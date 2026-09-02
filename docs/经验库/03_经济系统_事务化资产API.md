# 03 · 经济系统：事务化资产 API（扣钱不发货 / 扣料丢产出 锁死）

> 检索关键词：经济、背包、商店、锻造、炼药、事务、资产守恒、锁定、InventoryTransaction、try_consume、BUG-04
> 等级：E2

## 真源
`services/inventory/inventory_service.gd`（778 行）、`inventory_transaction.gd`（83 行）、`services/shop/shop_service.gd`（145 行）、`services/forge/forge_service.gd`（106 行）、`services/alchemy/alchemy_service.gd`（43 行）。

## 核心模式
把「扣钱不发货 / 扣料丢产出 / 售卖锁定物换钱」类 **P0 资产损失 BUG** 用事务化 API 全部锁死。

## 分层
- `InventoryService`：三栏（主/材料/任务），按 `type` 自动归类、堆叠、负重；**实例 ID 发号器** `_next_iid` 全局自增 + 存档恢复（杜绝撞车）；`_count_index` O(1) 查总数；**锁定** `locked` 实例受保护。
- `InventoryTransaction`（批量事务）：`commit` 先**预校验**（remove 用 `get_unlocked_count` / add 用 `can_add` / consume 用实例存在）再 apply `add → remove → consume`，失败回滚。
- `ShopService`：买入 `spend_money`+`add_item`；卖出 `remove_item_by_id`+`add_money`。
- `ForgeService` / `AlchemyService`：校验 → 扣料 → 产出。

## 关键实现（代码技术）
1. **两段式事务**：`try_consume` 聚合 `need_by_id` 全量校验（防同物多条漏算），用**非锁定可用量** `get_unlocked_count` 校验，统一 `remove_item_by_id`；任一不足整体不扣。
2. **买卖防「钱扣了货没到」**（P0）：`buy` 先 `can_add` 预检背包，装不下直接拒；`add_item` 失败兜底 `add_money(total)` 退款。
3. **售卖防经济漏洞**（BUG-04）：`sell` 用 `get_unlocked_count`（非 `get_item_count`）——用含锁定总量会「只扣未锁定却按全量付钱」，白赚银两还留锁定物。
4. **锻造/炼药防「扣料丢产出」**（P0）：先 `can_add(out_id, out_count)` 预检产出空间，满包整体失败；再 `try_consume` 原子扣料；最后 `add_item` 产出。
5. **实例身份保留**：装备卸下走 `add_instance`（原样归还，不 mint 新 iid、保耐久/锁定）。
6. **负重真值**：`get_max_weight = BASE_MAX_WEIGHT + strength × 系数`，UI 禁再用常量。

## 解决什么
- P0 资产损失三类全锁死；锁定物在售卖/分解/丢弃/团灭均跳过（`lose_some_non_rare_items` 规则全配置化，去硬编码 `rarity=="common"`）。

## 隐患
- 事务顺序 `add → remove`：add 成功 remove 失败则回滚（日志可追）。
- 战斗用药不直接改 `PlayerState`（P1-3）：派发 `item_used_in_battle` 由战斗场景结算。
- `query_add` 用 `maxi(0, mini(...))` 夹紧负 `room`（P2-8），防 `added` 负 / `overflow` 越界。
- `save` 必须 `duplicate(true)` 深拷贝（否则 `reset().clear()` 连带清空快照）。

## 关联
- 见 `04_结缘系统_单一真源与回城编排.md`（propose 事务扣聘礼同源）
- 见 `09_可复用模式清单.md`（事务化资产 API 作为跨项目复用模式）
