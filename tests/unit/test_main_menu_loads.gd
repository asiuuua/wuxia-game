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

func test_wuxia_menu_button_base_scale_applies() -> void:
	# 回归：工作室「菜单按钮显示尺寸」写入的 base_scale 必须只缩放图标、文字与按钮整体不动。
	var scr = load("res://scenes/ui/components/wuxia_menu_button/WuxiaMenuButton.tscn")
	if scr == null:
		expect(false, "WuxiaMenuButton.tscn 应可加载")
		return
	var inst: Control = scr.instantiate()
	inst.base_scale = 0.85
	# 不挂树直接调 _ready：run_all._ready 期间 root 正在 setup children，同步 add_child 会报 ERROR；
	# _ready 里的样式/字号/scale 赋值均不依赖挂树，可直接验证。
	inst._ready()
	var icon: Control = inst.get_node("icon")
	expect(icon != null and absf(icon.scale.x - 0.85) < 0.001,
		"base_scale=0.85 时图标 scale.x 应为 0.85，实际 %s" % str(icon.scale.x if icon != null else "null"))
	expect(absf(inst.scale.x - 1.0) < 0.001, "按钮整体 scale.x 应保持 1.0（不再整体缩放），实际 %f" % inst.scale.x)
	var label_main: Control = inst.get_node("label_main")
	var label_sub: Control = inst.get_node("label_sub")
	expect(label_main != null and label_sub != null
		and absf(label_main.scale.x - 1.0) < 0.001 and absf(label_sub.scale.x - 1.0) < 0.001,
		"文字 label 的 scale 应保持 1.0（不被缩放）")
	# 悬停动画：图标与文字各自围绕自身中心等比例放大到相同倍数（不变形、不拉伸、不聚合）
	inst._hover_t = 1.0
	inst._is_pressed = false
	inst._apply_scale()
	expect(absf(icon.scale.x - 0.85 * inst.hover_scale) < 0.001 and absf(icon.scale.y - 0.85 * inst.hover_scale) < 0.001,
		"悬停时图标应等比例缩放为 base*hover=%f，实际 %s" % [0.85 * inst.hover_scale, str(icon.scale)])
	expect(absf(label_main.scale.x - inst.hover_scale) < 0.001 and absf(label_main.scale.y - inst.hover_scale) < 0.001
		and absf(label_sub.scale.x - inst.hover_scale) < 0.001 and absf(label_sub.scale.y - inst.hover_scale) < 0.001,
		"悬停时文字应独立等比例放大为 hover_scale=%f（不乘 base_scale），实际 main=%s sub=%s" % [inst.hover_scale, str(label_main.scale), str(label_sub.scale)])
	# 图标与文字都围绕自身中心缩放（等比例、不向任何一侧拉伸）
	expect(icon != null and absf(icon.pivot_offset.x - icon.size.x * 0.5) < 0.001,
		"图标 pivot 应在自身水平中心（实际 %f）" % (icon.pivot_offset.x if icon != null else -1.0))
	expect(absf(label_main.pivot_offset.x - label_main.size.x * 0.5) < 0.001 and absf(label_sub.pivot_offset.x - label_sub.size.x * 0.5) < 0.001,
		"文字 pivot 应在自身水平中心（实际 main=%f sub=%f）" % [label_main.pivot_offset.x, label_sub.pivot_offset.x])
	inst.free()

func test_main_menu_reads_icon_scales_config() -> void:
	# 回归：MainMenu._load_assets_config 应读取 main_menu_assets.json 的 icon_scales（缺省补齐 5 个 1.0）。
	var scr = load("res://scenes/ui/screens/main_menu/MainMenu.tscn")
	if scr == null:
		expect(false, "MainMenu.tscn 应可加载")
		return
	var inst: Node = scr.instantiate()
	inst._load_assets_config()
	var scales: Array = inst._icon_scales
	expect(scales.size() == 5, "icon_scales 应补齐为 5 个，实际 %d" % scales.size())
	for s in scales:
		expect(typeof(s) == TYPE_FLOAT and s >= 0.4 and s <= 1.6, "每个缩放值应在 [0.4,1.6]，实际 %s" % str(s))
	inst.free()
