# Agent Sandbox

在全新的 Docker 容器里运行 OMP、Claude Code 或 Codex，并连接到你的 Magpie 网关。沙盒不会导入宿主机的助手配置、OAuth 会话或 GitHub 凭据。

[English](./README.md)

## 快速开始

在宿主机上启动 Docker 和 Magpie。在本仓库目录下运行以下命令。如果你的网关密钥不是 `magpie`，请替换为实际值。

```bash
export OPENAI_BASE_URL='http://127.0.0.1:3425/v1'
export OPENAI_API_KEY='magpie'

./sandbox up omp
# 在容器的 shell 中运行：
omp
```

也可以用 `./sandbox up claude-code` 或 `./sandbox up codex` 启动其他助手。用完后，在容器的 shell 中输入 `exit`。传入项目目录可将其挂载到 `/workspace`：

```bash
./sandbox up codex ~/my-project
```

**工作区为读写挂载。** 在 `/workspace` 中的改动会写回宿主目录。不传工作区时，启动器不会挂载宿主机上的文件。

| 助手 | 容器内命令 | 默认 Magpie 模型 | 配置 |
|------|------------|------------------|------|
| `omp` | `omp` | `auto/gpt-6.1-sol` | [OMP](./agents/omp/) |
| `claude-code` | `claude` | `auto/claude-opus-4-8` | [Claude Code](./agents/claude-code/) |
| `codex` | `codex` | `auto/gpt-6.1-sol` | [Codex](./agents/codex/) |

## 恢复或替换容器

用 `docker start -ai sandbox-omp` 恢复已停止的 OMP 容器。将命令中的 `omp` 替换为 `claude-code` 或 `codex`，即可恢复对应的容器。沙盒只初始化缺失的助手配置文件，重启不会覆盖已有文件。网关地址、密钥和模型环境变量也仍是创建容器时的值。

`sandbox up` 不会删除已有容器。要替换容器（包括接入 Magpie 之前创建的容器），先保存仅存在于容器内的工作，再运行 `./sandbox down <agent>`，然后重新运行 `./sandbox up <agent>`。修改启动环境变量后也按此方式重新创建。`--purge` 会额外删除所选助手的 `:magpie` 镜像，不会清理其他镜像或删除旧的 `:latest` 镜像。

```text
sandbox up <agent> [workspace] [--no-proxy]
sandbox down <agent> [--purge]
sandbox list
sandbox status <agent>
sandbox help
```

## 网络和环境变量

| 变量 | 默认值 | 用途 |
|------|--------|------|
| `OPENAI_BASE_URL` | `http://127.0.0.1:3425/v1` | 宿主机访问的 Magpie API 地址。使用 HTTP 或 HTTPS，包含主机名或 IP，可带端口和路径。不要包含凭据、查询参数或片段。 |
| `OPENAI_API_KEY` | 必填 | 导出 Magpie 网关密钥。启动器通过环境变量名 `MAGPIE_API_KEY` 传给容器，不把密钥写入 Docker 命令参数或镜像。有权访问该容器的 Docker 用户可以查看容器环境变量。 |
| `MAGPIE_MODEL` | 见上表 | 创建沙盒时指定模型 ID。 |
| `NPM_CONFIG_REGISTRY` | `https://registry.npmjs.org` | 首次构建镜像时使用指定的软件包仓库。请选择可信的地址，不要在 URL 中包含凭据。已有镜像不会因此重建。 |
| `PROXY_PORT` | 未设置 | 显式启用宿主机的 HTTP 代理。`--no-proxy` 会忽略此变量。 |

沙盒使用 Docker 桥接网络。不发布端口，不使用宿主网络，也不会修改宿主机上的监听地址。容器默认直连，不采用 Docker 客户端的代理默认值。首次构建镜像也使用直连，需要能访问镜像和软件包仓库。

- 启动器把 `localhost`、`127.0.0.1`、`[::1]` 等回环地址替换为 `host.docker.internal`，保留协议、端口和路径。非回环地址保持原样。请使用容器可访问的地址。若使用 HTTPS，证书必须对容器实际访问的主机名有效。
- OrbStack 和 Docker Desktop 提供 `host.docker.internal`。在 macOS 上，OrbStack 可通过默认地址访问只监听回环地址的 Magpie。如果当前 Docker 端点使用 Colima 套接字，启动器会尝试使用 Colima 虚拟机网关。能否连通取决于 Colima 的网络和服务监听配置。
- 其他 Docker 守护进程需要 `host.docker.internal` 时，启动器会尝试 Docker 的 `host-gateway` 映射。在原生 Linux 上，此映射无法访问只监听 `127.0.0.1` 或 `::1` 的服务。如果使用远程 Docker，映射指向运行 Docker 的宿主机，而不是运行命令的机器。这些情况下请使用 Docker 网络已能访问的 Magpie 地址。
- 如需使用宿主 HTTP 代理，将 `PROXY_PORT` 设为容器可以访问的现有代理端口，例如 `PROXY_PORT=7890 ./sandbox up omp`。`NO_PROXY` 和 `no_proxy` 包含 Magpie 主机名，访问 Magpie 时不走代理。代理不可用时可加 `--no-proxy`。

Codex 的命令在它自己的工作区沙盒内也可以联网。Docker 仍过滤系统调用。若要关闭 Codex 命令的联网权限，参见 [Codex 命令的网络访问](./agents/codex/#network-access-for-commands)。

## 运行回归测试

```bash
bash tests/cli.sh
```

测试通过模拟的 Docker 命令调用公开 CLI，不需要 Docker 守护进程或 Magpie。若测试机器装有 `jq`，测试还会在临时主目录中运行镜像的入口脚本。启动器本身不需要宿主机安装 `jq`。

## 添加助手

在 `agents/<name>/agent.sh` 中定义镜像标签、容器名称、显示名称、容器内命令和默认模型。在同一目录下添加 `Dockerfile`。它可以从构建上下文复制 `sandbox-entry`，并将助手名称作为入口参数。在 `lib/sandbox-entry` 中添加需要在容器内完成的初始化。

## 路线图

- [x] 使用 Magpie 的全新 OMP、Claude Code 和 Codex 沙盒
- [x] 统一 CLI 管理容器和查看状态
- [ ] 多助手工作流共享网络
- [ ] 容器快照和恢复
- [ ] 单个 skill 文件试用模式

## 许可证

[MIT](./LICENSE)
