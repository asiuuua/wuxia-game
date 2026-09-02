# scenes/ui/components/ui_feedback/UIFeedback.gd
# 交互反馈组件（2026-08-29 行为层落地）
#
# 挂到任意 Control 上，提供：悬停缩放 / 按下反馈 / 焦点（键盘）反馈 / 音效 / 禁用守卫。
# 数值全部来自配置表 data/configs/ui/ui_anim.json 与 ui_sfx.json，改手感只改表不动代码。
#
# 修正了外部建议代码里的三个真实缺陷：
#   1) **pivot_offset**：Control 的 scale 以 pivot_offset 为旋转/缩放基准，默认是 (0,0) 即左上角。
#      直接缩放会让控件往右下角生长——右下角的按钮会溢出屏幕。这里把 pivot 设到控件中心，
#      实现真正的"原地放大"，并在 resized 时重算。
#   2) **tween kill**：每次新动画前 kill 掉旧的。不 kill 的话快速进出会有多个 tween
#      同时驱动同一个 scale 属性，产生抖动。
#   3) **键盘焦点也触发**：原方案只连 mouse_entered/exited，导致 MenuItem
#      （FOCUS_NONE + 自定义 ui_up/ui_down 导航）键盘选中时完全没有反馈。
#      这里额外监听 focus_entered/focus_exited，并暴露 notify_selection_changed() 供外部导航调用。
#
# 音效：走 AudioManager.play_ui_sfx(事件名)，配置表驱动；音频文件缺失静默跳过。

extends Node
class_name UIFeedback

## 预设名，对应 ui_anim.json 里的 hover / press / focus 组
var _preset: String = "hover"
## 是否接管鼠标悬停。MenuItem 这类自己用 gui_input 处理鼠标的组件必须传 false，
## 改由 set_selected() -> notify_selection_changed() 显式驱动，否则会双重触发
## （动画跳两遍 + 音效放两次）
var _handle_mouse: bool = true
var _target: Control = null
var _tween: Tween = null
var _hovering: bool = false
var _pressed: bool = false
var _selected: bool = false   # 键盘/外部导航选中标（供 MenuItem 这类自定义导航用）

# === 令牌解析结果缓存（审计派单 fdfcce7396ed：悬停动效高频触发，避免每次重复解析令牌→枚举）===
# 令牌→Tween 枚举映射全局复用（static，跨实例共享）；预设/时长/缩放按实例缓存（_preset 在 attach 时固定）。
static var _trans_cache: Dictionary = {}
static var _ease_cache: Dictionary = {}
var _cached_preset: Dictionary = {}
var _cached_duration_f: float = -1.0
var _cached_hover_scale_f: float = -1.0
var _cached_press_scale_f: float = -1.0
var _cached_focus_scale_f: float = -1.0

## 工厂方法：把反馈挂到目标控件上
## 用法：UIFeedback.attach(my_button)
## 用法：UIFeedback.attach(menu_item, "focus", false)  # 由外部导航驱动
static func attach(target: Control, preset: String = "hover", handle_mouse: bool = true) -> UIFeedback:
	if target == null:
		return null
	var fx := UIFeedback.new()
	fx.name = "UIFeedback"
	fx._preset = preset
	fx._handle_mouse = handle_mouse
	fx._target = target       # 必须在 add_child 之前设，_ready 里要用
	target.add_child(fx)
	return fx

func _ready() -> void:
	if _target == null:
		return
	_apply_pivot()
	# 尺寸变化（换字号/换语言/布局重排）时重算 pivot，否则缩放中心会偏
	if not _target.resized.is_connected(_apply_pivot):
		_target.resized.connect(_apply_pivot)
	if _handle_mouse:
		_target.mouse_entered.connect(_on_mouse_entered)
		_target.mouse_exited.connect(_on_mouse_exited)
	_target.focus_entered.connect(_on_focus_entered)
	_target.focus_exited.connect(_on_focus_exited)
	if _target is Button:
		_target.button_down.connect(_on_press_start)
		_target.button_up.connect(_on_press_end)

func _exit_tree() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()

# === pivot 修正：Control 缩放默认绕左上角，设到中心才是"原地放大" ===
func _apply_pivot() -> void:
	if _target == null:
		return
	_target.pivot_offset = _target.size / 2.0

