# autoload/ui_manager.gd
# UI 管理器（autoload，不写 class_name —— 避免与单例名冲突解析失败，今日 08-27 刚踩此坑）
# 职责：维护 6 个 CanvasLayer 层级，提供全屏界面栈的打开/关闭。
# 界面登记在 data/configs/ui/screens.json：值统一为「场景路径(.tscn)」（B 路线复合控件）。
# open_screen 仅支持 .tscn：load().instantiate() 后挂到对应层级；非法扩展名（非 .tscn）直接报错返回 null。
# 2026-08-30 收尾：全量界面已迁 .tscn，旧的 .gd / script.new() 分支已删除，不再兼容脚本路径。
#
# 2026-08-29 P2 弹窗生命周期：screens.json 支持 {path, cache} 写法；cache=true 的界面关闭时
# 仅隐藏、保留在层上（_screen_cache），重开复用，不销毁——高频弹窗（设置/存档）省重建开销；
# cache=false（默认）关闭即 queue_free 彻底释放，避免内存堆积。弹窗关闭统一走
# EventBus.popup_close_requested（PopupBase 发出），UIManager 收口，弹窗自身不销毁自己。

@warning_ignore("shadowed_global_identifier")

extends Node

# 渲染层级：枚举值 * 10 = CanvasLayer.layer 真实值。
# 注意：值已显式固定，新增层级只能"插入"，不可改动已有项的值（否则 get_layer / open_screen 调用错位）。
enum Layer {
	BACKGROUND = 0,        # 0    游戏世界底（TileMap/角色/NPC/Camera2D）
	HUD = 5,               # 50   常驻 HUD（状态卡/任务追踪/右上菜单/技能栏），屏幕固定、不受 Camera2D 影响
	TRANSITION = 10,       # 100  场景淡入淡出转场遮罩
	FULLSCREEN = 20,       # 200  全屏界面（背包/结缘/菜单/任务…）
	POPUP = 30,            # 300  弹窗（确认框等）
	TOOLTIP = 40,          # 400  Toast / 浮动提示
	SYSTEM_OVERLAY = 50,   # 500  系统级浮层（严重告警）
}

const SCREENS_FILE := "res://data/configs/ui/screens.json"
const UIPalette = preload("res://core/constants/ui_theme.gd")
# 图标解析引擎（美术接入预留接口）：任何图标只经此取，禁在代码里写死 load(png)
const IconRegistry = preload("res://scenes/ui/icon_registry.gd")

var _layers: Dictionary = {}         # int(layer) -> CanvasLayer
var _screen_paths: Dictionary = {}   # 界面名 -> 脚本路径（或 {path, cache} 对象）
var _screen_stack: Array = []        # 打开中的全屏界面（Control）
var _screen_layer: Dictionary = {}   # Control -> 所在层级（用于判断弹窗是否打开）
var _current_screen: Control = null
var _hud: Control = null             # 当前常驻 HUD（挂在 HUD 层；autoload 跨场景常驻，须显式 unmount 释放）
var _screen_cache: Dictionary = {}   # 缓存模式弹窗实例（key=界面名）：关闭仅隐藏、保留层上，重开复用不销毁
var _exit_tweens: Dictionary = {}    # 进行中的关闭补间（key=界面实例）；重开缓存实例时 kill，避免把复用实例误隐藏

func _ready() -> void:
	_init_layers()
	_load_screen_registry()
	EventBus.notification_show.connect(show_tooltip)
	# 背包溢出全局订阅：掉落/发奖/任何 add_item 满包时不再静默丢物，统一弹 Toast 提示玩家
	EventBus.inventory_add_overflow.connect(_on_inventory_add_overflow)
	EventBus.ui_action_requested.connect(_on_ui_action_requested)
	EventBus.popup_close_requested.connect(_on_popup_close_requested)

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

