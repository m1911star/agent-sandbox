#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────────────────────
# omp-sandbox-up: Launch an isolated OMP (Oh My Pi) trial environment
# Host config is never modified; container destruction resets everything.
# ─────────────────────────────────────────────────────────────────────────────

CONTAINER_NAME="omp-sandbox"
IMAGE_NAME="omp-sandbox:latest"
PROXY_PORT="${PROXY_PORT:-7890}"

# ── Helpers ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
error() { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }

# ── Prerequisites ────────────────────────────────────────────────────────────
command -v docker >/dev/null 2>&1 || error "Docker not found. Install Docker or start colima."
docker info >/dev/null 2>&1 || error "Docker daemon not running. Start colima first: colima start"

# ── Detect host IP (gateway from inside the VM = host) ───────────────────────
HOST_IP="host.docker.internal"
if command -v colima >/dev/null 2>&1 && colima status &>/dev/null; then
    HOST_IP=$(colima ssh -- ip route show default 2>/dev/null | awk '{print $3}') || HOST_IP="host.docker.internal"
    info "Host IP (colima gateway): $HOST_IP"
fi

# ── Auth & config checks ────────────────────────────────────────────────────
OMP_AGENT_DIR="$HOME/.omp/agent"
[[ -f "$OMP_AGENT_DIR/agent.db" ]]  || error "OMP agent.db not found at $OMP_AGENT_DIR/agent.db — run 'omp' and /login first"
[[ -f "$OMP_AGENT_DIR/config.yml" ]] || error "OMP config.yml not found at $OMP_AGENT_DIR/config.yml"

# ── Optional workspace mount ────────────────────────────────────────────────
WORKSPACE="${1:-}"
WORKSPACE_MOUNT=""
if [[ -n "$WORKSPACE" ]]; then
    WORKSPACE=$(cd "$WORKSPACE" && pwd)
    WORKSPACE_MOUNT="-v ${WORKSPACE}:/workspace"
    info "Workspace: $WORKSPACE → /workspace"
fi

# ── Build image (first run only) ────────────────────────────────────────────
if ! docker image inspect "$IMAGE_NAME" &>/dev/null; then
    info "Building sandbox image (first time, ~60s)..."
    docker build -t "$IMAGE_NAME" -f - /tmp <<'DOCKERFILE'
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    git curl ca-certificates openssh-client jq unzip \
    && rm -rf /var/lib/apt/lists/*

# Package registry mirrors
RUN npm config set registry https://registry.npmmirror.com
RUN curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"
RUN printf '[install]\nregistry = "https://registry.npmmirror.com"\n' > /root/bunfig.toml

# Install OMP
RUN bun install -g @oh-my-pi/pi-coding-agent@latest

# Minimal git config
RUN git config --global init.defaultBranch main \
    && git config --global user.email "sandbox@trial" \
    && git config --global user.name "OMP Sandbox"

# Entrypoint: copy read-only mounts to writable locations
RUN printf '#!/bin/bash\n\
mkdir -p ~/.omp/agent\n\
[[ -f /tmp/omp-config.yml ]] && cp /tmp/omp-config.yml ~/.omp/agent/config.yml\n\
[[ -f /tmp/omp-agent.db ]]  && cp /tmp/omp-agent.db  ~/.omp/agent/agent.db\n\
exec bash "$@"\n' > /usr/local/bin/sandbox-entry && chmod +x /usr/local/bin/sandbox-entry

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entry"]
DOCKERFILE
    info "Image built: $IMAGE_NAME"
else
    info "Image ready: $IMAGE_NAME"
fi

# ── Remove stale container ───────────────────────────────────────────────────
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    warn "Removing previous sandbox container..."
    docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
fi

# ── Export GH CLI token (if available) ───────────────────────────────────────
GH_TOKEN=""
if command -v gh >/dev/null 2>&1 && gh auth status &>/dev/null; then
    GH_TOKEN=$(gh auth token 2>/dev/null || true)
fi

# ── Launch ───────────────────────────────────────────────────────────────────
info "Starting OMP sandbox..."
echo "  Proxy:     http://${HOST_IP}:${PROXY_PORT}"
echo "  Auth:      agent.db + config.yml (read-only → writable copy)"
echo "  Exit:      type 'exit'"
echo "  Resume:    docker start -ai ${CONTAINER_NAME}"
echo ""

# shellcheck disable=SC2086
docker run -it \
    --name "$CONTAINER_NAME" \
    --add-host=host.docker.internal:${HOST_IP} \
    -e "HTTP_PROXY=http://host.docker.internal:${PROXY_PORT}" \
    -e "HTTPS_PROXY=http://host.docker.internal:${PROXY_PORT}" \
    -e "http_proxy=http://host.docker.internal:${PROXY_PORT}" \
    -e "https_proxy=http://host.docker.internal:${PROXY_PORT}" \
    -e "NO_PROXY=localhost,127.0.0.1,host.docker.internal" \
    -e "no_proxy=localhost,127.0.0.1,host.docker.internal" \
    -e "GH_TOKEN=${GH_TOKEN}" \
    -v "${OMP_AGENT_DIR}/agent.db:/tmp/omp-agent.db:ro" \
    -v "${OMP_AGENT_DIR}/config.yml:/tmp/omp-config.yml:ro" \
    ${WORKSPACE_MOUNT} \
    "$IMAGE_NAME"

# ── Post-exit info ───────────────────────────────────────────────────────────
echo ""
info "Sandbox exited. Container preserved as '${CONTAINER_NAME}'."
echo "  Resume:  docker start -ai ${CONTAINER_NAME}"
echo "  Delete:  omp-sandbox-down"
echo "  Nuke:    omp-sandbox-down --purge"
