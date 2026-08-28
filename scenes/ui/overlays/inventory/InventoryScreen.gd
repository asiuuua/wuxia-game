# scenes/ui/overlays/inventory/InventoryScreen.gd
# 背包面板（B 键开关）：主背包 / 材料箱 / 任务栏 三栏分类展示，含负重
# 铁律：UI 只展示与输入，数据来自 GameManager.inventory_service / ConfigManager

@warning_ignore("shadowed_global_identifier")
extends Control

class_name InventoryScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")

var _weight_label: Label
var _list: VBoxContainer

func _ready() -> void:
	# 面板自身不抢键盘焦点，确保 B 键能穿透到场景层关闭本面板
	focus_mode = Control.FOCUS_NONE
	_build()
	_refresh()
	EventBus.inventory_item_added.connect(_on_inv_changed)
	EventBus.inventory_item_removed.connect(_on_inv_changed)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	panel.size = Vector2(580, 480)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var title := Label.new()
	title.text = tr("ui_inventory_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_weight_label = Label.new()
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_weight_label)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var close := Button.new()
	close.text = tr("ui_inventory_close")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(UIManager.close_screen.bind(self))
	v.add_child(close)

func _refresh() -> void:
	if _weight_label == null:
		return
	for child in _list.get_children():
		child.queue_free()
	var inv: InventoryService = GameManager.inventory_service
	_weight_label.text = tr("ui_inventory_weight") % [inv.get_weight(), InventoryService.BASE_MAX_WEIGHT]
	_add_section(tr("ui_inventory_main"), inv.main_slots)
	_add_section(tr("ui_inventory_material"), inv.material_slots)
	_add_section(tr("ui_inventory_quest"), inv.quest_slots)

func _add_section(title_text: String, bag: Array) -> void:
	# 按 item_id 聚合（保留 id 以便定位实例与判断消耗品），显示用配置名
	var items := {}   # item_id -> { "name": String, "count": int }
	for inst in bag:
		if inst == null:
			continue
		var data: Dictionary = ConfigManager.get_item(inst.item_id)
		var nm: String = data.get("name", inst.item_id)
		if not items.has(inst.item_id):
			items[inst.item_id] = { "name": nm, "count": 0 }
		var entry: Dictionary = items[inst.item_id]
		entry["count"] = int(entry["count"]) + inst.count
	if items.is_empty():
		return
	var head := Label.new()
	head.text = "[%s]" % title_text
	_list.add_child(head)
	for item_id in items:
		var info: Dictionary = items[item_id]
		var row := HBoxContainer.new()
		var l := Label.new()
		l.text = "  %s  x%d" % [info["name"], info["count"]]
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(l)
		# 消耗品：提供城镇内使用入口（战斗内用药走 BattleScene 物品菜单）
		if _is_consumable(item_id):
			var use := Button.new()
			use.text = "使用"
			use.focus_mode = Control.FOCUS_NONE
			use.pressed.connect(_on_use_pressed.bind(item_id))
			row.add_child(use)
		_list.add_child(row)

## 是否消耗品：pill 类型或 flags 含 CONSUMABLE（与 use_item 校验保持一致）
func _is_consumable(item_id: String) -> bool:
	var data: Dictionary = ConfigManager.get_item(item_id)
	if data.is_empty():
		return false
	return data.get("type", "") == "pill" \
			or (int(data.get("flags", 0)) & ItemEnums.ItemFlag.CONSUMABLE) != 0

## 城镇内用药：取该物品第一个可用实例交给 use_item
## （结算走 PlayerState.heal/restore_mp，扣件后的 removed 事件会触发本面板刷新）
func _on_use_pressed(item_id: String) -> void:
	var inv: InventoryService = GameManager.inventory_service
	if inv == null:
		return
	for bag in [inv.main_slots, inv.material_slots, inv.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				inv.use_item(inst.instance_id, "town")
				return

func _on_inv_changed(_p: Variant = null) -> void:
	_refresh()

func _exit_tree() -> void:
	if EventBus.inventory_item_added.is_connected(_on_inv_changed):
		EventBus.inventory_item_added.disconnect(_on_inv_changed)
	if EventBus.inventory_item_removed.is_connected(_on_inv_changed):
		EventBus.inventory_item_removed.disconnect(_on_inv_changed)
