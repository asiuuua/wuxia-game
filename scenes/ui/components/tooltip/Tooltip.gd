@warning_ignore("shadowed_global_identifier")
extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

var _panel: Panel
var _title: Label
var _type: Label
var _desc: Label

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build()

func _build() -> void:
	_panel = Panel.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GLASS_BORDER
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.shadow_size = 12
	sb.shadow_offset = Vector2(0, 4)
	sb.shadow_color = UIPalette.GLASS_SHADOW
	_panel.add_theme_stylebox_override("panel", sb)
	add_child(_panel)
	var v := VBoxContainer.new()
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.add_theme_constant_override("separation", 4)
	v.add_theme_constant_override("margin_left", 12)
	v.add_theme_constant_override("margin_top", 10)
	v.add_theme_constant_override("margin_right", 12)
	v.add_theme_constant_override("margin_bottom", 10)
	_panel.add_child(v)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 16)
	_title.add_theme_color_override("font_color", UIPalette.GOLD)
	v.add_child(_title)
	_type = Label.new()
	_type.add_theme_font_size_override("font_size", 12)
	_type.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	v.add_child(_type)
	_desc = Label.new()
	_desc.add_theme_font_size_override("font_size", 13)
	_desc.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(_desc)
	visible = false

## 显示某物品浮窗；global_pos 为触发位置的屏幕坐标
func show_for(item_id: String, global_pos: Vector2) -> void:
	var data: Dictionary = ConfigManager.get_item(item_id)
	if data.is_empty():
		return
	_title.text = data.get("name", item_id)
	_title.add_theme_color_override("font_color", _rarity_color(data.get("rarity", "common")))
	var t: String = data.get("type", "")
	var r: String = data.get("rarity", "")
	_type.text = "类型：%s　稀有度：%s" % [t, r]
	var desc: String = data.get("desc", "")
	_desc.text = desc if desc != "" else "（暂无描述）"
	visible = true
	await get_tree().process_frame
	var sz: Vector2 = size
	var vp: Vector2 = get_viewport_rect().size
	position = Vector2(
		mini(maxi(0, global_pos.x + 16), vp.x - sz.x - 8),
		mini(maxi(0, global_pos.y + 16), vp.y - sz.y - 8)
	)

func _rarity_color(r: String) -> Color:
	match r:
		"uncommon": return Color(0.30, 0.80, 0.40)
		"rare": return Color(0.35, 0.65, 0.95)
		"epic": return Color(0.70, 0.45, 0.95)
		"legendary": return Color(0.95, 0.70, 0.25)
	return UIPalette.GOLD

func hide_tip() -> void:
	visible = false
