# services/shop/shop_trade_transaction.gd
# 买卖事务编排（10 图 EC-5 / 宪法 0-C.19 / 01 §60 七步 / 09 TX-3·TX-4 / D-10 收编）。
# 购买链路唯一合法形状（01 §60）：
#   Shop Validation → Economy Validation → Transaction → Money Mutation
#   → Inventory Mutation → Commit → Purchase Events
# 本类只承担 Transaction→Commit 段（前两段 Validation 在 ShopService 预检，事件投影在
# ShopService commit 后发射=0-C.7 Committed Event 投影）。Shop 不直碰 Wallet 的语义由
# Effect 边界物理化：银两变更只经 WalletMutationEffect（Owner=economy），物品变更只经
# Inventory*Effect（Owner=inventory），各写各 Owner，事务捆住（09 TX-3）。
# 0-C.19 Purchase Golden Invariant（VS-001 永久回归）：
#   成功 GoldAfter=GoldBefore-Price ∧ InventoryAfter=InventoryBefore+Item
#   失败两侧零变化（由 rollback 保证，测试钉死）。
# 落位备注：Effect/Undo 内部类随 shop 收编批暂驻本文件（每状态键一个类已追认），
# Phase4 模块重排时 Wallet 类随 economy、Inventory 类随 inventory 迁移（ADR_INDEX §4 有口）。
#
# 矩阵映射（宪法 0-C.20，GATE26）：Runtime 层十一路由 tests/unit/test_transaction_runtime.gd
# 承接；本类+test_shop_trade_tx 承接业务侧可达场景——成功 / Precheck 失败 / 首个
# Mutation 失败（sell remove）/ 中间 Mutation 失败（buy add）/ Invariant 失败 /
# 连续事务（0-C.10 释放正确性）。Cancel/Timeout/Save Failure/Event Handler 失败/
# Rollback Failure 属 Runtime 职责，不在业务层重复。

class_name ShopTradeTransaction
extends RefCounted

static var _event_seq: int = 0

var _rt: TransactionRuntime

func _init(rt: TransactionRuntime = null) -> void:
	_rt = rt if rt != null else TransactionRuntime.new()

## 执行买入事务（total=应扣银两，count=件数）。
## 返回单形态 Dictionary：
##   result: CommandResult（committed / rejected / recovery_required）
##   fail_tag: String（失败时给 UI 的既存英文标签，与旧 buy 失败分支同集）
func execute_buy(ps: PlayerState, inv: InventoryService, shop_id: String, item_id: String, total: int, count: int) -> Dictionary:
	var silver0: int = ps.silver
	var count0: int = inv.get_item_count(item_id)
	var tx := _rt.begin()
	var ctx := MutationContext.new(tx.get_transaction_id())
	var effects: Array[Effect] = [
		WalletMutationEffect.new_spend(ps, total),
		InventoryAddEffect.new(inv, item_id, count, "shop_buy"),
	]
	var r := _rt.run(tx, effects, ctx)
	if r.is_failed():
		return _finish_failure(tx, r.get_error().get_code(), "buy", shop_id, item_id)
	_rt.add_pending_event(tx, TradeEvent.new(item_id, shop_id, count, total / maxi(count, 1), true))
	var facts := ShopTradeFacts.new(ps, inv, item_id, silver0 - total, count0 + count)
	var cr := _rt.commit(tx, facts, [TradeGoldenInvariant.new()])
	return {"result": cr, "fail_tag": "INVALID"}

## 执行卖出事务（total=应得银两；先扣货后给钱，10 图 P-E5 冻结序）。
func execute_sell(ps: PlayerState, inv: InventoryService, shop_id: String, item_id: String, total: int, count: int) -> Dictionary:
	var silver0: int = ps.silver
	var count0: int = inv.get_item_count(item_id)
	var tx := _rt.begin()
	var ctx := MutationContext.new(tx.get_transaction_id())
	var effects: Array[Effect] = [
		InventoryRemoveEffect.new(inv, item_id, count),
		WalletMutationEffect.new_earn(ps, total),
	]
	var r := _rt.run(tx, effects, ctx)
	if r.is_failed():
		return _finish_failure(tx, r.get_error().get_code(), "sell", shop_id, item_id)
	_rt.add_pending_event(tx, TradeEvent.new(item_id, shop_id, count, total / maxi(count, 1), false))
	var facts := ShopTradeFacts.new(ps, inv, item_id, silver0 + total, count0 - count)
	var cr := _rt.commit(tx, facts, [TradeGoldenInvariant.new()])
	return {"result": cr, "fail_tag": "INVALID"}

