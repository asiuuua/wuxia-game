# autoload/ui_manager.gd
# UI 管理器（autoload，不写 class_name —— 避免与单例名冲突解析失败，今日 08-27 刚踩此坑）
# 职责：维护 6 个 CanvasLayer 层级，提供全屏界面栈的打开/关闭。
# 界面以「脚本路径」登记在 data/configs/ui/screens.json，open_screen 用 script.new() 实例化
# （对齐本项目「代码构建 Control 覆盖层」的惯例，不依赖 .tscn）。

@warning_ignore("shadowed_global_identifier")

extends Node

enum Layer {
	BACKGROUND,
	TRANSITION,
	FULLSCREEN,
	POPUP,
	TOOLTIP,
	SYSTEM_OVERLAY,
}

const SCREENS_FILE := "res://data/configs/ui/screens.json"
const UIPalette = preload("res://core/constants/ui_theme.gd")

var _layers: Dictionary = {}         # int(layer) -> CanvasLayer
var _screen_paths: Dictionary = {}   # 界面名 -> 脚本路径
var _screen_stack: Array = []        # 打开中的全屏界面（Control）
var _screen_layer: Dictionary = {}   # Control -> 所在层级（用于判断弹窗是否打开）
var _current_screen: Control = null

func _ready() -> void:
	_init_layers()
	_load_screen_registry()
	EventBus.notification_show.connect(show_tooltip)

func _init_layers() -> void:
	for layer_value in Layer.values():
		var canvas: CanvasLayer = CanvasLayer.new()
		canvas.layer = layer_value * 10
		canvas.name = "UILayer_%s" % layer_value
		_layers[layer_value] = canvas
		# autoload _ready 期间 root 正在被装配，直接 add_child 会报 "busy"，延迟到下一帧挂载
		get_tree().root.call_deferred("add_child", canvas)

