# 09 Item / Inventory / Equipment 施工图 V1.2

| 项 | 值 |
|---|---|
| 状态 | **FROZEN CANDIDATE**（待用户批准升 FROZEN） |
| 日期 | 2026-09-05 |
| 上游 | 宪法 V1.2（0-C.19 Purchase Golden Invariant / 0-C.20 事务测试矩阵 / L2058-2065 Owner 表）→ 01 §56 Item·§57 Inventory·§58 Equipment·§60 Shop 边界 → 02（Transaction 契约/EntityId）→ 04（Gate/双替）→ 05（Definition/校验）→ 06（iid 分配器） |
| 范围 | 冻结 8 件：Item 三件套 / Inventory 容器契约 / Equipment 契约 / 装备实例身份入档 / 跨模块物品事务 / iid 分配统一 / flags·数值校验 / Enforcement |
| 冻结物 | `ITEM-INVENTORY-EQUIPMENT v1.2.0`（见 §12） |

---

## 0. 定位

本图是 **0-C 事务的主战场**：项目反复出现的 P0 资产损失（扣钱不发货 / 扣料丢产出 / **换装丢装备**）全部落在此域。好消息是地基比预想好——`InventoryTransaction`（0-C 模块内雏形）、实例锁定、来源留痕都已被真实事故教育出来；坏消息是**装备存档丢实例身份**（耐久不入档）和**事务不跨模块**两颗雷还在。本图把雏形收编为 02 事务契约的标准实现，把两颗雷拆除。

**铁律**：施工范围未批前只产文档不动代码（§104）。

---

## 1. 现状盘点（机器扫描证据，2026-09-05 实测）

### 1.1 已有资产（第 171 节：升级不丢弃）

| 资产 | 实测 | 处置 |
|---|---|---|
| `inventory_service.gd`（873 行） | 三袋（main/material/quest）+ 重量 + `_next_iid` 实例发号器（注释：随存档恢复杜绝撞车）+ count 索引缓存（P2-7 优化）+ `query_add` 预检 + **锁定系统**（locked 防被动移除：售卖/分解/丢弃/团灭丢失/批量扣料——事故教育出的设计） | 容器契约地基（§2） |
| `inventory_transaction.gd`（82 行） | **0-C 模块内雏形已存在**：批量操作 commit 前预校验、add 先于 remove 顺序保障、失败回滚——注释明写「杜绝扣了料产物没进的静默丢料」（P1-2 修复） | 收编为事务契约的 Inventory 段实现（§5） |
| `equipment_service.gd`（148 行） | 三槽（main_hand/armor/accessory）+ equip 同槽旧装退包 + **手工回滚痕迹**（L46-55「卸下旧装备失败，已回滚」——换装丢装备 P0 的修复现场） | 收编为 Command/事务（§5），手工补偿退役 |
| `ItemInstance`（data/runtime，RefCounted） | iid/item_id/count/durability/max_durability/**acquired_source（"drop:bandit_001" 来源留痕）**/acquired_time/locked + **SCHEMA_VERSION=1 实例级存档版本钩子** | 三件套的 Instance 实现，原样收编（§2） |
| 数据 | weapons.json 19 条（id/rarity/max_stack/weight/price/**flags 位掩码**/attack/durability/speed/equip_slot）+ pills/equipment/materials | Definition 面（§2/§7） |
| 测试 | test_inventory/equipment/resource_manager/item_flags/shop | 保留升级（含锁定语义用例） |

### 1.2 缺口（本图要补）

