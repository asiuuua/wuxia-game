# scenes/ui/components/wuxia_menu_button/WuxiaMenuButton.gd
# 水墨武侠风格主菜单按钮（B 路线叶子预制）
# 职责：统一、自然的 hover 动效（墨迹底板淡入 + 图标/文字颜色渐变 + 轻微上浮/右移 + 缩放）；不写业务跳转。
# 业务与键盘导航由 MainMenu.gd 统一接管。

extends Button

signal selected
signal confirmed

const UIPalette = preload("res://core/constants/ui_theme.gd")
const BOLD_FONT := preload("res://resources/fonts/SiYuanSongTiRegular/SourceHanSerifCN-Bold-2.otf")
const REG_FONT := preload("res://resources/fonts/SiYuanSongTiRegular/SourceHanSerifCN-Regular-1.otf")

const TEXT_NORMAL := UIPalette.TEXT_SECONDARY   # 常态：灰白
const TEXT_HOVER := UIPalette.GOLD_DARK         # 悬停：暗金
const ICON_COLOR_NORMAL := Color(0.65, 0.60, 0.55, 1.0)  # 图标常态：与文字同调的暖灰
const ICON_COLOR_HOVER := UIPalette.GOLD                  # 图标悬停：亮金

const HOVER_DURATION := 0.20
const PRESS_DURATION := 0.08
var hover_shift_x: float = 5.0   # 悬停时图标与文字统一向右位移（像素）；负值=左移。由工作室「悬停浮动」设置驱动
var hover_shift_y: float = 3.0   # 悬停时图标与文字统一向上位移（像素）；由工作室「悬停浮动」设置驱动

@export var text_key: String = ""          # 本地化 key（如 menu_new_game）
@export var sub_text: String = ""          # 底部英文/小字装饰，直接文本
@export var icon_normal: Texture2D         # 常态图标
@export var icon_hover: Texture2D          # hover 高亮图标；缺省时用金色 modulate 占位
@export var bg_hover: Texture2D            # hover 墨迹底板（常态透明，hover 淡入）
@export var hover_scale: float = 1.03      # 悬停整体缩放（图标+文字同步）
@export var press_scale: float = 0.96      # 按下整体缩放
@export var disabled_alpha: float = 0.45
# 基础显示缩放（1.0=100%）。工作室「菜单按钮显示尺寸」写入的 icon_scales 会经 MainMenu 设置到这里。
@export var base_scale: float = 1.0
# 字号（主菜单按钮整体缩到 65%，文字同步缩到 65%）
@export var main_font_size: int = 15
@export var sub_font_size: int = 8

@onready var bg_panel: TextureRect = $bg_panel
@onready var icon_rect: TextureRect = $icon
@onready var label_main: Label = $label_main
@onready var label_sub: Label = $label_sub

var _is_selected: bool = false
var _is_hovered: bool = false
var _is_pressed: bool = false
var _hover_t: float = 0.0
var _hover_tween: Tween = null
var _press_tween: Tween = null

var _icon_base_pos: Vector2 = Vector2.ZERO
var _label_main_base_pos: Vector2 = Vector2.ZERO
var _label_sub_base_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_clear_button_skin()
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false
	_apply_icon_scale(base_scale)

	# 记录原始局部位置，供悬停位移动画使用
	_icon_base_pos = icon_rect.position
	_label_main_base_pos = label_main.position
	_label_sub_base_pos = label_sub.position

	# 墨迹底板常驻但初始全透明，悬停时通过 alpha 淡入
	if bg_panel != null:
		bg_panel.texture = bg_hover
		bg_panel.modulate.a = 0.0

	label_main.add_theme_font_override("font", BOLD_FONT)
	label_main.add_theme_font_size_override("font_size", main_font_size)

	label_sub.add_theme_font_override("font", REG_FONT)
	label_sub.add_theme_font_size_override("font_size", sub_font_size)

	_refresh_text()
	_apply_hover(0.0)

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)


func _clear_button_skin() -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)


# 只缩放图标节点（围绕自身中心），文字与按钮布局不动
func _apply_icon_scale(value: float) -> void:
	if icon_rect == null:
		return
	base_scale = value
	icon_rect.pivot_offset = icon_rect.size * 0.5
	icon_rect.scale = Vector2(value, value)


