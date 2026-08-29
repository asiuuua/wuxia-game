# tests/unit/run_all.gd
# 单元测试总入口：扫描 tests/unit 下所有 test_*.gd，逐个执行后汇总退出码
# 运行：Godot_4.7.2_console --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn
# 退出码：0 全通过 / 1 有失败（可直接接 CI）
# 注意：必须走场景运行（--path + 场景），不能用 --script——后者不加载 autoload，
#       ConfigManager / GameManager / DifficultyManager 全部缺失。

extends Node

const TEST_DIR := "res://tests/unit"

func _ready() -> void:
	var scripts: Array[String] = _find_test_scripts()
	print("══════════════════════════════")
	print("武侠江湖 · 单元测试总入口")
	print("发现 %d 个测试脚本" % scripts.size())
	print("══════════════════════════════")
	var suite_pass := 0
	var suite_fail := 0
	for path in scripts:
		var sc := load(path) as Script
		if sc == null or not sc.can_instantiate():
			print("  ! 脚本加载失败（缺失/解析错误/类缓存未解析 class_name）：%s" % path)
			print("    ↳ 若多文件同时报此错：类缓存可能损坏 —— 先 `godot --headless --editor --quit` 重建 .godot/global_script_class_cache.cfg，并确保无并发 Godot 进程抢缓存")
			suite_fail += 1
			continue
		var inst := sc.new() as TestBase
		if inst == null:
			print("  ! 脚本实例化失败（未继承 TestBase 或 _init 抛错，绝不静默跳过）：%s" % path)
			suite_fail += 1
			continue
		var code: int = inst.run()
		if code == 0:
			suite_pass += 1
		else:
			suite_fail += 1
			for line in inst.get_fail_log():
				print("      ✗ %s" % line)
	print("══════════════════════════════")
	print("套件：通过 %d · 失败 %d" % [suite_pass, suite_fail])
	print("══════════════════════════════")
	get_tree().quit(1 if suite_fail > 0 else 0)

func _find_test_scripts() -> Array[String]:
	var out: Array[String] = []
	var dir := DirAccess.open(TEST_DIR)
	if dir == null:
		push_error("[Test] 无法打开测试目录: %s" % TEST_DIR)
		return out
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.begins_with("test_") and fname.ends_with(".gd"):
			out.append(TEST_DIR + "/" + fname)
		fname = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out
