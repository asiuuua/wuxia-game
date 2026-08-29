# scenes/ui/overlays/hud/status_card_panel.gd
# HUD 左上角状态卡（v2 四面板之一）：头像框 + 姓名/等级/银两 + 气血条 + 内力条 + 六维属性条。
# 纯展示层，订阅 EventBus 的 player_* 信号刷新，不修改业务数据。
# 配色全部走 UIPalette，禁止裸 Color 字面量。

extends Control
class_name StatusCardPanel

const UIPalette = preload("res://core/constants/ui_theme.gd")

# 六维属性（key 对应 PlayerState 成员名，name 为面板显示用单字）
const _ATTRS := [
	{"key": "strength", "name": "力"},
	{"key": "constitution", "name": "骨"},
	{"key": "agility", "name": "敏"},
	{"key": "wisdom", "name": "悟"},
	{"key": "luck", "name": "福"},
	{"key": "focus", "name": "定"},
]

# === 单条数值条（标签 + 轨道 + 填充 + 可选数值文本） ===
class _Bar extends Control:
	var _fill: ColorRect
	var _val_label: Label
	func _init(p_label: String, p_color: Color, p_width: float, p_height := 16.0, show_val := true) -> void:
		var label_w := 42.0
		var val_w := 58.0 if show_val else 0.0
		var track_w := p_width - label_w - val_w
		custom_minimum_size = Vector2(p_width, p_height + 16.0)
		var h := HBoxContainer.new()
		h.size_flags_horizontal = SIZE_EXPAND_FILL
		var lab := Label.new()
		lab.text = p_label
		lab.custom_minimum_size = Vector2(label_w, p_height)
		lab.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
		lab.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
		h.add_child(lab)
		var track := Panel.new()
		track.custom_minimum_size = Vector2(track_w, p_height)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UIPalette.PANEL_DARK
		for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
			sb.set("corner_radius_" + r, 4)
		track.add_theme_stylebox_override("panel", sb)
		_fill = ColorRect.new()
		_fill.color = p_color
		_fill.anchor_left = 0.0
		_fill.anchor_top = 0.0
		_fill.anchor_right = 0.0
		_fill.anchor_bottom = 1.0
		_fill.offset_left = 0.0
		_fill.offset_top = 0.0
		_fill.offset_right = 0.0
		_fill.offset_bottom = 0.0
		track.add_child(_fill)
		h.add_child(track)
		if show_val:
			_val_label = Label.new()
			_val_label.custom_minimum_size = Vector2(val_w, p_height)
			_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			_val_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
			_val_label.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
			h.add_child(_val_label)
		add_child(h)
	func set_value(cur: int, maxv: int) -> void:
		var r := 0.0
		if maxv > 0:
			r = float(cur) / float(maxv)
		_fill.anchor_right = clampf(r, 0.0, 1.0)
		if _val_label != null:
			_val_label.text = "%d/%d" % [cur, maxv]
	func set_level(cur: int, cap := 100) -> void:
		_fill.anchor_right = clampf(float(cur) / float(cap), 0.0, 1.0)
		if _val_label != null:
			_val_label.text = str(cur)

var _name_label: Label
var _lv_label: Label
var _money_label: Label
var _avatar_char: Label
var _avatar_tex: TextureRect
var _hp_bar: _Bar
var _mp_bar: _Bar
var _attr_bars: Dictionary = {}

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_build()
	if is_instance_valid(EventBus):
		EventBus.player_hp_changed.connect(_refresh)
		EventBus.player_mp_changed.connect(_refresh)
		EventBus.player_level_up.connect(_refresh)
		EventBus.player_exp_changed.connect(_refresh)
		EventBus.player_stats_changed.connect(_refresh)
		EventBus.player_money_changed.connect(_refresh)
	_refresh()

# === 构建状态卡 ===
# 视觉尺寸说明：用户要求「缩小三分之一」→ 保留 2/3（约 0.667），实际渲染 227×212，
# 远低于屏幕左上 1/4（960×540），满足「不超左上四分之一」约束。
# 后续若需再调整体改 _VISUAL_SCALE 即可，不动内部 _Bar/字号字面。
# 用 Control.scale 做整体变换，pivot 显式锚左上，position/size 不变。
const _VISUAL_SCALE := 0.667

