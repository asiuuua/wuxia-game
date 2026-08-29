# scenes/ui/overlays/attributes/AttributesScreen.gd
# 人物属性面板（Tab 键开关）：基础信息 + 经验/气血/内力进度条 + 属性总览
# 铁律：UI 只展示与输入，数据来自 GameManager.player_state

@warning_ignore("shadowed_global_identifier")
extends PopupBase

class_name AttributesScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")

var _info_label: Label
var _exp_bar: ProgressBar
var _hp_bar: ProgressBar
var _mp_bar: ProgressBar
var _attr_grid: GridContainer

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	popup_id = "Attributes"
	_build()
	_refresh()
	EventBus.player_stats_changed.connect(_on_changed)
	EventBus.player_hp_changed.connect(_on_changed)
	EventBus.player_mp_changed.connect(_on_changed)
	EventBus.player_level_up.connect(_on_changed)
	EventBus.player_money_changed.connect(_on_changed)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := make_glass_panel(Vector2(520, 560))
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var title := Label.new()
	title.text = tr("ui_attr_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	_info_label = Label.new()
	v.add_child(_info_label)
	_exp_bar = ProgressBar.new()
	_exp_bar.max_value = 1.0
	_exp_bar.show_percentage = false
	v.add_child(_exp_bar)
	_hp_bar = ProgressBar.new()
	_hp_bar.max_value = 1.0
	_hp_bar.show_percentage = false
	v.add_child(_hp_bar)
	_mp_bar = ProgressBar.new()
	_mp_bar.max_value = 1.0
	_mp_bar.show_percentage = false
	v.add_child(_mp_bar)
	var attr_title := Label.new()
	attr_title.text = tr("ui_attr_overview")
	v.add_child(attr_title)
	_attr_grid = GridContainer.new()
	_attr_grid.columns = 2
	_attr_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_attr_grid)
	var close := Button.new()
	close.text = tr("ui_attr_close")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(request_close)
	v.add_child(close)

func _refresh() -> void:
	if _info_label == null:
		return
	var ps: PlayerState = GameManager.player_state
	if ps == null:
		return
	_info_label.text = tr("ui_attr_info") % [ps.player_name, ps.level, ps.age]
	_exp_bar.value = float(ps.experience) / float(ps.exp_to_next) if ps.exp_to_next > 0 else 0.0
	_hp_bar.value = ps.get_hp_percent()
	_mp_bar.value = float(ps.mp) / float(ps.max_mp) if ps.max_mp > 0 else 0.0
	for c in _attr_grid.get_children():
		c.queue_free()
	var rows := [
		["ui_attr_hp", "%d / %d" % [ps.hp, ps.max_hp]],
		["ui_attr_mp", "%d / %d" % [ps.mp, ps.max_mp]],
		["ui_attr_atk", str(ps.attack)],
		["ui_attr_def", str(ps.defense)],
		["ui_attr_crit", "%.1f%%" % (ps.crit_rate * 100)],
		["ui_attr_dodge", "%.1f%%" % (ps.dodge_rate * 100)],
		["ui_attr_str", str(ps.strength)],
		["ui_attr_con", str(ps.constitution)],
		["ui_attr_agi", str(ps.agility)],
		["ui_attr_wis", str(ps.wisdom)],
		["ui_attr_luck", str(ps.luck)],
		["ui_attr_focus", str(ps.focus)],
		["ui_attr_silver", str(ps.silver)],
	]
	for pair in rows:
		var row := HBoxContainer.new()
		var k := Label.new()
		k.text = tr(pair[0])
		k.custom_minimum_size = Vector2(70, 0)
		k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var val := Label.new()
		val.text = pair[1]
		val.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(k)
		row.add_child(val)
		_attr_grid.add_child(row)

func _on_changed(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	_refresh()

func _exit_tree() -> void:
	if EventBus.player_stats_changed.is_connected(_on_changed):
		EventBus.player_stats_changed.disconnect(_on_changed)
	if EventBus.player_hp_changed.is_connected(_on_changed):
		EventBus.player_hp_changed.disconnect(_on_changed)
	if EventBus.player_mp_changed.is_connected(_on_changed):
		EventBus.player_mp_changed.disconnect(_on_changed)
	if EventBus.player_level_up.is_connected(_on_changed):
		EventBus.player_level_up.disconnect(_on_changed)
	if EventBus.player_money_changed.is_connected(_on_changed):
		EventBus.player_money_changed.disconnect(_on_changed)
