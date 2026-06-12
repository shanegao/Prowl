# Workspace 内 Codex ↔ Claude Code Hands-off 方案设计

> 调研 + 方案。输入：`switcher-hands-off-design.md`（一份通用的独立 CLI 设想）。
> 本文把那份设想落到 Prowl 的真实架构上，给出分层、可分阶段实施的方案。
> 过程结论均有代码实证，关键位置附 `file:line`（实现时以代码为准）。

## 0. 结论先行（TL;DR）

**核心判断：不要做独立外部工具（前期调研里的 TypeScript "Switcher" + `.switcher/`）。** Prowl
已经具备 handoff 所需的大半基础设施，正确做法是把 handoff 建在这些既有能力之上：

1. **Workspace** —— 一个 agent 在多仓共享的 cwd 里干活，元数据在 `.prowl/workspace.json`。
2. **Agent 检测** —— Prowl 已经知道每个 pane 里跑的是 codex 还是 claude（`DetectedAgent`），
   以及它处于 working / blocked / done / idle，并有状态变化事件 `agentEntryChanged`。
3. **`prowl` CLI** —— 已能开 tab、把命令注入 pane、读屏（`--capture` 走 OSC 133）、发键、聚焦。
4. **终端注入** —— `createTabWithInput` / `createSplitWithInput` / `insertText` 已经能在新
   pane 里启动 `claude "<prompt>"` / `codex "<prompt>"`。
5. **通知** —— agent 完成 / 阻塞时已有系统通知 + sidebar/Dock 提醒。

也就是说 **handoff 的「机制层」基本现成**；真正缺的是「**契约层**」（一个跨 agent 的工件 +
两边都遵守的协议）和把它们串起来的一层薄编排。

**分层落地（推荐先做 L0 + L1）：**

| 层 | 内容 | app 代码量 | 现在能用吗 |
|----|------|-----------|-----------|
| **L0** 纯约定 | handoff 工件模板 + AGENTS.md/CLAUDE.md 协议 + 现成 `prowl` 命令手动交接 | 0 | ✅ 今天就能用 |
| **L1** `prowl handoff` | 新 CLI 子命令 `save`/`to`/`status` + handoff 存储 + `prowl list` 暴露 agent 身份 | 中（CLI + handler） | 需开发 |
| **L2** UI 集成 | 命令面板动作、通知里的「Hand off now?」、可选的 Handoff 面板 | 中 | 需开发 |
| **L3** 半自动 / 自动 | 钩 `agentEntryChanged`，按策略自动交接（强安全栏 + 显式开关） | 大 | 需开发 |

---

## 1. 问题的本质：为什么 agent-to-agent handoff 难

Codex 和 Claude Code 是**两个各自独立的进程**，各自维护内部对话上下文。一旦从 A 切到 B，
**A 的内存上下文对 B 完全不可见**。它们之间唯一可靠、持久的通道是**文件系统 + git 工作区**。

> 推论：任何 handoff 都必须把 A 的相关上下文「外化」成一个 B 能读懂的**工件（artifact）**。
> 这正是前期调研的核心洞察，本文完全采纳。Prowl 的增值在于把这件事做得**自动、就地、可驱动**。

把 handoff 拆成三个子问题，后文逐一对应：

- **Capture（A → 工件）**：谁来写工件、写什么、何时写。
- **Transport（工件 → B）**：B 怎样「带着工件」启动并接着干。
- **Trigger（时机）**：手动按钮 / A 收尾时自己触发 / 状态变化自动触发。

---

## 2. Prowl 现状盘点（决定了方案形态）

下表是本次调研在代码里逐条验证过的事实，它们决定了「该做什么、不该重复造什么」。

