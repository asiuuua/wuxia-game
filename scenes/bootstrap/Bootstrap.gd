# scenes/bootstrap/Bootstrap.gd
# 启动入口（规范 §4.1）：按依赖顺序执行初始化步骤，发射生命周期信号，完成后进入主菜单。
# 仅登记当前已存在的模块；Phase 2 接入 input/localization/ui/scene/debug 后追加步骤。

extends Node
class_name Bootstrap


# 图标解析引擎（scenes/ui 层，UI 窗口主权）。本组合根在运行时经 EventBus 把它注入 UIManager，
# 以依赖反转消除"基础层 UIManager 静态依赖 scenes/ui"的唯一真实架构违例（2026-09-02 治理）。
const IconRegistry = preload("res://scenes/ui/icon_registry.gd")

var _init_sequence: Array[Dictionary] = []
var _current_step: int = 0
var _is_bootstrapping: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	GameLogger.setup()
	# 先让场景树稳定一帧，确保 UIManager 的层级已就绪
	await get_tree().process_frame
	# 架构治理（2026-09-02）：UIManager 已 _ready 并连好 EventBus，此刻把图标解析器
	# 经 EventBus 注入（依赖反转），此后 UIManager.get_icon 取真实图标而非占位兜底。
	EventBus.icon_provider_registered.emit(Callable(IconRegistry, "get_icon"), Callable(IconRegistry, "has_icon"))
	# 打开加载界面（覆盖层），进度由 bootstrap 信号驱动
	UIManager.open_screen("LoadingScreen", UIManager.Layer.FULLSCREEN)
	# 再等一帧，确保 LoadingScreen._ready 已连接 bootstrap 信号
	await get_tree().process_frame
	_build_init_sequence()
	await _start_bootstrap()

func _build_init_sequence() -> void:
	# 顺序即依赖顺序：前一个完成后才进入下一个
	_init_sequence = [
		{"name": "core_constants", "func": "_init_core_constants"},
		{"name": "event_bus", "func": "_init_event_bus"},
		{"name": "config_manager", "func": "_init_config_manager"},
		{"name": "save_manager", "func": "_init_save_manager"},
		{"name": "audio_manager", "func": "_init_audio_manager"},
		{"name": "error_handler", "func": "_init_error_handler"},
		{"name": "game_services", "func": "_init_game_services"},
	]

func _start_bootstrap() -> void:
	_is_bootstrapping = true
	_current_step = 0
	EventBus.bootstrap_started.emit(_init_sequence.size())
	await _execute_next_step()

func _execute_next_step() -> void:
	if _current_step >= _init_sequence.size():
		_on_bootstrap_complete()
		return
	var step: Dictionary = _init_sequence[_current_step]
	EventBus.bootstrap_step_started.emit(step.name, _current_step)
	call(step.func)
	EventBus.bootstrap_step_completed.emit(step.name, _current_step)
	_current_step += 1
	# 步骤间留出时间，让加载进度条可见地推进（而非瞬间跳满）
	await get_tree().create_timer(0.15).timeout
	await _execute_next_step()

# === 各初始化步骤（真实模块才执行；其余 pass 保持序列可读、不造空引用） ===
func _init_core_constants() -> void:
	pass  # 常量类随脚本加载即就绪

func _init_event_bus() -> void:
	pass  # EventBus 为 Autoload，已在场景树就绪

func _init_config_manager() -> void:
	# ConfigManager 在自身 _ready 完成配置加载与索引构建，此处仅做可达性确认
	if not ConfigManager.is_loaded():
		GameLogger.warn("Bootstrap", "ConfigManager 尚未就绪")

func _init_save_manager() -> void:
	# 可存档对象由 GameManager._register_saveables 注册，此处确认完整性
	if SaveManager.get_saveable_count() == 0:
		GameLogger.warn("Bootstrap", "SaveManager 无可存档对象")

func _init_audio_manager() -> void:
	AudioManager.setup()

func _init_error_handler() -> void:
	ErrorHandler.setup()

func _init_game_services() -> void:
	if GameManager.player_state == null:
		GameLogger.error("Bootstrap", "player_state 未初始化")
		return
	GameLogger.info("Bootstrap", "游戏服务已就绪 (v%s)" % str(ProjectSettings.get_setting("application/config/version", "?")))

func _on_bootstrap_complete() -> void:
	_is_bootstrapping = false
	EventBus.bootstrap_completed.emit()
	# 不再切场景：由 LoadingScreen 接管，用户点击后进入主菜单
