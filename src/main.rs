use regex::Regex;
use serde::{Deserialize, Serialize};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::OnceLock;
use std::time::{SystemTime, UNIX_EPOCH};

const TMUX_SEP: &str = "\x1f";
const STATES: [&str; 5] = ["blocked", "working", "done", "idle", "unknown"];
const SPINNER_FRAMES: [&str; 10] = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"];
const ON_VALUES: [&str; 6] = ["1", "on", "true", "yes", "y", "enabled"];

const AGENT_ALIASES: &[(&str, &[&str])] = &[
    ("pi", &["pi", "pi-coding-agent"]),
    (
        "claude",
        &[
            "claude",
            "claude-code",
            "claude_code",
            "@anthropic-ai/claude-code",
        ],
    ),
    ("codex", &["codex", "openai-codex", "@openai/codex"]),
    ("gemini", &["gemini", "gemini-cli", "@google/gemini-cli"]),
    ("opencode", &["opencode", "opencode-ai"]),
    ("cursor-agent", &["cursor-agent", "cursoragent"]),
    ("copilot", &["copilot", "ghcs", "github-copilot"]),
    ("amp", &["amp"]),
    ("droid", &["droid"]),
    ("grok", &["grok"]),
    ("kimi", &["kimi"]),
    ("kiro", &["kiro"]),
    ("kilo", &["kilo"]),
    ("qodercli", &["qodercli", "qoder"]),
    ("hermes", &["hermes"]),
];

const RUNTIME_WRAPPERS: &[&str] = &[
    "node", "nodejs", "npx", "npm", "pnpm", "pnpx", "yarn", "bun", "bunx", "deno", "python",
    "python3", "pipx", "uv", "uvx", "bash", "sh", "zsh", "fish", "env",
];

const SHELL_NAMES: &[&str] = &[
    "bash", "sh", "zsh", "fish", "ksh", "dash", "tcsh", "csh", "login",
];

#[derive(Clone, Debug)]
struct ProcessInfo {
    pid: i32,
    ppid: i32,
    pgid: i32,
    stat: String,
    args: String,
    depth: i32,
}

impl ProcessInfo {
    fn command(&self) -> String {
        command_tokens(Some(&self.args), None)
            .first()
            .map(|token| normalize_token(token))
            .unwrap_or_default()
    }
}

#[derive(Clone, Debug, Default)]
struct PaneRaw {
    session_id: String,
    session_name: String,
    window_id: String,
    window_index: String,
    window_name: String,
    pane_id: String,
    pane_index: String,
    pane_active: bool,
    window_active: bool,
    pane_current_command: String,
    pane_title: String,
    pane_current_path: String,
    pane_pid: String,
    pane_width: String,
    pane_height: String,
}

impl PaneRaw {
    fn is_active(&self) -> bool {
        self.pane_active && self.window_active
    }

    fn target(&self) -> String {
        format!(
            "{}:{}.{}",
            self.session_name, self.window_index, self.pane_index
        )
    }
}

#[derive(Clone, Debug, Serialize, Deserialize, Default)]
struct ExplicitReport {
    #[serde(default)]
    pane: String,
    #[serde(default)]
    updated_at: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    agent: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    state: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    ttl: Option<i64>,
}

#[derive(Clone, Debug, Serialize, Deserialize, Default)]
struct StateRecord {
    #[serde(default)]
    state: String,
    #[serde(default)]
    raw_state: String,
    #[serde(default)]
    reason: String,
    #[serde(default)]
    hash: String,
    #[serde(default)]
    changed: bool,
    #[serde(default)]
    updated_at: f64,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    agent_label: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    target: Option<String>,
}

