# core/execution/mutation_journal.gd
# Execution 层（01 §17 / 宪法 0-C.4）：Transaction Engine 拥有 Mutation Journal 生命周期。
# 职责：收纳 JournalEntry（8 字段审计行），提供回滚所需的严格 sequence 降序视图。
# 铁律（01 §17 / 0-C.8）：Rollback 必须按 Journal 反向顺序恢复，禁止猜测式补偿。
# K-R16：排序只认 sequence（sort_custom 显式降序，不依赖 append 顺序）。

class_name MutationJournal
extends RefCounted

var _entries: Array[JournalEntry] = []

## 收纳一条登记（sequence 已由 MutationContext 单调分配，本类不重排号）。
func append_entry(entry: JournalEntry) -> void:
	_entries.append(entry)

## 幂等替换指定事务的全部条目（Runtime 从 MutationContext 审计面同步用；
## 多次 run 同一事务时 ctx audits 为累积全量，替换保证 journal 不重不漏）。
func replace_for(transaction_id: StringName, entries: Array[JournalEntry]) -> void:
	var kept: Array[JournalEntry] = []
	for e in _entries:
		if e.transaction_id != transaction_id:
			kept.append(e)
	_entries = kept
	for e in entries:
		_entries.append(e)

## 指定事务的全部条目（sequence 升序副本，审计/查询用）。
func entries_for(transaction_id: StringName) -> Array[JournalEntry]:
	var out: Array[JournalEntry] = []
	for e in _entries:
		if e.transaction_id == transaction_id:
			out.append(e)
	return out

## 指定事务的回滚视图：sequence 严格降序副本（01 §17 / K-R16）。
func entries_reverse_for(transaction_id: StringName) -> Array[JournalEntry]:
	var out := entries_for(transaction_id)
	out.sort_custom(func(a: JournalEntry, b: JournalEntry) -> bool: return a.sequence > b.sequence)
	return out

## 指定事务的条目数。
func entry_count(transaction_id: StringName) -> int:
	var n := 0
	for e in _entries:
		if e.transaction_id == transaction_id:
			n += 1
	return n

## 全量条目数（诊断用）。
func total_count() -> int:
	return _entries.size()
