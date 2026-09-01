# tests/unit/test_shop_service.gd
# 商店服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 重点：P0 回归保护——BUG-04 售卖锁定物经济漏洞
#   - 售卖预校验必须用 get_unlocked_count（非 get_item_count），否则"只扣未锁定部分却按全量付钱"白赚银两+保留锁定物
#   - remove_item_by_id 失败（全锁定时）必须不计钱、物品不丢

extends TestBase
class_name TestShopService

const SHOP_GENERAL := "shop_general_001"
const SHOP_WEAPON := "shop_weapon_001"
const PILL := "pill_heal_xiaohuan_001"      # 售价 20*0.5=10；可堆叠（单实例）
const WEAPON := "weapon_sword_iron_001"      # 售价 80*0.5=40；max_stack=1（多实例，便于锁）
const PILL_SELL := 10
const WEAPON_SELL := 40

var _orig_inv: InventoryService
var _inv: InventoryService
var _shop: ShopService

func before_each() -> void:
	# 隔离：用本套件自有背包实例替换全局，避免污染其它套件
	_orig_inv = GameManager.inventory_service
	_inv = InventoryService.new()
	_inv.reset()
	GameManager.inventory_service = _inv
	GameManager.player_state.silver = 1000
	_shop = ShopService.new()

func after_each() -> void:
	# 还原全局背包 + 清零银两，避免跨套件污染
	GameManager.inventory_service = _orig_inv
	if _orig_inv != null:
		_orig_inv.reset()
	GameManager.player_state.silver = 0

func _all_iids(item_id: String) -> Array:
	var out: Array = []
	for bag in [_inv.main_slots, _inv.material_slots, _inv.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				out.append(String(inst.instance_id))
	return out

## 正常售卖：扣物 + 加钱，按未锁定全量结算
func test_sell_normal_success() -> void:
	_inv.add_item(PILL, 5, "test")
	var silver0: int = GameManager.player_state.silver
	var r: int = _shop.sell(SHOP_GENERAL, PILL, 3)
	expect_eq(r, ShopEnums.TradeResult.SUCCESS, "正常售卖应成功")
	expect_eq(_inv.get_item_count(PILL), 2, "应扣 3 个，剩 2")
	expect_eq(GameManager.player_state.silver, silver0 + 3 * PILL_SELL, "银两应 +3*10=30")

## BUG-04 核心回归：请求卖出量超过「未锁定」可用量 → 整体拒绝，绝不白赚
func test_sell_locked_rejected() -> void:
	# 5 把武器（max_stack=1 → 5 个独立实例），锁 2 把，未锁定可用=3
	_inv.add_item(WEAPON, 1, "test")
	_inv.add_item(WEAPON, 1, "test")
	_inv.add_item(WEAPON, 1, "test")
	_inv.add_item(WEAPON, 1, "test")
	_inv.add_item(WEAPON, 1, "test")
	var iids: Array = _all_iids(WEAPON)
	expect_eq(iids.size(), 5, "应有 5 个独立实例")
	_inv.set_item_locked(iids[0], true)
	_inv.set_item_locked(iids[1], true)
	expect_eq(_inv.get_unlocked_count(WEAPON), 3, "未锁定可用应为 3")
	var silver0: int = GameManager.player_state.silver
	# 试图卖 5 把（>未锁定 3）→ 必须失败，且银两/物品不变
	var r: int = _shop.sell(SHOP_WEAPON, WEAPON, 5)
	expect_eq(r, ShopEnums.TradeResult.FAIL_NO_ITEM, "超未锁定量售卖应拒绝")
	expect_eq(_inv.get_item_count(WEAPON), 5, "物品不应被扣（锁定物受保护）")
	expect_eq(GameManager.player_state.silver, silver0, "银两不应增加（无白赚）")

## 仅未锁定部分可售：卖 3（==未锁定量）成功，只扣未锁的，钱按 3 结算
func test_sell_partial_locked_only_removes_unlocked() -> void:
	_inv.add_item(WEAPON, 1, "test")
	_inv.add_item(WEAPON, 1, "test")
	_inv.add_item(WEAPON, 1, "test")
	_inv.add_item(WEAPON, 1, "test")
	_inv.add_item(WEAPON, 1, "test")
	var iids: Array = _all_iids(WEAPON)
	_inv.set_item_locked(iids[0], true)
	_inv.set_item_locked(iids[1], true)
	var silver0: int = GameManager.player_state.silver
	var r: int = _shop.sell(SHOP_WEAPON, WEAPON, 3)
	expect_eq(r, ShopEnums.TradeResult.SUCCESS, "恰好未锁定量应成功")
	expect_eq(_inv.get_item_count(WEAPON), 2, "应只扣 3 把未锁的，剩 2 把锁定")
	expect_eq(GameManager.player_state.silver, silver0 + 3 * WEAPON_SELL, "银两应 +3*40=120")

## count<=0 非法请求：直接拒绝，无状态变化
func test_sell_count_zero_invalid() -> void:
	_inv.add_item(PILL, 3, "test")
	var silver0: int = GameManager.player_state.silver
	var r: int = _shop.sell(SHOP_GENERAL, PILL, 0)
	expect_eq(r, ShopEnums.TradeResult.FAIL_INVALID, "count<=0 应拒绝")
	expect_eq(_inv.get_item_count(PILL), 3, "物品数不变")
	expect_eq(GameManager.player_state.silver, silver0, "银两不变")

## 不存在的商店：直接拒绝
func test_sell_unknown_shop_rejected() -> void:
	_inv.add_item(PILL, 3, "test")
	var r: int = _shop.sell("no_such_shop_999", PILL, 1)
	expect_eq(r, ShopEnums.TradeResult.FAIL_INVALID, "未知商店应拒绝")
