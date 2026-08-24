# Agent Sandbox

> 在完全隔离的容器中试用任何 AI 编程助手。对宿主配置零风险。

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

**Agent Sandbox** 为每个编程助手提供一次性的、预认证的容器环境。只读挂载现有凭证，容器内获得可写副本，自由实验，一条命令销毁一切。

```bash
./omp/sandbox-up.sh           # 进入沙盒（已认证，零配置）
# ... 试新 skill、搞破坏、随便折腾 ...
exit                          # 退出
./omp/sandbox-down.sh --purge # 核弹选项：抹除所有痕迹
```

## 支持的 Agent

| Agent | 状态 | 目录 | 认证方式 |
|-------|------|------|----------|
| **OMP** (Oh My Pi) | ✅ 可用 | [`omp/`](./omp/) | agent.db (Copilot OAuth) |
| Claude Code | 🔲 计划中 | `claude-code/` | ANTHROPIC_AUTH_TOKEN |
| Codex (OpenAI) | 🔲 计划中 | `codex/` | 本地代理透传 |
| Cursor | 🔲 计划中 | `cursor/` | 待定 |
| Windsurf | 🔲 计划中 | `windsurf/` | 待定 |

## 快速开始

### OMP

**前置条件**：Docker 运行时（colima / OrbStack / Docker Desktop）+ 宿主上已认证的 OMP。

```bash
# 克隆仓库
git clone https://github.com/m1911star/agent-sandbox.git
cd agent-sandbox

# 启动沙盒
./omp/sandbox-up.sh

# 或者挂载一个项目目录
./omp/sandbox-up.sh ~/my-project
```

容器内：

```bash
omp                              # 完整可用，已预认证
vi ~/.omp/agent/config.yml       # 随意修改 —— 宿主不受影响
# 安装实验性 skill，尝试新工作流...
exit                             # 完成
```

清理：

```bash
./omp/sandbox-down.sh            # 删除容器，保留镜像（下次秒启）
./omp/sandbox-down.sh --purge    # 容器 + 镜像全部删除
```

## 工作原理

```
┌─────────── 宿主 ───────────┐          ┌─────────── 容器 ───────────────┐
│                             │          │                                  │
│  ~/.omp/agent/agent.db ────┼── :ro ──→│ /tmp/omp-agent.db               │
│  ~/.omp/agent/config.yml ──┼── :ro ──→│ /tmp/omp-config.yml             │
│                             │          │         │                        │
│                             │          │    entrypoint 复制到:            │
│                             │          │    ~/.omp/agent/agent.db    (rw) │
│                             │          │    ~/.omp/agent/config.yml  (rw) │
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
| 默认不加 `--rm` | 允许 `docker start -ai` 恢复进行中的工作 |
| 自动检测 Host IP | 跨 colima、OrbStack、Docker Desktop 无需配置 |
| `PROXY_PORT` 环境变量 | 适配不同本地代理配置 |

## 配置

| 变量 | 默认值 | 说明 |
|------|--------|------|
| `PROXY_PORT` | `7890` | 宿主 HTTP 代理端口，转发到容器内 |

## 路线图

- [x] OMP 沙盒，支持 GitHub Copilot 认证透传
- [ ] Claude Code 沙盒（headless 模式 + API key 注入）
- [ ] Codex 沙盒（OpenAI Responses API）
- [ ] 多 Agent 编排（共享网络，跨 Agent 工作流）
- [ ] 快照与恢复（保存容器状态为可复用镜像）
- [ ] Skill 试用模式（注入单个 skill 文件，无需完整配置克隆）
- [ ] `sandbox-shell` 统一 CLI 入口

## 贡献

每个 Agent 沙盒遵循相同契约：

1. `sandbox-up.sh` — 构建镜像（如需）+ 启动容器
2. `sandbox-down.sh` — 销毁容器，`--purge` 删除镜像
3. `README.md` — Agent 专属的认证流程、用法和问题排查

添加新 Agent 只需创建包含以上三个文件的目录，提交 PR。

## 许可证

[MIT](./LICENSE)
