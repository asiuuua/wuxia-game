# autoload/settings_manager.gd
# 设置管理器：集中保存/读取玩家设置（落 user://settings.json，不污染项目资源）
# 覆盖：音频音量 / 画面 / 控制键位 / 游戏偏好 / 语言
# 实时生效：任何 set_* 都会立即应用到对应系统并自动落盘
# 注意：autoload 脚本不写 class_name（避免与单例名冲突）

extends Node

const SAVE_PATH := "user://settings.json"

# 可重绑定的动作（键位偏好来源；实际 InputMap 在游戏内由 TownScene 注册默认，这里仅存偏好并尽力应用）
const REBINDABLE_ACTIONS := ["move_up", "move_down", "move_left", "move_right", "toggle_inventory", "toggle_map", "toggle_attributes"]

# 默认键位（KEY_* 全局常量）
const DEFAULT_BINDINGS := {
	"move_up": KEY_W,
	"move_down": KEY_S,
	"move_left": KEY_A,
	"move_right": KEY_D,
	"toggle_inventory": KEY_B,
	"toggle_map": KEY_M,
	"toggle_attributes": KEY_TAB,
}

# 分辨率候选（窗口/最大化模式下的窗口像素尺寸；全屏时由系统决定）
const RESOLUTIONS := ["1280x720", "1366x768", "1600x900", "1920x1080", "2560x1440", "3840x2160"]
const DISPLAY_MODES := ["windowed", "fullscreen", "maximized"]
# 显示模式存储值 → 界面中文标签（避免设置里直接显示英文原值）
const DISPLAY_MODE_LABELS := {
	"windowed": "gfx_mode_windowed",
	"fullscreen": "gfx_mode_fullscreen",
	"maximized": "gfx_mode_maximized",
}
# 渲染分辨率（内部渲染倍率）：>1 超采样更锐利但更吃 GPU；<1 降分辨率提速但略糊
const RENDER_SCALES := [0.75, 1.0, 1.25, 1.5, 2.0]
const RENDER_SCALE_LABELS := {
	0.75: "gfx_rs_075",
	1.0: "gfx_rs_100",
	1.25: "gfx_rs_125",
	1.5: "gfx_rs_150",
	2.0: "gfx_rs_200",
}
# UI 缩放（界面/文字大小倍率）：与 3D 渲染分辨率**完全独立**
# 2026-08-29 拆分：此前 render_scale 被误赋给 content_scale_factor，
# 导致玩家为提帧调低渲染倍率时 UI 跟着缩小发虚。二者必须各走各的。
const UI_SCALES := [0.75, 1.0, 1.25, 1.5]
const UI_SCALE_LABELS := {
	0.75: "gfx_ui_075",
	1.0: "gfx_ui_100",
	1.25: "gfx_ui_125",
	1.5: "gfx_ui_150",
}
# Window.content_scale_stretch 枚举（Godot 4.7+）：FRACTIONAL=0 / INTEGER=1
# 旧 content_scale_mode + FRACTIONAL=1 已在 4.7 改名为 content_scale_stretch + FRACTIONAL=0
const CONTENT_SCALE_STRETCH_FRACTIONAL := 0
const QUALITY_LEVELS := ["low", "medium", "high", "ultra"]
const DIFFICULTY_LEVELS := ["easy", "normal", "hard"]
const TEXT_SPEED_LEVELS := ["slow", "normal", "fast"]
const LOCALES := ["zh_CN", "zh_TW", "en"]

# 设置数据（嵌套字典，单一真相源）
var data: Dictionary = {
	"audio": {"master": 0.8, "music": 0.6, "sfx": 0.8, "voice": 1.0},
	"graphics": {"resolution": "1920x1080", "display_mode": "fullscreen", "vsync": true, "fps_limit": 60, "quality": "high", "render_scale": 1.0, "ui_scale": 1.0},
	"control": {"bindings": {}},
	"game": {"difficulty": "normal", "autosave": true, "autosave_interval": 300, "text_speed": "normal"},
	"language": {"locale": "zh_CN"},
}

func _ready() -> void:
	load_settings()
	# 用已存偏好补全默认键位（未改过则用默认）
	for action in REBINDABLE_ACTIONS:
		if not data["control"]["bindings"].has(action):
			data["control"]["bindings"][action] = DEFAULT_BINDINGS[action]
	apply_audio()
	# 画面/窗口设置依赖主窗口就绪，延后一帧确保窗口已创建（避免 _ready 期窗口为空导致设置失效）
	call_deferred("apply_graphics")

## 读取磁盘设置并合并到 data（缺失字段保留默认值）
func load_settings() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not (parsed is Dictionary):
		GameLogger.warn("Settings", "设置文件解析失败，使用默认: %s" % SAVE_PATH)
		return
	_merge_dict(data, parsed)

## 写盘（自动调用，无需手动）
func save_settings() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		GameLogger.warn("Settings", "无法写入设置: %s" % SAVE_PATH)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()

# ===== 音频 =====
func get_audio_volume(category: String) -> float:
	return float(data["audio"].get(category, 0.8))

func set_audio_volume(category: String, value: float) -> void:
	var v: float = clampf(value, 0.0, 1.0)
	data["audio"][category] = v
	if AudioManager != null and AudioManager.has_method("set_bus_volume"):
		AudioManager.set_bus_volume(category.capitalize(), v)
	save_settings()

func apply_audio() -> void:
	for category in data["audio"].keys():
		if AudioManager != null and AudioManager.has_method("set_bus_volume"):
			AudioManager.set_bus_volume(category.capitalize(), float(data["audio"][category]))

