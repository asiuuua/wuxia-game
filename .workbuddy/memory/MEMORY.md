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
Phase 0 脚手架 ✅ → Phase 1 垂直切片 ✅ → 战斗 M1 逻辑内核 ✅(3f30636) → M2 演出编排 ✅(9d6e5c3) → M3-1/2/3 (AI/状态/令牌化) ✅ → Phase 2 系统填充（难度✅；锻造/商店/门派叶子逻辑✅；背包P0/P1✅）→ Phase 3 内容扩张（战斗切片A/B ✅、结缘 M1–M4 ✅、UI 姻缘面板+婚礼演出 ✅ ）→ Phase 4 平台适配。
- ✅ `ui_anim.json` 的 `battle` 令牌块**已由 UI 窗口补完（含 M3-3 三机制意图时长）**，动效令牌化全闭环。

## GDScript 4.x 硬规（高频踩坑）
- autoload 脚本**禁止**写与单例同名的 `class_name`；`const X = preload()` 与全局 `class_name X` 同名会 shadowed。
- untyped Array 遍历出 Variant，`var x := el.f()` 会 `Cannot infer type` → 显式标类型或 `Array[T]`。
- **typed Array 禁止 `as Array[String]`**（只换包装不转元素，运行期崩）→ 必须循环 `append(String(s))`（读档必踩）。
- 遍历背包空槽位：`inst.xxx` 必须包 `if inst != null`。
- tab 缩进；**函数体不能空**（至少 `pass`）；场景树忙时切场景用 `call_deferred`。
- `@warning_ignore` 顶层声明**必须从列首无缩进开始**；类级注解必须在 `extends` 之前；autoload signal 必须**逐条**加 `@warning_ignore("unused_signal")`（类级不生效）。
- **`mini`/`maxi` 仅 2 个参数**（Godot 4.x），多参必须嵌套 `mini(mini(a,b),c)`；写三参会 `Parse Error: Too many arguments` 并级联拖垮所有依赖脚本（含存档套件），双闸门必拦。
- 4.7.2：`content_scale_mode`→`content_scale_stretch`；`Theme` 无 `bold_font` 属性（用 `theme.set_font("bold_font","RichTextLabel",f)`）；`mouse_filter` 是 Control 专属，Node2D 设了报错。
- `.gdignore` 跳过整个目录。删 `.godot` 后必须先 `--headless --editor --quit` 重建 `global_script_class_cache.cfg`。
- **`Invalid call. Nonexistent function 'new' in base 'GDScript'` 是级联误导**：真因是某脚本 Parse Error 编译失败。往上翻日志找第一条真正 Parse Error（常是 `Function "xxx()" not found in base self`，删函数后残留调用）。
- **删函数必须全工程 grep 确认无残留**：同一函数常在 `if` 与 `elif` 分支各调一次，只删末尾一处会漏。
- **Control `scale` 以 `pivot_offset` 为基准（默认 0,0=左上角）** → 悬停放大要先把 pivot 设中心并监听 `resized` 重算，否则往右下长溢出。

