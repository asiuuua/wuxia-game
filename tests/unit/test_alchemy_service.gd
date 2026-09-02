# tests/unit/test_alchemy_service.gd
# 炼化服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 边界契约：未知配方不崩，返回安全值（can_refine/refine 均拒绝）。

extends TestBase
class_name TestAlchemyService

var _svc: AlchemyService

func before_each() -> void:
	_svc = AlchemyService.new()

func after_each() -> void:
	_svc = null

func test_can_refine_unknown() -> void:
	expect(not _svc.can_refine("no_such_recipe_999"), "未知配方不可炼化")

func test_refine_unknown() -> void:
	expect(not _svc.refine("no_such_recipe_999"), "炼化未知配方应失败不崩")
