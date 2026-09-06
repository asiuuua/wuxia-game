# tests/unit/test_gift_transaction.gd
# 08 图批1 ②：送礼事务化契约（TX-1~TX-4 / RF-R05，ShopTradeTransaction 同款 0-C 形状）。
# 覆盖：成功链 Golden 等式（好感/计数/物品三侧）、中间 Mutation 失败全量逆序回滚
#       （DoD2=「扣了物品好感没加」机制性不可能）、预检形状保真、Runtime 工厂注入。

extends TestBase


func before_each() -> void:
	GameManager.bond_service.reset()
	GameManager.inventory_service.reset()


func _first_iid(item_id: String) -> String:
	for bag in [GameManager.inventory_service.main_slots, GameManager.inventory_service.material_slots, GameManager.inventory_service.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				return inst.instance_id
	return ""


func _add_one(item_id: String) -> String:
	expect(GameManager.inventory_service.add_item(item_id, 1, "test"), "加测试物品应成功：%s" % item_id)
	return _first_iid(item_id)


func test_successful_gift_golden_equations() -> void:
	var bs := GameManager.bond_service
	var inv := GameManager.inventory_service
	var iid := _add_one("pill_heal_dahuang_001")
	var aff0: int = bs.get_affection("npc_su_waner")
	var count0: int = inv.get_item_count("pill_heal_dahuang_001")
	var res: Dictionary = bs.give_gift("npc_su_waner", iid)
	expect(res.get("ok", false), "送礼事务应提交")
	# 0-C.19 同款 Golden Invariant（三侧等式同时成立）
	expect_eq(bs.get_affection("npc_su_waner"), aff0 + 20, "Golden：好感=before+20")
	expect_eq(int(bs.gift_count.get("npc_su_waner", 0)), 1, "Golden：送礼计数+1")
	expect_eq(inv.get_item_count("pill_heal_dahuang_001"), count0 - 1, "Golden：物品-1")


func test_middle_failure_full_rollback() -> void:
	# RF-R05 / DoD2：consume 成功 + 后继 Mutation 失败 → 全量逆序回滚，
	# 「扣了物品好感没加」从机制上不可能。
	var bs := GameManager.bond_service
	var inv := GameManager.inventory_service
	var iid := _add_one("pill_mp_huixue_001")
	var aff0: int = bs.get_affection("npc_su_waner")
	var count0: int = inv.get_item_count("pill_mp_huixue_001")
	var log0: int = bs.interaction_log.size()
	var rt := TransactionRuntime.new()
	var trade := GiftTransaction.new(rt)
	var tx := rt.begin()
	var ctx := MutationContext.new(tx.get_transaction_id())
	var effects: Array[Effect] = [
		GiftTransaction.GiftInstanceConsumeEffect.new(inv, iid, "pill_mp_huixue_001"),
		GiftTransaction.AffectionMutationEffect.new(bs, "npc_su_waner", 3, "gift:test"),
		FailingMutationEffect.new(),
	]
	var r := rt.run(tx, effects, ctx)
	expect(r.is_failed(), "后继 Mutation 失败应使 run 失败")
	var rb := rt.rollback(tx, r.get_error().get_code(), {"op": "gift_test"})
	expect(not rb.is_recovery_required(), "回滚应成功（非 RECOVERY_REQUIRED）")
	expect_eq(inv.get_item_count("pill_mp_huixue_001"), count0, "物品已补回（TX-1 核心保证）")
	expect_eq(bs.get_affection("npc_su_waner"), aff0, "好感零残留")
	expect_eq(int(bs.gift_count.get("npc_su_waner", 0)), 0, "计数零残留")
	expect_eq(bs.interaction_log.size(), log0, "互动日志零残留（undo 快照截断）")
	expect_eq(bs.affection_levels.get("npc_su_waner", -1), bs._level_of(aff0), "等级随值恢复")


func test_precheck_shape_preserved() -> void:
	var bs := GameManager.bond_service
	var r1: Dictionary = bs.give_gift("npc_no_such", "whatever")
	expect(r1.get("reason", "") == "NO_NPC", "未知 NPC 预检标签保真")
	var r2: Dictionary = bs.give_gift("npc_su_waner", "no_such_iid_999")
	expect(r2.get("reason", "") == "NO_ITEM", "未知实例预检标签保真")
	var iid := _add_one("material_ore_001")
	GameManager.inventory_service.get_instance_by_id(iid).locked = true
	var r3: Dictionary = bs.give_gift("npc_su_waner", iid)
	expect(r3.get("reason", "") == "ITEM_LOCKED", "锁定实例预检标签保真")
	for r in [r1, r2, r3]:
		expect(not bool(r.get("ok", true)), "预检失败 ok=false")
		expect_eq(int(r.get("reaction", -1)), -1, "预检失败 reaction=-1")


func test_tag_for_maps_legacy_reasons() -> void:
	expect(GiftTransaction.tag_for(ErrorCode.ITEM_NOT_FOUND) == "REMOVE_FAILED", "消耗失败标签与旧 give_gift 同集")
	expect(GiftTransaction.tag_for(&"SOMETHING_ELSE") == "INVALID", "未知码兜底 INVALID")


func test_golden_invariant_rejects_tampered_facts() -> void:
	var inv_bad := TamperedInventory.new()
	var bs_bad := TamperedBond.new()
	inv_bad.fake_count = 5
	bs_bad.fake_affection = 99
	var facts := TamperedFacts.new()
	facts.values = {
		&"affection": 99, &"expect_affection": 20,
		&"gift_count": 1, &"expect_gift_count": 1,
		&"item_count": 5, &"expect_item_count": 4,
	}
	var r := GiftTransaction.GiftGoldenInvariant.new().evaluate(facts)
	expect(r.is_failed(), "篡改读数必须被 Gift Golden Invariant 拦截")
	expect(r.get_error().get_code() == ErrorCode.INVARIANT_VIOLATION, "失败码=INVARIANT_VIOLATION")
	# 类型面：Facts 门面构造可实例化（强类型取值契约）
	var real_facts := GiftTransaction.GiftFacts.new(bs_bad, inv_bad, "npc_x", "item_x", 1, 1, 1)
	expect(real_facts.get_int(&"affection") == 99, "Facts 实时读数走 bond")
	expect(real_facts.get_int(&"item_count") == 5, "Facts 实时读数走 inv")
	expect(real_facts.get_entity_id(&"affection") != null, "Facts 实体锚")


func test_gift_runtime_factory_injected() -> void:
	# ADR-0007 批B 升表口：ApplicationRoot 注入后 bond 持工厂；旧路径兜底 null。
	var factory: Callable = GameManager.bond_service._gift_runtime_factory
	expect(factory.is_valid(), "GameManager 旧路径亦应注入工厂（批B 转正默认 true）")
	var rt: TransactionRuntime = factory.call()
	expect(rt != null, "工厂产物=TransactionRuntime 新实例")


# ---------------- 测试替身 ----------------

class FailingMutationEffect extends Effect:
	func apply(_ctx: MutationContext) -> OperationResult:
		return OperationResult.fail(ErrorCode.ITEM_NOT_FOUND, "forced failure for rollback test", {})

class TamperedInventory extends InventoryService:
	var fake_count: int = 0
	func get_item_count(_item_id: String) -> int:
		return fake_count

class TamperedBond extends BondService:
	var fake_affection: int = 0
	func get_affection(_npc_id: String) -> int:
		return fake_affection

class TamperedFacts extends GameFacts:
	var values: Dictionary = {}
	func get_int(key: StringName) -> int:
		return int(values.get(key, 0))
	func get_bool(_key: StringName) -> bool:
		return false
	func get_entity_id(_key: StringName) -> EntityId:
		return EntityId.of(&"NPC", "npc_test")
