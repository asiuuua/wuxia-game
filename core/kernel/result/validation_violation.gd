# core/kernel/result/validation_violation.gd
# Kernel 契约（02 图 §4.4）：强类型校验违约项。禁止用 Dictionary 表达。

class_name ValidationViolation
extends RefCounted

var _code: StringName
var _field: StringName
var _detail: String

func _init(code: StringName, field: StringName, detail: String = "") -> void:
	_code = code
	_field = field
	_detail = detail

func get_code() -> StringName:
	return _code

func get_field() -> StringName:
	return _field

func get_detail() -> String:
	return _detail
