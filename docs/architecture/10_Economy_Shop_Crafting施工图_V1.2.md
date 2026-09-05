# 10 Economy / Shop / Crafting 施工图 V1.2

> 状态：**FROZEN CANDIDATE**（契约冻结候选，待用户批准升 FROZEN 后方可在该域实施）
> 依据：宪法 `PROJECT_CONSTITUTION_V1.2.md` 0-C.19 / 0-C.20 / §8 / §171；01 总体架构施工图 §59 Crafting、§60 Economy / Shop；02 ErrorCode·Transaction 契约；03 ID·Schema 契约；04 Gate Registry（LN 编号）；05 Pack 收编；07 Schedule·ShopRefresh；09 InventoryTransaction·TX 系列。
> 冻结日期：2026-09-05。本图与 09 互为咬合：09 定「事务怎么走」，本图定「经济域里走什么」。

---

## 0. 编号命名空间声明

本图全文引用的门禁编号一律使用 **LN 逻辑编号 = 宪法 §88 GATE01~20 ∪ 01 §127 GATE21~32**（命名空间政策见 04 §2，待 04-T1 追认）。不裸引 verify_all 物理槽位号（物理 3/4/6/8/9 与 LN 同号不同义）。

---

## 1. 定位

Economy / Shop / Crafting 是本项目 **0-C Transaction 语义的第二主战场**（第一为 09 物品装备域）。宪法 0-C.19 Purchase Golden Case 的两个等式（`GoldAfter = GoldBefore - Price`、`InventoryAfter = InventoryBefore + Item`）在本域机器化为永久回归；01 §60 购买链路七步为唯一合法形状；01 §59 禁止 Forge / Alchemy / Cooking 三套核心并存。

**本图职责**：货币（Money/Currency/Wallet）、价格与经济规则（Price/Economic Rule）、商店五件套（01 §60）、统一 Crafting（01 §59）、生产/购买事务、经济域 ErrorCode、死亡惩罚与负债消费端。
**本图不负责**：背包容器与实例身份（09）、掉落产出（09 来源留痕消费端）、时间推进与刷新调度器本体（07，本图只定义 ShopRefreshCommand 这一消费面）、Task/Quest 奖励发放（Quest 域，只准调用本域 Command）。

---

## 2. 现状盘点（2026-09-05 机器实扫）

### 2.1 已有资产（§171：升级不丢弃）

| 资产 | 位置 | 行数 | 状态 |
| --- | --- | --- | --- |
| ShopService（buy/sell/can_buy/can_sell/buy_price/sell_price） | `services/shop/shop_service.gd` | 144 | buy 预检链完整（0-C.19 手工版），sell 有锁定物防白赚 |
| ForgeService（forge/can_forge/describe_inputs） | `services/forge/forge_service.gd` | 105 | P0 预检产出（「绝不扣了材料丢产出」）+ 白嫖窗口（见 P-1） |
| AlchemyService（refine/can_refine） | `services/alchemy/alchemy_service.gd` | 42 | try_consume 接返回值（比 forge 严谨），失败码中文串 |
| Wallet（silver/copper/gold + spend_money/add_money/add_debt/debt） | `data/runtime/player_state.gd` | 279 | 三级货币 + 负债字段已在，spend 返回 bool |
| InventoryTransaction（先 add 后 remove + 失败回滚雏形） | `services/inventory/inventory_transaction.gd` | 82 | 09 TX-3 已冻结收编为 Journal Handler |
| try_consume（聚合需求 + 未锁定量校验 + 原子整体失败） | `services/inventory/inventory_service.gd` L207-228 | — | 锁定语义正确，问题是调用方 |
| 配置三份 | `data/configs/shop/shops.json`、`data/configs/forge/recipes.json`、`data/configs/alchemy/recipes.json` | — | shop ID 合规；配方 ID/schema 双轨（见 P-4/P-7） |
| 测试三份 | `tests/unit/test_shop_service.gd`(103)/`test_forge_service.gd`(21)/`test_alchemy_service.gd`(20) | 144 | 商店锁定物三件套断言优秀（§171 保留升级）；锻造/炼金覆盖极薄 |
| 死亡惩罚消费端（扣钱→掉物→负债→CG） | `autoload/defeat_handler.gd` | — | 负债语义已存在，但直改钱包字段（P-6） |

