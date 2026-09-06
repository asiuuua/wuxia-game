# 07 World / Time / Schedule 施工图 V1.4 修复版

| 项 | 值 |
|---|---|
| 状态 | **FROZEN**（2026-09-06 用户批准；可依此实施） |
| 日期 | 2026-09-05 |
| 上游 | 宪法 V1.4（0-C.15 四层 Scheduler / §79 Game Clock / §78 Deterministic Random / 0-F.6 VS-004 / §80 Debug 三级标签 / L677 回放记录）→ 01 §53 World·§54 Schedule·§67 World Simulation Scheduler·§112 VS-004 → 02（GameClock/RandomProvider/Command 事务）→ 04（双替/回放）→ 06（Materialize 触发权/schedule_ref 挂点） |
| 范围 | 冻结 8 件：World State Owner / Time 契约 / Calendar / Weather / Schedule 四件套 / 推进事务化 / World Simulation Scheduler / Save·回放 |
| 冻结物 | `WORLD-TIME v1.2.0`（见 §12） |

---

## 0. 定位

> **V1.4 修复版总注**：本图随宪法 V1.4（ADR-0005）与 01 图 V1.4 修复版同步升版——①宪法条款号零漂移，正文「宪法 §N / 0-C.x / 0-F.x」引用全部有效；②RULE 001 放软：Domain 经白名单 Adapter/Boundary 触达 Godot 属合法协作（判据=0-E.3/GATE15，白名单升表随 ACR）；③本图冻结契约与冻结物版本零变化，V1.2 原稿保留（§171 收编不丢弃）。域内衔接：IGameClock 装配注入（01 图 §29 直修）与本图 Time 契约同口径；0-C.15 推进事务化与 0-C 章零变化声明一致（V1.4 0-C 20 条全保留）。

时间是世界的心跳：**所有「过了几天」引发的变化（孕期/子嗣成长/店铺刷新/任务超时/世界事件）都从同一次心跳出发**。本图把心跳钉成契约——心跳本身可回放（确定性），心跳引发的变化走事务（0-C），心跳的消费者各有 Owner（不许谁私接电线）。

**铁律**：施工范围未批前只产文档不动代码（§104）。

---

## 1. 现状盘点（机器扫描证据，2026-09-05 实测）

### 1.1 已有资产（第 171 节：升级不丢弃）

| 资产 | 实测 | 处置 |
|---|---|---|
| `weather_time_service.gd`（147 行 autoload） | `advance_time(hours)` 跨日递归 `advance_day`；`advance_day(days)` 推季节+重掷天气；三信号 `world_day_advanced/world_time_changed/world_weather_changed`；debug 面 | 升级为 §2/§3 契约，壳保留 |
| `WorldTimeState`（data/runtime，ISaveable） | day / time_of_day(0-24 float) / season / weather 四字段 + save/load；**注释明写「自身不持有 Node」——形态正确** | 原样收编为 World Time State |
| `world_config.json` | season_days=15 · start_* · **weather_weights（4 季×7 天气权重矩阵）**——调参全在 JSON | 静态调参归 Definition，契约保留 |
| `world_enums.gd` | Season 4 / Weather 7 / TimeOfDay 4 相（DAWN/DAY/DUSK/NIGHT 按时刻分段） | 保留 |
| 休息推进链 | `romance_service.advance_days(n)`：子嗣加龄→孕期累加→满 gestation_days 分娩；`GameManager._on_world_day_advanced` 扇入 | 收编为 §6 推进事务的消费面 |

### 1.2 缺口（本图要补）