## Godot 静态验证（本机）
- 4.7.2 console：`C:\Users\Administrator\.workbuddy\binaries\godot\Godot_v4.7.2-stable_win64_console.exe`
- 健康检查：`--headless --path "D:/武侠游戏" --quit 2>&1`
- 单脚本：`--check-only --script res://<path>.gd`（**不加载 autoload**，引用单例报 `Identifier not found` 系假阳性；真伪以完整 `--quit` 或实际启动为准）。验证界面脚本真编译须把 `tests/ui/*.tscn` 当主场景跑。
- **单元测试**：`Godot_v4.7.2_console --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn`（场景运行，autoload 全加载）。当前 **13 个套件、约 130 项**（背包 30 / 战斗 smoke 23 + roster 3 + status 2 / 存读档 6 / 结缘 9 + 姻缘 8 + 关系 6 + 结义 5 + 师徒 6 / UI inventory_smoke 等），双闸门常态全绿。
- 门禁 `tools/gate_check.sh`（v2）+ `gate_allowlist.txt` + `tools/wip_check.sh`：① `--quit` 零硬错 ② `run_all` 无 `✗` + ERROR 全命中白名单 ③ `inventory_smoke.tscn` 出 `ALL_INV_OK`。
- ⚠️ **Godot headless 在 Windows 上的两条致命验证铁律（必记牢）**：
  1. **POSIX 路径 `/d/xxx` 会让 Godot 静默不运行场景（零输出零报错）→ 门禁误报绿**。脚本 ROOT 必须归一化为 Windows 风格（`cygpath -w`，如 `D:/武侠游戏`）。
  2. **`get_tree().quit(code)` 退出码不被 Godot headless 传播（失败也返回 0）** → 不能靠进程退出码判测试成败；门禁以 `run_all.gd` 的 `✗` 标记为真实失败判据（负向用例合法「失败 N」小计不含 `✗`，不误报）。
- 多 Godot 进程抢 `.godot` 类缓存会玄学报错 → **验证必须串行**。
- ✅ **gate[3] 已转绿（2026-08-29）**：原 `inventory_smoke` 跨栏断言与背包窗口 `move_instance` 类型不变式冲突（派单 `f1e8ac0c4ce7`）；根因是 UI 自有 smoke 用例断言过时行为，背包窗契约为有意设计（自带回归 `test_move_instance_rejects_cross_type`）。UI 主权内对齐 smoke 用例（武器→material 改负向断言 + 同栏重定位正向 + 装备改从 main）→ `ALL_INV_OK pass=13 fail=0`。背包窗契约保持不变。

## 资源与主题
- 中文靠工程默认主题下发：`project.godot [gui] theme/custom="res://resources/themes/ui_theme.tres"`；字体思源宋体 `resources/fonts/SiYuanSongTiRegular/`；主题由 `tools/gen_ui_theme.gd` 重生成。
- 设计令牌：`core/constants/ui_theme.gd` 的 `UIPalette`；**UI 动效令牌 `data/configs/ui/ui_anim.json`**、**音效令牌 `ui_sfx.json`**（禁止脚本里写裸数字/裸路径）。
- 资产管线硬规：JPG→PNG 必须 PIL 真正重编码（`shutil.copy` 只是改扩展名，Godot 导入会静默 null）；高清图要 LANCZOS 预降采样到显示尺寸 2–4 倍 + mipmap + `default_texture_filter=3`，否则越清晰越糊；改完必须删 `.godot/imported/*.ctex` 重导。角色显示高 140px。
- PIL venv：`C:\Users\Administrator\.workbuddy\binaries\python\envs\default\Scripts\python.exe`（已装 pillow）。