#[derive(Clone, Debug)]
struct DetectionResult {
    state: String,
    raw_state: String,
    reason: String,
    changed: bool,
    content_hash: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct SessionInfo {
    id: String,
    name: String,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct WindowInfo {
    id: String,
    index: String,
    name: String,
    active: bool,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct PaneInfo {
    id: String,
    index: String,
    active: bool,
    title: String,
    current_command: String,
    current_path: String,
    pid: String,
    width: i64,
    height: i64,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct ProcessOut {
    foreground_command: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    foreground_pid: Option<i32>,
    #[serde(skip_serializing_if = "Option::is_none")]
    foreground_pgid: Option<i32>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct AgentItem {
    agent: String,
    status: String,
    state: String,
    state_reason: String,
    raw_state: String,
    name: String,
    target: String,
    session: SessionInfo,
    window: WindowInfo,
    pane: PaneInfo,
    process: ProcessOut,
    #[serde(skip_serializing_if = "Option::is_none")]
    report: Option<ExplicitReport>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct AgentPayload {
    generated_at: f64,
    scope: String,
    counts: BTreeMap<String, usize>,
    agents: Vec<AgentItem>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct NotificationPayload {
    events: Vec<NotificationEvent>,
}

#[derive(Clone, Debug, Serialize, Deserialize)]
struct NotificationEvent {
    kind: String,
    title: String,
    body: String,
    agent: String,
    previous_status: String,
    status: String,
    target: String,
    session: SessionInfo,
    window: WindowInfo,
    pane: PaneInfo,
    generated_at: f64,
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let code = if args.is_empty() {
        run_agents(&[])
    } else {
        match args[0].as_str() {
            "agents" | "status" => run_agents(&args[1..]),
            "notify" => run_notify(&args[1..]),
            "report" => run_report(&args[1..]),
            "help" | "--help" | "-h" => {
                print_help();
                0
            }
            // Compatibility: let the binary be used directly like agents.sh.
            _ => run_agents(&args),
        }
    };
    std::process::exit(code);
}

fn print_help() {
    println!("tmux-agent-plugin");
    println!("usage:");
    println!("  tmux-agent-plugin agents [json|tsv|count|spinner|summary|compact|refresh] [name] [--refresh]");
    println!("  tmux-agent-plugin notify [json|tmux|system|both]");
    println!("  tmux-agent-plugin report [--pane PANE] [--agent NAME] [--state STATE] [--label TEXT] [--ttl N] [--clear]");
}

fn run_agents(args: &[String]) -> i32 {
    let mut command: Option<String> = None;
    let mut name: Option<String> = None;
    let mut refresh = false;
    let mut owner: Option<String> = None;
    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--refresh" => refresh = true,
            "--owner" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("tmux-agent-plugin: --owner requires a target");
                    return 2;
                }
                owner = Some(args[i].clone());
            }
            value if command.is_none() => command = Some(value.to_string()),
            value if name.is_none() => name = Some(value.to_string()),
            other => {
                eprintln!("tmux-agent-plugin: unexpected argument: {other}");
                return 2;
            }
        }
        i += 1;
    }

    let command = command.unwrap_or_else(|| "json".to_string());
    let force = refresh || command == "refresh";
    let payload = match build_payload(force, owner.as_deref()) {
        Ok(payload) => payload,
        Err(err) => {
            eprintln!("tmux-agent-plugin: {err}");
            return 1;
        }
    };

    match command.as_str() {
        "json" => print_json(&payload),
        "tsv" => print_tsv(&payload),
        "count" => {
            let key = name.unwrap_or_else(|| "all".to_string());
            println!("{}", payload.counts.get(&key).copied().unwrap_or(0));
        }
        "spinner" => println!("{}", spinner(&payload.counts)),
        "summary" => println!("{}", summary(&payload.counts)),
        "compact" => println!("{}", compact(&payload.counts)),
        "refresh" => {}
        other => {
            eprintln!("tmux-agent-plugin: unknown agents command: {other}");
            return 2;
        }
    }
    0
}

fn run_notify(args: &[String]) -> i32 {
    let command = args.first().map(|s| s.as_str()).unwrap_or("json");
    if !matches!(command, "json" | "tmux" | "system" | "both") {
        eprintln!("tmux-agent-plugin: unknown notify command: {command}");
        return 2;
    }

    let events = match collect_events() {
        Ok(events) => events,
        Err(err) => {
            eprintln!("tmux-agent-plugin: {err}");
            return 1;
        }
    };

    if command == "json" {
        print_json(&NotificationPayload { events });
        return 0;
    }

    for event in &events {
        if command == "tmux" || command == "both" {
            tmux_notify(event);
        }
        if command == "system" || command == "both" {
            let _ = system_notify(event);
        }
    }
    0
}

fn run_report(args: &[String]) -> i32 {
    let mut pane: Option<String> = None;
    let mut agent: Option<String> = None;
    let mut state: Option<String> = None;
    let mut label: Option<String> = None;
    let mut ttl: Option<i64> = None;
    let mut clear = false;
    let mut quiet = false;

    let mut i = 0;
    while i < args.len() {
        match args[i].as_str() {
            "--pane" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("tmux-agent-plugin: --pane requires a pane id");
                    return 2;
                }
                pane = Some(args[i].clone());
            }
            "--agent" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("tmux-agent-plugin: --agent requires a value");
                    return 2;
                }
                agent = Some(args[i].clone());
            }
            "--state" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("tmux-agent-plugin: --state requires a value");
                    return 2;
                }
                let value = args[i].clone();
                if !STATES.contains(&value.as_str()) {
                    eprintln!("tmux-agent-plugin: invalid state: {value}");
                    return 2;
                }
                state = Some(value);
            }
            "--label" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("tmux-agent-plugin: --label requires a value");
                    return 2;
                }
                label = Some(args[i].clone());
            }
            "--ttl" => {
                i += 1;
                if i >= args.len() {
                    eprintln!("tmux-agent-plugin: --ttl requires seconds");
                    return 2;
                }
                match args[i].parse::<i64>() {
                    Ok(value) => ttl = Some(value),
                    Err(_) => {
                        eprintln!("tmux-agent-plugin: invalid ttl: {}", args[i]);
                        return 2;
                    }
                }
            }
            "--clear" => clear = true,
            "--quiet" => quiet = true,
            "--help" | "-h" => {
                println!("usage: report [--pane PANE] [--agent NAME] [--state STATE] [--label TEXT] [--ttl N] [--clear] [--quiet]");
                return 0;
            }
            other => {
                eprintln!("tmux-agent-plugin: unexpected report argument: {other}");
                return 2;
            }
        }
        i += 1;
    }

    let pane_id = pane.unwrap_or_else(current_pane);
    if pane_id.is_empty() {
        eprintln!("tmux-agent-plugin: unable to determine pane id");
        return 2;
    }

    if clear {
        let removed = fs::remove_file(report_path(&pane_id)).is_ok();
        if !quiet {
            let message = if removed { "cleared" } else { "no" };
            let _ = run_tmux(&[
                "display-message",
                &format!("tmux-agent-plugin: {message} report for {pane_id}"),
            ]);
        }
        return 0;
    }

    if agent.is_none() && state.is_none() && label.is_none() {
        eprintln!(
            "tmux-agent-plugin: at least one of --agent, --state, --label, or --clear is required"
        );
        return 2;
    }

    let report = ExplicitReport {
        pane: pane_id.clone(),
        updated_at: now_secs(),
        agent,
        state,
        label,
        ttl,
    };

    if let Err(err) = write_report(&pane_id, &report) {
        eprintln!("tmux-agent-plugin: {err}");
        return 1;
    }

    if !quiet {
        let mut pieces = vec![pane_id.clone()];
        if let Some(agent) = &report.agent {
            pieces.push(agent.clone());
        }
        if let Some(state) = &report.state {
            pieces.push(state.clone());
        }
        if let Some(label) = &report.label {
            pieces.push(label.clone());
        }
        let _ = run_tmux(&[
            "display-message",
            &format!("tmux-agent-plugin: reported {}", pieces.join(" · ")),
        ]);
    }
    0
}

fn build_payload(force_refresh: bool, owner: Option<&str>) -> Result<AgentPayload, String> {
    if !force_refresh {
        if let Some(payload) = load_cached_payload() {
            return Ok(payload);
        }
    }
    collect_payload(owner, true)
}

fn load_cached_payload() -> Option<AgentPayload> {
    let ttl = cache_ttl();
    if ttl <= 0.0 {
        return None;
    }
    let path = state_output_file();
    let metadata = fs::metadata(&path).ok()?;
    let modified = metadata.modified().ok()?;
    let age = modified.elapsed().ok()?.as_secs_f64();
    if age > ttl {
        return None;
    }
    let content = fs::read_to_string(path).ok()?;
    serde_json::from_str(&content).ok()
}

fn collect_payload(owner: Option<&str>, write_cache: bool) -> Result<AgentPayload, String> {
    let now = now_secs();
    let scope = option_value("@agent-status-scope", "all", Some("@agent-sidebar-scope"));
    let include_non_agents = option_bool(
        "@agent-status-include-non-agents",
        "off",
        Some("@agent-sidebar-include-non-agents"),
    );
    let process_detection = option_bool(
        "@agent-status-process-detection",
        "on",
        Some("@agent-sidebar-process-detection"),
    );
    let output_detection = option_bool(
        "@agent-status-output-detection",
        "on",
        Some("@agent-sidebar-output-detection"),
    );
    let capture_lines = option_i64(
        "@agent-status-capture-lines",
        80,
        Some("@agent-sidebar-capture-lines"),
    );
    let report_ttl = option_i64(
        "@agent-status-report-ttl",
        30,
        Some("@agent-sidebar-report-ttl"),
    );

    let panes = filter_by_scope(list_panes(), &scope, owner);
    let processes = if process_detection {
        parse_processes()
    } else {
        HashMap::new()
    };
    let previous_state = load_pane_state();
    let mut next_state: HashMap<String, StateRecord> = HashMap::new();
    let mut items: Vec<AgentItem> = Vec::new();

    for pane in panes {
        let foreground = if process_detection {
            foreground_process(&pane.pane_pid, &pane.pane_current_command, &processes)
        } else {
            None
        };
        let (foreground_command, foreground_pid, foreground_pgid) =
            if let Some(proc_info) = foreground {
                (proc_info.args, Some(proc_info.pid), Some(proc_info.pgid))
            } else {
                (pane.pane_current_command.clone(), None, None)
            };

        let mut agent_label =
            detect_agent(Some(&foreground_command), Some(&pane.pane_current_command));
        let report = load_report(&pane.pane_id, report_ttl, now);
        if let Some(report) = &report {
            if report.agent.as_deref().unwrap_or("").is_empty() == false {
                agent_label = report.agent.clone();
            }
        }

        if agent_label.is_none() && !include_non_agents && report.is_none() {
            continue;
        }

        let previous = previous_state
            .get(&pane.pane_id)
            .cloned()
            .unwrap_or_default();
        let (state, raw_state, reason, record) = if let Some(report) = &report {
            if let Some(report_state) = &report.state {
                let record = StateRecord {
                    state: report_state.clone(),
                    raw_state: report_state.clone(),
                    reason: "explicit-report".to_string(),
                    hash: previous.hash.clone(),
                    changed: false,
                    updated_at: now,
                    agent_label: None,
                    target: None,
                };
                (
                    report_state.clone(),
                    report_state.clone(),
                    "explicit-report".to_string(),
                    record,
                )
            } else if output_detection {
                classify_for_pane(&pane, capture_lines, agent_label.as_deref(), &previous, now)
            } else {
                default_detection_record(agent_label.as_deref(), &previous, now)
            }
        } else if output_detection {
            classify_for_pane(&pane, capture_lines, agent_label.as_deref(), &previous, now)
        } else {
            default_detection_record(agent_label.as_deref(), &previous, now)
        };

        let mut record = record;
        record.agent_label = agent_label.clone();
        record.target = Some(pane.target());
        next_state.insert(pane.pane_id.clone(), record);

        let item = normalize_agent(
            &pane,
            agent_label.as_deref().unwrap_or("unknown"),
            &state,
            &raw_state,
            &reason,
            &foreground_command,
            foreground_pid,
            foreground_pgid,
            report,
        );
        items.push(item);
    }

    items.sort_by(agent_sort);
    let counts = counts(&items);
    let payload = AgentPayload {
        generated_at: now,
        scope,
        counts,
        agents: items,
    };

    fs::create_dir_all(cache_dir()).map_err(|err| format!("unable to create cache dir: {err}"))?;
    save_pane_state(&next_state)?;
    if write_cache {
        atomic_write_json(&state_output_file(), &payload)?;
    }
    Ok(payload)
}

