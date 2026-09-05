# core/kernel/result/validation_result.gd
# Kernel 契约（02 图 §4.4）：校验结果。violations 为强类型数组（禁 Dictionary 表达）。

class_name ValidationResult
extends OperationResult

var _violations: Array[ValidationViolation] = []

func _init(ok: bool, error: OperationError, violations: Array[ValidationViolation] = []) -> void:
	super(ok, error)
	_violations = violations

func get_violations() -> Array[ValidationViolation]:
	return _violations

func is_valid() -> bool:
	return _ok and _violations.is_empty()
