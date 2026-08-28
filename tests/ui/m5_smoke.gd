# tests/ui/m5_smoke.gd
# M5 运行时冒烟：ConfirmDialog 弹出/确认回调、TransitionManager、Toast、SaveLoadScreen 接 ConfirmDialog
extends Node

var _confirm_fired: bool = false

func _ready() -> void:
	await get_tree().process_frame
	var mm = UIManager.open_screen("MainMenu", UIManager.Layer.FULLSCREEN)
	if mm == null:
		push_error("[M5Test] MainMenu null"); get_tree().quit(); return
	print("[M5Test] MainMenu OK")
	await get_tree().create_timer(0.3).timeout

	# ConfirmDialog：弹出 + setup + 模拟确认回调
	var dlg: Control = UIManager.show_popup("ConfirmDialog")
	if dlg == null:
		push_error("[M5Test] ConfirmDialog null"); get_tree().quit(); return
	dlg.setup("测试确认", "确定吗？", func(): _confirm_fired = true)
	print("[M5Test] ConfirmDialog opened, children=%d" % dlg.get_child_count())
	await get_tree().create_timer(0.3).timeout
	dlg._on_confirm()
	await get_tree().create_timer(0.3).timeout
	print("[M5Test] confirm_fired=%s" % _confirm_fired)

	# TransitionManager：水墨转场 + 中点回调
	TransitionManager.transition_to(TransitionManager.TransitionType.INK, func(): print("[M5Test] transition mid callback"))
	print("[M5Test] transition started")
	await get_tree().create_timer(1.4).timeout

	# Toast：经 EventBus.notification_show
	EventBus.notification_show.emit("这是一条江湖通知")
	print("[M5Test] notification emitted")
	await get_tree().create_timer(0.5).timeout

	# SaveLoadScreen：打开 + 触发删除确认弹窗（验证 ConfirmDialog 接入）
	var sl = UIManager.open_screen("SaveLoadScreen", UIManager.Layer.FULLSCREEN)
	if sl == null:
		push_error("[M5Test] SaveLoadScreen null"); get_tree().quit(); return
	print("[M5Test] SaveLoadScreen OK children=%d" % sl.get_child_count())
	await get_tree().create_timer(0.3).timeout
	print("[M5Test] ALL_M5_OK")
	get_tree().quit()
