# scenes/ui/screens/abilities/AbilitiesScreen.gd
# 江湖技艺（已学武学）面板：列出玩家习得的武学，展示名称/描述/内力消耗/修炼等级。
# 数据来自 GameManager.ability_service.learned + ConfigManager.get_ability；纯展示，不修改业务。
# B 路线：静态壳（压暗底 + 居中玻璃面板 + 标题/滚动列表/关闭）在 AbilitiesScreen.tscn，
# 美术可在编辑器直接编辑布局与外观；本脚本只负责动态行填充与交互。

extends PopupBase
class_name AbilitiesScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

@onready var _title: Label = $Panel/Margin/VLayout/Title
@onready var _content: VBoxContainer = $Panel/Margin/VLayout/BodyAnchor/List
@onready var _close: Button = $Panel/Margin/VLayout/Close

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	UIManager.apply_safe_area(self)
	popup_id = "Abilities"
	_build_ui()
	_refresh()

func _build_ui() -> void:
	_title.add_theme_color_override("font_color", UIPalette.GOLD)
	_title.add_theme_font_size_override("font_size", UIPalette.FS_HEADER)
	_close.text = "关闭"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(request_close)
	UIFeedback.attach(_close)

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

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后渲染已学武学（规避 GameManager）
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_title = $Panel/Margin/VLayout/Title
	_content = $Panel/Margin/VLayout/BodyAnchor/List
	_close = $Panel/Margin/VLayout/Close
	if _title == null or _content == null:
		return
	_title.add_theme_color_override("font_color", UIPalette.GOLD)
	_title.add_theme_font_size_override("font_size", UIPalette.FS_HEADER)
	_title.text = "江湖技艺"
	_close.text = "关闭"
	for c in _content.get_children():
		c.queue_free()
	var ids: Array = []
	if ConfigManager.has_method("get_all_ability_ids"):
		ids = ConfigManager.get_all_ability_ids()
	if ids.is_empty():
		ids = ["basic_sword", "qinggong", "inner_force", "sword_21"]
	for i in mini(ids.size(), 4):
		_content.add_child(_build_ability_row(String(ids[i]), 1 + i))
