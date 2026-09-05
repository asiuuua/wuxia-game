# autoload/error_handler.gd
# 全局错误兜底（13图SV域（旧§4.2.3编号已废））：监听 game_error，按级别分级处理。
# FATAL 弹窗并退出；ERROR 记录日志 + 通知；WARN 仅记录。

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

func _ready() -> void:
	EventBus.game_error.connect(_on_game_error)

## 幂等初始化入口（Bootstrap 可显式调用，_ready 已连接）
func setup() -> void:
	pass

func _on_game_error(level: int, module: String, message: String) -> void:
	match level:
		GameErrorLevel.FATAL:
			_show_fatal_error(module, message)
		GameErrorLevel.ERROR:
			GameLogger.error(module, message)
			EventBus.notification_show.emit("系统异常：%s" % message)
		GameErrorLevel.WARN:
			GameLogger.warn(module, message)
		_:
			GameLogger.info(module, message)

func _show_fatal_error(module: String, message: String) -> void:
	var dialog: AcceptDialog = AcceptDialog.new()
	dialog.title = "致命错误"
	dialog.dialog_text = "模块: %s\n错误: %s\n\n游戏无法继续运行，建议回滚到最近的自动存档。" % [module, message]
	dialog.confirmed.connect(_on_fatal_confirmed)
	get_tree().root.add_child(dialog)
	dialog.popup_centered()

func _on_fatal_confirmed() -> void:
	get_tree().quit()
