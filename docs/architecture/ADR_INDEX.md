# ADR_INDEX —— 架构决策记录统一登记表

- 建立：2026-09-06（用户整批复核「按各图 §7 推荐追认」落地件；11 图跨图登记条目的执行）
- 规则（用户追认）：**新 ADR 编号自 0005 起顺延**；宪法 §23A 预占题保持专名引用、**不占号**（见 §3）；每条 ADR 状态 ∈ {PROPOSED / APPROVED / SUPERSEDED}；本表是编号唯一真源，正文锚定各图原文。

---

## 1. 已裁决 ADR

| # | 标题 | 裁决（原文锚点） | 状态 |
|---|---|---|---|
| ADR-0002 | **内容 ID 格式** | **基线形态 C**：现有小写下划线 ID（`npc_su_waner`）合法，零迁移、不动存档红线（03 图 §11）。**扩展二级形态（06 图 AC-1 推荐 B）**：区域前缀变体 `nv_npc_chief` / `mt_dialog_priest` 经「区域缩写白名单 + 域段固定」正则合法化（`^[a-z]{2,4}_(npc\|dlg\|...)_ [a-z0-9_]+$` 族），敌人裸名补 `enemy_` 前缀；**裸名区域升 `region_*` 前缀（16 图 CP-2）**。nv/mt 存量迁移随 Phase3~4 实施时执行，须配套存档迁移链 + Impact Analysis（01 §71；实施前按 APPROVAL 惯例报备影响面） | APPROVED（2026-09-06 用户整批追认） |
| ADR-0003 | **目录迁移时机**：`data/configs/**` → `content/definitions/**` | 延后至 **Phase 5**（先用契约约束，待 Registry 就绪一次性搬迁，避免二次返工）（03 图 §11） | APPROVED（2026-09-06） |
| ADR-0004 | **Schema 表达形式** | 保留 **GDScript `.gd` 强类型类**（编译器即校验器），另生成机器可读 Schema 摘要供工具消费（03 图 §11） | APPROVED（2026-09-06） |
| ADR-0005 | **宪法升版 V1.2→V1.4（Context Integrity Edition）** | 用户 2026-09-06 指令采用《工程宪法_V1.4_修复版》为最新修订宪法，入库 `docs/constitution/PROJECT_CONSTITUTION_V1.4.md`（7345 行，Supersedes V1.3；V1.3 本工程未独立存在，其能力经 V1.4 §0.1/§0.2 修订说明承载）。**版本链**：V1.2（d4b4c05 入库，按 §171 保留为历史基线）→ V1.3（承载于 V1.4 修订说明）→ **V1.4（现行有效）**。**V1.4 治理核心**：①RULE 001 放软——「核心业务状态与规则不得绑定 Godot 生命周期/不得直接内联 Godot API；允许经明确白名单 Adapter/Boundary 与 Godot 原生运行时深度协作」；②新增 0-B.0 分治双轨（治理=企业化 / 运行时=Godot 原生，交界走 Adapter/Boundary/Port）；③0-B.12 Signal/Domain Event/Command 三层语义显式化；④0-E.3/GATE15 白名单 Adapter（`*_adapter.gd`/`adapter/` 层）放行判据可机器验证；⑤§93 性能所需 Godot 下沉经白名单可达 Runtime Shell。**升表口（不即时动）**：02 图 K-R 系列+GATE22 基线的 Adapter 放行判据落地须随 ACR 升施工图与门禁基线；18 图 FROZEN 锚定 V1.2 条款按冻结版继续执行，冲突处以 V1.4 为准、修订走 ACR；0-C 章 20 条逐字兼容已核验（0-C.5/6/19 抽查一致），现行事务工作零影响；ACR-0001 名称保留（历史事实），迁移分批框架不变 | APPROVED（2026-09-06 用户指令） |

> ADR-0001（采纳 V1.2 宪法与目标架构迁移）以 ACR-0001 文档承载（`ACR-0001_采纳V1.2宪法与目标架构迁移.md`，APPROVED 2026-09-06），不另占 ADR 号。

## 2. 各图开放问题整批追认（2026-09-06）

02 O-1~4 / 03 ADR-0002~0004 / 04 T-1~4 / 05 C-1~4 / 06 AC-1~4 / 07 WT-1~4 / 08 RF-1~4 / 09 IE-1~4 / 10 EC-1~4 / 11 AB-1~4 / 12 QD-1~4 / 13 SV-1~4 / 14 PV-1~4 / 15 ST-1~4 / 16 CP-1~4 / 17 SBP-1~4 / 18 RH-1~4 —— **全部按各图推荐/倾向执行**，批注已回写各图开放问题章节；原表保留供审计。其中 17 图 SBP-3/4 已按推荐实施（GATE40+）；18 图 RH-1/2/3 已执行，RH-4 按「Phase4 最小可玩闭环」推荐。