func _load_screen_registry() -> void:
	if not FileAccess.file_exists(SCREENS_FILE):
		GameLogger.warn("UIManager", "界面注册表缺失: %s" % SCREENS_FILE)
		return
	var f := FileAccess.open(SCREENS_FILE, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null:
		GameLogger.warn("UIManager", "界面注册表解析失败: %s" % SCREENS_FILE)
		return
	_screen_paths = parsed

func get_layer(layer: int) -> CanvasLayer:
	return _layers.get(layer, null) as CanvasLayer

## 安全区边距（安卓刘海/挖孔/圆角）：返回 Vector4(left, top, right, bottom)，单位像素。
## 桌面平台与无挖孔设备返回全 0，无副作用。
## 用途：界面根容器按此值留白，避免标题/底部按钮被刘海或系统手势条切掉。
## 注：窗口尺寸变化后需重新取值（配合 NOTIFICATION_RESIZED 或每帧读取）。
func get_safe_area_margins() -> Vector4:
	var win_size: Vector2i = DisplayServer.window_get_size()
	var safe: Rect2i = DisplayServer.get_display_safe_area()
	return Vector4(
		float(maxi(safe.position.x, 0)),
		float(maxi(safe.position.y, 0)),
		float(maxi(win_size.x - safe.end.x, 0)),
		float(maxi(win_size.y - safe.end.y, 0))
	)

## 把安全区边距应用到某个 Control（改其 offset，需该 Control 已用锚点预设铺满父容器）
## 用法：界面根节点在 _ready 里调用 UIManager.apply_safe_area(self)
func apply_safe_area(root: Control) -> void:
	if root == null:
		return
	var m: Vector4 = get_safe_area_margins()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.offset_left = m.x
	root.offset_top = m.y
	root.offset_right = -m.z
	root.offset_bottom = -m.w

## 当前置顶的全屏界面（供界面在 _unhandled_input 里判断自己是否处于顶层，避免被遮挡时仍响应输入）
func get_current_screen() -> Control:
	_prune_invalid()
	return _current_screen

## 是否存在任意已打开的界面（游戏内 overlay 用此门控移动输入）
func is_any_screen_open() -> bool:
	_prune_invalid()
	return not _screen_stack.is_empty()

## 按注册名查找当前已打开的界面实例（未打开返回 null）；供同键开关判断
func get_open_screen(screen_name: String) -> Control:
	_prune_invalid()
	for s in _screen_stack:
		if is_instance_valid(s) and s.name == screen_name:
			return s as Control
	return null

func open_screen(screen_name: String, layer: int = Layer.FULLSCREEN, init_data: Variant = null) -> Control:
	if not _screen_paths.has(screen_name):
		GameLogger.error("UIManager", "未注册界面: %s" % screen_name)
		return null
	var script: Script = load(_screen_paths[screen_name]) as Script
	if script == null:
		GameLogger.error("UIManager", "界面脚本加载失败: %s" % screen_name)
		return null
	var screen: Control = script.new() as Control
	screen.name = screen_name
	# 初始化数据（如界面模式 save/load）：若有 _on_open 方法则注入，避免界面硬编码打开上下文
	if init_data != null and screen.has_method("_on_open"):
		screen._on_open(init_data)
	var canvas: CanvasLayer = get_layer(layer)
	if canvas == null:
		GameLogger.error("UIManager", "UI 层级不存在: %d" % layer)
		return null
	canvas.add_child(screen)
	_screen_stack.append(screen)
	_screen_layer[screen] = layer
	_current_screen = screen
	# 统一淡入转场：界面进入时从透明渐显，时长与缓动读 ui_anim.json 的 screen 预设
	screen.modulate.a = 0.0
	screen.show()
	var enter_tween := create_tween()
	enter_tween.set_trans(ConfigManager.get_anim_trans(_screen_easing()))
	enter_tween.set_ease(ConfigManager.get_anim_ease(_screen_easing()))
	enter_tween.tween_property(screen, "modulate:a", 1.0, _screen_fade_duration(true))
	return screen

## 界面转场时长（秒），读 ui_anim.json 的 screen 预设；配置缺失时退回 0.25
func _screen_fade_duration(is_enter: bool) -> float:
	var preset: Dictionary = ConfigManager.get_anim_preset("screen")
	var key: String = "fade_in_duration" if is_enter else "fade_out_duration"
	return ConfigManager.get_anim_duration(String(preset.get(key, "screen")), 0.25)

## 界面转场缓动令牌名
func _screen_easing() -> String:
	return String(ConfigManager.get_anim_preset("screen").get("easing", "smooth"))

func close_screen(screen: Control = null, on_closed: Callable = Callable()) -> void:
	_prune_invalid()
	var target: Control = screen if screen != null else _current_screen
	if target == null or not is_instance_valid(target):
		return
	_screen_stack.erase(target)
	_screen_layer.erase(target)
	# 先让出焦点/输入：更新栈顶，避免关闭动画期间残留响应
	if not _screen_stack.is_empty():
		_current_screen = _screen_stack.back() as Control
	else:
		_current_screen = null
	# 统一淡出转场：渐隐后释放，并触发 on_closed 回调（如切场景）；时长/缓动同读 screen 预设
	target.modulate.a = 1.0
	var exit_tween := create_tween()
	exit_tween.set_trans(ConfigManager.get_anim_trans(_screen_easing()))
	exit_tween.set_ease(ConfigManager.get_anim_ease(_screen_easing()))
	exit_tween.tween_property(target, "modulate:a", 0.0, _screen_fade_duration(false))
	exit_tween.tween_callback(func():
		if is_instance_valid(target):
			target.queue_free()
		if on_closed.is_valid():
			on_closed.call()
	)

## 清理界面栈中已销毁（freed）或失效的引用，避免后续访问销毁对象时触发 "Trying to cast a freed object"
## 任何界面若绕过 close_screen 直接 queue_free（历史代码/组件自销毁），都会在此被兜底清除
func _prune_invalid() -> void:
	var valid: Array = []
	for s in _screen_stack:
		if is_instance_valid(s):
			valid.append(s)
		else:
			_screen_layer.erase(s)
	_screen_stack = valid
	if _screen_stack.is_empty():
		_current_screen = null
	elif not is_instance_valid(_current_screen):
		_current_screen = _screen_stack.back() as Control

func show_popup(popup_name: String) -> Control:
	return open_screen(popup_name, Layer.POPUP)

## 关闭栈内全部界面（读档/新游戏时调用：连同底层主菜单一并释放，避免残留遮挡）
func close_all_screens() -> void:
	_prune_invalid()
	for screen in _screen_stack:
		if is_instance_valid(screen):
			(screen as Control).queue_free()
	_screen_stack.clear()
	_screen_layer.clear()
	_current_screen = null

## 是否有弹窗（POPUP 层级界面）处于打开中；供底层界面在 _unhandled_input 判断是否让权
func is_popup_open() -> bool:
	_prune_invalid()
	for screen in _screen_stack:
		if _screen_layer.get(screen, -1) == Layer.POPUP:
			return true
	return false

## 轻量通知 Toast（EventBus.notification_show 自动接入）：顶部居中淡入，2.2s 后淡出
func show_tooltip(text: String) -> void:
	if text == "":
		return
	var layer: CanvasLayer = get_layer(Layer.TOOLTIP)
	if layer == null:
		return
	var toast: Label = Label.new()
	toast.text = text
	toast.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	toast.add_theme_font_size_override("font_size", 16)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.0, 0.0, 0.0, 0.82)
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GOLD
	toast.add_theme_stylebox_override("normal", sb)
	toast.add_theme_constant_override("margin_left", 16)
	toast.add_theme_constant_override("margin_top", 10)
	toast.add_theme_constant_override("margin_right", 16)
	toast.add_theme_constant_override("margin_bottom", 10)
	toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	toast.anchor_left = 0.5
	toast.anchor_top = 0.0
	toast.anchor_right = 0.5
	toast.anchor_bottom = 0.0
	toast.offset_left = -160.0
	toast.offset_top = 20.0
	toast.offset_right = 160.0
	toast.offset_bottom = 60.0
	toast.modulate.a = 0.0
	layer.add_child(toast)
	var tween := create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.2)
	tween.tween_property(toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(toast.queue_free)

func hide_tooltip() -> void:
	pass
