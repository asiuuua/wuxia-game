# scenes/ui/components/skill_slot/SkillSlot.gd
# B 路线复合控件：快捷栏单个技能槽（图标 + 名称 + 冷却读秒覆盖层）。
# 由 skill_bar_panel.gd 的内嵌 class _Slot 抽出；节点结构见 SkillSlot.tscn，
# 样式与几何走代码（UIPalette）。不含 class_name，调用方用 const 双引用模式。
# 冷却逻辑归属武学窗主权，本控件只展示 remain_time 文本，不驱动计时。

extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

@onready var _icon: TextureRect = $_icon
@onready var _name: Label = $_name
@onready var _cd: Label = $_cd

var _ability_id: String = ""
var _ready_done := false

func _ensure_ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	if _icon == null:
		_icon = $_icon
		_name = $_name
		_cd = $_cd
	_configure_static()

func _ready() -> void:
	_ensure_ready()
	set_empty()

func _configure_static() -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_color = UIPalette.GLASS_BORDER
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	add_theme_stylebox_override("panel", sb)
	# 几何（原 _init 里的布局，迁入代码以保持与 .tscn 解耦、便于统一维护）
	_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.anchor_left = 0.0
	_name.anchor_right = 1.0
	_name.anchor_top = 1.0
	_name.anchor_bottom = 1.0
	_name.offset_top = -16.0
	_name.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	_name.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_cd.add_theme_color_override("font_color", UIPalette.BADGE_RED)
	_cd.add_theme_font_size_override("font_size", UIPalette.FS_SUB)
	_cd.visible = false

func set_empty() -> void:
	_ensure_ready()
	_ability_id = ""
	_icon.texture = null
	_icon.visible = false
	_name.text = "—"
	_cd.visible = false

func set_ability(ability_id: String) -> void:
	_ensure_ready()
	_ability_id = ability_id
	_name.text = ConfigManager.get_ability(ability_id).get("name", ability_id) if ConfigManager.has_ability(ability_id) else ability_id
	if UIManager.has_icon("skills/" + ability_id):
		_icon.texture = UIManager.get_icon("skills/" + ability_id)
		_icon.visible = true
	else:
		_icon.texture = null
		_icon.visible = false
	_cd.visible = false

func get_ability_id() -> String:
	return _ability_id

func set_cd(remain: float) -> void:
	_ensure_ready()
	if remain > 0.0:
		_cd.text = "%.1f" % remain
		_cd.visible = true
	else:
		_cd.visible = false
