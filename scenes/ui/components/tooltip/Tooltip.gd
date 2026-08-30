@warning_ignore("shadowed_global_identifier")
extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

@onready var _panel: Panel = $Panel
@onready var _title: Label = $Panel/VBox/Title
@onready var _type: Label = $Panel/VBox/Type
@onready var _desc: Label = $Panel/VBox/Desc

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
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
		"uncommon": return UIPalette.RARITY_UNCOMMON
		"rare": return UIPalette.RARITY_RARE
		"epic": return UIPalette.RARITY_EPIC
		"legendary": return UIPalette.RARITY_LEGENDARY
	return UIPalette.GOLD

func hide_tip() -> void:
	visible = false