fn classify_for_pane(
    pane: &PaneRaw,
    capture_lines: i64,
    agent_label: Option<&str>,
    previous: &StateRecord,
    now: f64,
) -> (String, String, String, StateRecord) {
    let captured = capture_pane(&pane.pane_id, capture_lines);
    let result = classify_screen(&captured, agent_label, pane.is_active(), previous, now);
    let record = StateRecord {
        state: result.state.clone(),
        raw_state: result.raw_state.clone(),
        reason: result.reason.clone(),
        hash: result.content_hash,
        changed: result.changed,
        updated_at: now,
        agent_label: None,
        target: None,
    };
    (result.state, result.raw_state, result.reason, record)
}

fn default_detection_record(
    agent_label: Option<&str>,
    previous: &StateRecord,
    now: f64,
) -> (String, String, String, StateRecord) {
    let state = if agent_label.is_some() {
        "idle"
    } else {
        "unknown"
    }
    .to_string();
    let record = StateRecord {
        state: state.clone(),
        raw_state: state.clone(),
        reason: "output-detection-disabled".to_string(),
        hash: previous.hash.clone(),
        changed: false,
        updated_at: now,
        agent_label: None,
        target: None,
    };
    (
        state.clone(),
        state,
        "output-detection-disabled".to_string(),
        record,
    )
}

#[allow(clippy::too_many_arguments)]
fn normalize_agent(
    pane: &PaneRaw,
    agent_label: &str,
    state: &str,
    raw_state: &str,
    reason: &str,
    foreground_command: &str,
    foreground_pid: Option<i32>,
    foreground_pgid: Option<i32>,
    report: Option<ExplicitReport>,
) -> AgentItem {
    let target = pane.target();
    let name = display_name(pane, report.as_ref(), &target);
    AgentItem {
        agent: agent_label.to_string(),
        status: state.to_string(),
        state: state.to_string(),
        state_reason: reason.to_string(),
        raw_state: raw_state.to_string(),
        name,
        target,
        session: SessionInfo {
            id: pane.session_id.clone(),
            name: pane.session_name.clone(),
        },
        window: WindowInfo {
            id: pane.window_id.clone(),
            index: pane.window_index.clone(),
            name: pane.window_name.clone(),
            active: pane.window_active,
        },
        pane: PaneInfo {
            id: pane.pane_id.clone(),
            index: pane.pane_index.clone(),
            active: pane.pane_active,
            title: pane.pane_title.clone(),
            current_command: pane.pane_current_command.clone(),
            current_path: pane.pane_current_path.clone(),
            pid: pane.pane_pid.clone(),
            width: parse_i64(&pane.pane_width, 0),
            height: parse_i64(&pane.pane_height, 0),
        },
        process: ProcessOut {
            foreground_command: foreground_command.to_string(),
            foreground_pid,
            foreground_pgid,
        },
        report,
    }
}

fn display_name(pane: &PaneRaw, report: Option<&ExplicitReport>, target: &str) -> String {
    if let Some(label) = report.and_then(|r| r.label.as_ref()) {
        if !label.trim().is_empty() {
            return label.clone();
        }
    }
    let title = pane.pane_title.trim();
    if is_useful_pane_title(title) {
        return title.to_string();
    }
    let path = pane.pane_current_path.trim();
    if !path.is_empty() {
        if let Some(name) = Path::new(path).file_name().and_then(|name| name.to_str()) {
            if !name.is_empty() {
                return name.to_string();
            }
        }
        return path.to_string();
    }
    target.to_string()
}

fn is_useful_pane_title(title: &str) -> bool {
    let title = title.trim();
    if title.is_empty() || title.ends_with(".local") {
        return false;
    }

    // Some terminal programs can leak capability/escape-response fragments into
    // tmux's pane title, e.g. "Ga=d,d=I,i=9000,q=2". Those are not human labels.
    let has_whitespace = title.chars().any(char::is_whitespace);
    let equals_count = title.matches('=').count();
    let comma_count = title.matches(',').count();
    if !has_whitespace && equals_count > 0 && comma_count > 0 {
        return false;
    }

    true
}

fn counts(items: &[AgentItem]) -> BTreeMap<String, usize> {
    let mut result = BTreeMap::new();
    for state in STATES {
        result.insert(state.to_string(), 0);
    }
    result.insert("all".to_string(), items.len());
    result.insert("opened".to_string(), items.len());
    for item in items {
        let key = if STATES.contains(&item.status.as_str()) {
            item.status.as_str()
        } else {
            "unknown"
        };
        *result.entry(key.to_string()).or_insert(0) += 1;
    }
    let active =
        result.get("blocked").copied().unwrap_or(0) + result.get("working").copied().unwrap_or(0);
    let attention =
        result.get("blocked").copied().unwrap_or(0) + result.get("done").copied().unwrap_or(0);
    result.insert("active".to_string(), active);
    result.insert("attention".to_string(), attention);
    result
}

fn spinner(counts: &BTreeMap<String, usize>) -> String {
    if counts.get("working").copied().unwrap_or(0) == 0 {
        return String::new();
    }
    let frame = ((now_secs() * 5.0) as usize) % SPINNER_FRAMES.len();
    SPINNER_FRAMES[frame].to_string()
}

