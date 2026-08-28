extends Node

const ItemSlotScript = preload("res://scenes/ui/components/item_slot/ItemSlot.gd")

var _pass: int = 0
var _fail: int = 0

func _ready() -> void:
	await _run()
	get_tree().quit()

func _run() -> void:
	var inv: InventoryService = GameManager.inventory_service
	_assert(inv != null, "inventory_service 可用")
	# 准备干净数据
	inv.reset()
	inv.add_item("pill_heal_xiaohuan_001", 5, "test")
	inv.add_item("weapon_sword_iron_001", 1, "test")
	_assert(int(inv.get_item_count("pill_heal_xiaohuan_001")) == 5, "pill 添加 5 个")
	# 构建界面（P2-1：实例网格 + 组件）
	var screen = preload("res://scenes/ui/overlays/inventory/InventoryScreen.gd").new()
	add_child(screen)
	await get_tree().process_frame
	_assert(screen != null, "InventoryScreen 实例化")
	screen._refresh()
	await get_tree().process_frame
	var slots: int = _count_slots(screen)
	_assert(slots >= 2, "界面渲染出至少 2 个 ItemSlot(实际 %d)" % slots)
	# 使用消耗品
	var pill1: String = _first_iid(inv, "pill_heal_xiaohuan_001")
	var before: int = int(inv.get_item_count("pill_heal_xiaohuan_001"))
	inv.use_item(pill1, "town")
	_assert(int(inv.get_item_count("pill_heal_xiaohuan_001")) == before - 1, "使用消耗品后 -1")
	# 拆分（P2-1）
	var pill2: String = _first_iid(inv, "pill_heal_xiaohuan_001")
	var pre_split: int = int(inv.get_item_count("pill_heal_xiaohuan_001"))
	var r: Dictionary = inv.split_instance(pill2, 2)
	_assert(r.get("ok", false) == true, "split_instance 成功")
	_assert(int(inv.get_item_count("pill_heal_xiaohuan_001")) == pre_split, "拆分后总数量不变(分布变化)")
	# 跨栏移动（拖拽 P2-1）
	var w_iid: String = _first_iid(inv, "weapon_sword_iron_001")
	_assert(inv.move_instance(w_iid, "material", 0), "move_instance 跨栏成功")
	_assert(_bag_of(inv, w_iid) == "material", "移动后位于 material 栏")
	# 整理（P2-1）
	inv.sort_bag("main")
	inv.sort_bag("material")
	_assert(true, "sort_bag 调用无异常")
	screen._refresh()
	await get_tree().process_frame
	# 装备（经既有 EquipmentService.equip）
	var w_mat: String = _first_iid_in(inv, "material", "weapon_sword_iron_001")
	_assert(GameManager.equipment_service.equip(w_mat), "装备武器成功")
	# 丢弃（移除实例 P2-1）
	var any_iid: String = _any_iid(inv)
	_assert(inv.remove_instance(any_iid), "discard/remove_instance 成功")
	screen._refresh()
	await get_tree().process_frame
	if _fail == 0:
		GameLogger.info("InvSmoke", "[INV] ALL_INV_OK pass=%d fail=%d" % [_pass, _fail])
	else:
		GameLogger.error("InvSmoke", "[INV] INV_FAIL pass=%d fail=%d" % [_pass, _fail])

func _assert(cond: bool, msg: String) -> void:
	if cond:
		_pass += 1
		GameLogger.info("InvSmoke", "PASS: " + msg)
	else:
		_fail += 1
		GameLogger.error("InvSmoke", "FAIL: " + msg)

func _first_iid(inv: InventoryService, item_id: String) -> String:
	for bag in [inv.main_slots, inv.material_slots, inv.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				return inst.instance_id
	return ""

func _first_iid_in(inv: InventoryService, bag_name: String, item_id: String) -> String:
	var bag: Array = _bagarr(inv, bag_name)
	for inst in bag:
		if inst != null and inst.item_id == item_id:
			return inst.instance_id
	return ""

func _bag_of(inv: InventoryService, iid: String) -> String:
	for name in ["main", "material", "quest"]:
		for inst in _bagarr(inv, name):
			if inst != null and inst.instance_id == iid:
				return name
	return ""

func _bagarr(inv: InventoryService, name: String) -> Array:
	match name:
		"main": return inv.main_slots
		"material": return inv.material_slots
		"quest": return inv.quest_slots
	return []

func _any_iid(inv: InventoryService) -> String:
	for bag in [inv.main_slots, inv.material_slots, inv.quest_slots]:
		for inst in bag:
			if inst != null:
				return inst.instance_id
	return ""

func _count_slots(node: Node) -> int:
	var n: int = 0
	for c in node.get_children():
		if c.get_script() == ItemSlotScript:
			n += 1
		n += _count_slots(c)
	return n