| 能力 | 现状 | 对 handoff 的意义 | 代码位置 |
|------|------|------------------|---------|
| Workspace 共享 cwd | terminal 起在 workspace **root**；多仓在 `.prowl/workspace.json`（symlink / worktree） | 两个 agent 同 cwd、同一份磁盘文件，工件放 `.prowl/` 天然共享 | `Domain/ProjectWorkspace.swift`；`Features/Repositories/Reducer/RepositoriesFeature+StateQueries.swift:30` |
| Agent **身份**检测 | `DetectedAgent`（`.claude`/`.codex`/…），按进程名 + argv + 屏幕启发式识别；存在 `PaneAgentState.detectedAgent`，per-surface | 不必新增「assign agent」状态就能知道某 pane 跑的是谁 | `Infrastructure/AgentDetection/AgentClassifier.swift:3`；`Domain/AgentDetection/PaneAgentState.swift:3` |
| Agent **状态** | working / blocked / done / idle；done vs idle 靠 `seen` 标志（后台完成未看 = done） | 能精确知道「A 干完了」「A 卡住等人」 → 是 handoff 的触发信号 | `Domain/AgentDetection/PaneAgentState.swift:24`；`ScreenHeuristics.swift` |
| 状态变化**事件** | `TerminalClient.Event.agentEntryChanged(ActiveAgentEntry)`，带 agent 身份 + raw/display 状态 | L3 自动 handoff 的钩子 | `Clients/Terminal/TerminalClient.swift:69`；`WorktreeTerminalManager.swift:269` |
| CLI 注入/驱动 | `tab create` / `send`（`--capture` 走 OSC 133）/ `read --wait-stable` / `key` / `focus` | 启动接手 agent、把 prompt 喂进去、读它的输出，全部已具备 | `docs/components/cli.md`；`supacode/CLIService/*` |
| 终端注入机制 | 文本走 `ghostty_surface_text` + 合成回车；`createTabWithInput`/`createSplitWithInput`/`insertText` 已存在 | 在新 tab/split 里跑 `claude "…"`/`codex "…"` 不用新造轮子 | `Clients/Terminal/TerminalClient.swift:19`；`Infrastructure/Ghostty/GhosttySurfaceBridge.swift:72` |
| 自定义命令 | `UserCustomCommand`（存 `~/.prowl/repo/<repo>/prowl.onevcat.json`），可把 `claude -p "…"` 绑成按钮 + 快捷键，支持「新 tab / 就地 / 新 split」 | L0 不写 app 代码就能把「交接给 X」做成一个键 | `Features/Settings/Models/UserRepositorySettings.swift:31`；`AppFeature.swift:666` |
| 通知 | agent done/blocked → 系统通知 + sidebar 铃铛 + Dock 角标 | L2「Hand off now?」动作的载体 | `docs/components/notifications.md` |

**两个关键缺口（本方案要补的）：**

1. **没有跨 agent 的工件 / 协议**（契约层缺失）——这是地基，见 §4。
2. **`prowl list` 不暴露 agent 身份**——只给 `task.status`（running/idle），不告诉你「这个 pane
   是 codex 还是 claude」。已用线上 `prowl list --json` 实测确认。编排层要看到「谁是谁」，需要把
   `DetectedAgent` 透出到 CLI（见 §5.2）。响应模型在 `supacode/CLIService/Shared/ListCommandPayload.swift:13`。

> 另一处事实：workspace 打开后**没有任何 auto-start 命令、也没有「这个 workspace 归属哪个 agent」
> 的持久状态**——用户自己在 tab 里敲 `claude`/`codex`。所以「启动接手方」这一步要么靠 L0 的自定义
> 命令，要么靠 L1 的 `prowl handoff to`。

---

## 3. 与前期调研的对照（采纳什么、改什么）

**采纳：**

- handoff 工件的**结构化分节**（Goal / State / Done / Files / Commands / Open Questions / Risks /
  Next Steps / Suggested Prompt）——直接复用，见 §4.2。
- **安全边界**（不自动 commit/push、不破坏性 git、不写 secrets、自动模式需显式配置）——见 §7。
- **分阶段**思路与 `run` 状态模型（id/title/objective/agent/status/nextStep）。

**改（因为落到 Prowl）：**

- ❌ 不做独立 TypeScript CLI、不引 `.switcher/` 目录。改为复用 `.prowl/` 与 `prowl` CLI——避免再造
  一套 git 状态读取、进程驱动、agent 检测（Prowl 都有）。
- ❌ 不要 per-run 的 8 文件布局。一个 workspace 通常 == 一个任务，简化为**单个活跃 handoff +
  归档**，见 §4.1。
- ✅ 把「检测当前是哪个 agent / 它什么状态」从「用户配置」改为「Prowl 实时检测」——这是 Prowl 独有
  的能力，前期调研（作为外部工具）拿不到。

---

## 4. 契约层：Handoff 工件 + 协议（地基，最重要也最稳定）

这一层不依赖任何 app 代码改动，是所有上层方案的公共基础，应**最先确定并冻结格式**。

