# tools/verify_p1_loc.gd
# 校验 P1-⑤：切换三种 locale，确认新增 UI 本地化键都能解析（不回退成 key 本身）
extends SceneTree

func _init() -> void:
	call_deferred("_run")

func _run() -> void:
	var keys := [
		"ui_inventory_title", "ui_map_title", "ui_save_load", "region_start_town",
		"ui_dialog_fight", "ui_attr_hp", "ui_loading_progress", "ui_confirm_ok",
	]
	var ok := true
	for loc in ["zh_CN", "en", "zh_TW"]:
		TranslationServer.set_locale(loc)
		for k in keys:
			var t: String = tr(k)
			var resolved: bool = t != k
			if not resolved:
				ok = false
			print("LOC %s  %s = [%s]  resolved=%s" % [loc, k, t, resolved])
	print("ALL_RESOLVED" if ok else "SOME_KEYS_UNRESOLVED")
	quit()
