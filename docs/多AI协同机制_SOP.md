# 多 AI 协同不出问题机制（SOP）

> 适用：单 git 分支（master）+ 多个 AI 窗口并行开发 Godot 武侠工程。
> 目标：**所有修改留痕 · 每步自查自审 · BUG 可追溯到 AI 窗口 · 避免"改半天是小改动引起的回归"**。
> 配套工具：`tools/change_log.py`（更改日志）· `tools/handoff.py`（隐患传递板）· `tools/commit_queue.py`（提交队列）· 双闸门 GATE1/GATE2 · `tools/gen_contract.gd`（契约总表）。

---

## 0. 总原则（五道防线）

1. **主权边界**：每个窗口只改自己主权模块；碰别人/共享地基 → 走 handoff + 变更通告，绝不硬改。
2. **共享地基冻结**：EventBus / ConfigManager / `core/enums/*` / `screens.json` / `strings.csv` / `GameManager` / `GameState` 改动须架构师认可 + 写变更通告。
3. **所有动作留痕**：每次修改进 `更改日志.md`；大改动额外写 `变更通告_*.md`；commit 带窗口署名 + `[模块]` 前缀。
4. **每步双闸门**：GATE1（零解析/编译错误）+ GATE2（单测零 ✗）通过才允许 commit。
5. **调前先查**：任何 BUG 先查更改日志 + `git log` + handoff 板，确认不是别人刚改的回归，再深入。

---

## 1. 角色与职责（RACI）

| 角色 | 主权范围 | 核心职责 | 留痕要求 |
|---|---|---|---|
| 架构师 Architect | 共享地基 + 契约总表 | 维护共享地基冻结清单；审批跨主权/共享地基改动；定义接口契约 | 共享地基改动必须出**变更通告** |
| 项目经理 PM（集成窗口） | 提交队列 / handoff / 双闸门终验 / 统一 push | 跑 `commit_queue flush` + `handoff dashboard`；整树双闸门全绿后统一 push 远端；冲突协调；追溯总入口 | 每次集成在 changelog 登记一行「集成 push」 |
| 程序员（后端逻辑 services） | `services/**`（RefCounted） | 业务服务；改前查契约总表 + changelog；改后跑对应单测 | `change_log add` + 跑 GATE2 相关套件 |
| 前端（UI/scenes） | `scenes/ui/**` + `data/configs/ui/**` | .tscn + 屏幕栈；注意 UIManager 缓存屏契约 | `change_log add`；动屏幕栈须登记 |
| 后端（数据/configs） | `data/configs/**`（JSON 数值） | 数值全进 JSON；改 JSON 同步契约总表 | `change_log add`；注意 town.json 类"间接引用"陷阱 |
| 后期运维 Ops（工具/CI） | `tools/**` + `.gitignore` + 双闸门脚本 | 维护 `change_log.py`/handoff/commit_queue；定期跑 `security_selftest.py`；管 push 节奏 | 工具改动跑 `py_compile`；changelog 登记 |

> 窗口署名：每个 AI 窗口启动即 `git config user.name "AI-<窗口>" user.email "ai-<窗口>@local"`，使 `git log` 与 changelog 的 `author` 列 = 责任窗口，**禁匿名提交**。

---

## 2. 留痕机制（所有修改动作）

- **每次修改** → `python tools/change_log.py add --commit <sha> --module <模块> --scope <范围> --what "<改了什么>" --impact "<影响/风险>" --ref "<派单/通告>"`
  - `--module`：顶层目录（如 `services`/`scenes`/`autoload`）；`--scope`：含子路径（如 `scenes/gameplay/battle`），便于按文件 grep。
- **共享地基 / 跨主权 / 大改动** → 额外 `python tools/change_log.py notice --title "..." --module ... --what ... --impact ...`，生成 `docs/变更通告_YYYY-MM-DD_主题.md`（含回滚方案 + 协同方需知），并在 changelog「关联」列指向该通告。
- **commit 纪律**：精确 `git add <文件>`（禁 `-A`）；message 带 `[<模块>]` 前缀 + 窗口署名；不通过双闸门绝不 commit。
- **板（handoff/commit_queue）**：append-only，落 `.workbuddy/`（gitignored 工作区）；push 前 PM 把关键项汇总进 changelog。

---

## 3. 自查（Self-check）— 每个 AI 改完自己跑

