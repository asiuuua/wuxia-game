# scenes/ui/screens/equipment/EquipmentScreen.gd
# 装备界面（Phase 2，纯代码构建）：展示三槽位与背包可装备物品，支持装卸
# 铁律：UI 只做展示与输入，业务逻辑调用 GameManager / EquipmentService

extends PopupBase
class_name EquipmentScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")

var _slot_labels: Dictionary = {}
var _inv_list: VBoxContainer
var _stat_label: Label

func _ready() -> void:
	popup_id = "EquipmentScreen"
	_build_ui()
	refresh()
	EventBus.equipment_changed.connect(_on_equipment_changed)

func _build_ui() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := make_glass_panel(Vector2(560, 560))
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	margin.add_child(v)
	var title := Label.new()
	title.text = tr("ui_equip_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_stat_label = Label.new()
	v.add_child(_stat_label)
	for slot in EquipmentService.ALL_SLOTS:
		var h := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = _slot_name(slot) + "："
		name_l.custom_minimum_size = Vector2(80, 0)
		var item_l := Label.new()
		item_l.name = "ItemLabel"
		h.add_child(name_l)
		h.add_child(item_l)
		_slot_labels[slot] = item_l
		v.add_child(h)
	var inv_title := Label.new()
	inv_title.text = tr("ui_equip_bag")
	v.add_child(inv_title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_inv_list = VBoxContainer.new()
	_inv_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_inv_list)
	var close := Button.new()
	close.text = tr("ui_equip_close")
	close.pressed.connect(request_close)
	v.add_child(close)

func _slot_name(slot: String) -> String:
	match slot:
		"main_hand": return tr("ui_equip_main_hand")
		"armor": return tr("ui_equip_armor")
		"accessory": return tr("ui_equip_accessory")
		_: return slot

func refresh() -> void:
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		_stat_label.text = tr("ui_equip_stat") % [
			ps.attack, ps.defense, ps.hp, ps.max_hp, ps.mp, ps.max_mp]
	for slot in _slot_labels:
		var item_id: String = GameManager.equipment_service.get_equipped(slot)
		var txt: String = "空"
		if item_id != "":
			txt = ConfigManager.get_item(item_id).get("name", item_id)
		_slot_labels[slot].text = txt
	for child in _inv_list.get_children():
		child.queue_free()
	var items: Array = GameManager.inventory_service.get_equippable_instances()
	if items.is_empty():
		var empty := Label.new()
		empty.text = tr("ui_equip_none")
		_inv_list.add_child(empty)
	for i in items.size():
		var inst: ItemInstance = items[i]
		var data: Dictionary = ConfigManager.get_item(inst.item_id)
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = data.get("name", inst.item_id)
		l.custom_minimum_size = Vector2(120, 0)
		var btn := Button.new()
		btn.text = tr("ui_equip_equip")
		btn.pressed.connect(_on_equip_pressed.bind(inst.instance_id))
		h.add_child(l)
		h.add_child(btn)
		_inv_list.add_child(h)

func _on_equip_pressed(instance_id: String) -> void:
	# equip() 内部已 emit EventBus.equipment_changed → _on_equipment_changed → refresh()，
	# 故此处不再显式 refresh()，避免双重刷新（非幂等、浪费一帧重建列表）。
	GameManager.equipment_service.equip(instance_id)

func _on_equipment_changed() -> void:
	refresh()

func _exit_tree() -> void:
	if EventBus.equipment_changed.is_connected(_on_equipment_changed):
		EventBus.equipment_changed.disconnect(_on_equipment_changed)