### 2.2 实锤缺陷（编号 P-E1~P-E7，全部为扫描所得）

- **P-E1【P0·白嫖窗口】** `forge_service.gd` L57-58：`inv.try_consume(mats, ...)` **返回值未接**；且 L45 材料预检用 `get_item_count`（含锁定实例），而 `try_consume` 内部用「未锁定量」校验（`inventory_service.gd` L221-223）。三者组合：当锁定物恰好卡在 `unlocked < need ≤ total` 区间时——预检通过 → 扣料失败被吞 → **材料分文未扣、产出照发**。这是「扣料丢产出」的镜像缺陷「零料白得产出」。
- **P-E2【预检口径三态并存】** ① `can_forge` L81-87、`can_refine` L40、`describe_inputs` L101 用 `get_item_count`（含锁定）；② `shop_service.can_sell` L144 也用 `get_item_count`，**而同文件 `sell()` L111 用 `get_unlocked_count`**——同一服务内自相矛盾：UI 按钮可点（can_sell=true），执行必败（FAIL_NO_ITEM）；③ `try_consume` L223 用未锁定量。预检与执行必须同口径、同函数源。
- **P-E3【失败码双轨】** forge 失败 emit 英文常量（`"BAG_FULL"`/`"MISSING_MATERIAL"`），alchemy 失败 emit **中文串**（`"背包已满，无法放入产出"`/`"材料不足"`，alchemy_service L19/L26）；EventBus L82/L179/L185 三个信号 `reason: String`——违 02 ErrorCode「机器可识别、禁中文串判断」契约。
- **P-E4【配方双 schema】** forge 配方键 `output_item_id` + `forge_type`，alchemy 配方键 `output_pill_id`（无类别键）——同类「配方」两套形状；01 §59 要求统一 RecipeDefinition。
- **P-E5【事务四形态并存】** buy=预检→`spend_money`→`add_item`→失败退款兜底（L73-83 注释「装不下就不扣钱，绝不出现钱扣了货没到」=0-C.19 手工版，形态最完整）；sell=预检→remove→`add_money`（先扣货后给钱）；forge=预检(错口径)→try_consume(吞返回值)→add；alchemy=预检→try_consume(接返回值)→add（**先扣后产**，与 inventory_transaction 已验证的「先产后扣」相反）。四处均未走 InventoryTransaction/Journal。
- **P-E6【货币直改 + 负债游离】** `defeat_handler.gd` L94 `ps.silver = 0` 绕过 `spend_money`（手工补发事件 L95）；`debt`/`add_debt` 负债语义已存在但不在任何经济契约内；死亡掉物 `lose_some_non_rare_items` 无失去原因留痕。
- **P-E7【Shop 静态死配置 + ID 违例】** shop_service L3 自述「纯配置驱动、无持久状态」，但 `shops.json` 每条目都有 `restock` 字段——**全库无消费者**（死配置）；`stock_limit` 实际语义是「单笔购买上限」而非货架余量；配方 ID `forge_iron_sword` 违 03 白名单正则（`forge` 非 13 域，应为 `recipe_` 域，同文件 `recipe_xiaohuan` 合规）。

### 2.3 关联现状

