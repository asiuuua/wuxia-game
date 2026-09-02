# 多 AI 协同 SOP 差异报告（大厂标准 vs 现有机制）

> 生成日期：2026-09-02
> 背景：用户贴了一份"武侠 CRPG 多 AI 协同开发 风险预防&安全隔离机制（大厂标准）"，
> 要求评估**相对我们已落地的 `docs/多AI协同机制_SOP.md` 还差什么、哪些对你这个单机 Godot 项目是过度设计**。
> 用户定位：真实新手开发，设计/架构/维护全靠多 AI 协同完成 → 本报告的"怎么整合"由 AI 侧给出可执行建议，用户拍板即可。
> 结论：**不重复造轮子**——90% 已覆盖，只缺 4 条零成本文档条款 + 3 条值得建的机制；飞书台账/硬分支/网游外壳三类属过度设计，裁剪。

---

## 〇、一句话结论

| 用户贴的大厂条款 | 我们现状 | 处置 |
|---|---|---|
| 角色权责 + 禁止操作 | 已有 RACI + 红线，但禁止操作散落 | **补（P0）**：合并成列 |
| 分支规范 / 禁直推 main / 合并评审 | 仅把分支列为可选项，目前全在 `master` 直推 | **补（P1/P2）**：采纳命名 + 大改动评审 |
| commit 备注规范 | 已有 `[模块]` 前缀 + 窗口署名 | 已有，加 `#bugID` 关联 |
| 文件类型归属（脚本/tscn/csv 分人） | 已有主权范围 | 已有 |
| 模块只暴露接口、内部私有 | 有主权 + 契约总表，缺代码级明写 | **补（P0）**：一条规则 |
| 双闸门 + 冒烟 | 完全覆盖 GATE1/GATE2 | 已有 |
| 功能开关隔离（CSV 开关） | **缺** | **补（P1）**：轻量 `feature_flags.json` |
| 资源/代码解耦 Live-Ops | 已有"数值全进 JSON" | 没必要重复 |
| 回滚保护（标签 + 资源备份） | 有回滚概念，无纪律 | **补（P1）**：里程碑 tag |
| 标准工作流 | 已有接入 + 流程 | 已有 |
| 踩坑清单 | 基本覆盖 | **补（P0）**：同 tscn 单窗口 |
| 故障应急 | 已有追溯 + 回滚 | **补（P0）**：严重阻塞先回滚首响 |

---

## 一、需要补充的条款（详细 + 怎么整合到 AI 工作流）

### P0 — 零成本，纯文档条款（建议立刻并入 SOP §1/§5/§7/§9）

**① 角色"禁止操作"列化**
把现有 §1 的"主权范围/核心职责/留痕要求"三列，扩成四列，新增**禁止操作**列（直接来自大厂表）：

| 角色 | 禁止操作（铁则） |
|---|---|
| PM | 不许改 GDScript / 不许改配置表 / 不许改美术资源 |
| 架构师 | 禁止直接写业务逻辑；不直接改 UI/战斗数值，只定规则与接口 |
| 业务程序员 | 禁止改 UI 控件布局 / 禁硬编码文案数值 / 禁直改 tscn 节点 |
| UI 前端 | 禁止改战斗逻辑 / 禁改配置表 / 禁改写业务服务内部代码 |
| 后端（数据） | 禁止在脚本里写死数值，只动 JSON |
| 运维 Ops | 不改动业务代码，只校验/备份/复现 |

> **怎么整合**：这是文档条款，AI 改任何文件前先看自己角色的"禁止操作"列；跨列即触发 handoff + 变更通告。无需新工具。

**② 模块边界代码级规则（明写"内部私有"）**
在 §0 主权边界补一条硬规则：
> 业务模块（RefCounted 服务）只通过**公开方法**对外暴露能力；内部 state 用私有 `var`；跨模块**只允许调用公开方法或走 EventBus**，**禁止直接读写对方内部数组/字典/状态列表**。
> 例：战斗对外只暴露 `CombatService.start_battle(cfg_id)`，外部不得直接碰 `_actors`/`_states`。

