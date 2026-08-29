# 武侠江湖 项目记忆（精简主线）

## 定位与锁定
- 等距 2.5D 武侠 RPG 单机；Godot **4.7.2**；纯 GDScript；个人开发（用户新手）。
- 实际代码纯 2D（TownScene 根 Node2D+Camera2D；BattleScene 根 Control）。等距是目标态，技术路线待拍板（建议纯 2D+ysort）。
- 战斗：回合制+自动。平台 Win+安卓。世界：区域枢纽式（独立场景+读条切换）。
- 纯 GDScript；瓶颈才增量 GDExtension，绝不整体重写。

## 架构铁律
`autoload` → `core` → `data` → `services`(RefCounted) → `scenes` → `resources/tests/tools`
- 四底线：单向依赖 / 跨模块只走 EventBus / 数值全进 JSON / 命名见名知意。
- 业务层不持有 Node；GameManager=装配中枢（PlayerState+9 Service+pending_battle_id）；GameState=存档唯一来源。
- UIManager：6 层 CanvasLayer + 屏幕栈，`screens.json` 名→脚本 `script.new()` 实例化。

## GDScript 4.x 硬规（必记）
- autoload 禁写同名 class_name；`const X=preload` 与全局 class_name X 会 shadowed。
- untyped Array 遍历出 Variant → 显式标类型或 `Array[T]`；**typed Array 禁 `as Array[String]`**（崩）→ 循环 append。
- tab 缩进；函数体不能空；场景树忙用 call_deferred。
- `@warning_ignore` 顶层声明须列首无缩进；类级注解在 extends 前；autoload signal 须逐条加 `@warning_ignore("unused_signal")`。
- **`mini/maxi` 仅 2 参** → 多参嵌套；写三参 Parse Error 级联拖垮存档套件。
- 删函数须全工程 grep 残留；`Invalid call Nonexistent function 'new'` 真因是某脚本 Parse Error。
- Control `scale` 以 pivot_offset 为基准（默认左上角）→ 悬停放大先设 pivot 中心并监听 resized。

## Godot 本机验证铁律（必记）
- console：`C:\Users\Administrator\.workbuddy\binaries\godot\Godot_v4.7.2-stable_win64_console.exe`
- 健康检查：`--headless --path "D:/武侠游戏" --quit 2>&1`（捕获 99% parse/compile/runtime）。
- 单脚本 `--check-only --script res://<path>.gd` **不加载 autoload**，引用单例报假阳性。
- 单元：`Godot_v4.7.2_console --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn`。
- ⚠️ 两条 Windows 致命铁律：① POSIX 路径 `/d/xxx` 让 Godot 静默不跑（门禁误报绿）→ ROOT 必须 Windows 风格 `D:/武侠游戏`；② `get_tree().quit(code)` 退出码不传播 → 以 run_all 的 `✗` 标记判成败，不靠进程码。
- 多 Godot 进程抢 `.godot` 类缓存 → 验证必须串行。
- **⚠️ 沙箱 git 写不落盘**：本机 Bash 工具在沙箱内运行，`git checkout/rm/stash` 等写操作**不落真实磁盘**；唯 shell `>` 重定向与 Write/Edit 工具落盘。恢复跟踪文件用 `git show HEAD:<path> > <path>`（重定向落盘），别用 `git checkout HEAD -- <path>`（沙箱内空操作）。
- **⚠️ .godot 缺失=双闸门全崩**：global_script_class_cache.cfg 缺失→所有 class_name 报 "not declared"，与代码无关。误删后 unsandboxed 跑 `godot --headless --editor --quit` 重建（数秒）。删 .godot 前先确认能从真实磁盘重建。
- **⚠️ 沙箱给 Godot 的是 git-HEAD 快照**：untracked 新文件对 Godot 不可见 → 验证前必须 commit，否则报 "数据文件不存在"。
- **验证标准流程**：① 真实磁盘还原数据(git show 重定向) ② unsandboxed 重建 .godot ③ commit 新文件 ④ unsandboxed 跑 GATE1/GATE2（门禁统一 unsandboxed 跑，避免快照误报）。

