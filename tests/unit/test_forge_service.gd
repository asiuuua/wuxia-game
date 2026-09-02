# tests/unit/test_forge_service.gd
# 锻造服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 边界契约：未知配方不崩，返回安全值；describe_inputs 对未知配方返回字符串不崩。

extends TestBase
class_name TestForgeService

var _svc: ForgeService

func before_each() -> void:
	_svc = ForgeService.new()

func after_each() -> void:
	_svc = null

func test_can_forge_unknown() -> void:
	expect(not _svc.can_forge("no_such_recipe_999", 1), "未知配方不可锻造")

func test_describe_inputs_unknown_no_crash() -> void:
	var s: String = _svc.describe_inputs("no_such_recipe_999")
	expect(s is String, "未知配方 describe_inputs 返回字符串不崩")
