# tests/unit/test_transaction_runtime.gd
# Transaction Test（01 §118 / 宪法 0-C.20 十一路失败路径矩阵 + 0-C.10 嵌套拒绝）。
# 承载 GATE26（Transaction Atomicity）/ GATE27（Rollback Recovery）内容面（04 图 §2.2）。
# 路径清单：Success / Precheck Failure / First·Middle·Last Mutation Failure /
#           Invariant Failure / Cancel / Timeout / Event Handler Failure / Save Failure /
#           Rollback Failure(→RECOVERY_REQUIRED) / Nested Rejected。
# 替身全部文件内定义（tests/doubles 驻地规则不适用于单文件测试小替身，随 04-T 基线）。

extends TestBase

# ---------------- 测试替身 ----------------

## 带标签的回滚策略：restore 时向共享 call_log 追加 tag（逆序断言依据）。
class TagUndo extends UndoStrategy:
	var tag: String
	var fail: bool
	var call_log: Array
	func _init(p_tag: String, p_log: Array, p_fail: bool = false) -> void:
		tag = p_tag
		call_log = p_log
		fail = p_fail
	func restore() -> bool:
		call_log.append(tag)
		return not fail

## 可推进时钟（timeout 路径用 effect 内 advance 模拟执行耗时）。
class FakeClock extends GameClock:
	var tick: int = 100
	func now_tick() -> int:
		return tick
	func now_timestamp() -> int:
		return tick * 1000
	func advance(delta_tick: int) -> void:
		tick += delta_tick
	func can_advance() -> bool:
		return true

class FakeFacts extends GameFacts:
	func get_int(_key: StringName) -> int:
		return 7
	func get_bool(_key: StringName) -> bool:
		return true
	func get_entity_id(_key: StringName) -> EntityId:
		return EntityId.of(&"NPC", "000001")

## 变更 Effect：可选推进时钟（tick_cost）→ 登记 mutation（before/after 审计双值）→ 返回 ok/fail。
class MutEffect extends Effect:
	var ok: bool
	var fail_code: StringName
	var undo_tag: String
	var undo_fail: bool
	var call_log: Array
	var clock: FakeClock
	var tick_cost: int
	var before_v: Variant
	var after_v: Variant
	func _init(p_ok: bool, p_tag: String, p_log: Array, p_fail_code: StringName = ErrorCode.INVALID_TARGET) -> void:
		ok = p_ok
		undo_tag = p_tag
		call_log = p_log
		fail_code = p_fail_code
		undo_fail = false
		clock = null
		tick_cost = 0
		before_v = null
		after_v = null
	func apply(ctx: MutationContext) -> OperationResult:
		if clock != null and tick_cost > 0:
			clock.advance(tick_cost)
		if undo_tag != "":
			ctx.register(&"PLAYER_001", &"test_module", StringName(undo_tag), TagUndo.new(undo_tag, call_log, undo_fail), before_v, after_v)
		if ok:
			return OperationResult.ok()
		return OperationResult.fail(fail_code, "mut effect failed")

class InvRule extends Rule:
	var fail_code: StringName
	func _init(p_fail_code: StringName = &"") -> void:
		fail_code = p_fail_code
	func evaluate(_facts: GameFacts) -> OperationResult:
		if fail_code == &"":
			return OperationResult.ok()
		return OperationResult.fail(fail_code, "invariant violated")

class FakeEvent extends DomainEvent:
	func _init(id: StringName) -> void:
		super(id, &"TEST_EVENT")

## 标准工装：无时钟运行时 + 新事务。
func _make_rt() -> TransactionRuntime:
	return TransactionRuntime.new()

func _make_ctx(tx: TransactionContext) -> MutationContext:
	return MutationContext.new(tx.get_transaction_id())

# ---------------- 路径 1：Success（0-C.2 正常链 / 0-C.19 Golden Case 语义） ----------------

