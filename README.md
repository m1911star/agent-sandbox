# Agent Sandbox

Run OMP, Claude Code, or Codex in a clean Docker container connected to your Magpie gateway. The sandbox does not import host agent configs, OAuth sessions, or GitHub credentials.

[中文文档](./README.zh-CN.md)

## Quick start

Start Docker and Magpie on your host. Run the following commands from this checkout. Replace `magpie` with your own gateway key if it differs.

```bash
export OPENAI_BASE_URL='http://127.0.0.1:3425/v1'
export OPENAI_API_KEY='magpie'

./sandbox up omp
# In the container shell:
omp
```

Use `./sandbox up claude-code` or `./sandbox up codex` for the other agents. Type `exit` in the container shell when you finish. Pass a project directory to mount it at `/workspace`:

```bash
./sandbox up codex ~/my-project
```

**The workspace mount is read-write.** Edits in `/workspace` change the host directory. Without a workspace argument, nothing from your host filesystem is mounted by the launcher.

| Agent | Container command | Default Magpie model | Configuration |
|-------|-------------------|----------------------|---------------|
| `omp` | `omp` | `auto/gpt-6.1-sol` | [OMP](./agents/omp/) |
| `claude-code` | `claude` | `auto/claude-opus-4-8` | [Claude Code](./agents/claude-code/) |
| `codex` | `codex` | `auto/gpt-6.1-sol` | [Codex](./agents/codex/) |

## Resume or replace a container

Run `docker start -ai sandbox-omp` to resume a stopped OMP container. Replace `omp` with `claude-code` or `codex` to resume another agent. The sandbox initializes missing agent config files and leaves existing files alone on restart. The container also retains the gateway, key, and model environment from its creation.

`sandbox up` never deletes an existing container. To replace a container, including one created before Magpie support, save any container-only work you need and run `./sandbox down <agent>` before running `./sandbox up <agent>` again. Use the same procedure after changing the launcher environment. `--purge` also removes the selected `:magpie` image. It does not prune other images or remove an old `:latest` image.

```text
sandbox up <agent> [workspace] [--no-proxy]
sandbox down <agent> [--purge]
sandbox list
sandbox status <agent>
sandbox help
```

## Network and environment

| Variable | Default | Use |
|----------|---------|-----|
| `OPENAI_BASE_URL` | `http://127.0.0.1:3425/v1` | Magpie API URL as seen from the host. Use HTTP or HTTPS with a hostname or IP address and an optional port and path. Do not include credentials, a query, or a fragment. |
| `OPENAI_API_KEY` | Required | Export the Magpie gateway key. The launcher passes it by environment name as `MAGPIE_API_KEY`, not in Docker arguments or the image. Docker users with access to the container can inspect its environment. |
| `MAGPIE_MODEL` | Agent default above | Override the model ID when you create a sandbox. |
| `NPM_CONFIG_REGISTRY` | `https://registry.npmjs.org` | Use a trusted package registry for the first image build. Set a URL without credentials. If the image already exists, this setting does not rebuild it. |
| `PROXY_PORT` | Unset | Opt in to a host HTTP proxy for container traffic. `--no-proxy` ignores this setting. |

The sandbox uses Docker bridge networking. It does not publish ports, use the host network, or change host listeners. Outbound traffic goes direct by default, even if the Docker client has proxy defaults. First-time builds also go direct and need access to the image and package registries.

- The launcher rewrites loopback addresses such as `localhost`, `127.0.0.1`, and `[::1]` to `host.docker.internal`, keeping the scheme, port, and path. It leaves non-loopback URLs unchanged. Use a URL the container can reach. For HTTPS, the certificate must be valid for the hostname the container uses.
- OrbStack and Docker Desktop provide `host.docker.internal`. OrbStack can reach Magpie on macOS loopback with the default URL. If the active Docker endpoint is a Colima socket, the launcher tries the Colima VM gateway. Reachability depends on the Colima network and listener configuration.
- For other daemons, the launcher tries Docker's `host-gateway` mapping when it needs `host.docker.internal`. On native Linux this does not reach services bound only to `127.0.0.1` or `::1`. On a remote daemon, the mapping points at the Docker host, not your CLI machine. In these cases use a Magpie URL already reachable from the Docker network.
- To use a host HTTP proxy, set `PROXY_PORT` to the port of an existing proxy reachable from Docker, for example `PROXY_PORT=7890 ./sandbox up omp`. `NO_PROXY` and `no_proxy` include the Magpie hostname, so requests to Magpie bypass the proxy. Use `--no-proxy` if the proxy is unavailable.

Codex commands also have network access inside their workspace sandbox. Docker still filters system calls. See [running network commands in Codex](./agents/codex/#network-access-for-commands) to turn off network access for Codex commands.

## Run the regression tests

```bash
bash tests/cli.sh
```

The tests exercise the public CLI with a fake Docker executable. They do not use a Docker daemon or Magpie. If `jq` is installed on the test host, the tests also run the image's entrypoint in a temporary home. The launcher does not need host `jq`.

## Add an agent

Define the image tag, container name, display name, shell command, and default model in `agents/<name>/agent.sh`. Add a `Dockerfile` in the same directory. It can copy `sandbox-entry` from the build context and pass the agent name to the entrypoint. Add any container-side setup to `lib/sandbox-entry`.

## Roadmap

- [x] Clean OMP, Claude Code, and Codex sandboxes with Magpie access
- [x] Unified CLI for container lifecycle and status
- [ ] Shared networking for multi-agent workflows
- [ ] Container snapshots and restore
- [ ] Trial mode for a single skill file

## License

[MIT](./LICENSE)
