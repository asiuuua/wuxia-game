# tests/unit/test_shop_trade_tx.gd
# 买卖事务收编测试（D-10 / 宪法 0-C.19 Golden Case / 0-C.20 业务侧可达场景 / 10 图 EC-5）
# 矩阵分工：Runtime 层十一路失败路径由 test_transaction_runtime.gd 承接；
# 本套件钉死业务侧：成功黄金等式 / Precheck 失败零变化 / 首·中 Mutation 失败回滚 /
# Invariant 拦截 / 连续事务（0-C.10 释放正确性）。
# 替身：FakeInvAddFail（can_add 真实现过预检、add_item 恒败 → 驱动中间 Mutation 失败）
#       FakeInvRemoveFail（get_unlocked_count 真实现过预检、remove 恒败 → 驱动首个 Mutation 失败）
#       BadFacts（get_int 返回被篡改读数 → 驱动 Invariant 拦截）

extends TestBase
class_name TestShopTradeTx

const SHOP_GENERAL := "shop_general_001"
const SHOP_WEAPON := "shop_weapon_001"
const PILL := "pill_heal_xiaohuan_001"      # 售价 20*0.5=10；可堆叠
const WEAPON := "weapon_sword_iron_001"      # max_stack=1（多实例，便于构造满包）

var _orig_inv: InventoryService
var _inv: InventoryService
var _shop: ShopService

func before_each() -> void:
	_orig_inv = GameManager.inventory_service
	_inv = InventoryService.new()
	_inv.reset()
	GameManager.inventory_service = _inv
	GameManager.player_state.silver = 1000
	_shop = ShopService.new()

func after_each() -> void:
	GameManager.inventory_service = _orig_inv
	if _orig_inv != null:
		_orig_inv.reset()
	GameManager.player_state.silver = 0

# ---------------- 替身 ----------------

## add_item 恒败（预检 can_add 走真实现 → 构造「预检过、Mutation 失败」）
class FakeInvAddFail extends InventoryService:
	func add_item(_item_id: String, _count: int, _source: String = "") -> bool:
		return false

## remove_item_by_id 恒败（get_unlocked_count 真实现 → 构造「预检过、首 Mutation 失败」）
class FakeInvRemoveFail extends InventoryService:
	func remove_item_by_id(_item_id: String, _count: int) -> bool:
		return false

## 被篡改读数的事实门面（silver 与 expect_silver 读数错位 → 驱动 Golden Invariant 拦截）
class BadFacts extends GameFacts:
	func get_int(key: StringName) -> int:
		return 999999 if key == &"silver" else 12345

	func get_bool(_key: StringName) -> bool:
		return false

	func get_entity_id(_key: StringName) -> EntityId:
		return EntityId.of(&"test", "bad")

# ---------------- buy ----------------

## 0-C.19 成功侧：GoldAfter = GoldBefore - Price ∧ InventoryAfter = InventoryBefore + Item
func test_buy_success_golden() -> void:
	_inv.add_item(PILL, 1, "test")
	var silver0: int = GameManager.player_state.silver
	var count0: int = _inv.get_item_count(PILL)
	var r: int = _shop.buy(SHOP_GENERAL, PILL, 2)
	expect_eq(r, ShopEnums.TradeResult.SUCCESS, "买入应成功")
	expect_eq(GameManager.player_state.silver, silver0 - 40, "黄金等式：银两应 -40（20*2）")
	expect_eq(_inv.get_item_count(PILL), count0 + 2, "黄金等式：物品应 +2")

## 0-C.19 失败侧：余额不足 Precheck 拒绝，两侧零变化
func test_buy_insufficient_silver_zero_mutation() -> void:
	_inv.add_item(PILL, 1, "test")
	GameManager.player_state.silver = 5
	var r: int = _shop.buy(SHOP_GENERAL, PILL, 2)
	expect_eq(r, ShopEnums.TradeResult.FAIL_NO_MONEY, "余额不足应拒绝")
	expect_eq(GameManager.player_state.silver, 5, "失败侧：银两零变化")
	expect_eq(_inv.get_item_count(PILL), 1, "失败侧：物品零变化")

## 0-C.19 失败侧：满包 Precheck 拒绝，零变化
func test_buy_bag_full_zero_mutation() -> void:
	# 塞满主栏（weapon max_stack=1 每把占一槽）
	for i in range(InventoryService.MAX_MAIN_SLOTS):
		_inv.add_item(WEAPON, 1, "test")
	GameManager.player_state.silver = 5000
	var r: int = _shop.buy(SHOP_WEAPON, WEAPON, 1)
	expect_eq(r, ShopEnums.TradeResult.FAIL_BAG_FULL, "满包应拒绝")
	expect_eq(GameManager.player_state.silver, 5000, "失败侧：银两零变化")

