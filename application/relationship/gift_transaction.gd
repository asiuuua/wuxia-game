# application/relationship/gift_transaction.gd
# 送礼事务编排（08 图批1 ② / TX-1~TX-4 / 0-C 形状，ShopTradeTransaction 同款范式）。
# 送礼链路唯一合法形状（对位 01 §60 七步）：
#   Gift Validation → Transaction → [Instance Consume → Affection Mutation → Gift Count]
#   → Commit → Gift Events（0-C.7 Committed Event 投影，BondService 层发射）
# TX-1：扣物品（Inventory Owner）+ 加好感（Relationship Owner）+ 送礼计数，一个事务
#   全量 Journal——「扣了物品好感没加」从机制上不可能（0-C 核心诉求）。
# TX-2：add_affection 收编——直改路径保留为 Effect 内部实现（bond 静默变更 API），
#   外部调用必经本事务；set_affection 仅限存档恢复/回滚路径。
# TX-4：一次性事件（fired_events）属 Commit 后投影（01 §60 第七步同款），事务窗口内
#   零事件写入→回滚面为零；事件奖励（物品/好感）在投影步走既有静默通道。
# RF-R05（GATE26）：送礼必为单事务——test_gift_transaction 钉死 Middle Failure 回滚。
# 矩阵映射（宪法 0-C.20）：成功 / Precheck 失败（BondService 预检） / 中间 Mutation
#   失败（consume ok + affection fail）→ 全量逆序回滚；Runtime 层十一路由仍由
#   test_transaction_runtime 承接，不在业务层重复。

class_name GiftTransaction
extends RefCounted

static var _event_seq: int = 0

var _rt: TransactionRuntime

func _init(rt: TransactionRuntime = null) -> void:
	_rt = rt if rt != null else TransactionRuntime.new()

## 执行送礼事务（预检已在 BondService.give_gift 完成——Validation→Transaction 分段同 Shop）。
## 返回 { "result": CommandResult }；失败时事务已逆序回滚（0-C.8），失败码透传。
func execute(bond: BondService, inv: InventoryService, npc_id: String, instance_id: String, item_id: String, gain: int) -> Dictionary:
	var aff0: int = bond.get_affection(npc_id)
	var gc0: int = int(bond.gift_count.get(npc_id, 0))
	var count0: int = inv.get_item_count(item_id)
	var tx := _rt.begin()
	var ctx := MutationContext.new(tx.get_transaction_id())
	var effects: Array[Effect] = [
		GiftInstanceConsumeEffect.new(inv, instance_id, item_id),
		AffectionMutationEffect.new(bond, npc_id, gain, "gift:%s" % item_id),
		GiftCountEffect.new(bond, npc_id),
	]
	var r := _rt.run(tx, effects, ctx)
	if r.is_failed():
		var rb := _rt.rollback(tx, r.get_error().get_code(), {"op": "gift", "npc": npc_id, "item": item_id})
		return {"result": rb}
	_rt.add_pending_event(tx, GiftEvent.new(npc_id, item_id, gain))
	# 期望值与执行端同口径钳制（好感域 0-100；讨厌礼在 0 好感上不再下探，Golden 等式才成立）
	var facts := GiftFacts.new(bond, inv, npc_id, item_id, clampi(aff0 + gain, 0, 100), gc0 + 1, count0 - 1)
	var cr := _rt.commit(tx, facts, [GiftGoldenInvariant.new()])
	return {"result": cr}

## 失败码 → 既存失败标签（与旧 give_gift 失败分支同集，API 形状保真）
static func tag_for(code: StringName) -> String:
	match code:
		ErrorCode.ITEM_NOT_FOUND:
			return "REMOVE_FAILED"
		_:
			return "INVALID"

# ================= 内部类：Effect（0-C.2 Mutation 步，各写各 Owner） =================

## 背包实例消耗（Owner=inventory）：按 iid 扣 1（与用药同源）。
class GiftInstanceConsumeEffect extends Effect:
	var _inv: InventoryService
	var _instance_id: String
	var _item_id: String

	func _init(inv: InventoryService, instance_id: String, item_id: String) -> void:
		_inv = inv
		_instance_id = instance_id
		_item_id = item_id

	func apply(ctx: MutationContext) -> OperationResult:
		var before: int = _inv.get_item_count(_item_id)
		if not _inv.consume_instance(_instance_id):
			return OperationResult.fail(ErrorCode.ITEM_NOT_FOUND, "consume_instance refused", {"iid": _instance_id})
		ctx.register(&"player_inventory", &"inventory", StringName("gift_%s" % _instance_id), GiftInstanceConsumeUndo.new(_inv, _item_id), before, before - 1)
		return OperationResult.ok()

## 好感变更（Owner=relationship）：走 bond 静默变更执行端（TX-2 Effect 内部实现）。
class AffectionMutationEffect extends Effect:
	var _bond: BondService
	var _npc_id: String
	var _gain: int
	var _source: String
	var _snapshot: Dictionary = {}

	func _init(bond: BondService, npc_id: String, gain: int, source: String) -> void:
		_bond = bond
		_npc_id = npc_id
		_gain = gain
		_source = source

	func apply(ctx: MutationContext) -> OperationResult:
		_snapshot = _bond.apply_affection_mutation(_npc_id, _gain, _source)
		ctx.register(&"bond_affection", &"relationship", StringName("affection_%s" % _npc_id),
			AffectionMutationUndo.new(_bond, _npc_id, int(_snapshot["before"]), int(_snapshot["log_size"])),
			int(_snapshot["before"]), int(_snapshot["after"]))
		return OperationResult.ok()

