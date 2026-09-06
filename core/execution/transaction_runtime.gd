# core/execution/transaction_runtime.gd
# Execution 层运行时（01 §14~20 / 宪法 0-C 章）：「这个变化如何安全发生」。
# 分界铁律（01 §16 / 02 图 §7）：契约（TransactionContext/DomainEvent/Result）属 Kernel；
# Begin/Run/Commit/Rollback/Recovery/Journal 生命周期/Pending Event 属本运行时。
# 禁止并入 GameManager 或形成 TransactionManager God Object。
#
# 语义锚点：
# - 0-C.5/01 §17：Journal 登记 8 字段，Rollback 按 sequence 严格逆序，禁猜测式补偿。
# - 0-C.6：Commit 五条件（Required Mutation 完成/Invariant 通过/Precondition 满足/
#          未取消/Persistence Boundary——前置两类由 Application 编排承担，本类管后三类）。
# - 0-C.7/01 §19：事务内 Pending Event，仅 commit 成功推进为 Committed（_mark_committed）。
# - 0-C.8/9/01 §18：回滚逆序恢复；undo 失败 → RECOVERY_REQUIRED + 五元组记录，禁静默吞错。
# - 0-C.10：嵌套事务第一版明确拒绝（begin 返回 null）。
# - 0-C.12：timeout 依赖注入 GameClock（core 禁 Time.*，K-R 禁 API），deadline_tick<=0 = 无限期。
# - 0-C.17/01 §20：COMMITTED 为终态——事后 rollback 一律拒绝（Handler 失败不得假回滚）。
# - 0-C.18：Save 位于 Post-Commit Persistence Boundary，不在本类事务面内。

class_name TransactionRuntime
extends RefCounted

var _journal: MutationJournal
var _clock: GameClock = null            # 可选注入；null = 无超时能力
var _active: TransactionContext = null  # 单活动事务（0-C.10 拒绝嵌套）
var _tx_counter: int = 0
var _pending_events: Dictionary = {}    # tx_id -> Array[DomainEvent]
var _deadlines: Dictionary = {}         # tx_id -> int（<=0 无限期）
var _ctxs: Dictionary = {}              # tx_id -> MutationContext（journal 同步源）

func _init(clock: GameClock = null) -> void:
	_journal = MutationJournal.new()
	_clock = clock

func get_journal() -> MutationJournal:
	return _journal

## 开启事务（0-C.10：存在未终态活动事务时明确拒绝，返回 null）。
func begin(deadline_tick: int = 0, correlation_id: StringName = &"", causation_id: StringName = &"") -> TransactionContext:
	if _active != null:
		return null
	_tx_counter += 1
	var tx_id := StringName("TX_%03d" % _tx_counter)
	var start_tick := _clock.now_tick() if _clock != null else 0
	var tx := TransactionContext.new(tx_id, correlation_id, causation_id, start_tick)
	if not tx._begin():
		return null
	_active = tx
	_deadlines[tx_id] = deadline_tick
	var evs: Array[DomainEvent] = []
	_pending_events[tx_id] = evs
	return tx

## 登记事务待提交事件（0-C.7：仅 commit 成功后才成为 Committed Event）。
func add_pending_event(tx: TransactionContext, event: DomainEvent) -> bool:
	if tx == null or tx.get_state() != TransactionContext.State.RUNNING:
		return false
	var tx_id := tx.get_transaction_id()
	# Dictionary 取值保持 untyped Array，逐元素转入 typed（GDScript 4.x 禁 untyped→typed 直赋）
	var events: Array = _pending_events.get(tx_id, [])
	events.append(event)
	_pending_events[tx_id] = events
	return true

## Domain Execution（0-C.2）：逐 Effect 执行，失败即停（原子性，调用方决定回滚或补偿编排）。
## Effect 经 ctx.register 登记可逆变更；run 结束把 ctx 审计面同步进 Journal。
## Effect 之间检查超时：过期则自动回滚并返回失败（0-C.12）。
func run(tx: TransactionContext, effects: Array[Effect], ctx: MutationContext) -> OperationResult:
	if tx == null or tx.get_state() != TransactionContext.State.RUNNING:
		return OperationResult.fail(ErrorCode.INVALID_STATE, "transaction not running")
	_ctxs[tx.get_transaction_id()] = ctx
	for effect in effects:
		if _is_expired(tx):
			_sync_journal(tx, ctx)   # 超时回滚前必须先同步已登记变更（逆序恢复依据）
			var rec := _rollback_and_finish(tx)
			if rec != null:
				return OperationResult.fail(ErrorCode.RECOVERY_REQUIRED, "timeout rollback failed", {})
			return OperationResult.fail(ErrorCode.INVALID_STATE, "transaction timed out", {"reason": "timeout"})
		var r := effect.apply(ctx)
		if r.is_failed():
			_sync_journal(tx, ctx)
			return r
	_sync_journal(tx, ctx)
	return OperationResult.ok()