## 3. 宪法 §23A 预占题（不占号，实施期专名立项）

Repository 选型 / Combat 使用 CombatantSnapshot / Marriage·Children 结构 / Save·RuntimeState 边界 —— 实施到对应 Phase 时以专名另立 ADR（编号届时顺延），不在本表预占。

## 4. 设计决议备忘（未占 ADR 号的落定项）

- **patch manifest 与迁移 Callable 的域边界（13/18 图张力）**：manifest 为数据面，只载 `from/to` 元数据；Callable 迁移步骤居代码注册表（`SaveManager._migrations`），补丁安装时按注册表链走并对账 `save_version`。Phase1 已冻结 manifest `save_migration` 旧字符串格式拒收改 ERROR 响报（更改日志 2026-09-06）。
- **forge_iron_sword（10 图 P-E7）处置**：`forge` 前缀违 03 白名单正则 + `material_iron_001` 悬空（materials.json 无定义，配方恒 `can_forge=false`，测试已锚定该行为）。按 10 图 EC-R07 既定路线 **Phase4 随 GATE07 基线统一迁移 `recipe_` 域**；迁移时同步：①清存量引用后再登记 `_retired_ids.json`（CP-R02 无基线豁免，存量未清即登记 = GATE6 即时红）；②随 Recipe schema 统一决定补铁料定义或改配方产出。基线冻结制下现状维持，不提前改内容。
- **GATE2 flaky 防抖（04 图 D-07）**：首跑红自动复跑一次，FLAKY-RECOVERED 判绿留痕（6a45c99 已落地）。
- **Kernel 契约临时落位 `core/kernel/`（2026-09-06 Phase B 骨架批）**：02 图目录图的顶层 `kernel/`（ACR-0001 写 `domain/kernel/`）在目录收敛（Phase 5，同 ADR-0003 延后原则）前临时落于 `core/kernel/`——arch_linter GATE22 扫描 `core/` 即自动覆盖 Kernel 禁 API（K-R01~R05/R10），13 子目录划分按冻结清单原样保留。
- **MutationContext 最小形态（2026-09-06）**：02 图 §6 Effect 契约引用 MutationContext 但全文未定义；落地时在 `kernel/transaction/` 补最小数据面（transaction_id + `register()` 单调分配 sequence + records），Journal 持久化/恢复/逆序回放仍属 Execution Runtime（02 图 §7 分界铁律）；Runtime 实施时如有出入按 ACR 升版。
- **GameFacts 撞名处置（2026-09-06）**：kernel 冻结名 `GameFacts`（@abstract：get_int/get_bool/get_entity_id）独占；存量 `services/quest/facts.gd` 适配器改名 `ServiceGameFacts`（纯改名零行为变化），Phase D 升级为实现 kernel 契约（02 图 §15 迁移映射）。
- **EffectRegistry 与 kernel Effect 契约咬合（2026-09-06 QD-2 批）**：02 图 Effect 契约（`core/kernel/effect/effect.gd`，Phase B 骨架）定**形**，12 图 QD-1 追认的域级执行注册表（`core/effect_registry.gd`，五类 kind 锁定）定**执行**——互补不重叠，非撞名（EffectRegistry 与 Effect 是两个 class_name）。`core/effect_registry.gd` 为 12 图 Freeze 清单「Effect 五类注册表」契约面文件：**不可退役**（§171 收编不丢弃：CommandDispatcher 等五形态已收编入此表）；**可随目录收敛迁移**（Phase 5，同 ADR-0003 延后原则），迁移时 02/12 图咬合确认并随单广播新路径（handoff 69b59a4fd344 已通报 kernel 窗）。若 Phase D kernel Effect 契约升级要求注册表实现契约接口，按 ACR 流程对齐，不推倒已收编的注册期拦截语义（QD-R03/R09）。
- **TransactionContext 内部推进接口 + 构造补全（2026-09-06）**：§7.1 契约仅含 getter；为使状态机可测、Runtime 可推进，补下划线内部接口 `_begin/_mark_committed/_mark_rolled_back/_mark_recovery_required`（合法迁移：PENDING→RUNNING→{COMMITTED,ROLLED_BACK,RECOVERY_REQUIRED}、ROLLED_BACK→RECOVERY_REQUIRED，非法迁移拒绝返回 false）——非公共契约，不违反 K-R09；Query/DomainEvent/Result 子类按 Command 模式补最小 `_init` 构造。O-4 的 Transaction Test 拆两步：契约层（15 项）随骨架落地，01 §118 十一路失败路径随 TransactionRuntime 批次（GATE26/27/28 物理化条件届时成熟）。
- **TransactionRuntime 批次四处补充（2026-09-06）**：①MutationContext `register()` 追加可选 `before/after` 参数 + `_audits` 审计侧表 + `get_audits()`——宪法 0-C.5/01 §17 要求 Journal 登记 before/after 双值，但 02 图 MutationRecord（§7.2 冻结面）无此二字段，由 Execution 层 JournalEntry（`core/execution/journal_entry.gd`）承接双值，Phase4 迁移时对齐 02 图契约文档；②DomainEvent 补下划线内部接口 `_mark_committed()`（PENDING→COMMITTED，仅 Runtime.commit 在事务提交成功时调用，与 TransactionContext._mark_* 同构，非公共契约）；③timeout 无专用错误码（ErrorCode 15 常量冻结表），复用 `INVALID_STATE` + context `reason=timeout`，未来按 ACR 升表；④Journal 同步走幂等 `replace_for`（MutationContext 审计面为全量真源，多次 run 同一事务不重不漏）。
- **01 图 V1.4 修复版落地与复校正（2026-09-06，ADR-0005 执行件）**：用户指令将桌面《01_总体架构施工图_V1.4修复版》随宪法 V1.4 升版落地，入库 `docs/architecture/01_总体架构施工图_V1.4修复版.md`（2101 行；原 V1.2 稿 2069 行保留为历史基线）。差异=11 处批注式直修（§3 优先级链/§5 Kernel=Domain Contracts 同层消歧/§6 Execution 公共契约层 01-1/§13 §38 归属唯一权威/§16 B7 Shared Foundation 治理/§29 IGameClock I 前缀+C3 装配注入/§35 白名单 Adapter 放行复校/§36 Player 不设独立 Owner/§37 NPCState 只读引用/§127 GATE21~32 升硬性验收+GATE30 改名 Context Integrity & Freshness/§128 Phase A-D=宪法 §229 同定义）+ 头部七项落地说明 + 尾部关联文档。**复校正 3 处**（桌面版引用与本库实际不符）：①Authority 宪法路径→`PROJECT_CONSTITUTION_V1.4.md`；②「Supersedes V1.4/V1.3/V1.2」病句→「Supersedes V1.3/V1.2」；③尾部引用库内不存在的两个「_V1.4_语境复校版」文件→库内实际 V1.2 基线文件名+待升版标注。**升表口（不即时动）**：①§127「GATE21~32 硬性验收+GATE30 进 verify_all」——GATE30=Context Integrity & Freshness（04 图现定义 Context Freshness 同族扩义）物理化随 ACR 升 04 图 Registry 与 verify_all；②§29 Composition Root 统一装配注入与批次3 装配收敛（ADR 0006 预留）衔接；③02~18 图逐图 V1.4 口径升版走 ACR 不批量直改。锚点核验：§59/60/88/118/125/14~20/24/65/71/72/91/92/93 全保留无漂移。
- **buy/sell 0-C 事务收编落位（2026-09-06 D-10 批）**：10 图 EC-5「一操作一事务一 Journal」落地——`services/shop/shop_trade_transaction.gd`（ShopTradeTransaction）承接 01 §60 七步的 Transaction→Commit 段，预检留在 ShopService（0-C.2 Validation 先于 Begin），EventBus `notify_trade_*` 发射=commit 后投影（0-C.7）。①Effect/Undo/Facts/GoldenInvariant/TradeEvent 内部类暂驻单文件（每状态键一个类已追认），Phase4 模块重排时 Wallet 类随 economy、Inventory 类随 inventory、Facts/Event 随 shop 迁移；②`owner_module` 分账 economy/inventory（09 TX-3 各写各 Owner，Shop 不直碰 Wallet 由 Effect 边界物理化）；③ShopService 每笔交易 new 独立 TransactionRuntime（无 clock=无 deadline，0-C.12 合法形态），Phase3 装配收敛时可上提为装配注入；④0-C.19 Purchase Golden Case（VS-001）以 `TradeGoldenInvariant` 进 commit Invariant 链 + 永久回归套件 `test_shop_trade_tx`（10 项，矩阵分工：Runtime 层十一路由 test_transaction_runtime 承接）。

## 5. 关联

- 各图开放问题原文：`02~18_*施工图_V1.2.md` 对应章节
- 宪法 §23A / APPROVAL_2026-09-06 / ACR-0001
