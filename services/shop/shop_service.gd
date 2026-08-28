# services/shop/shop_service.gd
# 商店系统（Phase 2 系统填充）：玩家向商店买卖物品
# 纯配置驱动、无持久状态（商店库存为静态配置），故不实现 ISaveable
# 2026-08-29 叶子层实现：buy() / sell() / can_buy() / can_sell() 补全
# 货币走 PlayerState.silver（spend_money / add_money），价格单位=银两

extends RefCounted
class_name ShopService

## 找商店里某物品的库存条目；没有返回空 Dictionary
func _find_stock(shop: Dictionary, item_id: String) -> Dictionary:
	for s in shop.get("stock", []):
		if String(s.get("item_id", "")) == item_id:
			return s
	return {}

## 买入价 = 配置 price × buy_rate
func buy_price(shop_id: String, item_id: String) -> int:
	var shop: Dictionary = ConfigManager.get_shop(shop_id)
	var entry: Dictionary = _find_stock(shop, item_id)
	if entry.is_empty():
		return 0
	var rate: float = float(shop.get("buy_rate", 1.0))
	return int(round(float(entry.get("price", 0)) * rate))

## 卖出价 = 配置 price × sell_rate
func sell_price(shop_id: String, item_id: String) -> int:
	var shop: Dictionary = ConfigManager.get_shop(shop_id)
	var entry: Dictionary = _find_stock(shop, item_id)
	if entry.is_empty():
		return 0
	var rate: float = float(shop.get("sell_rate", 0.5))
	return int(round(float(entry.get("price", 0)) * rate))

## 玩家买入：扣银两 + 入背包
func buy(shop_id: String, item_id: String, count: int) -> int:
	if count <= 0 or item_id == "":
		EventBus.notify_trade_failed.emit(shop_id, item_id, "INVALID")
		return ShopEnums.TradeResult.FAIL_INVALID

	var shop: Dictionary = ConfigManager.get_shop(shop_id)
	if shop.is_empty():
		EventBus.notify_trade_failed.emit(shop_id, item_id, "INVALID")
		return ShopEnums.TradeResult.FAIL_INVALID

	var entry: Dictionary = _find_stock(shop, item_id)
	if entry.is_empty():
		EventBus.notify_trade_failed.emit(shop_id, item_id, "NO_STOCK")
		return ShopEnums.TradeResult.FAIL_NO_STOCK

	# 库存上限（stock_limit < 0 表示不限）
	var limit: int = int(entry.get("stock_limit", -1))
	if limit >= 0 and count > limit:
		EventBus.notify_trade_failed.emit(shop_id, item_id, "NO_STOCK")
		return ShopEnums.TradeResult.FAIL_NO_STOCK

	var total: int = buy_price(shop_id, item_id) * count
	var ps: PlayerState = GameManager.player_state
	if ps == null or ps.silver < total:
		EventBus.notify_trade_failed.emit(shop_id, item_id, "NO_MONEY")
		return ShopEnums.TradeResult.FAIL_NO_MONEY

	var inv: InventoryService = GameManager.inventory_service
	if inv == null:
		EventBus.notify_trade_failed.emit(shop_id, item_id, "INVALID")
		return ShopEnums.TradeResult.FAIL_INVALID

	# 物品存在性检查（先于 can_add：不存在物品不能误报成"背包满"）
	if not ConfigManager.has_item(item_id):
		EventBus.notify_trade_failed.emit(shop_id, item_id, "NO_SUCH_ITEM")
		return ShopEnums.TradeResult.FAIL_INVALID

	# 背包空间预检（P0 修复）：装不下就不扣钱，绝不出现"钱扣了货没到"
	if not inv.can_add(item_id, count):
		EventBus.notify_trade_failed.emit(shop_id, item_id, "BAG_FULL")
		return ShopEnums.TradeResult.FAIL_BAG_FULL

	ps.spend_money(total)
	if not inv.add_item(item_id, count, "shop_buy"):
		# 兜底回滚（预检后理论上不可达）：退款，保证资产守恒
		ps.add_money(total)
		EventBus.notify_trade_failed.emit(shop_id, item_id, "BAG_FULL")
		return ShopEnums.TradeResult.FAIL_BAG_FULL
	EventBus.notify_trade_completed.emit(shop_id, item_id, count, true)
	return ShopEnums.TradeResult.SUCCESS

## 玩家卖出：扣背包 + 加银两
func sell(shop_id: String, item_id: String, count: int) -> int:
	if count <= 0 or item_id == "":
		EventBus.notify_trade_failed.emit(shop_id, item_id, "INVALID")
		return ShopEnums.TradeResult.FAIL_INVALID

	var shop: Dictionary = ConfigManager.get_shop(shop_id)
	if shop.is_empty():
		EventBus.notify_trade_failed.emit(shop_id, item_id, "INVALID")
		return ShopEnums.TradeResult.FAIL_INVALID

	var entry: Dictionary = _find_stock(shop, item_id)
	if entry.is_empty():
		EventBus.notify_trade_failed.emit(shop_id, item_id, "NO_ITEM")
		return ShopEnums.TradeResult.FAIL_NO_ITEM

	var inv: InventoryService = GameManager.inventory_service
	var ps: PlayerState = GameManager.player_state
	if inv == null or ps == null:
		EventBus.notify_trade_failed.emit(shop_id, item_id, "INVALID")
		return ShopEnums.TradeResult.FAIL_INVALID

	if inv.get_item_count(item_id) < count:
		EventBus.notify_trade_failed.emit(shop_id, item_id, "NO_ITEM")
		return ShopEnums.TradeResult.FAIL_NO_ITEM

	var total: int = sell_price(shop_id, item_id) * count
	inv.remove_item_by_id(item_id, count)
	ps.add_money(total)
	EventBus.notify_trade_completed.emit(shop_id, item_id, count, false)
	return ShopEnums.TradeResult.SUCCESS

## UI 用：银两是否够买 count 个
func can_buy(shop_id: String, item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	var entry: Dictionary = _find_stock(ConfigManager.get_shop(shop_id), item_id)
	if entry.is_empty():
		return false
	var limit: int = int(entry.get("stock_limit", -1))
	if limit >= 0 and count > limit:
		return false
	var ps: PlayerState = GameManager.player_state
	return ps != null and ps.silver >= buy_price(shop_id, item_id) * count

## UI 用：背包是否够卖 count 个
func can_sell(shop_id: String, item_id: String, count: int = 1) -> bool:
	if count <= 0:
		return false
	var entry: Dictionary = _find_stock(ConfigManager.get_shop(shop_id), item_id)
	if entry.is_empty():
		return false
	var inv: InventoryService = GameManager.inventory_service
	return inv != null and inv.get_item_count(item_id) >= count