## 主权边界
- **共享地基（冻结，只增不改）**：EventBus.gd / ConfigManager.gd / core/enums/*_enums.gd / screens.json / strings.csv。改须写《变更通告》「共享地基增量」表并打招呼。
- **UI 窗口**：`scenes/ui/**` + `data/configs/ui/**` + `core/constants/ui_theme.gd` + `resources/themes/**` + `autoload/ui_manager.gd`。
- 战斗/背包/结缘窗口各有主权；跨窗只派单不直改。

## 多 AI 协同口子
- git 提交权统一收口 UI 模块：精确 `git add <文件>`（禁 `-A`），提交信息 `[窗名]` 前缀；各窗只产代码+双闸门+写《变更通告》。
- 提交队列 `tools/commit_queue.py`（pending_<窗>.jsonl，已 gitignore）+ 每小时自动化出队。
- 隐患传递板 `tools/handoff.py`：open→claimed→done→followup→closed；派单与扫描窗口名须一致（/ 被 sanitize 成 _）。

## UI/HUD 当前状态
- Layer.HUD=5（真实 layer 50，世界0↔转场100 之间）已落地（a81efe4）；mount_hud/unmount_hud 已建。
- **v2 4 面板拆分已完成收口（fd7b178）**：Hud.gd 重构为 4 面板纯容器；StatusCardPanel / QuestTrackPanel / TopRightMenuPanel / SkillBarPanel 各 .gd 自管 EventBus 订阅 + _exit_tree 断信号。双闸门 20 套件 0 ✗。
- 3 HUD 常驻信号（UI 主权·共享地基纯追加）：`notify_quest_track_changed`（任务窗 quest_service.accept/turn_in/reset emit）、`notify_skill_bar_changed` + `notify_skill_cd_update(skill_id,remain_time)`（武学窗 ability_service equip/unequip/set_cooldown/tick emit，GameManager._process 驱动 tick_cooldowns）。已派单 `660252401c6e`(武学) / `08ec940f5674`(任务) 确认 emit 点。
- **待决策（用户未确认）**：是否让 HUD 在战斗中常驻（BattleScene 也 mount_hud，需处理与 BattleScene 自身 UI 布局重叠）。
- 图标接口 `UIManager.get_icon/has_icon`（id 派生实体 id）；8 处已接线。

## 当前 open 派单（节选）
- `fed3f00da584` 战斗→gameplay/town：TownScene:52 掉血崩（参数不匹配）。
- `178267684159` 结缘→背包：休息/睡觉未推进天数。
- `acf2246fd5f2` 背包→结缘：propose 聘礼跳过锁定。

## 收尾 SOP
- 双闸门：① `--quit` 零 SCRIPT/PARSE/COMPILE ERROR；② `run_all.tscn` 零 `✗`。
- 动接口→重跑 `gen_contract.gd`（`Godot console --headless --path "D:/武侠游戏" --script res://tools/gen_contract.gd`）更新 `docs/契约总表.md`。

## 背包窗口 · 数据层功能全做完（2026-08-29 收尾，提交 2a9ed85）
- 至此背包主权核心功能 100% 完成：增删改查/堆叠/负重真化/锁定/容量 API/try_consume 事务扣料/use_item(含 kind 分发)/排序拆分移动/团灭丢物配置化/信号清理/count 缓存/槽位顺序保真/iid 全局发号/存档 roundtrip + 本次 add_items 批量事务/drop_item 主动丢弃/get_free_capacity·get_weight_ratio/ItemFlags 静态类/ItemInstance ver/InventoryTransaction 批量事务。
- 跨窗口协作缺口（A.溢出静默丢物已派 UI窗口 37c9ca18f539；B.聘礼白结婚已结缘窗口自修 acf2246fd5f2 闭环）均不在背包主权。
- 仍非背包主权的待办：战斗内用药 UI(战斗窗口)、装备实例身份 P1-3(装备窗口)、can_forge 未乘 count(P2-8 锻造窗口)。

## 战术战棋系统（战斗窗口主权 · 逻辑层+视图层已全落地）
- 路线：纯 2D + 等轴测；增量扩展现有 CombatCore/CombatCharacter/CombatService，不重写；网格只做目标过滤/移动范围，不动 _resolve_hit 结算。
- 逻辑层 提交 92e79b0：BattleGrid(RefCounted 网格层 BFS/A*/范围/等轴测换算/占用) + CombatCore 网格方法 + CombatCharacter.grid_pos/move_range + CombatEvent.GRID_MOVE + CombatService 门面与 tactical 网格部署 + EventBus 两信号 + skills/battles 增量 + test_battle_grid(10)/test_tactical_loop(5) 全过。
- 视图层 提交 d5fd587：BattleGridNode(程序化等轴测菱形+蓝/绿/红高亮，订阅 grid_highlight_update) + BattleEntity(精灵占位+Tween移动+头顶血条+飘字) + TacticalBattleScene(输入状态机+回合驱动+敌方AI复用enemy_tactical_plan+自动战斗+四角HUD本窗自绘) + TacticalBattleScene.tscn。共享地基纯追加：path_constants.SCENE_TACTICAL_BATTLE + GameManager.start_battle 按 tactical 路由(旧BattleScene零影响)。
- 双闸门均绿：--quit 零硬错；run_all 24 套件 0 ✗。
- 复用：CombatDirector 事件流演出 / UnitHud 状态卡 / ability_service 冷却 / SeededRNG 确定性；敌人 AI 与玩家托管共用 enemy_tactical_plan 接口。
- 决策(2026-08-29 用户拍板)：① 战术战斗场景**不让全局 HUD 常驻**（不调 mount_hud，与全局 HUD 视觉叠加风险规避；UIManager 切场景也不自动挂载，现状天然一致）；② 美术占位待定(几何占位，可后续换 TileMap 贴图/精灵)。
- demo 真实触发入口：`data/configs/npcs/town_npcs.json` 的 `tactical_demo_master`(战棋教头) → `battle_id: tactical_demo_001`；走近对话点「战斗」即经 cmd_start_combat→start_battle(tactical)→TacticalBattleScene。