# === 事件 ===
func _on_mouse_entered() -> void:
	if _is_disabled():
		return
	_hovering = true
	_animate_to(_hover_scale())
	_play("hover")

func _on_mouse_exited() -> void:
	_hovering = false
	_pressed = false
	_rest()

func _on_press_start() -> void:
	if _is_disabled():
		return
	_pressed = true
	_animate_to(_press_scale())
	_play("click")

func _on_press_end() -> void:
	_pressed = false
	_rest()

func _on_focus_entered() -> void:
	if _is_disabled():
		return
	_animate_to(_focus_scale())
	_play("hover")

func _on_focus_exited() -> void:
	_rest()

## 供外部自定义导航调用（MenuItem 用 FOCUS_NONE + 自己处理 ui_up/ui_down，
## 系统不会发 focus_entered，必须显式通知本组件）
func notify_selection_changed(selected: bool) -> void:
	if _selected == selected:
		return
	_selected = selected
	if _is_disabled():
		return
	if selected:
		_animate_to(_focus_scale())
		_play("hover")
	else:
		_rest()

## 回到静止态：若仍处于悬停/选中则回到对应放大态，否则回原始大小
func _rest() -> void:
	if _hovering:
		_animate_to(_hover_scale())
	elif _selected:
		_animate_to(_focus_scale())
	else:
		_animate_to(1.0)

# === 动画 ===
func _animate_to(target_scale: float) -> void:
	if _target == null or not is_instance_valid(_target):
		return
	# kill 旧 tween：否则快速进出会有多个 tween 抢同一个 scale，产生抖动
	if _tween != null and _tween.is_valid():
		_tween.kill()
	var token: String = _easing_token()
	_tween = create_tween()
	_tween.set_trans(_cached_trans(token))
	_tween.set_ease(_cached_ease(token))
	_tween.tween_property(_target, "scale", Vector2(target_scale, target_scale), _cached_duration())

# === 令牌解析结果缓存（审计派单 fdfcce7396ed：悬停动效高频触发，避免每次重复解析令牌→枚举）===
# 静态缓存：令牌→Tween 枚举映射跨实例共享（配置启动时固定、运行期不变，缓存安全）
static func _cached_trans(token: String) -> int:
	if not _trans_cache.has(token):
		_trans_cache[token] = ConfigManager.get_anim_trans(token)
	return _trans_cache[token]

static func _cached_ease(token: String) -> int:
	if not _ease_cache.has(token):
		_ease_cache[token] = ConfigManager.get_anim_ease(token)
	return _ease_cache[token]

# 实例缓存：预设 dict / 时长 / 缩放幅度在 attach 时固定，缓存避免高频悬停重复查表
func _cached_preset_dict() -> Dictionary:
	if _cached_preset.is_empty():
		_cached_preset = ConfigManager.get_anim_preset(_preset)
	return _cached_preset

func _cached_duration() -> float:
	if _cached_duration_f < 0.0:
		_cached_duration_f = ConfigManager.get_anim_preset_duration(_preset)
	return _cached_duration_f

# === 配置读数（全部带兜底，配置缺失也不崩）===
func _hover_scale() -> float:
	if _cached_hover_scale_f < 0.0:
		_cached_hover_scale_f = ConfigManager.get_anim_value("hover", "scale", 1.08)
	return _cached_hover_scale_f

func _press_scale() -> float:
	if _cached_press_scale_f < 0.0:
		_cached_press_scale_f = ConfigManager.get_anim_value("press", "scale", 0.96)
	return _cached_press_scale_f

func _focus_scale() -> float:
	if _cached_focus_scale_f < 0.0:
		_cached_focus_scale_f = ConfigManager.get_anim_value("focus", "scale", 1.05)
	return _cached_focus_scale_f

func _easing_token() -> String:
	return String(_cached_preset_dict().get("easing", "standard"))

func _is_disabled() -> bool:
	if _target == null:
		return true
	if _target is Button:
		return _target.disabled
	return false

func _play(event: String) -> void:
	if AudioManager != null:
		AudioManager.play_ui_sfx(event)