| # | 缺口 | 证据 |
|---|---|---|
| P-1 | **天气 RNG 用全局 `randi()`**——确定性破坏实锤；`seeded_rng.gd` 注释自己写着「严禁直接调全局 randf()」，天气 roll（L140 `randi() % total`）违反同族铁律 | weather_time_service L140 |
| P-2 | **推进无 Command/事务通道**：advance_time/advance_day 直改 state 直发信号；休息推进跨时间+子嗣+孕期+分娩多系统，**无事务边界**——正是反复出现的「扣钱不发货」P0 家族的同类形态 | romance_service L602-625 |
| P-3 | **child ID 撞车隐患**：`_birth` 生成 `child_%s_%d` 用 `children.size()+1`——子嗣被移除后序号复用，违 03 ID 铁律「永不复用」 | romance_service L628 |
| P-4 | **无 Calendar**：season 循环（4×15=60 天）无「年」概念、无日期格式化 API（01 §53 要求 Calendar） | world_enums/服务 |
| P-5 | **Schedule 四件套全缺**（01 §54：ScheduleDefinition/State/Rule/Entry）：NPC 无日程、Shop 无刷新、Quest 无超时、World Event 无定时；VS-004 整体缺失 | 全仓无 schedule 代码 |
| P-6 | **World State 无聚合 Owner**：时间天气在 WeatherTimeState、世界开关在 `GameState._global_flags`、区域静态在 `_map_index`——01 §38 的 World State Owner 形同虚设 | 分散实扫 |
| P-7 | **delta 语义缺失**：`world_time_changed` 每次发全量四元组，消费方无法知道「这次推进了多少」；01 §587 要求的 `TimeAdvancedEvent`（带增量）不存在 | 服务 L83-96 |
| P-8 | debug_set_* 无三级标签（宪法 §80：Production Safe / Development Only / Test Only） | 服务 L23-40 |

---

## 2. World State Owner（冻结项 1/8）

| # | 冻结内容 |
|---|---|
| WO-1 | **World 九词职责（01 §53 原文）**：Region · Location · Weather · Calendar · Time · World State · Spawn · Travel · World Event 归 World 域；**禁管清单（原文）**：UI · Scene · NPC Panel · Combat UI |
| WO-2 | **职责分派**：Region/Location→静态 Definition（05 RegionPack）；Spawn/Travel→06 Materializer/旅行 Command；本图实管=Time/Calendar/Weather/WorldState/WorldEvent 五项 |
| WO-3 | **聚合形态**：`WorldState`（RefCounted，Owner=World 模块）聚合 `WorldTimeState`（原样收编）+ `world_flags`（`_global_flags` 自 GameState 迁入，SetFlagEffect 的目标）；**区域静态不进聚合**（Definition 归 ContentRegistry） |
| WO-4 | **唯一写入口**：对 WorldState 的一切可变访问只经 Command（§6）；Query 只读快照 |

---

## 3. Time 契约（冻结项 2/8）

| # | 冻结内容 |
|---|---|
| T-1 | **WorldTime 实现即 02 GameClock 契约**：WeatherTimeService 降级为 Application 壳（autoload 过渡，Phase3 收敛），域逻辑入 World 模块 `WorldTimeService`（RefCounted，持 WorldState） |
| T-2 | **单调性冻结**：day 单调递增、time_of_day ∈ [0,24) 单调循环、season 由 day 派生（现 `_update_season` 公式保留为唯一实现）；**禁倒流 API 进生产**（回退只存在于 FakeClock 测试替身，宪法 §79） |
| T-3 | **delta 事件（补 P-7）**：新增 `TimeAdvancedEvent { delta_hours, from_day/to_day, cause }`（cause=rest/travel/command/debug）；`world_time_changed` 全量广播保留为「读数信号」，**消费方判定逻辑一律用 delta 事件，禁用全量信号做业务判断** |
| T-4 | **TimeOfDay 四相**（DAWN/DAY/DUSK/NIGHT）为 time_of_day 的派生分段（现 L65 公式保留）；四相名走本地化键（LN-G18） |
| T-5 | **AdvanceTimeCommand**：`{ hours | days, cause }`——时间推进的唯一合法入口（debug 直改除外，见 §7 WT-4）；休息/旅行/剧情跳时间全部收敛到此 |

---

## 4. Calendar（冻结项 3/8）

