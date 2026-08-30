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
./sandbox up omp                  # Enter sandbox (fully authenticated, zero setup)
# ... try new skills, break things, experiment ...
exit                              # Leave
./sandbox down omp --purge        # Nuclear option: erase all traces
```

## Supported Agents

| Agent | Status | Auth Method | Docs |
|-------|--------|-------------|------|
| **OMP** (Oh My Pi) | ✅ Ready | agent.db (Copilot OAuth) | [`agents/omp/`](./agents/omp/) |
| **Claude Code** | ✅ Ready | `ANTHROPIC_API_KEY` or OAuth | [`agents/claude-code/`](./agents/claude-code/) |
| **Codex** (OpenAI) | ✅ Ready | `OPENAI_API_KEY` | [`agents/codex/`](./agents/codex/) |
| Cursor | 🔲 Planned | TBD | — |
| Windsurf | 🔲 Planned | TBD | — |

## Quick Start

**Prerequisites**: Docker runtime (colima / OrbStack / Docker Desktop).

```bash
# Clone
git clone https://github.com/m1911star/agent-sandbox.git
cd agent-sandbox

# Launch any agent
./sandbox up omp                         # OMP (needs prior `omp` login)
./sandbox up claude-code                 # Claude Code (needs API key or `claude login`)
./sandbox up codex                       # Codex (needs OPENAI_API_KEY)

# Mount a project to work on
./sandbox up omp ~/my-project

# Skip proxy forwarding (if you don't use one)
./sandbox up claude-code --no-proxy
```

Inside the container:

```bash
omp                              # or `claude` / `codex`
# Fully working, pre-authenticated
# Tweak config, install skills, experiment...
exit                             # Done
```

Cleanup:

```bash
./sandbox down omp               # Remove container, keep image for fast re-launch
./sandbox down omp --purge       # Remove container + image completely
```

## CLI Reference

```
sandbox up    <agent> [workspace] [--no-proxy]    Launch sandbox
sandbox down  <agent> [--purge]                   Tear down
sandbox list                                      Show agents & status
sandbox status <agent>                            Container details
sandbox help                                      Usage info
```

## How It Works

```
┌─────────── Host ───────────┐          ┌─────────── Container ───────────┐
│                             │          │                                  │
│  ~/.omp/  ~/.claude/  etc. ─┼── :ro ──→│ /tmp/sandbox-auth/              │
│                             │          │         │                        │
│                             │          │    entrypoint copies to:         │
│                             │          │    ~/.<agent>/  (rw)             │
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
| Plugin-style agents | Each agent is a self-contained `agent.sh` — easy to add new ones |
| No `--rm` by default | Allows `docker start -ai` to resume work-in-progress |
| Colima-only `--add-host` | Docker Desktop / OrbStack resolve `host.docker.internal` natively |
| `--no-proxy` flag | Works without a local proxy running |

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `PROXY_PORT` | `7890` | HTTP proxy port on the host |
| `ANTHROPIC_API_KEY` | — | Claude Code API key (alternative to OAuth) |
| `OPENAI_API_KEY` | — | Codex API key |

## Project Structure

```
agent-sandbox/
├── sandbox                # Unified CLI entry point
├── lib/
│   └── common.sh          # Shared utilities (Docker, proxy, networking)
├── agents/
│   ├── omp/               # OMP agent
│   │   ├── agent.sh       # Agent definition (auth, Dockerfile, mounts)
│   │   └── README.md      # OMP-specific docs
│   ├── claude-code/       # Claude Code agent
│   │   ├── agent.sh
│   │   └── README.md
│   └── codex/             # Codex agent
│       ├── agent.sh
│       └── README.md
├── README.md              # This file
├── README.zh-CN.md        # Chinese documentation
└── LICENSE                # MIT
```

## Adding a New Agent

Create `agents/<name>/agent.sh` implementing four functions:

```bash
AGENT_DISPLAY_NAME="My Agent"
AGENT_IMAGE="sandbox-my-agent:latest"
AGENT_CONTAINER="sandbox-my-agent"

agent_check_auth()    # Validate host credentials exist
agent_dockerfile()    # Print Dockerfile to stdout
agent_docker_args()   # Append -v/-e flags to SANDBOX_ARGS array
agent_post_info()     # Print post-launch usage hints
```

See any existing agent in `agents/` for a complete example.

## Roadmap

- [x] OMP sandbox with GitHub Copilot auth passthrough
- [x] Claude Code sandbox (API key + OAuth)
- [x] Codex sandbox (OpenAI API key)
- [x] Unified CLI (`sandbox up/down/list`)
- [ ] Cursor sandbox
- [ ] Windsurf sandbox
- [ ] Multi-agent compose (shared network, cross-agent workflows)
- [ ] Snapshot & restore (save container state as reusable image)
- [ ] Skill trial mode (inject a single skill file without full config clone)

## License

[MIT](./LICENSE)