### 4.1 存储布局

工件就放在 workspace 已有的 `.prowl/` 下，与静态配置 `workspace.json` 并列：

```text
<workspace>/.prowl/
  workspace.json                         # 静态：多仓配置（已存在）
  handoff/
    current.md                           # 活跃 handoff 工件（跨 agent 的「契约」）
    log.md                               # append-only：每次交接一行（from→to / 时间 / 摘要）
    archive/
      2026-06-11T1430-codex-to-claude.md # 历史快照（每次 handoff to 时归档上一份）
```

**为什么和 `workspace.json` 分开**：`workspace.json` 是**静态配置**（哪些仓、在哪、分支），由
创建流程写、之后基本不变；handoff 是**动态状态**，每次交接都更新。混在一起会让静态配置变得「脏」。
（注：`ProjectWorkspace` 是 Codable 且已被加载，未来若要在 `prowl list` 里带上「当前目标 / 当前
agent」，可另加一个轻量 `.prowl/run.json`，而不是塞进 `workspace.json`。）

> 对非 workspace 的普通 git worktree，同一套 `.prowl/handoff/` 放在仓库根也成立——本方案以
> workspace 为中心，但机制可推广到任意 runnable target。

### 4.2 工件模板（English，供 agent 读写）

`current.md` 分两部分：**agent 维护的语义段**（人/agent 写）+ **Prowl 自动生成的机械附录**
（`prowl handoff save` 每次重算，永远新鲜）。这样「意图/决策」与「当前 diff 状态」解耦。

```markdown
<!-- .prowl/handoff/current.md -->
# Handoff

## Objective
<!-- one-paragraph task goal; stable across the whole run -->

## Current State
<!-- where things stand right now -->

## What Has Been Done
<!-- bullet list of completed steps + key decisions/dead-ends -->

## Open Questions
<!-- unresolved decisions the next agent (or human) must settle -->

## Risks / Watch Out
<!-- anything fragile, half-done, or easy to break -->

## Next Steps
<!-- ordered, concrete; the receiving agent starts here -->

## Suggested Prompt For Next Agent
<!-- a ready-to-paste kickoff instruction -->

---
<!-- BEGIN PROWL AUTOGEN — regenerated by `prowl handoff save`; do not edit by hand -->
## Context Appendix (auto)
- Generated: 2026-06-11T14:30:00+08:00
- Outgoing agent (detected): codex
- Workspace: Checkout Flow  (/Users/.../checkout-flow)
- Repos & branches:
  - app      checkout-flow   (3 files changed, +120/-14)
  - api      checkout-flow   (1 file changed,  +8/-2)
  - shared   checkout-flow   (clean)
- Changed files:
  - app/Sources/LoginView.swift
  - app/Tests/LoginViewTests.swift
  - api/handlers/auth.go
- Recent commands (best-effort): swift build; swift test
<!-- END PROWL AUTOGEN -->
```

要点：
- **语义段**由 agent 维护（它最懂意图、决策、踩过的坑），机械段由 Prowl 重算（git diff、分支、检测到
  的出让 agent、时间戳）。L1 的 `prowl handoff save` 负责重算并覆盖 AUTOGEN 区块。
- 工件**指向**而非内联——下一个 agent 的启动 prompt 只需说「读 `.prowl/handoff/current.md`」，避免
  把大段内容塞进终端输入。

### 4.3 协议（写进 workspace 的 AGENTS.md + CLAUDE.md）

Codex 读 `AGENTS.md`，Claude Code 读 `CLAUDE.md`。要让两边**原生遵守**同一协议，就在 workspace
root 同时放两份（内容相同，或一份 + 另一份 include）。建议片段：

```markdown
## Handoff protocol (this is a Prowl workspace)
- On start: read `.prowl/handoff/current.md` and `.prowl/workspace.json`. Continue from "Next Steps".
- Before you stop or hand off: update `.prowl/handoff/current.md`
  (Objective / Current State / What Has Been Done / Open Questions / Risks / Next Steps /
  Suggested Prompt). Keep it accurate enough that another agent can resume cold.
- To hand the task to the other agent, run:  `prowl handoff to claude`  (or `codex`).
  This snapshots state and launches the other agent in a new tab pointed at the handoff file.
- Never commit/push or run destructive git unless the human explicitly asks. Do not put
  secrets/tokens in the handoff file.
```