fn summary(counts: &BTreeMap<String, usize>) -> String {
    let all = counts.get("all").copied().unwrap_or(0);
    if all == 0 {
        return "agents 0".to_string();
    }
    let mut parts = vec![format!("agents {all}")];
    let working = counts.get("working").copied().unwrap_or(0);
    if working > 0 {
        parts.push(format!("{} {working} working", spinner(counts)));
    }
    let blocked = counts.get("blocked").copied().unwrap_or(0);
    if blocked > 0 {
        parts.push(format!("⚠ {blocked} blocked"));
    }
    let done = counts.get("done").copied().unwrap_or(0);
    if done > 0 {
        parts.push(format!("✓ {done} done"));
    }
    parts.join(" · ")
}

fn compact(counts: &BTreeMap<String, usize>) -> String {
    let all = counts.get("all").copied().unwrap_or(0);
    if all == 0 {
        return "󰚩0".to_string();
    }
    let mut parts = vec![format!("󰚩{all}")];
    let working = counts.get("working").copied().unwrap_or(0);
    if working > 0 {
        parts.push(format!("{}{working}", spinner(counts)));
    }
    let blocked = counts.get("blocked").copied().unwrap_or(0);
    if blocked > 0 {
        parts.push(format!("⚠{blocked}"));
    }
    let done = counts.get("done").copied().unwrap_or(0);
    if done > 0 {
        parts.push(format!("✓{done}"));
    }
    parts.join(" ")
}

fn print_tsv(payload: &AgentPayload) {
    let columns = [
        "status",
        "agent",
        "target",
        "name",
        "session",
        "window",
        "pane",
        "cwd",
        "pane_id",
        "window_id",
        "session_id",
    ];
    println!("{}", columns.join("\t"));
    for item in &payload.agents {
        let values = [
            item.status.as_str(),
            item.agent.as_str(),
            item.target.as_str(),
            item.name.as_str(),
            item.session.name.as_str(),
            item.window.index.as_str(),
            item.pane.index.as_str(),
            item.pane.current_path.as_str(),
            item.pane.id.as_str(),
            item.window.id.as_str(),
            item.session.id.as_str(),
        ];
        println!("{}", values.map(clean_tsv).join("\t"));
    }
}

fn clean_tsv(value: &str) -> String {
    value.replace('\t', " ").replace('\n', " ")
}

fn agent_sort(a: &AgentItem, b: &AgentItem) -> std::cmp::Ordering {
    let ka = (
        state_rank(&a.status),
        a.session.name.to_lowercase(),
        parse_i64(&a.window.index, 999),
        parse_i64(&a.pane.index, 999),
        a.pane.id.clone(),
    );
    let kb = (
        state_rank(&b.status),
        b.session.name.to_lowercase(),
        parse_i64(&b.window.index, 999),
        parse_i64(&b.pane.index, 999),
        b.pane.id.clone(),
    );
    ka.cmp(&kb)
}

fn state_rank(state: &str) -> i32 {
    match state {
        "blocked" => 0,
        "working" => 1,
        "done" => 2,
        "idle" => 3,
        "unknown" => 4,
        _ => 9,
    }
}

fn collect_events() -> Result<Vec<NotificationEvent>, String> {
    let previous = load_pane_state();
    let payload = collect_payload(None, true)?;
    let include_active = option_bool("@agent-status-notify-active", "off", None);
    let mut events = Vec::new();
    for item in &payload.agents {
        if let Some(event) = event_for_transition(previous.get(&item.pane.id), item, include_active)
        {
            events.push(event);
        }
    }
    Ok(events)
}

fn event_for_transition(
    previous: Option<&StateRecord>,
    item: &AgentItem,
    include_active: bool,
) -> Option<NotificationEvent> {
    if !include_active && item.pane.active && item.window.active {
        return None;
    }

    let old_state = previous
        .map(|p| p.state.as_str())
        .filter(|s| !s.is_empty())
        .unwrap_or("unknown");
    let old_agent = previous.and_then(|p| p.agent_label.as_deref());
    let new_state = item.status.as_str();
    let new_agent = item.agent.as_str();

    if old_state == new_state && old_agent == Some(new_agent) {
        return None;
    }

    let (kind, title) = if new_state == "blocked" {
        ("needs_attention", format!("{new_agent} needs attention"))
    } else if matches!(old_state, "working" | "blocked")
        && matches!(new_state, "done" | "idle")
        && old_agent.map(|agent| agent == new_agent).unwrap_or(true)
    {
        ("finished", format!("{new_agent} finished"))
    } else {
        return None;
    };

    Some(NotificationEvent {
        kind: kind.to_string(),
        title,
        body: event_context(item),
        agent: new_agent.to_string(),
        previous_status: old_state.to_string(),
        status: new_state.to_string(),
        target: item.target.clone(),
        session: item.session.clone(),
        window: item.window.clone(),
        pane: item.pane.clone(),
        generated_at: now_secs(),
    })
}

fn event_context(item: &AgentItem) -> String {
    format!(
        "{}:{}.{} · {}",
        item.session.name, item.window.index, item.pane.index, item.name
    )
}

fn tmux_notify(event: &NotificationEvent) {
    let _ = run_tmux(&[
        "display-message",
        &format!("{}: {}", event.title, event.body),
    ]);
}

fn system_notify(event: &NotificationEvent) -> bool {
    let title = event.title.as_str();
    let body = event.body.as_str();
    match env::consts::OS {
        "macos" => {
            if command_exists("terminal-notifier") {
                return Command::new("terminal-notifier")
                    .args(["-title", title, "-message", body])
                    .stdin(Stdio::null())
                    .stdout(Stdio::null())
                    .stderr(Stdio::null())
                    .status()
                    .map(|status| status.success())
                    .unwrap_or(false);
            }
            Command::new("osascript")
                .args([
                    "-e",
                    "on run argv",
                    "-e",
                    "display notification (item 2 of argv) with title (item 1 of argv)",
                    "-e",
                    "end run",
                    title,
                    body,
                ])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|status| status.success())
                .unwrap_or(false)
        }
        "linux" => {
            if !command_exists("notify-send") {
                return false;
            }
            Command::new("notify-send")
                .args(["--", title, body])
                .stdin(Stdio::null())
                .stdout(Stdio::null())
                .stderr(Stdio::null())
                .status()
                .map(|status| status.success())
                .unwrap_or(false)
        }
        _ => false,
    }
}

