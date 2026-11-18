# Claude Code Sandbox

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) with clean configuration and your Magpie gateway. The sandbox does not copy your host `~/.claude/` or use host OAuth sessions.

From the Agent Sandbox checkout, [export the Magpie URL and key](../../README.md#quick-start), then run:

```bash
./sandbox up claude-code
# In the container shell:
claude
```

The entrypoint removes a final `/v1` from the gateway URL for `ANTHROPIC_BASE_URL`. It maps `MAGPIE_API_KEY` to `ANTHROPIC_AUTH_TOKEN`, sets `ANTHROPIC_MODEL` to `auto/claude-opus-4-8` by default, and sets `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`. Set `MAGPIE_MODEL` when creating a sandbox to select another Claude model served by Magpie.

Claude Code creates its own settings inside the container. `docker start -ai sandbox-claude-code` preserves those files and reapplies the original container environment.

Pass a project path to `./sandbox up claude-code` only if you want a read-write mount at `/workspace`. See [network and environment settings](../../README.md#network-and-environment) if Claude Code cannot reach Magpie.
