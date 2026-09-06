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
var _audits: Array[Dictionary] = []   # 审计侧表（0-C.5：before/after 不在 MutationRecord 冻结面内，由 Runtime 经 get_audits() 同步进 Journal）
var _next_sequence: int = 0

func _init(transaction_id: StringName = &"") -> void:
	_transaction_id = transaction_id

func get_transaction_id() -> StringName:
	return _transaction_id

func get_records() -> Array[MutationRecord]:
	return _records

func get_record_count() -> int:
	return _records.size()

## 审计记录（0-C.5 七字段 + transaction_id）：供 Execution Runtime 填充 MutationJournal。
func get_audits() -> Array[Dictionary]:
	return _audits

## 登记一条可逆变更；sequence 由本上下文单调分配（Rollback 按其逆序执行，01 §17）。
## before/after 为可选项（0-C.5 要求 Journal 登记双值；未提供时为 null，审计面如实记录）。
func register(
	target_id: StringName,
	owner_module: StringName,
	state_key: StringName,
	undo: UndoStrategy,
	before: Variant = null,
	after: Variant = null
) -> MutationRecord:
	var record := MutationRecord.new(_next_sequence, _transaction_id, target_id, owner_module, state_key, undo)
	_audits.append({
		"sequence": _next_sequence,
		"transaction_id": _transaction_id,
		"target_id": target_id,
		"owner_module": owner_module,
		"state_key": state_key,
		"before": before,
		"after": after,
		"undo": undo,
	})
	_next_sequence += 1
	_records.append(record)
	return record