> 这一步是「让 agent 自己成为 handoff 的执行者」的关键：codex 干完自己那部分，**自己**敲
> `prowl handoff to claude`，新 claude tab 弹出、人看到。正是 Prowl overview 里「agents coordinate
> *through* Prowl」的形态。

---

## 5. 机制层：分层方案

### L0 — 纯约定（今天可用，0 app 代码）

只靠 §4 的契约 + 现成 `prowl` CLI / 自定义命令即可完成一次完整 handoff。

**手动命令序列（codex → claude）**，由出让方 agent 或人执行：

```bash
# 1) 出让方先把 .prowl/handoff/current.md 写好（按 §4.2 模板）
# 2) 在同一 workspace 新开一个 tab 跑 claude，并喂入启动 prompt
self="$(prowl list --json | jq -r '.data.items[]|select(.pane.focused==true)|.pane.id')"
wt="$(prowl list --json | jq -r '.data.items[0].worktree.id')"   # 该 workspace 的 worktree id
pane="$(prowl tab create --worktree "$wt" --json | jq -r '.data.target.pane.id')"
test "$pane" != "$self"
prowl send --pane "$pane" \
  'claude "You are taking over a task in this Prowl workspace. Read .prowl/handoff/current.md (the full handoff) and .prowl/workspace.json (repo layout), then continue from Next Steps. Ask before any commit/push or destructive git."' \
  --no-wait --json
prowl focus --pane "$pane" --json
```

反向（claude → codex）只把启动命令换成 `codex "…"`。

**绑成一个键（自定义命令，写 `~/.prowl/repo/<workspace>/prowl.onevcat.json`）：**

```jsonc
{
  "customCommands": [
    {
      "id": "handoff-to-claude",
      "title": "Hand off → Claude",
      "systemImage": "arrow.right.circle",
      "command": "claude \"Take over this workspace task. Read .prowl/handoff/current.md and .prowl/workspace.json, continue from Next Steps. Ask before commit/push.\"",
      "execution": "shellScript",          // 新 tab；也可 "split" 开分屏并排
      "closeOnSuccess": false,
      "shortcut": { "key": "j", "modifiers": ["command", "shift"] }
    },
    { "id": "handoff-to-codex", "title": "Hand off → Codex", "systemImage": "arrow.right.circle",
      "command": "codex \"Take over this workspace task. Read .prowl/handoff/current.md and .prowl/workspace.json, continue from Next Steps. Ask before commit/push.\"",
      "execution": "shellScript", "closeOnSuccess": false }
  ]
}
```

- 优点：**零 app 改动、今天可用、agent 无关**；同时是 L1/L2 的「降级形态」。
- 局限：①「写工件」全靠 agent 自觉（靠 §4.3 协议约束）；②没结构化的 run 状态，`prowl list` 看不到
  「谁在跑」；③机械附录（git diff 摘要）得 agent 自己生成或人贴。L1 把这三点补上。

### L1 — `prowl handoff` 命令 + handoff 存储 + agent 身份进 `list`（推荐核心）

把 L0 的约定固化成一等公民的命令，并补上 Prowl 能自动提供的机械上下文。

#### 5.1 新增 `prowl handoff` 子命令

```bash
prowl handoff save   [--note "…"]                 # 重算机械附录、快照 git、（可选）追加一条 note
prowl handoff to <claude|codex> [--split h|v] [--note "…"] [--no-launch]
prowl handoff status [--json]                     # 读 current.md 头部 + run 状态
```

- **`save`**：以 target 的 worktree/workspace 为范围，对每个子仓跑 `git -C <repo> status/diff --stat`，
  重写 `current.md` 的 AUTOGEN 区块（出让 agent 取自 `DetectedAgent`），并在 `log.md` 追加一行。
  不动语义段（那是 agent 写的）。
- **`to <agent>`**：先隐式 `save`（保证工件新鲜）→ 把 `current.md` 归档到 `archive/<ts>-<from>-to-<to>.md`
  → 在**同一 worktree 新开 tab（或 `--split` 开并排分屏）**跑接手 agent，启动 prompt 指向
  `current.md` → 返回新 pane id（供脚本/自动化串联）→ `log.md` 记一行。`--no-launch` 只做归档+
  记录、不启动（给人手动接管）。
- **`status`**：给人/编排一个快照：当前目标、出让/接手 agent、上次 handoff 时间、变更文件数。