| # | 缺口 | 证据 |
|---|---|---|
| P-1 | **装备存档丢实例身份**：`_equipped_inst` 注释明写「存档只存 item_id，耐久不入档为预存限制」——存档回环=耐久/未来强化丢失，违 01 §56 INSTANCE 语义（Enhancement/Durability/Owner 是实例核心） | equipment_service L15/L131-134 |
| P-2 | **事务不跨模块**：InventoryTransaction 只覆盖 inventory 内部；equip 手工补偿；购买链路（shop→economy→inventory）无统一事务——0-C.19 的 Golden Invariant 无机器载体 | 三服务对读 |
| P-3 | **iid 发号与 EntityId 分离**：`_next_iid` 自管自增+存档恢复——与 02/06 的 EntityId 分配器是两套序列，撞号/回滚档恢复策略未定义 | inventory L18 |
| P-4 | **装备槽硬编码**：三槽 const 写死服务代码（违「数值全进 JSON」铁律）；Loadout（多套配装）无概念 | equipment L10-13 |
| P-5 | **flags 位掩码魔数**：`"flags": 67` 直接写数据，语义靠 item_flags 位定义，无非法组合校验 | weapons.json |
| P-6 | **equip 跨服务直调**：`GameManager.inventory_service.add_instance` 直连退包（08 RM-2 同族违例） | equipment L46 |
| P-7 | **容量规则散装**：MAX_MAIN_SLOTS/MATERIAL/QUEST 与 BASE_MAX_WEIGHT 分居服务与 ItemConstants 常量——容量策略不可配置 | inventory L8-11 |
| P-8 | **Stack 语义未类型化**：max_stack 在 Definition（✓）但堆叠拆分/合并逻辑以裸 Array 操作散布 `_stack_to_existing` 等 | inventory L230+ |

---

## 2. Item 三件套（冻结项 1/8）

| # | 冻结内容 |
|---|---|
| IT-1 | **三态分离（01 §56 原文）**：`ItemDefinition`（ITEM_SWORD_001 → Attack=30/Weight=5）· `ItemInstance`（INSTANCE_xxxx → Enhancement=+7/Durability=83/Owner）· `ItemStack`（同 Definition 同位置的聚合视图）——三态三类，禁混装 |
| IT-2 | **Instance Identity 契约**：iid 全局唯一**永不复用**；`acquired_source` 来源留痕为必填（格式 `<kind>:<ref>`，如 drop:enemy_bandit_001 / quest:quest_x / shop:shop_y）；`locked` 语义冻结=防**被动**移除（售卖/分解/丢弃/团灭/批量扣料），主动消耗与装备不受限 |
| IT-3 | **SCHEMA_VERSION 钩子保留**：实例级 `ver` 字段是未来物品结构迁移的识别钩子（LN-G09 联动），禁删 |
| IT-4 | **Owner 字段显式化**：Instance 增加显式 `owner`（player / npc_id / container_id）——当前隐含「在哪个袋子里」，落地为字段后支撑掉落归属/交易/偷窃等玩法不重构 |

---

## 3. Inventory 容器契约（冻结项 2/8）

| # | 冻结内容 |
|---|---|
| IN-1 | **七词职责（01 §57 原文）**：Container · Slot · Stack · Add · Remove · Move · Capacity；**不负责清单（原文）**：Equipment Rule · Shop Price · Crafting Rule · Quest Reward |
| IN-2 | **容器配置化（补 P-7）**：三袋（main/material/quest）的容量上限、重量上限全部迁 `data/configs/inventory/bags.json`（Definition 面，05 契约）；服务内常量退役 |
| IN-3 | **预检先行**：`query_add`/`can_add` 预检保留为唯一容量判定入口；`query_add` 返回结构冻结为 `{ok, reason_code, missing}`（reason 用 ErrorCode 常量，禁中文字符串判定） |
| IN-4 | **Stack 操作类型化**：堆叠合并/拆分收敛为 `_stack_to_existing`/`split_stack` 两个纯函数（输入输出全类型化），禁散布裸 Array 操作 |
| IN-5 | **count 索引缓存保留**（P2-7 优化），但增删必须同步 bump（现实现保留），一致性由回放测试兜底 |

---

## 4. Equipment 契约（冻结项 3/8）