## 中间 Mutation 失败（0-C.20）：spend 成功 → add 失败 → 逆序 undo 补回银两
func test_buy_add_fails_rolls_back_money() -> void:
	var fake := FakeInvAddFail.new()
	fake.reset()
	GameManager.inventory_service = fake
	_inv.add_item(PILL, 1, "test")   # 原包留个底，确保不是空包歧义
	GameManager.player_state.silver = 1000
	var r: int = _shop.buy(SHOP_GENERAL, PILL, 2)
	expect_eq(r, ShopEnums.TradeResult.FAIL_BAG_FULL, "add_item 失败应映射 BAG_FULL")
	expect_eq(GameManager.player_state.silver, 1000, "核心断言：扣款必须被 undo 完整补回")
	# 还原隔离
	GameManager.inventory_service = _inv

## 连续两笔事务（0-C.10：每笔终态后 _active 必须释放，第二笔不得被嵌套拒绝误伤）
func test_consecutive_buy_no_stuck() -> void:
	var r1: int = _shop.buy(SHOP_GENERAL, PILL, 1)
	var r2: int = _shop.buy(SHOP_GENERAL, PILL, 1)
	expect_eq(r1, ShopEnums.TradeResult.SUCCESS, "第一笔应成功")
	expect_eq(r2, ShopEnums.TradeResult.SUCCESS, "第二笔应成功（事务已释放）")

# ---------------- sell ----------------

## 0-C.19 对称等式：卖成败侧（先扣货后给钱冻结序）
func test_sell_success_golden() -> void:
	_inv.add_item(PILL, 5, "test")
	var silver0: int = GameManager.player_state.silver
	var r: int = _shop.sell(SHOP_GENERAL, PILL, 3)
	expect_eq(r, ShopEnums.TradeResult.SUCCESS, "卖出应成功")
	expect_eq(_inv.get_item_count(PILL), 2, "物品应 -3")
	expect_eq(GameManager.player_state.silver, silver0 + 30, "银两应 +30（10*3）")

## 首个 Mutation 失败（0-C.20）：remove 失败 → 回滚 → 绝不加钱、物品不丢
func test_sell_remove_fails_no_money() -> void:
	var fake := FakeInvRemoveFail.new()
	fake.reset()
	GameManager.inventory_service = fake
	_inv.add_item(PILL, 5, "test")
	GameManager.player_state.silver = 100
	var silver0: int = GameManager.player_state.silver
	var r: int = _shop.sell(SHOP_GENERAL, PILL, 3)
	expect_eq(r, ShopEnums.TradeResult.FAIL_NO_ITEM, "remove 失败应拒绝")
	expect_eq(GameManager.player_state.silver, silver0, "核心断言：remove 失败绝不加钱")
	GameManager.inventory_service = _inv
	expect_eq(_inv.get_item_count(PILL), 5, "原包物品不受替身套件影响")

## 锁定物防白赚回归（BUG-04 既有语义在新事务形态下保持）：锁定 2 把、只卖得动 3 把
func test_sell_locked_rejected_under_tx() -> void:
	for i in range(5):
		_inv.add_item(WEAPON, 1, "test")
	var iids: Array = []
	for bag in [_inv.main_slots, _inv.material_slots, _inv.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == WEAPON:
				iids.append(String(inst.instance_id))
	for i in range(2):
		_inv.set_item_locked(iids[i], true)
	var silver0: int = GameManager.player_state.silver
	var r: int = _shop.sell(SHOP_WEAPON, WEAPON, 4)
	expect_eq(r, ShopEnums.TradeResult.FAIL_NO_ITEM, "超过未锁定可用量应整体拒绝")
	expect_eq(GameManager.player_state.silver, silver0, "零变化：绝不白赚")
	expect_eq(_inv.get_item_count(WEAPON), 5, "锁定物必须全部保留")

# ---------------- Invariant ----------------

## 0-C.19 Invariant 拦截：被篡改读数（银两对不上等式）必须 INVARIANT_VIOLATION
func test_golden_invariant_rejects_tampered_facts() -> void:
	var golden := ShopTradeTransaction.TradeGoldenInvariant.new()
	var r: OperationResult = golden.evaluate(BadFacts.new())
	expect(r.is_failed(), "篡改读数必须被 Golden Invariant 拦截")
	expect(r.get_error().get_code() == ErrorCode.INVARIANT_VIOLATION, "错误码应为 INVARIANT_VIOLATION")

## 对照：真实 ShopTradeFacts 在成功路径上 Invariant 必须放行（防 Invariant 永假空转）
func test_golden_invariant_passes_real_facts() -> void:
	var before: int = _inv.get_item_count(PILL)
	_shop.buy(SHOP_GENERAL, PILL, 1)
	var facts := ShopTradeTransaction.ShopTradeFacts.new(
		GameManager.player_state, _inv, PILL,
		GameManager.player_state.silver, before + 1
	)
	var golden := ShopTradeTransaction.TradeGoldenInvariant.new()
	var r: OperationResult = golden.evaluate(facts)
	expect(r.is_ok(), "真实一致读数必须放行（Invariant 不得永假）")
