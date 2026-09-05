# 17_Simulation_Balance_Performance施工图_V1.2

> 状态：**FROZEN**（2026-09-06 架构 Owner 批准；可依此实施）
> 序列位置：施工图序列 17/18（01 §128 Phase A）
> 证据基线：2026-09-05 机器实测（全库 .gd 静态扫描 131+13 文件 + 数值表全景 + 模拟链路追踪）
> 上游：项目宪法 V1.2（最高执行标准）→ 01 总体架构 → 06 Actor/Scheduler → 07 时间域 → 10 经济 → 11 战斗 → 04 测试基建 → 16 内容生产

---

## 0. 编号命名空间声明（冲突检查）

本图启用 **SBP**（Simulation / Balance / Performance）命名空间：

| 段 | 归属 | 说明 |
|---|---|---|
| `SBP-1 ~ SBP-8` | 本图冻结契约 | 模拟/平衡/性能 8 件套 |
| `P-SB1 ~ P-SB10` | 本图实锤 | 机器扫描证据，带文件行号 |
| `SBP-R01 ~ SBP-R12` | 本图 Enforcement | 规则 → Gate 矩阵 |
| `SBP-1 ~ SBP-4`（§7） | 本图开放问题 | 必须用户/ADR 裁决，AI 不得自决 |

**撞号检查**：01~16 已占用 T / I / O / CT·CO·VA·PK·VE·DM·C / AC / WT / RF / IE / EC / AB / QD / SV / PV / ST / CP。**SBP 无撞号**。实锤前缀 `P-SB` 与 13 存档域 `P-S` 不同名，不冲突。

**编号接管声明**：本图**不接管**任何前序编号——
- 天气 `randi()`、AdvanceTimeCommand 唯一入口、TimeConsumer 注册制在 **07 WT**（本图引用其冻结，补充证据）；
- 冷却双时钟、randf 兜底退役、attribute_table 唯一真源在 **11 AB-4/AB-5/AB-6**（本图给确定性裂缝的**全量证据清单**，归属不变）；
- 团灭死亡惩罚 DebtRule+LoseItemsRule 在 **10 EC-7**（本图冻结消费端对接）；
- NPC Scheduler 五态 Tick 在 **06**（本图只冻 Simulation Level 四档定义）；
- 缓存/装载机器在 **05 Cache/Loader**（本图不重复冻结）；
- 孕期 pregnancy 结构细节归属 **08 RF**（本图只登记双时间源混用现象）。

---

## 1. 定位

**17 号 = Simulation / Balance / Performance Hardening**：治理「世界如何运转、数值从哪来、跑得多快」三件事——模拟的时间与确定性纪律、平衡数值的真源与难度系统、性能的预算与防回归。

**与邻图的分工（一句话）**：07 管**时间怎么走**（Advance 命令与事件）；06 管 **NPC 怎么被调度**（Scheduler 五态）；11 管**战斗怎么算**（公式与确定性）；05 管**数据怎么装载**（Cache/Index/Lazy）；17 号管**三者的横切纪律**——随机源从哪来（确定性）、数值表怎么管（平衡）、预算怎么立与守（性能）。前四图是器官，本图是体检标准。

