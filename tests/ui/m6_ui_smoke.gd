# tests/ui/m6_ui_smoke.gd
# M6 运行时冒烟：实例化 HUD（经 .tscn）+ 打开 GameMenu / BondRomance / AbilitiesScreen 三屏，
# 验证 _ready/_refresh 无运行期报错（方法名拼错、空引用、UIPalette 缺失等静态门禁抓不到的问题）。
extends Node

func _ready() -> void:
	await get_tree().process_frame

	# 1) HUD：TownScene 经 .tscn 实例化，这里直接 instantiate 验证 _ready 构建
	var hud_scene: PackedScene = load("res://scenes/ui/overlays/hud/Hud.tscn")
	if hud_scene == null:
		push_error("[M6Test] Hud.tscn 加载失败"); get_tree().quit(); return
	var hud: Node = hud_scene.instantiate()
	if hud == null:
		push_error("[M6Test] Hud instantiate 失败"); get_tree().quit(); return
	add_child(hud)
	print("[M6Test] Hud OK children=%d" % hud.get_child_count())
	await get_tree().process_frame

	# 2) GameMenu
	var gm: Control = UIManager.open_screen("GameMenu", UIManager.Layer.FULLSCREEN)
	if gm == null:
		push_error("[M6Test] GameMenu 打开失败"); get_tree().quit(); return
	print("[M6Test] GameMenu OK children=%d" % gm.get_child_count())
	await get_tree().create_timer(0.3).timeout
	UIManager.close_screen(gm)

	# 3) BondRomance（修复数据源后重新验证 _ready 不崩）
	var br: Control = UIManager.open_screen("BondRomance", UIManager.Layer.FULLSCREEN)
	if br == null:
		push_error("[M6Test] BondRomance 打开失败"); get_tree().quit(); return
	print("[M6Test] BondRomance OK children=%d" % br.get_child_count())
	await get_tree().create_timer(0.3).timeout
	UIManager.close_screen(br)

	# 4) AbilitiesScreen（已学武学面板）
	var ab: Control = UIManager.open_screen("AbilitiesScreen", UIManager.Layer.FULLSCREEN)
	if ab == null:
		push_error("[M6Test] AbilitiesScreen 打开失败"); get_tree().quit(); return
	print("[M6Test] AbilitiesScreen OK children=%d" % ab.get_child_count())
	await get_tree().create_timer(0.3).timeout
	UIManager.close_screen(ab)

	print("[M6Test] ALL_M6_OK")
	get_tree().quit()
