FROM rust:1-bookworm

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update \
	&& apt-get install -y --no-install-recommends \
		bash \
		ca-certificates \
		curl \
		fzf \
		git \
		jq \
		perl \
		procps \
		python3 \
		tmux \
	&& rm -rf /var/lib/apt/lists/*

RUN git clone --depth 1 https://github.com/tmux-plugins/tpm /root/.tmux/plugins/tpm

COPY . /work/tmux-agent-plugin-src
RUN mkdir -p /root/.tmux/plugins \
	&& cp -a /work/tmux-agent-plugin-src /root/.tmux/plugins/tmux-agent-plugin \
	&& cd /root/.tmux/plugins/tmux-agent-plugin \
	&& cargo build --release

COPY tests/docker/bin/fake-agent /usr/local/bin/fake-agent
RUN chmod +x /usr/local/bin/fake-agent \
	&& ln -s /usr/local/bin/fake-agent /usr/local/bin/pi \
	&& ln -s /usr/local/bin/fake-agent /usr/local/bin/claude \
	&& ln -s /usr/local/bin/fake-agent /usr/local/bin/codex \
	&& ln -s /usr/local/bin/fake-agent /usr/local/bin/gemini \
	&& ln -s /usr/local/bin/fake-agent /usr/local/bin/opencode

WORKDIR /root/.tmux/plugins/tmux-agent-plugin
ENTRYPOINT ["/root/.tmux/plugins/tmux-agent-plugin/tests/docker/run.sh"]
