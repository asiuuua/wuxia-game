# 武侠江湖 项目记忆（精简版，细节见 .workbuddy/memory/YYYY-MM-DD.md）

## 定位与锁定决策
- 等距(俯视角) 2.5D 武侠 RPG 单机；Godot **4.7.2**；纯 GDScript；个人开发（用户新手）。
- **实际代码是纯 2D**（TownScene 根 Node2D + Camera2D，零 3D 节点）；BattleScene 根是 **Control**（战斗=UI 界面）。`scenes/actors/{player,enemy,npc,interactable}` 全空，角色系统未实现。等距 2.5D 是目标态，技术路线待用户拍板（建议纯 2D，补 ysort）。
- 战斗：回合制 + 自动（CRPG 策略感）。平台：Win+安卓首发。世界：区域枢纽式（独立场景+读条切换）。
- 语言纯 GDScript；遇瓶颈只对热路径增量 GDExtension，绝不整体重写。

## 架构分层与铁律
`autoload`(18 个管家) → `core`(常量/枚举/接口/工具) → `data`(runtime 类 + configs JSON) → `services`(RefCounted 业务) → `scenes`(表现) → `resources`/`tests`/`tools`
- **四底线**：分层单向依赖 / 跨模块只走 EventBus / 数值全进 JSON / 命名见名知意。
- 业务层**不持有 Node**；GameManager 是装配中枢（持 PlayerState + 9 个 Service + pending_battle_id）。
- GameState 独立单例持全局状态（存档唯一来源）；GameManager 退为场景编排 + Service 容器。
- UIManager：6 层 CanvasLayer + 屏幕栈，`data/configs/ui/screens.json` 名→脚本，用 `script.new()` 实例化。
- 权威基线 `docs/模块设计规范.md`；协同框架 `docs/项目进度与协同开发框架.md`。

## 路线图
Phase 0 脚手架 ✅ → Phase 1 垂直切片 ✅ → **M1 战斗逻辑内核 ✅(2026-08-29, 提交 3f30636)** → Phase 2 系统填充（难度✅；锻造/商店/门派叶子逻辑✅；背包P0/P1✅）→ Phase 3 内容扩张 → Phase 4 平台适配
- 战斗下一步：M2 演出编排（BattleScene 瘦身 + Director/View + ATB 顺序条 + 加速/跳过）。

## GDScript 4.x 硬规（高频踩坑）
- autoload 脚本**禁止**写与单例同名的 `class_name`；`const X = preload()` 与全局 `class_name X` 同名会 shadowed。
- untyped Array 遍历出 Variant，`var x := el.f()` 会 `Cannot infer type` → 显式标类型或 `Array[T]`。
- **typed Array 禁止 `as Array[String]`**（只换包装不转元素，运行期崩）→ 必须循环 `append(String(s))`（读档必踩）。
- 遍历背包空槽位：`inst.xxx` 必须包 `if inst != null`。
- tab 缩进；**函数体不能空**（至少 `pass`）；场景树忙时切场景用 `call_deferred`。
- `@warning_ignore` 顶层声明**必须从列首无缩进开始**；类级注解必须在 `extends` 之前；autoload signal 必须**逐条**加 `@warning_ignore("unused_signal")`（类级不生效）。
- 4.7.2：`content_scale_mode`→`content_scale_stretch`；`Theme` 无 `bold_font` 属性（用 `theme.set_font("bold_font","RichTextLabel",f)`）；`mouse_filter` 是 Control 专属，Node2D 设了报错。
- `.gdignore` 跳过整个目录。删 `.godot` 后必须先 `--headless --editor --quit` 重建 `global_script_class_cache.cfg`。
- **`Invalid call. Nonexistent function 'new' in base 'GDScript'` 是级联误导**：真因是某脚本 Parse Error 编译失败。往上翻日志找第一条真正 Parse Error（常是 `Function "xxx()" not found in base self`，删函数后残留调用）。
- **删函数必须全工程 grep 确认无残留**：同一函数常在 `if` 与 `elif` 分支各调一次，只删末尾一处会漏。
- **Control `scale` 以 `pivot_offset` 为基准（默认 0,0=左上角）** → 悬停放大要先把 pivot 设中心并监听 `resized` 重算，否则往右下长溢出。