**宪法锚点**：
- **§93 性能原则**（L4106~4117）：不优化不存在的瓶颈，但架构必须支持七件套（Cache/Index/Lazy Loading/Batch Query/Snapshot/Object Pool/Simulation Tick）；**Domain 不得为了性能直接依赖 Godot**；
- **§94 大世界/NPC 性能**（L4120~4135）：禁每 NPC 每帧完整 AI / 每帧扫整个世界 / 每帧查数据库；采用 Tick/Schedule/Interest Area/Event/**Simulation Level**；NPC 四档 Full/Reduced/Background/Dormant；
- **§94A Performance Budget / Simulation Budget**（L4138~4163）：「不提前优化」≠「不设预算」；13 项关键系统预算清单；7 条预算规则（数值由真实 Profile 建立**不写死万能毫秒数** / 超预算先 Profile / **不许为过 Gate 破坏 Domain 边界** / 优化改变可观察业务结果=业务变更 / **Simulation Level 切换须一致性测试** / 固定规模基准场景进 Regression Suite）；
- **§121 Simulation + §122 Headless 优先**（L4564~4592）：Fast World Simulation 一天推演（Schedule→Faction→Economy→Quest→Relationship）全部 Headless 可跑——Domain 必须 Headless 运行；
- **§216 Performance Regression Governance**（L6321~6337）：每个 Benchmark 存基线（输入规模/环境/结果分布/允许波动/版本）；**性能修复完成后 Benchmark 不删除**；功能正确但超 Release Budget = FUNCTIONAL PASS，**不能是 RELEASE PASS**；
- **§230 第一阶段禁止项**（L6737~6751）：全量 NPC 社会模拟 / 10000 NPC 性能极限优化 / 全面多线程化 等 VS-001 前禁止冒充 ACTIVE——本图的 YAGNI 边界。

**一句话**：随机要有户口（Seeded）、数值要有表格（真源）、性能要有体检（预算+回归），三者都为「Headless 可跑、回放可复现、回归可拦截」服务。

---

## 2. 现状盘点（机器扫描证据，2026-09-05 实测）

### 2.1 资产表（宪法 §171：升级不丢弃）

| # | 资产 | 实测 | 处置 |
|---|---|---|---|
| 1 | `core/utils/seeded_rng.gd` | SeededRNG 封装（chance/randf，注释 L4 明令战斗逻辑禁全局 randf） | **确定性正主，冻结**（11 AB-6 宿主） |
| 2 | `services/combat/combat_core.gd` | 607 行最高质量内核；L212/240 敌人 AI 选招走 `rng.randf()`（seed 驱动） | 11 AB 冻结，本图引用 |
| 3 | `autoload/difficulty_manager.gd` | 138 行难度宿主：指令事件驱动 + game_loaded 刷新缓存 + **11 个对外 API**（四倍率/逃跑/AI Profile/团灭 9 字段）；L5 铁律「禁止业务按 difficulty_id 写 if」 | **Balance 域最佳实践，冻结收编**（SBP-4） |
| 4 | `data/configs/difficulty/difficulty_table.json` | 5 档（EASY→HELL）× 20 字段：四倍率、逃跑、AI Profile 四种、团灭行为三种（RESPAWN/LOAD/DELETE）+扣钱/丢物/负债/CG 全套 | 数值真源收编（SBP-3）；version "1.0" 违例（P-SB6） |
| 5 | `data/configs/combat/attribute_table.json` | 战斗换算表：derive_mode 开关 + 五维权重 + 判定上限 + 防御软上限公式（1-K/(K+def)）+ 成长曲线；**消费面实装**（combat_character.gd L33-146 flat/five_attr 双模式派生管线） | 11 AB-4 已冻结，本图补预埋段管理（SBP-8） |
| 6 | `autoload/weather_time_service.gd` | 148 行世界时钟：**无 tick 显式推进**（L5 铁律注释）、ISaveable、季节按 season_days 推算、天气按权重表重掷、三信号（day_advanced/weather_changed/time_changed） | **Simulation 正主，冻结**（SBP-2）；L140 randi 归 07 WT |
| 7 | `data/configs/world/world_config.json` | season_days=15 + 四季天气权重表（7 种天气×4 季）+ 起始态 | 数据化标杆 ✓（version 1.0.0） |
| 8 | 战斗奖励数据面 | `battles.json` reward_exp + `enemies.json` loot 数组 + `_grant_rewards` 带 `drop:<enemy_id>` 留痕 | 数据真源 ✓；发放面绕事务（P-SB7，归 11/10） |
| 9 | 缓存/池/异步文化 | **全库 189 处 cache 命中**：ConfigManager 对话 LRU（L746-787）、core/resource_manager 引用计数 LRU、dialogue 条件缓存 TTL 1s（L282-285）、Toast 对象池、SFX 流缓存、立绘 LRU+预热（portrait_cache_manager）、inventory count 索引（P2-7）、异步场景加载+分帧释放+流式视频 | §93 七件套已实践五件；**§171 收编为性能资产清单**（SBP-6 基准对象） |
| 10 | 性能优化注释文化 | 13 处历史优化标注（GameManager 异步加载、battle_entity 弹字排队 7.3.5、tactical 分帧释放 P2、双立绘预热等） | 知识随代码走，鼓励延续 |
| 11 | `tests/unit/test_phaseA_world.gd` | 天气/季节推进测试（advance_day 15×4 季节轮转） | Simulation 首批测试资产收编 |
| 12 | `data/configs/npcs/npc_stats.json` | NPC 面板属性占位（2 个 NPC，_doc 自认预留） | 数值真源待扩展（P-SB5 违 I-5） |
| 13 | EventBus 世界信号面 | world_day_advanced / world_weather_changed / world_time_changed（L169-173）三信号 | 07 冻结，本图登记消费面 |

### 2.2 实锤 P-SB1 ~ P-SB10

> 扫描口径：autoload/services/scenes/core 131 文件 + data/ 13 文件；模式 = 每帧入口 / 随机源 / Timer / 计时 / 缓存 / TODO。

| # | 实锤 | 证据 |
|---|---|---|
| **P-SB1** | **确定性裂缝：业务概率走全局随机源 5 处**（11 AB-6「randf 兜底退役」的全量证据清单）：<br>① `combat_service.gd:417` try_escape 回退分支 `randf() < chance`（L414-417 双路径：有 `_core.rng` 走 Seeded，null 回退全局——同一战斗回放可复现性被回退分支破坏）；<br>② `data/runtime/combat_character.gd:72` dodge 判定、`L78` crit 判定同款回退（`rng.chance(x)) or (rng == null and randf() < x`；**注释 L66 自认「rng 为 null 时回退全局 randf()（不可复现）」——明知故犯的兼容分支**）；<br>③ `weather_time_service.gd:140` 天气重掷 `randi() % total`（07 WT 已登记归属）；<br>④ `romance_service.gd:435` **受孕判定** `randf() < chance`（conceive_chance 配置驱动但走全局随机——回放中受孕结果不可复现）；<br>⑤ `math_util.gd:14` `randf() < rate`（**全库零调用方的死代码**——chance 判定宿主在 core 层用全局随机但无人用） | 逐处行号（左）；对照好消息：combat_core L240 / combat_service L415 / seeded_rng.gd 主力已走 SeededRNG |
| **P-SB2** | **GameManager._process 四职责混合**（L230-240）：①冷却 tick（ability_service.tick_cooldowns）+ ②每秒 buff 过期清理（_buff_tick_accum 累加器）+ ③异步加载轮询（_poll_async_loading/_poll_preloads）+ ④加载动画（_animate_loading_overlay）。11 AB-5 已登记「每帧递减迁 Application」——本图补充结构面：单函数四职责无预算归属 | GameManager.gd L226-240 |
| **P-SB3** | **每帧世界扫描（§94 字面对照）**：TownScene._physics_process L390-393 每帧遍历全部 `_npc_nodes` 算距离找最近 NPC（O(N)/帧）。**当前 15 NPC 规模无实际瓶颈**——按 §93「不优化不存在的瓶颈」登记为规模水位监控项而非整改项；NPC 数超水位线时按 §94 Interest Area 改造 | TownScene.gd L374-394 |
| **P-SB4** | **attribute_table 预埋死配置**：judgment / growth / weapon_range 三段**全库零消费点**（grep 仅 derive_mode/five_attr/soft_cap_k 有消费）——_doc 自认「阶段A 仅存档 / 阶段B 启用」的**有意预埋**（与 10 图 P-E7 restock 无声明死配置同族但性质不同）。处置=登记冻结非删除（SBP-8 声明制） | attribute_table.json L13-38 + 全库 grep |
| **P-SB5** | **npc_stats.json 显示名引用**：martial_arts 存中文显示名数组（"村中拳法"/"乞讨十八式"）非 abil ID 引用——违 I-5「引用只存 ID」；gift_prefs 同（"茶叶"/"好酒"）。_doc 自认占位，仅 2 NPC | npc_stats.json L9-10/L20-21 |
| **P-SB6** | **难度主表 version 违例**：difficulty_table.json L2 `"version": "1.0"` 非 x.y.z（P-CP4 已登记三文件之一，Balance 主表点名——它是全库消费面最广的数值表之一） | difficulty_table.json L2 |
| **P-SB7** | **奖励发放绕事务**（数据真源 ✓、发放面 ✗）：`_grant_rewards` L456 `ps.gain_exp(battle["reward_exp"])` 直调 + L460 `add_item(...)` 直调（**留痕格式 `drop:<enemy_id>` 正确**）——11 图 P-C3 同源，0-C Mutation Journal 视角的战斗域缺口；silver 掉落现状为零（enemies.json 无 silver 字段，设计空白非缺陷） | combat_service.gd L452-460 |
| **P-SB8** | **性能资产丰富 vs 预算机制零建立**：缓存/池/异步文化 189 处（资产表 #9）但 **§94A 13 项预算全库零 benchmark 文件、零基线、零 Performance Regression Suite**；§216 五字段基线格式无宿主。「架构支持性能」已达，「性能可测量」未起步 | 全库无 benchmark 目录/文件；cache 扫描 189 处 |
| **P-SB9** | **Simulation 双时间源混用（孕期）**：`romance_service.gd` L383/L437 pregnancy.start_day 存 `Time.get_unix_time_from_system()`（**Unix 墙钟秒**）但字段名叫 **day**；L7 注释自认「时间源解耦为 advance_days(n) 由天数喂」——**同一 pregnancy 结构混用 Unix 墙钟与游戏天数两种时间源**（实际推进走 advance_days L602→L612-634，start_day 仅记录；违 07 W「Time 单调」精神）。归属 08 RF 核查，本图登记 | romance_service.gd L7/L383/L437/L602-634 |
| **P-SB10** | **每帧入口全景 + 零 TODO**：全库 12 处 _process/_physics_process/_unhandled_input（GameManager 1 + TownScene 2 + UI 9；拖拽类 2 处有 _dragging 守卫低风险）；**零 TODO/FIXME/HACK**、零 set_process 动态切换——每帧热点面小且静态，是预算化的良好起点 | 扫描全景（资产表 #10 同源） |

---

## 3. 冻结契约 SBP-1 ~ SBP-8

### SBP-1 确定性纪律（承接 11 AB-6，给全量证据清单）

| # | 冻结内容 |
|---|---|
| a | **业务概率判定禁全局随机源**：`randf()/randi()/randomize()` 只许出现在（①SeededRNG 内部实现 ②表现层装饰豁免清单）；业务判定（战斗/结缘/天气/经济/任务）一律走 SeededRNG |
| b | **回退分支退役路线**：combat_service L417、combat_character L72/78 的 `rng == null and randf()` 回退分支随 11 AB-6 Phase 迁移删除——**回退到不可复现不是容错，是确定性裂缝**；rng 缺失应 FATAL 而非静默降级 |
| c | **表现层装饰豁免清单**（冻结）：GameManager L193 加载提示随机、TownScene L205 装饰相位——不影响业务结果与回放，登记豁免；清单外新增随机调用 = 违规（SBP-R02） |
| d | math_util.gd 死代码 chance 函数退役（全库零调用方，零迁移成本；开放问题 SBP-2 确认处置方式） |

### SBP-2 Simulation Tick 契约（承接 07 WT / 06 Scheduler）

| # | 冻结内容 |
|---|---|
| a | **无 tick 显式推进 = 本项目标准形态**（weather_time_service L5 模式收编）：时间只在被显式推进时流动（睡眠/赶路/事件触发），禁自带 tick 的全局模拟循环——与 07 WT AdvanceTimeCommand 唯一入口咬合 |
| b | **NPC 四档定义冻结**（§94）：Full（在场每 Tick 完整）/ Reduced（低频 Tick 关键项）/ Background（事件驱动+低频）/ Dormant（零开销仅存档态）。**当前只实装 Full**（单城镇 15 NPC），档位切换机制延后（开放问题 SBP-1）；四档切换必须配 §94A 规则 6 一致性测试 |
| c | **Interest Area 禁实装**（§230 YAGNI）：登记为 §94 大世界阶段预案，TownScene 每帧距离扫描（P-SB3）保持现状 + 规模水位监控（NPC 数 > 50 触发改造评估） |
| d | **世界日消费面注册制**：world_day_advanced 消费方须显式 connect 并登记（现状仅 GameManager L221 扇入孕期）；新增消费方走 07 TimeConsumer 注册制，禁隐式轮询天数 diff |

### SBP-3 平衡数值真源集中（承接 11 AB-4 / 16 CP）

| # | 冻结内容 |
|---|---|
| a | **Balance 数据真源全景冻结**：难度倍率 = difficulty_table.json；战斗换算 = attribute_table.json；天气 = world_config.json weather_weights；战斗奖励 = battles.reward_exp + enemies.loot；NPC 面板 = npc_stats.json；经济 = shops/prices（10 EC）。「数值全进 JSON」铁律的 Balance 域落点即此六表 |
| b | **禁新增硬编码系数**：新数值系数必须入对应真源表；确需临时硬编码的必须 `_doc`/注释声明阶段与去留（与 SBP-8 声明制联动） |
| c | **npc_stats 升级路线**：martial_arts/gift_prefs 改 ID 引用（abil_/item_ 域，随 06 NPC 域迁移 + 16 CP-2 映射），显示名由 ID 查表派生（I-5 落地） |
| d | difficulty_table version 升 `1.0.0`（P-SB6，随 16 CP-4 一并处置） |

### SBP-4 难度系统收编（difficulty_manager 冻结）

| # | 冻结内容 |
|---|---|
| a | difficulty_manager.gd **零 if 判断铁律升级为全库规则**（L5 注释 → SBP-R10 扫描器）：一切难度差异走其 11 个对外 API，业务代码禁按 difficulty_id 写 if |
| b | 团灭字段消费端对接 10 EC-7：defeat_behaviour/lose_money/lose_items/debt_if_broke/lose_rarities 等执行时走 DebtRule+LoseItemsRule 契约（禁直接扣钱丢物）；cg_text_id 走对话演出链 |
| c | ai_behavior_profile 字段对接 11 AB-3 AIProfile 挂点（easy/default/aggressive/nightmare 四种 → 11 图 AI Profile 数据面） |
| d | 难度切换指令事件（cmd_set_difficulty + notify_difficulty_change_rejected）= Command 化过渡白名单成员（14 PV-2 同期处置） |

### SBP-5 预算机制建立（§94A 落地，分期）

| # | 冻结内容 |
|---|---|
| a | **首批预算 3 项**（开放问题 SBP-3 确认）：Boot Time / Save Time / Combat Turn Resolution——对应已有垂直切片与 P0 风险面；其余 10 项按需分期，**禁一次全建**（§94A 规则 1：数值由真实 Profile 建立） |
| b | **Benchmark 基线文件格式冻结**（§216 五字段）：`{ benchmark_id, input_scale, environment, result_distribution, allowed_variance, version }`，JSON 存 `tools/benchmarks/`；无五字段 = 格式 FATAL（SBP-R07） |
| c | 预算值**不写进宪法/施工图**（§94A 规则 1），由 Benchmark 实测后登记进基线文件；施工图只冻结机制 |
| d | Benchmark 宿主形态：Godot `--headless --script` 基准脚本 + JSON 基线（开放问题 SBP-4 确认宿主与 Gate 槽位） |

### SBP-6 性能回归门禁（§216 落地）

| # | 冻结内容 |
|---|---|
| a | **Benchmark 永不删除**：性能修复完成后基准脚本与基线文件保留进 Regression Suite（防「修完就删、下月复发」） |
| b | **双 PASS 状态机**：功能正确但超 Release Budget = FUNCTIONAL PASS ≠ RELEASE PASS——状态写进 04 测试基建 verify_all V2 的 --tier 体系（Performance 为独立 tier） |
| c | **固定规模基准场景**：TownScene 现状（15 NPC + 每帧扫描）登记为首规模基准；每次大世界区域开放追加新基准场景（§94A 规则 7） |
| d | 超预算处置流程冻结：先 Profile → 再优化 → **禁为过 Gate 破坏 Domain 边界**（§94A 规则 4）→ 优化改变可观察业务结果 = 业务变更走变更流程（规则 5） |

### SBP-7 每帧纪律（§94 字面化）

| # | 冻结内容 |
|---|---|
| a | **三禁令机器化**（§94）：`_process/_physics_process` 内禁完整 AI 逐帧执行 / 禁世界全量扫描（get_children 全遍历找对象）/ 禁逐帧查询数据库（ConfigManager 查询在循环内）——静态扫描器登记新增 |
| b | **每帧入口登记制**：新增 `func _process/_physics_process` 须登记（宿主文件+职责一句话+预算归属）；现状 12 处全景冻结为基线（P-SB10） |
| c | GameManager._process 拆分路线（承接 11 AB-5）：冷却 tick 迁 Application 计时器、buff 清理保留每秒累加器、加载轮询/动画迁 LoadingScreen 自持——拆分后 _process 归零或单一职责 |

### SBP-8 预埋配置声明制

| # | 冻结内容 |
|---|---|
| a | **预埋段必须 `_doc` 声明启用阶段**（judgment「阶段B 启用」/ growth「阶段D 调参」为范例格式）；无声明的零消费配置段 = 死配置违规（10 图 P-E7 同族拦截） |
| b | attribute_table 预埋三段（judgment/growth/weapon_range）登记为冻结预埋，阶段 B/D 启用时走变更流程 |
| c | derive_mode 开关 = 数值演进标准形态（flat↔five_attr 零回归切换已实装收编）；未来数值层升级优先「新开关+并行模式」禁原地改语义 |

---

## 4. 现有资产迁移映射表（绞杀者分批）

| 现状 | 目标 | Phase | 备注 |
|---|---|---|---|
| math_util 死 chance 函数 | 退役/收编 | **Phase1**（零调用方零风险） | SBP-2 开放问题确认方式 |
| 3 处 rng==null 回退分支（combat_service/character ×2） | 删除回退，rng 缺失 FATAL | **Phase2~3**（随 11 AB-6） | P-SB1①② |
| romance L435 受孕 / weather L140 天气 randi | SeededRNG 注入 | **Phase3**（weather 归 07 WT 迁移） | P-SB1③④ |
| difficulty_table version "1.0" | 升 1.0.0 | **Phase1** | 随 16 CP-4 |
| GameManager._process 四职责拆分 | 各归其位（AB-5 承接） | **Phase3** | P-SB2 |
| 首批 3 项 Benchmark + 五字段基线 | tools/benchmarks/ 建立 | **Phase1~2** | SBP-5；Phase0 测量先行 |
| TownScene 固定规模基准入 Suite | Regression Suite 首成员 | **Phase2** | SBP-6c |
| 每帧登记制 + 三禁令扫描器 | 挂 GATE（15 ST-6 注册表） | **Phase2** | SBP-7；SBP-R03/04 |
| npc_stats ID 化 + 难度 defeat_* 走 EC-7 | 06/10 域迁移时顺带 | **Phase4** | P-SB5 / SBP-4b |
| NPC 四档 / Interest Area | 只冻定义不实装 | **Phase5+**（大世界阶段） | SBP-2b/c；§230 |

---

## 5. Freeze 清单（`SIM-BAL-PERF v1.2.0`）

1. 业务概率禁全局随机源 + 表现层装饰豁免清单（GameManager L193 / TownScene L205 两处冻结）；
2. 回退分支即裂缝原则（rng 缺失 FATAL 禁静默降级）；
3. 无 tick 显式推进标准形态 + NPC 四档定义 + Interest Area 禁实装；
4. Balance 六表真源全景（difficulty/attribute/world_config/battles/enemies/npc_stats）；
5. difficulty_manager 零 if 全库规则 + defeat_* 走 EC-7 + ai_profile 对接 AB-3；
6. Benchmark 五字段基线格式 + 永不删除 + 双 PASS 状态机 + 固定规模基准场景；
7. 三禁令（每帧 AI/扫世界/查库）+ 每帧入口登记制 + 现状 12 处基线；
8. 预埋配置 `_doc` 声明制 + derive_mode 开关范式。

---

## 6. 完成定义（DoD，7 条）

1. 随机源基线建立：业务面全局 rand 调用 = 0，豁免清单（2 处表现层装饰）冻结在案，静态扫描器可证；
2. 3 处 `rng == null` 回退分支删除，rng 缺失路径 FATAL；
3. 首批 3 项 Benchmark 存在且基线文件五字段齐全（input_scale/environment/result_distribution/allowed_variance/version）；
4. TownScene 固定规模基准进入 Regression Suite，verify_all 可选 tier 可跑；
5. 每帧入口基线（12 处）登记在案，三禁令扫描器上线且零违例；
6. difficulty_table version x.y.z + attribute_table 预埋三段 `_doc` 阶段声明齐全；
7. GameManager._process 拆分完成：冷却迁 Application、_process 归零或单一职责。

---

## 7. 开放问题（必须用户/ADR 裁决，AI 不得自决）

| # | 问题 | 倾向（AI 建议，仅供决策参考） |
|---|---|---|
| SBP-1 | NPC 四档（Full/Reduced/Background/Dormant）实装时机：VS-001 前只冻定义 vs 提前实装 Reduced | **只冻定义**（推荐）：当前单城镇 15 NPC 距离任何性能水位都很远（§93 不优化不存在的瓶颈）；§230 明令 VS-001 前禁全量 NPC 社会模拟。四档切换的一致性测试成本高，无收益先不付 |
| SBP-2 | math_util.gd 死 chance 函数处置：直接删除 vs 收编进 SeededRNG 作为唯一随机判定入口 | **直接删除**（推荐）：全库零调用方（grep 仅文件头自引用），零迁移成本；SeededRNG 已有 chance()，无需第二入口。若未来需要 core 层无 RNG 依赖的纯判定工具，届时按需重建 |
| SBP-3 | 首批预算选哪 3 项：Boot/Save/Combat Turn（AI 推荐）vs 加 Content Lookup/World Sim Tick | **Boot/Save/Combat Turn**（推荐）：Boot 对应异步加载链已有资产、Save 对应 13 SV-5 原子写与 P0 风险面、Combat Turn 对应 11 确定性回放——三项都有现成测试宿主，Benchmark 改造成本最低；Content Lookup 随 16 CP-5 校验器上线后再测 |
| SBP-4 | Benchmark 宿主形态：Godot --headless --script 基准脚本 + JSON 基线 vs 并入现有 GATE 工具链（如 verify_all 新 tier） | **--script 基准脚本 + JSON 基线文件，注册进 verify_all 可选 tier**（推荐）：基准脚本独立可跑（开发期随时手动跑），verify_all 只做「跑基准→比对基线→报 PASS/FAIL」的门禁壳；物理槽走 GATE40+（15 ST-6 注册表），LN 编号随 04 T-1 追认 |

---

## 8. Enforcement：规则 → Gate 矩阵 SBP-R01 ~ SBP-R12

> E0 = 当前执行率 0%；Gate 槽位归属遵循 15 ST-6 统一注册表；扫描器均为新增工具（REPORT 模式起步，基线稳定后转拦截）。

| # | 规则 | 级别 | 执行点 | Gate |
|---|---|---|---|---|
| SBP-R01 | 业务概率判定禁全局 `randf/randi/randomize`（白名单 = SeededRNG 内部 + 豁免清单） | FATAL | 随机源扫描器（白名单基线） | GATE06 |
| SBP-R02 | 表现层装饰随机豁免清单外新增随机调用 | ERROR | 同上 | GATE06 |
| SBP-R03 | 新增 `_process/_physics_process` 须登记（宿主+职责+预算归属） | ERROR | 每帧入口登记基线 diff | GATE06 |
| SBP-R04 | 三禁令（每帧完整 AI/世界全量扫描/循环内配置查询） | ERROR | 静态启发式扫描器 | GATE06 |
| SBP-R05 | 数值系数禁硬编码（新系数入六表真源；临时硬编码须注释声明阶段） | ERROR | 审查型扫描 + 变更审计 | GATE06 |
| SBP-R06 | 预埋配置段必须 `_doc` 声明启用阶段（无声明零消费段 = 死配置） | ERROR | 配置审计器（16 CP-5 语义层复用） | GATE06 |
| SBP-R07 | Benchmark 基线文件五字段格式（input_scale/environment/result_distribution/allowed_variance/version） | FATAL | 基线格式校验 | GATE40+ |
| SBP-R08 | 性能修复后 Benchmark 不得删除（Suite 文件审计） | FATAL | Suite 清单核对 | GATE40+ |
| SBP-R09 | 超 Release Budget = FUNCTIONAL PASS ≠ RELEASE PASS（双 PASS 状态机） | ERROR | verify_all V2 --tier 状态机 | GATE40+ |
| SBP-R10 | 业务代码禁按 difficulty_id 写 if（一律走 DifficultyManager API） | ERROR | 静态扫描器（difficulty_id in condition） | GATE06 |
| SBP-R11 | Simulation Level 档位切换必须附一致性测试（启用时生效） | FATAL | 登记制（启用前无此 Gate） | 未来 |
| SBP-R12 | world_day_advanced 消费方注册制（禁隐式轮询天数 diff） | ERROR | TimeConsumer 注册表核对（07 W 承接） | GATE06 |

---

## 9. 17 的一句话总纲

**随机走种子、数值进真源、每帧有户口、预算五字段、基准永不删；不优化不存在的瓶颈，但超了预算先 Profile 且不破 Domain。**

---

## 10. 关联文档

- 项目宪法 V1.2（§93 性能原则 / §94 大世界 NPC / §94A Performance Budget / §121 Simulation / §122 Headless / §216 Performance Regression / §230 第一阶段禁止项）
- 01_总体架构施工图_V1.2.md（§92 Validators / §127 Gate 体系 / §128 Phase A 序列）
- 04_测试基建施工图_V1.2.md（verify_all V2 --tier / golden 基线体系——Benchmark 门禁宿主）
- 06_Actor_NPC施工图_V1.2.md（Scheduler 五态 Tick / NPC 数据契约）
- 07_Time_Weather施工图_V1.2.md（AdvanceTimeCommand / TimeConsumer / 天气 randi 归属）
- 08_Relationship_Faction施工图_V1.2.md（pregnancy 双时间源核查归属）
- 10_Economy_Shop_Crafting施工图_V1.2.md（EC-7 团灭惩罚 / P-E7 死配置同族）
- 11_Ability_Combat_CombatAI施工图_V1.2.md（AB-3 AIProfile / AB-4 数值真源 / AB-5 冷却 / AB-6 确定性）
- 15_Studio_Authoring_Validator_Preview施工图_V1.2.md（ST-6 校验器注册表——新扫描器挂载点）
- 16_Content_Production施工图_V1.2.md（CP-4 版本契约 / CP-5 校验器群 / P-CP4 version 违例）
- ACR-0001（迁移总纲：施工范围未批，本图为契约文档，不含实现代码）
