# Codex Sandbox

Isolated container for trialing [Codex CLI](https://github.com/openai/codex) configurations and workflows.

## Authentication

| Method | How | Precedence |
|--------|-----|------------|
| **API Key** | Set `OPENAI_API_KEY` env var on host | Checked first |
| **Config dir** | Pre-configured `~/.codex/` on host | Fallback |

The sandbox copies `~/.codex/` read-only into the container and makes a writable copy at startup.

## Files Mounted

| Host Path | Container Path | Mode | Purpose |
|-----------|---------------|------|---------|
| `~/.codex/` | `/tmp/sandbox-auth/codex/` → `~/.codex/` | ro → copy | Config + credentials |
| `OPENAI_API_KEY` | env var passthrough | — | API key auth |
| Optional: workspace | `/workspace` | rw | Project directory |

## Usage

```bash
OPENAI_API_KEY=sk-... sandbox up codex         # API key
sandbox up codex                                # from ~/.codex/ config
sandbox up codex ~/repos/my-app                 # with project
sandbox up codex --no-proxy                     # skip proxy
docker start -ai sandbox-codex                  # resume
sandbox down codex --purge                      # full cleanup
```

## Inside the Container

```bash
codex                            # start Codex CLI

# experiment with instructions
cat > ~/.codex/instructions.md << 'EOF'
Always write tests before implementation.
Use TypeScript strict mode.
EOF
# all changes are container-local
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No API key` | No env var or config dir | Set `OPENAI_API_KEY` |
| Network timeout | Proxy misconfigured | Use `--no-proxy` |
| Image build fails | npm unreachable | Check network; `sandbox down codex --purge` and retry |
