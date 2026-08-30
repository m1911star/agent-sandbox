# ─── Codex (OpenAI) ──────────────────────────────────────────────────────────
# Auth: OPENAI_API_KEY env var  — or —  config in ~/.codex/
# Docs: https://github.com/openai/codex
# ─────────────────────────────────────────────────────────────────────────────

AGENT_DISPLAY_NAME="Codex (OpenAI)"
AGENT_IMAGE="sandbox-codex:latest"
AGENT_CONTAINER="sandbox-codex"

_CODEX_DIR="$HOME/.codex"

agent_check_auth() {
    if [[ -n "${OPENAI_API_KEY:-}" ]]; then
        info "Auth: OPENAI_API_KEY env var"
        return 0
    fi
    if [[ -d "$_CODEX_DIR" ]] && [[ -n "$(find "$_CODEX_DIR" -maxdepth 1 -type f 2>/dev/null | head -1)" ]]; then
        info "Auth: config dir (~/.codex/)"
        return 0
    fi
    error "No Codex auth found.\n       Set OPENAI_API_KEY or configure ~/.codex/ first."
}

agent_dockerfile() {
    cat <<'EOF'
FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates openssh-client jq \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g @openai/codex@latest

RUN git config --global init.defaultBranch main \
    && git config --global user.email "sandbox@trial" \
    && git config --global user.name "Sandbox"

# Entrypoint: copy read-only .codex/ → writable home
RUN printf '#!/bin/bash\nset -e\nif [ -d /tmp/sandbox-auth/codex ]; then\n  cp -a /tmp/sandbox-auth/codex ~/.codex\nfi\nexec bash "$@"\n' \
    > /usr/local/bin/sandbox-entry && chmod +x /usr/local/bin/sandbox-entry

WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entry"]
EOF
}

agent_docker_args() {
    [[ -n "${OPENAI_API_KEY:-}" ]] && SANDBOX_ARGS+=(-e "OPENAI_API_KEY=${OPENAI_API_KEY}")

    if [[ -d "$_CODEX_DIR" ]]; then
        SANDBOX_ARGS+=(-v "${_CODEX_DIR}:/tmp/sandbox-auth/codex:ro")
    fi

    [[ -n "${GH_TOKEN:-}" ]] && SANDBOX_ARGS+=(-e "GH_TOKEN=${GH_TOKEN}")
}

agent_post_info() {
    echo "  Agent:   codex"
    echo "  Config:  ~/.codex/ (writable copy)"
}
