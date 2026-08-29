# scenes/gameplay/bond/WeddingScene.gd
# 婚礼演出场景（MVP）：展示新人与婚礼类型，提供「礼成」返回主城。
# 由 GameManager 监听 bond_wedding_started 后 change_scene_to_file 进入；
# 新人信息取自 GameManager.last_wedding（演出层持有，不依赖入参）。

extends Control
class_name WeddingScene

const UIPalette = preload("res://core/constants/ui_theme.gd")
const PathConstants = preload("res://core/constants/path_constants.gd")

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build()

func _build() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.03, 0.10, 1.0)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var center := VBoxContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(center)

	var w: Dictionary = GameManager.last_wedding if (GameManager.last_wedding is Dictionary) else {}
	var npc_id: String = String(w.get("npc_id", ""))
	var wt: int = int(w.get("wedding_type", 0))
	var npc = ConfigManager.get_relation(npc_id)
	var npc_name: String = npc.get("name", npc_id) if (npc != null and not npc.is_empty()) else npc_id

	var title := Label.new()
	title.text = "囍  婚  礼  囍"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 40)
	title.add_theme_color_override("font_color", UIPalette.GOLD)
	center.add_child(title)

	var sub := Label.new()
	sub.text = "主角 与 %s 的%s婚礼" % [npc_name, _wedding_type_name(wt)]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 22)
	center.add_child(sub)

	var done := Button.new()
	done.text = "礼成 · 返回主城"
	done.focus_mode = Control.FOCUS_NONE
	done.pressed.connect(_on_done)
	center.add_child(done)

func _wedding_type_name(wt: int) -> String:
	match wt:
		1: return "简"
		2: return "盛大"
		_: return "普通"

func _on_done() -> void:
	get_tree().change_scene_to_file(PathConstants.SCENE_TOWN)
