# 06 Actor / Player / NPC 施工图 V1.2

| 项 | 值 |
|---|---|
| 状态 | **FROZEN**（2026-09-06 用户批准；可依此实施） |
| 日期 | 2026-09-05 |
| 上游 | 宪法 V1.2 → 01 §34~38（Actor 架构 / Materialization / Player / NPC / State Ownership）·§54 Schedule·§66 Actor Scheduler·§113 VS-005 → 02（EntityId/Command 事务语义）→ 04（Gate Registry/双替）→ 05（ContentRegistry/Definition/ID 校验） |
| 范围 | 冻结 8 件：Actor Carrier / Materialization / Player 四件套 / NPC 四态 / Actor Scheduler / State Owner 落位 / Save 关联 / Enforcement |
| 冻结物 | `ACTOR-RUNTIME v1.2.0`（见 §12） |

---

## 0. 定位

01 §34 一句话定调：**Actor 是 Runtime Entity Carrier，Actor 不拥有整个游戏**。本图把这句话钉成机器可查的契约：场景里的 Node2D 只是「皮」，事实永远活在 Owner State 里；皮可以随时撕掉重贴（Materialize/Dematerialize），事实一毫秒都不能丢（VS-005 状态一致性）。

**铁律**：施工范围未批前只产文档不动代码（§104）。

---

## 1. 现状盘点（机器扫描证据，2026-09-05 实测）

### 1.1 已有资产（第 171 节：升级不丢弃）

| 资产 | 实测 | 处置 |
|---|---|---|
| NPC 世界态雏形 | `GameState._unit_runtime`：`unit_id -> {status, faction, affinity}`，默认 ALIVE 防误判；战斗结束 `apply_combat_snapshot` 回写 | 迁为 NPCState 的 Owner 种子（§6） |
| 区域化生成 | `TownScene._spawn_npcs()` 按区域表 `scene` 字段过滤（修复过「迷烟镇 NPC 出现在起始城镇」的区域不设防缺陷）；`_npc_nodes: npc_id -> Node2D` | 收编为 Materializer 的 spawn 数据源 |
| NPC Definition 雏形 | `regions/<rid>/npcs.json`：`{id, name, scene, pos_x, pos_y, dialog_id, quest_id, battle_id}`（newbie_village 13 条） | 补齐 03 Definition 契约（01 §37 四态） |
| 战斗单位池 | `core/combat_entity_pool.gd` + `test_swarm.gd`（20 小怪压测） | Combatant Snapshot 的运行时载体 |
| 队伍 | `test_party.gd` / `test_enemy_target_party.gd` | Party 契约地基 |
| 存档 | `GameState.save()/load()` 含 `_unit_runtime`/`_global_flags`/`_quest_phase`/`_last_region_id`，SAVE_VERSION 1.1.0 迁移链 | Player/NPC SaveDTO 的既有通道 |
| 数据修正先例 | `town_npcs.json` 已只读留档（npcs 清空迁区域分片），GATE5 双写防线守着 | 同款手法用于 §10 迁移 |

### 1.2 缺口（本图要补）

