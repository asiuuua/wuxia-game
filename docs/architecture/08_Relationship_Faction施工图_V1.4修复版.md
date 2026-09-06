# 08 Relationship / Faction 施工图 V1.4 修复版

| 项 | 值 |
|---|---|
| 状态 | **FROZEN**（2026-09-06 用户批准；可依此实施） |
| 日期 | 2026-09-05 |
| 上游 | 宪法 V1.4（§39 Relationship 边界 / §40~42 Romance·Marriage 边界 / §37 Memory 建议 / L2034-2053 Owner 表）→ 01 §48 Relationship·§55 Faction·§38 Owner 基线 → 02（EntityId/Command/Event）→ 04（Gate/双替）→ 05（Definition/ID 校验）→ 06（NPC Definition/Membership 挂点） |
| 范围 | 冻结 8 件：RelationshipGraph 本体 / 十型统一 / 职责边界 / Faction 九件套 / Membership 契约 / 好感送礼事务化 / 读模型合规 / Save·联动 |
| 冻结物 | `RELATION-FACTION v1.2.0`（见 §12） |

---

## 0. 定位

> **V1.4 修复版总注**：本图随宪法 V1.4（ADR-0005）与 01 图 V1.4 修复版同步升版——①宪法条款号零漂移，正文「宪法 §N / 0-C.x / 0-F.x」引用全部有效；②RULE 001 放软：Domain 经白名单 Adapter/Boundary 触达 Godot 属合法协作（判据=0-E.3/GATE15，白名单升表随 ACR）；③本图冻结契约与冻结物版本零变化，V1.2 原稿保留（§171 收编不丢弃）。域内衔接：好感真源=BondService 口径不变；宪法 §39~42 边界条款号零漂移；Owner 观察期收口仍为对齐审计在办偏差项（与本图升版互不影响）。

宪法 §39 定边界：**Relationship 管人与人之间的关系、类型、状态、数值、规则；不管婚姻、怀孕、子女、婚礼**——那些是上层模块。本图把「关系」从四套散装系统（好感/配偶/结义/师徒）收敛为**一张图**，把「门派」从单服务雏形补成 01 §55 的九件套；图是唯一事实源，模块只做投影。

**铁律**：施工范围未批前只产文档不动代码（§104）。

---

## 1. 现状盘点（机器扫描证据，2026-09-05 实测）

### 1.1 已有资产（第 171 节：升级不丢弃）

