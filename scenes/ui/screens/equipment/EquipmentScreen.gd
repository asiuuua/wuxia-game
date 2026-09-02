@tool
# scenes/ui/screens/equipment/EquipmentScreen.gd
# 装备界面（B 路线：静态壳在 EquipmentScreen.tscn，脚本只填动态内容）
# 铁律：UI 只做展示与输入，业务逻辑调用 GameManager / EquipmentService

extends PopupBase
class_name EquipmentScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")

@onready var _title: Label = $Panel/Margin/VLayout/Title
@onready var _stat_label: Label = $Panel/Margin/VLayout/StatLabel
@onready var _slots: VBoxContainer = $Panel/Margin/VLayout/Slots
@onready var _inv_list: VBoxContainer = $Panel/Margin/VLayout/BodyAnchor/List
@onready var _close: Button = $Panel/Margin/VLayout/Close

var _slot_labels: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	popup_id = "EquipmentScreen"
	_build_ui()
	refresh()
	EventBus.equipment_changed.connect(_on_equipment_changed)
	enable_responsive($Panel, Vector2(560, 560))

func _build_ui() -> void:
	_title.text = tr("ui_equip_title")
	_close.text = tr("ui_equip_close")
	_close.pressed.connect(request_close)
	_build_slots()

func _build_slots() -> void:
	for child in _slots.get_children():
		child.queue_free()
	_slot_labels.clear()
	for slot in EquipmentService.ALL_SLOTS:
		var h := HBoxContainer.new()
		var name_l := Label.new()
		name_l.text = _slot_name(slot) + "："
		name_l.custom_minimum_size = Vector2(80, 0)
		var item_l := Label.new()
		item_l.name = "ItemLabel"
		h.add_child(name_l)
		h.add_child(item_l)
		_slots.add_child(h)
		_slot_labels[slot] = item_l

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

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后填充示例装备（规避 GameManager）
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_title = $Panel/Margin/VLayout/Title
	_stat_label = $Panel/Margin/VLayout/StatLabel
	_slots = $Panel/Margin/VLayout/Slots
	_inv_list = $Panel/Margin/VLayout/BodyAnchor/List
	_close = $Panel/Margin/VLayout/Close
	if _title == null or _slots == null:
		return
	_title.text = tr("ui_equip_title")
	_close.text = tr("ui_equip_close")
	_build_slots()
	_stat_label.text = tr("ui_equip_stat") % [156, 98, 920, 1180, 340, 760]
	var mock := {"main_hand": "精钢长剑", "armor": "玄铁护甲", "accessory": "空"}
	for slot in _slot_labels:
		_slot_labels[slot].text = mock.get(slot, "空")
	for child in _inv_list.get_children():
		child.queue_free()
	var sample := ["精钢长剑", "玄铁护甲", "轻身靴", "回春丹"]
	for nm in sample:
		var h := HBoxContainer.new()
		var l := Label.new()
		l.text = nm
		l.custom_minimum_size = Vector2(120, 0)
		var btn := Button.new()
		btn.text = tr("ui_equip_equip")
		h.add_child(l)
		h.add_child(btn)
		_inv_list.add_child(h)