## 多 AI 协同（提交队列 + 隐患传递板 + git 收口）
- **git 提交权（用户 2026-08-29 拍板收口到「UI 模块」）**：git 提交**统一由 UI 模块收口**，战斗/背包/设置/结缘等窗口**不再自行 `git commit`**。各窗收尾只做：产代码 + 跑双闸门 + 写《变更通告》（含「改动文件清单」+「共享地基增量」）；UI 模块按清单逐个 `git add <文件>` 精确入库（**严禁 `git add -A` / `git add .`**），提交信息 `[窗口名]` 前缀。
- **提交队列**（与隐患传递板并列）：`tools/commit_queue.py`，各窗完成任务自验后 `add` 入队（写 `.workbuddy/commits/pending_<窗>.jsonl`，已 gitignore）；PM 每轮 flush + 每小时自动化 `提交队列定时出队`（id `automation-1787964331592`）出队，精确 `git add` 所列文件、commit、移入 `done_<窗>.jsonl`。flush 铁律：只 add 所列文件、不跑 Godot 重验证、MERGE/REBASE 整体跳过、无改动 no-op 跳过。规范 `docs/提交队列协同规范.md`。
- **隐患传递板**（跨窗派单）：`tools/handoff.py`，目录 `.workbuddy/handovers/` 已 gitignore。状态机由事件重放推导 `open → claimed → done → followup → closed`；命令 `issue/scan/claim/done/followup/close/dashboard`。窗口名自由字符串但 `/` 被 sanitize 成 `_`，**派单与扫描必须用同一字符串**（如 `--to gameplay/town` 与 `--window gameplay/town` 都归一 `gameplay_town`）。执行方只改本窗主权文件；要求改共享地基/它窗主权则跳过回报。规范 `docs/协作隐患传递板规范.md`。
- **周期自动化（各窗 hourly 认领执行）**：背包 `automation-1787964677539`、战斗 `automation-1787964873704`（扫 to==己 的 open → 主权内认领修复 + 双闸门自验 → done，不自 git 提交）。**UI 窗口的同类自动化待建。**
- **当前 open 派单（dashboard 实况）**：
  - `fed3f00da584` 战斗→`gameplay/town`：TownScene.gd:52 玩家掉血即崩（`player_hp_changed`(2)→`_on_player_changed`(1) 参数不匹配），待 town 窗认领。
  - `178267684159` 结缘→背包：游戏内"休息/睡觉"未驱动时间服务推进天数（子嗣孕期不流逝），待背包窗。
  - ~~e769b689077d~~ **[done]** UI→战斗：test_elite 非确定性（combat_core 时间戳种子致 REFLECT/REVIVE/SHIELD_ABSORB 概率性出现）→ UI 窗口替战斗窗收口切片B cohesive 提交 `a8ae77f`（test_battle_status_content.gd + enemies/skills/battles json + combat_core/combat_service/combat_character），run_all 提交后 3 连跑 ✗0、13套件全绿。
  - `fb36b027ba06` UI→测试基建：run_all 退出码不传播（**不派单**，Godot headless 固有限制，gate 已以 `✗` 兜底）。
  - `37c9ca18f539` 背包→**UI**：`inventory_add_overflow` 信号无游戏内订阅方，满包时物品静默丢失（**to=UI，我窗待认领修复**）。
  - `acf2246fd5f2` 背包→结缘：romance_service.propose 聘礼扣除跳过锁定实例且不校验返回值，锁定聘礼时白结婚。
  - ~~f1e8ac0c4ce7~~ **[done]** `inventory_smoke`[3] 门禁红（`move_instance` 类型不变式 vs UI 跨栏断言）→ UI 窗口对齐自有 smoke 用例到背包窗已确立契约（2026-08-29，变更通告 `docs/变更通告_2026-08-29_inventory_smoke对齐类型不变式.md`），背包窗契约不变。

## 主权边界
- **共享地基（冻结，只增不改）**：`core/enums/*_enums.gd`、`autoload/EventBus.gd`、`autoload/ConfigManager.gd`、`data/configs/ui/screens.json`、`strings.csv`。改动须写入当轮《变更通告》「共享地基增量」表（信号/枚举末尾追加，绝不动已有项）并打招呼。
- **UI 窗口主权**：`scenes/ui/**` + `data/configs/ui/**` + `core/constants/ui_theme.gd` + `resources/themes/**` + `autoload/ui_manager.gd`。
- **战斗窗口主权**：`services/combat/**` + `data/runtime/combat_*.gd` + `data/configs/scenes/battles.json` + `scenes/gameplay/battle/**` + `skills.json` + `enemies.json`。
- **背包窗口主权**：`services/inventory/**` + `data/runtime/item_instance.gd` + `data/configs/items/**` + `core/constants/item_constants.gd` + `core/enums/item_enums.gd` + `tools/gen_contract.gd` + `docs/契约总表.md`。
- **结缘窗口**：`services/bond/**` + `data/configs/bond/**` + `tests/unit/test_*bond*`；`GameManager`/`EventBus`/`ConfigManager` 只纯追加装配（不注册存档/不重置非本窗 key）。

