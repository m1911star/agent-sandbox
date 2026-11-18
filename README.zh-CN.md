# Agent Sandbox

> 在一次性的 Docker 容器里试用 OMP、Claude Code 和 Codex，容器内的助手配置与宿主分开。

<p align="center">
  <a href="./README.md">English</a> ·
  <a href="#快速开始">快速开始</a> ·
  <a href="#支持的-agent">支持的 Agent</a> ·
  <a href="#工作原理">工作原理</a> ·
  <a href="#路线图">路线图</a>
</p>

---

## 痛点

你发现了一个有趣的 AI 编程助手工作流、skill 或配置，想试用，但是：

- 本地配置精心调教过 —— 不想搞坏
- Agent 配置都是全局的（`~/.omp/`、`~/.claude/`、`~/.codex/`）—— 难以隔离
- 实验失败后回滚意味着到处找散落的状态文件
- 清理后重新认证很痛苦

## 解决方案

**Agent Sandbox** 为已支持的编程助手提供一次性的、预认证的容器环境。只读挂载现有凭证，容器内获得可写副本，自由实验，一条命令销毁一切。

```bash
./sandbox up omp                  # 进入沙盒（已认证，零配置）
# ... 试新 skill、搞破坏、随便折腾 ...
exit                              # 退出
./sandbox down omp --purge        # 核弹选项：抹除所有痕迹
```

## 支持的 Agent

| Agent | 认证方式 | 文档 |
|-------|----------|------|
| **OMP** (Oh My Pi) | `agent.db` (Copilot OAuth) | [`agents/omp/`](./agents/omp/) |
| **Claude Code** | `ANTHROPIC_API_KEY` 或 OAuth | [`agents/claude-code/`](./agents/claude-code/) |
| **Codex** (OpenAI) | `OPENAI_API_KEY` | [`agents/codex/`](./agents/codex/) |

## 快速开始

**前置条件**：Docker 运行时（colima / OrbStack / Docker Desktop）。

```bash
# 克隆仓库
git clone https://github.com/m1911star/agent-sandbox.git
cd agent-sandbox

# 启动已支持的 Agent
./sandbox up omp                         # OMP（需先 `omp` 登录）
./sandbox up claude-code                 # Claude Code（需 API key 或 `claude login`）
./sandbox up codex                       # Codex（需 OPENAI_API_KEY）

# 挂载项目目录
./sandbox up omp ~/my-project

# 不使用代理转发
./sandbox up claude-code --no-proxy
```

容器内：

```bash
omp                              # 或 `claude` / `codex`
# 完整可用，已预认证
# 修改配置、安装 skill、随意实验...
exit                             # 完成
```

清理：

```bash
./sandbox down omp               # 删除容器，保留镜像（下次秒启）
./sandbox down omp --purge       # 容器 + 镜像全部删除
```

## CLI 参考

```
sandbox up    <agent> [workspace] [--no-proxy]    启动沙盒
sandbox down  <agent> [--purge]                   销毁沙盒
sandbox list                                      列出所有 Agent 及状态
sandbox status <agent>                            容器详情
sandbox help                                      使用帮助
```

## 工作原理

```
┌─────────── 宿主 ───────────┐          ┌─────────── 容器 ───────────────┐
│                             │          │                                  │
│  ~/.omp/  ~/.claude/  等 ──┼── :ro ──→│ /tmp/sandbox-auth/              │
│                             │          │         │                        │
│                             │          │    entrypoint 复制到:            │
│                             │          │    ~/.<agent>/  (rw)             │
│                             │          │                                  │
│  localhost:7890 (代理) ────┼─ tcp ───→│ host.docker.internal:7890        │
│                             │          │                                  │
└─────────────────────────────┘          └──────────────────────────────────┘
         永远不会被修改                        sandbox-down 后彻底销毁
```

### 核心设计决策

| 决策 | 理由 |
|------|------|
| 只读挂载 + 复制 | 容器永远不可能损坏宿主状态，即使崩溃也不会 |
| Entrypoint 启动时复制 | Agent 获得可写工作区，无需 bind-mount 回写 |
| 插件式 Agent | 每个 Agent 是独立的 `agent.sh` —— 添加新 Agent 极简 |
| 默认不加 `--rm` | 允许 `docker start -ai` 恢复进行中的工作 |
| 仅 Colima 注入 `--add-host` | Docker Desktop / OrbStack 原生解析 `host.docker.internal` |
| `--no-proxy` 选项 | 不跑代理的环境也能正常使用 |

## 配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PROXY_PORT` | `7890` | 宿主 HTTP 代理端口 |
| `ANTHROPIC_API_KEY` | — | Claude Code API key（替代 OAuth） |
| `OPENAI_API_KEY` | — | Codex API key |

## 项目结构

```
agent-sandbox/
├── sandbox                # 统一 CLI 入口
├── lib/
│   └── common.sh          # 公共工具（Docker、代理、网络）
├── agents/
│   ├── omp/               # OMP Agent
│   │   ├── agent.sh       # Agent 定义（认证、Dockerfile、挂载）
│   │   └── README.md      # OMP 专属文档
│   ├── claude-code/       # Claude Code Agent
│   │   ├── agent.sh
│   │   └── README.md
│   └── codex/             # Codex Agent
│       ├── agent.sh
│       └── README.md
├── README.md              # 英文文档
├── README.zh-CN.md        # 本文件
└── LICENSE                # MIT
```

## 添加新 Agent

创建 `agents/<name>/agent.sh`，实现四个函数：

```bash
AGENT_DISPLAY_NAME="My Agent"
AGENT_IMAGE="sandbox-my-agent:latest"
AGENT_CONTAINER="sandbox-my-agent"

agent_check_auth()    # 校验宿主凭据是否存在
agent_dockerfile()    # 输出 Dockerfile 到 stdout
agent_docker_args()   # 往 SANDBOX_ARGS 数组追加 -v/-e 参数
agent_post_info()     # 输出启动后的使用提示
```

参考 `agents/` 下任意现有 Agent 作为完整示例。

## 路线图

- [x] OMP 沙盒，支持 GitHub Copilot 认证透传
- [x] Claude Code 沙盒（API key + OAuth）
- [x] Codex 沙盒（OpenAI API key）
- [x] 统一 CLI（`sandbox up/down/list`）
- [ ] 多 Agent 编排（共享网络，跨 Agent 工作流）
- [ ] 快照与恢复（保存容器状态为可复用镜像）
- [ ] Skill 试用模式（注入单个 skill 文件，无需完整配置克隆）

## 许可证

[MIT](./LICENSE)