| # | 缺口 | 证据 |
|---|---|---|
| P-1 | **无 Actor 抽象与 Materialization**：`_make_actor()` 直造 Node2D 挂场景，无 Materialize/Dematerialize 循环；VS-005 整体缺失（01 §113 状态一致性无从谈起） | TownScene L240-276 |
| P-2 | **ID 三形态并存**（ADR-0002 范围扩大）：①全局语义 `npc_su_waner`（合规 03 选项 C）②区域前缀 `nv_npc_chief`/`mt_dialog_priest`（**违 03 冻结正则**——`nv`/`mt` 不在 13 域白名单）③敌人裸名 `bandit_001`（无域前缀） | npcs.json/enemies.json 实扫 |
| P-3 | **内容硬编码进代码**：`DEBUG_CELEBRATION_SPOUSE_ID := "npc_su_waner"` 写死在场景脚本 | TownScene L70 |
| P-4 | **NPC 四态未分离**（01 §37 要求 Definition/State/SaveDTO/Runtime 四态）：现 pos_x/pos_y（Definition spawn 点）与悬停/交互态（Runtime）混在场景 Node 上 | TownScene |
| P-5 | **无 Actor Scheduler**（01 §66）：五态 tick（REALTIME/ACTIVE/REDUCED/SIMULATION/SUSPENDED）全缺；NPC 是纯静态摆设，无日程无降频 | weather_time_service 无 schedule 挂点 |
| P-6 | **Player 四件套未分离**（01 §36）：Progression/Preferences/Meta/CampaignState 混在 GameState autoload 的字段里（`_global_flags`/`_quest_phase`/`_last_safe_point`） | game_state.gd L13-19 |
| P-7 | **NPC 日程整体缺失**（01 §54 Schedule State Owner 已列，VS-004 范围） | 无任何 schedule 代码 |
| P-8 | **状态写入绕行风险**：`set_unit_status` 直改 Dictionary——无 Command 通道；未来 Actor Tick 一旦加行为就会直改 Domain State（违 01 §66） | game_state.gd L38 |

---

## 2. Actor Carrier（冻结项 1/8）

| # | 冻结内容 |
|---|---|
| AC-1 | **Actor 八组件（01 §34 原文）**：Identity · Stats · Progression Ref · Inventory Ref · Equipment Ref · Relationship Ref · Faction Ref · Status。**Ref = 引用 ID，不是内嵌对象**（03 C-R08 只存 ID 同源） |
| AC-2 | **禁吞清单（01 §34 原文，机器可查）**：`ActorState` 不得出现 Quest / Relationship / Inventory / Economy / Faction / Family / Combat / World 任一状态字段；Owner 各归其主（§7） |
| AC-3 | **载体分层**：`ActorIdentity`（RefCounted，EntityId + 类型 + 存活态）为唯一事实锚；`ActorRuntime`（场景侧呈现态）可销毁重建；两者以 EntityId 关联 |
| AC-4 | Player 与 NPC **共用同一 Carrier 契约**，差异只在挂载的模块 Ref 集合与调度档位（§5） |

---

## 3. Actor Materialization（冻结项 2/8 · VS-005）

| # | 冻结内容 |
|---|---|
| AM-1 | **四相循环（01 §35/§113 原文）**：`World State → Materialize → Actor Runtime → Active → Dematerialize → World State → Rematerialize`；**Rematerialize 后状态必须逐字段一致**（回放测试断言，A-R05） |
| AM-2 | **Scene 非事实源（01 §35 红线）**：Actor Scene/Node2D 销毁不得丢失任何业务状态；`_npc_nodes` 字典降级为纯渲染索引，禁业务读写 |
| AM-3 | **Materializer 归属**：Application 层服务（RefCounted），输入=RegionPack NPC 定义（05 收编）+ World State；输出=ActorRuntime；**禁在 Domain/Kernel 出现任何 Node**（02 K-R02 同源） |
| AM-4 | **触发时机**：区域进入=批量 Materialize；离屏/切换=Dematerialize 回写；战斗=Combatant Snapshot（01 §1051 行语义：World Actor → Snapshot → Combat Session），战后快照经 Command 回写 |

---

## 4. Player 四件套（冻结项 3/8）

| # | 冻结内容 |
|---|---|
| PL-1 | **五组件（01 §36 原文）**：Actor + PlayerProgression + PlayerPreferences + PlayerMeta + PlayerCampaignState |
| PL-2 | **禁塞世界（01 §36 红线）**：`PlayerState` 不得出现 NPC 表 / 区域表 / 世界开关等内容性字段——`_global_flags`（剧情变量）归属 World/Story State Owner，迁移映射见 §8 |
| PL-3 | **四件套 Owner 划分**：Progression→Progression Owner（XP/Level/Talent）；Preferences→SettingsManager（现存）；Meta→平台层（设备/账号，当前占位）；CampaignState→Player 模块（章节进度/安全点/抵押物清单——现 `_quest_phase`/`_last_safe_point`/`_xiaozhang_collateral` 的迁入目标） |
| PL-4 | **Player 是 Actor**：复用 §2/§3 全部契约，禁止为 Player 另写第二套生命周期 |