## 把常驻 HUD 根节点挂到 HUD 层（屏幕固定位置，Camera2D 无关）。
## 该层是 autoload 的 CanvasLayer、跨场景常驻，HUD 不随场景树释放，故切场景时由挂载方在 _exit_tree 调 unmount_hud() 释放。
## 重复挂载会先释放旧 HUD，避免"双 HUD"残留。
func mount_hud(hud: Control) -> void:
	var layer_canvas: CanvasLayer = get_layer(Layer.HUD)
	if layer_canvas == null:
		GameLogger.error("UIManager", "HUD 层不存在，无法挂载常驻 HUD")
		return
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
	_hud = hud
	layer_canvas.add_child(hud)

## 释放当前常驻 HUD（切场景 / 退主菜单时调用）。
func unmount_hud() -> void:
	if _hud != null and is_instance_valid(_hud):
		_hud.queue_free()
		_hud = null

## 取图标纹理（美术接入预留接口）。id 形如 "skills/fire_sword"（不含扩展名）。
## 找不到返回占位图，绝不返回 null。其它窗口统一经此取图标，禁写死 load(png)。
func get_icon(icon_id: String) -> Texture2D:
	return IconRegistry.get_icon(icon_id)

## 是否存在某图标文件（供 UI 判断是否绘制图标框）
func has_icon(icon_id: String) -> bool:
	return IconRegistry.has_icon(icon_id)

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

## 解析界面注册项（screens.json 兼容两种写法：纯路径字符串 或 {path, cache} 对象）
## cache=true 表示「缓存模式」：关闭仅隐藏、保留在层上，重开复用，不销毁（省重建开销）
func _resolve_screen(screen_name: String) -> Dictionary:
	if not _screen_paths.has(screen_name):
		return {}
	var v: Variant = _screen_paths[screen_name]
	if v is String:
		return {"path": v, "cache": false}
	if v is Dictionary:
		var d: Dictionary = v
		return {"path": String(d.get("path", "")), "cache": bool(d.get("cache", false))}
	return {}

func open_screen(screen_name: String, layer: int = Layer.FULLSCREEN, init_data: Variant = null) -> Control:
	var entry: Dictionary = _resolve_screen(screen_name)
	if entry.is_empty() or String(entry.get("path", "")) == "":
		GameLogger.error("UIManager", "未注册界面: %s" % screen_name)
		return null
	# BUG-02 防重复打开：界面已在打开栈中（当前可见）则直接返回现有实例，
	# 避免背包等非缓存界面被二次 instantiate 导致实例叠加 + 信号双重监听（叠加闪烁/焦点错乱）。
	for s in _screen_stack:
		if is_instance_valid(s) and s.name == screen_name:
			return s
	var cached: Control = _screen_cache.get(screen_name, null) as Control
	var screen: Control
	if bool(entry.get("cache", false)) and cached != null and is_instance_valid(cached):
		# 缓存模式复用：实例已在层上（关闭时被隐藏），恢复显示并重跑打开钩子
		screen = cached
		screen.visible = true
		screen.modulate.a = 0.0
		# 重开时 kill 进行中的关闭补间，避免动画结束后把复用实例误隐藏
		if _exit_tweens.has(screen):
			var pt: Variant = _exit_tweens[screen]
			if pt != null and is_instance_valid(pt):
				(pt as Tween).kill()
			_exit_tweens.erase(screen)
		if init_data != null and screen.has_method("_on_open"):
			screen._on_open(init_data)
		elif screen.has_method("_on_reopen"):
			screen._on_reopen()
		# 缓存复用分支必须把屏幕补回栈/层/当前屏追踪：关闭时 close_screen 已从
		# _screen_stack/_screen_layer 移除并更新了 _current_screen，若不补回，重开的
		# 缓存屏会让 is_any_screen_open() 误报 false，且 BaseScreen 键盘守卫
		# get_current_screen()!=self 成立 → 键盘上下/确认/取消全部失效（Critical 回归）
		if not _screen_stack.has(screen):
			_screen_stack.append(screen)
		_screen_layer[screen] = layer
		_current_screen = screen
	else:
		var path: String = String(entry.get("path", ""))
		# B 路线（2026-08-29 收尾）：全量界面已迁 .tscn，不再支持 .gd 脚本路径。
		# 若登记的不是 .tscn 复合控件场景，直接报错返回，避免静默走旧 new() 分支。
		if not path.ends_with(".tscn"):
			GameLogger.error("UIManager", "界面必须为 .tscn 复合控件场景: %s (%s)" % [screen_name, path])
			return null
		var packed: PackedScene = load(path) as PackedScene
		if packed == null:
			GameLogger.error("UIManager", "界面场景加载失败: %s" % screen_name)
			return null
		screen = packed.instantiate() as Control
		screen.name = screen_name
		# 初始化数据（如界面模式 save/load）：若有 _on_open 方法则注入，避免界面硬编码打开上下文
		if init_data != null and screen.has_method("_on_open"):
			screen._on_open(init_data)
		var canvas: CanvasLayer = get_layer(layer)
		if canvas == null:
			GameLogger.error("UIManager", "UI 层级不存在: %d" % layer)
			return null
		canvas.add_child(screen)
		if bool(entry.get("cache", false)):
			_screen_cache[screen_name] = screen
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