func _refresh_text() -> void:
	if text_key == "":
		label_main.text = ""
	else:
		label_main.text = tr(text_key)
	label_sub.text = sub_text


func _active() -> bool:
	return _is_hovered or _is_selected


# 启动/归位 hover 插值；目标由当前 active 状态决定
func _tween_hover(target: float) -> void:
	if _hover_tween != null and _hover_tween.is_valid():
		_hover_tween.kill()
	_hover_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_hover_tween.tween_method(_apply_hover, _hover_t, target, HOVER_DURATION)


# 应用某一 hover 进度 t∈[0,1]：底板淡入、颜色渐变、位置微移、缩放更新
func _apply_hover(t: float) -> void:
	_hover_t = t

	# 墨迹底板淡入
	if bg_panel != null:
		bg_panel.modulate.a = t

	# 图标：优先使用 icon_hover 纹理；否则 icon_normal + 颜色插值
	if icon_rect != null:
		var use_hover_tex := t > 0.5 and icon_hover != null
		if use_hover_tex:
			icon_rect.texture = icon_hover
			icon_rect.modulate = Color.WHITE
		else:
			icon_rect.texture = icon_normal
			icon_rect.modulate = ICON_COLOR_NORMAL.lerp(ICON_COLOR_HOVER, t)

	# 文字颜色：灰白 -> 暗金
	var text_color := TEXT_NORMAL.lerp(TEXT_HOVER, t)
	label_main.add_theme_color_override("font_color", text_color)
	label_sub.add_theme_color_override("font_color", text_color)

	# 图标与文字共用同一位移向量（向右 + 向上），同向同步浮动，方向感一致，不再各奔东西
	if icon_rect != null:
		icon_rect.position.x = _icon_base_pos.x + hover_shift_x * t
		icon_rect.position.y = _icon_base_pos.y - hover_shift_y * t
	label_main.position.x = _label_main_base_pos.x + hover_shift_x * t
	label_main.position.y = _label_main_base_pos.y - hover_shift_y * t
	label_sub.position.x = _label_sub_base_pos.x + hover_shift_x * t
	label_sub.position.y = _label_sub_base_pos.y - hover_shift_y * t

	_apply_scale()


# 根据当前 _hover_t 与 _is_pressed 计算并应用缩放。
# 悬停/按压：图标与文字各自围绕自身中心等比例放大/缩小到相同倍数（不变形、不拉伸、不聚合）；
# 尺寸档位（常态）：只缩放图标，文字保持原样。上浮/右移动画见 _apply_hover，与此互不影响。
func _apply_scale() -> void:
	var hover_mul := lerpf(1.0, hover_scale, _hover_t)
	var press_mul := press_scale if _is_pressed else 1.0
	var final_mul := hover_mul * press_mul

	if icon_rect != null:
		icon_rect.pivot_offset = icon_rect.size * 0.5
		icon_rect.scale = Vector2(base_scale * final_mul, base_scale * final_mul)

	label_main.pivot_offset = label_main.size * 0.5
	label_sub.pivot_offset = label_sub.size * 0.5
	label_main.scale = Vector2(final_mul, final_mul)
	label_sub.scale = Vector2(final_mul, final_mul)


func _on_mouse_entered() -> void:
	if disabled:
		return
	_is_hovered = true
	_tween_hover(1.0)
	_play_hover_sfx()
	if not _is_selected:
		selected.emit()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_is_pressed = false
	_tween_hover(1.0 if _is_selected else 0.0)


func _on_button_down() -> void:
	if disabled:
		return
	_is_pressed = true
	_apply_scale()
	_play_click_sfx()


func _on_button_up() -> void:
	_is_pressed = false
	_apply_scale()
	if _is_hovered:
		confirmed.emit()


func _play_hover_sfx() -> void:
	if Engine.is_editor_hint():
		return
	AudioManager.play_ui_sfx("hover")


func _play_click_sfx() -> void:
	if Engine.is_editor_hint():
		return
	AudioManager.play_ui_sfx("click")


# === 供 MainMenu 键盘导航调用的公共接口 ===
func set_selected(value: bool) -> void:
	_is_selected = value
	_tween_hover(1.0 if _active() else 0.0)


func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	modulate.a = 1.0 if enabled else disabled_alpha
	_tween_hover(0.0)
	_apply_scale()


func is_enabled() -> bool:
	return not disabled