| # | 冻结内容 |
|---|---|
| EQ-1 | **六词职责（01 §58 原文）**：Slot · Equip · Unequip · Loadout · Requirement · Modifier；**与 Inventory 通过 Command / Transaction / Event 协作（原文）——禁直调**（补 P-6） |
| EQ-2 | **槽位配置化（补 P-4）**：`data/configs/equipment/slots.json`（slot_id/兼容 flags/加成键）；服务内三槽 const 退役；槽位校验进 05 语义层 |
| EQ-3 | **Requirement**：装备需求（等级/门派/性别/flags）走 Condition 契约（02 `@abstract Condition`），配置驱动，禁硬编码判定 |
| EQ-4 | **Modifier 重算纯函数化**：`_recompute`/`_add_bonus` 收敛为 `recompute_bonuses(equipped_refs) -> BonusSet` 纯函数（可单测可回放）；PlayerState 加成写入经 Command |
| EQ-5 | **Loadout 挂点**：多套配装（战斗/采集快切）留 `loadout_id` 挂点不实装（YAGNI，§11 IE-3） |

---

## 5. 装备实例身份入档 + 跨模块物品事务（冻结项 4/5）

### 5.1 实例身份入档（补 P-1）

| # | 冻结内容 |
|---|---|
| EA-1 | **equipped 存 iid 引用**：Equipment 存档从 `{slots: {slot: item_id}}` 升级为 `{slots: {slot: iid}}`——实例真源在 Inventory（§11 IE-1），装备区只是引用；存档回环耐久/来源/锁定**逐字段不丢**（0-C.19 同族 Golden Invariant） |
| EA-2 | **旧档兼容**：读到旧格式（item_id 值）按「无实例身份」降级重建实例（新 iid + 来源 legacy），出 WARNING 不拒读——「旧存档必须可用」红线 |
| EA-3 | `_equipped_inst` 运行时缓存退役（引用即真源）；耐久变更（战斗损耗）必经 Command 进 Journal |

### 5.2 跨模块事务（补 P-2 · 0-C.19/0-C.20 机器化）

| # | 冻结内容 |
|---|---|
| TX-1 | **PurchaseCommand Golden Invariant（0-C.19 原文）**：`GoldAfter = GoldBefore - Price ∧ InventoryAfter = InventoryBefore + Item`；失败则双方原样（`GoldAfter=GoldBefore ∧ InventoryAfter=InventoryBefore`）——写成永久回归测试（宪法 0-C.20 矩阵 11 场景，VS-001 A-G 全覆盖） |
| TX-2 | **三命令统一走事务**：Purchase / Equip / Consume 经 02 Transaction Runtime（TransactionContext + MutationJournal + 逆序 undo）；`InventoryTransaction` 收编为 Journal 的 Inventory 段 Handler（其 add→remove 顺序经验保留）；equip 手工回滚（L46-55）改 Journal undo，退役 |
| TX-3 | **Shop 边界（01 §60 原文）**：Shop 不直接操作 Player Wallet——买=Shop 出价，Economy 扣钱，Inventory 收货，各写各 Owner，事务捆住 |
| TX-4 | **失败码契约**：购买失败原因必须为 ErrorCode 常量（MONEY_INSUFFICIENT / CAPACITY_FULL / ITEM_LOCKED…），UI 禁判中文字符串 |

---

## 6. iid 分配统一（冻结项 6/8）

| # | 冻结内容 |
|---|---|
| ID-1 | **单一分配器**：`_next_iid` 迁入 02/06 的 EntityId 分配器（iid 成为分配器的一个 domain 序列），`instance_id` 格式冻结 `<prefix>_<serial>`，永不复用 |
| ID-2 | **存档恢复策略**：load 后分配器水位 = max(现存 serial) + 1（修复回滚档/旧档恢复撞号隐患 P-3）；分配器水位本身不入档（可从数据推导） |
| ID-3 | **禁再发明**：任何模块禁自建 `size()+1` / 时间戳 / UUID 序列（07 TX-4 child 撞车同款禁令的域内重申） |

---

## 7. flags / 数值校验（冻结项 7/8）

