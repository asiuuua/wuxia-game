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
	_tween.set_trans(ConfigManager.get_anim_trans(token))
	_tween.set_ease(ConfigManager.get_anim_ease(token))
	_tween.tween_property(_target, "scale", Vector2(target_scale, target_scale),
		ConfigManager.get_anim_preset_duration(_preset))

# === 配置读数（全部带兜底，配置缺失也不崩）===
func _hover_scale() -> float:
	return ConfigManager.get_anim_value("hover", "scale", 1.08)

func _press_scale() -> float:
	return ConfigManager.get_anim_value("press", "scale", 0.96)

func _focus_scale() -> float:
	return ConfigManager.get_anim_value("focus", "scale", 1.05)

func _easing_token() -> String:
	return String(ConfigManager.get_anim_preset(_preset).get("easing", "standard"))

func _is_disabled() -> bool:
	if _target == null:
		return true
	if _target is Button:
		return _target.disabled
	return false

func _play(event: String) -> void:
	if AudioManager != null:
		AudioManager.play_ui_sfx(event)