- GameManager L17-19 持 alchemy/forge/shop 三 service（计入 17 Service God Object，Phase3 收敛）。
- ShopScreen 直调 `GameManager.shop_service.*`（查询/执行混合，Phase2 Command 收口；查询面 can_buy/can_sell/价格走 Query 化保留）。
- 07 已冻结「首张 Schedule 消费面 = Shop 刷新」——本图 EC-3 是其数据落点。
- 09 已冻结：PurchaseCommand = 0-C.19 Golden Invariant 永久回归、query_add 预检 ErrorCode、iid 分配器、InventoryTransaction 收编、「Shop 不直碰 Wallet」（09 TX-4）。本图 EC-5/R02 与之同源衔接。

---

## 3. 冻结契约

### EC-1 货币与钱包（Money / Currency / Wallet）

- **三级货币 `silver` / `copper` / `gold` 冻结保留**（旧存档三字段，存档兼容红线）；换算规则为纯函数（进 Wallet，禁散落）。
- 钱包 Owner = Economy 模块 Wallet State（`player_state` 货币段 Phase3/4 迁出落位，迁移期 facade 委托）。
- **唯一写入口 = Money Mutation**（Credit / Debit / Transfer），每次变动记一条 Journal 记录（cause 必填）；**禁直改 `silver/copper/gold/debt` 字段**（P-E6 的 `ps.silver = 0` 退役，改为 Debit 携带 `allow_overdraft` 语义）。
- **负债 Debt = 显式 Economic Rule**：`add_debt`/`debt` 收编进 Wallet State 契约；负债上限、清偿入口（后续任务/商店代扣）挂 EconomicRule 挂点，YAGNI 只留接口。
- 事件双轨：`player_money_changed(silver, copper, gold)` 全量读数信号保留兼容，但**业务判定禁依赖它**；新增 `MoneyChangedEvent { currency, delta, cause }`（对齐 07 `TimeAdvancedEvent` delta 模式）。

### EC-2 价格与经济规则（Price / Economic Rule）

- `buy_price` / `sell_price` 收编为 Economy **PriceCalculator 纯函数**（现 shop_service 签名保留，内部委托）。
- 取整规则冻结：`int(round(price × rate))`——禁止截断（floor）与浮点直等比较。
- 折扣 / 溢价 / 好感减免挂 **EconomicRule 挂点**（规则输入 PriceContext，输出修正价）；YAGNI：本期不实装任何具体折扣。
- 价格禁 UI 私算：UI 一律走 Query（现 ShopScreen 调 `buy_price/sell_price` 合规，保留为 Query 面）。

### EC-3 Shop 五件套（01 §60）

- **ShopDefinition**（shops.json 收编，归 05 Content Pack）/ **ShopState**（货架余量 + 上次刷新日，Owner=Shop 模块，入存档切片）/ **ShopInventory**（条目数组容器）/ **ShopEntry**（`item_id + price + per_trade_limit + stock_max`）/ **ShopRule**（restock 规则）。
- **`restock` 死字段激活**：语义定为「每次刷新回补量」，由 **ShopRefreshCommand** 消费——即 07 冻结的首张 Schedule 消费面；刷新必走 Command，禁私挂 Timer。
- `stock_limit` 语义拆分冻结：`per_trade_limit`（单笔上限，现行为）+ `stock_max`（货架余量上限，随 ShopState 启用）；「纯配置驱动、无持久状态」注释退役。
- Shop 模块**不持有钱包**（01 §60「Shop 不直接操作 Player Wallet」；09 TX-4 复述，本图 R02 机器化）。

### EC-4 Crafting 统一（01 §59）

- **统一 RecipeDefinition**，唯一 schema：`{ id, name, inputs: [{item_id, count}], output_item_id, output_count, level_req, craft_type ∈ {FORGE, ALCHEMY, COOKING} }`。`output_pill_id`（alchemy）退役映射到 `output_item_id`；`forge_type` 改名收编为 `craft_type`。
- **统一 CraftingExecutor**：等级校验 → 产出空间预检 → 材料校验/扣除 → 产出 → 事件，全部一处实现；`forge_service` / `alchemy_service` 降级为**薄壳 facade**（公开签名不变，内部委托 Executor）——绞杀者迁移，21/20 行薄测试先升级为契约测试。
- **禁止**为 Forge / Alchemy / Cooking 分别建立三套核心（01 §59 原文）；新增烹饪 = 新增 RecipeDefinition 数据 + craft_type 枚举值，零核心改动。
- CraftingRule / CraftingEffect 挂点预留（品质浮动、批量消耗修正等，YAGNI 不实装）。