| # | 冻结内容 |
|---|---|
| FV-1 | **flags 位掩码合法组合校验**（补 P-5）：item_flags 位定义保留，05 五层 Validation 的语义层增加「位组合合法性」规则（如 consumable↔equipable 互斥、quest 物必 locked 初始），构建期 GATE6 拦 |
| FV-2 | **派生规则配置化**：rarity→价格区间/堆叠上限默认/掉落权重这类派生关系进 Definition JSON，禁代码查表 |
| FV-3 | **耐久规则挂点**：损耗系数/修理价格留 Definition 挂点（玩法 Phase4+，YAGNI） |

---

## 8. Enforcement：规则 → Gate 矩阵 IE-R01~IE-R12

| RULE_ID | 规则 | 严重度 | 执行层 | 检查器 / 测试 | Gate |
|---|---|---|---|---|---|
| IE-R01 | iid 永不复用，唯一分配器发放（ID-1/3） | FATAL | E3 | id_validator（序列审计） | GATE07 |
| IE-R02 | 装备存档必含 iid 引用，回环耐久/来源/锁定逐字段一致（EA-1） | FATAL | E2 | equip_roundtrip_test | GATE08 |
| IE-R03 | Purchase Golden Invariant 永久回归（TX-1/0-C.19） | FATAL | E2 | transaction_test（VS-001 A-G） | GATE26 |
| IE-R04 | 物品变更必经 Command/事务，禁旁路直改 slots/袋子 | FATAL | E3 | module_scope_validator | GATE05 |
| IE-R05 | Inventory 不负责清单（Equipment Rule/Shop Price/Crafting Rule/Quest Reward）禁入 | FATAL | E3 | state_owner_validator（词表） | GATE25 |
| IE-R06 | Equipment↔Inventory 只许 Command/Transaction/Event（EQ-1），禁 `GameManager.<service>` 直调 | FATAL | E3 | dependency_validator | GATE04 |
| IE-R07 | 槽位/容量/重量上限必须 JSON 配置，服务内 const 退役（IN-2/EQ-2） | ERROR | E3 | 硬编码扫描 | GATE06 |
| IE-R08 | flags 位组合合法性（FV-1） | ERROR | E3 | content 语义层校验 | GATE06 |
| IE-R09 | locked 实例禁被动移除（IT-2）——存量锁定测试升级为契约 | FATAL | E2 | inventory_lock_test | GATE02 |
| IE-R10 | Rematerialize/读档回环：物品数/耐久/锁定逐字段一致（06 AM-1 同源） | FATAL | E2 | inventory_roundtrip_test | GATE08 |
| IE-R11 | 回放：同 seed 同命令序列 ⇒ 背包/装备终态一致 | FATAL | E2 | inventory_replay_test | GATE29 |
| IE-R12 | 派生规则（rarity→价格/堆叠）禁代码查表（FV-2） | ERROR | E3 | content 校验 | GATE06 |

**E0（纯文档约束）计数 = 0**。Gate 列一律 LN 编号（04 §2.1 政策）。

---

## 9. 现有资产迁移映射表

| 现状 | 目标 | Phase |
|---|---|---|
| `equipment.save()` 只存 item_id | `{slots: {slot: iid}}` + 旧档降级重建（EA-1/2） | Phase2 |
| equip 手工回滚（L46-55） | Transaction Journal undo（TX-2） | Phase2 |
| `InventoryTransaction` | 02 事务契约的 Inventory 段 Handler（TX-2） | Phase2 |
| shop→economy→inventory 购买链 | PurchaseCommand + Golden Invariant 测试（TX-1/3） | Phase2（VS-001） |
| `_next_iid` 自管发号 | EntityId 分配器 domain 序列（ID-1/2） | Phase1 |
| 三槽 const + 容量常量 | slots.json + bags.json（EQ-2/IN-2） | Phase3 |
| `flags: 67` 魔数 | 位组合校验规则（FV-1） | Phase1（校验器） |
| `GameManager.inventory_service` 直调 | Command/Event（EQ-1） | Phase2 |