启动 prompt 模板（按 agent 区分，flag 应可配置，因为 codex/claude 的 CLI 参数会演进）：

```text
claude "<kickoff>"          # 交互式，首条消息即 kickoff；人可随时介入
codex  "<kickoff>"
# <kickoff> = Take over … read .prowl/handoff/current.md & .prowl/workspace.json … continue from Next Steps …
```

#### 5.2 `prowl list` 暴露 agent 身份（小改动，价值大）

给 `pane` 增加一个可选字段 `agent`（`claude`/`codex`/…/null），来源是已有的
`PaneAgentState.detectedAgent`。这样编排（人或 agent）能直接看出「左边 codex、右边 claude」，
是 handoff 自动化的前提。

```jsonc
// prowl list --json 里每个 item 的 pane 增加：
"pane": { "id": "…", "title": "…", "cwd": "…", "focused": true, "agent": "codex" }
```

#### 5.3 实现要点（要改的文件，调研已定位）

新增一个 CLI 命令是「**5 个编辑点**」的成熟套路（与现有 `tab`/`send` 完全对称）：

1. **共享 wire 契约**（`ProwlCLIShared`，两端共享）
   - `supacode/CLIService/Shared/CommandEnvelope.swift:16` 的 `Command` enum 加 `case handoff(HandoffInput)`
     （编译器会强制你补齐 router 的 switch）。
   - `Shared/InputModels.swift` 加 `HandoffInput`（`action: .save/.to/.status`，`toAgent: String?`，
     `note: String?`，`split: …?`，`launch: Bool`，复用 `TargetSelector` 定位）。
   - 新增 `Shared/HandoffCommandPayload.swift`（返回 run 摘要 + `artifactPath` + 可选 `launchedPane`）。
   - `Shared/ErrorCodes.swift:6` 加 `HANDOFF_FAILED` 等。
2. **CLI 前端**：新增 `ProwlCLI/Commands/HandoffCommand.swift`（仿 `SendCommand`/`TabCommand`），注册到
   `ProwlCLI/Commands/ProwlCommand.swift:13` 的 `subcommands`；可在 `Output/OutputRenderer.swift` 加
   文本渲染分支。
3. **app 端 handler**：新增 `supacode/CLIService/HandoffCommandHandler.swift`（仿 `TabCommandHandler`，
   闭包注入、不直接 import 终端层），加进 `CLICommandRouter`（`CLICommandRouter.swift:8`/`:37` 的属性、
   init、`route` switch）。
4. **组合根接线**：`supacode/App/supacodeApp.swift` 的 `makeCLICommandRouter`（约 `:361`）里构造
   handler，闭包调用 `terminalManager.state(for:).createTab(...)` / `.createSplitWithInput`、读取
   `surfaceAgentStates` 的 `detectedAgent`、用 `ShellClient`/`GitRunner` 跑 `git -C … diff --stat`。
   list 加 `agent` 字段则改 `supacode/CLIService/ListCommandHandler.swift:82` + `Shared/ListCommandPayload.swift:74`。
5. **测试 + 文档**：`ProwlCLITests`（socket round-trip）；`docs/components/cli.md` + 新增
   `docs/components/handoff.md`（CLAUDE.md 要求改用户可见行为时同步 docs，并跑 `sync-docs`）；
   `make build-cli` / `test-cli-smoke` / `test-cli-integration` / `build-app`。

> handler 保持「闭包注入、不 import 终端层」的既有风格；所有 live 接线放 `makeCLICommandRouter`。
> 范围严格限制在「加命令 + list 加字段」，不顺手重命名/重构既有终端代码。

- 优点：handoff 成为可脚本化、可被 agent 调用的一等操作；机械上下文自动新鲜；编排能看到「谁是谁」。
- 局限：仍是「手动/agent 主动触发」，不自动。自动化在 L3。

### L2 — UI 集成

把 L1 的命令接到人能点的地方（都基于既有设施）：

- **命令面板（⌘P）动作**：「Hand off → Claude」「Hand off → Codex」，对当前 workspace 执行
  `handoff to`。入口仿 `CommandPaletteSupport.swift` 既有自定义命令项。
- **通知里的动作**：agent 变 **done/blocked** 时（已有通知），通知/铃铛 popover 里加一个「Hand off
  now?」按钮——这是「人离开后回来一键交接」的关键体验，正好接 §2 的 `agentEntryChanged`。
