# services/shop/shop_service.gd
# 商店系统（Phase 2 系统填充）：玩家向商店买卖物品
# 纯配置驱动、无持久状态（商店库存为静态配置），故不实现 ISaveable
# 2026-08-29 叶子层实现：buy() / sell() / can_buy() / can_sell() 补全
# 2026-09-06 D-10 收编：buy/sell 事务段改走 ShopTradeTransaction（TransactionRuntime/
#   Journal/0-C.19 Golden Invariant），手工补偿退役；预检链与对外签名零变。
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

	# 事务段（10 图 EC-5 / 0-C.19 / 01 §60）：Money Mutation → Inventory Mutation → Commit。
	# 预检后理论上不可达的 run 失败也走统一回滚（0-C.8），绝不手工补偿。
	var trade := ShopTradeTransaction.new()
	var out: Dictionary = trade.execute_buy(ps, inv, shop_id, item_id, total, count)
	var cr: CommandResult = out["result"]
	if cr.is_ok():
		EventBus.notify_trade_completed.emit(shop_id, item_id, count, true)
		return ShopEnums.TradeResult.SUCCESS
	if cr.is_recovery_required():
		# 0-C.9：回滚自身失败禁静默，五元组上日志，人工介入
		push_error("[ShopService] buy rollback RECOVERY_REQUIRED: %s" % str(cr.get_error().get_context()))
	var fail_tag: String = out["fail_tag"]
	EventBus.notify_trade_failed.emit(shop_id, item_id, fail_tag)
	return _tag_to_result(fail_tag)

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

	# 预检用「未锁定」数量：锁定物受保护不被动移除（见 inventory_service.remove_item_by_id 跳过 locked），
	# 若用含锁定的 get_item_count 预检会出现「只扣未锁定部分却按全量付钱」的经济漏洞（白赚银两+保留锁定物）
	if inv.get_unlocked_count(item_id) < count:
		EventBus.notify_trade_failed.emit(shop_id, item_id, "NO_ITEM")
		return ShopEnums.TradeResult.FAIL_NO_ITEM

	var total: int = sell_price(shop_id, item_id) * count
	# 事务段：Inventory Mutation → Money Mutation（先扣货后给钱，10 图 P-E5 冻结序）。
	# remove 失败（预检后理论不可达）走统一回滚，绝不加钱。
	var trade := ShopTradeTransaction.new()
	var out: Dictionary = trade.execute_sell(ps, inv, shop_id, item_id, total, count)
	var cr: CommandResult = out["result"]
	if cr.is_ok():
		EventBus.notify_trade_completed.emit(shop_id, item_id, count, false)
		return ShopEnums.TradeResult.SUCCESS
	if cr.is_recovery_required():
		push_error("[ShopService] sell rollback RECOVERY_REQUIRED: %s" % str(cr.get_error().get_context()))
	var fail_tag: String = out["fail_tag"]
	EventBus.notify_trade_failed.emit(shop_id, item_id, fail_tag)
	return _tag_to_result(fail_tag)

## 失败标签 → TradeResult 映射（09 TX-4：失败原因走常量，UI 禁判中文字符串；
## 既存英文标签为 UI 兼容面，Phase4 随 GATE21/32 收编统一）
func _tag_to_result(tag: String) -> int:
	match tag:
		"NO_MONEY":
			return ShopEnums.TradeResult.FAIL_NO_MONEY
		"BAG_FULL":
			return ShopEnums.TradeResult.FAIL_BAG_FULL
		"NO_ITEM":
			return ShopEnums.TradeResult.FAIL_NO_ITEM
		"NO_STOCK":
			return ShopEnums.TradeResult.FAIL_NO_STOCK
		_:
			return ShopEnums.TradeResult.FAIL_INVALID

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
