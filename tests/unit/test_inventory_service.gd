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

func after_each() -> void:
	# 力量是全局单例，复位避免污染其他用例/套件（负重相关测试会改它）
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.strength = 10
	# 难度是全局单例，复位到 NORMAL 避免团灭丢物配置测试污染其他用例
	EventBus.cmd_set_difficulty.emit("NORMAL", true)

func test_add_item_success() -> void:
	expect(_service.add_item(PILL, 5), "添加应成功")
	expect_eq(_service.get_item_count(PILL), 5, "应有 5 个")

func test_add_item_full_and_overflow_event() -> void:
	# 拉高强度把负重上限顶高，隔离"槽位满"逻辑（武器单件 3.5 重，力量10时只能装 21 件）
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.strength = 1000
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
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.strength = 1000
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
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.strength = 1000
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

func test_get_max_weight_strength_coupling() -> void:
	# 真负重：max = BASE(50) + strength * COEFF(2.5)
	var ps: PlayerState = GameManager.player_state
	expect(ps != null, "player_state 应存在")
	if ps == null:
		return
	ps.strength = 10
	expect_eq(_service.get_max_weight(), 75.0, "力量10时上限=50+10*2.5=75")
	ps.strength = 20
	expect_eq(_service.get_max_weight(), 100.0, "力量20时上限=50+20*2.5=100")
	ps.strength = 10

func test_query_add_weight_limited() -> void:
	# 精铁矿石 weight=1.0；力量10时上限75 → 重量限制为 75 件（材料箱 200 格远大于此）
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.strength = 10
	var q: Dictionary = _service.query_add("material_ore_001", 1000)
	expect_eq(int(q["added"]), 75, "重量上限应限制为 75 件")
	expect_eq(int(q["overflow"]), 925, "溢出应为 925")

func test_add_respects_weight_cap() -> void:
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.strength = 10
	var overflow_count: Array = []
	var cb := func(item_id: String, lost: int) -> void:
		overflow_count.append([item_id, lost])
	EventBus.inventory_add_overflow.connect(cb)
	var ok := _service.add_item("material_ore_001", 80, "test")
	EventBus.inventory_add_overflow.disconnect(cb)
	expect(not ok, "超重时 add 应返回 false（未全部装入）")
	expect_eq(_service.get_item_count("material_ore_001"), 75, "实际装入应恰好 75 件（卡在负重上限）")
	expect(overflow_count.size() == 1, "应发 1 次溢出事件")
	if overflow_count.size() == 1:
		expect_eq(int(overflow_count[0][1]), 5, "溢出量应为 5")