| 闸门 | 命令 | 判绿 |
|---|---|---|
| GATE0 | `python tools/lint_mouse_filter.py --tier default` | 0 高危发现（专抓「按钮装饰子节点误写 mouse_filter=STOP 静默吞点击」这类**无报错** BUG；细节见 `docs/跨模块BUG修复机制.md` §6） |
| GATE1 | `godot --headless --path "D:/武侠游戏" --quit` | rc=0 且 **0** SCRIPT/PARSE/COMPILE ERROR |
| GATE2 | `godot --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn` | rc=0 且 **0 ✗** 且「套件：失败 0」（含 `test_ui_mouse_filter.gd` 静默拦截运行时断言） |

- 改了某服务 → 跑对应单测套件；改了 UI → 跑 `tests/ui/*` smoke；改了契约 → 重跑 `gen_contract.gd` + **全量** GATE2。
- 工具改动 → `python -m py_compile tools/*.py`；工作室工具 → `security_selftest.py`（15 断言）。
- 验证须 **unsandboxed** 跑（`.godot` 缓存 + 真实文件系统）；ROOT 必须 Windows 风格 `D:/武侠游戏`。

---

## 4. 自审核（Self-review）— 提交前

1. **diff 自检**：grep 特殊字符（反引号 `` ` `` 等）、缩进错乱、是否误删被引用文件（`git checkout HEAD -- <file>` 可救 tracked 误删）。
2. **主权检查**：是否碰了别人/共享地基？是 → 出变更通告 + handoff issue，不要硬改。
3. **回归检查**：跑 **全量** GATE2（不只自己改的套件），确认零 ✗、失败 0。
4. **留痕检查**：changelog 行已 `add`？共享地基有变更通告？commit 有 `[模块]` 前缀 + 窗口署名？

---

## 5. 追溯（Traceability）— BUG 是哪个 AI 造成的

接到 BUG，按序执行（**先查后改**，避免重复劳动）：

1. `python tools/change_log.py query --module <嫌疑模块>` 或 `--keyword <文件名>` → 看最近改了什么。
2. `git log -- <文件>` → 看署名 author/窗口 与 commit 时间。
3. `python tools/handoff.py dashboard` → 看是否有相关派单/隐患。
4. 命中某 commit → 在 changelog 该行「关联」注明 **「回归自 `<commit>`」**，并 `handoff issue` 给责任窗口追因。

> 责任归属 = changelog `author` 列 + `git log` author/窗口。**禁匿名提交**是追溯的前提。

---

## 6. 没有 BUG 是否要上 git？（commit / push 节奏）

- **commit（本地）**：凡是自查 + 自审核 + 双闸门**通过**的改动，**必须 commit**（留痕、防丢失、可回滚）。不通过的绝不 commit，留在工作树修。
- **push（远端）**：单分支多 AI **不要各自盲目 push**（互相覆盖/冲突）。节奏二选一：
  - A（推荐，单分支）：各窗口本地精确 commit → PM/集成窗口在整树 GATE1+GATE2 全绿后统一 `git pull --rebase` + push。
  - B（多分支）：各窗口走 `feature/<窗口>-<主题>` 分支，各自 push 后由 PM 合并到 master。
- **结论**：**无 BUG 的代码一定要进 git（commit）；是否 push 远端由集成节奏决定——本地必交，远端统一交。**

---

## 7. 防"改半天是小改动引起的"——调试纪律（最重要）

- 任何人接到 BUG，**先执行 §5 追溯四步**，确认不是回归再深入。
- 反例（本工程真实发生）：误删 `town.json`（判为死数据）→ GATE2 退化 3 失败 → 查 changelog/`git log` 立刻定位其为战术底图几何依赖、非死数据 → `git checkout` 恢复。若没日志，可能花半天去查战斗/`grid` 代码。
- 正例：先 `query --module scenes/gameplay/town` → 看到近期改动 → 直接定位。

---

## 8. 工具链清单

| 工具 | 命令 | 用途 |
|---|---|---|
| 更改日志 | `tools/change_log.py add/notice/query/backfill` | 登记每次修改 + 按模块/关键词查近期改动 |
| 隐患传递板 | `tools/handoff.py issue/scan/claim/done/followup/close/dashboard` | 跨窗口 BUG/依赖派单，状态机 open→claimed→done→followup→closed |
| 提交队列 | `tools/commit_queue.py add/flush/list` | 窗口入队就绪文件，PM 精确提交（禁 `-A`） |
| 双闸门 | GATE1/GATE2（见 §3） | 零回归门禁 |
| 契约总表 | `tools/gen_contract.gd` | EventBus/接口漂移检测，改契约后重跑 |
| 工作室安全 | `tools/security_selftest.py` | 15 断言，工具改动后必跑 |

---

## 9. 红线（违反即回滚/告警）

- 禁 `git add -A`；禁改共享地基不写变更通告；禁匿名/无 `[模块]` 前缀 commit。
- 禁未过双闸门就 commit；禁各窗口盲目 push 互覆盖；禁碰他人主权代码不 handoff。
- 禁"接到 BUG 不查日志直接改"——须先走 §5 追溯四步。

---

## 10. 新窗口接入清单（一次性）

1. `git config user.name "AI-<窗口>" user.email "ai-<窗口>@local"`。
2. 读 `docs/契约总表.md` + `docs/多AI协同机制_SOP.md` + `MEMORY.md`（主权边界）。
3. 装 change-tracking skill（自动遵守本 SOP）。
4. 首次改动前先 `change_log.py query --module <你的模块>` 熟悉近期上下文。
5. **开窗口第一句**：把 `docs/AI协同启动卡.md` 里的「启动口令」复制粘贴给 AI（见 §11）。

---

## 11. 执行保障：怎么让 AI 真的遵守（四层 Enforcement）

光写文档不够——必须让"遵守"成为**默认行为**而非"靠自觉"。本项目用四层叠加，越往下越不依赖 AI 意志力：

### 第 1 层 · 项目记忆自动注入（最强软约束，已生效）
- 每次 AI 开会话，`MEMORY.md` 的「多 AI 协同」铁律**自动注入上下文**（系统级）。AI 看不到"我没学过规矩"的借口。
- 铁律 1 留痕 / 铁律 2 调前先查 / 铁律 3 提交节奏 / 铁律 4 门禁非绿即阻断，均在 MEMORY.md。

### 第 2 层 · change-tracking skill（任务级触发，已生效）
- 凡"改文件 / 提交 / 修 BUG"任务，AI **应加载** `change-tracking` skill（描述已写明触发条件）。
- skill 给的是**可执行命令**：`change_log.py add/query/notice`、`handoff.py dashboard`、双闸门跑法。不是空话。

### 第 3 层 · 用户启动口令（人肉点火，关键缺口已补）
- **这是让第 1/2 层真正生效的开关**：用户每次开新窗口，复制 `docs/AI协同启动卡.md` 的口令粘进去。
- 口令干两件事：① 命令 AI 读 MEMORY + 加载 skill；② **指定本窗口名**（决定 `git` 署名 → 追溯归谁）。
- 没有这步，AI 可能"没被提示"就开工 → 漏登记。口令是给用户的最低成本操作。

### 第 4 层 · git pre-commit 钩子（机器级硬约束，已生效，最重要）
- **不靠 AI 想不想**——提交时机器自动扫 `mouse_filter=STOP` 的按钮装饰子节点（静默吞点击 BUG），违规则**直接拦下提交**。
- 钩子：`tools/hooks/pre-commit`（安装：`python tools/install_hooks.py`）。
- 配套：`tools/lint_mouse_filter.py`（GATE0 扫描器，已加 `--files` 模式只查本次提交文件）。
- 应急绕过：`git commit --no-verify`（**仅应急，禁止常规使用**——绕过即放弃机器守卫）。

### 四层怎么配合（给用户的白话）
> 你开窗口 → 粘启动口令（第 3 层，点火）→ AI 读记忆+加载 skill（第 1/2 层，知道规矩）→ 干活、登记、跑门禁 → 提交时钩子兜底（第 4 层，忘了也被机器拦）。
> 哪怕第 1/2/3 层全失效，第 4 层仍能把"静默吞点击"这类最阴的 BUG 挡在仓库外。

### ⚠ 已知冗余（待清理）
- `tools/check_mouse_filter.py` 是另一个 AI 窗口写的**重复扫描器**（与 `lint_mouse_filter.py` 同目的、同背景、实现略不同）。
- 已选 `lint_mouse_filter.py` 为唯一真源（已接 GATE0 + pre-commit 钩子 + SOP）。`check_mouse_filter.py` 暂未提交、未接线，**待其责任窗口确认后删除或合并**，避免两个扫描器让后续 AI 困惑。

### 第 4 层钩子的已知隐患与缓解（诚实清单，用户问"会不会有隐患/假性BUG"）
机器守卫不是万能，已知风险与对策如下（均已落地下文对策）：

| 隐患 | 严重度 | 对策（已做/待做） |
|---|---|---|
| **范围太窄→假性安全感**：只拦 `mouse_filter=0` 按钮装饰子节点；全屏 STOP 遮挡、`z_index`、`gui_input` 重写等其它静默输入 BUG 不拦 | 高 | 已在 `docs/跨模块BUG修复机制.md` 写明"钩子≠通用 UI 安全网"；其它类靠 GATE2 `test_ui_mouse_filter.gd` + 人工拾取模拟器兜底。**禁止把"钩子绿"当"界面无输入 BUG"** |
| **钩子不在 git→换机/新克隆静默消失** | 高 | `install_hooks.py` 已装；**换机/新克隆后必须再跑一次**（写进启动卡 + 本 SOP §10）。沙箱/CI 同理 |
| **install_hooks 覆盖已有钩子** | 中 | ✅ 已修：装前先备份为 `pre-commit.bak`，不再静默删 |
| **`--no-verify` 绕过全废** | 中 | 红线禁止常规使用；提供白名单逃生口（见下）替代"整体绕过" |
| **假性 BUG（误报）** | 低 | default 层只拦"显式 `=0` 装饰子节点"，误报仅发生在"确有意的 STOP"；✅ 已加白名单 `tools/lint_mouse_filter.allow` 精准豁免单文件，**不必 `--no-verify`** |
| **Python 路径硬写→变动后静默失效** | 中 | 钩子有 fallback（`python3`/`python`），再无则**跳过放行**（失败开放）；后果是守卫静默消失。生产机请确保 managed python 或系统 python 在 |
| **只扫本次暂存文件（commit 级盲区）** | 低 | 历史违规下次动到该文件才暴露；定期跑 `lint_mouse_filter.py --tier strict` 全量审计补盲 |
| **rebase/amend 会重跑钩子** | 低 | 历史已合规，正常无碍；若 rebase 遇阻，先用白名单/修复，勿一律 `--no-verify` |

**白名单逃生口用法**（替代 `--no-verify`，守住整体守卫）：
- 确有一处**有意的** `mouse_filter=0`（如按钮内嵌可点子图标），把该 `.tscn` 路径加入 `tools/lint_mouse_filter.allow`（支持相对路径/绝对路径/纯文件名，`#` 注释）。
- 加白名单 = 承认该文件"暂不修的静默拦截风险"，只应在确属有意时使用；普通手误请用 `mouse_filter = 2`(IGNORE) 真正修复。

