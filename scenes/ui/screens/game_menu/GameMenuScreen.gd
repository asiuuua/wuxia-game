# scenes/ui/screens/game_menu/GameMenuScreen.gd
# 进入游戏后的分类主功能菜单（"江湖"）：把现有子系统按品类归类，点击进入对应屏幕。
# 设计：全屏遮罩 + 居中玻璃面板，四大类（人物 / 江湖 / 技艺·生产 / 系统）各一组按钮网格。
# 纯展示与导航：数据来自各业务服务的公开方法，跨模块只经 UIManager.open_screen；
# 姻缘条目带"可求婚"红点，消费 EventBus.bond_relationship_changed 实时刷新。

extends Control
class_name GameMenuScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

# 分类目录（screen 名对应 data/configs/ui/screens.json 的注册键）
const _CATEGORIES := [
	{
		"title": "人 物",
		"items": [
			{"name": "属性", "screen": "AttributesScreen"},
			{"name": "背包", "screen": "InventoryScreen"},
			{"name": "装备", "screen": "EquipmentScreen"},
		],
	},
	{
		"title": "江 湖",
		"items": [
			{"name": "姻缘 · 情缘录", "screen": "BondRomance", "badge": true},
			{"name": "门派", "screen": "SectScreen"},
			{"name": "江湖地图", "screen": "MapScreen"},
		],
	},
	{
		"title": "技 艺 · 生 产",
		"items": [
			{"name": "江湖技艺", "screen": "AbilitiesScreen"},
			{"name": "锻造", "screen": "ForgeScreen"},
			{"name": "炼药", "screen": "AlchemyScreen"},
			{"name": "商铺", "screen": "ShopScreen"},
		],
	},
	{
		"title": "系 统",
		"items": [
			{"name": "设置", "screen": "SettingsScreen"},
			{"name": "存档", "screen": "SaveLoadScreen"},
		],
	},
]

var _romance_badge: Label

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	UIManager.apply_safe_area(self)
	_build()
	if not EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.connect(_on_relationship_changed)
	_refresh_romance_badge()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.size = Vector2(760, 540)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_color = UIPalette.GLASS_BORDER
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var title := Label.new()
	title.text = "江 湖"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UIPalette.GOLD)
	title.add_theme_font_size_override("font_size", UIPalette.FS_HEADER)
	v.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	for cat in _CATEGORIES:
		content.add_child(_build_category(cat))
	var close := Button.new()
	close.text = "返回"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(UIManager.close_screen.bind(self))
	UIFeedback.attach(close)
	v.add_child(close)

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
	b.pressed.connect(_open.bind(screen_name))
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

func _open(screen_name: String) -> void:
	UIManager.open_screen(screen_name, UIManager.Layer.FULLSCREEN)
	UIManager.close_screen(self)

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
