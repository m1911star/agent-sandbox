# Agent Sandbox

> Trial any AI coding agent in a fully isolated container. Zero risk to your host configuration.

<p align="center">
  <a href="./README.zh-CN.md">中文文档</a> ·
  <a href="#quick-start">Quick Start</a> ·
  <a href="#supported-agents">Agents</a> ·
  <a href="#how-it-works">How It Works</a> ·
  <a href="#roadmap">Roadmap</a>
</p>

---

## The Problem

You discover an interesting AI coding agent workflow, skill, or configuration. You want to try it, but:

- Your local setup is carefully tuned — you don't want to break it
- Agent configs are global (`~/.omp/`, `~/.claude/`, `~/.codex/`) — hard to isolate
- Rolling back failed experiments means hunting down scattered state files
- Re-authentication after cleanup is painful

## The Solution

**Agent Sandbox** gives you disposable, pre-authenticated containers for each coding agent. Mount your existing credentials read-only, get a writable copy inside the container, experiment freely, and destroy everything with one command.

```bash
./omp/sandbox-up.sh           # Enter sandbox (fully authenticated, zero setup)
# ... try new skills, break things, experiment ...
exit                          # Leave
./omp/sandbox-down.sh --purge # Nuclear option: erase all traces
```

## Supported Agents

| Agent | Status | Directory | Auth Method |
|-------|--------|-----------|-------------|
| **OMP** (Oh My Pi) | ✅ Ready | [`omp/`](./omp/) | agent.db (Copilot OAuth) |
| Claude Code | 🔲 Planned | `claude-code/` | ANTHROPIC_AUTH_TOKEN |
| Codex (OpenAI) | 🔲 Planned | `codex/` | Local proxy passthrough |
| Cursor | 🔲 Planned | `cursor/` | TBD |
| Windsurf | 🔲 Planned | `windsurf/` | TBD |

## Quick Start

### OMP

**Prerequisites**: Docker runtime (colima / OrbStack / Docker Desktop) + authenticated OMP on host.

```bash
# Clone
git clone https://github.com/m1911star/agent-sandbox.git
cd agent-sandbox

# Launch sandbox
./omp/sandbox-up.sh

# Or mount a project to work on
./omp/sandbox-up.sh ~/my-project
```

Inside the container:

```bash
omp                              # Fully working, pre-authenticated
vi ~/.omp/agent/config.yml       # Tweak freely — host is untouched
# Install experimental skills, try new workflows...
exit                             # Done
```

Cleanup:

```bash
./omp/sandbox-down.sh            # Remove container, keep image for fast re-launch
./omp/sandbox-down.sh --purge    # Remove container + image completely
```

## How It Works

```
┌─────────── Host ───────────┐          ┌─────────── Container ───────────┐
│                             │          │                                  │
│  ~/.omp/agent/agent.db ────┼── :ro ──→│ /tmp/omp-agent.db               │
│  ~/.omp/agent/config.yml ──┼── :ro ──→│ /tmp/omp-config.yml             │
│                             │          │         │                        │
│                             │          │    entrypoint copies to:         │
│                             │          │    ~/.omp/agent/agent.db    (rw) │
│                             │          │    ~/.omp/agent/config.yml  (rw) │
│                             │          │                                  │
│  localhost:7890 (proxy) ───┼─ tcp ───→│ host.docker.internal:7890        │
│                             │          │                                  │
└─────────────────────────────┘          └──────────────────────────────────┘
         NEVER modified                       Destroyed on sandbox-down
```

### Key Design Decisions

| Decision | Rationale |
|----------|-----------|
| Read-only mounts + copy | Container can never corrupt host state, even on crash |
| Entrypoint copies on start | Writable workspace for the agent without bind-mount writes |
| No `--rm` by default | Allows `docker start -ai` to resume work-in-progress |
| Host IP auto-detection | Works across colima, OrbStack, Docker Desktop without config |
| `PROXY_PORT` env override | Adapts to different local proxy setups |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PROXY_PORT` | `7890` | HTTP proxy port on the host, forwarded into container |

## Project Structure

```
agent-sandbox/
├── README.md              # This file (English)
├── README.zh-CN.md        # Chinese documentation
├── LICENSE                # MIT
├── .gitignore
├── omp/                   # OMP agent sandbox
│   ├── README.md          # OMP-specific docs & troubleshooting
│   ├── sandbox-up.sh      # Launch script
│   └── sandbox-down.sh    # Teardown script
├── claude-code/           # (planned)
├── codex/                 # (planned)
└── ...
```

## Roadmap

- [x] OMP sandbox with GitHub Copilot auth passthrough
- [ ] Claude Code sandbox (headless mode + API key injection)
- [ ] Codex sandbox (OpenAI Responses API)
- [ ] Multi-agent compose (shared network, cross-agent workflows)
- [ ] Snapshot & restore (save container state as reusable image)
- [ ] Skill trial mode (inject a single skill file without full config clone)
- [ ] `sandbox-shell` unified CLI wrapper for all agents

## Contributing

Each agent sandbox follows the same contract:

1. `sandbox-up.sh` — builds image (if needed) + launches container
2. `sandbox-down.sh` — tears down container, `--purge` removes image
3. `README.md` — agent-specific auth flow, usage, and troubleshooting

To add a new agent, create a directory with these three files and submit a PR.

## License

[MIT](./LICENSE)
