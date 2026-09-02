# tests/unit/test_sect_service.gd
# 门派服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 重点：get_rank_name 纯函数（阶位->中文名）映射正确，未知阶位安全回退。

extends TestBase
class_name TestSectService

var _svc: SectService

func before_each() -> void:
	_svc = SectService.new()

func after_each() -> void:
	_svc = null

func test_rank_name_map() -> void:
	expect(_svc.get_rank_name(SectEnums.Rank.INNER) == "内门弟子", "INNER 阶位名")
	expect(_svc.get_rank_name(SectEnums.Rank.CORE) == "核心弟子", "CORE 阶位名")
	expect(_svc.get_rank_name(SectEnums.Rank.ELDER) == "长老", "ELDER 阶位名")
	expect(_svc.get_rank_name(SectEnums.Rank.LEADER) == "掌门", "LEADER 阶位名")
	expect(_svc.get_rank_name(999) == "外门弟子", "未知阶位回退外门弟子")
