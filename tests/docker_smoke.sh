#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
IMAGE="${IMAGE:-tmux-agent-plugin:docker-smoke}"

cd "$ROOT_DIR"
docker build -f tests/docker/Dockerfile -t "$IMAGE" .
docker run --rm "$IMAGE"