# ===== 画面 =====
func get_graphics(key: String):
	return data["graphics"].get(key, null)

func set_graphics(key: String, value) -> void:
	data["graphics"][key] = value
	apply_graphics()
	save_settings()

func apply_graphics() -> void:
	if Engine.is_editor_hint():
		return
	var window: Window = get_window()
	if window == null:
		# 主窗口尚未就绪，下一帧重试（启动早期常见）
		call_deferred("apply_graphics")
		return

	# 解析目标分辨率（仅窗口/最大化模式生效；全屏时由系统决定尺寸）
	var res_str: String = str(data["graphics"]["resolution"])
	var target_size: Vector2i = Vector2i(1920, 1080)
	if res_str.contains("x"):
		var parts: PackedStringArray = res_str.split("x")
		if parts.size() == 2:
			var w: int = int(parts[0])
			var h: int = int(parts[1])
			if w > 0 and h > 0:
				target_size = Vector2i(w, h)

	# 显示模式：先退出全屏到窗口态再设尺寸（全屏态下 window_set_size 无效，
	# 这是「切到窗口分辨率不生效」的常见根因）；最大化时在设好尺寸后再置最大化（尺寸被忽略，仅占位）
	var mode_str: String = str(data["graphics"]["display_mode"])
	var mode: int = DisplayServer.WINDOW_MODE_WINDOWED
	match mode_str:
		"fullscreen": mode = DisplayServer.WINDOW_MODE_FULLSCREEN
		"maximized": mode = DisplayServer.WINDOW_MODE_MAXIMIZED
		_: mode = DisplayServer.WINDOW_MODE_WINDOWED

	if mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		DisplayServer.window_set_size(target_size)
		if mode == DisplayServer.WINDOW_MODE_MAXIMIZED:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)

	# 垂直同步
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if bool(data["graphics"]["vsync"]) else DisplayServer.VSYNC_DISABLED)
	# 帧率限制
	Engine.max_fps = int(data["graphics"]["fps_limit"])

	# 3D 渲染分辨率倍率：只影响 3D 画面精度（Viewport.scaling_3d_scale），**不动 2D 界面**
	var rs: float = float(data["graphics"].get("render_scale", 1.0))
	window.scaling_3d_scale = clampf(rs, 0.5, 4.0)

	# UI 缩放：只影响 2D 界面与文字大小（content_scale_factor），**与 3D 渲染分辨率互不相干**
	# 分数模式允许任意取值；整数模式更锐利但只能整倍缩放
	window.content_scale_stretch = CONTENT_SCALE_STRETCH_FRACTIONAL as Window.ContentScaleStretch
	var us: float = float(data["graphics"].get("ui_scale", 1.0))
	window.content_scale_factor = clampf(us, 0.5, 4.0)

# ===== 控制 / 键位 =====
func get_binding(action: String) -> int:
	return int(data["control"]["bindings"].get(action, -1))

func rebind(action: String, keycode: int) -> void:
	data["control"]["bindings"][action] = keycode
	_apply_one_binding(action, keycode)
	save_settings()

## 把偏好尽力应用到当前 InputMap（动作存在才改，避免游戏内默认覆盖问题——TownScene 注册默认后此偏好应在进入场景前生效）
func apply_bindings() -> void:
	for action in data["control"]["bindings"].keys():
		_apply_one_binding(action, int(data["control"]["bindings"][action]))

func _apply_one_binding(action: String, keycode: int) -> void:
	if not InputMap.has_action(action):
		return
	# 清掉现有键盘绑定（保留非键盘事件）
	var events: Array = InputMap.action_get_events(action)
	for ev in events:
		if ev is InputEventKey:
			InputMap.action_erase_event(action, ev)
	var new_event := InputEventKey.new()
	new_event.keycode = keycode
	InputMap.action_add_event(action, new_event)

# ===== 游戏偏好 =====
func get_game(key: String):
	return data["game"].get(key, null)

func set_game(key: String, value) -> void:
	data["game"][key] = value
	save_settings()

## 恢复某分类到默认值并立即应用+落盘
func reset_category(category: String) -> void:
	match category:
		"audio":
			data["audio"] = {"master": 0.8, "music": 0.6, "sfx": 0.8, "voice": 1.0}
			apply_audio()
		"graphics":
			data["graphics"] = {"resolution": "1920x1080", "display_mode": "fullscreen", "vsync": true, "fps_limit": 60, "quality": "high", "render_scale": 1.0, "ui_scale": 1.0}
			apply_graphics()
		"control":
			data["control"]["bindings"] = {}
			for action in REBINDABLE_ACTIONS:
				data["control"]["bindings"][action] = DEFAULT_BINDINGS[action]
			apply_bindings()
		"game":
			data["game"] = {"difficulty": "normal", "autosave": true, "autosave_interval": 300, "text_speed": "normal"}
		"language":
			data["language"] = {"locale": "zh_CN"}
			set_language("zh_CN")
	save_settings()

# ===== 语言 =====
func get_language() -> String:
	return str(data["language"]["locale"])

func set_language(locale: String) -> void:
	if not LOCALES.has(locale):
		locale = "zh_CN"
	data["language"]["locale"] = locale
	TranslationServer.set_locale(locale)
	save_settings()

# ===== 工具 =====
## 深合并 parsed 到 base（仅覆盖已存在键，不动 base 的结构类型约束）
func _merge_dict(base: Dictionary, parsed: Dictionary) -> void:
	for key in parsed.keys():
		if not base.has(key):
			base[key] = parsed[key]
			continue
		if base[key] is Dictionary and parsed[key] is Dictionary:
			_merge_dict(base[key], parsed[key])
		else:
			base[key] = parsed[key]