# ---------------- 内部 ----------------

## run 失败统一出口：逆序回滚（0-C.8）→ 失败码透传；回滚自身失败 → RECOVERY_REQUIRED
## 原样上抛（0-C.9 禁静默，五元组在 error context，由调用方 push_error）。
func _finish_failure(tx: TransactionContext, code: StringName, op: String, shop_id: String, item_id: String) -> Dictionary:
	var rb := _rt.rollback(tx, code, {"op": op, "shop": shop_id, "item": item_id})
	if rb.is_recovery_required():
		return {"result": rb, "fail_tag": "INVALID"}
	return {"result": rb, "fail_tag": tag_for(code)}

static func tag_for(code: StringName) -> String:
	match code:
		ErrorCode.INSUFFICIENT_FUNDS:
			return "NO_MONEY"
		ErrorCode.INSUFFICIENT_CAPACITY:
			return "BAG_FULL"
		ErrorCode.ITEM_NOT_FOUND:
			return "NO_ITEM"
		_:
			return "INVALID"

# ================= 内部类：Effect（0-C.2 Money/Inventory Mutation 步） =================

## 银两变更（Owner=economy）：delta<0 走 spend_money（不足拒扣），delta>0 走 add_money。
class WalletMutationEffect extends Effect:
	var _ps: PlayerState
	var _delta: int

	func _init(ps: PlayerState, delta: int) -> void:
		_ps = ps
		_delta = delta

	static func new_spend(ps: PlayerState, amount: int) -> WalletMutationEffect:
		return WalletMutationEffect.new(ps, -amount)

	static func new_earn(ps: PlayerState, amount: int) -> WalletMutationEffect:
		return WalletMutationEffect.new(ps, amount)

	func apply(ctx: MutationContext) -> OperationResult:
		var before: int = _ps.silver
		var after: int = before + _delta
		var ok: bool
		if _delta < 0:
			ok = _ps.spend_money(-_delta)
			if not ok:
				return OperationResult.fail(ErrorCode.INSUFFICIENT_FUNDS, "spend_money refused", {"before": before, "want": -_delta})
		else:
			_ps.add_money(_delta)
			ok = true
		ctx.register(&"player_wallet", &"economy", &"silver", WalletUndo.new(_ps, _delta), before, after)
		return OperationResult.ok()

## 背包入货（Owner=inventory）：走 add_item（P0 后含聚合预检），失败=容量不足。
class InventoryAddEffect extends Effect:
	var _inv: InventoryService
	var _item_id: String
	var _count: int
	var _source: String

	func _init(inv: InventoryService, item_id: String, count: int, source: String) -> void:
		_inv = inv
		_item_id = item_id
		_count = count
		_source = source

	func apply(ctx: MutationContext) -> OperationResult:
		var before: int = _inv.get_item_count(_item_id)
		if not _inv.add_item(_item_id, _count, _source):
			return OperationResult.fail(ErrorCode.INSUFFICIENT_CAPACITY, "add_item refused", {"item": _item_id, "count": _count})
		ctx.register(&"player_inventory", &"inventory", StringName("item_%s" % _item_id), InventoryAddUndo.new(_inv, _item_id, _count), before, before + _count)
		return OperationResult.ok()

## 背包出货（Owner=inventory）：走 remove_item_by_id（尊重锁定），失败=可动量不足。
class InventoryRemoveEffect extends Effect:
	var _inv: InventoryService
	var _item_id: String
	var _count: int

	func _init(inv: InventoryService, item_id: String, count: int) -> void:
		_inv = inv
		_item_id = item_id
		_count = count

	func apply(ctx: MutationContext) -> OperationResult:
		var before: int = _inv.get_item_count(_item_id)
		if not _inv.remove_item_by_id(_item_id, _count):
			return OperationResult.fail(ErrorCode.ITEM_NOT_FOUND, "remove_item_by_id refused", {"item": _item_id, "count": _count})
		ctx.register(&"player_inventory", &"inventory", StringName("item_%s" % _item_id), InventoryRemoveUndo.new(_inv, _item_id, _count), before, before - _count)
		return OperationResult.ok()

# ================= 内部类：UndoStrategy（State Owner 提供具体恢复，01 §18） =================

