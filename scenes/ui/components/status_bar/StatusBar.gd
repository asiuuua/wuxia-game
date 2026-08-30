# scenes/ui/components/status_bar/StatusBar.gd
# B 路线复合控件：单条数值条（标签 + 轨道 + 填充 + 可选数值文本）。
# 由 status_card_panel.gd 的内嵌 class _Bar 抽出；节点结构见 StatusBar.tscn，
# 样式与动态参数（标签/颜色/尺寸/是否显值）走代码，全部引用 UIPalette，禁止裸 Color。
# 不含 class_name（避免全局脚本类缓存缺失导致全工程解析飘红），调用方用 const 双引用模式。

extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

@onready var _label: Label = $HBox/Label
@onready var _track: Panel = $HBox/Track
@onready var _fill: ColorRect = $HBox/Track/Fill
@onready var _val_label: Label = $HBox/Val

var _ready_done := false

# 防御式懒初始化：入树时 _ready 自动跑；孤儿态（单元测试手动 _ready 不触发子节点 _ready）
# 则经 $ 路径手动取节点 + 配置，保证两种上下文行为一致。
func _ensure_ready() -> void:
	if _ready_done:
		return
	_ready_done = true
	if _label == null:
		_label = $HBox/Label
		_track = $HBox/Track
		_fill = $HBox/Track/Fill
		_val_label = $HBox/Val
	_configure_static()

func _ready() -> void:
	_ensure_ready()

func _configure_static() -> void:
	_label.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_label.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.PANEL_DARK
	sb.border_color = UIPalette.GLASS_BORDER
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	for r in ["top_left", "top_right", "bottom_left", "bottom_right"]:
		sb.set("corner_radius_" + r, 4)
	_track.add_theme_stylebox_override("panel", sb)
	_val_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_val_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	_val_label.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	_fill.anchor_left = 0.0
	_fill.anchor_top = 0.0
	_fill.anchor_right = 0.0
	_fill.anchor_bottom = 1.0
	_fill.offset_left = 0.0
	_fill.offset_top = 0.0
	_fill.offset_right = 0.0
	_fill.offset_bottom = 0.0

# 动态构造参数（原 _init 职责）：标签/颜色/总宽/条高/是否显值。
func setup(p_label: String, p_color: Color, p_width: float, p_height := 16.0, show_val := true) -> void:
	_ensure_ready()
	var label_w := 42.0
	var val_w := 58.0 if show_val else 0.0
	var track_w := p_width - label_w - val_w
	custom_minimum_size = Vector2(p_width, p_height + 16.0)
	_label.text = p_label
	_label.custom_minimum_size = Vector2(label_w, p_height)
	_fill.color = p_color
	_track.custom_minimum_size = Vector2(track_w, p_height)
	if show_val:
		_val_label.visible = true
		_val_label.custom_minimum_size = Vector2(val_w, p_height)
	else:
		_val_label.visible = false

func set_value(cur: int, maxv: int) -> void:
	_ensure_ready()
	var r := 0.0
	if maxv > 0:
		r = float(cur) / float(maxv)
	_fill.anchor_right = clampf(r, 0.0, 1.0)
	if _val_label != null and _val_label.visible:
		_val_label.text = "%d/%d" % [cur, maxv]

func set_level(cur: int, cap := 100) -> void:
	_ensure_ready()
	_fill.anchor_right = clampf(float(cur) / float(cap), 0.0, 1.0)
	if _val_label != null and _val_label.visible:
		_val_label.text = str(cur)
