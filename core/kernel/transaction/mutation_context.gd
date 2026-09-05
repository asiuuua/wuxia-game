# core/kernel/transaction/mutation_context.gd
# Kernel 契约补充（02 图 §6 Effect 契约的依赖项）：事务内变更收集上下文。
# 备忘：02 图 §6 引用 MutationContext 但未给定义；本文件为使 Effect 契约可编译的
# 最小数据面形态（登记见 ADR_INDEX §4；Execution Runtime 实施时如有出入按 ACR 升版）。
# Effect.apply() 经 register() 登记可回滚变更，序号由本上下文单调分配（回滚按序逆放）；
# Journal 持久化 / 恢复 / 逆序回放属 Execution Runtime（02 图 §7 分界铁律，本批不落地）。

class_name MutationContext
extends RefCounted

var _transaction_id: StringName
var _records: Array[MutationRecord] = []
var _next_sequence: int = 0

func _init(transaction_id: StringName = &"") -> void:
	_transaction_id = transaction_id

func get_transaction_id() -> StringName:
	return _transaction_id

func get_records() -> Array[MutationRecord]:
	return _records

func get_record_count() -> int:
	return _records.size()

## 登记一条可逆变更；sequence 由本上下文单调分配（Rollback 按其逆序执行，01 §17）。
func register(target_id: StringName, owner_module: StringName, state_key: StringName, undo: UndoStrategy) -> MutationRecord:
	var record := MutationRecord.new(_next_sequence, _transaction_id, target_id, owner_module, state_key, undo)
	_next_sequence += 1
	_records.append(record)
	return record
