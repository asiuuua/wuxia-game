# tests/unit/test_inventory_service.gd
# 背包服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 重点：P0 回归保护——满包溢出事件 / query_add 预检 / try_consume 原子性 / iid 唯一性 / next_iid 存读 / use_item

extends TestBase
class_name TestInventoryService

var _service: InventoryService
const PILL := "pill_heal_xiaohuan_001"
const WEAPON := "weapon_sword_iron_001"

func before_each() -> void:
	_service = InventoryService.new()
	_service.reset()

func test_add_item_success() -> void:
	expect(_service.add_item(PILL, 5), "添加应成功")
	expect_eq(_service.get_item_count(PILL), 5, "应有 5 个")

func test_add_item_full_and_overflow_event() -> void:
	for i in 30:
		_service.add_item(WEAPON, 1, "test")
	var overflow_count: Array = []
	var cb := func(item_id: String, lost: int) -> void:
		overflow_count.append([item_id, lost])
	EventBus.inventory_add_overflow.connect(cb)
	var ok := _service.add_item(WEAPON, 1, "test")
	EventBus.inventory_add_overflow.disconnect(cb)
	expect(not ok, "背包满时 add 应失败")
	expect(overflow_count.size() == 1, "应发出 1 次溢出事件")
	if overflow_count.size() == 1:
		expect_eq(int(overflow_count[0][1]), 1, "溢出量应为 1")

func test_remove_item() -> void:
	_service.add_item(PILL, 10, "test")
	expect(_service.remove_item_by_id(PILL, 3), "移除应成功")
	expect_eq(_service.get_item_count(PILL), 7, "应剩 7 个")

func test_unknown_item_rejected() -> void:
	expect(not _service.add_item("no_such_item_999", 1), "不存在的物品应拒绝")
	expect(not _service.can_add("no_such_item_999", 1), "不存在物品 can_add 应 false")
	expect_eq(_service.get_item_count("no_such_item_999"), 0, "不应产生计数")

func test_query_add_stack_math() -> void:
	_service.add_item(PILL, 5, "test")   # 一堆 5/10
	var q: Dictionary = _service.query_add(PILL, 7)
	expect_eq(int(q["added"]), 7, "7 个应全部装下（堆尾5+新堆2）")
	expect_eq(int(q["overflow"]), 0, "不应有溢出")
	var q2: Dictionary = _service.query_add(PILL, 0)
	expect_eq(int(q2["added"]), 0, "count=0 应 added=0")

func test_can_add_false_when_full() -> void:
	for i in 30:
		_service.add_item(WEAPON, 1, "test")
	expect(not _service.can_add(PILL, 1), "主栏满时 can_add 应 false")
	var q: Dictionary = _service.query_add(WEAPON, 3)
	expect_eq(int(q["added"]), 0, "满时 added 应为 0")
	expect_eq(int(q["overflow"]), 3, "满时 overflow 应为 3")

func test_try_consume_atomic() -> void:
	_service.add_item("material_herb_001", 3, "test")
	_service.add_item("material_root_001", 3, "test")
	var ok := _service.try_consume([
		{ "item_id": "material_herb_001", "count": 2 },
		{ "item_id": "material_root_001", "count": 2 },
	], "test")
	expect(ok, "材料充足时应成功")
	expect_eq(_service.get_item_count("material_herb_001"), 1, "草药应 -2")
	expect_eq(_service.get_item_count("material_root_001"), 1, "药根应 -2")
	# 原子性：其一不足则整体不扣
	var ok2 := _service.try_consume([
		{ "item_id": "material_herb_001", "count": 1 },
		{ "item_id": "material_root_001", "count": 99 },
	], "test")
	expect(not ok2, "任一不足应整体失败")
	expect_eq(_service.get_item_count("material_herb_001"), 1, "失败时草药不应被扣")

func test_instance_id_unique_on_batch() -> void:
	var ids := {}
	for i in 30:
		_service.add_item(WEAPON, 1, "test")
	for inst in _service.main_slots:
		if inst == null:
			continue
		var iid: String = String(inst.instance_id)
		expect(not ids.has(iid), "instance_id 不应重复: %s" % iid)
		ids[iid] = true
		expect(iid.contains("#"), "iid 应为 item_id#N 发号器格式: %s" % iid)

func test_next_iid_save_roundtrip() -> void:
	_service.add_item(WEAPON, 3, "test")
	var data: Dictionary = _service.save()
	var service2 := InventoryService.new()
	service2.load(data)
	# 记录读档后已存在的 id 集合，再新增 1 件，断言新件 id 不与旧集合冲突
	var old_ids := {}
	for inst in service2.main_slots:
		if inst != null:
			old_ids[String(inst.instance_id)] = true
	expect_eq(old_ids.size(), 3, "读档应恢复 3 件")
	service2.add_item(WEAPON, 1, "test2")
	for inst in service2.main_slots:
		if inst == null:
			continue
		var iid: String = String(inst.instance_id)
		if old_ids.has(iid):
			continue
		expect(iid.contains("#"), "新发号应为 item_id#N 格式: %s" % iid)
		expect(not old_ids.has(iid), "读档后新发号不应与旧 id 冲突: %s" % iid)

func test_use_item_pill() -> void:
	var ps: PlayerState = GameManager.player_state
	expect(ps != null, "GameManager.player_state 应存在")
	if ps == null:
		return
	var hp0: int = ps.hp
	var max_hp0: int = ps.max_hp
	_service.add_item(PILL, 2, "test")
	ps.hp = max_hp0 - 60
	var res: Dictionary = _service.use_item(_first_iid(PILL), "town")
	expect(bool(res.get("ok", false)), "使用丹药应成功")
	expect_eq(ps.hp, max_hp0 - 10, "吃小还丹应回 50 血")
	expect_eq(_service.get_item_count(PILL), 1, "丹药应剩 1 个")
	ps.hp = hp0
	_service.reset()

func test_use_item_not_consumable() -> void:
	_service.add_item(WEAPON, 1, "test")
	var iid: String = _first_iid(WEAPON)
	var res: Dictionary = _service.use_item(iid, "town")
	expect(not bool(res.get("ok", false)), "武器不可使用")
	expect(String(res.get("reason", "")) == "NOT_CONSUMABLE", "reason 应为 NOT_CONSUMABLE")
	expect_eq(_service.get_item_count(WEAPON), 1, "武器数量不应变化")

func test_consume_instance_reclaims_slot() -> void:
	_service.add_item(PILL, 5, "test")
	var iid: String = _first_iid(PILL)
	for i in 5:
		expect(_service.consume_instance(iid), "第 %d 次扣件应成功" % (i + 1))
	expect_eq(_service.get_item_count(PILL), 0, "应扣空")
	expect(not _service.consume_instance(iid), "实例耗尽后应返回 false")
	var slot_freed := false
	for inst in _service.main_slots:
		if inst == null:
			slot_freed = true
			break
	expect(slot_freed, "耗尽的堆应回收格子")

func _first_iid(item_id: String) -> String:
	for bag in [_service.main_slots, _service.material_slots, _service.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				return String(inst.instance_id)
	return ""