fn command_exists(program: &str) -> bool {
    Command::new("sh")
        .arg("-c")
        .arg(format!("command -v {program} >/dev/null 2>&1"))
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn list_panes() -> Vec<PaneRaw> {
    let fields = [
        "#{session_id}",
        "#{session_name}",
        "#{window_id}",
        "#{window_index}",
        "#{window_name}",
        "#{pane_id}",
        "#{pane_index}",
        "#{pane_active}",
        "#{window_active}",
        "#{pane_current_command}",
        "#{pane_title}",
        "#{pane_current_path}",
        "#{pane_pid}",
        "#{pane_width}",
        "#{pane_height}",
    ];
    let format = fields.join(TMUX_SEP);
    let output = run_tmux(&["list-panes", "-a", "-F", &format]);
    let mut panes = Vec::new();
    for line in output.lines() {
        let parts: Vec<&str> = line.split(TMUX_SEP).collect();
        if parts.len() != fields.len() {
            continue;
        }
        panes.push(PaneRaw {
            session_id: parts[0].to_string(),
            session_name: parts[1].to_string(),
            window_id: parts[2].to_string(),
            window_index: parts[3].to_string(),
            window_name: parts[4].to_string(),
            pane_id: parts[5].to_string(),
            pane_index: parts[6].to_string(),
            pane_active: parse_bool_flag(parts[7]),
            window_active: parse_bool_flag(parts[8]),
            pane_current_command: parts[9].to_string(),
            pane_title: parts[10].to_string(),
            pane_current_path: parts[11].to_string(),
            pane_pid: parts[12].to_string(),
            pane_width: parts[13].to_string(),
            pane_height: parts[14].to_string(),
        });
    }
    panes
}

fn filter_by_scope(panes: Vec<PaneRaw>, scope: &str, owner: Option<&str>) -> Vec<PaneRaw> {
    if scope == "all" {
        return panes;
    }
    let (session_id, window_id) = owner_scope(owner);
    if scope == "current-window" {
        panes
            .into_iter()
            .filter(|pane| pane.window_id == window_id)
            .collect()
    } else {
        panes
            .into_iter()
            .filter(|pane| pane.session_id == session_id)
            .collect()
    }
}

fn owner_scope(owner: Option<&str>) -> (String, String) {
    if let Some(owner) = owner {
        let session_id = run_tmux(&["display-message", "-p", "-t", owner, "#{session_id}"])
            .trim()
            .to_string();
        let window_id = run_tmux(&["display-message", "-p", "-t", owner, "#{window_id}"])
            .trim()
            .to_string();
        if !session_id.is_empty() || !window_id.is_empty() {
            return (session_id, window_id);
        }
    }
    let session_id = run_tmux(&["display-message", "-p", "#{session_id}"])
        .trim()
        .to_string();
    let window_id = run_tmux(&["display-message", "-p", "#{window_id}"])
        .trim()
        .to_string();
    (session_id, window_id)
}

fn parse_processes() -> HashMap<i32, ProcessInfo> {
    let commands: &[&[&str]] = &[
        &["-axo", "pid=,ppid=,pgid=,stat=,args="],
        &["-eo", "pid=,ppid=,pgid=,stat=,args="],
    ];
    let mut output = String::new();
    for args in commands {
        match Command::new("ps").args(*args).output() {
            Ok(proc_output) if proc_output.status.success() && !proc_output.stdout.is_empty() => {
                output = String::from_utf8_lossy(&proc_output.stdout).into_owned();
                break;
            }
            _ => {}
        }
    }

    let mut processes = HashMap::new();
    for line in output.lines() {
        let mut parts = line.split_whitespace();
        let Some(pid_text) = parts.next() else {
            continue;
        };
        let Some(ppid_text) = parts.next() else {
            continue;
        };
        let Some(pgid_text) = parts.next() else {
            continue;
        };
        let Some(stat) = parts.next() else { continue };
        let args = parts.collect::<Vec<&str>>().join(" ");
        if args.is_empty() {
            continue;
        }
        let Ok(pid) = pid_text.parse::<i32>() else {
            continue;
        };
        let Ok(ppid) = ppid_text.parse::<i32>() else {
            continue;
        };
        let Ok(pgid) = pgid_text.parse::<i32>() else {
            continue;
        };
        processes.insert(
            pid,
            ProcessInfo {
                pid,
                ppid,
                pgid,
                stat: stat.to_string(),
                args,
                depth: 0,
            },
        );
    }
    processes
}

fn descendants(root_pid: i32, processes: &HashMap<i32, ProcessInfo>) -> Vec<ProcessInfo> {
    let mut children: HashMap<i32, Vec<ProcessInfo>> = HashMap::new();
    for proc_info in processes.values() {
        children
            .entry(proc_info.ppid)
            .or_default()
            .push(proc_info.clone());
    }

    let mut result = Vec::new();
    let mut stack: Vec<(ProcessInfo, i32)> = children
        .get(&root_pid)
        .map(|kids| kids.iter().cloned().map(|child| (child, 1)).collect())
        .unwrap_or_default();
    let mut seen = HashSet::new();
    while let Some((mut proc_info, depth)) = stack.pop() {
        if !seen.insert(proc_info.pid) {
            continue;
        }
        proc_info.depth = depth;
        result.push(proc_info.clone());
        if let Some(kids) = children.get(&proc_info.pid) {
            for child in kids {
                stack.push((child.clone(), depth + 1));
            }
        }
    }
    result
}

fn foreground_process(
    root_pid: &str,
    fallback_command: &str,
    processes: &HashMap<i32, ProcessInfo>,
) -> Option<ProcessInfo> {
    let root = root_pid.parse::<i32>().unwrap_or(-1);
    let mut candidates = descendants(root, processes);
    if let Some(root_proc) = processes.get(&root) {
        let mut root_proc = root_proc.clone();
        root_proc.depth = 0;
        candidates.push(root_proc);
    }
    candidates
        .into_iter()
        .max_by_key(|proc_info| process_score(proc_info, fallback_command))
}

fn process_score(proc_info: &ProcessInfo, fallback_command: &str) -> i32 {
    let mut score = proc_info.depth * 10;
    let command = proc_info.command();
    if proc_info.stat.contains('+') {
        score += 100;
    }
    if detect_agent(Some(&proc_info.args), Some(fallback_command)).is_some() {
        score += 1000;
    }
    if SHELL_NAMES.contains(&command.as_str()) {
        score -= 100;
    }
    if RUNTIME_WRAPPERS.contains(&command.as_str()) {
        score += 5;
    }
    score
}

fn capture_pane(pane_id: &str, lines: i64) -> String {
    let lines = lines.max(1);
    run_tmux(&[
        "capture-pane",
        "-t",
        pane_id,
        "-p",
        "-J",
        "-S",
        &format!("-{lines}"),
    ])
}

fn detect_agent(argv: Option<&str>, fallback_command: Option<&str>) -> Option<String> {
    let tokens = command_tokens(argv, fallback_command);
    let normalized: Vec<String> = tokens
        .iter()
        .map(|token| normalize_token(token))
        .filter(|token| !token.is_empty())
        .collect();
    if normalized.is_empty() {
        return None;
    }

    for pair in normalized.windows(2) {
        if pair[0] == "gh" && pair[1] == "copilot" {
            return Some("copilot".to_string());
        }
    }

    for token in &normalized {
        if let Some(agent) = alias_to_agent(token) {
            return Some(agent.to_string());
        }
    }

    let lowered_command = tokens.join(" ").to_lowercase();
    let substring_markers = [
        ("pi", "pi-coding-agent"),
        ("claude", "claude-code"),
        ("claude", "@anthropic-ai/claude-code"),
        ("codex", "@openai/codex"),
        ("gemini", "@google/gemini-cli"),
        ("opencode", "opencode"),
        ("cursor-agent", "cursor-agent"),
    ];
    for (label, marker) in substring_markers {
        if lowered_command.contains(marker) {
            return Some(label.to_string());
        }
    }

    None
}

fn alias_to_agent(token: &str) -> Option<&'static str> {
    for (label, aliases) in AGENT_ALIASES {
        if aliases.contains(&token) {
            return Some(label);
        }
    }
    None
}

fn command_tokens(argv: Option<&str>, fallback_command: Option<&str>) -> Vec<String> {
    let mut tokens = Vec::new();
    if let Some(argv) = argv {
        tokens.extend(split_command(argv));
    }
    if let Some(fallback) = fallback_command {
        tokens.extend(split_command(fallback));
    }
    tokens
}

