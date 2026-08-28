# core/utils/game_logger.gd
# 统一日志工具（规范 §4.3）：替代散落的 print，控制台 + 文件双输出，支持日志轮转。
# 使用约定：所有模块打日志统一走 GameLogger，禁止裸 print（见 docs/开发规范.md）。

class_name GameLogger
extends RefCounted

enum Level { DEBUG, INFO, WARN, ERROR, FATAL }

const LOG_TO_FILE: bool = true
const LOG_FILE_PATH := "user://logs/game.log"
const MAX_LOG_FILES: int = 5
const MAX_LOG_SIZE: int = 10 * 1024 * 1024  # 10MB

static var _log_file: FileAccess = null
static var _current_level: int = Level.DEBUG

## 启动日志系统：轮转旧日志并打开当前日志文件
static func setup() -> void:
	_rotate_logs()
	if LOG_TO_FILE:
		_log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
		if _log_file != null:
			_log_file.seek_end()
			_write_header()

static func debug(module: String, message: String) -> void:
	_log(Level.DEBUG, module, message)

static func info(module: String, message: String) -> void:
	_log(Level.INFO, module, message)

static func warn(module: String, message: String) -> void:
	_log(Level.WARN, module, message)
	push_warning("[%s] %s" % [module, message])

static func error(module: String, message: String) -> void:
	_log(Level.ERROR, module, message)
	push_error("[%s] %s" % [module, message])

## 致命错误：记录日志并广播 game_error，由 ErrorHandler 弹窗处理
static func fatal(module: String, message: String) -> void:
	_log(Level.FATAL, module, message)
	push_error("[FATAL][%s] %s" % [module, message])
	EventBus.game_error.emit(GameErrorLevel.FATAL, module, message)

static func _log(level: int, module: String, message: String) -> void:
	if level < _current_level:
		return
	var time_str: String = Time.get_time_string_from_system()
	var level_str: String = _level_to_string(level)
	var log_line: String = "[%s][%s][%s] %s" % [time_str, level_str, module, message]
	print(log_line)
	if _log_file != null and LOG_TO_FILE:
		_log_file.store_line(log_line)
		_check_log_size()

static func _level_to_string(level: int) -> String:
	match level:
		Level.DEBUG: return "DEBUG"
		Level.INFO: return "INFO"
		Level.WARN: return "WARN"
		Level.ERROR: return "ERROR"
		Level.FATAL: return "FATAL"
	return "UNKNOWN"

static func _write_header() -> void:
	if _log_file == null:
		return
	var sep: String = "=".repeat(60)
	_log_file.store_line(sep)
	_log_file.store_line("Game Log - %s" % Time.get_date_string_from_system())
	_log_file.store_line("Godot Version: %s" % Engine.get_version_info()["string"])
	_log_file.store_line("Platform: %s" % OS.get_name())
	_log_file.store_line(sep)

## 保留最近 MAX_LOG_FILES 个日志：.1->.2->...->.4，当前->.1
static func _rotate_logs() -> void:
	for i in range(MAX_LOG_FILES - 1, 0, -1):
		var old_path: String
		if i > 1:
			old_path = LOG_FILE_PATH + ".%d" % (i - 1)
		else:
			old_path = LOG_FILE_PATH
		var new_path: String = LOG_FILE_PATH + ".%d" % i
		if FileAccess.file_exists(old_path):
			DirAccess.copy_absolute(old_path, new_path)

static func _check_log_size() -> void:
	if _log_file == null:
		return
	if _log_file.get_position() > MAX_LOG_SIZE:
		_log_file.close()
		_rotate_logs()
		_log_file = FileAccess.open(LOG_FILE_PATH, FileAccess.WRITE)