| 资产 | 实测 | 处置 |
|---|---|---|
| `bond_service.gd`（好感） | affections/affection_levels/gift_count/fired_events（一次性事件）/interaction_log（封顶 100 条）；`give_gift` 送礼→好感+解锁对话 | 收编为 Edge 写入 Effect（§6） |
| `relationship_service.gd`（225 行聚合读模型） | `get_relationship_graph()` 拼 好感+配偶+子嗣+结义+师徒 成统一视图；marriageable/spouses_enriched/children/sworn_enriched/masters_enriched | 收编为 Query 投影（§7） |
| `sect_service.gd`（122 行） | current_sect_id / reputation(sect_id→int) / rank；join/contribute；`_rank_for_reputation` 阈值判阶（数据来自 sects.json ranks） | 收编为 FactionState 的 Rank/Reputation（§4） |
| `sworn_service / master_service` | 结义（含结义技能 get_sworn_ability）/ 师徒 | 收编为 SWORN/MASTER·DISCIPLE 边语义 |
| `relations.json`（6 条 NPC 关系档案） | name/gender/age/personality/**is_romanceable**/required_*/initial_affection/max_affection/decay_rate/liked·loved_gifts/**faction/required_faction** | 拆分：Definition 面归 ContentRegistry，Membership 归 §5 |
| `sects.json`（2 门派） | `sect_sword_001` 主键 + ranks 阈值表（OUTSIDER/INNER/CORE/ELDER…rep_threshold/benefit） | FactionDefinition 雏形，原样收编 |
| 测试 4 份 | test_bond/relationship/sect/sworn | 保留升级为契约测试 |

### 1.2 缺口（本图要补）

| # | 缺口 | 证据 |
|---|---|---|
| P-1 | **无 Graph 本体**：relationship_service 只是读模型聚合器，直接翻兄弟服务**内部字典**（`GameManager.romance_service.spouses.get(...)` L23、`romance_service.children.keys()` L33）——无统一 Edge 存储，01 §48 的 Graph/Edge/Type/State/Rule 五件全缺 | relationship_service L22-47 |
| P-2 | **关系类型散装**：宪法十型（Friend/Respect/Trust/Hatred/Romance/Family/Master/Disciple/Sworn/Faction）无一统一建模——现状四套各存各的 | 四服务对比 |
| P-3 | **faction 引用断裂实锤**：relations.json 里 `"faction": "qingyun"` 是**裸名**，而 sects.json 主键是 `sect_sword_001`——按 03 C-R06 悬空、按 ID 契约不同域 | 两 JSON 对读 |
| P-4 | **无 Faction 模块**：01 §55 九件套仅 rank/reputation 有雏形；FactionRelation（势力间）/FactionRule/Policy/Resource 全缺 | sect_service 能力面 |
| P-5 | **好感写入直改无事务**：`add_affection/set_affection` 直改 Dictionary；`give_gift`=跨模块操作（扣物品+加好感+触发事件）无事务——「扣了物品好感没加」正是 P0 资产损失家族形态 | bond_service L47-59 |
| P-6 | **跨模块直连**：relationship_service 直引 `GameManager.` 六处兄弟服务内部字段——违「跨模块只走 EventBus/公共契约」底线 | L22-47 |
| P-7 | **rank 字符串/枚举双轨**：sects.json `"rank": "OUTSIDER"` 字符串 vs `SectEnums.Rank` int 枚举，`_rank_from_string` 手动映射——漂移风险 | sects.json / sect_enums |
| P-8 | **无 Memory 分层**：interaction_log 单一封顶 100 条；宪法 §37 建议 Permanent/Temporary/Rumor/Faction/Personal 五类 Memory | bond_service L18 |

---

## 2. RelationshipGraph 本体（冻结项 1/8）

| # | 冻结内容 |
|---|---|
| RG-1 | **五件套（01 §48 原文）**：`RelationshipGraph`（边集合）· `RelationshipEdge` · `RelationshipType` · `RelationshipState` · `RelationshipRule`——Relationship 模块（Owner=Relationship Edge/Score/Type，01 §38）唯一持有 |
| RG-2 | **Edge 键冻结**：`{min_id, max_id}`（无序对，字典序排定）+ `type` 复合键；**有向语义（MASTER→DISCIPLE）内含于 Type，不另设方向标志**（§11 RF-2）；Edge 值=`{score: int, state: enum, since_day: int}` |
| RG-3 | **score 语义**：每 Type 独立量程（AFFECTION 0-100 沿用现值；SWORN/MASTER 为状态型无分值，state 表达）；**禁跨 Type 共用量程** |
| RG-4 | **规则面**：`RelationshipRule` 只做图内判定（阈值/衰减/互斥如「已婚禁新结义」——跨模块互斥走 Query 查询他模块只读投影，禁反向直写） |
| RG-5 | **载体**：RefCounted，禁 Node；边数上限与衰减参数全部 JSON 配置（05 Definition 契约） |

---

## 3. 关系十型与现四系统收编（冻结项 2/8）

| # | 冻结内容 |
|---|---|
| TY-1 | **十型枚举（宪法原文全列）**：FRIEND · RESPECT · TRUST · HATRED · ROMANCE · FAMILY · MASTER · DISCIPLE · SWORN · FACTION |
| TY-2 | **收编映射**：现好感→`AFFECTION`（实现为 FRIEND/RESPECT/TRUST/HATRED 四象的复合 score，等级名沿用 affection_levels）· 结义→`SWORN` · 师徒→`MASTER`/`DISCIPLE`（双向两条边）· 配偶→`ROMANCE` 的终态投影（真源在 Marriage 模块，§3 TY-3）· 门派归属→`FACTION` 型边（NPC↔Faction，§5） |
| TY-3 | **只读投影纪律**：Marriage/Pregnancy/Children 是上层模块（宪法 §39-42），Relationship 图中的配偶/子嗣信息**只读投影**——真源分别在 Marriage/Pregnancy/Family 模块，投影失效即重查，禁双写 |
| TY-4 | **FAMILY/HATRED 等未启用型**：枚举先冻结、实现后补（YAGNI）；新增类型=枚举+量程+规则三件套齐全才许启用 |

---

## 4. Faction 九件套（冻结项 3/8）

| # | 冻结内容 |
|---|---|
| FA-1 | **九件套（01 §55 原文全列）**：FactionDefinition · FactionState · FactionMember · FactionRank · FactionRelation · FactionReputation · FactionRule · FactionPolicy · FactionResource |
| FA-2 | **现状收编**：`sects.json`→FactionDefinition（含 ranks 阈值表）；`sect_service` 的 reputation/rank→FactionReputation/FactionRank（Player 视角）；join→FactionMember 写入 |
| FA-3 | **Rank 双轨合一（补 P-7）**：以 `SectEnums.Rank` int 枚举为唯一真源，sects.json 的字符串 rank 改为**枚举序号或机器映射表**（工具校验双向一致，禁手写映射函数独走） |
| FA-4 | **FactionRelation**（势力间关系：敌对/同盟/中立）预留挂点——当前 2 门派无需实装，挂点防后续堵路 |
| FA-5 | **FactionRule/Policy/Resource**：挂点（贡献货币、政策效果、公共资源池——Phase4+ 随玩法）；九件套**名称先冻结，防私造同义件** |

---

## 5. Membership 契约（冻结项 4/8）

| # | 冻结内容 |
|---|---|
| MB-1 | **NPC 只存 Membership（01 §55 原文）**：NPC 侧仅存 `faction_id`（引用）+ `rank`——新增势力无需改 NPC 核心结构（原文理由即契约理由） |
| MB-2 | **引用修复（补 P-3）**：`relations.json` 的 `"faction": "qingyun"` 必须改指 `sect_sword_001`（真主键）；裸名在 ref_index 升级后=悬空拦断 |
| MB-3 | **成员判定走 Query**：`required_faction` 档案条件→`IsFactionMemberQuery`，禁档案层内置判定逻辑 |
| MB-4 | **双向一致**：FACTION 型边（图内）与 FactionMember 名册（模块内）同事务写（§6 TX 同源），禁两边各写各的 |

---

## 6. 好感 / 送礼事务化（冻结项 5/8）

| # | 冻结内容 |
|---|---|
| TX-1 | **GiveGiftCommand → Transaction**：扣物品（Inventory Owner）+ 加好感（Relationship Owner）+ 一次性事件触发 + 解锁对话标记，**一个事务全量 Journal**——「扣了物品好感没加」从机制上不可能（0-C 核心诉求） |
| TX-2 | **add_affection 收编为 Effect**（`ModifyRelationshipEffect`，01 §597 原文点名）：直改路径保留为 Effect 内部实现，外部调用必经 Command；`set_affection` 仅限存档恢复路径 |
| TX-3 | **衰减规则**：`affection_decay_rate` 与 `gift_count` 逻辑保留，衰减触发挂在 TimeConsumer（07 §6 注册制），禁私挂定时器 |
| TX-4 | **一次性事件 fired_events 语义保留**：进 Journal 的 AffectedIds，回滚时随之回滚 |

---

## 7. 读模型合规（冻结项 6/8）

| # | 冻结内容 |
|---|---|
| RM-1 | **relationship_service 重定位**：从「聚合器直翻内部字典」改为 **Query 驱动投影**——对 Romance/Sworn/Master 发 `GetSpousesQuery` 等公共 Query（02 契约），禁再触 `romance_service.spouses` 内部字段 |
| RM-2 | **GameManager 直连清零**：L22-47 六处 `GameManager.xxx_service` 引用改为构造注入或 Query；P-6 是「跨模块只走 EventBus/公共契约」底线的违例样本 |
| RM-3 | **投影实时性**：投影不缓存（现查现拼），避免与真源的双写一致性负担（§11 RF-3）；性能证据出来前不做缓存优化（01 §121 先测量） |

---

## 8. Save / Memory 联动（冻结项 7/8）

| # | 冻结内容 |
|---|---|
| SV-1 | **图切片**：RelationshipGraph 的边集（含 score/state/since_day）为 SaveDTO，Owner 导出；现 affections/spouses/sworn/master 各散存档键迁移期双读兼容，迁移完成删旧键（走 SAVE_VERSION 迁移步） |
| SV-2 | **FactionState 切片**：reputation/rank/membership 原样保留现 save 通道（已 ISaveable），补 Owner 声明 |
| SV-3 | **Memory 分层挂点（补 P-8）**：interaction_log 升级为 `PermanentMemory`（关键事件）+ `TemporaryMemory`（互动流水，保留现封顶策略）；Rumor/Faction/Personal 三类留挂点（宪法 §37 建议五类，Memory 可独立模块） |
| SV-4 | **可回放**：好感/加入门派/结义变迁全留 Command 足迹，支撑 04 §6.3 回放比对 |

---

## 9. Enforcement：规则 → Gate 矩阵 RF-R01~RF-R12

| RULE_ID | 规则 | 严重度 | 执行层 | 检查器 / 测试 | Gate |
|---|---|---|---|---|---|
| RF-R01 | 关系读写必经 RelationshipGraph，禁旁路直改兄弟服务内部字段（RM-1） | FATAL | E3 | module_scope_validator | GATE05 |
| RF-R02 | 生产代码禁 `GameManager.<service>` 直连（RM-2） | FATAL | E3 | dependency_validator（模式扫描） | GATE04 |
| RF-R03 | Edge 键=无序对+Type，禁以显示名/单 ID 为键（RG-2） | FATAL | E3 | naming/shape validator | GATE21 |
| RF-R04 | Marriage/Pregnancy/Children 数据禁进 Relationship 写路径（TY-3/宪法 §39） | FATAL | E3 | state_owner_validator | GATE25 |
| RF-R05 | 送礼必为单事务（TX-1）：缺物品扣减或好感 Journal 即红 | FATAL | E2 | gift_transaction_test | GATE26 |
| RF-R06 | faction 引用必须命中 FactionDefinition 主键（MB-2） | FATAL | E3/E4 | ref_index 升级版 | GATE07 |
| RF-R07 | Rank 枚举与配置字符串映射必须工具校验一致（FA-3） | ERROR | E3 | schema 校验扩展 | GATE06 |
| RF-R08 | 新关系型启用需三件套（枚举+量程+规则）齐备（TY-4） | ERROR | E3 | content 校验 | GATE06 |
| RF-R09 | NPC 侧仅存 membership 引用，禁内嵌 FactionState（MB-1） | FATAL | E3 | state_owner_validator | GATE25 |
| RF-R10 | 衰减禁私挂定时器，必经 TimeConsumer（TX-3） | FATAL | E3 | forbidden_api_validator（Timer 扫描） | GATE22 |
| RF-R11 | 图切片/门派切片由各自 Owner 导出，禁代写（SV-1/2） | FATAL | E3 | module_scope_validator | GATE05 |
| RF-R12 | 同 seed 同命令序列 ⇒ 图与门派状态逐字段一致 | FATAL | E2 | relation_replay_test | GATE29 |

**E0（纯文档约束）计数 = 0**。Gate 列一律 LN 编号（04 §2.1 政策）。

---

## 10. 现有资产迁移映射表

| 现状 | 目标 | Phase |
|---|---|---|
| `relationship_service` 直翻内部字段 | Query 驱动投影（RM-1/RM-2） | Phase2 |
| affections/spouses/sworn/master 散存 | RelationshipGraph 边集 + 只读投影 | Phase2 |
| `bond_service.add/set_affection` | ModifyRelationshipEffect + GiveGiftCommand 事务（TX-1/2） | Phase2（0-C） |
| `sects.json` "OUTSIDER" 字符串 rank | 枚举序号/机器映射（FA-3） | Phase1（数据+校验） |
| `"faction": "qingyun"` 裸名 | 改 `sect_sword_001`（MB-2，ADR 随基线） | Phase1（数据修正） |
| sect_service reputation/rank | FactionReputation/FactionRank（FA-2） | Phase3 |
| interaction_log | Permanent/Temporary Memory 分层（SV-3） | Phase4 |
| FactionRelation/Rule/Policy/Resource | 挂点（FA-4/FA-5，YAGNI） | Phase4+ |

---

## 11. 开放问题（必须 ADR 裁决，AI 不得自决）

> **【已追认 2026-09-06】** 用户整批复核：以下 RF-1~RF-4 全部按倾向执行（RF-1「直接改数据」即 qingyun→sect_sword_001 数据修正路线；本表保留原文供审计）。

| # | 问题 | 倾向 |
|---|---|---|
| RF-1 | `qingyun` 裸名修复方向：改数据指 `sect_sword_001` vs sects.json 加 alias 表 | **直接改数据**（6 条档案一处引用，alias=第二真源必漂移；随基线进 ref_index 拦截） |
| RF-2 | Edge 方向性：有向型（MASTER/DISCIPLE）用双边还是 Edge 内 direction 标志 | **方向内含于 Type**（MASTER 与 DISCIPLE 是两个 Type 的两条边——图查询简单、规则可对称书写） |
| RF-3 | 配偶/子嗣投影：实时现查 vs 缓存失效 | **现查**（RM-3；避免双写一致性负担，性能有证据再优化） |
| RF-4 | Memory 是否独立模块 | 留挂点暂不独立（宪法说「可以」非「必须」；五类分层先落两类） |

---

## 12. Freeze 清单（`RELATION-FACTION v1.2.0`）

| 冻结物 | 内容 |
|---|---|
| RelationshipGraph | RG-1~RG-5（五件套 / Edge 键 / score 量程 / 规则面） |
| 十型 | TY-1~TY-4（枚举全列 / 收编映射 / 只读投影纪律 / 启用三件套） |
| Faction 九件套 | FA-1~FA-5（全列 / 收编 / Rank 合一 / 挂点） |
| Membership | MB-1~MB-4（NPC 只存引用 / 裸名修复 / Query 判定 / 双写禁令） |
| 事务化 | TX-1~TX-4（GiveGift 事务 / Effect 收编 / TimeConsumer 衰减 / 事件回滚） |
| 读模型 | RM-1~RM-3（Query 驱动 / GameManager 清零 / 现查投影） |
| Save·Memory | SV-1~SV-4（图切片 / 门派切片 / Memory 分层 / 回放足迹） |
| RF-R01~RF-R12 | §9 全矩阵 |

---

## 13. 完成定义（DoD，7 条）

1. RelationshipGraph 落地：Edge 键/量程/规则三件套齐，存量四系统数据可完整迁入（GATE2 全绿）；
2. GiveGiftCommand 事务：故意制造「物品扣了、好感写入失败」→ 全量回滚（01 §118 Middle Failure 绿）；
3. `GameManager.<service>` 直连清零（RF-R02 扫描通过）；
4. faction 引用悬空清零（RF-R06 绿），qingyun→sect_sword_001 数据修正入基线；
5. Rank 双轨合一：配置↔枚举工具校验通过（RF-R07 绿）；
6. 四份存量测试升级为契约测试（图切片 roundtrip + 事务用例）；
7. **全部为骨架与契约，未动任何生产源码**（本图产出阶段）。

---

## 14. 08 的一句话总纲

**一张图管所有关系，一个名册管所有势力；婚姻是投影不是事实，送礼必须一手交钱一手交货。**

---

## 关联文档

- `PROJECT_CONSTITUTION_V1.4.md`（§37 Memory / §39 Relationship / §40~42 Romance·Marriage 边界 / L2034-2053 Owner 表 / L3079 Memory 五类）
- `01_总体架构施工图_V1.4修复版.md`（§48 Relationship / §55 Faction / §38 Owner 基线 / §597 ModifyRelationshipEffect）
- `02_Domain_Kernel施工图_V1.4修复版.md`（Command/Query/Event / Transaction / EntityId）
- `06_Actor_Player_NPC施工图_V1.4修复版.md`（NPC Definition / Relationship Ref / SV-1 切片纪律）
- `05_Content_Registry_Content_Pipeline施工图_V1.4修复版.md`（relations/sects 归 Definition / ID 校验 / 引用悬空拦截）
