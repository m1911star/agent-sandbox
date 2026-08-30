# Claude Code Sandbox

Isolated container for trialing [Claude Code](https://docs.anthropic.com/en/docs/claude-code) configurations, custom commands, and CLAUDE.md workflows.

## Authentication

| Method | How | Precedence |
|--------|-----|------------|
| **API Key** | Set `ANTHROPIC_API_KEY` env var on host | Checked first |
| **OAuth** | Run `claude login` on host → tokens in `~/.claude/` | Fallback |

The sandbox copies `~/.claude/` read-only into the container and makes a writable copy at startup.

## Files Mounted

| Host Path | Container Path | Mode | Purpose |
|-----------|---------------|------|---------|
| `~/.claude/` | `/tmp/sandbox-auth/claude/` → `~/.claude/` | ro → copy | Credentials + settings |
| `ANTHROPIC_API_KEY` | env var passthrough | — | API key auth |
| Optional: workspace | `/workspace` | rw | Project directory |

## Usage

```bash
ANTHROPIC_API_KEY=sk-ant-... sandbox up claude-code   # API key
sandbox up claude-code                                 # OAuth
sandbox up claude-code ~/repos/my-app                  # with project
sandbox up claude-code --no-proxy                      # skip proxy
docker start -ai sandbox-claude-code                   # resume
sandbox down claude-code --purge                       # full cleanup
```

## Inside the Container

```bash
claude                           # start Claude Code

# experiment with CLAUDE.md
cat > /workspace/CLAUDE.md << 'EOF'
You are a security-focused reviewer.
Always check for injection vulnerabilities.
EOF

# try custom commands
mkdir -p /workspace/.claude/commands
cat > /workspace/.claude/commands/review.md << 'EOF'
Review the current file for security issues.
EOF
# all changes are container-local
```

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `No API key` | No env var or OAuth credentials | Set `ANTHROPIC_API_KEY` or `claude login` on host |
| `401 Unauthorized` | Expired OAuth token | Re-run `claude login` on host, restart sandbox |
| Network timeout | Proxy misconfigured | Use `--no-proxy` |
| Image build fails | npm unreachable | Check network; `sandbox down claude-code --purge` and retry |
