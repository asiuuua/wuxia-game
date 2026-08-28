# scenes/ui/screens/equipment/EquipmentScreen.gd
# 装备界面（Phase 2，纯代码构建）：展示三槽位与背包可装备物品，支持装卸
# 铁律：UI 只做展示与输入，业务逻辑调用 GameManager / EquipmentService

extends Control
class_name EquipmentScreen

var _slot_labels: Dictionary = {}
var _inv_list: VBoxContainer
var _stat_label: Label

func _ready() -> void:
	_build_ui()
	refresh()
	EventBus.equipment_changed.connect(_on_equipment_changed)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var title := Label.new()
	title.text = tr("ui_equip_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	_stat_label = Label.new()
	root.add_child(_stat_label)
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
		root.add_child(h)
	var inv_title := Label.new()
	inv_title.text = tr("ui_equip_bag")
	root.add_child(inv_title)
	_inv_list = VBoxContainer.new()
	root.add_child(_inv_list)
	var close := Button.new()
	close.text = tr("ui_equip_close")
	close.pressed.connect(UIManager.close_screen.bind(self))
	root.add_child(close)

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
	GameManager.equipment_service.equip(instance_id)
	refresh()

func _on_equipment_changed() -> void:
	refresh()

func _exit_tree() -> void:
	if EventBus.equipment_changed.is_connected(_on_equipment_changed):
		EventBus.equipment_changed.disconnect(_on_equipment_changed)
