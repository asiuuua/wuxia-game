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

func test_menu_item_icon_wired() -> void:
	var item = load("res://scenes/ui/components/menu_item/MenuItem.gd").new()
	item.set_icon("menu/save_game")
	item.set_text("保存")
	item._ready()   # _build 在 _ready 内跑
	var ok := item._icon != null and item._icon is TextureRect and item._icon.texture != null
	expect(ok, "MenuItem 设 set_icon 后 _build 应创建图标 TextureRect（UIManager.get_icon 占位图兜底）")
	# 不设图标时不应创建图标（向后兼容旧菜单项）
	var plain = load("res://scenes/ui/components/menu_item/MenuItem.gd").new()
	plain.set_text("纯文字")
	plain._ready()
	expect(plain._icon == null, "未设 set_icon 的 MenuItem 不应创建图标（向后兼容旧菜单项）")

func test_dialog_overlay_portrait_no_crash() -> void:
	var dlg = load("res://scenes/ui/overlays/dialog/DialogOverlay.gd").new()
	dlg.show_for_npc({"id": "npc_test_x", "dialogs": []})
	expect(dlg.get_child_count() > 0, "DialogOverlay.show_for_npc 应成功构建（立绘双通道不崩）")

func test_hud_builds() -> void:
	var hud = load("res://scenes/ui/overlays/hud/Hud.gd").new()
	hud._ready()
	expect(hud.get_child_count() > 0, "Hud._build 应成功（含头像双通道接线）")
