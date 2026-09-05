# core/kernel/transaction/mutation_record.gd
# Kernel 契约（02 图 §7.2）：单个可逆变更的登记（01 §17）。
# 铁律：Rollback 必须按 sequence 逆序执行；
#       禁止「扣100 → 失败 → 再加100」这种猜测式补偿。
#       正确做法：由 Owner 提供 UndoStrategy，持有 before 值并知道如何恢复。

class_name MutationRecord
extends RefCounted

var _sequence: int                 # Journal 内序号，回滚按此逆序
var _transaction_id: StringName
var _target_id: StringName         # 被变更对象
var _owner_module: StringName      # 状态 Owner 模块
var _state_key: StringName         # 被变更的状态键
var _undo: UndoStrategy            # 持有 before，提供 restore()

## 构造仅限事务数据面（MutationContext.register 统一分配序号）；业务代码不得手工拼装。
func _init(
	sequence: int,
	transaction_id: StringName,
	target_id: StringName,
	owner_module: StringName,
	state_key: StringName,
	undo: UndoStrategy
) -> void:
	_sequence = sequence
	_transaction_id = transaction_id
	_target_id = target_id
	_owner_module = owner_module
	_state_key = state_key
	_undo = undo

func get_sequence() -> int:
	return _sequence

func get_transaction_id() -> StringName:
	return _transaction_id

func get_target_id() -> StringName:
	return _target_id

func get_owner_module() -> StringName:
	return _owner_module

func get_state_key() -> StringName:
	return _state_key

func get_undo() -> UndoStrategy:
	return _undo