> **怎么整合**：架构师在"合并评审"（见 P1③）时按此规则查 diff；契约总表 `gen_contract.gd` 已能检测接口漂移，叠加此规则即可。

**③ 同一 `.tscn` 同刻只许一个窗口改 + 细粒度拆分**
在 §9 红线补：
> 同一 `.tscn` 场景文件，同一时刻只允许一个 AI 窗口编辑；大 UI 拆成独立细粒度 prefab（背包/对话/HUD 各自独立 .tscn），每人只动自己的预制。

> **怎么整合**：用现有 `handoff.py` 登记"我正在改 `X.t scn`"（issue 类型 `lock_file`），别人 `handoff dashboard` 一眼看到，避免 Git 冲突。本项目 B 路线 .tscn 迁移已把 21 个屏幕拆开，天然契合。

**④ 故障首响：严重阻塞先回滚保 master 可用**
在 §7 追加盖一条：
> 接到**严重阻塞 BUG**（master 跑不起来/主流程崩）→ **第一动作不是修，是先回滚到上一个稳定 tag/commit 保 master 可用**，再在修复分支复现+修+走双闸门，最后合并。

> **怎么整合**：配合 P1② 的里程碑 tag 才有得回滚。命令草图：`git tag` 看稳定点 → `git checkout <stable_tag>` 确认可用 → 修复分支 `fix/xxx` 上改 → 双闸门过 → 合并。

**⑤ commit / changelog 带 `#bugID`**
现有 handoff issue ID（如 `fed3f00da584`）即 bug ID。`change_log.py add` 的 `--ref` 已能填，建议在 §2 明确：**修 BUG 的 commit message 与 changelog 行必须带 `#<handoff_issue_id>`**，便于一键反查。

---

### P1 — 值得建的机制（建议建骨架，AI 评判后用户拍板）

**① 轻量功能开关 `feature_flags.json`（防半成品污染主版本）**
- 文件：`data/configs/feature_flags.json`
  ```json
  {
    "enable_backstab": false,
    "enable_new_dialog_system": false,
    "enable_sect_war": false
  }
  ```
- 访问器（加在 `ConfigManager.gd`）：
  ```gdscript
  var _feature_flags: Dictionary = {}
  func is_feature_enabled(key: String) -> bool:
      return bool(_feature_flags.get(key, false))
  # _ready 里 load 该 json（走现有 JSON 加载约定）
  ```
- 用法：未完成大模块代码可以提交，但外层 `if is_feature_enabled("enable_xxx"):` 包住，**开关 false 时整段不执行**，主版本永远可跑。开发完翻 true。
- **怎么整合**：架构师审批新模块时，要求"带开关提交"；属共享地基改动，须出变更通告（符合现有 §0 铁律）。

**② 里程碑版本标签 + 资源备份纪律**
- tag：`git tag -a v0.9.2-audit-clean -m "P2全清+双闸门53/0"`（每个稳定里程碑一个）。
- 资源备份：关键二进制（.tscn/.import/立绘）**改动前先 commit**（已强制），git 本身就是备份；额外建议：大 UI 重构前跑一次 `git stash list`/确认工作树干净，避免未提交资源丢失（注意我们铁律禁 `git stash -u`）。
- **怎么整合**：PM/运维在每次"整树双闸门全绿 + 集成 push"后打一个 tag，写进 changelog「集成 push」行。无需新脚本，一条命令。

**③ 大改动 / 跨主权合并评审**
- 规则：以下三类合并进 master 前，**必须另一个 AI 窗口（架构师角色）过一遍 diff + 跑全量 GATE2**：
  1. 动共享地基（EventBus/ConfigManager/core/enums/screens.json/strings.csv/GameManager/GameState）
  2. 跨主权改别人模块
  3. 动 `gen_contract.gd` 契约 或 单次改动 > 8 文件