## Godot 静态验证（本机）
- 4.7.2 console：`C:\Users\Administrator\.workbuddy\binaries\godot\Godot_v4.7.2-stable_win64_console.exe`
- 健康检查：`--headless --path "D:/武侠游戏" --quit 2>&1`
- 单脚本：`--check-only --script res://<path>.gd`
- ⚠️ `--check-only --script` **不加载 autoload**，引用单例必报 `Identifier not found`（假阳性）。真伪以完整 `--quit` 或实际启动为准。
- **单元测试**：`Godot_v4.7.2_console --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn`（场景运行，autoload 全加载，退出码 0/1）。当前 战斗 13 + 存读档 6 全绿。
- ⚠️ 验证**界面脚本**真编译：把 `tests/ui/m5_smoke.tscn` 当主场景跑（或真实打开工程），`--script` 模式不加载 autoload 会假阳性。
- 多 Godot 进程抢 `.godot` 类缓存会玄学报错 → **验证必须串行**。

## 资源与主题
- 中文靠工程默认主题下发：`project.godot [gui] theme/custom="res://resources/themes/ui_theme.tres"`；字体思源宋体 `resources/fonts/SiYuanSongTiRegular/`；主题由 `tools/gen_ui_theme.gd` 重生成。
- 设计令牌：`core/constants/ui_theme.gd` 的 `UIPalette`；**UI 动效令牌 `data/configs/ui/ui_anim.json`**、**音效令牌 `ui_sfx.json`**（禁止脚本里写裸数字/裸路径）。
- 资产管线硬规：JPG→PNG 必须 PIL 真正重编码（`shutil.copy` 只是改扩展名，Godot 导入会静默 null）；高清图要 LANCZOS 预降采样到显示尺寸 2–4 倍 + mipmap + `default_texture_filter=3`，否则越清晰越糊；改完必须删 `.godot/imported/*.ctex` 重导。角色显示高 140px。
- PIL venv：`C:\Users\Administrator\.workbuddy\binaries\python\envs\default\Scripts\python.exe`（已装 pillow）。

## 战斗层现状（M1 已交付 · 提交 3f30636）
- **事件契约** `data/runtime/combat_event.gd`：`enum Type`（TURN_START/ACTION_BASIC/ACTION_SKILL/QI_COST/QI_GAIN/COOLDOWN_SET/DAMAGE/HEAL/STATUS_APPLIED/STATUS_TICK/STATUS_EXPIRED/OUTCOME）+ actor_id/target_id/value/crit/dodged/status_id/stacks/skill_id。
- **逻辑内核** `services/combat/combat_core.gd`（纯 RefCounted，零 Node/零全局 randf/零 Tween）：ATB `action_order()`（按 `effective_charge_rate()`=speed+状态修正降序）、双资源(气血 hp + 真气 mp)、招式分阶与冷却(`qi_cost`/`cooldown`)、状态引擎(`tick_unit`：DoT/HoT+持续递减+到期移除；`StatusEffect` 有 flat/pct/层数/持续/clear_on_rest)、确定性随机(注入 `SeededRNG`)。`_resolve_hit` 经 rng 决定闪避/暴击。
- **门面** `combat_service.gd`：保留全部旧接口零回归(`player_attack`/`player_cast`/`run_enemy_turns`/`finalize`/`try_escape`)，内部委托 `_core`；新增 `get_core`/`player_rest`/`player_use_item`。`player_use_item` 只结算战斗快照(CombatCharacter)，finalize 才回写 PlayerState——战斗内切勿直调 InventoryService.use_item。
- **配置**：`skills.json` v1.2.0（普攻/二式/三式/绝世/轻功/心法/调息 七类，含 target/qi_cost/cooldown/effects）；`status_effects.json`（破甲/强攻/固守/灼烧/中毒/聚气/疾行）；`battles.json` 加 `turn_mode`（atb/se时)，`battle_bandit_001`=atb；`enemies.json` 的 `speed` 字段已被消费。
- **枚举** `combat_enums.gd` 增 `TurnMode { SEQUENTIAL, ATB }`；`EventBus` 增 `item_used`（战斗内用药刷背包 UI 例外走总线）；`GameManager` 接 `cmd_start_combat`（任务/对话发令自动开战）。
- **已知待做（M2/M3）**：BattleScene 流程编排仍未抽到 Director（仍是 UI 直接调门面）；敌人 AI 权重选技能（enemies.json `abilities` 字段已就位，M3 接）；状态引擎扩护盾/反弹/复活；演出层(顺序条/血条直设/飘字)待建；事件暂无 `target_hp_after`（M2 需补，属共享契约）。
- ⚠️ **确定性测试陷阱**：`combat_service` 是单例，确定性测试每个 run 必须「开战→行动→记录」自成一体；先开两次战再行动会让两次行动都作用在最后一次激活态上（已栽过，见 `test_deterministic_same_seed`）。