## 银两逆操作：spend 的 undo=补回 add_money；earn 的 undo=补扣 spend_money
## （补扣失败=钱已花掉无法恢复 → false → RECOVERY_REQUIRED，0-C.9 语义正确）。
class WalletUndo extends UndoStrategy:
	var _ps: PlayerState
	var _delta: int

	func _init(ps: PlayerState, delta: int) -> void:
		_ps = ps
		_delta = delta

	func restore() -> bool:
		if _delta < 0:
			_ps.add_money(-_delta)
			return true
		return _ps.spend_money(_delta)

## 加货逆操作=移除刚加的量（刚加实例未被锁定，理论恒可达；false → RECOVERY_REQUIRED）。
class InventoryAddUndo extends UndoStrategy:
	var _inv: InventoryService
	var _item_id: String
	var _count: int

	func _init(inv: InventoryService, item_id: String, count: int) -> void:
		_inv = inv
		_item_id = item_id
		_count = count

	func restore() -> bool:
		return _inv.remove_item_by_id(_item_id, _count)

## 出货逆操作=补回刚扣的量（满包等极端态 → false → RECOVERY_REQUIRED，禁静默吞）。
class InventoryRemoveUndo extends UndoStrategy:
	var _inv: InventoryService
	var _item_id: String
	var _count: int

	func _init(inv: InventoryService, item_id: String, count: int) -> void:
		_inv = inv
		_item_id = item_id
		_count = count

	func restore() -> bool:
		return _inv.add_item(_item_id, _count, "shop_rollback")

# ================= 内部类：0-C.19 Golden Invariant + 只读 Facts 门面 =================

## 只读事实门面（GameFacts 强类型取值）：silver/item_count 为实时读数，
## expect_* 为事务前快照推算的黄金等式期望值。
class ShopTradeFacts extends GameFacts:
	var _ps: PlayerState
	var _inv: InventoryService
	var _item_id: String
	var _expect_silver: int
	var _expect_count: int

	func _init(ps: PlayerState, inv: InventoryService, item_id: String, expect_silver: int, expect_count: int) -> void:
		_ps = ps
		_inv = inv
		_item_id = item_id
		_expect_silver = expect_silver
		_expect_count = expect_count

	func get_int(key: StringName) -> int:
		match key:
			&"silver":
				return _ps.silver
			&"item_count":
				return _inv.get_item_count(_item_id)
			&"expect_silver":
				return _expect_silver
			&"expect_count":
				return _expect_count
			_:
				return 0

	func get_bool(_key: StringName) -> bool:
		return false

	func get_entity_id(_key: StringName) -> EntityId:
		return EntityId.of(&"shop_trade", _item_id)

## 0-C.19 Purchase Golden Case（VS-001 永久 Golden Invariant）：
## 银两与物品两侧等式必须同时成立，任一不成立 = INVARIANT_VIOLATION → commit 逆序回滚。
class TradeGoldenInvariant extends Rule:
	func evaluate(facts: GameFacts) -> OperationResult:
		var ok_silver: bool = facts.get_int(&"silver") == facts.get_int(&"expect_silver")
		var ok_count: bool = facts.get_int(&"item_count") == facts.get_int(&"expect_count")
		if ok_silver and ok_count:
			return OperationResult.ok()
		return OperationResult.fail(
			ErrorCode.INVARIANT_VIOLATION,
			"purchase golden case violated (0-C.19)",
			{
				"silver": facts.get_int(&"silver"),
				"expect_silver": facts.get_int(&"expect_silver"),
				"item_count": facts.get_int(&"item_count"),
				"expect_count": facts.get_int(&"expect_count"),
			}
		)

# ================= 内部类：Pending→Committed Domain Event（0-B.12 强类型载荷） =================

## 交易事实事件（过去时命名）：事务内 add_pending_event 登记，仅 commit 成功后
## 由 Runtime 推进 Committed（0-C.7）；EventBus 发射是 commit 后的投影（ShopService 层）。
class TradeEvent extends DomainEvent:
	var shop_id: String
	var item_id: String
	var count: int
	var unit_price: int
	var is_buy: bool

	func _init(item_id: String, shop_id: String, count: int, unit_price: int, buy: bool) -> void:
		ShopTradeTransaction._event_seq += 1
		super(StringName("SHOP_TRADE_%04d" % ShopTradeTransaction._event_seq), &"ITEM_PURCHASED" if buy else &"ITEM_SOLD")
		self.shop_id = shop_id
		self.item_id = item_id
		self.count = count
		self.unit_price = unit_price
		self.is_buy = buy