### EC-5 购买 / 生产事务（0-C 落地主战场续）

- **BuyItemCommand / SellItemCommand / CraftExecutionCommand = 一操作一事务一 Journal，全程可回滚**（0-C.20 矩阵覆盖）。
- 段顺序冻结（对齐 09 TX 与 inventory_transaction 已验证语义）：**产出/入货段先于扣款/扣料段**（先占坑后付钱——「先 add 后 remove」扩展到跨 Wallet+Inventory）；失败任一段整体回滚。
- **`try_consume` / `add_item` / `spend_money` 返回值禁吞**（P-E1 白嫖窗口封死；生产事务内改为显式检查 + 回滚）。
- **可用性预检唯一口径 = `get_unlocked_count`**（锁定语义全域统一）；`can_buy` / `can_sell` / `can_forge` / `can_refine` 必须与执行体共用同一校验函数源（can_* 调 can_execute，禁两套判断——P-E2 封死）。
- **0-C.19 Purchase Golden Case**：`GoldAfter = GoldBefore - Price ∧ InventoryAfter = InventoryBefore + Item`（及失败侧两等式）进永久回归套件（与 09 TX-1 同源共用用例，双域引用）。
- 0-C.20 十一场景（正常/Precheck 失败/首·中·末 Mutation 失败/Invariant 失败/Cancel/Timeout/Event Handler 失败/Save Failure/Rollback Failure）对**购买 + 生产**两类事务全覆盖（GATE26）。

### EC-6 经济域 ErrorCode

- 错误码表冻结：`TRADE_INVALID` / `TRADE_NO_STOCK` / `TRADE_NO_MONEY` / `TRADE_NO_SUCH_ITEM` / `TRADE_BAG_FULL` / `TRADE_NO_ITEM` / `CRAFT_UNKNOWN_RECIPE` / `CRAFT_MISSING_MATERIAL` / `CRAFT_LEVEL_TOO_LOW` / `CRAFT_BAG_FULL` / `CRAFT_INVALID_COUNT`。
- 事件 `reason: String` 参数升级为 ErrorCode（02 契约：机器可识别，禁中文串判断）；中文失败串退役（P-E3）。
- 码表挂接 Kernel ErrorCode 的「域扩展段」（核心 14 常量不动）——扩容机制见开放问题 EC-2 ADR。

### EC-7 死亡惩罚与负债（Economic Transaction 消费端）

- defeat 扣钱 → 掉物 → 负债三段收编为 **DebtRule + LoseItemsRule**（EconomicRule 实现），由 DefeatProcessor 按 DifficultyManager 配置驱动。
- 直改 `ps.silver = 0` 退役 → `Debit(all, allow_overdraft: true)`；负债写入 Wallet State 并入存档断言（GATE08 SaveHeader 面补 debt 字段断言）。
- 失去物品必留 Journal 足迹：`lose:defeat` 原因（09 来源留痕的镜像——得到要留痕，失去也要留痕）。

---

## 4. 迁移映射表（绞杀者，禁一次性大改）

