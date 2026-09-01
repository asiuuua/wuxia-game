# tests/unit/test_main_menu_loads.gd
# 回归测试：主菜单与水墨按钮预制必须能正确解析/加载（无 Parse Error）。
# 背景：WuxiaMenuButton 曾因声明 `var icon` 与 Button.icon 原生属性重名，
# 导致整脚本 Parse Error，主菜单一实例化就崩；而原 GATE2 套件从未实例化 MainMenu，
# 漏报此错（GATE1 --quit 也不加载该脚本）。此测试强制加载两者，堵住盲点。
# MainMenu.gd 内部 preload 了 WuxiaMenuButton.tscn，故加载 MainMenu 会连带解析按钮脚本。
extends TestBase

func test_wuxia_menu_button_loads() -> void:
	var scr = load("res://scenes/ui/components/wuxia_menu_button/WuxiaMenuButton.tscn")
	expect(scr != null, "WuxiaMenuButton.tscn 应可加载（脚本无 Parse Error）")
	if scr == null:
		return
	var inst = scr.instantiate()
	expect(is_instance_valid(inst), "WuxiaMenuButton 应可实例化")

func test_main_menu_loads() -> void:
	var scr = load("res://scenes/ui/screens/main_menu/MainMenu.tscn")
	expect(scr != null, "MainMenu.tscn 应可加载（其脚本 preload 了 WuxiaMenuButton，无 Parse Error 连带失败）")
	if scr == null:
		return
	var inst = scr.instantiate()
	expect(is_instance_valid(inst), "MainMenu 应可实例化")
	inst.free()
