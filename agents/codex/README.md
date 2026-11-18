# Codex Sandbox

Run [Codex CLI](https://github.com/openai/codex) with clean configuration and your Magpie gateway. The sandbox does not copy your host `~/.codex/` or sign-in state.

From the Agent Sandbox checkout, [export the Magpie URL and key](../../README.md#quick-start), then run:

```bash
./sandbox up codex
# In the container shell:
codex
```

The sandbox initializes `~/.codex/config.toml` with the `magpie` provider and `auto/gpt-6.1-sol` as the default model. The provider uses the OpenAI Responses API and reads `MAGPIE_API_KEY`. Set `MAGPIE_MODEL` when creating a sandbox to select a different model. You can edit `~/.codex/config.toml` inside the container. `docker start -ai sandbox-codex` does not replace an existing config file.

Pass a project path to `./sandbox up codex` only if you want a read-write mount at `/workspace`.

## Network access for commands

The generated Codex config enables `workspace-write` and sets `sandbox_workspace_write.network_access = true`. Codex commands can access Magpie and the internet while writes remain limited to the workspace and temporary directories. The launcher does not change approvals. To block network access for Codex commands, set `network_access = false` in the container's config and relaunch `codex`.

Codex uses bubblewrap inside Docker. The launcher applies a [seccomp profile](./seccomp.json) to let bubblewrap create and configure its own namespaces. This profile starts with [Moby's default](https://github.com/moby/profiles/blob/f862455628f78f84c937e967e4a03902fb1dee11/seccomp/default.json) and adds only rules for `clone` with `CLONE_NEWUSER`, `unshare` with `CLONE_NEWUSER` or `CLONE_NEWPID`, and `mount`, `umount2`, and `pivot_root`. Docker still filters system calls, and the launcher adds no capabilities and does not use privileged mode. The upstream profile is [Apache 2.0 licensed](./LICENSE-moby.txt).

Docker hosts that prohibit unprivileged user namespaces can still block Codex commands. See [Codex sandbox prerequisites](https://developers.openai.com/codex/concepts/sandboxing#prerequisites) for runtime requirements. See [network and environment settings](../../README.md#network-and-environment) if the container shell cannot reach the network either.
