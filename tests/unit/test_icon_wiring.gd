# tests/unit/test_icon_wiring.gd
# 图标显示链路冒烟：验证三处 UI 接线在 autoload + GameManager 全加载环境下能编译并运行
# （--check-only 因不加载 autoload 会漏报此类脚本，故用 load().new() 在 run_all 真实语境下编译）。
# 同时验证 ItemSlot 确实把图标纹理设为非空（缺图走 UIManager.get_icon 占位图兜底）。
extends TestBase

func test_item_slot_icon_wired() -> void:
	var slot = load("res://scenes/ui/components/item_slot/ItemSlot.tscn").instantiate()
	slot._ready()   # @onready 在 _ready 内赋值（TestBase 为 RefCounted，无 add_child）
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
	var scr: Control = load("res://scenes/ui/screens/abilities/AbilitiesScreen.tscn").instantiate()
	scr._ready()
	expect(scr.get_child_count() > 0, "AbilitiesScreen._build 应成功（含技能图标接线）")

func test_bond_screen_builds() -> void:
	var scr: Control = load("res://scenes/ui/screens/bond_romance/BondRomanceScreen.tscn").instantiate()
	scr._ready()
	expect(scr.get_child_count() > 0, "BondRomanceScreen._build 应成功（含 NPC 头像接线）")

func test_menu_item_icon_wired() -> void:
	# 新行为（2026-08-30）：仅当后台真实存在图标文件时才显示图标；
	# 缺图时连"缺图标占位紫块"都不画（见 MenuItem._configure_nodes 的 UIManager.has_icon 门控）。
	var item = load("res://scenes/ui/components/menu_item/MenuItem.tscn").instantiate()
	item.set_icon("menu/__no_such_icon_xyz__")
	item.set_text("保存")
	item._ready()   # @onready + _configure_nodes 在 _ready 内跑（TestBase 为 RefCounted，无 add_child）
	expect(item._icon != null and item._icon is TextureRect, "MenuItem 应含 _icon 节点（TextureRect）")
	expect(item._icon.visible == false, "缺图标文件时 _icon 应隐藏，不显示占位紫块")
	expect(item._icon.texture == null, "缺图标文件时 _icon.texture 应为 null（不渲染占位图）")
	# 不设图标时 _icon 节点存在但不应显示（向后兼容旧菜单项）
	var plain = load("res://scenes/ui/components/menu_item/MenuItem.tscn").instantiate()
	plain.set_text("纯文字")
	plain._ready()
	expect(plain._icon != null and plain._icon.visible == false, "未设 set_icon 的 MenuItem _icon 应存在但不显示（向后兼容旧菜单项）")

func test_dialog_overlay_portrait_no_crash() -> void:
	var dlg: Control = load("res://scenes/ui/overlays/dialog/DialogOverlay.tscn").instantiate()
	dlg._ready()
	# 解耦后通过 dialog_id 绑定台词；npc_merchant 在 town_npcs.json 与 dialogs.json 均存在
	dlg.show_for_npc({"id": "npc_merchant", "dialog_id": "npc_merchant"})
	expect(dlg.get_child_count() > 0, "DialogOverlay.show_for_npc 应成功构建（立绘双通道不崩）")

func test_hud_builds() -> void:
	var hud = load("res://scenes/ui/overlays/hud/Hud.gd").new()
	hud._ready()
	expect(hud.get_child_count() > 0, "Hud._build 应成功（含头像双通道接线）")