## 提交（0-C.6）：状态 RUNNING + 未超时 + Invariant 全过 → Pending Event 推进 Committed → 终态。
## 任一不满足则逆序回滚后返回失败结果；回滚自身失败则返回 recovery_required。
func commit(tx: TransactionContext, facts: GameFacts, invariants: Array[Rule] = []) -> CommandResult:
	var tx_id := tx.get_transaction_id() if tx != null else &""
	if tx == null or tx.get_state() != TransactionContext.State.RUNNING:
		return CommandResult.rejected(ErrorCode.INVALID_STATE, tx_id, {"reason": "transaction not running"})
	if _is_expired(tx):
		var rec := _rollback_and_finish(tx)
		if rec != null:
			return rec
		return CommandResult.rejected(ErrorCode.INVALID_STATE, tx_id, {"reason": "timeout"})
	for rule in invariants:
		var r := rule.evaluate(facts)
		if r.is_failed():
			var code := r.get_error().get_code() if r.get_error() != null else ErrorCode.INVARIANT_VIOLATION
			var rec := _rollback_and_finish(tx)
			if rec != null:
				return rec
			return CommandResult.rejected(ErrorCode.INVARIANT_VIOLATION, tx_id, {"invariant": String(code)})
	var events: Array[DomainEvent] = []
	for ev in _pending_events.get(tx_id, []):
		events.append(ev)
	for ev in events:
		ev._mark_committed()
	tx._mark_committed()
	_release(tx)
	return CommandResult.committed(tx_id, events)

## 回滚（0-C.8）：逆序 undo → ROLLED_BACK；undo 失败 → RECOVERY_REQUIRED（0-C.9 五元组）。
## COMMITTED/RECOVERY_REQUIRED 等非 RUNNING 状态一律拒绝（0-C.17 语义的运行时物理化）。
func rollback(tx: TransactionContext, reason_code: StringName, extra_context: Dictionary = {}) -> CommandResult:
	var tx_id := tx.get_transaction_id() if tx != null else &""
	if tx == null or tx.get_state() != TransactionContext.State.RUNNING:
		return CommandResult.rejected(ErrorCode.INVALID_STATE, tx_id, {"reason": "rollback refused"})
	var rec := _rollback_and_finish(tx)
	if rec != null:
		return rec
	var ctx := {"rollback": "completed", "reason": String(reason_code)}
	for k in extra_context:
		ctx[k] = extra_context[k]
	return CommandResult.rejected(reason_code, tx_id, ctx)

## 取消（0-C.12）：主动放弃未提交事务，已登记 mutation 走逆序恢复。
func cancel(tx: TransactionContext) -> CommandResult:
	return rollback(tx, ErrorCode.INVALID_STATE, {"reason": "cancelled"})

# ---------------- 内部 ----------------

## 超时判断（deadline_tick<=0 或未注入 clock = 无限期）。
func _is_expired(tx: TransactionContext) -> bool:
	if _clock == null:
		return false
	var deadline: int = _deadlines.get(tx.get_transaction_id(), 0)
	if deadline <= 0:
		return false
	return _clock.now_tick() > deadline

## 把 ctx 审计面同步进 Journal（幂等替换；run 已同步过则此为空操作等价）。
func _sync_journal(tx: TransactionContext, ctx: MutationContext) -> void:
	var tx_id := tx.get_transaction_id()
	var entries: Array[JournalEntry] = []
	for a in ctx.get_audits():
		entries.append(JournalEntry.new(
			tx_id,
			a["target_id"],
			a["owner_module"],
			a["state_key"],
			a["before"],
			a["after"],
			a["sequence"],
			a["undo"]
		))
	_journal.replace_for(tx_id, entries)

## 逆序恢复 + 终态推进。返回 null = 回滚成功（事务已 ROLLED_BACK 并释放）；
## 返回非 null = RECOVERY_REQUIRED 结果（0-C.9 五元组在 context）。
func _rollback_and_finish(tx: TransactionContext) -> CommandResult:
	var tx_id := tx.get_transaction_id()
	var entries := _journal.entries_reverse_for(tx_id)
	for e in entries:
		if e.undo != null and not e.undo.restore():
			# 0-C.9 五元组：transaction_id / mutation sequence / failed undo /
			#                current known state / recovery action。禁静默吞错。
			var five := {
				"transaction_id": String(tx_id),
				"failed_mutation_sequence": e.sequence,
				"failed_undo": "%s:%s" % [String(e.target_id), String(e.state_key)],
				"current_known_state": "mutations with sequence > %d restored; mutation %d and earlier pending manual recovery" % [e.sequence, e.sequence],
				"recovery_action": "manual_intervention_required",
			}
			tx._mark_recovery_required()
			_release(tx)
			return CommandResult.recovery_required(tx_id, five)
	tx._mark_rolled_back()
	_release(tx)
	return null

## 终态后释放运行时侧关联（tx 对象本身由调用方持有，状态可查）。
func _release(tx: TransactionContext) -> void:
	var tx_id := tx.get_transaction_id()
	_pending_events.erase(tx_id)
	_deadlines.erase(tx_id)
	_ctxs.erase(tx_id)
	if _active == tx:
		_active = null
