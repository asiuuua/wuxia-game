# core/execution/journal_entry.gd
# Execution 层（01 §17 / 宪法 0-C.5）：Mutation Journal 条目。
# 与 kernel MutationRecord（02 图 §7.2 冻结面：sequence/transaction_id/target_id/
# owner_module/state_key/undo）互补——0-C.5 与 01 §17 要求 Journal 另行登记
# before/after 双值（禁猜测式补偿：Rollback 恢复 before，不靠当前状态反推）。
# 补充缺口登记 ADR_INDEX §4（JournalEntry 承接，Phase4 迁移时对齐 02 图契约文档）。

class_name JournalEntry
extends RefCounted

var transaction_id: StringName
var target_id: StringName
var owner_module: StringName
var state_key: StringName
var before: Variant
var after: Variant
var sequence: int          # K-R16：排序只认 sequence
var undo: UndoStrategy     # null = 不可逆登记（仅审计，回滚跳过）

func _init(
	p_transaction_id: StringName,
	p_target_id: StringName,
	p_owner_module: StringName,
	p_state_key: StringName,
	p_before: Variant,
	p_after: Variant,
	p_sequence: int,
	p_undo: UndoStrategy
) -> void:
	transaction_id = p_transaction_id
	target_id = p_target_id
	owner_module = p_owner_module
	state_key = p_state_key
	before = p_before
	after = p_after
	sequence = p_sequence
	undo = p_undo
