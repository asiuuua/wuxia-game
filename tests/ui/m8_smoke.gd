# tests/ui/m8_smoke.gd
# 设置弹窗冒烟测试：经 UIManager.show_popup 实例化 SettingsScreen（真实打开路径），
# 验证弹窗框架(遮罩/面板)存在、无 SCRIPT ERROR、模拟各项设置写入与语言切换/重置不报错、关闭可用。
# 运行：Godot 4.7.2 --headless --path "D:/武侠游戏" "res://tests/ui/m8_smoke.tscn"

extends Node

func _ready() -> void:
	await get_tree().process_frame
	var screen: Control = UIManager.show_popup("SettingsScreen")
	if screen == null:
		push_error("[M8] show_popup(\"SettingsScreen\") 返回 null")
		get_tree().quit(1)
		return
	# 等两帧让 _ready 构建完成
	await get_tree().process_frame
	await get_tree().process_frame

	var ok: bool = true
	if not screen.is_inside_tree():
		ok = false
		print("[M8] FAIL: screen not in tree")
	if screen.get_node_or_null("Backdrop") == null:
		ok = false
		print("[M8] FAIL: missing Backdrop")
	if screen.get_node_or_null("Panel") == null:
		ok = false
		print("[M8] FAIL: missing Panel")
	if screen.get_node_or_null("Panel/Header") == null:
		ok = false
		print("[M8] FAIL: missing Panel/Header")
	if screen.get_node_or_null("Panel/Body/CategoryList") == null:
		ok = false
		print("[M8] FAIL: missing CategoryList")

	# 模拟真实操作链路：切换分类、写入各项设置、语言切换、重置
	screen._select_category("graphics")
	screen._select_category("control")
	screen._select_category("language")
	SettingsManager.set_graphics("resolution", "1600x900")
	SettingsManager.set_graphics("display_mode", "windowed")
	SettingsManager.set_graphics("ui_scale", 1.25)
	SettingsManager.set_graphics("render_scale", 1.5)
	SettingsManager.set_audio_volume("master", 0.5)
	SettingsManager.rebind("move_up", KEY_W)
	SettingsManager.set_language("zh_TW")
	SettingsManager.set_language("zh_CN")
	SettingsManager.reset_category("audio")
	SettingsManager.reset_category("graphics")

	# 语言切换重建断言：左侧分类按钮必须保留（旧 bug 会把 _category_buttons 清零导致文案不刷新）
	SettingsManager.set_language("en")
	screen._rebuild_ui()
	if screen._category_buttons.size() != 5:
		ok = false
		print("[M8] FAIL: _category_buttons size=%d (期望 5，旧 bug 会清零)" % screen._category_buttons.size())
	var cat0: Button = screen.get_node_or_null("Panel/Body/CategoryList/audio") as Button
	if cat0 == null or cat0.text == "":
		ok = false
		print("[M8] FAIL: 左侧分类按钮 audio 丢失或文案为空（语言切换重建失效）")
	SettingsManager.set_language("zh_CN")

	# 关闭弹窗（三选一：返回按钮逻辑）
	screen._go_back()
	await get_tree().process_frame
	await get_tree().process_frame

	if ok:
		print("[M8] ALL_M8_OK")
	get_tree().quit()