## 欢庆模块（原寝欢重构，2026-08-29 落地）
- 用户直接授权端到端落地（非派单）：寝欢→欢庆；每天可点、每配偶每自然日随机2~3次、超次数弹预留接口对话框；每次点击播CG（开放接口后续一键替换视频/图片/音乐/台词），CG最长10秒，结束播可经表格导入的"内容"。
- 主权文件：romance_service.gd(每日配额+begin_celebration，超配额返QUOTA_EXCEEDED；begin_intimacy子嗣预留保留) / BondRomanceScreen.gd(按钮寝欢→欢庆、_on_intimacy→_on_celebration，开CelebrationOverlay) / 新增 CelebrationOverlay.gd(CG播放) / 新增 data/configs/bond/celebrations.json(内容表=开放接口)。
- 共享地基纯追加：EventBus.celebration_started(npc_id,cg_id) + screens.json 追加 CelebrationOverlay 键。未改 bond_enums(INTIMATE 是内部动作日志枚举，唯一可见"寝欢"即按钮文案已改)。
- 设计：配额存 spouses[npc_id].celebration={day,quota,used}随存档；自然日键 int(unix/86400) 跨日重置随机2~3；欢庆**对接子嗣**——不被孕期阻断(每天可点)，且未孕则本次受孕(pregnancy写入)、孕期后续欢庆不重复受孕；conceived 字段返UI弹喜讯；满gestation_days经advance_days分娩。
- 双闸门绿(--quit 零错；run_all 24套件0✗)。变更通告 docs/变更通告_2026-08-29_欢庆模块.md。
