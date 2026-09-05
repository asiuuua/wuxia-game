# core/kernel/result/query_result.gd
# Kernel 契约（02 图 §4.3）：Query 结果。
# 铁律：payload 必须是显式强类型的只读 Snapshot（RefCounted）。
#       禁止 Variant / Dictionary 作为载荷（宪法 0-B.2）。
#       get_payload_as 的 Variant 参数为 K-DB-03 登记项（仅用于类型校验）。

class_name QueryResult
extends OperationResult

var _payload: RefCounted   # 具体类型由 Query 契约声明，调用方按契约 downcast

func _init(ok: bool, error: OperationError, payload: RefCounted) -> void:
	super(ok, error)
	_payload = payload

static func success(payload: RefCounted) -> QueryResult:
	return QueryResult.new(true, null, payload)

static func not_found(code: StringName = ErrorCode.ITEM_NOT_FOUND) -> QueryResult:
	return QueryResult.new(false, OperationError.new(code), null)

func get_payload() -> RefCounted:
	return _payload

## 按契约取具体快照类型；类型不符返回 null（调用方必须处理）
func get_payload_as(expected_type: Variant) -> RefCounted:
	if _payload != null and is_instance_of(_payload, expected_type):
		return _payload
	return null