func test_success_path() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	expect(tx != null, "begin 应成功")
	var log: Array = []
	var ctx := _make_ctx(tx)
	var effects: Array[Effect] = [MutEffect.new(true, "m0", log), MutEffect.new(true, "m1", log)]
	effects[0].before_v = 500
	effects[0].after_v = 400
	var run_res := rt.run(tx, effects, ctx)
	expect(run_res.is_ok(), "run 应成功")
	var ev0 := FakeEvent.new(&"E0")
	var ev1 := FakeEvent.new(&"E1")
	expect(rt.add_pending_event(tx, ev0), "pending event 0 应登记")
	expect(rt.add_pending_event(tx, ev1), "pending event 1 应登记")
	var res := rt.commit(tx, FakeFacts.new(), [InvRule.new()])
	expect(res.is_ok(), "commit 应成功")
	expect_eq(res.get_committed_events().size(), 2, "应产出 2 条 committed event")
	expect(ev0.is_committed(), "event 0 应已推进 COMMITTED（0-C.7）")
	expect(ev1.is_committed(), "event 1 应已推进 COMMITTED（0-C.7）")
	expect(tx.is_committed(), "事务应为 COMMITTED")
	expect_eq(log.size(), 0, "成功路径不得触发任何 undo")
	expect_eq(rt.get_journal().entry_count(tx.get_transaction_id()), 2, "Journal 应登记 2 条（0-C.5）")
	var entries := rt.get_journal().entries_for(tx.get_transaction_id())
	expect(entries[0].before == 500 and entries[0].after == 400, "Journal 应含 before=500/after=400（0-C.5 禁猜测补偿）")

# ---------------- 路径 2：Precheck Failure（Precheck 属 Application 编排，失败后回滚空事务） ----------------

func test_precheck_failure() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	expect(tx != null, "begin 应成功")
	# Application 层 Precheck 失败：未 run 任何 Effect，事务以失败结束
	var res := rt.rollback(tx, ErrorCode.PRECHECK_FAILED)
	expect(res.is_failed(), "结果应为失败")
	expect(res.has_error_code(ErrorCode.PRECHECK_FAILED), "错误码应为 PRECHECK_FAILED")
	expect(tx.get_state() == TransactionContext.State.ROLLED_BACK, "事务应 ROLLED_BACK")
	expect_eq(rt.get_journal().entry_count(tx.get_transaction_id()), 0, "空事务 Journal 应为 0")

# ---------------- 路径 3：First Mutation Failure ----------------

func test_first_mutation_failure() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	# 首个 effect 失败（但已登记变更——部分登记语义）
	var effects: Array[Effect] = [MutEffect.new(false, "m0", log), MutEffect.new(true, "m1", log)]
	var run_res := rt.run(tx, effects, ctx)
	expect(run_res.is_failed(), "run 应失败")
	var res := rt.rollback(tx, run_res.get_error().get_code())
	expect(res.is_failed(), "回滚结果承载业务失败语义")
	expect(tx.get_state() == TransactionContext.State.ROLLED_BACK, "事务应 ROLLED_BACK")
	expect_eq(log.size(), 1, "仅首个 effect 的 undo 被调")
	expect(log[0] == "m0", "逆序应从 m0 开始（仅此一条）")
	expect_eq(rt.get_journal().entry_count(tx.get_transaction_id()), 1, "Journal 应有 1 条已登记")

# ---------------- 路径 4：Middle Mutation Failure ----------------

func test_middle_mutation_failure() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	var effects: Array[Effect] = [MutEffect.new(true, "m0", log), MutEffect.new(false, "m1", log), MutEffect.new(true, "m2", log)]
	var run_res := rt.run(tx, effects, ctx)
	expect(run_res.is_failed(), "run 应失败")
	var res := rt.rollback(tx, run_res.get_error().get_code())
	expect(tx.get_state() == TransactionContext.State.ROLLED_BACK, "事务应 ROLLED_BACK")
	expect_eq(log.size(), 2, "已登记两条 undo 均被调")
	expect(log[0] == "m1", "逆序第一应为 m1（01 §17 反向恢复）")
	expect(log[1] == "m0", "逆序第二应为 m0")

# ---------------- 路径 5：Last Mutation Failure ----------------

func test_last_mutation_failure() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	var effects: Array[Effect] = [MutEffect.new(true, "m0", log), MutEffect.new(true, "m1", log), MutEffect.new(false, "m2", log)]
	var run_res := rt.run(tx, effects, ctx)
	expect(run_res.is_failed(), "run 应失败")
	var res := rt.rollback(tx, run_res.get_error().get_code())
	expect(tx.get_state() == TransactionContext.State.ROLLED_BACK, "事务应 ROLLED_BACK")
	expect_eq(log.size(), 3, "三条 undo 全部被调")
	expect(log[0] == "m2" and log[1] == "m1" and log[2] == "m0", "应为 m2→m1→m0 严格逆序（K-R16）")

# ---------------- 路径 6：Invariant Failure（0-C.6 Invariant 不过 → 拒绝提交并回滚） ----------------

