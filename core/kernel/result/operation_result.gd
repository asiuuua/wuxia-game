# core/kernel/result/operation_result.gd
# Kernel 契约（02 图 §4.1）：所有 Kernel 结果类型的基类。
# 铁律（宪法 0-B.16）：禁止返回 true / false / null / Dictionary / String / Error 混合。

class_name OperationResult
extends RefCounted

var _ok: bool
var _error: OperationError

func _init(ok: bool, error: OperationError) -> void:
	_ok = ok
	_error = error

static func ok() -> OperationResult:
	return OperationResult.new(true, null)

static func fail(code: StringName, message: String = "", context: Dictionary = {}) -> OperationResult:
	return OperationResult.new(false, OperationError.new(code, message, context))

func is_ok() -> bool:
	return _ok

func is_failed() -> bool:
	return not _ok

func get_error() -> OperationError:
	return _error

func has_error_code(code: StringName) -> bool:
	return (not _ok) and _error != null and _error.has_code(code)
