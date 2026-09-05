# tests/unit/test_kernel_contracts.gd
# Kernel 契约测试（02 图 §14 DoD「Contract Compliance」：签名/类型/不可变性）。
# 覆盖：EntityId 解析/相等、ErrorCode/OperationError、Result 家族（K-R13）、
#       TransactionContext 状态机合法迁移、MutationContext 序号单调 + UndoStrategy 恢复契约、
#       DomainEvent Phase、Command/Query 形状、@abstract 契约经子类实例化。
# 说明：01 §118 的 11 种事务失败路径属 TransactionRuntime 批次的 Transaction Test（GATE26/27/28），
#       本文件只测契约层可保证的部分（Phase B 骨架批，02 图 O-4 第一步）。

extends TestBase

# ---------------- 契约测试替身（验证 @abstract 契约可被正确实现） ----------------

class FakeFacts extends GameFacts:
	func get_int(_key: StringName) -> int:
		return 7
	func get_bool(_key: StringName) -> bool:
		return true
	func get_entity_id(_key: StringName) -> EntityId:
		return EntityId.of(&"NPC", "000001")

class FakeCondition extends Condition:
	var _result: bool
	func _init(result: bool = true) -> void:
		_result = result
	func evaluate(_facts: GameFacts) -> bool:
		return _result

class FakeRule extends Rule:
	var _fail_code: StringName
	func _init(fail_code: StringName = &"") -> void:
		_fail_code = fail_code
	func evaluate(_facts: GameFacts) -> OperationResult:
		if _fail_code == &"":
			return OperationResult.ok()
		return OperationResult.fail(_fail_code, "rule failed")

class FakeUndo extends UndoStrategy:
	var restored: bool = false
	var fail: bool = false
	func restore() -> bool:
		restored = true
		return not fail

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

class FakeRandom extends RandomProvider:
	var _seed_value: int = 0
	func set_seed(seed_value: int) -> void:
		_seed_value = seed_value
	func get_seed() -> int:
		return _seed_value
	func next_float() -> float:
		return 0.5
	func next_int(min_value: int, max_value: int) -> int:
		return mini(min_value, max_value)

class FakeSnapshot extends RefCounted:
	var value: int = 1

# ---------------- EntityId（02 图 §2） ----------------

func test_entity_id_parse_and_roundtrip() -> void:
	var e := EntityId.of(&"NPC", "000001")
	expect(e.get_domain() == &"NPC", "domain 应为 NPC")
	expect(e.get_serial() == "000001", "serial 应为 000001")
	expect(str(e) == "NPC_000001", "_to_string 应为 NPC_000001")
	var p := EntityId.parse("NPC_000001")
	expect(p != null, "合法格式应解析成功")
	expect(p != null and p.equals(e), "parse 结果应与 of 构造相等")

func test_entity_id_parse_rejects_bad_input() -> void:
	expect(EntityId.parse("") == null, "空串应返回 null")
	expect(EntityId.parse("NPC") == null, "无分隔符应返回 null")
	expect(EntityId.parse("A_B_C") == null, "三段应返回 null")
	var e := EntityId.of(&"ITEM", "000002")
	expect(e.equals(null) == false, "与 null 比较应返回 false")
	var other := EntityId.of(&"ITEM", "000003")
	expect(e.equals(other) == false, "不同 serial 不应相等")

# ---------------- ErrorCode / OperationError（02 图 §3） ----------------

func test_error_code_constants_are_stringnames() -> void:
	expect(ErrorCode.NONE == &"ERR_NONE", "NONE 常量值应锚定")
	expect(ErrorCode.INSUFFICIENT_FUNDS == &"ERR_INSUFFICIENT_FUNDS", "INSUFFICIENT_FUNDS 常量值应锚定")
	expect(ErrorCode.TRANSACTION_ROLLBACK_FAILED == &"ERR_TRANSACTION_ROLLBACK_FAILED", "ROLLBACK_FAILED 常量值应锚定")
	expect(ErrorCode.RECOVERY_REQUIRED == &"ERR_TRANSACTION_RECOVERY_REQUIRED", "RECOVERY_REQUIRED 常量值应锚定")