| # | 冻结内容 |
|---|---|
| CA-1 | **纪元公式（纯派生，零额外状态）**：`year = floor((day-1) / (4×season_days)) + 1`；`season_index = floor((day-1)/season_days) % 4`（与现实现一致）；`day_of_season = (day-1) % season_days + 1` |
| CA-2 | **只读 API**：`get_year() / get_season_day() / get_date_key() -> "Y2-Spring-D7"`（存档与日志用稳定英文键；显示名走本地化） |
| CA-3 | **YAGNI 挂点**：月/节气/节日不建——`CalendarDefinition`（JSON：节日表→WorldEvent 触发）留 manifest 挂点，需要时随内容包进来，不改代码 |
| CA-4 | **season_days 变更=内容变更**：改 15→20 属 Definition 变更，走 05 版本规则+旧档兼容判定（天数语义漂移须迁移步） |

---

## 5. Weather（冻结项 4/8）

| # | 冻结内容 |
|---|---|
| WE-1 | **禁全局随机（本图最高优先级规则）**：`_roll_weather` 的 `randi()` 必须替换为注入的 `RandomProvider`（02 契约，SeededRNG 实现）；P-1 是 K-R04 同族违例的活体 |
| WE-2 | **权重表保留**：`weather_weights`（4 季×7 天气）已 JSON 化，契约不变；roll 算法（累积权重抽样）保留但抽离为纯函数 `roll_weather(weights, rng) -> Weather`（可单测可回放） |
| WE-3 | **天气变化留痕**：`WeatherChangedEvent { from, to, cause }`；由 AdvanceTimeCommand 的 Mutation Journal 记录 before/after |
| WE-4 | **set_weather 直设仅限 Debug/剧情**：剧情强制天气走 Command（`SetWeatherCommand`，带 cause），debug 走三级标签面（§7） |

---

## 6. 推进事务化（冻结项 5/8 · 0-C 落地核心）

| # | 冻结内容 |
|---|---|
| TX-1 | **AdvanceTimeCommand → Transaction**：一次推进=一事务，Mutation Journal 记录全部 before/after——day/time_of_day/season/weather + 各消费面写入（孕期/子嗣/体力/店铺…）；**回滚=逆序 undo（02 契约），失败=RECOVERY_REQUIRED** |
| TX-2 | **消费面注册制**：时间推进的影响方（romance 孕期/子嗣、体力恢复、店铺刷新、任务超时…）注册为 `TimeConsumer`（`on_time_advanced(delta, ctx) -> Array[MutationRecord]`）；**禁各模块私听 delta 信号再各自直改**（现状 advance_days 直改模式收编为第一个 TimeConsumer） |
| TX-3 | **消费顺序冻结**：子嗣加龄先于分娩判定（现实现注释已明确，保留为契约）；同类消费者按注册序（注册序进 PROJECT_STATUS） |
| TX-4 | **child ID 改注册表分配（补 P-3）**：`child_<npc_id>_<serial>` 的 serial 由 EntityId 分配器（02 契约）发放，**禁用 children.size()+1**；已生 child 的 ID 永不复用 |
| TX-5 | **跨日结算点唯一**：跨日（time_of_day 越过 24）触发的日结（天气/日程/超时）在同一事务内、按固定顺序执行一次；禁消费方重复挂日结 |

---

## 7. Schedule 四件套（冻结项 6/8 · VS-004）

| # | 冻结内容 |
|---|---|
| SD-1 | **四件套（01 §54 原文）**：`ScheduleDefinition`（数据驱动：时段→活动/地点/状态，来自 ContentRegistry）/ `ScheduleState`（NPC 当前执行到哪条）/ `ScheduleRule`（选择与覆盖规则）/ `ScheduleEntry`（单条时段项） |
| SD-2 | **推进链（01 §54 原文）**：`TimeAdvancedEvent → Schedule Resolver → Schedule State → NPC/Shop/World Effects`；**Resolver 产 Command，不直改**（与 06 A-R06 同源） |
| SD-3 | **四个消费面**：NPC 日程（挂 06 `schedule_ref`）· Shop 刷新（周期=Calendar）· Quest 超时（Condition 里的 TimeCondition）· WorldEvent 定时触发（含节日挂点 CA-3）——**首张实装面见 WT-3** |
| SD-4 | **挂起纪律**：SUSPENDED 区 NPC（06 SC-1）不跑 Resolver，唤醒时按当前时间重算一次（无状态漂移） |
| SD-5 | **World Simulation Scheduler（01 §67）**：负责 World Time/Schedule/World Events/Background Simulation/Materialization 触发权；**其产出的状态变化仍守 State Owner 与 Execution Boundary（原文）**——四层 Scheduler 各司其职，禁万能 Scheduler（宪法 0-C.15） |