- **（可选）Handoff / Run 面板**：在 workspace 详情区显示 current.md 的头部（Objective / 当前 agent /
  Next Steps）+ 「打开 Diff（⌘⇧Y）」+ handoff log。让人一眼看清「这个 workspace 现在卡在哪、轮到谁」。

### L3 — 半自动 / 自动 hands-off（事件驱动，opt-in，强安全）

钩 `TerminalClient.Event.agentEntryChanged`（带 agent 身份 + display 状态），按策略触发自动交接。
**必须默认关闭、显式配置、带硬性安全栏**（见 §7）。几种有用 pattern：

- **Ping-pong**：A done → 自动 `handoff to B`，直到达到最大轮数或某个完成标记。
- **Reviewer**：codex 写完 → 自动开 claude 审 codex 的 diff（`claude "review the diff in this workspace…"`），
  审完把意见写回 `current.md`。
- **Escalation**：A **blocked**（卡在权限/选择 prompt）→ 不自动答，而是通知人 + 给「交给 B 试试」的选项。

安全栏（写进配置，仿前期调研的 `[safety]`）：最大自动轮数、单轮/总时长上限、总成本上限、**kill
switch**、禁止破坏性 git、检测到 blocked 不自动「替人确认」。没有这些不要上 L3——自动 ping-pong
最大的风险是无限循环烧 token。

---

## 6. 端到端示例（workspace 内 codex → claude → codex）

1. 人在 workspace "Checkout Flow" 的 tab 里跑 `codex "实现登录页响应式布局，三个仓一起改"`。
2. codex 干到一半要把 UI 细节交给 claude。它按协议更新 `.prowl/handoff/current.md`（语义段），
   然后敲 `prowl handoff to claude`。
3. Prowl：`save`（重算 AUTOGEN：app +120/-14、api +8/-2…）→ 归档上一份 → **新开一个 tab** 跑
   `claude "Take over… read .prowl/handoff/current.md…"` → 聚焦它 → `log.md` +1 行。codex 的 tab
   原样保留（可回看/回滚）。
4. claude 接手，先读 `current.md` + `workspace.json`，从 Next Steps 干；完事更新 `current.md`，
   `prowl handoff to codex` 交回。
5. 人离开期间任一方 **done/blocked**，Prowl 通知；回来在通知里点「Hand off now?」或在面板看
   `prowl handoff status` 的摘要，一眼知道「轮到谁、卡在哪、下一步」。

---

## 7. 安全边界（采纳前期调研并具体化到 Prowl）

- **不自动 commit / push / 破坏性 git**（`reset`/`clean`/删除）。handoff 只读 git 状态（`diff --stat`）。
- **不把 secrets 写进工件**：`save` 生成机械段时跳过 env / token 类内容；协议里也明确要求 agent 不写。
- **close / `--force` 仍需显式 target**：handoff 只**新增** tab/split，绝不替你关旧 pane。
- **先记状态、再切换**：`to` 一定先 `save`+归档，再启动接手方——崩了也能从工件恢复。
- **自动模式（L3）必须显式开启 + 带安全栏**，且**遇到 blocked 不替人确认**（那正是需要人的信号）。
- **self-pane 保护**：agent 调 `prowl handoff to` 时新建 pane，天然不会打到自己；脚本路径仍按
  CLI skill 的 `self_pane` 习惯排除自身。

---

## 8. 推荐落地顺序 & 验收

| 步 | 做什么 | 验收 |
|----|--------|------|
| **1（先做，0 代码）** | 冻结 §4 工件模板 + 协议片段；在一个真实 workspace 放好 `.prowl/handoff/` + AGENTS.md/CLAUDE.md；用 L0 命令/自定义命令跑通一次 codex↔claude 往返 | 能完成一次手动往返；接手方仅凭 `current.md` 就能冷启动续上 |
| **2** | 实现 `prowl handoff save/to/status` + `prowl list` 加 `pane.agent` | `prowl handoff to claude` 自动 save+归档+开 claude tab 并返回 pane id；`prowl list --json` 能区分 codex/claude；CLI 测试 + docs 同步通过 |
| **3** | 命令面板动作 + 通知「Hand off now?」（+ 可选面板） | 人离开后回来能一键交接；面板/`status` 能看清当前 run |
| **4（可选）** | L3 自动 hands-off + 安全配置 | 默认关；开启后能跑有界 ping-pong/reviewer，触顶/kill 能停 |

