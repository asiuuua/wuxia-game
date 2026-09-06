# tests/unit/test_command_ordering.gd
# GATE28 Command Ordering（02 图 K-R16 / 01 §65 / 04 图，B4 点亮 2026-09-06）：
# 排序只依赖 sequence，禁止依赖 Dictionary 遍历顺序 / Node 树顺序 / append 顺序 / 线程调度。
# 载体：MutationJournal（Execution 层回滚视图/审计视图）+ MutationContext（单调分配）。
# K-R16 FATAL E2——任一断言破即红。纯 Kernel/Execution 数据面测试，零生产依赖。

extends TestBase
class_name TestCommandOrdering

const TX_A := &"tx_a"
const TX_B := &"tx_b"

func _entry(tx: StringName, seq: int) -> JournalEntry:
	# undo=null = 不可逆登记（仅审计，回滚跳过）——排序语义与 undo 无关，纯排序测试用 null
	return JournalEntry.new(tx, &"target_x", &"owner_test", &"state_key", 0, 0, seq, null)

func _seqs(view: Array[JournalEntry]) -> Array:
	var out := []
	for e in view:
		out.append(e.sequence)
	return out

# === K-R16：回滚视图 = sequence 严格降序，与 append 顺序无关 ===
func test_rollback_view_strict_descending_by_sequence() -> void:
	var j := MutationJournal.new()
	for seq in [5, 1, 9, 3]:   # 故意乱序 append
		j.append_entry(_entry(TX_A, seq))
	var view := j.entries_reverse_for(TX_A)
	expect(_seqs(view) == [9, 5, 3, 1],
		"回滚视图应按 sequence 严格降序 [9,5,3,1]（实际 %s）" % [_seqs(view)])

# === 审计视图 = sequence 升序 ===
func test_audit_view_ascending_by_sequence() -> void:
	var j := MutationJournal.new()
	for seq in [9, 3, 5, 1]:
		j.append_entry(_entry(TX_A, seq))
	var view := j.entries_for(TX_A)
	expect(_seqs(view) == [1, 3, 5, 9],
		"审计视图应按 sequence 升序 [1,3,5,9]（实际 %s）" % [_seqs(view)])

# === K-R16 核心：同批条目不同 append 序 → 视图逐位相等（禁依赖 append 顺序） ===
func test_append_order_independence() -> void:
	var j1 := MutationJournal.new()
	for seq in [5, 1, 9, 3]:
		j1.append_entry(_entry(TX_A, seq))
	var j2 := MutationJournal.new()
	for seq in [3, 9, 1, 5]:   # 完全相反的 append 序
		j2.append_entry(_entry(TX_A, seq))
	var v1 := j1.entries_reverse_for(TX_A)
	var v2 := j2.entries_reverse_for(TX_A)
	var s1 := _seqs(v1)
	var s2 := _seqs(v2)
	expect(s1 == s2, "同批条目不同 append 序的回滚视图必须逐位相等（%s vs %s）" % [s1, s2])
	# 条目身份也要一致（state_key 对位相同，防排序不稳定导致条目错位）
	var keys1 := []
	var keys2 := []
	for e in v1:
		keys1.append(e.state_key)
	for e in v2:
		keys2.append(e.state_key)
	expect(keys1 == keys2, "回滚视图条目对位应一致（防排序不稳定错位）")

# === 事务隔离：视图只含本事务条目（交错 append 不串号） ===
func test_transaction_views_isolated() -> void:
	var j := MutationJournal.new()
	j.append_entry(_entry(TX_A, 1))
	j.append_entry(_entry(TX_B, 100))
	j.append_entry(_entry(TX_A, 2))
	j.append_entry(_entry(TX_B, 101))
	expect(_seqs(j.entries_for(TX_A)) == [1, 2], "TX_A 审计视图应只含自身条目 [1,2]")
	expect(_seqs(j.entries_reverse_for(TX_A)) == [2, 1], "TX_A 回滚视图应为 [2,1]")
	expect(_seqs(j.entries_for(TX_B)) == [100, 101], "TX_B 审计视图应只含自身条目")
	expect(j.entry_count(TX_A) == 2 and j.entry_count(TX_B) == 2, "事务条目数应各自独立")

# === Journal 幂等同步：多次 replace_for 同一事务不重不漏（0-C.10 同族） ===
func test_replace_for_idempotent() -> void:
	var j := MutationJournal.new()
	j.append_entry(_entry(TX_A, 1))
	var batch: Array[JournalEntry] = [_entry(TX_A, 1), _entry(TX_A, 2), _entry(TX_A, 3)]
	j.replace_for(TX_A, batch)
	j.replace_for(TX_A, batch)   # 二次同步（模拟多次 run 同一事务）
	expect(j.entry_count(TX_A) == 3, "幂等替换不应累积条目（实际 %d）" % j.entry_count(TX_A))
	expect(_seqs(j.entries_for(TX_A)) == [1, 2, 3], "替换后应保留新批次全量")

# === MutationContext：sequence 单调分配（register 调用序 = sequence 序，无跳号） ===
func test_mutation_context_sequence_monotonic() -> void:
	var ctx := MutationContext.new(&"tx_seq")
	for i in 5:
		ctx.register(&"t%d" % i, &"owner_test", &"k%d" % i, null)
	var seqs := []
	for a in ctx.get_audits():
		seqs.append(a["sequence"])
	expect(seqs == [0, 1, 2, 3, 4], "register 审计面 sequence 应单调 [0..4]（实际 %s）" % [seqs])
	expect(ctx.get_record_count() == 5, "records 与 audits 应一一对应")

# === 审计面 before/after 如实记录（null 合法，禁吞值） ===
func test_audit_preserves_before_after() -> void:
	var ctx := MutationContext.new(&"tx_audit")
	ctx.register(&"t1", &"owner_test", &"k", null, 10, 20)
	ctx.register(&"t2", &"owner_test", &"k", null)   # 不提供双值 → null 如实记录
	var audits := ctx.get_audits()
	expect(audits[0]["before"] == 10 and audits[0]["after"] == 20, "双值应如实入审计面")
	expect(audits[0].has("before") and audits[1].has("before"), "未提供双值时键也应存在（null 如实）")
