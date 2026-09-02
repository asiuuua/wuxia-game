# tests/unit/test_game_state.gd
# 全局游戏状态单元测试（继承 TestBase，被 run_all.tscn 收录）
# 重点：存档序列化 round-trip（save/load 一致）、全局 flag / 安全点读写一致。

extends TestBase
class_name TestGameState

func before_each() -> void:
	pass

func after_each() -> void:
	GameState.reset()

func test_global_flag_roundtrip() -> void:
	GameState.set_global_flag("ut_flag", 42)
	expect_eq(int(GameState.get_global_flag("ut_flag", 0)), 42, "全局标志读写一致")
	expect(GameState.has_global_flag("ut_flag"), "应存在该标志")
	expect_eq(int(GameState.get_global_flag("missing_key", 7)), 7, "缺失键回退默认值")

func test_last_safe_point_roundtrip() -> void:
	GameState.set_last_safe_point("ut_marker", "ut_text")
	var sp: Dictionary = GameState.get_last_safe_point()
	expect_eq(int(sp.get("marker", "") == "ut_marker"), 1, "安全点 marker 一致")
	expect_eq(int(sp.get("text_id", "") == "ut_text"), 1, "安全点 text_id 一致")

func test_save_load_roundtrip() -> void:
	GameState.set_global_flag("ut_save", 7)
	var d: Dictionary = GameState.save()
	GameState.set_global_flag("ut_save", 0)
	GameState.load(d)
	expect_eq(int(GameState.get_global_flag("ut_save", 0)), 7, "load 后恢复全局标志")
