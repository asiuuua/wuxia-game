# scenes/ui/overlays/hud/top_right_menu_panel.gd
# HUD 右上角功能入口（v2 四面板之一）：「姻缘」按钮（可求婚时红点）+「菜单」按钮（打开分类主菜单）。
# 纯展示/入口层，红点轮询 GameManager.romance_service.get_marriageable_npc_ids()；
# 订阅 bond_relationship_changed 刷新。配色走 UIPalette，交互走 UIFeedback。

extends Control
class_name TopRightMenuPanel

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

var _bond_badge: Label

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()
	if is_instance_valid(EventBus):
		EventBus.bond_relationship_changed.connect(_refresh_badge)
	_refresh_badge()

# === 右上角按钮：姻缘（红点）+ 菜单 ===
func _build() -> void:
	var bond_btn := Button.new()
	bond_btn.text = "姻缘"
	bond_btn.focus_mode = Control.FOCUS_NONE
	bond_btn.anchor_left = 1.0
	bond_btn.anchor_right = 1.0
	bond_btn.anchor_top = 0.0
	bond_btn.anchor_bottom = 0.0
	bond_btn.offset_left = -178.0
	bond_btn.offset_right = -96.0
	bond_btn.offset_top = 12.0
	bond_btn.offset_bottom = 44.0
	bond_btn.pressed.connect(UIManager.open_screen.bind("BondRomance"))
	UIFeedback.attach(bond_btn)
	add_child(bond_btn)
	# 红点：存在可求婚 NPC 时点亮
	var badge := Label.new()
	badge.name = "RomanceBadge"
	badge.text = "●"
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	badge.anchor_left = 1.0
	badge.anchor_right = 1.0
	badge.anchor_top = 0.0
	badge.anchor_bottom = 0.0
	badge.offset_left = -16.0
	badge.offset_right = -2.0
	badge.offset_top = -10.0
	badge.offset_bottom = 4.0
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	badge.add_theme_color_override("font_color", UIPalette.BADGE_RED)
	badge.visible = false
	bond_btn.add_child(badge)
	_bond_badge = badge
	# 菜单按钮（打开分类主菜单）
	var menu_btn := Button.new()
	menu_btn.text = "菜单"
	menu_btn.focus_mode = Control.FOCUS_NONE
	menu_btn.anchor_left = 1.0
	menu_btn.anchor_right = 1.0
	menu_btn.anchor_top = 0.0
	menu_btn.anchor_bottom = 0.0
	menu_btn.offset_left = -92.0
	menu_btn.offset_right = -10.0
	menu_btn.offset_top = 12.0
	menu_btn.offset_bottom = 44.0
	menu_btn.pressed.connect(UIManager.open_screen.bind("GameMenu"))
	UIFeedback.attach(menu_btn)
	add_child(menu_btn)

func _exit_tree() -> void:
	if not is_instance_valid(EventBus):
		return
	if EventBus.bond_relationship_changed.is_connected(_refresh_badge):
		EventBus.bond_relationship_changed.disconnect(_refresh_badge)

# 姻缘红点：存在可求婚 NPC 时点亮右上角姻缘按钮
func _refresh_badge(_p: Variant = null) -> void:
	if _bond_badge == null:
		return
	if not is_instance_valid(GameManager) or GameManager.romance_service == null:
		_bond_badge.visible = false
		return
	var ids: Array = GameManager.romance_service.get_marriageable_npc_ids()
	_bond_badge.visible = not ids.is_empty()