## 取缓存模式实例（关闭后仍驻留内存、被隐藏）；非缓存/未打开返回 null（供测试与调试）
func get_cached_screen(screen_name: String) -> Control:
	var c: Variant = _screen_cache.get(screen_name, null)
	if c != null and is_instance_valid(c):
		return c as Control
	return null

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
	# 缓存模式判定：该实例是否仍登记在缓存里（关闭时只隐藏、不销毁）
	var name: String = target.name
	var target_id: int = target.get_instance_id()
	var is_cached: bool = _screen_cache.has(name) and is_instance_valid(_screen_cache.get(name, null)) and (_screen_cache[name] == target)
	var exit_tween := create_tween()
	exit_tween.set_trans(ConfigManager.get_anim_trans(_screen_easing()))
	exit_tween.set_ease(ConfigManager.get_anim_ease(_screen_easing()))
	exit_tween.tween_property(target, "modulate:a", 0.0, _screen_fade_duration(false))
	if is_cached:
		# 缓存模式：淡出后仅隐藏（节点保留在层上，下次 open_screen 复用），不释放，省重建开销
		# 用实例 id 代替直接捕获 target：避免转场期间 target 被其他路径释放导致 lambda 捕获失效
		exit_tween.tween_callback(func():
			var t: Control = instance_from_id(target_id) as Control
			if t != null:
				_exit_tweens.erase(t)
				t.visible = false
				t.modulate.a = 1.0   # 复位 alpha，下次打开直接显示，避免闪一下透明
			if on_closed.is_valid():
				on_closed.call()
		)
	else:
		# 销毁模式：淡出后彻底 queue_free，从场景树移除并释放显存内存（现有行为，防内存堆积）
		# 用实例 id 代替直接捕获 target：避免转场期 target 已被其他路径释放触发
		# "Lambda capture at index 0 was freed" 刷屏（实测 LoadingScreen→MainMenu 转场 4 次）
		exit_tween.tween_callback(func():
			var t: Control = instance_from_id(target_id) as Control
			if t != null:
				_exit_tweens.erase(t)
				t.queue_free()
			if on_closed.is_valid():
				on_closed.call()
		)
	_exit_tweens[target] = exit_tween

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
## 缓存弹窗一并释放，确保新游戏/读档后无残留隐藏节点（彻底释放，不占内存）
func close_all_screens() -> void:
	_prune_invalid()
	for screen in _screen_stack:
		if is_instance_valid(screen):
			(screen as Control).queue_free()
	_screen_stack.clear()
	_screen_layer.clear()
	_current_screen = null
	for c in _screen_cache.values():
		if is_instance_valid(c):
			(c as Control).queue_free()
	_screen_cache.clear()
	_exit_tweens.clear()

