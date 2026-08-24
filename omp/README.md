# OMP Sandbox

Isolated container environment for trialing [OMP (Oh My Pi)](https://github.com/nicepkg/oh-my-pi) coding agent configurations, skills, and workflows.

## Authentication

OMP stores credentials in `~/.omp/agent/agent.db` — a SQLite database containing OAuth tokens for the configured provider (typically GitHub Copilot):

```
agent.db → auth_credentials table
  ├── provider: "github-copilot"
  ├── credential_type: "oauth"
  └── data: { access: "gho_...", expires: <unix_ts>, refresh: "gho_..." }
```

The sandbox copies this DB at container start. OMP handles token refresh in-memory via the GitHub Copilot API. **No re-login required.**

> **Note**: OMP does NOT read `~/.config/github-copilot/apps.json` at runtime. It maintains its own credential store independently.

## Files Mounted

| Host Path | Container Path | Mode | Purpose |
|-----------|---------------|------|---------|
| `~/.omp/agent/agent.db` | `/tmp/omp-agent.db` → `~/.omp/agent/agent.db` | ro → copy | Auth credentials |
| `~/.omp/agent/config.yml` | `/tmp/omp-config.yml` → `~/.omp/agent/config.yml` | ro → copy | Model & preferences |
| Optional: `$1` | `/workspace` | rw | Project directory |

## Usage

```bash
# Basic sandbox
./sandbox-up.sh

# With a project directory
./sandbox-up.sh ~/repos/my-app

# Custom proxy port
PROXY_PORT=1087 ./sandbox-up.sh

# Resume previous session (container persists after exit)
docker start -ai omp-sandbox

# Rebuild image after OMP updates
./sandbox-down.sh --purge && ./sandbox-up.sh
```

## Inside the Container

```bash
# Everything works out of the box
omp

# Try different models
sed -i 's/claude-opus-4.6-1m/claude-sonnet-4/' ~/.omp/agent/config.yml

# Experiment with skills
cat > /workspace/CLAUDE.md << 'EOF'
# Experimental skill trial
@./my-new-skill.md
EOF

# All changes are container-local — host is never touched
```

## Container Contents

| Component | Version | Path |
|-----------|---------|------|
| Node.js | 22.x | system |
| Bun | latest | `~/.bun/bin/bun` |
| OMP | 18.x (latest) | `~/.bun/bin/omp` |
| Git | 2.39+ | system |

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No model selected` | agent.db missing or empty | Ensure OMP is authenticated on host: run `omp` → `/login` |
| Network timeout | Host proxy not running | Start proxy, or override: `PROXY_PORT=<port> ./sandbox-up.sh` |
| `Docker daemon not running` | colima not started | `colima start` |
| Image build fails | npm registry unreachable | Ensure proxy is running during build; `./sandbox-down.sh --purge` and retry |
| Token expired after long idle | OAuth access token has TTL | Re-run `./sandbox-down.sh && ./sandbox-up.sh` to get fresh copy |
