# core/kernel/transaction/transaction_context.gd
# Kernel 契约（02 图 §7.1）：事务契约。只定义状态与标识，不实现执行。
# 分界铁律（02 图 §7 / 01 §16）：Begin / Prepare / Commit / Rollback / Recovery 的
# 运行时行为属于 Execution 的 TransactionRuntime——本类仅提供状态机数据面；
# 下划线前缀的 _begin/_mark_* 为 Runtime 专用内部推进接口（非公共契约，K-R09 不适用）。

class_name TransactionContext
extends RefCounted

enum State {
	PENDING,            # 已创建，未开始
	RUNNING,            # 执行中，Mutation 正在登记
	COMMITTED,          # 已提交
	ROLLED_BACK,        # 已回滚
	RECOVERY_REQUIRED,  # 回滚自身失败 → FATAL，需人工/自动恢复（01 §18）
}

var _transaction_id: StringName
var _state: State
var _started_tick: int
var _correlation_id: StringName
var _causation_id: StringName

func _init(
	transaction_id: StringName,
	correlation_id: StringName = &"",
	causation_id: StringName = &"",
	started_tick: int = 0
) -> void:
	_transaction_id = transaction_id
	_state = State.PENDING
	_correlation_id = correlation_id
	_causation_id = causation_id
	_started_tick = started_tick

func get_transaction_id() -> StringName:
	return _transaction_id

func get_state() -> State:
	return _state

func get_started_tick() -> int:
	return _started_tick

func get_correlation_id() -> StringName:
	return _correlation_id

func get_causation_id() -> StringName:
	return _causation_id

func is_committed() -> bool:
	return _state == State.COMMITTED

func is_recovery_required() -> bool:
	return _state == State.RECOVERY_REQUIRED

# ---- Runtime 内部推进接口（合法迁移：PENDING→RUNNING；RUNNING→COMMITTED/ROLLED_BACK/
#      RECOVERY_REQUIRED；ROLLED_BACK→RECOVERY_REQUIRED。其余一律拒绝并返回 false）----

func _begin() -> bool:
	if _state != State.PENDING:
		return false
	_state = State.RUNNING
	return true

func _mark_committed() -> bool:
	if _state != State.RUNNING:
		return false
	_state = State.COMMITTED
	return true

func _mark_rolled_back() -> bool:
	if _state != State.RUNNING:
		return false
	_state = State.ROLLED_BACK
	return true

func _mark_recovery_required() -> bool:
	if _state != State.RUNNING and _state != State.ROLLED_BACK:
		return false
	_state = State.RECOVERY_REQUIRED
	return true
