# scenes/ui/screens/game_menu/GameMenuScreen.gd
# 进入游戏后的分类主功能菜单（"江湖"）：把现有子系统按品类归类，点击进入对应屏幕。
# 设计：全屏遮罩 + 居中玻璃面板，四大类（人物 / 江湖 / 技艺·生产 / 系统）各一组按钮网格。
# 纯展示与导航：数据来自各业务服务的公开方法，跨模块只经 UIManager.open_screen；
# 姻缘条目带"可求婚"红点，消费 EventBus.bond_relationship_changed 实时刷新。
# B 路线：静态壳在 GameMenuScreen.tscn，脚本只填动态内容。

extends PopupBase
class_name GameMenuScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

# 菜单清单改为数据驱动：data/configs/ui/menu_config.json（action_id → screen/badge/icon_id），
# GameMenuScreen 读配置建按钮、按钮只 emit ui_action_requested，零硬编码跳转、加菜单零代码改动。

@onready var _title: Label = $Panel/Margin/VLayout/Title
@onready var _content: VBoxContainer = $Panel/Margin/VLayout/BodyAnchor/Content
@onready var _close: Button = $Panel/Margin/VLayout/Close

var _romance_badge: Label

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	UIManager.apply_safe_area(self)
	popup_id = "GameMenu"
	_build_ui()
	if not EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.connect(_on_relationship_changed)
	_refresh_romance_badge()

func _build_ui() -> void:
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_color_override("font_color", UIPalette.GOLD)
	_title.add_theme_font_size_override("font_size", UIPalette.FS_HEADER)
	_close.text = "返回"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(request_close)
	UIFeedback.attach(_close)
	for cat in ConfigManager.get_menu_config().get("categories", []):
		_content.add_child(_build_category(cat))

func _build_category(cat: Dictionary) -> Control:
	var block := VBoxContainer.new()
	block.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	block.add_theme_constant_override("separation", 8)
	var head := Label.new()
	head.text = cat.get("title", "")
	head.add_theme_color_override("font_color", UIPalette.GOLD)
	head.add_theme_font_size_override("font_size", UIPalette.FS_MENU)
	block.add_child(head)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 12)
	for item in cat.get("items", []):
		grid.add_child(_build_item(item))
	block.add_child(grid)
	return block

func _build_item(item: Dictionary) -> Control:
	var screen_name: String = String(item.get("screen", ""))
	var b := Button.new()
	b.text = item.get("name", screen_name)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(210, 50)
	UIFeedback.attach(b)
	var icon_id: String = String(item.get("icon_id", ""))
	if icon_id != "" and UIManager.has_icon(icon_id):
		b.icon = UIManager.get_icon(icon_id)
	b.pressed.connect(func(): EventBus.ui_action_requested.emit(String(item.get("action_id", ""))))
	if bool(item.get("badge", false)):
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
		b.add_child(badge)
		_romance_badge = badge
	return b

func _on_relationship_changed() -> void:
	_refresh_romance_badge()

func _refresh_romance_badge() -> void:
	if _romance_badge == null or GameManager.romance_service == null:
		return
	var ids: Array = GameManager.romance_service.get_marriageable_npc_ids()
	_romance_badge.visible = not ids.is_empty()

func _exit_tree() -> void:
	if EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.disconnect(_on_relationship_changed)