---

## 5. NPC 四态数据契约（冻结项 4/8）

| # | 冻结内容 |
|---|---|
| NP-1 | **四态分离（01 §37 原文）**：`NPCDefinition`（数据驱动，来自 ContentRegistry）/ `NPCState`（Runtime 可变）/ `NPCSaveDTO`（存档切片）/ `NPCActorRuntime`（场景呈现）——四态四类，禁混装 |
| NP-2 | **NPCState 白名单（01 §37 原文）**：位置 · 生命 · 当前状态 · 当前任务状态 · 当前日程状态 · Runtime Flags。**六项之外进 NPCState 即违例** |
| NP-3 | **NPC 禁存清单（01 §37 原文）**：Node · Scene · Texture · UI · DialoguePanel——一律不得出现在 NPCState/SaveDTO |
| NP-4 | **Definition 补齐**：region npcs.json 条目升级为完整 Definition（display_name 键化接 LN-G18 / dialog_id/quest_id/battle_id 归 Binding 01 §47 / spawn 点保留在 Definition）；敌人定义并入同一契约（域前缀见 §10 迁移） |
| NP-5 | **日程挂点**：NPCState 预留 `schedule_ref`（01 §54 Schedule State Owner=NPC 日程状态的宿主在 Schedule 模块）；本图只留挂点不建日程（VS-004 范围，YAGNI） |

---

## 6. Actor Scheduler（冻结项 5/8）

| # | 冻结内容 |
|---|---|
| SC-1 | **五态 tick（01 §66 原文）**：`REALTIME > ACTIVE > REDUCED > SIMULATION > SUSPENDED`；Player 默认 REALTIME，视野内 NPC ACTIVE，视野外降 SIMULATION，休眠区 SUSPENDED |
| SC-2 | **Tick 禁直改（01 §66 红线，本图最高优先级规则）**：`Actor Tick → Decision → Command → Execution`；**禁止 `Tick → 直接修改 Domain State`**——P-8 的 `set_unit_status` 直改路径必须先包 Command（Phase2 事务落地时一并收口） |
| SC-3 | **调度器形态**：Application 层 `ActorScheduler`（RefCounted），统一节拍驱动（挂 WeatherTime/Engine tick 之一，Phase2 定），按档位聚合 tick；**禁每 NPC 一个 Timer/Thread** |
| SC-4 | **降档纪律**：档位切换只影响 tick 频率，**不改变状态语义**（SIMULATION 下跑的是同一套 Decision→Command，只是低频）；档位对 Combat 生效边界=Combat Session 内全员提至 ACTIVE+ |

---

## 7. State Owner 落位（冻结项 6/8）

| State | Owner（01 §38 基线） | 现状 → 迁移 |
|---|---|---|
| Actor Identity | Actor 模块 | 新建（EntityId 分配器随 Phase1 Kernel） |
| NPC Runtime State | **NPC 模块**（非 GameState） | `_unit_runtime` 自 GameState 迁出（§10，AC-2 追认） |
| Player CampaignState | Player 模块 | `_quest_phase`/`_last_safe_point`/`_xiaozhang_collateral` 迁入 |
| 世界开关/剧情变量 | World / Story State | `_global_flags` 迁出 GameState |
| Schedule State | Schedule 模块 | 占位（VS-004） |
| Combat Session | Combat 模块 | 现战斗服务已持有，补 Owner 声明 |

**通用红线**：每个 Runtime State 唯一 Owner（01 §38）；跨模块访问只许 Command/Query/Event（02 契约）；GameState autoload 终局=组合层薄壳（Phase3 装配收敛），不再持有业务 State。

---

## 8. Save 关联（冻结项 7/8）

