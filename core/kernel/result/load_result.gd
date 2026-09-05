# core/kernel/result/load_result.gd
# Kernel 契约（02 图 §4.4）：读档结果。payload 为强类型 SaveDTO（禁直接序列化 Runtime Object）。

class_name LoadResult
extends OperationResult

var _dto: RefCounted
var _migrated_from: StringName   # 若发生过迁移，记录来源版本；未迁移则为空

func _init(ok: bool, error: OperationError, dto: RefCounted = null, migrated_from: StringName = &"") -> void:
	super(ok, error)
	_dto = dto
	_migrated_from = migrated_from

func get_dto() -> RefCounted:
	return _dto

func was_migrated() -> bool:
	return _migrated_from != &""