func _first_iid(item_id: String) -> String:
	for bag in [_service.main_slots, _service.material_slots, _service.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				return String(inst.instance_id)
	return ""

# ── 团灭丢物规则配置化回归（数值进 JSON，去除硬编码 rarity=="common"）──

func test_lose_items_respects_rarity_config() -> void:
	# 默认难度（NORMAL）defeat_lose_rarities 默认 ["common"]：只丢 common，非 common 保留
	_service.add_item("pill_heal_xiaohuan_001", 3, "test")   # common
	_service.add_item("pill_heal_dahuang_001", 1, "test")    # uncommon
	var lost := _service.lose_some_non_rare_items(2)
	expect_eq(_service.get_item_count("pill_heal_xiaohuan_001"), 1, "common 小还丹应被丢 2 件，剩 1")
	expect_eq(_service.get_item_count("pill_heal_dahuang_001"), 1, "uncommon 大还丹应被保留")
	expect_eq(lost.size(), 2, "应返回 2 个丢失 id")
	for id in lost:
		expect(String(id) == "pill_heal_xiaohuan_001", "丢失列表只应含 common 物品")

func test_lose_items_slot_scope_follows_config() -> void:
	# 切到 HARD：defeat_lose_include_material 默认 false → 材料栏不丢，主栏 common 照丢
	EventBus.cmd_set_difficulty.emit("HARD", true)
	expect_eq(DifficultyManager.get_defeat_lose_include_material(), false, "HARD 默认不波及材料栏")
	_service.add_item("weapon_sword_iron_001", 3, "test")    # 主栏 common
	_service.add_item("material_ore_001", 3, "test")         # 材料栏 common
	var lost := _service.lose_some_non_rare_items(2)
	expect_eq(_service.get_item_count("weapon_sword_iron_001"), 1, "主栏 common 武器应被丢 2 件")
	expect_eq(_service.get_item_count("material_ore_001"), 3, "材料栏不应被波及（include_material=false）")
	expect_eq(lost.size(), 2, "应只丢主栏 2 件")

# ── 物品锁定保护 + 容量查询 API（P2-3）回归 ──

func _all_iids(item_id: String) -> Array:
	var out: Array = []
	for bag in [_service.main_slots, _service.material_slots, _service.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				out.append(String(inst.instance_id))
	return out

func test_lock_skips_passive_remove() -> void:
	# WEAPON max_stack=1 → 3 次 add 得 3 个独立实例，便于测"跳过锁定实例"
	_service.add_item(WEAPON, 1, "test")
	_service.add_item(WEAPON, 1, "test")
	_service.add_item(WEAPON, 1, "test")
	var iids: Array = _all_iids(WEAPON)
	expect_eq(iids.size(), 3, "应有 3 个独立实例")
	# 锁第 1、3 个，留第 2 个未锁
	expect(_service.set_item_locked(iids[0], true), "锁定实例1应成功")
	expect(_service.set_item_locked(iids[2], true), "锁定实例3应成功")
	expect(_service.is_item_locked(iids[0]), "查询应返回已锁定")
	# 被动移除应跳过锁定实例，只扣未锁的第 2 个
	expect(_service.remove_item_by_id(WEAPON, 1), "扣未锁实例应成功")
	expect_eq(_service.get_item_count(WEAPON), 2, "应剩 2 个（2 个锁定）")
	expect(_service.is_item_locked(iids[0]), "锁定实例仍在")
	# 剩下的全是锁定的 → 被动移除应整体失败（保护关键物）
	expect(not _service.remove_item_by_id(WEAPON, 1), "其余已锁定时移除应失败")
	expect_eq(_service.get_item_count(WEAPON), 2, "锁定物不应被移除")

func test_try_consume_respects_lock() -> void:
	_service.add_item(WEAPON, 1, "test")
	_service.add_item(WEAPON, 1, "test")
	_service.add_item(WEAPON, 1, "test")
	var locked_iid: String = _first_iid(WEAPON)
	_service.set_item_locked(locked_iid, true)
	# 非锁定可用量=2，批量扣料应只扣未锁的，不动锁定的
	expect(_service.try_consume([{ "item_id": WEAPON, "count": 2 }], "test"), "扣 2 件未锁应成功")
	expect_eq(_service.get_item_count(WEAPON), 1, "应剩 1 个锁定的")
	expect(_service.is_item_locked(locked_iid), "锁定实例未被扣")
	# 非锁定可用量=0 → 即便需求=1 也整体失败（锁保护 + 原子性）
	expect(not _service.try_consume([{ "item_id": WEAPON, "count": 1 }], "test"), "全锁定时批量扣料应整体失败")
	expect_eq(_service.get_item_count(WEAPON), 1, "失败时锁定物不被动")

func test_lose_items_skips_locked() -> void:
	# 团灭丢失应跳过锁定关键物（与 rarity 配置无关）
	_service.add_item(WEAPON, 3, "test")   # 主栏 common，3 实例
	var locked_iid: String = _first_iid(WEAPON)
	_service.set_item_locked(locked_iid, true)
	var lost := _service.lose_some_non_rare_items(2)
	expect_eq(_service.get_item_count(WEAPON), 1, "锁定的 1 件应被保留，未锁 2 件被丢")
	expect(_service.is_item_locked(locked_iid), "锁定实例团灭后仍在")
	expect_eq(lost.size(), 2, "应丢 2 件未锁的")

func test_capacity_api() -> void:
	# 三栏总槽位：主30 + 材料200 + 任务50 = 280
	expect_eq(_service.get_total_slots(), 280, "总槽位应为 280")
	expect_eq(_service.get_used_slots(), 0, "空包已用 0")
	expect_eq(_service.get_free_slots(), 280, "空包剩余 280")
	_service.add_item(WEAPON, 1, "test")
	_service.add_item(WEAPON, 1, "test")
	_service.add_item(PILL, 5, "test")
	expect_eq(_service.get_used_slots(), 3, "应已用 3 格")
	expect_eq(_service.get_free_slots(), 277, "应剩 277 格")

func test_lock_serialization_roundtrip() -> void:
	_service.add_item(WEAPON, 1, "test")
	var iid: String = _first_iid(WEAPON)
	expect(_service.set_item_locked(iid, true), "锁定应成功")
	var data: Dictionary = _service.save()
	var s2 := InventoryService.new()
	s2.load(data)
	expect(s2.is_item_locked(iid), "读档后锁定状态应保留")
	var data2: Dictionary = s2.save()
	var s3 := InventoryService.new()
	s3.load(data2)
	expect(s3.is_item_locked(iid), "二次存读锁定状态仍保留")

## ===== P2-7：count 缓存索引一致性 =====
func test_count_index_tracks_add_remove() -> void:
	_service.reset()
	_service.add_item(PILL, 5)
	expect_eq(_service.get_item_count(PILL), 5, "新增后缓存计数应=5")
	_service.remove_item_by_id(PILL, 2)
	expect_eq(_service.get_item_count(PILL), 3, "移除后缓存计数应=3")
	_service.remove_item_by_id(PILL, 3)
	expect_eq(_service.get_item_count(PILL), 0, "清空后缓存应归零")

func test_count_index_lock_keeps_total() -> void:
	_service.reset()
	_service.add_item(WEAPON, 3)   # max_stack=1 -> 3 个主栏实例
	var locked := 0
	for inst in _service.main_slots:
		if inst != null and inst.item_id == WEAPON and locked < 2:
			_service.set_item_locked(String(inst.instance_id), true)
			locked += 1
	expect_eq(_service.get_item_count(WEAPON), 3, "锁定不改变总数，缓存应仍=3")
	expect_eq(_service.get_unlocked_count(WEAPON), 1, "非锁定应=1")
	_service.remove_item_by_id(WEAPON, 1)   # 只移未锁的那 1 个
	expect_eq(_service.get_item_count(WEAPON), 2, "移除未锁后总数=2，缓存同步")
	expect_eq(_service.get_unlocked_count(WEAPON), 0, "未锁应耗尽")

func test_count_index_rebuild_on_load() -> void:
	_service.reset()
	_service.add_item(PILL, 4)
	_service.add_item("material_ore_001", 7)
	var data: Dictionary = _service.save()
	_service.reset()
	_service.load(data)
	expect_eq(_service.get_item_count(PILL), 4, "load 后缓存应重建为 4")
	expect_eq(_service.get_item_count("material_ore_001"), 7, "load 后缓存应重建为 7")

func test_item_config_integrity() -> void:
	# Phase 3 内容扩张：校验全部物品配置可被正确解析且字段自洽（防 JSON 写坏/flag 配错）
	var files := ["weapons", "pills", "equipment", "materials"]
	var valid_types := ["weapon", "armor", "pill", "material", "accessory", "quest"]
	var valid_rarities := ["common", "uncommon", "rare", "epic", "legendary"]
	var seen_ids := {}
	for fname in files:
		var path := "res://data/configs/items/%s.json" % fname
		var fa := FileAccess.open(path, FileAccess.READ)
		expect(fa != null, "能打开 %s.json" % fname)
		if fa == null:
			continue
		var text := fa.get_as_text()
		fa.close()
		var parsed: Variant = JSON.parse_string(text)
		expect(parsed is Dictionary, "%s.json 顶层为对象" % fname)
		if not (parsed is Dictionary):
			continue
		var items: Array = parsed.get("items", [])
		expect(items.size() > 0, "%s.json 至少含 1 条物品" % fname)
		for entry in items:
			var id: String = String(entry.get("id", ""))
			expect(id != "", "%s 中每条都有 id" % fname)
			expect(not seen_ids.has(id), "id 全局唯一: %s" % id)
			seen_ids[id] = true
			var t: String = String(entry.get("type", ""))
			expect(valid_types.has(t), "%s type 合法(%s)" % [id, t])
			var r: String = String(entry.get("rarity", ""))
			expect(valid_rarities.has(r), "%s rarity 合法(%s)" % [id, r])
			var flags: int = int(entry.get("flags", 0))
			expect(flags > 0, "%s flags 为正整数" % id)
			var max_stack: int = int(entry.get("max_stack", 1))
			if (flags & ItemEnums.ItemFlag.EQUIPPABLE) != 0:
				expect_eq(max_stack, 1, "%s 可装备必 max_stack=1" % id)
			if (flags & ItemEnums.ItemFlag.STACKABLE) != 0:
				expect(max_stack > 1, "%s 可堆叠必 max_stack>1" % id)

## === P2-9(#163) 槽位顺序保真（为 UI 窗口 P2-1 拖拽 move_instance 做存档支撑）===

func test_slot_order_preserved_after_drag_save_load() -> void:
	# 拖拽 move_instance 的结果须能存读保真：index5 命中该实例、原 index1 空
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.strength = 1000   # 拉高强度隔离负重干扰
	_service.add_item(WEAPON, 1, "t")
	_service.add_item(WEAPON, 1, "t")
	expect(_service.main_slots[0] != null, "index0 应有武器")
	expect(_service.main_slots[1] != null, "index1 应有武器")
	var iid_at_1: String = _service.main_slots[1].instance_id
	expect(_service.move_instance(iid_at_1, "main", 5), "拖拽到 index5 应成功")
	expect(_service.main_slots[5] != null and _service.main_slots[5].instance_id == iid_at_1, "拖拽后 index5 应命中该实例")
	expect(_service.main_slots[1] == null, "原 index1 应空")
	var snap: Dictionary = _service.save()
	var s2 := InventoryService.new()
	s2.load(snap)
	expect(s2.main_slots[5] != null and s2.main_slots[5].instance_id == iid_at_1, "读档后 index5 仍命中该实例（顺序保真）")
	expect(s2.main_slots[1] == null, "读档后 index1 仍空")
	expect_eq(s2.get_item_count(WEAPON), 2, "总数不变")

func test_load_legacy_save_without_idx_compat() -> void:
	# 兼容旧档（裸 ItemInstance 字典、无 idx 键）：不崩且物品数不变
	var s := InventoryService.new()
	s.add_item(WEAPON, 1, "t")
	var snap: Dictionary = s.save()
	var legacy_main: Array = []
	for e in snap["main"]:
		legacy_main.append(e["data"])   # 去掉 {idx,data} 包装，模拟旧格式
	var legacy: Dictionary = {
		"main": legacy_main,
		"material": snap["material"],
		"quest": snap["quest"],
		"weight": snap["weight"],
		"next_iid": snap["next_iid"],
	}
	var s2 := InventoryService.new()
	s2.load(legacy)
	expect_eq(s2.get_item_count(WEAPON), 1, "旧档应能载入，物品数不变")