---

## 10. 开放问题（必须 ADR 裁决，AI 不得自决）

| # | 问题 | 倾向 |
|---|---|---|
| IE-1 | 装备实例真源归属：Inventory 单一真源+Equipment 持 iid 引用 vs Equipment 自持已装实例 | **Inventory 单一真源**（与 08 图思想同源：一处事实，多处引用；双处持实例必漂移） |
| IE-2 | `_next_iid` 并入 EntityId 分配器的时机与旧档水位策略 | Phase1 随 Kernel；水位=max(现存)+1（ID-2） |
| IE-3 | Loadout 多配装本期是否建 | 挂点不实装（EQ-5，YAGNI） |
| IE-4 | 耐久损耗/修理玩法时机 | Phase4+ 玩法期（FV-3 只留 Definition 挂点） |

---

## 11. Freeze 清单（`ITEM-INVENTORY-EQUIPMENT v1.2.0`）

| 冻结物 | 内容 |
|---|---|
| Item 三件套 | IT-1~IT-4（三态 / 实例身份 / SCHEMA_VERSION / owner 字段） |
| Inventory | IN-1~IN-5（七词+不负责清单 / 容器 JSON 化 / 预检先行 / Stack 纯函数 / 索引缓存） |
| Equipment | EQ-1~EQ-5（六词+协作方式 / 槽位 JSON 化 / Condition 需求 / 纯函数重算 / Loadout 挂点） |
| 实例入档+事务 | EA-1~3 + TX-1~4（iid 引用 / 旧档降级 / Golden Invariant / 三命令统一事务 / Shop 边界 / ErrorCode） |
| iid 分配 | ID-1~ID-3（单一分配器 / 水位策略 / 禁自建序列） |
| flags·数值 | FV-1~FV-3（位组合校验 / 派生配置化 / 耐久挂点） |
| IE-R01~IE-R12 | §8 全矩阵 |

---

## 12. 完成定义（DoD，7 条）

1. 装备存档升级 iid 引用：回环测试耐久/来源/锁定零丢失（EA-1，IE-R02 绿）；
2. PurchaseCommand 通过 0-C.19 Golden Invariant + 0-C.20 十一场景矩阵（VS-001 A-G 全红转绿）；
3. equip 手工回滚退役，Journal undo 接管；`InventoryTransaction` 收编为段 Handler；
4. iid 并入分配器，水位推导可复算，撞号构造测试被拒（ID-1/2）；
5. 槽位/容量 JSON 化，服务内 const 清零（IE-R07 扫描通过）；
6. flags 位组合校验上线，非法组合数据被 GATE6 拦截（构造用例验证）；
7. **全部为骨架与契约，未动任何生产源码**（本图产出阶段）。

---

## 13. 09 的一句话总纲

**定义只读、实例唯一、装备是引用；一手交钱一手交货是 Golden Invariant，不是愿望。**

---

## 关联文档

- `PROJECT_CONSTITUTION_V1.2.md`（0-C.19 Purchase Golden Invariant / 0-C.20 事务测试矩阵 / L2058-2065 Owner 表）
- `01_总体架构施工图_V1.2.md`（§56 Item / §57 Inventory / §58 Equipment / §60 Shop 边界 / §108-109 VS-001）
- `02_Domain_Kernel施工图_V1.2.md`（TransactionContext / MutationJournal / ErrorCode / EntityId）
- `06_Actor_Player_NPC施工图_V1.2.md`（分配器 / AM-1 回环一致）
- `07_World_Time_Schedule施工图_V1.2.md`（TX-4 禁自建序列同源 / TimeConsumer）
- `08_Relationship_Faction施工图_V1.2.md`（一处事实多处引用同源思想 / RM-2 直连清零）
- `05_Content_Registry_Content_Pipeline施工图_V1.2.md`（items/*.json 归 Definition / 五层校验语义层）
