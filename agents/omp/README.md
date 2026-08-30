# OMP Sandbox

Isolated container for trialing [OMP (Oh My Pi)](https://github.com/nicepkg/oh-my-pi) configurations, skills, and workflows.

## Authentication

OMP stores credentials in `~/.omp/agent/agent.db` — a SQLite database containing OAuth tokens (typically GitHub Copilot):

```
agent.db → auth_credentials table
  ├── provider: "github-copilot"
  ├── credential_type: "oauth"
  └── data: { access: "gho_...", expires: <unix_ts>, refresh: "gho_..." }
```

The sandbox copies this DB at container start. OMP handles token refresh in-memory. **No re-login required.**

## Files Mounted

| Host Path | Container Path | Mode | Purpose |
|-----------|---------------|------|---------|
| `~/.omp/agent/agent.db` | `/tmp/sandbox-auth/agent.db` → `~/.omp/agent/agent.db` | ro → copy | Auth credentials |
| `~/.omp/agent/config.yml` | `/tmp/sandbox-auth/config.yml` → `~/.omp/agent/config.yml` | ro → copy | Model & preferences |
| Optional: workspace | `/workspace` | rw | Project directory |

## Usage

```bash
sandbox up omp                        # basic
sandbox up omp ~/repos/my-app         # with project
sandbox up omp --no-proxy             # skip proxy forwarding
PROXY_PORT=1087 sandbox up omp        # custom proxy port
docker start -ai sandbox-omp          # resume session
sandbox down omp --purge              # full cleanup
```

## Inside the Container

```bash
omp                              # fully pre-authenticated

sed -i 's/claude-opus-4.6-1m/claude-sonnet-4/' ~/.omp/agent/config.yml

cat > /workspace/CLAUDE.md << 'EOF'
@./my-new-skill.md
EOF
# all changes are container-local — host is never touched
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No model selected` | agent.db missing/empty | Run `omp` → `/login` on host |
| Network timeout | Proxy not running | Start proxy, or `--no-proxy` |
| Image build fails | Registry unreachable | `sandbox down omp --purge` and retry |
| Token expired | OAuth TTL | `sandbox down omp && sandbox up omp` |
