@tool
@warning_ignore("shadowed_global_identifier")
extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

signal slot_pressed(iid: String)
signal slot_context(iid: String)
signal slot_hover(iid: String)
signal slot_drop(iid: String, data: Dictionary)

const SIZE := 64

# B 路线：节点结构（_bg/_icon/_label/_badge/_lock_icon）已迁入 ItemSlot.tscn，
# 美术可在编辑器直接编辑布局与外观；本脚本只负责状态、交互与数据填充。
@onready var _bg: Panel = $_bg
@onready var _icon: TextureRect = $_icon
@onready var _label: Label = $_label
@onready var _badge: Label = $_badge
@onready var _lock_icon: Label = $_lock_icon

var _iid: String = ""

func _ready() -> void:
	custom_minimum_size = Vector2(SIZE, SIZE)
	size = Vector2(SIZE, SIZE)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_configure_static()
	_apply_bg(false)
	mouse_entered.connect(func(): slot_hover.emit(_iid))
	mouse_exited.connect(func(): slot_hover.emit(""))

# 结构来自 .tscn，这里只补静态外观（对齐/字号/描边/角标位置），状态色在 setup() 内按数据刷新
func _configure_static() -> void:
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.custom_minimum_size = Vector2(SIZE - 14, SIZE - 14)
	_icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.add_theme_font_size_override("font_size", 11)
	_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 1))
	_label.add_theme_constant_override("outline_size", 2)
	_badge.position = Vector2(SIZE - 32, 2)
	_badge.add_theme_font_size_override("font_size", 13)
	_badge.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_lock_icon.text = "锁"
	_lock_icon.position = Vector2(2, 2)
	_lock_icon.add_theme_font_size_override("font_size", 12)
	_lock_icon.add_theme_color_override("font_color", UIPalette.GOLD)
	_lock_icon.visible = false

## 填充一个物品实例（inst 为 ItemInstance；传 null 表示空槽）
func setup(inst) -> void:
	if _label == null:
		return  # 安全网：实例化后未进树时跳过
	if inst == null:
		_iid = ""
		_label.text = ""
		_icon.texture = null
		_badge.text = ""
		_lock_icon.visible = false
		_apply_bg(false)
		return
	_iid = inst.instance_id
	_icon.texture = UIManager.get_icon("items/" + inst.item_id)
	var data: Dictionary = ConfigManager.get_item(inst.item_id)
	var nm: String = data.get("name", inst.item_id)
	_label.text = nm
	_label.add_theme_color_override("font_color", _rarity_color(data.get("rarity", "common")))
	_badge.text = "" if int(inst.count) <= 1 else "x%d" % int(inst.count)
	_lock_icon.visible = bool(inst.locked)
	_apply_bg(false)

func _rarity_color(r: String) -> Color:
	match r:
		"uncommon": return Color(0.30, 0.80, 0.40)
		"rare": return Color(0.35, 0.65, 0.95)
		"epic": return Color(0.70, 0.45, 0.95)
		"legendary": return Color(0.95, 0.70, 0.25)
	return UIPalette.TEXT_MAIN

func _apply_bg(selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GLASS_BORDER if not selected else UIPalette.GLASS_BORDER_FOCUS
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left = 2
	sb.content_margin_right = 2
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2
	_bg.add_theme_stylebox_override("panel", sb)

func get_iid() -> String:
	return _iid

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			slot_pressed.emit(_iid)
			accept_event()
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_RIGHT:
			slot_context.emit(_iid)
			accept_event()

func _get_drag_data(_pos: Vector2) -> Variant:
	if _iid == "":
		return null
	var preview := Panel.new()
	preview.custom_minimum_size = Vector2(SIZE, SIZE)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG_HOVER
	sb.border_color = UIPalette.GLASS_BORDER_FOCUS
	sb.corner_radius_top_left = 6
	sb.corner_radius_top_right = 6
	sb.corner_radius_bottom_left = 6
	sb.corner_radius_bottom_right = 6
	preview.add_theme_stylebox_override("panel", sb)
	var pv := Label.new()
	pv.text = _label.text
	UICenterUtils.center_panel(pv)   # 修复 Godot4.7.2 PRESET_CENTER 不居中（拖拽预览内文字居中）
	preview.add_child(pv)
	set_drag_preview(preview)
	return { "iid": _iid }

func _can_drop_data(_pos: Vector2, data: Variant) -> bool:
	return typeof(data) == TYPE_DICTIONARY and data.has("iid")

func _drop_data(_pos: Vector2, data: Variant) -> void:
	if typeof(data) == TYPE_DICTIONARY and data.has("iid"):
		slot_drop.emit(_iid, data)
