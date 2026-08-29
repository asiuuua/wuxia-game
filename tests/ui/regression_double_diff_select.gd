# tests/ui/regression_double_diff_select.gd
# 回归测试："点开始→选难度→未进游戏→再选一次才能进入" bug
#
# 根因：DifficultySelect._proceed 只 close_screen(self)，MainMenu 仍留在 _screen_stack。
#       change_scene_to_file 切 TownScene 后，autoload 的 CanvasLayer 仍挂着 MainMenu，遮挡 TownScene。
#       玩家看到 MainMenu 以为"没进游戏"，再次点"开始" → 又进 DifficultySelect → 又选难度，
#       形成"选2遍模式"循环。
#
# 修复：DifficultySelect._proceed 改用 UIManager.close_all_screens() 一次性同步释放所有 UI 屏幕，
#       与 SaveLoadScreen._do_new_game 行为一致（UI 入口自行清理 UI，符合主权边界）。
#
# 跑：Godot_v4.7.2_console --headless --path "D:/武侠游戏" res://tests/ui/regression_double_diff_select.tscn
# 通过：输出 ✓ PASS；失败：✗ FAIL + 非零退出码。
# 不进 run_all：测试会触发 GameManager.start_new_game 切场景，干扰其他测试套件。

extends Node

func _ready() -> void:
	await get_tree().process_frame
	var mm: Control = UIManager.open_screen("MainMenu", UIManager.Layer.FULLSCREEN)
	if mm == null:
		_fail("MainMenu 打开失败"); get_tree().quit(1); return
	await get_tree().process_frame
	_log("1. MainMenu opened, _screen_stack size=%d" % _stack_size())

	# 模拟点 MainMenu 的"新游戏" → 打开 DifficultySelect
	mm._new_game()
	await get_tree().process_frame
	var diff: Control = UIManager.get_current_screen()
	if diff == null or diff.name != "DifficultySelect":
		_fail("DifficultySelect 未在栈顶"); get_tree().quit(1); return
	_log("2. DifficultySelect opened, _screen_stack size=%d" % _stack_size())

	# 模拟点难度按钮 → _proceed（这是 bug 的关键路径）
	# 修复后：_proceed 内部调 UIManager.close_all_screens() + GameManager.start_new_game()，
	# change_scene_to_file 是延迟到帧末的，所以同步检查 _screen_stack 即可判定。
	_log("3. Calling _proceed('NORMAL') ...")
	diff._proceed("NORMAL")
	_log("4. Right after _proceed (sync), _screen_stack size=%d" % _stack_size())

	if _stack_size() == 0:
		_log("✓ PASS: _proceed 同步清空 UI 栈，TownScene 不会被旧 UI 遮挡")
		get_tree().quit(0)
	else:
		_fail("✗ FAIL: _proceed 后 _screen_stack 仍非空（size=%d），TownScene 会被旧 UI 遮挡" % _stack_size())
		get_tree().quit(1)

func _stack_size() -> int:
	return UIManager._screen_stack.size()

func _log(msg: String) -> void:
	print("[Regression][%s] %s" % [Time.get_ticks_msec(), msg])

func _fail(msg: String) -> void:
	printerr("[Regression] %s" % msg)
