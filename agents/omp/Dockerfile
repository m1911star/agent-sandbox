FROM oven/bun:1.4.4-slim

ENV BUN_INSTALL="/root/.bun"
ENV PATH="/root/.bun/bin:${PATH}"
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates openssh-client jq \
    && rm -rf /var/lib/apt/lists/*

ARG NPM_CONFIG_REGISTRY=https://registry.npmjs.org
RUN bun install -g @oh-my-pi/pi-coding-agent@latest --registry "$NPM_CONFIG_REGISTRY" \
    && omp --version

RUN git config --global init.defaultBranch main \
    && git config --global user.email "sandbox@trial" \
    && git config --global user.name "Sandbox"

COPY --chmod=755 sandbox-entry /usr/local/bin/sandbox-entry
WORKDIR /workspace
ENTRYPOINT ["/usr/local/bin/sandbox-entry", "omp"]