| # | 冻结内容 |
|---|---|
| SV-1 | **SaveDTO 三切片**：PlayerSaveDTO（CampaignState+Progression）/ NPCSaveDTO（NP-2 白名单六项的持久化子集——位置与日程态按需，Flags 全量）/ PartySaveDTO（队伍编成）——**各自 Owner 负责 export/import，GameState 不代写** |
| SV-2 | **版本内聚**：Actor/NPC 切片随 SAVE_VERSION 1.1.0 迁移链走（LN-G09）；字段新增=MINOR，结构变更=MAJOR+迁移步 |
| SV-3 | **读档恢复顺序**：Save → World State → Materialize（AM-1 四相）→ 派生呈现；**禁止先造 Node 再灌状态**（事实源倒挂） |
| SV-4 | **可回放**：NPC 关键变迁（死亡/俘虏/关系突变）必须留 Command 足迹（02 语义），支撑 04 §6.3 Record→Replay |

---

## 9. Enforcement：规则 → Gate 矩阵 A-R01~A-R12

| RULE_ID | 规则 | 严重度 | 执行层 | 检查器 / 测试 | Gate |
|---|---|---|---|---|---|
| A-R01 | `ActorState`/`PlayerState` 禁吞清单字段（AC-2/PL-2） | FATAL | E3 | state_owner_validator（禁吞词表） | GATE25 |
| A-R02 | NPCState 白名单六项之外禁入（NP-2） | FATAL | E3 | state_owner_validator（白名单反向） | GATE25 |
| A-R03 | NPC 禁存 Node/Scene/Texture/UI（NP-3） | FATAL | E3 | forbidden_api_validator | GATE22 |
| A-R04 | Scene/Node2D 禁作业务事实源；`_npc_nodes` 类渲染索引禁业务读写 | FATAL | E3 | arch_lint --rules module_scope | GATE05 |
| A-R05 | Materialize→Dematerialize→Rematerialize 状态逐字段一致 | FATAL | E2 | materialization_test | GATE29 |
| A-R06 | Actor Tick 禁直改 Domain State，必走 Command（SC-2） | FATAL | E2/E3 | transaction_test + 静态扫描 | GATE26 |
| A-R07 | 禁每 NPC 一个 Timer/Thread；tick 必经 ActorScheduler | FATAL | E3 | forbidden_api_validator（Timer 计数） | GATE22 |
| A-R08 | NPC/敌人 ID 必须过 03 §3 正则（含本图扩展形态，ADR-0002 裁定后启用） | FATAL | E3/E4 | id_validator | GATE07 |
| A-R09 | 内容常量禁硬编码进场景脚本（P-3 类） | ERROR | E3 | content_lint（字面量 ID 扫描） | GATE06 |
| A-R10 | NPC/Player SaveDTO 由各自 Owner 导出，GameState 禁代写 | FATAL | E3 | module_scope_validator | GATE05 |
| A-R11 | 读档恢复顺序=State 先于 Node（SV-3） | FATAL | E2 | save_roundtrip 扩展用例 | GATE08 |
| A-R12 | 档位切换不改变状态语义（SC-4） | FATAL | E2 | scheduler_equivalence_test | GATE29 |

**E0（纯文档约束）计数 = 0**。Gate 列一律 LN 编号（04 §2.1 政策）。

---

## 10. 现有资产迁移映射表

| 现状 | 目标 | Phase |
|---|---|---|
| `GameState._unit_runtime` | NPCState Owner（NPC 模块服务），经 Command 写入 | Phase2 |
| `TownScene._spawn_npcs/_make_actor` | Materializer 四相循环，AM-1 契约 | Phase2（VS-005） |
| `_npc_nodes` 渲染索引 | 保留为纯渲染层，A-R04 兜底 | Phase2 |
| region npcs.json 条目 | 完整 NPCDefinition + Binding（NP-4） | Phase3（随 ContentRegistry 收编） |
| enemies.json `bandit_001` 裸名 | `enemy_bandit_001` 补域前缀（ADR-0002 扩展裁定后） | Phase1（数据修正+基线） |
| `DEBUG_CELEBRATION_SPOUSE_ID` 硬编码 | 移入测试/配置（A-R09） | Phase4 清零批 |
| `_global_flags`/`_quest_phase`/`_last_safe_point`/`_xiaozhang_collateral` | World-Story / Player CampaignState 各归 Owner（§7） | Phase3 |
| weather_time_service | ActorScheduler 统一节拍挂点（SC-3） | Phase2 |

