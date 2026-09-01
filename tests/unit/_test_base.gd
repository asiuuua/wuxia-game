# tests/unit/_test_base.gd
# 测试基类：提供断言与统计，被测脚本继承它并实现 test_* 方法
# 设计要点：用 expect() 而非 GDScript 的 assert()
#   assert() 只 push_error 不抛异常，runner 无法判定失败，且会污染错误日志

extends RefCounted
class_name TestBase

var _passed: int = 0
var _failed: int = 0
var _fail_log: Array[String] = []
var _current: String = ""

## 反射执行自身所有 test_* 方法，返回退出码（0 全通过 / 1 有失败）
func run() -> int:
	var names: Array[String] = _collect_tests()
	if names.is_empty():
		print("  ! 未发现任何 test_* 方法")
		return 1
	var title: String = String(get_script().get_path().get_file())
	print("──────────────────────────────")
	print("运行 %s · %d 项" % [title, names.size()])
	for n in names:
		_current = n
		if has_method("before_each"):
			call("before_each")
		var before: int = _failed
		call(n)
		if has_method("after_each"):
			call("after_each")
		if _failed == before:
			_passed += 1
			print("  ✓ %s" % n)
		else:
			print("  ✗ %s" % n)
	print("  小计：通过 %d · 失败 %d" % [_passed, _failed])
	return 1 if _failed > 0 else 0

## 断言：条件不成立时记录失败但不中断，让一次运行能暴露全部问题
func expect(cond: bool, msg: String) -> bool:
	if cond:
		return true
	_failed += 1
	_fail_log.append("%s：%s" % [_current, msg])
	return false

## 相等断言（int 专用，避免浮点与类型隐式转换误判）
func expect_eq(actual: int, expect_value: int, msg: String) -> bool:
	return expect(actual == expect_value, "%s（实际 %d，期望 %d）" % [msg, actual, expect_value])

func get_fail_log() -> Array[String]:
	return _fail_log

func _collect_tests() -> Array[String]:
	var names: Array[String] = []
	for m in get_method_list():
		var n: String = String(m.get("name", ""))
		if n.begins_with("test_"):
			names.append(n)
	names.sort()
	return names