func test_invariant_failure() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	var effects: Array[Effect] = [MutEffect.new(true, "m0", log), MutEffect.new(true, "m1", log), MutEffect.new(true, "m2", log)]
	expect(rt.run(tx, effects, ctx).is_ok(), "run 应成功")
	var res := rt.commit(tx, FakeFacts.new(), [InvRule.new(&"ERR_INVARIANT_TEST")])
	expect(res.is_failed(), "commit 应失败")
	expect(res.has_error_code(ErrorCode.INVARIANT_VIOLATION), "错误码应为 INVARIANT_VIOLATION")
	expect(tx.get_state() == TransactionContext.State.ROLLED_BACK, "事务应 ROLLED_BACK")
	expect(log[0] == "m2" and log[1] == "m1" and log[2] == "m0", "回滚应严格逆序")

# ---------------- 路径 7：Cancel（0-C.12 主动取消 → 逆序恢复 + 终态拒绝再提交） ----------------

func test_cancel() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	var effects: Array[Effect] = [MutEffect.new(true, "m0", log), MutEffect.new(true, "m1", log)]
	expect(rt.run(tx, effects, ctx).is_ok(), "run 应成功")
	var res := rt.cancel(tx)
	expect(res.is_failed(), "取消后事务以失败结束")
	expect(res.has_error_code(ErrorCode.INVALID_STATE), "错误码应为 INVALID_STATE")
	expect(tx.get_state() == TransactionContext.State.ROLLED_BACK, "事务应 ROLLED_BACK")
	expect(log[0] == "m1" and log[1] == "m0", "取消应逆序恢复")
	var again := rt.commit(tx, FakeFacts.new(), [])
	expect(again.is_failed() and again.has_error_code(ErrorCode.INVALID_STATE), "ROLLED_BACK 后 commit 应被状态机拒绝")

# ---------------- 路径 8：Timeout（0-C.12 deadline + 注入 GameClock，core 禁 Time.*） ----------------

func test_timeout() -> void:
	var clock := FakeClock.new()
	var rt := TransactionRuntime.new(clock)
	var tx := rt.begin(150)  # deadline_tick=150
	expect(tx != null, "begin 应成功")
	var log: Array = []
	var ctx := _make_ctx(tx)
	var e0 := MutEffect.new(true, "m0", log)
	e0.clock = clock
	e0.tick_cost = 40   # 100→140 未超时
	var e1 := MutEffect.new(true, "m1", log)
	e1.clock = clock
	e1.tick_cost = 40   # 140→180 已越 deadline
	var e2 := MutEffect.new(true, "m2", log)
	var effects: Array[Effect] = [e0, e1, e2]
	var run_res := rt.run(tx, effects, ctx)
	expect(run_res.is_failed(), "超时后 run 应失败")
	expect(run_res.has_error_code(ErrorCode.INVALID_STATE), "超时错误码应为 INVALID_STATE（15 常量表冻结，无专用码）")
	expect(tx.get_state() == TransactionContext.State.ROLLED_BACK, "超时应自动回滚至 ROLLED_BACK")
	expect(log[0] == "m1" and log[1] == "m0", "已登记 m0/m1 应逆序恢复，m2 未执行")

# ---------------- 路径 9：Event Handler Failure（0-C.17：已提交事实不得假回滚） ----------------

func test_event_handler_failure() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	var effects: Array[Effect] = [MutEffect.new(true, "m0", log)]
	expect(rt.run(tx, effects, ctx).is_ok(), "run 应成功")
	var ev := FakeEvent.new(&"E0")
	expect(rt.add_pending_event(tx, ev), "pending event 应登记")
	var res := rt.commit(tx, FakeFacts.new(), [])
	expect(res.is_ok(), "commit 应成功")
	# 模拟：Committed Event Handler 处理失败后，调用方尝试回滚已提交事务
	var late := rt.rollback(tx, ErrorCode.ITEM_NOT_FOUND)
	expect(late.is_failed() and late.has_error_code(ErrorCode.INVALID_STATE), "COMMITTED 终态 rollback 应被拒绝（0-C.17）")
	expect_eq(log.size(), 0, "undo 不得被调用（事实已成立）")
	expect(tx.is_committed(), "事务仍应为 COMMITTED")
	expect(ev.is_committed(), "事件仍为 Committed Event")

# ---------------- 路径 10：Save Failure（0-C.18：持久化在 Post-Commit Boundary，不回滚 Domain State） ----------------

func test_save_failure() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	var effects: Array[Effect] = [MutEffect.new(true, "m0", log)]
	expect(rt.run(tx, effects, ctx).is_ok(), "run 应成功")
	var res := rt.commit(tx, FakeFacts.new(), [])
	expect(res.is_ok(), "commit 应成功（Domain Transaction 在持久化之前已完成）")
	# 模拟：commit 后持久化写盘失败（Post-Commit Persistence Boundary 内，0-C.18）
	var late := rt.rollback(tx, ErrorCode.REPOSITORY_UNAVAILABLE)
	expect(late.is_failed() and late.has_error_code(ErrorCode.INVALID_STATE), "持久化失败不得触发事务回滚（0-C.18）")
	expect_eq(log.size(), 0, "undo 不得被调用")
	expect(tx.is_committed(), "事务仍应为 COMMITTED——Save 失败走 Recovery/Durability Gate，非事务回滚")