func _build() -> void:
	position = Vector2(12, 12)
	custom_minimum_size = Vector2(340, 318)
	size = Vector2(340, 318)
	pivot_offset = Vector2.ZERO  # 显式锚左上，scale 向右下收敛
	scale = Vector2(_VISUAL_SCALE, _VISUAL_SCALE)
	var panel := Panel.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
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
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	v.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 8)
	margin.add_child(v)
	# 头像 + 姓名/等级/银两
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 10)
	top.add_child(_build_avatar())
	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_label = Label.new()
	_name_label.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_name_label.add_theme_font_size_override("font_size", UIPalette.FS_NAME)
	info.add_child(_name_label)
	_lv_label = Label.new()
	_lv_label.add_theme_color_override("font_color", UIPalette.GOLD)
	_lv_label.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
	info.add_child(_lv_label)
	_money_label = Label.new()
	_money_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	_money_label.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	info.add_child(_money_label)
	top.add_child(info)
	v.add_child(top)
	# 气血 / 内力
	_hp_bar = _Bar.new("气血", UIPalette.HP_FILL, 300.0)
	v.add_child(_hp_bar)
	_mp_bar = _Bar.new("内力", UIPalette.MP_FILL, 300.0)
	v.add_child(_mp_bar)
	# 六维属性条
	var attr_title := Label.new()
	attr_title.text = "六 维 属 性"
	attr_title.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	attr_title.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	v.add_child(attr_title)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 4)
	for a in _ATTRS:
		var b := _Bar.new(a["name"], UIPalette.ATTR_FILL, 150.0, 14.0, false)
		_attr_bars[a["key"]] = b
		grid.add_child(b)
	v.add_child(grid)

# 圆角头像框：占位（无立绘时用角色名首字），金色暗调底
func _build_avatar() -> Control:
	var av := Panel.new()
	av.custom_minimum_size = Vector2(60, 60)
	av.size = Vector2(60, 60)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GOLD_DARK
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sb.set("corner_radius_" + r, 14)
	av.add_theme_stylebox_override("panel", sb)
	_avatar_char = Label.new()
	_avatar_char.text = "侠"
	_avatar_char.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_avatar_char.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_avatar_char.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_avatar_char.add_theme_font_size_override("font_size", 30)
	_avatar_char.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	av.add_child(_avatar_char)
	# 头像纹理层（可选）：npc/player 有真实图则显图盖住首字，否则首字兜底
	_avatar_tex = TextureRect.new()
	_avatar_tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_avatar_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_avatar_tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_avatar_tex.visible = false
	av.add_child(_avatar_tex)
	return av

func _exit_tree() -> void:
	# 本面板挂在 autoload 的 HUD 层，切场景/游戏退出时 EventBus 可能已先于本节点释放，
	# 故 disconnect 前必须 is_instance_valid 判空。
	if not is_instance_valid(EventBus):
		return
	if EventBus.player_hp_changed.is_connected(_refresh):
		EventBus.player_hp_changed.disconnect(_refresh)
	if EventBus.player_mp_changed.is_connected(_refresh):
		EventBus.player_mp_changed.disconnect(_refresh)
	if EventBus.player_level_up.is_connected(_refresh):
		EventBus.player_level_up.disconnect(_refresh)
	if EventBus.player_exp_changed.is_connected(_refresh):
		EventBus.player_exp_changed.disconnect(_refresh)
	if EventBus.player_stats_changed.is_connected(_refresh):
		EventBus.player_stats_changed.disconnect(_refresh)
	if EventBus.player_money_changed.is_connected(_refresh):
		EventBus.player_money_changed.disconnect(_refresh)

func _refresh(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	if not is_instance_valid(GameManager) or GameManager.player_state == null:
		return
	var ps: PlayerState = GameManager.player_state
	if _name_label != null:
		_name_label.text = ps.player_name
	if _lv_label != null:
		_lv_label.text = "等级 %d" % ps.level
	if _money_label != null:
		_money_label.text = "银两 %d" % ps.silver
	if _avatar_char != null:
		_avatar_char.text = ps.player_name.left(1)
	if _avatar_tex != null:
		# 双通道：有玩家头像（resources/icons/npc/player.png）显图，否则首字兜底
		if UIManager.has_icon("npc/player"):
			_avatar_tex.texture = UIManager.get_icon("npc/player")
			_avatar_tex.visible = true
			_avatar_char.visible = false
		else:
			_avatar_tex.visible = false
			_avatar_char.visible = true
	_hp_bar.set_value(ps.hp, ps.max_hp)
	_mp_bar.set_value(ps.mp, ps.max_mp)
	for a in _ATTRS:
		var b: _Bar = _attr_bars.get(a["key"], null)
		if b != null:
			# PlayerState 是 Object，Object.get 仅 1 参（无默认值）；
			# 用 `or 0` 兜底缺省属性，避免解析期 “Too many arguments for get()”。
			var raw: Variant = ps.get(a["key"])
			b.set_level(int(raw) if raw != null else 0, 100)