## 背包层现状（P0/P1 已修，详见 2026-08-29.md #149 段）
- `inventory_service.gd`：三栏（主30/材料200/任务50）+堆叠+负重+ISaveable；事务 API（`query_add`/`can_add`/`try_consume` 两遍式原子扣料）；iid 发号器(`next_iid` 进存档)。
- 用药链路：城镇=InventoryService.use_item→PlayerState；战斗=CombatService.player_use_item→战斗快照。UI 入口：BattleScene"物品"菜单 + InventoryScreen"使用"按钮。
- flags 已通（pills=51/weapon·armor=67/材料=19）。待办(P2)：ItemSlot/tooltip 组件空、UI 全量重建、负重未挂 strength、3 个测试套件未继承 TestBase 被 run_all 跳过。

## 多 AI 协同边界
- **共享地基（冻结，改前打招呼）**：`core/enums/*_enums.gd`、`autoload/EventBus.gd`、`autoload/ConfigManager.gd`、`data/configs/ui/screens.json`、`strings.csv`。
- **UI 窗口主权**：`scenes/ui/**` + `data/configs/ui/**` + `core/constants/ui_theme.gd` + `resources/themes/**` + `autoload/ui_manager.gd`。
- **战斗窗口主权**：`services/combat/**` + `data/runtime/combat_*.gd` + `data/configs/scenes/battles.json` + `scenes/gameplay/battle/**` + `skills.json` + `enemies.json`。
- **背包窗口主权**：`services/inventory/**` + `data/runtime/item_instance.gd` + `data/configs/items/**` + `core/constants/item_constants.gd` + `core/enums/item_enums.gd` + `tools/gen_contract.gd` + `docs/契约总表.md`。
- **Git 精确提交铁律**：仓库为 master 单分支，提交格式 `[窗口名] 改动；影响：xxx；不影响：xxx`。⚠️ 教训：M1 提交(`3f30636`)曾把当时工作区全部文件（含背包窗口未提交的 EventBus/player_state/combat_service 改动）一起卷入——**各窗口必须逐个 `git add <自己的文件>`，严禁 `git add -A` / `git add .`**；开工前先 `git log --oneline -5` + `git status` 区分哪些改动是自己的。
- Godot 验证**必须串行**；`docs/` 不要两人改同一篇；提交按里程碑分开（M1 提交 `3f30636` 已与 UI 并发改动隔离）。

## 协同开发 SOP（开工 / 收尾双闸门 · 用户 2026-08-29 拍板）
- **开工前**：读日期最新的 `docs/变更通告_*.md` + 读 `docs/契约总表.md`（gen_contract 自动生成，禁止手改；代码是唯一真源）。
- **收尾时**：跑双闸门 → ① `--headless --quit` 零错误 ② `res://tests/unit/run_all.tscn` 零失败 → 写本窗口的《变更通告》→ 若动了接口则重跑 `gen_contract.gd` 并把 `契约总表.md` 入库。
- **共享地基（冻结，只增不改）**：`core/enums/*_enums.gd`、`autoload/EventBus.gd`、`autoload/ConfigManager.gd`、`data/configs/ui/screens.json`、`strings.csv`。改动必须在当轮《变更通告》「共享地基增量」表里明示（信号/枚举末尾追加，绝不动已有项），并打招呼。
- 已落地的《变更通告》：`变更通告_2026-08-29_背包窗口.md`（背包窗口）、`变更通告_2026-08-29_战斗逻辑层.md`（M1）、`变更通告_2026-08-29_UI主线整改.md`（#150–#154）、`变更通告_2026-08-29_设置弹窗整改.md`（设置弹窗独立化 + 美工规范 + 现存弹窗审计 + 分辨率加固 + 契约总表 UIManager 段大小写修复）。
