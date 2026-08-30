# ─── Claude Code (Anthropic) ─────────────────────────────────────────────────
# Auth: ANTHROPIC_API_KEY env var  — or —  OAuth via ~/.claude/.credentials
# Docs: https://docs.anthropic.com/en/docs/claude-code
# ─────────────────────────────────────────────────────────────────────────────

AGENT_DISPLAY_NAME="Claude Code"
AGENT_IMAGE="sandbox-claude-code:latest"
AGENT_CONTAINER="sandbox-claude-code"

_CLAUDE_DIR="$HOME/.claude"

agent_check_auth() {
    if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
        info "Auth: ANTHROPIC_API_KEY env var"
        return 0
    fi
    if [[ -f "$_CLAUDE_DIR/.credentials" ]]; then
        info "Auth: OAuth (~/.claude/.credentials)"
        return 0
    fi
    if [[ -f "$_CLAUDE_DIR/credentials.json" ]]; then
        info "Auth: OAuth (~/.claude/credentials.json)"
        return 0
    fi
    error "No Claude Code auth found.\n       Set ANTHROPIC_API_KEY or run 'claude login' on the host first."
}

agent_dockerfile() {
    cat <<'EOF'
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates openssh-client jq \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @anthropic-ai/claude-code@latest

RUN git config --global init.defaultBranch main \
    && git config --global user.email "sandbox@trial" \
    && git config --global user.name "Sandbox"

# Entrypoint: copy read-only .claude/ → writable home
RUN printf '#!/bin/bash\nset -e\nif [ -d /tmp/sandbox-auth/claude ]; then\n  cp -a /tmp/sandbox-auth/claude ~/.claude\nfi\nexec bash "$@"\n' \
    > /usr/local/bin/sandbox-entry && chmod +x /usr/local/bin/sandbox-entry

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entry"]
EOF
}

agent_docker_args() {
    [[ -n "${ANTHROPIC_API_KEY:-}" ]] && SANDBOX_ARGS+=(-e "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}")

    # Mount .claude/ for OAuth credentials + settings (read-only, copied by entrypoint)
    if [[ -d "$_CLAUDE_DIR" ]]; then
        SANDBOX_ARGS+=(-v "${_CLAUDE_DIR}:/tmp/sandbox-auth/claude:ro")
    fi

    [[ -n "${GH_TOKEN:-}" ]] && SANDBOX_ARGS+=(-e "GH_TOKEN=${GH_TOKEN}")
}

agent_post_info() {
    echo "  Agent:   claude"
    echo "  Config:  ~/.claude/ (writable copy)"
}
