# tests/unit/test_phase2_pilot.gd
# Phase 2 样板（装备 + 炼药）单元测试（继承 TestBase，被 run_all.tscn 收录）
# 重点：P0 回归保护——满包卸下装备不丢 / 满包换装不丢旧装备 / 满包炼药不扣材料

extends TestBase
class_name TestPhase2Pilot

var _ps: PlayerState
var _inv: InventoryService
var _equip: EquipmentService
var _alchemy: AlchemyService
const WEAPON := "weapon_sword_iron_001"
const BLADE := "weapon_blade_iron_001"
const HERB := "material_herb_001"
const PILL_ID := "pill_heal_xiaohuan_001"

func before_each() -> void:
	_ps = GameManager.player_state
	_inv = GameManager.inventory_service
	_equip = GameManager.equipment_service
	_alchemy = GameManager.alchemy_service
	_inv.reset()
	_equip.reset()
	_ps.init_default("李十五", 1)

func _fill_main_bag() -> void:
	for i in 30:
		_inv.add_item(WEAPON, 1, "test")

func test_equip_raises_attack() -> void:
	var before: int = _ps.attack
	_inv.add_item(WEAPON, 1, "test")
	var insts: Array = _inv.get_equippable_instances()
	expect(insts.size() > 0, "应存在可装备实例")
	var inst: ItemInstance = insts[0]
	expect(_equip.equip(inst.instance_id), "装备应成功")
	expect_eq(_ps.attack, before + 15, "攻击应 +15")
	expect(String(_equip.get_equipped("main_hand")) == WEAPON, "主手应已装备")

func test_unequip_returns_to_inventory() -> void:
	_inv.add_item(WEAPON, 1, "test")
	var inst: ItemInstance = _inv.get_equippable_instances()[0]
	expect(_equip.equip(inst.instance_id), "先装备应成功")
	expect(_equip.unequip("main_hand"), "卸下应成功")
	expect(String(_equip.get_equipped("main_hand")) == "", "主手应清空")
	expect_eq(_inv.get_item_count(WEAPON), 1, "铁剑应退回背包")

func test_full_bag_unequip_keeps_equipment() -> void:
	# P0-3 回归：满包时卸下装备，装备必须留在槽上不消失
	_inv.add_item(WEAPON, 1, "test")
	var inst: ItemInstance = _inv.get_equippable_instances()[0]
	expect(_equip.equip(inst.instance_id), "装备铁剑应成功")
	_fill_main_bag()
	expect(not _equip.unequip("main_hand"), "满包卸下应失败")
	expect(String(_equip.get_equipped("main_hand")) == WEAPON, "失败时装备必须留在槽上")

func test_full_bag_swap_keeps_old() -> void:
	# P0-3 回归：满包换装，旧装备必须退回背包不蒸发
	_inv.add_item(WEAPON, 1, "test")
	var old_inst: ItemInstance = _inv.get_equippable_instances()[0]
	expect(_equip.equip(old_inst.instance_id), "装备铁剑应成功")
	_inv.add_item(BLADE, 1, "test")
	var blade_inst: ItemInstance = null
	for i in _inv.get_equippable_instances():
		if i.item_id == BLADE:
			blade_inst = i
	expect(blade_inst != null, "背包应有铁刀实例")
	if blade_inst == null:
		return
	_fill_main_bag()   # 铁刀已在包内，补满 30 格
	# 守恒断言：填包武器与旧装备同 id，不能用差值——改为前后总数守恒
	var swords_before: int = _inv.get_item_count(WEAPON) + (1 if String(_equip.get_equipped("main_hand")) == WEAPON else 0)
	var blades_before: int = _inv.get_item_count(BLADE)
	expect(_equip.equip(blade_inst.instance_id), "满包换装应成功（先抽新腾格）")
	var swords_after: int = _inv.get_item_count(WEAPON) + (1 if String(_equip.get_equipped("main_hand")) == WEAPON else 0)
	var blades_after: int = _inv.get_item_count(BLADE) + (1 if String(_equip.get_equipped("main_hand")) == BLADE else 0)
	expect_eq(swords_after, swords_before, "铁剑总数必须守恒（旧装备不得蒸发）")
	expect_eq(blades_after, blades_before, "铁刀总数必须守恒")
	expect(String(_equip.get_equipped("main_hand")) == BLADE, "主手应换为铁刀")

func test_alchemy_produces_pill() -> void:
	_inv.add_item(HERB, 5, "test")
	var before: int = _inv.get_item_count(PILL_ID)
	expect(_alchemy.refine("recipe_xiaohuan"), "炼制应成功")
	expect_eq(_inv.get_item_count(PILL_ID), before + 1, "小还丹应 +1")
	expect_eq(_inv.get_item_count(HERB), 3, "草药应 -2")

func test_alchemy_full_bag_no_material_loss() -> void:
	# P0-2 回归：主栏满装不下产出时，材料必须分文不动
	_inv.add_item(HERB, 5, "test")
	_fill_main_bag()
	expect(not _alchemy.refine("recipe_xiaohuan"), "满包炼制应整体失败")
	expect_eq(_inv.get_item_count(HERB), 5, "失败时草药不得被扣")

func test_equipment_save_roundtrip() -> void:
	_inv.add_item("armor_cloth_001", 1, "test")
	var inst: ItemInstance = null
	for i in _inv.get_equippable_instances():
		if i.item_id == "armor_cloth_001":
			inst = i
	expect(inst != null, "应找到粗布衣实例")
	if inst == null:
		return
	expect(_equip.equip(inst.instance_id), "装备护甲应成功")
	var data: Dictionary = _equip.save()
	expect(data.has("slots"), "存档应有 slots")
	expect(String(data["slots"].get("armor", "")) == "armor_cloth_001", "存档应记录护甲")
	_equip.reset()
	_equip.load(data)
	expect(String(_equip.get_equipped("armor")) == "armor_cloth_001", "读档后护甲在位")
	expect(_ps.max_hp >= 100, "护甲加成应体现在气血上限")