---

## 11. 开放问题（必须 ADR 裁决，AI 不得自决）

| # | 问题 | 倾向 |
|---|---|---|
| AC-1 / **ADR-0002 扩展** | ID 第三形态合规化：区域前缀 `nv_npc_chief`/`mt_dialog_priest` 违 03 冻结正则、敌人 `bandit_001` 裸名。**A** 全迁全局语义 ID（高扰动）**B** 正则扩二级形态 `^[a-z]{2,4}_(npc\|dlg\|...)_[a-z0-9_]+$`（区域缩写白名单+域段固定，机器可校验，零迁移）**C** 仅敌人补 `enemy_` 前缀、区域前缀维持基线容忍 | **推荐 B + 敌人补前缀**：B 保住语义与区域归属信息、正则仍可机检、存量 13+ 条 NPC 零迁移；A 会破坏「旧存档必须可用」红线（存档 _unit_runtime 键即旧 ID） |
| AC-2 | `_unit_runtime` 迁出 GameState 的时机 | Phase2 随 VS-005（Materializer 需要 NPCState Owner 先立） |
| AC-3 | NPC 日程是否纳入本图实现 | 否——只留 `schedule_ref` 挂点（NP-5），实现归 VS-004/时间域 |
| AC-4 | Player Meta（设备/账号层）当前是否建占位类 | 建空壳占位（防后续误塞进 CampaignState） |

---

## 12. Freeze 清单（`ACTOR-RUNTIME v1.2.0`）

| 冻结物 | 内容 |
|---|---|
| Actor Carrier | AC-1~AC-4（八组件 / 禁吞清单 / 双层载体） |
| Materialization | AM-1~AM-4（四相循环 / Scene 非事实源 / Snapshot 语义） |
| Player | PL-1~PL-4（五组件 / 四件套 Owner / 复用 Carrier） |
| NPC 四态 | NP-1~NP-5（四态分离 / 白名单 / 禁存清单 / 日程挂点） |
| Actor Scheduler | SC-1~SC-4（五态 / Tick 禁直改 / 统一节拍 / 降档纪律） |
| State Owner | §7 六行落位表 |
| Save | SV-1~SV-4（三切片 / 迁移内聚 / 恢复顺序 / 可回放） |
| A-R01~A-R12 | §9 全矩阵 |

---

## 13. 完成定义（DoD，7 条）

1. `ActorIdentity` + Owner 声明落地，`_unit_runtime` 迁入 NPC Owner 且经 Command 写入；
2. VS-005 四相循环可跑：同一 NPC 三次 Materialize 状态逐字段一致（A-R05 测试绿）；
3. ActorScheduler 五态 + 降档等价测试（A-R12）绿；
4. NPCDefinition 完整化（键化显示名 + Binding），NPCByRegion 索引点亮（05 IX-1 首批）；
5. Player 四件套 Owner 归位，GameState 剩组合壳（局部，全量归 Phase3）；
6. Save 三切片经现有 roundtrip + 迁移链测试，旧档可读（红线复验）；
7. **全部为骨架与契约，未动任何生产源码**（本图产出阶段）。

---

## 14. 06 的一句话总纲

**皮可以撕，事实不能丢：Node 永远不是事实源，Tick 永远不直改状态，Actor 八组件只持 ID。**

---

## 关联文档

- `PROJECT_CONSTITUTION_V1.2.md`（State Owner / Command 事务 / Deterministic Random / Test 体系 §81~87）
- `01_总体架构施工图_V1.2.md`（§34~38 Actor/Player/NPC/Owner / §54 Schedule / §66 Actor Scheduler / §105 Combat Snapshot / §113 VS-005）
- `02_Domain_Kernel施工图_V1.2.md`（EntityId / Command·DomainEvent / Transaction 契约）
- `04_Test_Infrastructure_Architecture_Gate施工图_V1.2.md`（Gate Registry / transaction_test / 回放）
- `05_Content_Registry_Content_Pipeline施工图_V1.2.md`（NPCDefinition 来源 / RegionPack / Index）