func test_operation_error_carries_context() -> void:
	var err := OperationError.new(ErrorCode.INVALID_TARGET, "目标无效", {"target": "x"}, &"corr1", &"cause1", &"tx1")
	expect(err.get_code() == ErrorCode.INVALID_TARGET, "code 应一致")
	expect(err.get_message() == "目标无效", "message 应一致（仅展示用）")
	expect(err.get_context().size() == 1, "context 应为 K-DB-01 诊断字典")
	expect(err.get_correlation_id() == &"corr1", "correlation_id 应一致")
	expect(err.get_causation_id() == &"cause1", "causation_id 应一致")
	expect(err.get_transaction_id() == &"tx1", "transaction_id 应一致")
	expect(err.has_code(ErrorCode.INVALID_TARGET), "has_code 应命中")
	expect(not err.has_code(ErrorCode.NONE), "has_code 不应误命中")

# ---------------- Result 家族（02 图 §4） ----------------

func test_operation_result_ok_fail() -> void:
	var ok := OperationResult.ok()
	expect(ok.is_ok(), "ok() 应成功")
	expect(not ok.is_failed(), "ok() 不应失败")
	expect(ok.get_error() == null, "成功结果错误对象应为 null")
	var f := OperationResult.fail(ErrorCode.ITEM_NOT_FOUND, "缺货")
	expect(f.is_failed(), "fail() 应失败")
	expect(f.has_error_code(ErrorCode.ITEM_NOT_FOUND), "错误码应可比较")
	expect(not f.has_error_code(ErrorCode.NONE), "错误码不应误命中")

func test_command_result_kr13_uncommitted_events_empty() -> void:
	var events: Array[DomainEvent] = [DomainEvent.new(&"e1", &"ItemPurchasedEvent", DomainEvent.Phase.COMMITTED)]
	var cr := CommandResult.committed(&"tx1", events)
	expect(cr.is_ok(), "committed 应成功")
	expect(cr.get_transaction_id() == &"tx1", "transaction_id 应一致")
	expect(cr.get_committed_events().size() == 1, "提交结果应带 1 条已提交事件")
	var rj := CommandResult.rejected(ErrorCode.PRECHECK_FAILED, &"tx2", {"reason": "poor"})
	expect(rj.is_failed(), "rejected 应失败")
	expect(rj.get_committed_events().is_empty(), "K-R13：未提交事务 committed_events 必须为空")
	expect(rj.get_error().get_transaction_id() == &"tx2", "错误对象应携带 transaction_id")
	var rec := CommandResult.recovery_required(&"tx3", {})
	expect(rec.is_failed(), "recovery_required 应失败")
	expect(rec.is_recovery_required(), "recovery_required 应可被 is_recovery_required 识别")
	expect(rec.get_committed_events().is_empty(), "恢复路径事件必须为空")

func test_query_result_payload_typing_kdb03() -> void:
	var qr := QueryResult.success(FakeSnapshot.new())
	expect(qr.is_ok(), "success 应成功")
	expect(qr.get_payload_as(FakeSnapshot) != null, "类型匹配应返回载荷")
	expect(qr.get_payload_as(OperationError) == null, "K-DB-03：类型不符应返回 null")
	var nf := QueryResult.not_found()
	expect(nf.is_failed(), "not_found 应失败")
	expect(nf.get_payload() == null, "not_found 载荷应为 null")

