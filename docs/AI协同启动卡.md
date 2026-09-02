# AI 协同启动卡 · 各窗口工作指令（多 AI 并行开发必读）

> 用途：你（用户）每开一个 AI 窗口（新对话）让它干活前，在下面「各窗口启动口令」找本次要干的
> 那块，整段复制粘进新窗口第一句话。它让 AI 自动遵守多 AI 协同纪律，并决定"这次改动算谁的"
> （署名 = 追溯归属）。其余守卫（项目记忆注入 / change-tracking skill / 机器 pre-commit 钩子）
> AI 自己会跑、机器会兜底，你不用管。

---

## 0. 怎么用这张卡（三步）

1. 看下表，确定这次窗口属于哪一类（填 `<窗口名>` 的依据）。
2. 在「§2 各窗口启动口令」里复制**对应那块**（已帮你把窗口名填好）。
3. 粘进新窗口第一句话 → 让它干活。

> 不用懂技术，照抄即可。换窗口就换一块粘。

---

## 1. 窗口一览（主权 / 署名 / 一句话职责）

| 窗口名 | git 署名 | 主权范围 | 一句话职责 |
|---|---|---|---|
| 战斗 | `AI-战斗` | `scenes/gameplay/battle`、战术战棋逻辑+视图、`BattleScene` | 回合制+自动战斗；动接口先查契约总表 |
| 背包 | `AI-背包` | `services/inventory`、背包数据层、道具/装备 | 道具增删改查与满溢出；别误删被间接引用的 JSON |
| 结缘 | `AI-结缘` | 结缘/剧情/婚恋模块 | 休息睡觉推进天数、propose 聘礼锁定 |
| UI | `AI-UI` | `scenes/ui`、`data/configs/ui`、`UIManager`、`.tscn` | 界面与屏幕栈；遇守卫只改 tscn 别动逻辑 |
| 数据 | `AI-数据` | `data/configs`（JSON 数值） | 数值全进 JSON；改完同步契约总表 |
| 工具 | `AI-工具` | `tools`、`.gitignore`、双闸门脚本 | 维护 change_log/handoff/commit_queue；别裸接 `--strict` |
| 测试 | `AI-测试` | `tests/unit`、`tests/ui` | GATE2 零 ✗；测试绝不 emit 真实信号、零副作用 |
| 音频 | `AI-音频` | `audio`、音效/音乐资源与加载 | 新资源必须 `editor --quit` 重导；exists 失败会静默跳过 |
| 工作室 | `AI-工作室` | `tools/desktop_studio`（游戏侧零依赖） | 外部调教工具；严守安全红线 |
| PM/集成 | `AI-PM` | 提交队列/handoff/双闸门终验/统一 push | 整树全绿后统一 push；冲突协调；追溯入口 |
| 审计核查 | `AI-审计` | 跨模块只读审查 + 写回 `docs/backlog.json`（不碰游戏逻辑代码） | 用专业测试标准做单模块/全盘/关联架构审查，产出隐患/漏错/建议并归类待办 |
| 架构 | `AI-架构` | `docs/架构方案*`、`docs/契约总表.md`、`docs/全角色工程手册*`、`tools/desktop_studio/scan_deps.py`、`projects/wuxia_game.yaml` 的 `ai_context` | 五层架构铁律 / 单向依赖 / 依赖图审查 / 共享地基变更 / 架构演进 |

> **共享地基（谁都别硬改）**：`EventBus` / `ConfigManager` / `core/enums/*` / `screens.json` /
> `strings.csv` / `GameManager` / `GameState`。要改须架构师认可 + 出变更通告，走 handoff 派单。

---

## 2. 各窗口启动口令（复制对应的那块，粘到新窗口）