fn split_command(command: &str) -> Vec<String> {
    let mut tokens = Vec::new();
    let mut current = String::new();
    let mut quote: Option<char> = None;
    let mut escaped = false;

    for ch in command.chars() {
        if escaped {
            current.push(ch);
            escaped = false;
            continue;
        }
        if ch == '\\' && quote != Some('\'') {
            escaped = true;
            continue;
        }
        if ch == '\'' || ch == '"' {
            if quote == Some(ch) {
                quote = None;
            } else if quote.is_none() {
                quote = Some(ch);
            } else {
                current.push(ch);
            }
            continue;
        }
        if ch.is_whitespace() && quote.is_none() {
            if !current.is_empty() {
                tokens.push(current.clone());
                current.clear();
            }
        } else {
            current.push(ch);
        }
    }
    if !current.is_empty() {
        tokens.push(current);
    }
    tokens
}

fn normalize_token(token: &str) -> String {
    let token = token.trim().trim_matches(['\'', '"']);
    if token.is_empty() {
        return String::new();
    }
    let lowered = token.to_lowercase();
    if lowered.starts_with('@') && lowered.contains('/') {
        return lowered;
    }
    let mut base = lowered
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or(lowered.as_str())
        .to_string();
    for suffix in [".exe", ".cmd", ".bat", ".js", ".mjs", ".cjs", ".py"] {
        if base.ends_with(suffix) {
            base.truncate(base.len() - suffix.len());
            break;
        }
    }
    base
}

fn classify_screen(
    text: &str,
    agent_label: Option<&str>,
    is_active: bool,
    previous: &StateRecord,
    _now: f64,
) -> DetectionResult {
    let digest = screen_hash(text);
    let changed = !previous.hash.is_empty() && previous.hash != digest;
    let (raw_state, mut reason) = raw_state_from_text(text, changed, agent_label);
    let previous_state = if previous.state.is_empty() {
        "unknown"
    } else {
        previous.state.as_str()
    };
    let mut state = raw_state.clone();

    if raw_state == "idle" && matches!(previous_state, "working" | "blocked") && !is_active {
        state = "done".to_string();
        reason = format!("transition:{previous_state}->idle-unfocused");
    } else if raw_state == "idle" && is_active {
        state = "idle".to_string();
    } else if previous_state == "done" && !is_active && raw_state == "idle" {
        state = "done".to_string();
        reason = "previous-done-unacknowledged".to_string();
    }

    DetectionResult {
        state,
        raw_state,
        reason,
        changed,
        content_hash: digest,
    }
}

fn raw_state_from_text(text: &str, _changed: bool, agent_label: Option<&str>) -> (String, String) {
    let normalized = normalize_screen(text);
    if normalized.is_empty() {
        return ("unknown".to_string(), "empty-capture".to_string());
    }

    let recent = recent_screen(text, 14);
    let recent_lines: Vec<&str> = recent.lines().collect();
    let tail = recent_lines
        .iter()
        .rev()
        .take(6)
        .cloned()
        .collect::<Vec<&str>>()
        .into_iter()
        .rev()
        .collect::<Vec<&str>>()
        .join("\n");

    for pattern in blocked_patterns() {
        if pattern.is_match(&recent) {
            return (
                "blocked".to_string(),
                format!("blocked-pattern:{}", pattern.as_str()),
            );
        }
    }
    if let Some(agent) = agent_label {
        if agent_specific_match(&recent, agent, "blocked") {
            return (
                "blocked".to_string(),
                format!("agent-blocked-pattern:{agent}"),
            );
        }
    }
    for pattern in working_patterns() {
        if pattern.is_match(&recent) {
            return (
                "working".to_string(),
                format!("working-pattern:{}", pattern.as_str()),
            );
        }
    }
    if let Some(agent) = agent_label {
        if agent_specific_match(&recent, agent, "working") {
            return (
                "working".to_string(),
                format!("agent-working-pattern:{agent}"),
            );
        }
    }
    for pattern in idle_patterns() {
        if pattern.is_match(&tail) {
            return (
                "idle".to_string(),
                format!("idle-pattern:{}", pattern.as_str()),
            );
        }
    }
    if let Some(agent) = agent_label {
        if agent_specific_match(&tail, agent, "idle") {
            return ("idle".to_string(), format!("agent-idle-pattern:{agent}"));
        }
    }
    if agent_label.is_some() {
        return (
            "idle".to_string(),
            "known-agent-no-active-evidence".to_string(),
        );
    }
    ("unknown".to_string(), "no-agent-or-pattern".to_string())
}

fn agent_specific_match(text: &str, agent: &str, kind: &str) -> bool {
    let name = regex::escape(agent).replace("\\-", "[-_ ]?");
    let suffix = match kind {
        "blocked" => {
            r"(?i)\b(needs?|waiting for|requires?)\b[^\n]{0,80}\b(approval|permission|confirmation|input)\b"
        }
        "working" => r"(?i)\b(thinking|working|running|analyzing|analysing|generating)\b",
        "idle" => r"(?i)\b(ready|idle|waiting for (your )?(prompt|message|input))\b",
        _ => return false,
    };
    let pattern = format!(r"(?im)\b{name}\b[^\n]{{0,120}}{suffix}");
    Regex::new(&pattern)
        .map(|regex| regex.is_match(text))
        .unwrap_or(false)
}

fn blocked_patterns() -> &'static [Regex] {
    static PATTERNS: OnceLock<Vec<Regex>> = OnceLock::new();
    PATTERNS
        .get_or_init(|| {
            [
                r"(?im)\b(do you want to|would you like to)\b[^\n]{0,120}\b(continue|proceed|run|apply|approve|allow)\b",
                r"(?im)\b(approve|approval|permission|authorize|confirm|confirmation|required)\b[^\n]{0,120}\b(yes/no|y/n|enter|return|proceed|continue|allow)\b",
                r"(?im)\b(yes/no|y/n|\[y/N\]|\[Y/n\])\b",
                r"(?im)\bpress\s+(enter|return)\s+to\s+(continue|confirm|proceed|send)",
                r"(?im)\bwaiting\s+for\s+(approval|confirmation|input|permission)",
                r"(?im)\baction\s+required\b",
                r"(?im)\brequires?\s+your\s+(approval|confirmation|permission)",
                r"(?im)\benter\s+to\s+confirm\b",
            ]
            .into_iter()
            .map(|pattern| Regex::new(pattern).expect("valid blocked regex"))
            .collect()
        })
        .as_slice()
}

fn working_patterns() -> &'static [Regex] {
    static PATTERNS: OnceLock<Vec<Regex>> = OnceLock::new();
    PATTERNS
        .get_or_init(|| {
            [
                r"(?im)(^|\n)\s*[⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏◐◓◑◒⣾⣽⣻⢿⡿⣟⣯⣷]\s+\S+",
                r"(?im)(^|\n)\s*[|/\\-]\s+(thinking|working|running|analyzing|analysing|generating|searching|planning|editing|writing|reading|executing|compiling|processing|streaming)\b",
                r"(?im)\b(thinking|working|running|analyzing|analysing|generating|searching|planning|editing|writing|reading|executing|compiling)\b",
                r"(?im)\b(calling|using|running)\s+(tool|command)",
                r"(?im)\b(tool use|tool call|in progress|processing|streaming)\b",
            ]
            .into_iter()
            .map(|pattern| Regex::new(pattern).expect("valid working regex"))
            .collect()
        })
        .as_slice()
}