| 现有资产 | 目标 | 阶段 |
| --- | --- | --- |
| `shop_service.buy/sell` | BuyItemCommand / SellItemCommand Handler（签名面保留 Query） | Phase2 |
| `shop_service.buy_price/sell_price` | Economy PriceCalculator（facade 委托） | Phase2 |
| `forge_service.forge/can_forge`、`alchemy_service.refine/can_refine` | CraftingExecutor 薄壳 facade（公开签名不变） | Phase2 |
| `player_state` 货币段（silver/copper/gold/debt） | Economy Wallet State（Phase3 装配收敛随迁，facade 保字段） | Phase3 |
| `shops.json` | ShopDefinition Pack 内容（05 收编）+ ShopRule（restock） | Phase1 契约 / Phase4 数据 |
| `output_pill_id` / `forge_type` / `forge_iron_sword` ID | 统一 Recipe schema + `recipe_` 域 ID（退役迁移名单入 `data/configs/_retired_ids.json`） | Phase4（随 GATE07 基线） |
| `defeat_handler._lose_money/掉物段` | DebtRule + LoseItemsRule（DefeatProcessor 调用） | Phase4 |
| `test_shop_service`（103 行锁定物三件套） | 升级契约测试（§171 保留）；`test_forge/test_alchemy` 补 0-C.20 场景 | Phase2 |
| EventBus `notify_trade_*`/`notify_forge_*`/`alchemy_*` 5 信号 | reason 升级 ErrorCode；新增 MoneyChangedEvent/进 contract_registry | Phase1 登记 / Phase2 实装 |

---

## 5. Enforcement 矩阵（EC-R01~R12，E0 = 0）

| 规则 | 内容 | 载体（LN Gate） | 级 |
| --- | --- | --- | --- |
| EC-R01 | 购买链路七步固定（01 §60）：BuyItemCommand → Shop Validation → Economy Validation → Transaction → Money Mutation → Inventory Mutation → Commit → Purchase Events | GATE24 契约漂移 + GATE28 命令序 | E2 |
| EC-R02 | Shop/Crafting 域源码禁出现 `spend_money` / `add_money` / 对 `silver|copper|gold|debt` 的直接赋值（Shop 不直碰 Wallet 机器化，09 TX-4 落扫描） | GATE12 arch_lint api 规则 + 基线 | E3 |
| EC-R03 | `try_consume` / `add_item` / `spend_money` 调用返回值禁吞（P-E1 白嫖窗口静态可查） | lint 扫描（未接返回值调用）+ GATE02 回归用例 | E3 |
| EC-R04 | 可用性预检唯一口径 `get_unlocked_count`；can_* 与执行体同函数源（禁两套判断并存，P-E2 封死） | 契约测试 + GATE24 | E2 |
| EC-R05 | 经济/生产失败 reason 必为 ErrorCode；失败信息禁中文字面量（P-E3） | GATE18 localization validator（前移覆盖）+ GATE24 | E3 |
| EC-R06 | Recipe schema 统一：`output_item_id` 唯一产出键 + `craft_type` 枚举；`output_pill_id`/`forge_type` 私键退役（P-E4） | GATE06 JSON schema validator | E3 |
| EC-R07 | 配方/商店 ID 白名单域（`recipe_` / `shop_`）；`forge_iron_sword` 类违例入退役迁移名单（P-E7） | GATE07 ref_index | E3 |
| EC-R08 | 一购买 / 一生产一事务一 Journal，任一段失败整体回滚（P-E5 收口） | GATE26 / GATE27 | E2 |
| EC-R09 | 0-C.19 Purchase Golden Case 两等式（成功侧+失败侧）永久回归，与 09 TX-1 共用用例 | GATE26（E2 实测） | E2 |
| EC-R10 | 0-C.20 十一场景对购买 + 生产事务全覆盖 | GATE26 | E2 |
| EC-R11 | 货币字段禁直改（仅 Money Mutation）；货币变动事件必带 `delta + cause`（P-E6） | GATE25 state_owner validator | E3 |
| EC-R12 | Shop 货架刷新必走 ShopRefreshCommand（07 Schedule 驱动），禁私挂 Timer / 直改 ShopState（P-E7 restock 激活面） | GATE25 + GATE28 | E3 |

> E0 占比 0%：每条规则都有扫描器或测试兜底，无「纯自觉」条款。

---

## 6. Freeze 清单（批准后冻结，改动需走 ACR）

