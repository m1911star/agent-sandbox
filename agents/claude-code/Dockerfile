FROM node:22-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates openssh-client jq \
    && rm -rf /var/lib/apt/lists/*

ARG NPM_CONFIG_REGISTRY=https://registry.npmjs.org
RUN npm install -g @anthropic-ai/claude-code@latest --loglevel=http \
    && claude --version

RUN git config --global init.defaultBranch main \
    && git config --global user.email "sandbox@trial" \
    && git config --global user.name "Sandbox"

COPY --chmod=755 sandbox-entry /usr/local/bin/sandbox-entry
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entry", "claude-code"]