## 送礼计数（Owner=relationship）：+1；undo=−1。
class GiftCountEffect extends Effect:
	var _bond: BondService
	var _npc_id: String

	func _init(bond: BondService, npc_id: String) -> void:
		_bond = bond
		_npc_id = npc_id

	func apply(ctx: MutationContext) -> OperationResult:
		var before: int = int(_bond.gift_count.get(_npc_id, 0))
		var after: int = _bond.adjust_gift_count(_npc_id, 1)
		ctx.register(&"bond_gift_count", &"relationship", StringName("gift_count_%s" % _npc_id), GiftCountUndo.new(_bond, _npc_id), before, after)
		return OperationResult.ok()

# ================= 内部类：UndoStrategy（State Owner 提供具体恢复，01 §18） =================

## 消耗逆操作=按内容补回 1 件（实例身份不可复活，与 ShopTrade InventoryRemoveUndo 同语义；
## 满包极端态 → false → RECOVERY_REQUIRED，禁静默吞）。
class GiftInstanceConsumeUndo extends UndoStrategy:
	var _inv: InventoryService
	var _item_id: String

	func _init(inv: InventoryService, item_id: String) -> void:
		_inv = inv
		_item_id = item_id

	func restore() -> bool:
		return _inv.add_item(_item_id, 1, "gift_rollback")

## 好感逆操作=静默恢复 before 值+日志截断（set_affection 恢复路径形态，TX-2）。
class AffectionMutationUndo extends UndoStrategy:
	var _bond: BondService
	var _npc_id: String
	var _before: int
	var _log_size: int

	func _init(bond: BondService, npc_id: String, before: int, log_size: int) -> void:
		_bond = bond
		_npc_id = npc_id
		_before = before
		_log_size = log_size

	func restore() -> bool:
		_bond.restore_affection_mutation(_npc_id, _before, _log_size)
		return true

## 计数逆操作=−1（不低于 0 钳制在 bond 执行端）。
class GiftCountUndo extends UndoStrategy:
	var _bond: BondService
	var _npc_id: String

	func _init(bond: BondService, npc_id: String) -> void:
		_bond = bond
		_npc_id = npc_id

	func restore() -> bool:
		_bond.adjust_gift_count(_npc_id, -1)
		return true

# ================= 内部类：0-C.19 Golden Invariant + 只读 Facts 门面 =================

## 只读事实门面：affection/gift_count/item_count 实时读数 vs 事务前快照推算期望值。
class GiftFacts extends GameFacts:
	var _bond: BondService
	var _inv: InventoryService
	var _npc_id: String
	var _item_id: String
	var _expect_aff: int
	var _expect_gc: int
	var _expect_count: int

	func _init(bond: BondService, inv: InventoryService, npc_id: String, item_id: String, expect_aff: int, expect_gc: int, expect_count: int) -> void:
		_bond = bond
		_inv = inv
		_npc_id = npc_id
		_item_id = item_id
		_expect_aff = expect_aff
		_expect_gc = expect_gc
		_expect_count = expect_count

	func get_int(key: StringName) -> int:
		match key:
			&"affection":
				return _bond.get_affection(_npc_id)
			&"gift_count":
				return int(_bond.gift_count.get(_npc_id, 0))
			&"item_count":
				return _inv.get_item_count(_item_id)
			&"expect_affection":
				return _expect_aff
			&"expect_gift_count":
				return _expect_gc
			&"expect_item_count":
				return _expect_count
			_:
				return 0

	func get_bool(_key: StringName) -> bool:
		return false

	func get_entity_id(_key: StringName) -> EntityId:
		return EntityId.of(&"NPC", _npc_id)

## Gift Golden Case：好感/计数/物品三侧等式必须同时成立，任一不成立=INVARIANT_VIOLATION
## → commit 逆序回滚（对位 0-C.19 Purchase Golden Invariant）。
class GiftGoldenInvariant extends Rule:
	func evaluate(facts: GameFacts) -> OperationResult:
		var ok_aff: bool = facts.get_int(&"affection") == facts.get_int(&"expect_affection")
		var ok_gc: bool = facts.get_int(&"gift_count") == facts.get_int(&"expect_gift_count")
		var ok_count: bool = facts.get_int(&"item_count") == facts.get_int(&"expect_item_count")
		if ok_aff and ok_gc and ok_count:
			return OperationResult.ok()
		return OperationResult.fail(ErrorCode.INVARIANT_VIOLATION, "gift golden case violated (TX-1)",
			{
				"affection": facts.get_int(&"affection"),
				"expect_affection": facts.get_int(&"expect_affection"),
				"gift_count": facts.get_int(&"gift_count"),
				"expect_gift_count": facts.get_int(&"expect_gift_count"),
				"item_count": facts.get_int(&"item_count"),
				"expect_item_count": facts.get_int(&"expect_item_count"),
			})

# ================= 内部类：Pending→Committed Domain Event（0-B.12 强类型载荷） =================

## 送礼事实事件（过去时命名）：commit 成功后经 Runtime 推进 Committed（0-C.7）；
## EventBus 发射是 commit 后投影（BondService 层）。
class GiftEvent extends DomainEvent:
	var npc_id: String
	var item_id: String
	var gain: int

	func _init(npc: String, item: String, affection_gain: int) -> void:
		GiftTransaction._event_seq += 1
		super(StringName("BOND_GIFT_%04d" % GiftTransaction._event_seq), &"BOND_GIFT_GIVEN")
		self.npc_id = npc
		self.item_id = item
		self.gain = affection_gain
