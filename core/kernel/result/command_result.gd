# core/kernel/result/command_result.gd
# Kernel 契约（02 图 §4.2）：Command 执行结果。
# 铁律（01 §19）：只有 Committed Event 才能出现在这里。
#       未 Commit 的事务，committed_events 必须为空数组（K-R13 / GATE26）。

class_name CommandResult
extends OperationResult

var _transaction_id: StringName
var _committed_events: Array[DomainEvent] = []

func _init(ok: bool, error: OperationError, transaction_id: StringName, committed_events: Array[DomainEvent]) -> void:
	super(ok, error)
	_transaction_id = transaction_id
	_committed_events = committed_events

## 成功提交
static func committed(transaction_id: StringName, events: Array[DomainEvent]) -> CommandResult:
	return CommandResult.new(true, null, transaction_id, events)

## Precheck / Invariant 失败：未产生任何状态变化，events 必须为空
static func rejected(code: StringName, transaction_id: StringName, context: Dictionary = {}) -> CommandResult:
	return CommandResult.new(false, OperationError.new(code, "", context, &"", &"", transaction_id), transaction_id, [])

## Rollback 自身失败 → RECOVERY_REQUIRED（01 §18）。禁止 catch 后 print 继续游戏。
static func recovery_required(transaction_id: StringName, context: Dictionary) -> CommandResult:
	return CommandResult.new(
		false,
		OperationError.new(ErrorCode.RECOVERY_REQUIRED, "rollback failed, manual recovery required", context, &"", &"", transaction_id),
		transaction_id,
		[]
	)

func get_transaction_id() -> StringName:
	return _transaction_id

func get_committed_events() -> Array[DomainEvent]:
	return _committed_events

func is_recovery_required() -> bool:
	return has_error_code(ErrorCode.RECOVERY_REQUIRED)