fn idle_patterns() -> &'static [Regex] {
    static PATTERNS: OnceLock<Vec<Regex>> = OnceLock::new();
    PATTERNS
        .get_or_init(|| {
            [
                r"(?im)\b(ready|idle|waiting for your message|what would you like|ask me anything)\b",
                r"(?im)\b(enter|type|send)\s+(your\s+)?(prompt|message|request)\b",
                r"(?im)(^|\n)\s*[╰└].*[>$] ?$",
                r"(?im)(^|\n).*\b(prompt|message|input)\b.*[>$❯]\s*$",
            ]
            .into_iter()
            .map(|pattern| Regex::new(pattern).expect("valid idle regex"))
            .collect()
        })
        .as_slice()
}

fn ansi_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| {
        Regex::new(r"\x1b(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~]|\][^\x07]*(?:\x07|\x1b\\))").unwrap()
    })
}

fn control_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]").unwrap())
}

fn whitespace_regex() -> &'static Regex {
    static REGEX: OnceLock<Regex> = OnceLock::new();
    REGEX.get_or_init(|| Regex::new(r"[ \t\r\f\v]+").unwrap())
}

fn strip_ansi(text: &str) -> String {
    let text = ansi_regex().replace_all(text, "");
    control_regex().replace_all(&text, "").into_owned()
}

fn normalize_screen(text: &str) -> String {
    let text = strip_ansi(text).replace('\r', "\n");
    text.lines()
        .map(|line| {
            whitespace_regex()
                .replace_all(line, " ")
                .trim_end()
                .to_string()
        })
        .collect::<Vec<String>>()
        .join("\n")
        .trim()
        .to_string()
}

fn recent_screen(text: &str, lines: usize) -> String {
    let normalized = normalize_screen(text);
    if normalized.is_empty() {
        return String::new();
    }
    let nonempty: Vec<&str> = normalized
        .lines()
        .filter(|line| !line.trim().is_empty())
        .collect();
    nonempty
        .iter()
        .skip(nonempty.len().saturating_sub(lines))
        .copied()
        .collect::<Vec<&str>>()
        .join("\n")
}

fn screen_hash(text: &str) -> String {
    stable_hash_hex(&normalize_screen(text))
}

fn stable_hash_hex(text: &str) -> String {
    // Stable, lightweight FNV-1a hash. It only needs to detect screen changes.
    let mut hash: u64 = 0xcbf29ce484222325;
    for byte in text.as_bytes() {
        hash ^= u64::from(*byte);
        hash = hash.wrapping_mul(0x100000001b3);
    }
    format!("{hash:016x}")
}

fn load_pane_state() -> HashMap<String, StateRecord> {
    let path = pane_state_file();
    let Ok(content) = fs::read_to_string(path) else {
        return HashMap::new();
    };
    serde_json::from_str(&content).unwrap_or_default()
}

fn save_pane_state(state: &HashMap<String, StateRecord>) -> Result<(), String> {
    atomic_write_json(&pane_state_file(), state)
}

fn load_report(pane_id: &str, default_ttl: i64, now: f64) -> Option<ExplicitReport> {
    let path = report_path(pane_id);
    let content = fs::read_to_string(path).ok()?;
    let report: ExplicitReport = serde_json::from_str(&content).ok()?;
    let ttl = report.ttl.unwrap_or(default_ttl);
    if ttl >= 0 && now - report.updated_at > ttl as f64 {
        return None;
    }
    Some(report)
}

fn write_report(pane_id: &str, report: &ExplicitReport) -> Result<(), String> {
    atomic_write_json(&report_path(pane_id), report)
}

fn current_pane() -> String {
    env::var("TMUX_PANE").unwrap_or_else(|_| {
        run_tmux(&["display-message", "-p", "#{pane_id}"])
            .trim()
            .to_string()
    })
}

fn sanitize_pane_id(pane_id: &str) -> String {
    pane_id.replace('%', "pct").replace('/', "_")
}

fn run_tmux(args: &[&str]) -> String {
    match Command::new("tmux").args(args).output() {
        Ok(output) => String::from_utf8_lossy(&output.stdout).into_owned(),
        Err(_) => String::new(),
    }
}

fn option_value(option: &str, default: &str, legacy: Option<&str>) -> String {
    let value = run_tmux(&["show-option", "-gqv", option])
        .trim_end()
        .to_string();
    if !value.is_empty() {
        return value;
    }
    if let Some(legacy) = legacy {
        let value = run_tmux(&["show-option", "-gqv", legacy])
            .trim_end()
            .to_string();
        if !value.is_empty() {
            return value;
        }
    }
    default.to_string()
}

fn option_bool(option: &str, default: &str, legacy: Option<&str>) -> bool {
    let value = option_value(option, default, legacy).trim().to_lowercase();
    ON_VALUES.contains(&value.as_str())
}

fn option_i64(option: &str, default: i64, legacy: Option<&str>) -> i64 {
    option_value(option, &default.to_string(), legacy)
        .trim()
        .parse()
        .unwrap_or(default)
}

fn cache_ttl() -> f64 {
    option_value(
        "@agent-status-cache-ttl",
        "2",
        Some("@agent-sidebar-refresh-interval"),
    )
    .trim()
    .parse::<f64>()
    .unwrap_or(2.0)
    .max(0.0)
}

fn cache_dir() -> PathBuf {
    let base = env::var_os("XDG_CACHE_HOME")
        .map(PathBuf::from)
        .or_else(|| env::var_os("HOME").map(|home| PathBuf::from(home).join(".cache")))
        .unwrap_or_else(|| PathBuf::from(".cache"));
    base.join("tmux-agent-plugin")
}

fn state_output_file() -> PathBuf {
    cache_dir().join("state.json")
}

fn pane_state_file() -> PathBuf {
    cache_dir().join("pane_state.json")
}

fn reports_dir() -> PathBuf {
    cache_dir().join("reports")
}

fn report_path(pane_id: &str) -> PathBuf {
    reports_dir().join(format!("{}.json", sanitize_pane_id(pane_id)))
}

fn atomic_write_json<T: Serialize>(path: &Path, value: &T) -> Result<(), String> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .map_err(|err| format!("unable to create {}: {err}", parent.display()))?;
    }
    let tmp = path.with_extension(format!("tmp.{}", std::process::id()));
    let json =
        serde_json::to_vec_pretty(value).map_err(|err| format!("unable to encode json: {err}"))?;
    fs::write(&tmp, json).map_err(|err| format!("unable to write {}: {err}", tmp.display()))?;
    fs::rename(&tmp, path).map_err(|err| format!("unable to replace {}: {err}", path.display()))
}

fn print_json<T: Serialize>(value: &T) {
    match serde_json::to_string(value) {
        Ok(json) => println!("{json}"),
        Err(err) => eprintln!("tmux-agent-plugin: unable to encode json: {err}"),
    }
}

fn parse_bool_flag(value: &str) -> bool {
    value.trim() == "1"
}

fn parse_i64(value: &str, fallback: i64) -> i64 {
    value.parse().unwrap_or(fallback)
}

