# scenes/ui/overlays/hud/Hud.gd
# 抬头显示：玩家状态 + 当前追踪任务（规范 §9 叠加层）
# 纯展示：订阅 EventBus 刷新，不修改业务数据

extends Control
class_name Hud

const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

var _info_label: Label
var _quest_label: Label
var _bond_btn: Button
var _bond_badge: Label

func _ready() -> void:
	_build()
	EventBus.player_hp_changed.connect(_refresh)
	EventBus.player_mp_changed.connect(_refresh)
	EventBus.player_level_up.connect(_refresh)
	EventBus.player_exp_changed.connect(_refresh)
	EventBus.quest_accepted.connect(_refresh)
	EventBus.quest_objective_updated.connect(_refresh)
	EventBus.quest_turned_in.connect(_refresh)
	EventBus.bond_relationship_changed.connect(_refresh)
	_refresh()

func _build() -> void:
	var panel := Panel.new()
	panel.position = Vector2(10, 10)
	panel.size = Vector2(300, 130)
	add_child(panel)
	_info_label = Label.new()
	_info_label.position = Vector2(12, 8)
	_info_label.size = Vector2(280, 60)
	panel.add_child(_info_label)
	_quest_label = Label.new()
	_quest_label.position = Vector2(12, 70)
	_quest_label.size = Vector2(280, 55)
	panel.add_child(_quest_label)
	# 键位提示条：让玩家快速知晓操作方式（布局合理化的一部分）
	var hint := Label.new()
	hint.position = Vector2(10, 150)
	hint.size = Vector2(420, 24)
	hint.text = tr("ui_hud_hint")
	add_child(hint)
	# 姻缘按钮（右上角，固定锚点避免窗口缩放错位）
	var bond_btn := Button.new()
	bond_btn.text = "姻缘"
	bond_btn.focus_mode = Control.FOCUS_NONE
	bond_btn.anchor_left = 1.0
	bond_btn.anchor_right = 1.0
	bond_btn.anchor_top = 0.0
	bond_btn.anchor_bottom = 0.0
	bond_btn.offset_left = -92.0
	bond_btn.offset_right = -10.0
	bond_btn.offset_top = 10.0
	bond_btn.offset_bottom = 42.0
	bond_btn.pressed.connect(UIManager.open_screen.bind("BondRomance"))
	UIFeedback.attach(bond_btn)
	add_child(bond_btn)
	_bond_btn = bond_btn
	# 红点：存在可求婚 NPC 时点亮（实时，监听 bond_relationship_changed 经 _refresh 刷新）
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
	badge.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2, 1.0))
	badge.visible = false
	bond_btn.add_child(badge)
	_bond_badge = badge

func _refresh(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	var ps: PlayerState = GameManager.player_state
	if ps == null:
		return
	_info_label.text = "%s\n%s\n%s" % [
		tr("ui_hud_line1") % [ps.level, ps.player_name],
		tr("ui_hud_line2") % [ps.hp, ps.max_hp, ps.mp, ps.max_mp],
		tr("ui_hud_line3") % [ps.silver]]
	var tracked: Array[QuestState] = GameManager.quest_service.get_tracked()
	if tracked.is_empty():
		_quest_label.text = tr("ui_hud_no_quest")
	else:
		var q: QuestState = tracked[0]
		var data: Dictionary = ConfigManager.get_quest(q.quest_id)
		var txt: String = tr("ui_hud_quest") % data.get("name", "") + "\n"
		for obj in data.get("objectives", []):
			txt += (tr("ui_hud_objective") % [obj.get("desc", ""), q.get_objective_progress(obj["id"]), obj.get("need", 1)]) + "\n"
		_quest_label.text = txt
	_refresh_romance_badge()

# 姻缘红点：存在可求婚 NPC 时点亮右上角姻缘按钮
func _refresh_romance_badge() -> void:
	if _bond_badge == null or GameManager.romance_service == null:
		return
	var ids: Array = GameManager.romance_service.get_marriageable_npc_ids()
	_bond_badge.visible = not ids.is_empty()
