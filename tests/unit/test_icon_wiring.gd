# tests/unit/test_icon_wiring.gd
# 图标显示链路冒烟：验证三处 UI 接线在 autoload + GameManager 全加载环境下能编译并运行
# （--check-only 因不加载 autoload 会漏报此类脚本，故用 load().new() 在 run_all 真实语境下编译）。
# 同时验证 ItemSlot 确实把图标纹理设为非空（缺图走 UIManager.get_icon 占位图兜底）。
extends TestBase

func test_item_slot_icon_wired() -> void:
	var slot = load("res://scenes/ui/components/item_slot/ItemSlot.gd").new()
	var inst = ItemInstance.new()
	inst.item_id = "iron_sword"
	slot.setup(inst)
	var icon_ok := false
	for c in slot.get_children():
		if c is TextureRect and c.texture != null:
			icon_ok = true
	expect(icon_ok, "ItemSlot 应含已设置纹理的图标（UIManager.get_icon 占位图兜底）")
	# 空槽应清空图标
	slot.setup(null)
	var empty_ok := true
	for c in slot.get_children():
		if c is TextureRect and c.texture != null:
			empty_ok = false
	expect(empty_ok, "空槽时图标纹理应为 null")

func test_abilities_screen_builds() -> void:
	var scr = load("res://scenes/ui/screens/abilities/AbilitiesScreen.gd").new()
	scr._ready()
	expect(scr.get_child_count() > 0, "AbilitiesScreen._build 应成功（含技能图标接线）")

func test_bond_screen_builds() -> void:
	var scr = load("res://scenes/ui/screens/bond_romance/BondRomanceScreen.gd").new()
	scr._ready()
	expect(scr.get_child_count() > 0, "BondRomanceScreen._build 应成功（含 NPC 头像接线）")