## 协同开发 SOP（开工 / 收尾双闸门）
- **开工前**：读日期最新的 `docs/变更通告_*.md` + `docs/契约总表.md`（gen_contract 自动生成，禁手改；代码是唯一真源）。
- **收尾时**：跑双闸门 → ① `--headless --quit` 零错误 ② `res://tests/unit/run_all.tscn` 零失败 → 写本窗《变更通告》→ 若动了接口则重跑 `gen_contract.gd` 并把 `契约总表.md` 入库。
- **git 提交**：见「多 AI 协同」→ 统一由 UI 模块收口。
- 已落地《变更通告》集中在 `docs/`（`变更通告_2026-08-29_*.md`）：背包窗口 / 战斗逻辑层(M1) / 战斗演出(M2) / UI主线整改(#150–#154) / 设置弹窗整改 / 敌人AI选技能(M3-1) / 状态引擎(M3-2) / 演出令牌化(M3-3) / 战斗切片A/B / 结缘M1–M4 / 姻缘面板与婚礼演出 / 战斗模块核检修复。

## 战斗层现状（M1+M2+M3 已收口）
- **事件契约** `data/runtime/combat_event.gd`：`enum Type`（TURN_START/ACTION_BASIC/ACTION_SKILL/QI_COST/QI_GAIN/COOLDOWN_SET/DAMAGE/HEAL/STATUS_APPLIED/STATUS_TICK/STATUS_EXPIRED/OUTCOME/SHIELD_ABSORB/REFLECT/REVIVE）+ actor_id/target_id/value/crit/dodged/status_id/stacks/skill_id + 演出直设(target_hp_after/target_max_hp/actor_mp_after/target_mp_after/target_shield_after)。
- **逻辑内核** `services/combat/combat_core.gd`（纯 RefCounted，零 Node/零全局 randf/零 Tween）：ATB `action_order()`（按 `effective_charge_rate()`=speed+状态修正降序）、双资源(气血 hp + 真气 mp)、招式分阶与冷却(`qi_cost`/`cooldown`)、状态引擎(`tick_unit`：DoT/HoT+持续递减+到期移除；`StatusEffect` 有 flat/pct/层数/持续/clear_on_rest)、确定性随机(注入 `SeededRNG`)。`_resolve_hit` 经 rng 决定闪避/暴击。
- **门面** `combat_service.gd`：保留全部旧接口零回归(`player_attack`/`player_cast`/`run_enemy_turns`/`finalize`/`try_escape`)，内部委托 `_core`；新增 `get_core`/`player_rest`/`player_use_item`（战斗内只结算快照，finalize 才回写 PlayerState，切勿直调 InventoryService.use_item）。
- **配置**：`skills.json` v1.2.0（七类：普攻/二式/三式/绝世/轻功/心法/调息）；`status_effects.json`（破甲/强攻/固守/灼烧/中毒/聚气/疾行/huti护盾/jingci荆棘反弹/buqu不屈复活）；`battles.json` 加 `turn_mode`（atb/se）；`enemies.json.speed` 已消费。
- **M2 演出**：`battle_director.gd`(CombatDirector 顺序 await + 速度缩放/跳过/卡死防护) + `battle_view.gd`(BattleView 飘字/血条/真气条) + `unit_hud.gd`(UnitHud) + `BattleScene.gd`(只装配+输入转发)。
- **M3-1/2/3**：AI 权重选技能（`enemies.json.abilities={id,weight,condition}` + `_normalize_abilities` + `_pick_enemy_ability` 确定性加权，自buff 免自伤）+ 状态引擎扩护盾/反弹/复活（`_apply_status` SHIELD 特例 + `_resolve_hit` 护盾吸收/反弹 + `_try_down` 复活，修致命 DoT 不致死缺口）+ 演出动效令牌化（`ui_anim.json` battle 块由 UI 窗口补完，Director 由 `_FALLBACK` 接管真实令牌）。
- **战斗模块核检修复（2026-08-29）**：⑤ 自动战斗加 `MAX_AUTO_ROUNDS=200` 防死循环；④ ATB 真实插队（`get_round_sequence()` + `enemy_act` 按序列驱动）；② 删零调用方 `CombatCharacter.basic_attack`；逃跑 `try_escape` 改走内核 SeededRNG；`action_order` 仅存活单位；新增 `test_battle_turn_order`(3/0)。未动手：①TownScene 掉血崩(已派单 gameplay/town)、③PlayerState.speed 字段(共享数据窗)、ability_service.take_damage 路径(ability 窗)。

## 背包层现状（P0/P1 + Phase3 物品扩张）
- `inventory_service.gd`：三栏（主30/材料200/任务50）+堆叠+负重+ISaveable；事务 API（`query_add`/`can_add`/`try_consume` 两遍式原子扣料）+ iid 发号器(`next_iid` 进存档)。
- **背包窗口自查修复（1bab4f4）**：① `try_consume` 同 item_id 多条需求按 id 聚合校验/扣料（修旧逐项漏算总量）；② `move_instance` 加类型不变式守卫（拒绝武器/丹药拖入材料/任务栏，保持 add_item 路由不变量）→ **此守卫与 UI `inventory_smoke.gd` 跨栏断言冲突曾致 gate[3] 红（派单 `f1e8ac0c4ce7`）；2026-08-29 UI 窗口对齐自有 smoke 用例到该已确立契约，gate[3] 转绿，背包窗契约不变**。补 2 条回归测试（库存 28→30 全绿）。
- 用药链路：城镇=InventoryService.use_item→PlayerState；战斗=CombatService.player_use_item→战斗快照。UI 入口：BattleScene"物品"菜单 + InventoryScreen"使用"按钮。
- Phase 3 物品扩张两轮：17→36（`1862bda`）→ 64（`0720ba9`，武侠主题 +28 件）。
- 已知协作风险（已派单）：A. `inventory_add_overflow` 满包溢出信号游戏内无订阅方→静默丢物（open `37c9ca18f539` 派 UI 窗）；B. `inventory_weight_changed` 信号无订阅方（死信号，非 bug）；C. `romance_service.propose` 聘礼跳过锁定（open `acf2246fd5f2` 派结缘窗）。

## 结缘层现状（模块18 · M1–M4 已交付，2026-08-29）
- **M1 好感度内核** `services/bond/bond_service.gd`(`BondService` extends ISaveable, key=`bond`)：好感度 6 级(0-100 夹紧)、送礼(loved+20/liked+12/disliked-5/neutral+3, 超5次×0.5衰减, 走 `InventoryService.consume_instance`)、好感度事件(阈值触发+奖励物品+奖励好感防递归+`fired_events`去重)。枚举 `core/enums/bond_enums.gd`(8枚举)；配置 `data/configs/bond/relations.json`(苏婉儿/张大彪/李苍松+样例)；EventBus 纯追加 5 信号；ConfigManager 纯追加 relations 加载器。
- **M2 姻缘内核** `services/bond/romance_service.gd`(`RomanceService` extends ISaveable, key=`romance`)：无限配偶(`spouses` Dict)、`can_propose`+`propose`(写配偶+推进MARRIED+聘礼校验)、子嗣数据层(`begin_intimacy`+`advance_days(n)` 孕期300游戏日、到期分娩、广播 `bond_child_born`，时间源解耦)。EventBus 纯追加 4 信号。
- **M3 关系网数据中枢** `services/bond/relationship_service.gd`(`RelationshipService` extends RefCounted, 无状态门面、不进存档、不碰 screens.json)：`get_relationship_graph()` 聚合 Bond+Romance；另供 `get_marriageable_npc_ids()`(右上角红点)、`get_spouses_enriched()`、`get_children()`、`get_summary()`。
- **M4 结义+师徒+关系图自动纳入**：`sworn_service.gd`(`SwornService` key=`sworn`，无限结义、`can_sworn`/`sworn`、广播 `bond_sworn_formed`)；`master_service.gd`(`MasterService` key=`master`，双向 masters/become_apprentice + apprentices/take_apprentice、`get_teachable_abilities`/`advance_grade`、广播 `bond_master_set`+`bond_apprentice_taken`)。RelationshipService 自动纳入三类关系（**UI 零改即见**）。`RomanceService.propose` 补 `bond_wedding_started`(消费地基预声明信号)。
- **小白配置**：加可结缘 NPC 只改 `relations.json` 复制一段，设 `is_romanceable:true`+礼物列表即可，不碰代码。
- 双闸门全绿：`--quit` 零错误；`run_all` 退出码0（全工程 13 套件 0 失败）。
- 预留对接点：① 关系网视图吃 `get_relationship_graph()`+监听 `bond_relationship_changed/romance_formed/affection_changed/child_born`；② 右上角屏 `BondRomanceScreen`(UI 模块建脚本+注册 screens.json, 打开 `UIManager.open_screen("BondRomanceScreen")`, 红点轮询 `get_marriageable_npc_ids`)；③ 子嗣等 TimeService/休息动作喂 `advance_days` 即跑通（⚠️ 当前"休息/睡觉"未驱动天数，open `178267684159` 派背包窗）。

## UI 窗口现状（门禁加固 + 姻缘面板/婚礼演出 M3）
- **门禁加固（a25a89e）**：`tools/signal_audit.py`(v4) 全量扫信号/处理器参数 argc，DEFINITE=信号实参超处理器形参（运行期必崩）。实测 92 信号/823 函数/130 连接点，仅 **1 DEFINITE = `TownScene.gd:52`**（`player_hp_changed`(2)→`_on_player_changed`(1)，gameplay/town 主权，已派单 `fed3f00da584`）。UI 已修 2 处真崩：`AttributesScreen._on_changed`、`Hud._refresh` 均扩 3 参。
- **姻缘面板 + 婚礼演出 M3（de89642，提交 UI 模块收口）**：
  - 姻缘/关系网面板 `scenes/ui/screens/bond_romance/BondRomanceScreen.gd` + `screens.json` 注册 `BondRomanceScreen`；HUD 右上角"姻缘"按钮（`UIFeedback` 悬停音效）+ **红点徽标**轮询 `romance_service.get_marriageable_npc_ids()` 实时更新；面板消费 `bond_relationship_changed`(0参, 安全) 刷新。
  - `advance_days` 接时间流：`GameManager._on_world_day_advanced` 把天数差喂 `romance_service.advance_days(delta)`（读取/新档 `_sync_day_baseline` 设 `_last_known_day`），子嗣孕期真正流逝。
  - 公开 API 扩：`bond_service` 结义/师徒 + `hold_wedding(npc_id)`（要求 `is_spouse`，emit `bond_wedding_started(npc_id, wedding_type, scene_path)`，`scene_path` 取 `relations.json` 的 `wedding_scene`）+ `GameManager.last_wedding` 缓存 + `_on_bond_wedding_started` 切场景。
  - 婚礼演出 `scenes/gameplay/bond/WeddingScene.tscn`(Control 根, 镜像 BattleScene 格式, `--quit` 可导入)；"礼成" `change_scene_to_file(SCENE_TOWN)` 回城。
  - 变更通告 `docs/变更通告_2026-08-29_姻缘面板与婚礼演出.md`。双闸门全绿；`signal_audit` 仅余 1 条预存在 cross-window DEFINITE。
- ~~`37c9ca18f539`~~ **[done]** `inventory_add_overflow` 信号无游戏内订阅方（满包静默丢物）→ UI 窗口已在 `autoload/ui_manager.gd` 全局订阅并弹 Toast（2026-08-29，变更通告 `docs/变更通告_2026-08-29_UI背包溢出订阅.md`）。