func test_validation_save_load_results() -> void:
	var v := ValidationViolation.new(&"ERR_REQUIREMENT_NOT_MET", &"level", "等级不足")
	expect(v.get_code() == &"ERR_REQUIREMENT_NOT_MET", "violation code 应一致")
	expect(v.get_field() == &"level", "violation field 应一致")
	expect(v.get_detail() == "等级不足", "violation detail 应一致")
	var vr := ValidationResult.new(true, null)
	expect(vr.is_valid(), "无违约应 valid")
	expect(vr.get_violations().is_empty(), "默认违约列表应为空")
	var sr := SaveResult.new(true, null, &"1.1.0", "user://save1.json")
	expect(sr.get_save_version() == &"1.1.0", "save_version 应一致")
	expect(sr.get_persisted_path() == "user://save1.json", "persisted_path 应一致")
	var lr := LoadResult.new(true, null, null, &"1.0.0")
	expect(lr.was_migrated(), "带来源版本应视为已迁移")
	var lr2 := LoadResult.new(true, null)
	expect(not lr2.was_migrated(), "无来源版本应视为未迁移")

# ---------------- TransactionContext 状态机（02 图 §7.1） ----------------

func test_transaction_context_legal_transitions() -> void:
	var ctx := TransactionContext.new(&"tx", &"corr", &"cause", 42)
	expect(ctx.get_state() == TransactionContext.State.PENDING, "初始应为 PENDING")
	expect(ctx.get_started_tick() == 42, "started_tick 应一致")
	expect(not ctx.is_committed(), "初始不应 committed")
	expect(not ctx._mark_committed(), "PENDING 直达 COMMITTED 应被拒")
	expect(ctx._begin(), "PENDING→RUNNING 应合法")
	expect(not ctx._begin(), "重复 begin 应被拒")
	expect(ctx._mark_committed(), "RUNNING→COMMITTED 应合法")
	expect(ctx.is_committed(), "is_committed 应为真")
	expect(not ctx._begin(), "COMMITTED 终态不得再迁移")

func test_transaction_context_rollback_and_recovery() -> void:
	var ctx := TransactionContext.new(&"tx2")
	expect(ctx._begin(), "begin 应成功")
	expect(ctx._mark_rolled_back(), "RUNNING→ROLLED_BACK 应合法")
	expect(ctx._mark_committed() == false, "ROLLED_BACK 不得再提交")
	expect(ctx._mark_recovery_required(), "回滚失败升级 RECOVERY_REQUIRED 应合法")
	expect(ctx.is_recovery_required(), "is_recovery_required 应为真")
	var ctx3 := TransactionContext.new(&"tx3")
	expect(ctx3._begin(), "begin 应成功")
	expect(ctx3._mark_recovery_required(), "RUNNING 直升 RECOVERY_REQUIRED 应合法（回滚中失败）")

# ---------------- MutationContext / MutationRecord / UndoStrategy（02 图 §7.2/7.3） ----------------

func test_mutation_context_sequence_monotonic() -> void:
	var mc := MutationContext.new(&"tx9")
	expect(mc.get_record_count() == 0, "初始记录应为空")
	expect(mc.get_transaction_id() == &"tx9", "transaction_id 应一致")
	var u0 := FakeUndo.new()
	var u1 := FakeUndo.new()
	var r0 := mc.register(&"wallet_001", &"economy", &"gold", u0)
	var r1 := mc.register(&"wallet_001", &"economy", &"gold", u1)
	expect(r0.get_sequence() == 0, "首条序号应为 0")
	expect(r1.get_sequence() == 1, "序号应单调递增")
	expect(r0.get_transaction_id() == &"tx9", "记录应携带事务号")
	expect(r0.get_target_id() == &"wallet_001", "target_id 应一致")
	expect(r0.get_owner_module() == &"economy", "owner_module 应一致")
	expect(r0.get_state_key() == &"gold", "state_key 应一致")
	expect(r0.get_undo() == u0, "undo 策略应原样持有")
	expect(mc.get_record_count() == 2, "登记后记录数应为 2")

func test_undo_strategy_restore_contract() -> void:
	var mc := MutationContext.new(&"tx10")
	var ok_undo := FakeUndo.new()
	var r := mc.register(&"inv_001", &"inventory", &"slot_3", ok_undo)
	var restored_ok: bool = r.get_undo().restore()
	expect(restored_ok, "恢复成功应返回 true")
	expect(ok_undo.restored, "restore 应被实际调用")
	var bad_undo := FakeUndo.new()
	bad_undo.fail = true
	var r2 := mc.register(&"inv_001", &"inventory", &"slot_3", bad_undo)
	expect(not r2.get_undo().restore(), "undo 失败应返回 false（Runtime 据此产出 RECOVERY_REQUIRED）")

