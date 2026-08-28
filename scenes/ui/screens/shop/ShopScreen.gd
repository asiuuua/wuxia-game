# scenes/ui/screens/shop/ShopScreen.gd
# 商店界面（Phase 2 系统填充，纯代码构建）：列出商店库存、显示银两、买入/卖出
# 铁律：UI 只做展示与输入，业务逻辑调用 GameManager / ShopService
# 2026-08-29 新建：补齐 screens.json 里已注册但缺失的界面

extends Control
class_name ShopScreen

var _list: VBoxContainer
var _silver_label: Label

func _ready() -> void:
	_build_ui()
	refresh()
	EventBus.notify_trade_completed.connect(_on_trade_completed)
	EventBus.notify_trade_failed.connect(_on_trade_failed)
	EventBus.player_money_changed.connect(_on_money_changed)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var title := Label.new()
	title.text = tr("ui_shop_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_silver_label = Label.new()
	_silver_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_silver_label)

	_list = VBoxContainer.new()
	root.add_child(_list)

	var close := Button.new()
	close.text = tr("ui_shop_close")
	close.pressed.connect(UIManager.close_screen.bind(self))
	root.add_child(close)

func refresh() -> void:
	var ps: PlayerState = GameManager.player_state
	if _silver_label != null and ps != null:
		_silver_label.text = "银两：%d" % ps.silver
	if _list == null:
		return
	for child in _list.get_children():
		child.queue_free()

	var shop_ids: Array[String] = ConfigManager.get_all_shop_ids()
	if shop_ids.is_empty():
		var e := Label.new()
		e.text = tr("ui_shop_empty")
		_list.add_child(e)
		return

	for sid in shop_ids:
		var shop: Dictionary = ConfigManager.get_shop(sid)
		var head := Label.new()
		head.text = "[%s]" % shop.get("name", sid)
		_list.add_child(head)
		for entry in shop.get("stock", []):
			_list.add_child(_build_row(sid, entry))

func _build_row(shop_id: String, entry: Dictionary) -> HBoxContainer:
	var item_id: String = String(entry.get("item_id", ""))
	var inv: InventoryService = GameManager.inventory_service
	var have: int = inv.get_item_count(item_id) if inv != null else 0
	var nm: String = ConfigManager.get_item(item_id).get("name", item_id)
	var bp: int = GameManager.shop_service.buy_price(shop_id, item_id)
	var sp: int = GameManager.shop_service.sell_price(shop_id, item_id)

	var h := HBoxContainer.new()
	var info := Label.new()
	info.custom_minimum_size = Vector2(340, 0)
	info.text = "%s  买%d/卖%d  持有%d" % [nm, bp, sp, have]

	var buy_btn := Button.new()
	buy_btn.text = tr("ui_shop_buy")
	buy_btn.disabled = not GameManager.shop_service.can_buy(shop_id, item_id, 1)
	buy_btn.pressed.connect(_on_buy_pressed.bind(shop_id, item_id))

	var sell_btn := Button.new()
	sell_btn.text = tr("ui_shop_sell")
	sell_btn.disabled = not GameManager.shop_service.can_sell(shop_id, item_id, 1)
	sell_btn.pressed.connect(_on_sell_pressed.bind(shop_id, item_id))

	h.add_child(info)
	h.add_child(buy_btn)
	h.add_child(sell_btn)
	return h

func _on_buy_pressed(shop_id: String, item_id: String) -> void:
	GameManager.shop_service.buy(shop_id, item_id, 1)

func _on_sell_pressed(shop_id: String, item_id: String) -> void:
	GameManager.shop_service.sell(shop_id, item_id, 1)

func _on_trade_completed(_shop_id: String, _item_id: String, _count: int, _is_buy: bool) -> void:
	refresh()

func _on_trade_failed(_shop_id: String, _item_id: String, reason: String) -> void:
	var msg: String = tr("ui_shop_no_money")
	match reason:
		"NO_ITEM": msg = tr("ui_shop_no_item")
		"NO_STOCK": msg = tr("ui_shop_no_stock")
	EventBus.notification_show.emit(msg)
	refresh()

func _on_money_changed(_silver: int, _copper: int, _gold: int) -> void:
	refresh()

func _exit_tree() -> void:
	if EventBus.notify_trade_completed.is_connected(_on_trade_completed):
		EventBus.notify_trade_completed.disconnect(_on_trade_completed)
	if EventBus.notify_trade_failed.is_connected(_on_trade_failed):
		EventBus.notify_trade_failed.disconnect(_on_trade_failed)
	if EventBus.player_money_changed.is_connected(_on_money_changed):
		EventBus.player_money_changed.disconnect(_on_money_changed)
