# tests/unit/test_quest_service.gd
# 任务服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 边界契约：未知任务/非法状态不崩，返回安全值；reset 清空活跃列表。

extends TestBase
class_name TestQuestService

var _svc: QuestService

func before_each() -> void:
	_svc = QuestService.new()

func after_each() -> void:
	_svc = null

func test_can_accept_unknown() -> void:
	expect(not _svc.can_accept("no_such_quest_999"), "未知任务不可接")

func test_accept_unknown_returns_false() -> void:
	expect(not _svc.accept("no_such_quest_999"), "接受未知任务应返回 false 不崩")

func test_is_active_unknown() -> void:
	expect(not _svc.is_active("no_such_quest_999"), "未知任务不应处于活跃")

func test_reset_clears_active() -> void:
	_svc.reset()
	expect_eq(_svc.get_active_quest_ids().size(), 0, "reset 后无活跃任务")