### ⚠ 给其他 AI 窗口的防绕路说明（用户最担心的"误拦导致绕远路"）
本守卫**只做一件事**：提交时扫你改动的 `.tscn` 文件里 `mouse_filter` 这一行文本，看按钮下的装饰子节点有没有误写成 `STOP(0)`。它**不碰、不运行、不修改任何游戏代码**——战斗、背包、存档、技能、地图逻辑全都不归它管。请记住：

1. **它不影响战斗/背包等任何模块的功能开发**。它不拦截 GDScript、不改数值、不引入依赖。把它理解成"Word 的拼写检查只查一个词"，而不是"会改变你程序的引擎"。
2. **遇到拦截 = 改 `.tscn`，不是改游戏逻辑**。钩子提示"发现静默吞点击"时，正确做法只有两种：把那个装饰子节点改成 `mouse_filter = 2`（IGNORE 穿透），或确有意的 STOP 就把它路径加进 `tools/lint_mouse_filter.allow`。**绝不要为了过钩子去动战斗/背包/其它代码**——那才是真的绕远路、越走越偏。
3. **它是透明的，谁都看得到**。拦截信息用中文直接打在 `git commit` 输出里，任何 AI 跑 commit 都会看见，不会"检测不到"。历史来龙去脉可查 `change_log.py query --module tools` 和 `docs/更改日志.md`。
4. **唯一会"误拦"的路径已被堵死**（见上表 `install_hooks 覆盖` + 本次 `875d391` 加固）：lint 自身崩溃改为失败开放，绝不冒充违规拦你。剩下的是"漏检"类（换机消失/`--no-verify`/只扫暂存），那些只会让守卫失效，**不会让你正常提交被卡**。
> 一句话：这个机器约束是 UI 静默卡死这一类 BUG 的**自动门**，对战斗/背包等功能**零副作用**；遇到它只调界面文件，别碰游戏逻辑，就不会绕远路。
