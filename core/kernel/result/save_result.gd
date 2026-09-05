# core/kernel/result/save_result.gd
# Kernel 契约（02 图 §4.4）：存档结果（01 §69/70）。

class_name SaveResult
extends OperationResult

var _save_version: StringName
var _persisted_path: String

func _init(ok: bool, error: OperationError, save_version: StringName = &"", persisted_path: String = "") -> void:
	super(ok, error)
	_save_version = save_version
	_persisted_path = persisted_path

func get_save_version() -> StringName:
	return _save_version

func get_persisted_path() -> String:
	return _persisted_path
