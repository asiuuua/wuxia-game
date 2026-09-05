# core/kernel/error/operation_error.gd
# Kernel 契约（02 图 §3.2）：错误对象。
# 至少包含 error_code + context；适用时带 causation / correlation / transaction_id。

class_name OperationError
extends RefCounted

var _code: StringName
var _message: String                 # 仅供日志与玩家展示，禁止用于业务判断
var _context: Dictionary             # 【Dynamic Data Boundary K-DB-01】禁止承载业务判断依据
var _correlation_id: StringName
var _causation_id: StringName
var _transaction_id: StringName

func _init(
	code: StringName,
	message: String = "",
	context: Dictionary = {},
	correlation_id: StringName = &"",
	causation_id: StringName = &"",
	transaction_id: StringName = &""
) -> void:
	_code = code
	_message = message
	_context = context
	_correlation_id = correlation_id
	_causation_id = causation_id
	_transaction_id = transaction_id

func get_code() -> StringName:
	return _code

func get_message() -> String:
	return _message

func get_context() -> Dictionary:
	return _context

func get_correlation_id() -> StringName:
	return _correlation_id

func get_causation_id() -> StringName:
	return _causation_id

func get_transaction_id() -> StringName:
	return _transaction_id

func has_code(code: StringName) -> bool:
	return _code == code
