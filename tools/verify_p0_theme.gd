# tools/verify_p0_theme.gd
# P0 端到端校验（诊断版）：确认自定义主题已生效且 Label 能继承中文字体
extends SceneTree

func _initialize() -> void:
	var dt: Theme = ThemeDB.get_default_theme()
	var rt: Theme = root.theme
	print("DBG_TotalDB_default_theme_path=", dt.resource_path if dt else "null")
	print("DBG_root_theme_path=", rt.resource_path if rt else "null")

	var label := Label.new()
	label.text = "江湖"
	root.add_child(label)
	var eff: Font = label.get_theme_font("font", "Label")
	print("DBG_label_effective_font_path=", eff.resource_path if eff else "null")
	print("DBG_label_font_has_江=", eff != null and eff.has_char(0x6C5F))

	# 判定：只要 Label 实际拿到中文字体，即证明 P0 生效
	if eff != null and eff.has_char(0x6C5F):
		print("P0_VERIFY_OK font=%s" % eff.resource_path)
		quit(0)
	else:
		push_error("VERIFY_FAIL: Label 未继承到中文字体")
		quit(1)
