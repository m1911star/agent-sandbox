# ─── OMP (Oh My Pi) ──────────────────────────────────────────────────────────
# Auth: Copilot OAuth stored in agent.db
# Docs: https://github.com/nicepkg/oh-my-pi
# ─────────────────────────────────────────────────────────────────────────────

AGENT_DISPLAY_NAME="OMP (Oh My Pi)"
AGENT_IMAGE="sandbox-omp:latest"
AGENT_CONTAINER="sandbox-omp"

_OMP_DIR="$HOME/.omp/agent"

agent_check_auth() {
    [[ -f "$_OMP_DIR/agent.db" ]]   || error "agent.db not found at $_OMP_DIR/\n       Run 'omp' and /login on the host first."
    [[ -f "$_OMP_DIR/config.yml" ]] || error "config.yml not found at $_OMP_DIR/\n       Run 'omp' on the host first."
    info "Auth: agent.db (Copilot OAuth)"
}

agent_dockerfile() {
    cat <<'EOF'
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates openssh-client jq unzip \
    && rm -rf /var/lib/apt/lists/*

# Package registry mirrors (Chinese users; override with NPM_REGISTRY build-arg)
RUN npm config set registry https://registry.npmmirror.com \
    && curl -fsSL https://bun.sh/install | bash
ENV PATH="/root/.bun/bin:$PATH"
RUN printf '[install]\nregistry = "https://registry.npmmirror.com"\n' > /root/bunfig.toml

RUN bun install -g @oh-my-pi/pi-coding-agent@latest

RUN git config --global init.defaultBranch main \
    && git config --global user.email "sandbox@trial" \
    && git config --global user.name "Sandbox"

# Entrypoint: copy read-only mounts → writable agent dir
RUN printf '#!/bin/bash\nset -e\nmkdir -p ~/.omp/agent\nfor f in /tmp/sandbox-auth/*; do\n  [ -f "$f" ] && cp "$f" ~/.omp/agent/\ndone\nexec bash "$@"\n' \
    > /usr/local/bin/sandbox-entry && chmod +x /usr/local/bin/sandbox-entry

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entry"]
EOF
}

agent_docker_args() {
    SANDBOX_ARGS+=(-v "${_OMP_DIR}/agent.db:/tmp/sandbox-auth/agent.db:ro")
    SANDBOX_ARGS+=(-v "${_OMP_DIR}/config.yml:/tmp/sandbox-auth/config.yml:ro")
    [[ -n "${GH_TOKEN:-}" ]] && SANDBOX_ARGS+=(-e "GH_TOKEN=${GH_TOKEN}")
}

agent_post_info() {
    echo "  Agent:   omp (pre-authenticated)"
    echo "  Config:  ~/.omp/agent/config.yml (writable copy)"
}