- **怎么整合（单分支模型）**：开 `review/<topic>` 分支 → 另一个窗口 `git diff master...review/<topic>` + 全量 GATE2 → 通过后 PM `commit_queue flush` 合入 master。多分支模型则直接 PR。

---

### P2 — 按需（团队壮大再上）

**① `feature/fix/ui` 分支命名落地**：非琐碎改动开分支，琐碎改动仍可在 master 署名直推（当前模型）。命名规范写进 §6。
**② 架构师静态检查清单固化**：把"越权跨模块 / 破坏事件总线 / 硬编码数值 / 违背数据驱动"四条固化为 §4 自审核清单的勾选项。

---

## 二、可以不要 / 该裁剪的（避免过度设计）

| 大厂条款 | 为什么对你过度 | 替代 |
|---|---|---|
| 用飞书文档做任务台账 | 外部依赖 + 不可机器 grep，正是"看之前改了什么"的短板 | 权威台账留 in-repo `docs/更改日志.md` + `handoff.py`（已能 `query`） |
| 强制每 AI 独立分支 + 每次合并必审 | 1–3 个 AI 的单机项目，开销 > 收益 | 按改动规模选"分支 vs 署名直推"（见 P2①/§6） |
| 网游 SCM 外壳（服务器/DLC 热更/Live-Ops 通道） | 单机体量用不到 | 只保留"数值外置 JSON"原则，不抄基建 |

> 飞书/canvas 文档**可以**作为给人看的架构总览补充，但**不是**机器可追溯的权威台账——调试 BUG 时仍以仓库内 changelog 为准。

---

## 三、整合到"小白 + 多 AI"工作流的总方案（AI 侧建议）

你作为真实新手，只需记住三件事，其余交给 AI 自律 + 工具：

1. **每个 AI 窗口启动**（一次性，AI 自动做）：
   `git config user.name "AI-<窗>"` → 读 `契约总表.md`+`SOP`+`MEMORY.md` → 装 `change-tracking` skill → `change_log.py query --module <自己的模块>` 热身。
2. **改东西的标准动作**（AI 自动遵守，你不用管）：
   改前查 changelog 防回归 → 改中只动自己主权（看"禁止操作"列）→ 改后 `change_log.py add` 登记 + 跑双闸门 → 通过才 commit（带 `[模块]`+署名+`#bugID`）。
3. **出 BUG 的标准动作**：先 `change_log.py query` + `git log` + `handoff dashboard` 定位是不是别人刚改的回归；严重阻塞先回滚保 master（见 P0④）→ 修复分支走双闸门 → 合并。

**AI 评判结论**：P0 五项零成本、立刻并入；P1 三项（功能开关/标签备份/合并评审）建议建骨架，等下个大模块开发时自然落地；P2 两项团队壮大再上。飞书台账/硬分支/网游外壳**不采纳**。

---

## 四、附：现有工具链（已落地，本报告不重复建）

| 工具 | 命令 | 用途 |
|---|---|---|
| 更改日志 | `tools/change_log.py add/notice/query/backfill` | 登记 + 按模块/关键词查近期改动 |
| 隐患传递板 | `tools/handoff.py issue/scan/claim/done/followup/close/dashboard` | 跨窗口派单/文件锁，状态机 |
| 提交队列 | `tools/commit_queue.py add/flush/list` | 精确提交（禁 `-A`） |
| 双闸门 | GATE1/GATE2 | 零回归门禁 |
| 契约总表 | `tools/gen_contract.gd` | 接口漂移检测 |

> 本报告本身尚未并入 `多AI协同机制_SOP.md`（按用户要求"先不整合"）。待用户拍板后，由 AI 把 §一 的 P0/P1 并入对应章节，并建 `feature_flags.json` 骨架 + tag 纪律。