### 🔥 战斗窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「战斗」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律（留痕 / 调前先查 / 提交节奏 / 门禁非绿即阻断）。
2. 改文件 / 提交 / 修 BUG 前，加载 change-tracking skill 按其命令执行。
3. 改前：change_log.py query --module scenes/gameplay/battle（或 --keyword <文件名>）确认不是别人刚改崩的回归。
4. 改完：change_log.py add 登记；碰共享地基 / 跨主权额外 change_log.py notice 出变更通告。
5. 提交前：双闸门全绿——GATE1（godot --headless --path "D:/武侠游戏" --quit 零错误）、GATE2（godot --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn 零 ✗ 且失败 0）。
6. 提交：精确 git add <文件>（禁 -A），message 带 [战斗] 前缀，署名 git config user.name "AI-战斗" user.email "ai-战斗@local"。
7. 本窗口专属：动战斗接口 → 重跑 tools/gen_contract.gd 比对 docs/契约总表.md 漂移；战术战棋逻辑与视图分离（services 不持有 Node）；别碰 GameManager/GameState/EventBus 等共享地基（要改先 handoff）；遇 town 相关先查 handoff 板（有战斗→town 掉血崩的 open 派单）。

本次窗口名：战斗
```

### 🎒 背包窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「背包」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律。
2. 改文件 / 提交 / 修 BUG 前，加载 change-tracking skill 按其命令执行。
3. 改前：change_log.py query --module services/inventory（或 --keyword <文件名>）确认不是回归。
4. 改完：change_log.py add 登记；跨主权额外 change_log.py notice。
5. 提交前：双闸门全绿（GATE1 零错误、GATE2 零 ✗ 且失败 0）。
6. 提交：精确 git add <文件>（禁 -A），message 带 [背包] 前缀，署名 git config user.name "AI-背包" user.email "ai-背包@local"。
7. 本窗口专属：背包满溢出的"真实生产者驱动"已由 tests/unit/test_inventory_service.gd 覆盖，测试窗口不会重复，你也别在自己逻辑里漏掉；JSON 数值文件（尤其 town.json 类被间接引用的）别当死数据误删——误删会让 GATE2 退化、且查日志才定位得到；休息/睡觉推进天数、propose 聘礼锁定若涉及结缘，先 handoff 派单。

本次窗口名：背包
```

### 💞 结缘窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「结缘」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律。
2. 改文件 / 提交 / 修 BUG 前，加载 change-tracking skill 按其命令执行。
3. 改前：change_log.py query --module <你的结缘模块路径>（或 --keyword <文件名>）确认不是回归。
4. 改完：change_log.py add 登记；跨主权额外 change_log.py notice。
5. 提交前：双闸门全绿（GATE1 零错误、GATE2 零 ✗ 且失败 0）。
6. 提交：精确 git add <文件>（禁 -A），message 带 [结缘] 前缀，署名 git config user.name "AI-结缘" user.email "ai-结缘@local"。
7. 本窗口专属：结缘常依赖背包（聘礼）/ 天数推进（休息睡觉），跨窗改动先 handoff 派单给背包 / 战斗窗口，别硬改别人主权；改动须与真实订阅方对齐（信号契约见 tests/unit/test_eventbus.gd 的 SEAMS 表）。

本次窗口名：结缘
```

### 🖥 UI 窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「UI」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律。
2. 改文件 / 提交 / 修 BUG 前，加载 change-tracking skill 按其命令执行。
3. 改前：change_log.py query --module scenes/ui（或 --keyword <文件名>）确认不是回归。
4. 改完：change_log.py add 登记；动 UIManager 屏幕栈须额外登记。
5. 提交前：双闸门全绿（GATE1 零错误、GATE2 零 ✗ 且失败 0，含 test_ui_mouse_filter.gd 静默拦截断言）。
6. 提交：精确 git add <文件>（禁 -A），message 带 [UI] 前缀，署名 git config user.name "AI-UI" user.email "ai-UI@local"。
7. 本窗口专属：提交时 pre-commit 钩子会扫你改的 .tscn 里 mouse_filter 这一行——若拦"静默吞点击"，只把装饰子节点改成 mouse_filter = 2（IGNORE 穿透），或确有意的 STOP 把它路径加进 tools/lint_mouse_filter.allow；【绝不要为过钩子去动战斗/背包/其它游戏逻辑】。钩子只扫 tscn 文本一行，对游戏功能零副作用。

本次窗口名：UI
```

