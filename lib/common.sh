#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
# agent-sandbox shared utilities
# Sourced by the sandbox CLI — not executed directly.
# ─────────────────────────────────────────────────────────────────────────────

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

info()   { echo -e "${GREEN}[✓]${NC} $*"; }
warn()   { echo -e "${YELLOW}[!]${NC} $*"; }
error()  { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
header() { echo -e "\n${BOLD}${CYAN}═══ $* ═══${NC}\n"; }

# ── Docker prerequisites ────────────────────────────────────────────────────

require_docker() {
    command -v docker >/dev/null 2>&1 || error "Docker not found. Install Docker, colima, or OrbStack."
    docker info >/dev/null 2>&1     || error "Docker daemon not running."
}

# ── Host networking ──────────────────────────────────────────────────────────
# Docker Desktop and OrbStack resolve host.docker.internal natively.
# Colima does NOT — we must inject the VM gateway IP via --add-host.
# Sets ADD_HOST_FLAG (empty string when not needed).

detect_host_networking() {
    ADD_HOST_FLAG=""
    if command -v colima >/dev/null 2>&1 && colima status &>/dev/null; then
        local gw
        gw=$(colima ssh -- ip route show default 2>/dev/null | awk '{print $3}') || true
        if [[ -n "$gw" ]]; then
            ADD_HOST_FLAG="--add-host=host.docker.internal:${gw}"
            info "Colima gateway: $gw"
        fi
    fi
}

# ── GH CLI token passthrough ────────────────────────────────────────────────

detect_gh_token() {
    GH_TOKEN=""
    if command -v gh >/dev/null 2>&1 && gh auth status &>/dev/null 2>&1; then
        GH_TOKEN=$(gh auth token 2>/dev/null || true)
    fi
}

# ── Proxy ────────────────────────────────────────────────────────────────────
# Appends HTTP(S)_PROXY env flags to the global SANDBOX_ARGS array.

add_proxy_args() {
    local url="http://host.docker.internal:${PROXY_PORT}"
    SANDBOX_ARGS+=(-e "HTTP_PROXY=${url}" -e "HTTPS_PROXY=${url}")
    SANDBOX_ARGS+=(-e "http_proxy=${url}" -e "https_proxy=${url}")
    SANDBOX_ARGS+=(-e "NO_PROXY=localhost,127.0.0.1,host.docker.internal")
    SANDBOX_ARGS+=(-e "no_proxy=localhost,127.0.0.1,host.docker.internal")
}

# ── Container lifecycle ──────────────────────────────────────────────────────

remove_stale_container() {
    local name="$1"
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        warn "Removing stale container: $name"
        docker rm -f "$name" >/dev/null 2>&1
    fi
}

# Builds image from agent_dockerfile() output if it doesn't already exist.
build_image_if_needed() {
    local image="$1"
    if ! docker image inspect "$image" &>/dev/null; then
        info "Building image (first time, may take a minute)..."
        agent_dockerfile | docker build -t "$image" -f - /tmp
        info "Image built: $image"
    else
        info "Image ready: $image"
    fi
}

remove_container() {
    local name="$1"
    if docker ps -a --format '{{.Names}}' | grep -q "^${name}$"; then
        docker rm -f "$name" >/dev/null 2>&1
        info "Container removed: $name"
    else
        warn "No container found: $name"
    fi
}

remove_image() {
    local image="$1"
    if docker image inspect "$image" &>/dev/null; then
        docker rmi "$image" >/dev/null 2>&1
        info "Image removed: $image"
    fi
    docker image prune -f >/dev/null 2>&1
    info "Dangling images pruned"
}
