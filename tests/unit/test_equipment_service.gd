# tests/unit/test_equipment_service.gd
# 装备系统单元测试：聚焦 P1-4 修复——装备/卸下往返必须保留实例身份（iid/耐久），
# 不再因 add_item(item_id,1) 退回新实例而重置身份。

extends TestBase
class_name TestEquipmentService

func before_each() -> void:
	GameManager.inventory_service.reset()
	GameManager.equipment_service.reset()

func test_equip_unequip_preserves_instance_identity() -> void:
	var inv = GameManager.inventory_service
	var eq = GameManager.equipment_service
	# 给一把铁剑（equip_slot=main_hand）
	inv.add_item("weapon_sword_iron_001", 1, "test")
	var iid: String = ""
	for inst in inv.main_slots:
		if inst != null:
			iid = String(inst.instance_id)
	expect(iid != "", "应能获得武器实例 iid")
	expect(eq.equip(iid), "装备应成功")
	# 装备中实例应已离包
	expect(inv.get_instance_by_id(iid) == null, "装备后实例应已离包")
	# 卸下后应按原 iid 找回（身份/耐久保留，P1-4 修复）
	expect(eq.unequip("main_hand"), "卸下应成功")
	var back: ItemInstance = inv.get_instance_by_id(iid)
	expect(back != null, "卸下后应按原 iid 找回实例（身份未重置）")
	expect_eq(inv.get_item_count("weapon_sword_iron_001"), 1, "武器数量应为 1（无重复/丢失）")

func test_equip_swap_preserves_old_instance() -> void:
	# 换装：被换下的旧装备退包应保留其原实例身份（不重置为 add_item 新实例）
	var inv = GameManager.inventory_service
	var eq = GameManager.equipment_service
	inv.add_item("weapon_sword_iron_001", 1, "test")   # 旧（铁剑）
	inv.add_item("weapon_blade_iron_001", 1, "test")   # 新（铁刀）
	var old_iid: String = ""
	var new_iid: String = ""
	for inst in inv.main_slots:
		if inst != null:
			if inst.item_id == "weapon_sword_iron_001":
				old_iid = String(inst.instance_id)
			elif inst.item_id == "weapon_blade_iron_001":
				new_iid = String(inst.instance_id)
	expect(eq.equip(new_iid), "装备新武器应成功")
	expect(eq.equip(old_iid), "换装（旧铁剑重新上）应成功")
	# 换装时旧装备(blade)被原样退回背包：其 iid 应保留（P1-4 核心——不再 add_item 重置）
	var back: ItemInstance = inv.get_instance_by_id(new_iid)
	expect(back != null, "换装后旧装备(blade)应按原 iid 退回背包（身份保留）")
	expect_eq(inv.get_item_count("weapon_blade_iron_001"), 1, "blade 在背包数量=1（未丢失/未重置）")
	expect(String(eq.get_equipped("main_hand")) == "weapon_sword_iron_001", "main_hand 现为铁剑（铁剑已装备，不在背包）")