fn now_secs() -> f64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_secs_f64())
        .unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn sample_item(state: &str) -> AgentItem {
        let pane = PaneRaw {
            session_id: "$1".to_string(),
            session_name: "project".to_string(),
            window_id: "@2".to_string(),
            window_index: "3".to_string(),
            window_name: "shell".to_string(),
            pane_id: "%4".to_string(),
            pane_index: "1".to_string(),
            pane_active: false,
            window_active: false,
            pane_current_command: "pi".to_string(),
            pane_title: "π - project".to_string(),
            pane_current_path: "/tmp/project".to_string(),
            pane_pid: "123".to_string(),
            pane_width: "100".to_string(),
            pane_height: "30".to_string(),
        };
        normalize_agent(
            &pane,
            "pi",
            state,
            state,
            "test",
            "pi",
            Some(123),
            Some(123),
            None,
        )
    }

    #[test]
    fn escape_response_titles_fall_back_to_directory_name() {
        let pane = PaneRaw {
            session_id: "$1".to_string(),
            session_name: "project".to_string(),
            window_id: "@2".to_string(),
            window_index: "3".to_string(),
            window_name: "shell".to_string(),
            pane_id: "%4".to_string(),
            pane_index: "1".to_string(),
            pane_active: false,
            window_active: false,
            pane_current_command: "pi".to_string(),
            pane_title: "Ga=d,d=I,i=9000,q=2".to_string(),
            pane_current_path: "/tmp/tmux-agent-plugin".to_string(),
            pane_pid: "123".to_string(),
            pane_width: "100".to_string(),
            pane_height: "30".to_string(),
        };
        assert_eq!(
            display_name(&pane, None, "project:3.1"),
            "tmux-agent-plugin"
        );
    }

    #[test]
    fn exact_agent_commands() {
        let cases = [
            ("pi", "pi"),
            ("claude", "claude"),
            ("claude-code", "claude"),
            ("codex", "codex"),
            ("gemini", "gemini"),
            ("opencode", "opencode"),
            ("cursor-agent", "cursor-agent"),
            ("ghcs", "copilot"),
            ("amp", "amp"),
            ("droid", "droid"),
            ("grok", "grok"),
            ("kimi", "kimi"),
            ("kiro", "kiro"),
            ("kilo", "kilo"),
            ("qodercli", "qodercli"),
            ("hermes", "hermes"),
        ];
        for (command, expected) in cases {
            assert_eq!(
                detect_agent(Some(command), None).as_deref(),
                Some(expected),
                "{command}"
            );
        }
    }

    #[test]
    fn runtime_wrapped_agents() {
        let cases = [
            ("node /usr/local/bin/pi-coding-agent", "pi"),
            ("npx @anthropic-ai/claude-code", "claude"),
            ("npm exec @openai/codex", "codex"),
            ("bunx @google/gemini-cli", "gemini"),
            ("python -m opencode", "opencode"),
            ("gh copilot suggest 'git status'", "copilot"),
        ];
        for (command, expected) in cases {
            assert_eq!(
                detect_agent(Some(command), None).as_deref(),
                Some(expected),
                "{command}"
            );
        }
    }

    #[test]
    fn fallback_current_command() {
        assert_eq!(
            detect_agent(Some("/bin/zsh"), Some("codex")).as_deref(),
            Some("codex")
        );
        assert_eq!(detect_agent(Some("vim README.md"), None), None);
    }

    #[test]
    fn strips_ansi_sequences() {
        assert_eq!(normalize_screen("\x1b[31mReady\x1b[0m\r\n"), "Ready");
    }

    #[test]
    fn screen_state_fixtures() {
        let blocked = include_str!("../fixtures/detect/blocked.txt");
        let working = include_str!("../fixtures/detect/working.txt");
        let idle = include_str!("../fixtures/detect/idle.txt");
        assert_eq!(
            raw_state_from_text(blocked, false, Some("claude")).0,
            "blocked"
        );
        assert_eq!(raw_state_from_text(working, false, Some("pi")).0, "working");
        assert_eq!(raw_state_from_text(idle, false, Some("gemini")).0, "idle");
    }

    #[test]
    fn stale_scrollback_does_not_dominate_recent_screen() {
        let old_blocker = format!(
            "Do you want to proceed? [y/N]\n{}\nReady for your message >\n",
            (0..20)
                .map(|i| format!("old line {i}"))
                .collect::<Vec<String>>()
                .join("\n")
        );
        let old_spinner = format!(
            "⠋ Thinking\n{}\nReady for your message >\n",
            (0..20)
                .map(|i| format!("old line {i}"))
                .collect::<Vec<String>>()
                .join("\n")
        );
        assert_eq!(
            raw_state_from_text(&old_blocker, false, Some("pi")).0,
            "idle"
        );
        assert_eq!(
            raw_state_from_text(&old_spinner, false, Some("pi")).0,
            "idle"
        );
    }

    #[test]
    fn bullet_lists_do_not_match_ascii_spinner() {
        let text =
            "Reinstalled:\n - vim-tmux-navigator\n - tmux-agent-plugin\n~/Documents/project >";
        let (state, reason) = raw_state_from_text(text, false, Some("pi"));
        assert_eq!(state, "idle", "{reason}");
    }

    #[test]
    fn changed_output_without_visible_working_signal_stays_idle() {
        let result = classify_screen(
            "ordinary transcript update without a prompt",
            Some("codex"),
            true,
            &StateRecord {
                state: "idle".to_string(),
                hash: "different".to_string(),
                ..StateRecord::default()
            },
            now_secs(),
        );
        assert_eq!(result.state, "idle");
        assert_eq!(result.reason, "known-agent-no-active-evidence");
    }

    #[test]
    fn classify_transitions() {
        let previous_hash = screen_hash("running command");
        let result = classify_screen(
            "Ready for your message",
            Some("gemini"),
            false,
            &StateRecord {
                state: "working".to_string(),
                hash: previous_hash,
                ..StateRecord::default()
            },
            now_secs(),
        );
        assert_eq!(result.state, "done");

        let result = classify_screen(
            "Ready for your message",
            Some("opencode"),
            true,
            &StateRecord {
                state: "done".to_string(),
                hash: screen_hash("Ready for your message"),
                ..StateRecord::default()
            },
            now_secs(),
        );
        assert_eq!(result.state, "idle");
    }

    #[test]
    fn counts_include_derived_values() {
        let items = vec![
            sample_item("blocked"),
            sample_item("working"),
            sample_item("done"),
        ];
        let counts = counts(&items);
        assert_eq!(counts["all"], 3);
        assert_eq!(counts["active"], 2);
        assert_eq!(counts["attention"], 2);
    }

    #[test]
    fn notify_transitions() {
        let blocked = sample_item("blocked");
        let event = event_for_transition(
            Some(&StateRecord {
                state: "idle".to_string(),
                agent_label: Some("pi".to_string()),
                ..StateRecord::default()
            }),
            &blocked,
            true,
        )
        .unwrap();
        assert_eq!(event.kind, "needs_attention");

        let done = sample_item("done");
        let event = event_for_transition(
            Some(&StateRecord {
                state: "working".to_string(),
                agent_label: Some("pi".to_string()),
                ..StateRecord::default()
            }),
            &done,
            true,
        )
        .unwrap();
        assert_eq!(event.kind, "finished");
    }
}