## 是否有弹窗（POPUP 层级界面）处于打开中；供底层界面在 _unhandled_input 判断是否让权
## 菜单/按钮动作路由（数据驱动）：UI 只 emit ui_action_requested(action_id)，此处据 menu_config.json 解析并派发。
## 不写死任何界面路径：screen 类走 open_screen；nav 类(battle/return_town)走 GameManager，绝不 change_scene（避"选2遍模式"类 bug）。
func _on_ui_action_requested(action_id: String) -> void:
	var item: Dictionary = ConfigManager.get_menu_item(action_id)
	if item.is_empty():
		GameLogger.warn("UIManager", "未知菜单动作: %s" % action_id)
		return
	var nav: String = String(item.get("nav", ""))
	if nav == "battle":
		GameManager.start_battle(String(item.get("battle_id", "")))
		return
	if nav == "return_town":
		GameManager.return_to_town()
		return
	var screen: String = String(item.get("screen", ""))
	if screen.is_empty():
		return
	var src: Control = get_open_screen("GameMenu")
	open_screen(screen, Layer.FULLSCREEN)
	if src != null and is_instance_valid(src):
		close_screen(src)

func is_popup_open() -> bool:
	_prune_invalid()
	for screen in _screen_stack:
		if _screen_layer.get(screen, -1) == Layer.POPUP:
			return true
	return false

## 弹窗请求关闭（PopupBase.request_close 发出）：只负责收口，弹窗自身绝不销毁自己
func _on_popup_close_requested(popup: Control) -> void:
	if popup == null or not is_instance_valid(popup):
		return
	close_screen(popup)

# Toast 对象池：避免每次通知都 new Label+StyleBox+tween 产生瞬时 GC 压力（性能极致优化）
var _toast_pool: Array = []

## 轻量通知 Toast（EventBus.notification_show 自动接入）：顶部居中淡入，2.2s 后淡出
func show_tooltip(text: String) -> void:
	if text == "":
		return
	var layer: CanvasLayer = get_layer(Layer.TOOLTIP)
	if layer == null:
		return
	var toast: Label
	if _toast_pool.is_empty():
		toast = Label.new()
		toast.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
		toast.add_theme_font_size_override("font_size", 16)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UIPalette.TOAST_BG
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
	else:
		toast = _toast_pool.pop_back()
		if toast.get_parent() != null:
			toast.get_parent().remove_child(toast)
	toast.text = text
	toast.modulate.a = 0.0
	layer.add_child(toast)
	var tween := create_tween()
	tween.tween_property(toast, "modulate:a", 1.0, 0.25)
	tween.tween_interval(2.2)
	tween.tween_property(toast, "modulate:a", 0.0, 0.3)
	tween.tween_callback(_recycle_toast.bind(toast))

## Toast 回收：从场景树摘下、归还对象池，下次通知复用（不再 queue_free）
func _recycle_toast(toast: Label) -> void:
	if toast == null or not is_instance_valid(toast):
		return
	if toast.get_parent() != null:
		toast.get_parent().remove_child(toast)
	_toast_pool.append(toast)

## 背包入包溢出（满包/超重导致物品丢失）：全局订阅，转成玩家可见的 Toast，避免静默丢物
func _on_inventory_add_overflow(item_id: String, lost_count: int) -> void:
	if lost_count <= 0:
		return
	var name_text: String = item_id
	var data: Variant = ConfigManager.get_item(item_id)
	if data != null and data is Dictionary:
		name_text = String(data.get("name", String(data.get("name_key", item_id))))
	EventBus.notification_show.emit(tr("ui_inventory_overflow") % [lost_count, name_text])

func hide_tooltip() -> void:
	pass