---

## 9. 开放问题 / 风险

- **工件可靠性**：语义段全靠 agent 自觉写。缓解：协议明确 + `save` 自动补机械段 + 面板让人随时检查。
- **大 diff / 长输出**：机械附录用 `--stat` 而非全文；启动 prompt 指向文件而非内联。
- **多任务并存**：一个 workspace 多个并行子任务时，单 `current.md` 不够——可加 `--run <id>` 维度，
  但建议第一版保持「一 workspace 一活跃 handoff」，不过早复杂化。
- **agent CLI 参数差异**：`claude`/`codex` 的启动/续接 flag 会演进（交互 vs `-p`、是否 resume 会话）。
  启动 prompt/命令应**可配置**（像自定义命令那样），不写死。
- **OSC 133 / capture 限制**：handoff 启动用 `--no-wait`（交互式 agent 不会「命令结束」）；要读接手
  方屏幕用 `read --wait-stable`，别用 `--capture`。
- **L3 循环风险**：自动 ping-pong 可能无限互踢烧 token——必须有最大轮数 + 成本/时长上限 + kill switch。
- **静态 vs 动态边界**：run 状态别塞进 `workspace.json`；要进 `prowl list`/面板就单列 `.prowl/run.json`。

---

## 附录 A：L1 要改的文件清单（实现时以代码为准）

- 共享：`supacode/CLIService/Shared/CommandEnvelope.swift`、`InputModels.swift`、
  新增 `HandoffCommandPayload.swift`、`ErrorCodes.swift`、（list 改）`ListCommandPayload.swift`。
- CLI：新增 `ProwlCLI/Commands/HandoffCommand.swift`、改 `ProwlCLI/Commands/ProwlCommand.swift`、
  `ProwlCLI/Output/OutputRenderer.swift`。
- app：新增 `supacode/CLIService/HandoffCommandHandler.swift`、改 `CLICommandRouter.swift`、
  `supacode/App/supacodeApp.swift`（`makeCLICommandRouter`）、（list 改）`ListCommandHandler.swift`。
- 测试/文档：`ProwlCLITests/*`、`docs/components/cli.md`、新增 `docs/components/handoff.md`。

## 附录 B：现状代码索引（关键 file:line）

- Workspace 模型：`supacode/Domain/ProjectWorkspace.swift`（`ProjectWorkspace` / `ProjectWorkspaceRepositoryEntry` / `load(from:)`）。
- Workspace 作为 Repository：`supacode/Domain/Repository.swift:48,62,80`（`workspace` / 强制 `.plain` / `isWorkspace`）。
- Workspace 终端 cwd = root：`Features/Repositories/Reducer/RepositoriesFeature+StateQueries.swift:30`。
- Agent 识别表：`supacode/Infrastructure/AgentDetection/AgentClassifier.swift:3`（claude/codex 名）。
- Agent 屏幕启发式：`supacode/Infrastructure/AgentDetection/ScreenHeuristics.swift:58`（claude）/`:80`（codex）。
- Per-pane agent 身份 + 状态：`supacode/Domain/AgentDetection/PaneAgentState.swift:3,24`。
- 状态变化事件：`supacode/Clients/Terminal/TerminalClient.swift:69`（`agentEntryChanged`）；接线 `WorktreeTerminalManager.swift:269`。
- CLI list 响应（无 agent 字段）：`supacode/CLIService/Shared/ListCommandPayload.swift:13,74`；构造 `ListCommandHandler.swift:82`。
- 终端注入命令：`supacode/Clients/Terminal/TerminalClient.swift:19`（`createTabWithInput`）/`:27`（`createSplitWithInput`）/`:38`（`insertText`）。
- 低层写入 surface：`supacode/Infrastructure/Ghostty/GhosttySurfaceBridge.swift:72`（`sendText`/`sendCommand`）。
- 自定义命令模型/执行：`Features/Settings/Models/UserRepositorySettings.swift:31`；`Features/App/Reducer/AppFeature.swift:666`。
- CLI 加命令的 5 编辑点：`CommandEnvelope.swift:16` / `ProwlCommand.swift:13` / `CLICommandRouter.swift:37` / `supacodeApp.swift:361` / `ErrorCodes.swift:6`。