# ---------------- 路径 11：Rollback Failure → RECOVERY_REQUIRED（0-C.9 五元组） ----------------

func test_rollback_failure_recovery_required() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	var e0 := MutEffect.new(true, "m0", log)
	var e1 := MutEffect.new(true, "m1", log)
	e1.undo_fail = true   # 中段 undo 失败
	var e2 := MutEffect.new(true, "m2", log)
	var effects: Array[Effect] = [e0, e1, e2]
	expect(rt.run(tx, effects, ctx).is_ok(), "run 应成功")
	var res := rt.commit(tx, FakeFacts.new(), [InvRule.new(&"ERR_INVARIANT_TEST")])
	expect(res.is_failed(), "commit 应失败")
	expect(res.is_recovery_required(), "undo 失败必须升级 RECOVERY_REQUIRED（0-C.9）")
	# 0-C.9 五元组
	var five := res.get_error().get_context()
	expect(five.has("transaction_id"), "五元组应含 transaction_id")
	expect(five.has("failed_mutation_sequence"), "五元组应含 mutation sequence")
	expect(five.has("failed_undo"), "五元组应含 failed undo")
	expect(five.has("current_known_state"), "五元组应含 current known state")
	expect(five.has("recovery_action"), "五元组应含 recovery action")
	expect_eq(int(five["failed_mutation_sequence"]), 1, "失败 undo 应为 sequence 1（m1）")
	expect(tx.is_recovery_required(), "事务应 RECOVERY_REQUIRED")
	expect_eq(log.size(), 2, "m2 成功恢复、m1 失败即停（append 在 restore 开头，含失败调用）")
	expect(log[0] == "m2" and log[1] == "m1", "恢复顺序应 m2→m1，m0 未触")
	var late := rt.rollback(tx, ErrorCode.INVALID_STATE)
	expect(late.is_failed() and late.has_error_code(ErrorCode.INVALID_STATE), "RECOVERY_REQUIRED 非 RUNNING，rollback 应被拒绝")

# ---------------- 路径 12（加固）：Nested Transaction Rejected（0-C.10） ----------------

func test_nested_transaction_rejected() -> void:
	var rt := _make_rt()
	var tx0 := rt.begin()
	expect(tx0 != null, "首个 begin 应成功")
	expect(rt.begin() == null, "嵌套 begin 应明确拒绝（0-C.10）")
	expect(rt.rollback(tx0, ErrorCode.INVALID_STATE).is_failed(), "释放事务")
	var tx1 := rt.begin()
	expect(tx1 != null, "终态后应允许新事务")
	expect(tx1.get_transaction_id() != tx0.get_transaction_id(), "新事务 id 应单调递增")

# ---------------- 加固：Journal 审计面（0-C.5 before/after + K-R16 sequence） ----------------

func test_journal_audit_fields_and_sequence() -> void:
	var rt := _make_rt()
	var tx := rt.begin()
	var log: Array = []
	var ctx := _make_ctx(tx)
	var e0 := MutEffect.new(true, "gold", log)
	e0.before_v = 500
	e0.after_v = 400
	var e1 := MutEffect.new(true, "inventory", log)
	e1.before_v = []
	e1.after_v = ["ITEM_POTION"]
	var effects: Array[Effect] = [e0, e1]
	expect(rt.run(tx, effects, ctx).is_ok(), "run 应成功")
	var entries := rt.get_journal().entries_for(tx.get_transaction_id())
	expect_eq(entries.size(), 2, "应登记 2 条")
	expect_eq(entries[0].sequence, 0, "sequence 应单调（0 起步）")
	expect_eq(entries[1].sequence, 1, "sequence 应单调递增")
	expect(entries[0].before == 500 and entries[0].after == 400, "gold 条目应含 before/after 双值（0-C.5 示例口径）")
	expect(entries[1].before is Array, "inventory before 应为 Variant 数组")
	expect(entries[1].after == ["ITEM_POTION"], "inventory after 应为追加后数组")
	expect(entries[0].owner_module == &"test_module", "owner_module 应登记")
	var rev := rt.get_journal().entries_reverse_for(tx.get_transaction_id())
	expect_eq(rev[0].sequence, 1, "逆序视图应 sequence 严格降序（K-R16）")
	expect_eq(rev[1].sequence, 0, "逆序视图末位应为 sequence 0")