---

## 8. Save / 回放（冻结项 7/8）

| # | 冻结内容 |
|---|---|
| SR-1 | **WorldTimeState.save/load 原样保留**（已 ISaveable；四字段即 SaveDTO）；world_flags 随 WorldState 切片进存档（Owner 导出，禁 GameState 代写——06 SV-1 同源） |
| SR-2 | **回放记录补全（宪法 L677）**：Game Time 已在存档；RNG Seed（天气 roll 的 Provider 状态）+ Command Sequence 必须进回放记录——`Record → Replay → Compare` 下同 seed 同命令序列必得同天气（A-R12 同族等价测试） |
| SR-3 | **旧档兼容**：现有存档四字段语义不变即通过；新增 world_flags 切片缺省=空（向后兼容，05 VE-3 同款红线） |

---

## 9. Enforcement：规则 → Gate 矩阵 W-R01~W-R12

| RULE_ID | 规则 | 严重度 | 执行层 | 检查器 / 测试 | Gate |
|---|---|---|---|---|---|
| W-R01 | 时间域禁全局 `randi()/randf()`，必经 RandomProvider（WE-1） | FATAL | E3 | forbidden_api_validator | GATE22 |
| W-R02 | 时间推进必经 AdvanceTimeCommand+事务（T-5/TX-1） | FATAL | E2 | transaction_test | GATE26 |
| W-R03 | 消费面必走 TimeConsumer 注册制，禁私听信号直改（TX-2） | FATAL | E3 | module_scope_validator | GATE05 |
| W-R04 | day 单调递增，禁生产倒流 API（T-2） | FATAL | E3 | naming/forbidden_api | GATE22 |
| W-R05 | 天气 roll 纯函数化，同 seed 同输入必同输出（WE-2/SR-2） | FATAL | E2 | weather_replay_test | GATE29 |
| W-R06 | 实体 serial 由分配器发放，禁 size()+1 类推导（TX-4） | FATAL | E3 | id_validator（静态模式扫描） | GATE07 |
| W-R07 | 业务判定禁用全量读数信号，必用 delta 事件（T-3） | ERROR | E3 | signal_audit（消费方白名单） | GATE24 |
| W-R08 | Schedule Resolver 产 Command 禁直改（SD-2） | FATAL | E2/E3 | transaction_test + 静态扫描 | GATE26 |
| W-R09 | 四层 Scheduler 职责禁混装，禁万能 Scheduler（SD-5/宪法 0-C.15） | FATAL | E3 | dependency_validator | GATE04 |
| W-R10 | season_days 变更必走内容版本规则（CA-4） | ERROR | E3 | schema_version_validator | GATE06 |
| W-R11 | debug 直改面必须带三级标签（宪法 §80） | ERROR | E3 | debug_tag_lint | GATE21 |
| W-R12 | 回放：同 seed+同命令序列 ⇒ 时间/天气/日程态逐字段一致 | FATAL | E2 | world_replay_test | GATE29 |

**E0（纯文档约束）计数 = 0**。Gate 列一律 LN 编号（04 §2.1 政策）。

---

## 10. 现有资产迁移映射表

| 现状 | 目标 | Phase |
|---|---|---|
| `weather_time_service.gd` L140 `randi()` | 注入 RandomProvider + roll 纯函数（WE-1/WE-2） | Phase1（随 Kernel 契约） |
| `advance_time/advance_day` 直改直发 | AdvanceTimeCommand + Transaction（TX-1） | Phase2（0-C 落地） |
| `romance_service.advance_days` 直改 | 第一个 TimeConsumer 注册（TX-2）， pregnancy/children 写入进 Journal | Phase2 |
| `_birth` 的 `children.size()+1` | EntityId 分配器 serial（TX-4） | Phase2 |
| `GameState._global_flags` | WorldState.world_flags（WO-3） | Phase3 |
| `world_time_changed` 业务消费方 | 迁 delta 事件（W-R07） | Phase2 |
| debug_set_* | 三级标签（WT-4） | Phase1（纯注释+lint） |
| `get_time_of_day_phase` 四相公式 | 保留为唯一实现（T-4） | 不迁 |

