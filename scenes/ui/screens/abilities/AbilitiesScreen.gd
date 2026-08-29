# scenes/ui/screens/abilities/AbilitiesScreen.gd
# 江湖技艺（已学武学）面板：列出玩家习得的武学，展示名称/描述/内力消耗/修炼等级。
# 数据来自 GameManager.ability_service.learned + ConfigManager.get_ability；纯展示，不修改业务。

extends Control
class_name AbilitiesScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

var _content: VBoxContainer

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	UIManager.apply_safe_area(self)
	_build()
	_refresh()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	panel.size = Vector2(720, 540)
	UICenterUtils.center_panel(panel)   # 修复 Godot4.7.2 PRESET_CENTER 不居中
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
	title.text = "江 湖 技 艺"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_color", UIPalette.GOLD)
	title.add_theme_font_size_override("font_size", UIPalette.FS_HEADER)
	v.add_child(title)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content.add_theme_constant_override("separation", 10)
	scroll.add_child(_content)
	var close := Button.new()
	close.text = "关闭"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(UIManager.close_screen.bind(self))
	UIFeedback.attach(close)
	v.add_child(close)

func _refresh() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	var asvc = GameManager.ability_service
	if asvc == null:
		return
	var ids: Array = asvc.learned.keys()
	if ids.is_empty():
		var note := Label.new()
		note.text = "尚未习得任何武学。可前往「门派」拜师学艺，或完成奇遇机缘。"
		note.add_theme_color_override("font_color", UIPalette.DISABLED)
		note.add_theme_font_size_override("font_size", UIPalette.FS_BODY)
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_content.add_child(note)
		return
	for id in ids:
		_content.add_child(_build_ability_row(String(id), int(asvc.learned.get(id, 1))))

func _build_ability_row(id: String, level: int) -> Control:
	var data: Dictionary = ConfigManager.get_ability(id)
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 2)
	row.add_theme_constant_override("margin_bottom", 6)
	var head := HBoxContainer.new()
	# 技能图标：美术按 ability id 丢 resources/icons/skills/<id>.png 即可替换
	var icon := TextureRect.new()
	icon.texture = UIManager.get_icon("skills/" + id)
	icon.custom_minimum_size = Vector2(40, 40)
	icon.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var name_l := Label.new()
	name_l.text = String(data.get("name", id))
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	name_l.add_theme_font_size_override("font_size", UIPalette.FS_NAME)
	head.add_child(name_l)
	var lvl_l := Label.new()
	lvl_l.text = "修炼 %d 重" % level
	lvl_l.add_theme_color_override("font_color", UIPalette.GOLD)
	lvl_l.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
	head.add_child(lvl_l)
	var cost: int = int(data.get("mp_cost", 0))
	if cost > 0:
		var cost_l := Label.new()
		cost_l.text = "内力 %d" % cost
		cost_l.add_theme_color_override("font_color", UIPalette.MP_FILL)
		cost_l.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
		head.add_child(cost_l)
	row.add_child(head)
	var desc := Label.new()
	desc.text = String(data.get("desc", "（无描述）"))
	desc.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	desc.add_theme_font_size_override("font_size", UIPalette.FS_SUB)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.add_child(desc)
	return row