- 文件面：`services/shop/shop_service.gd`、`services/forge/forge_service.gd`、`services/alchemy/alchemy_service.gd`、`player_state.gd` 货币段、`data/configs/shop/shops.json`、`data/configs/forge/recipes.json`、`data/configs/alchemy/recipes.json`、EventBus 5 经济信号、`test_shop_service/test_forge_service/test_alchemy_service`。
- 契约面：EC-1~EC-7 全部条款；EC-R01~R12 矩阵；错误码表 11 项；Recipe 统一 schema；货币三级与负债语义。
- 跨图咬合面：09 TX-1（Golden Invariant 用例共用）、07 ShopRefreshCommand（消费面唯一）、02 ErrorCode 域扩展段、05 ShopDefinition Pack 收编。

---

## 7. DoD（Definition of Done，7 条）

1. 本图全部 EC-* 冻结项经用户批准升 FROZEN；
2. EC-R01~R12 每条有指定载体（扫描器 / 契约测试 / validator）且实际落地，E0 = 0；
3. 0-C.19 两等式与 0-C.20 十一场景用例进入 contract / transaction 套件并在 GATE26 常绿；
4. P-E1~P-E7 每项在迁移映射表有对应收编行，旧资产升级不丢弃（§171）；
5. Recipe / Shops schema 经 GATE06 校验通过，GATE07 引用零悬空（含退役 ID 名单）；
6. 旧档兼容验证：silver / copper / gold / debt 读档不拒、缺省补齐（GATE08 / GATE09 面）；
7. 双闸门绿（GATE01 headless 零错 / GATE02 单测零 ✗）且 `verify_all.py` 全绿。

---

## 8. 开放问题（需用户 / ADR 裁决，AI 不自决）

- **EC-1（ADR）Crafting 模块归属**：独立 Crafting Module（01 §59 字面为独立 Module，**推荐**）vs 并入 Economy 作子域。推荐理由：01 §59 明文独立；与 Economy 共享事务层但内容自治；烹饪等后续类别零核心改动。
- **EC-2（ADR）Kernel ErrorCode 扩容机制**：「14 核心常量冻结不动 + 域扩展段」挂经济域 11 码（**推荐**，不破 02 冻结）vs 修改核心常量清单。与 02 O 系列开放问题咬合。
- **EC-3 货币形态**：保留三级 silver/copper/gold（**推荐**：旧存档三字段红线 + 换算纯函数）vs 收敛单币种。推荐理由：存档兼容红线，三级换算成本极低。
- **EC-4 价格粒度**：商店级 rate + ShopEntry 可选 `price_override`（**推荐**：现 shops.json 已是商店级，Entry 覆盖留弹性）vs 仅商店级 vs 全物品价目表。

---

## 9. 一句话总纲

**钱、货、配方三本账记进同一本 Journal——「钱扣了货没到」「料扣了产出丢」「零料白得货」在 10 图里是同一种机制上的不可能。**

---

## 10. 关联文档

- `01_总体架构施工图_V1.2.md` §59 Crafting / §60 Economy-Shop / §127 Gate 基线
- `02_Domain_Kernel施工图_V1.2.md` ErrorCode / Transaction 契约 / Result 家族
- `03_Contract_Schema_DataContract施工图_V1.2.md` ID 白名单正则 / Definition 四态 / Schema 版本
- `04_Test_Infrastructure_Architecture_Gate施工图_V1.2.md` Gate Registry（LN 全表）/ Test Double / GATE26
- `05_Content_Registry_Content_Pipeline施工图_V1.2.md` Pack 收编（shops/recipes 归 base pack）
- `07_World_Time_Schedule施工图_V1.2.md` ShopRefreshCommand（首张 Schedule 消费面）
- `09_Item_Inventory_Equipment施工图_V1.2.md` TX-1~4 / InventoryTransaction / iid 分配器 / ErrorCode 预检