### 🛠 工具窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「工具」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律。
2. 改文件 / 提交 / 修 BUG 前，加载 change-tracking skill 按其命令执行。
3. 改前：change_log.py query --module tools（或 --keyword <文件名>）确认不是回归。
4. 改完：change_log.py add 登记；大改动额外 change_log.py notice。
5. 提交前：工具改动跑 python -m py_compile tools/*.py（工作室工具额外跑 tools/security_selftest.py 15 断言）；GATE1/GATE2 仍须全绿。
6. 提交：精确 git add <文件>（禁 -A），message 带 [工具] 前缀，署名 git config user.name "AI-工具" user.email "ai-工具@local"。
7. 本窗口专属：lint_mouse_filter 守卫【范围窄，不是通用 UI 安全网】——别把"钩子绿"当"界面无输入 BUG"；check_assets_contract.py 默认只报告 exit 0，【禁止把 --strict 裸接进 pre-commit】（要接先配好 tools/check_assets_contract.allow 白名单），否则可能误拦别人正常提交；钩子用 managed python，换机/新克隆须重跑 python tools/install_hooks.py。

本次窗口名：工具
```

### 🧪 测试窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「测试」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律。
2. 改文件 / 提交 / 修 BUG 前，加载 change-tracking skill 按其命令执行。
3. 改前：change_log.py query --module tests（或 --keyword <文件名>）确认不是回归。
4. 改完：change_log.py add 登记。
5. 提交前：双闸门全绿（GATE1 零错误、GATE2 零 ✗ 且失败 0）。判绿须同时满足 grep -c "✗" == 0 且「套件：失败 0」（套件自身 Parse Error 时不打印 ✗，单看 ✗ 会误判绿）。
6. 提交：精确 git add <文件>（禁 -A），message 带 [测试] 前缀，署名 git config user.name "AI-测试" user.email "ai-测试@local"。
7. 本窗口【铁律·零副作用】：GATE2 测试【绝不 emit EventBus 信号】——EventBus 是单例，emit 会同步触发全部真实订阅方（UIManager/战斗/任务/存档），既产误导其他 AI 的防御性报错日志，又污染单例状态致后续测试偶发失败（失败指向错误测试 = 越走越偏）。信号类测试只做"声明存在 + 参数个数一致"的纯契约校验（参考 tests/unit/test_eventbus.gd）。✗ 文案须自带"若确有意为之请改本测试 SEAMS 表、勿改游戏逻辑"指引，让别的 AI 看到 ✗ 不会误读成游戏 BUG。【绝不重复别窗已覆盖的测试】（如背包满溢出的真实生产者驱动归背包窗）。

本次窗口名：测试
```

### 📋 PM / 集成窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「PM/集成」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律。
2. 加载 change-tracking skill 按其命令执行。
3. 集成前：change_log.py query（全局）看各窗近期改动；tools/handoff.py dashboard 看跨窗派单状态。
4. 出队提交：tools/commit_queue.py flush（精确提交，禁 -A）；其余窗口只 add 入队，不自行 flush。
5. 统一 push 前：整树双闸门全绿——GATE1（godot --headless --path "D:/武侠游戏" --quit 零错误）、GATE2（godot --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn 零 ✗ 且失败 0）。全绿后才 git pull --rebase + push；单分支禁各窗盲目 push 互覆盖。
6. 提交：message 带 [集成] 前缀，署名 git config user.name "AI-PM" user.email "ai-PM@local"。
7. 本窗口专属：门禁红了立即协调责任窗口修，禁止带红 merge；冲突协调；出 BUG 时在 changelog 该行「关联」注「回归自 <commit>」并 handoff issue 给责任窗口。

本次窗口名：PM
```

### 🔍 审计核查窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于「审计核查」角色。请严格遵守协同纪律与审计方法论：

1. 先读 docs/审计核查提示词.md（完整审计方法论：范围 A/B/C、8 大审计维度、正向+逆向+专业标准方法论、结构化输出格式、归类流程、主权纪律、双闸门）。
2. 审计是只读审查 + 写回待办清单，不是写功能。按用户指定范围（单模块 / 全盘 / 关联架构）执行。
3. 审计前必读：docs/backlog.json（执行清单）、docs/更改日志.md、docs/契约总表.md、tests/unit、tools/desktop_studio/scan_deps.py、.workbuddy/memory/MEMORY.md。
4. 逐条按 §5 格式记录发现并定三色（🔴红=迫在眉睫 / 🔵蓝=中规中矩 / 🟡黄=影响小）。
5. 归类：用 tools/audit_to_backlog.py --file findings.json 把待办项写入 docs/backlog.json 对应模块（匹配不到落 audit 模块），再跑 tools/gen_backlog.py 重生成文档，change_log.py add 留痕。
6. 主权铁律：只做只读审查 + 写回 docs/backlog.json 平台数据；要改游戏代码须 handoff 派单给对应窗口（不得越权），改完双闸门全绿才提交。
7. 提交（若你顺手修了游戏代码）：精确 git add <文件>（禁 -A），message 带 [审计] 前缀，署名 git config user.name "AI-审计" user.email "ai-审计@local"。

本次窗口名：审计核查
```

### 🏛 架构窗口
```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「架构」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律（留痕 / 调前先查 / 提交节奏 / 门禁非绿即阻断）。
2. 改文件 / 提交 / 修 BUG 前，加载 change-tracking skill 按其命令执行。
3. 改前：change_log.py query --module <架构文档/依赖图相关路径>（或 --keyword <文件名>）确认不是别人刚改崩的回归。
4. 改完：change_log.py add 登记；架构改动触及共享地基 / 全局分层，必须额外 change_log.py notice 出变更通告（见下方专属规则）。
5. 提交前：双闸门全绿——GATE1（godot --headless --path "D:/武侠游戏" --quit 零错误）、GATE2（godot --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn 零 ✗ 且失败 0）。
6. 提交：精确 git add <文件>（禁 -A），message 带 [架构] 前缀，署名 git config user.name "AI-架构" user.email "ai-架构@local"。
7. 本窗口专属（架构铁律）：
   - 五层架构：autoload → core → data → services → scenes → resources，依赖只允许「向下」；绝不允许上层反向依赖更基础的层（向上依赖违例 = 违反架构铁律）。
   - 动共享地基（EventBus / ConfigManager / core/enums/* / screens.json / strings.csv / GameManager / GameState）→ 必须先 handoff 派单 + change_log.py notice 出变更通告，并经 PM/架构师认可。
   - 改完跑 tools/desktop_studio/scan_deps.py 扫一遍，确认无「向上依赖违例」；新 AI 窗口要秒懂架构，同步更新 projects/wuxia_game.yaml 的 ai_context 与 docs/契约总表.md。
   - 跨模块通信只走 EventBus（信号契约见 tests/unit/test_eventbus.gd 的 SEAMS 表）；数值全进 JSON、不硬编码；命名见名知意。
   - 架构决策须对齐 docs/全角色工程手册与平台优化蓝图.md 与 docs/契约总表.md，不私下另立一套。

本次窗口名：架构
```

> 数据 / 音频 / 工作室 三个窗口：用上面同款结构，把窗口名换成 `数据` / `音频` / `工作室`、署名换成 `AI-数据` / `AI-音频` / `AI-工作室`、主权换成上表对应范围即可（通用口令模板见下方 §3）。
> 音频专属：新音频/资源导入必须用 `godot --headless --editor --quit --path "D:/武侠游戏"` 全量重导生成 `.import`，否则 `ResourceLoader.exists` 返回 false、`play_*` 会静默跳过（无报错无声音）。
> 数据专属：数值全进 JSON；改 JSON 同步重跑 `tools/gen_contract.gd`；注意 town.json 类被间接引用的文件别当死数据误删。

---

## 3. 通用启动口令模板（数据/音频/工作室等未单列窗口用这个，把 `<窗口名>` 换成实际）

```
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）工作，属于多 AI 协同的「<窗口名>」窗口。请严格遵守协同纪律：

1. 先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律（留痕/调前先查/提交节奏/门禁非绿即阻断）。
2. 任何「改文件 / 提交代码 / 修 BUG」任务，先加载 change-tracking skill（Skill → change-tracking）按其命令执行。
3. 改前：change_log.py query --module <你的模块> 查近期改动，确认不是别人刚改崩的回归再动手。
4. 改完：change_log.py add 登记一行（共享地基/跨主权改动额外 change_log.py notice 出变更通告）。
5. 提交前：双闸门全绿——GATE1（godot --headless --path "D:/武侠游戏" --quit 零错误）、GATE2（godot --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn 零 ✗ 且失败 0）。门禁红立刻修，禁止带红继续。
6. 提交：精确 git add <文件>（禁 -A），message 带 [<模块>] 前缀，署名 git config user.name "AI-<窗口名>" user.email "ai-<窗口名>@local"。
7. 别碰别人主权代码（见 MEMORY.md 主权边界）；要改先 handoff 派单。

本次窗口名：<窗口名>
```

---

## 4. 各窗口专属「别踩的坑」（真实教训，照着避）

- **战斗**：动接口 → 必跑 `gen_contract.gd` 比对契约总表；别碰 `GameManager/GameState/EventBus` 共享地基；`BattleScene._on_auto_pressed` 曾因缩进错长期 GATE2 红没人管 —— 门禁非绿即阻断，红门禁优先于任何新功能；遇 town 相关先查 handoff（有战斗→town 掉血崩 open 派单）。
- **背包**：`town.json` 曾被误删（判死数据）→ GATE2 退化；查 changelog/`git log` 才知是战术底图几何依赖 → `git checkout` 恢复。JSON 数值文件别当死数据；满溢出真实生产者驱动已由 `test_inventory_service` 覆盖（测试窗不重复）；休息/睡觉推进天数、propose 聘礼锁定若跨结缘先 handoff。
- **结缘**：跨窗依赖背包（聘礼）/天数（休息），先 handoff 派单，别硬改别窗主权；信号契约对齐看 `test_eventbus.gd` SEAMS 表。
- **UI**：pre-commit 钩子只扫 `.tscn` 里 `mouse_filter` 这一行，遇拦只改 tscn（`=2` 或加白名单），**绝不动游戏逻辑**；钩子不是通用 UI 安全网（全屏 STOP 遮挡/`z_index`/`gui_input` 重写它不拦）。
- **工具**：`lint_mouse_filter` 范围窄 ≠ 通用 UI 安全网；`check_assets_contract.py` **禁止裸接 `--strict` 进 pre-commit**（先配白名单）；改完 `py_compile`，工作室 `security_selftest.py`；换机/新克隆须重跑 `install_hooks.py`。
- **测试**：**GATE2 测试绝不 emit EventBus 信号**（单例污染状态 + 误导其他 AI 的噪音日志 = 越走越偏）；只做纯契约校验；判绿须 `✗==0` **且**「套件失败 0」双满足；✗ 文案自带"改测试勿改游戏逻辑"指引。
- **音频**：新资源必须 `editor --quit` 重导生成 `.import`，否则 `exists` 返回 false、播放静默跳过（无报错无声音）。
- **PM/集成**：整树双闸门全绿才统一 push；单分支禁各窗盲目 push 互覆盖；红门禁立即协调责任窗修，禁带红 merge。
- **审计核查**：只读审查、不得越权改他窗主权；归类只写 docs/backlog.json（平台数据，非游戏逻辑）；要改游戏代码须 handoff 派单 + 双闸门全绿。
- **架构**：五层架构依赖只允许向下，scan_deps.py 扫出「向上依赖违例」= 违反架构铁律，必须修；动共享地基（EventBus/ConfigManager/core 等）须先 handoff + 出变更通告、经架构师/PM 认可；跨模块通信只走 EventBus，数值全进 JSON 不硬编码；架构决策对齐 docs/契约总表.md 与 docs/全角色工程手册与平台优化蓝图.md，不另立一套。

---

## 5. 共享纪律速查（详细见 docs/多AI协同机制_SOP.md）

- **留痕**：每次修改 `change_log.py add`；共享地基/跨主权大改动额外 `change_log.py notice` 出变更通告。
- **调前先查**：接 BUG 先 `change_log.py query` + `git log -- <文件>` + `handoff.py dashboard`，确认不是回归再深入（禁"不查日志直接改"）。
- **双闸门**：GATE1 零 SCRIPT/PARSE/COMPILE ERROR；GATE2 零 ✗ 且失败 0。验证须 unsandboxed，ROOT 用 Windows 风格 `D:/武侠游戏`（POSIX `/d/...` 让 Godot 静默不跑 → 门禁误报绿）。
- **提交**：精确 `git add <文件>`（禁 `-A`）；message 带 `[<模块>]` 前缀 + 窗口署名；无 BUG 的改动必须 commit 留痕；push 由 PM 统一。
- **红线**：禁 `git add -A`；禁改共享地基不写变更通告；禁匿名/无 `[模块]` 前缀 commit；禁未过双闸门就 commit；禁各窗盲目 push 互覆盖；禁碰他人主权不 handoff；禁接 BUG 不查日志直接改。

---

## 6. 三层保险（你不用管，知道有就行）

1. 项目记忆自动灌进每个 AI 会话（它"天然"知道规矩）。
2. change-tracking skill 给它具体命令（怎么登记/查/跑门禁）。
3. git pre-commit 钩子在机器层兜底——哪怕 AI 忘了，提交时自动扫"静默吞点击"类 BUG 并拦下（已装 `python tools/install_hooks.py`）。

> 一句话：开窗口 → 粘对应口令（填窗口名）→ 让 AI 干活。其余守卫它自己会跑、机器也会兜底。

---

## 7. 切窗口协同纪律提示词（复制发给新 AI 窗口，固定显示在协同启动卡口令上方）

把下面整段复制，粘到新开的 AI 窗口里即可。它涵盖本次拍板的「并发上传互斥」等骨血规则，是比各窗口口令更高优先级的权威口径：

```text
你在本仓库（D:/武侠游戏，Godot 武侠 CRPG）参与多 AI 并行开发。开工前先读 .workbuddy/memory/MEMORY.md 的「多 AI 协同」铁律，并加载 change-tracking skill（Skill → change-tracking）按其命令执行。协同总纲（骨血）见 docs/变更通告_协同总纲_全员必须遵守.md，以下为不可绕过的硬性条件：

1. 提交权收口（最重要）：你（各窗口）不自行 git commit / git push。改完只做两件事——① 跑双闸门（GATE1：godot --headless --path "D:/武侠游戏" --quit 零错误；GATE2：godot --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn 零 ✗ 且失败 0）；② 用 python tools/commit_queue.py add --window <你> --message "..." --files a.gd b.json 把文件入队。由 PM/本对话（AI-UI / AI-PM）统一 flush 提交。
2. 并发上传互斥：检测到其他窗口正在向仓库上传（推送锁 .workbuddy/commits/_push_lock 被他人持有 / git fetch 后 origin 领先本地 / 本机有其他 git push 进程）→ 本次不提交不推送，改到下次。严禁在他人上传时强行 add/commit/push（这正是之前 .git 被踩坏的根因）。commit_queue.py flush 已内置该守卫（命中返回 4/5），正常走队列即可。
3. 文件主权 / 文件锁：开工前显式声明「本次改动文件清单」；同一文件同一时刻只归一个任务，不碰别人主权代码，绝不碰 preset_10x10.json / preset_12x12.json 等战斗预设（铁律：绝不动战斗预设）。
4. tscn 禁自动合并：.tscn 是文本格式，git 自动合并 90% 会搞坏场景；冲突时以一版为基准手动重改 + 本地验证能正常加载，绝不信任合并结果。
5. 双闸门：提交/入队前 GATE1+GATE2 必须全绿，门禁非绿即阻断。
6. 精确 add：若确需自行操作，只用 git add <具体文件>，严禁 git add -A / git add .，绝不 git stash -u（会踩坏 .git）。

> 若下方「窗口启动口令」中"提交：精确 git add…"等表述与本段冲突，以本段（协同总纲骨血）为准——你只需入队，不要自行 commit。

本次窗口名：<窗口名>
```