# ---------------- DomainEvent / Command / Query（02 图 §5） ----------------

func test_domain_event_phase_contract() -> void:
	var ev := DomainEvent.new(&"e1", &"MarriageFormedEvent")
	expect(ev.is_committed() == false, "默认 PENDING 不应 committed")
	expect(ev.get_type() == &"MarriageFormedEvent", "get_type 应返回事件类型")
	var ev2 := DomainEvent.new(&"e2", &"ItemPurchasedEvent", DomainEvent.Phase.COMMITTED, 5, &"cause_cmd", &"corr", &"tx")
	expect(ev2.is_committed(), "COMMITTED 应为真")
	expect(ev2.get_occurred_tick() == 5, "occurred_tick 应一致")
	expect(ev2.get_causation_id() == &"cause_cmd", "causation_id 应一致")
	expect(ev2.get_transaction_id() == &"tx", "transaction_id 应一致")

func test_command_and_query_shapes() -> void:
	var actor := EntityId.of(&"NPC", "000001")
	var c := Command.new(&"buy_item", 3, &"player", actor, 100, &"corr", &"cause")
	expect(c.get_command_id() == &"buy_item", "command_id 应一致")
	expect(c.get_sequence() == 3, "sequence 应一致（排序主键）")
	expect(c.get_source() == &"player", "source 应一致")
	expect(c.get_actor_id() == actor, "actor_id 应一致")
	expect(c.get_game_tick() == 100, "game_tick 应一致")
	expect(c.get_type() == &"Command", "get_type 默认 Command")
	var q := Query.new(&"qry_wallet", null, 7, &"corr")
	expect(q.get_query_id() == &"qry_wallet", "query_id 应一致")
	expect(q.get_actor_id() == null, "actor 可为 null")
	expect(q.get_game_tick() == 7, "game_tick 应一致")
	expect(q.get_type() == &"Query", "get_type 默认 Query")

# ---------------- @abstract 契约经子类实例化（02 图 §6/§8/§9/§10） ----------------

func test_abstract_contracts_instantiable_via_subclass() -> void:
	var facts := FakeFacts.new()
	expect(facts.get_int(&"x") == 7, "FakeFacts.get_int 应可用")
	expect(facts.get_bool(&"x"), "FakeFacts.get_bool 应可用")
	expect(facts.get_entity_id(&"x") != null, "FakeFacts.get_entity_id 应可用")
	var cond := FakeCondition.new(true)
	expect(cond.evaluate(facts), "Condition.evaluate 应走子类实现")
	var rule := FakeRule.new()
	expect(rule.evaluate(facts).is_ok(), "Rule 满足时应返回 ok")
	var rule_bad := FakeRule.new(ErrorCode.REQUIREMENT_NOT_MET)
	expect(rule_bad.evaluate(facts).has_error_code(ErrorCode.REQUIREMENT_NOT_MET), "Rule 不满足时应带具体错误码")
	var clock := FakeClock.new()
	expect(clock.now_tick() == 100, "FakeClock.now_tick 应可用")
	clock.advance(5)
	expect(clock.now_tick() == 105, "advance 应推进 tick")
	expect(clock.can_advance(), "FakeClock 可推进")
	var rng := FakeRandom.new()
	rng.set_seed(20260906)
	expect(rng.get_seed() == 20260906, "seed 应可回读")
	expect(rng.next_float() == 0.5, "next_float 应可用")
	expect(rng.next_int(1, 9) == 1, "next_int 应可用")
	var repo_probe := FakeRepository.new()
	expect(repo_probe.get_repository_id() == &"fake_repo", "Repository 契约应可经子类实现")

class FakeRepository extends Repository:
	func get_repository_id() -> StringName:
		return &"fake_repo"
