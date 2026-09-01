# scenes/ui/components/wuxia_menu_button/WuxiaMenuButton.gd
# 水墨武侠风格主菜单按钮（B 路线叶子预制）
# 职责：hover 切换墨迹底板 + 图标高亮 + 缩放动画 + 音效；不写业务跳转。
# 业务与键盘导航由 MainMenu.gd 统一接管。

extends Button

signal selected
signal confirmed

const UIPalette = preload("res://core/constants/ui_theme.gd")
const BOLD_FONT := preload("res://resources/fonts/SiYuanSongTiRegular/SourceHanSerifCN-Bold-2.otf")
const REG_FONT := preload("res://resources/fonts/SiYuanSongTiRegular/SourceHanSerifCN-Regular-1.otf")

const TEXT_NORMAL := UIPalette.TEXT_SECONDARY   # 常态：灰白
const TEXT_HOVER := UIPalette.GOLD_DARK         # 悬停：暗金

@export var text_key: String = ""          # 本地化 key（如 menu_new_game）
@export var sub_text: String = ""          # 底部英文/小字装饰，直接文本
@export var icon_normal: Texture2D         # 常态图标
@export var icon_hover: Texture2D          # hover 高亮图标；缺省时用金色 modulate 占位
@export var bg_hover: Texture2D            # hover 墨迹底板（常态不显示底图）
@export var hover_scale: float = 1.04
@export var press_scale: float = 0.96
@export var disabled_alpha: float = 0.45
# 字号（可在模板/实例的检查器里直接改，无需碰代码）
@export var main_font_size: int = UIPalette.FS_MENU
@export var sub_font_size: int = UIPalette.FS_TINY

@onready var bg_panel: TextureRect = $bg_panel
@onready var icon_rect: TextureRect = $icon
@onready var label_main: Label = $label_main
@onready var label_sub: Label = $label_sub

var _is_selected: bool = false
var _is_hovered: bool = false
var _is_pressed: bool = false
var _tween: Tween = null


func _ready() -> void:
	_clear_button_skin()
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	clip_contents = false

	label_main.add_theme_font_override("font", BOLD_FONT)
	label_main.add_theme_font_size_override("font_size", main_font_size)

	label_sub.add_theme_font_override("font", REG_FONT)
	label_sub.add_theme_font_size_override("font_size", sub_font_size)

	_refresh_text()
	_refresh_visual_state()

	mouse_entered.connect(_on_mouse_entered)
	mouse_exited.connect(_on_mouse_exited)
	button_down.connect(_on_button_down)
	button_up.connect(_on_button_up)
	resized.connect(_on_resized)
	_on_resized()


func _clear_button_skin() -> void:
	var empty := StyleBoxEmpty.new()
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		add_theme_stylebox_override(state, empty)


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _refresh_text() -> void:
	if text_key == "":
		label_main.text = ""
	else:
		label_main.text = tr(text_key)
	label_sub.text = sub_text


func _refresh_visual_state() -> void:
	var active := _is_hovered or _is_selected

	# 墨迹底板：只在 hover / 选中时显示
	bg_panel.texture = bg_hover if active else null

	# 图标：优先用 icon_hover；没有就用金色 modulate 占位；常态压灰
	if active and icon_hover != null:
		icon_rect.texture = icon_hover
		icon_rect.modulate = Color.WHITE
	elif active:
		icon_rect.texture = icon_normal
		icon_rect.modulate = UIPalette.GOLD
	else:
		icon_rect.texture = icon_normal
		icon_rect.modulate = Color(0.55, 0.55, 0.55)

	# 文字颜色：常态灰白，悬停/选中暗金（无需新 PNG，代码改色）
	var text_color := TEXT_HOVER if active else TEXT_NORMAL
	label_main.add_theme_color_override("font_color", text_color)
	label_sub.add_theme_color_override("font_color", text_color)

	# 缩放动画
	if _is_pressed:
		_tween_scale(Vector2(press_scale, press_scale))
	elif active:
		_tween_scale(Vector2(hover_scale, hover_scale))
	else:
		_tween_scale(Vector2.ONE)


func _tween_scale(target: Vector2) -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_tween = create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
	_tween.tween_property(self, "scale", target, 0.12)


func _on_mouse_entered() -> void:
	if disabled:
		return
	_is_hovered = true
	_refresh_visual_state()
	_play_hover_sfx()
	if not _is_selected:
		selected.emit()


func _on_mouse_exited() -> void:
	_is_hovered = false
	_is_pressed = false
	_refresh_visual_state()


func _on_button_down() -> void:
	if disabled:
		return
	_is_pressed = true
	_tween_scale(Vector2(press_scale, press_scale))
	_play_click_sfx()


func _on_button_up() -> void:
	_is_pressed = false
	if _is_hovered:
		confirmed.emit()
	_refresh_visual_state()


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
	_refresh_visual_state()


func set_enabled(enabled: bool) -> void:
	disabled = not enabled
	modulate.a = 1.0 if enabled else disabled_alpha
	_refresh_visual_state()


func is_enabled() -> bool:
	return not disabled
