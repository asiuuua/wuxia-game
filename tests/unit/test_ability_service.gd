# tests/unit/test_ability_service.gd
# 武学服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 边界契约：未知武学/非法槽位不崩，返回安全值。

extends TestBase
class_name TestAbilityService

var _svc: AbilityService

func before_each() -> void:
	_svc = AbilityService.new()

func after_each() -> void:
	_svc = null

func test_learn_unknown() -> void:
	expect(not _svc.learn("no_such_ability_999"), "学习未知武学应失败")

func test_is_learned_unknown() -> void:
	expect(not _svc.is_learned("no_such_ability_999"), "未知武学不应已学")

func test_equip_invalid_slot() -> void:
	expect(not _svc.equip_combat_skill(-1, "any"), "负槽位装备应失败")
	expect(not _svc.equip_combat_skill(999, "any"), "越界槽位装备应失败")