---

## 11. 开放问题（必须 ADR 裁决，AI 不得自决）

> **【已追认 2026-09-06】** 用户整批复核：以下 WT-1~WT-4 全部按倾向执行（本表保留原文供审计）。

| # | 问题 | 倾向 |
|---|---|---|
| WT-1 | Calendar 是否加「年」计数 | **加，纯派生零状态**（CA-1 公式；不加则 Y2 存档歧义） |
| WT-2 | 天气 roll 的 Provider 实例归属 | WorldTime 持有独立 SeededRandomProvider（种子独立于战斗域，进回放记录；隔离爆破半径） |
| WT-3 | Schedule 四消费面首张实装谁 | **Shop 刷新**（无模块主权冲突、周期语义最简，NPC 日程待 06 Owner 迁完再接） |
| WT-4 | debug_set_* 三级标签 | Development Only（生产禁入口）；测试走 FakeClock（04 §6.2），debug 面不进测试路径 |

---

## 12. Freeze 清单（`WORLD-TIME v1.2.0`）

| 冻结物 | 内容 |
|---|---|
| World State Owner | WO-1~WO-4（九词分派 / 聚合形态 / 唯一写入口） |
| Time 契约 | T-1~T-5（单调性 / delta 事件 / AdvanceTimeCommand） |
| Calendar | CA-1~CA-4（派生公式 / 稳定日期键 / 节日挂点） |
| Weather | WE-1~WE-4（禁全局随机 / 纯函数 roll / 留痕） |
| 推进事务化 | TX-1~TX-5（一推进一事务 / TimeConsumer 注册制 / 消费顺序 / 分配器 serial / 唯一日结） |
| Schedule | SD-1~SD-5（四件套 / Resolver 产 Command / 四消费面 / 挂起纪律 / §67 边界） |
| Save·回放 | SR-1~SR-3（切片 / seed+命令序列进回放 / 旧档兼容） |
| W-R01~W-R12 | §9 全矩阵 |

---

## 13. 完成定义（DoD，7 条）

1. `randi()` 出天气域：Weather roll 纯函数 + 注入 Provider，同 seed 回放一致（W-R01/W-R05 绿）；
2. AdvanceTimeCommand 事务落地：一次休息推进的全量 Mutation 可回滚（W-R02 绿，覆盖 01 §118 的 Middle Mutation Failure）；
3. romance advance_days 收编为首个 TimeConsumer，孕期/子嗣写入进 Journal；
4. child serial 走分配器，重复 ID 构造被拒（W-R06 绿）；
5. delta 事件上线，业务消费方零直听全量信号（W-R07 绿）；
6. Schedule 四件套骨架 + Shop 刷新首面（WT-3）跑通 VS-004 链路；
7. **全部为骨架与契约，未动任何生产源码**（本图产出阶段）。

---

## 14. 07 的一句话总纲

**心跳只有一个：一次推进一事务、一个 Provider 管随机、一个 Resolver 管日程；谁的心跳谁负责，别人只准听增量。**

---

## 关联文档

- `PROJECT_CONSTITUTION_V1.4.md`（0-C.15 四层 Scheduler / §78 随机 / §79 Game Clock / §80 Debug 三级 / 0-F.6 VS-004 / L677 回放记录）
- `01_总体架构施工图_V1.4修复版.md`（§53 World / §54 Schedule / §587 TimeAdvancedEvent / §67 World Simulation Scheduler / §112 VS-004）
- `02_Domain_Kernel施工图_V1.4修复版.md`（GameClock / RandomProvider / Transaction / RECOVERY_REQUIRED）
- `06_Actor_Player_NPC施工图_V1.4修复版.md`（schedule_ref / SC-1 五态 / SV-1 切片 / A-R06）
- `05_Content_Registry_Content_Pipeline施工图_V1.4修复版.md`（world_config 归 Definition / CA-3 节日内容化）
