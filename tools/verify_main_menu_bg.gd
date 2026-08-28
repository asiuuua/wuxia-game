extends SceneTree
# 主菜单背景图切换校验
# 验证 ResourceLoader 能找到 main_menu_bg.jpg、load() 能拿到 Texture2D 且尺寸非零

func _initialize() -> void:
	var path := "res://assets/ui/main_menu_bg.jpg"
	var exists: bool = ResourceLoader.exists(path)
	print("VERIFY exists=%s" % exists)
	if not exists:
		print("VERIFY_FAIL: image not registered as resource")
		quit(1); return
	var tex := load(path) as Texture2D
	if tex == null:
		print("VERIFY_FAIL: load returned null")
		quit(1); return
	var sz: Vector2 = tex.get_size()
	print("VERIFY size=%s" % str(sz))
	if sz.x <= 0 or sz.y <= 0:
		print("VERIFY_FAIL: zero-size texture")
		quit(1); return
	print("VERIFY_OK: main_menu_bg.jpg loaded %sx%s" % [sz.x, sz.y])
	quit(0)