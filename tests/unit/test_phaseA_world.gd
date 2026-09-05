# tests/unit/test_phaseA_world.gd
# 阶段A 基础设施校验：世界时钟（WeatherTimeService）+ 玩家状态前置（age/金钱/队友槽位）
# 改造：继承 TestBase 被 run_all.tscn 收录（场景模式 class_name 全注册，无需 preload 兜底）

@warning_ignore("shadowed_global_identifier")
extends TestBase
class_name TestPhaseAWorld

func before_each() -> void:
	# 复位世界时钟，保证用例自包含、可重复
	WeatherTimeService.debug_set_day(1)
	WeatherTimeService.debug_set_season(WorldEnums.Season.SPRING)

func test_clock_defaults() -> void:
	expect_eq(WeatherTimeService.get_day(), 1, "初始天数应为 1")
	expect(WeatherTimeService.get_season() == WorldEnums.Season.SPRING, "初始季节应为春")
	expect(WorldEnums.Weather.CLEAR == 0, "Weather.CLEAR 枚举值应为 0")

func test_advance_time_crosses_day() -> void:
	var d0: int = WeatherTimeService.get_day()
	WeatherTimeService.advance_time(30.0)
	expect_eq(WeatherTimeService.get_day(), d0 + 1, "跨 30 小时应进 1 天")
	expect(WeatherTimeService.get_time_of_day() < 24.0, "time_of_day 应回卷到 24 内")

func test_season_cycle() -> void:
	WeatherTimeService.debug_set_day(1)
	WeatherTimeService.debug_set_season(WorldEnums.Season.SPRING)
	WeatherTimeService.advance_day(15)
	expect(WeatherTimeService.get_season() == WorldEnums.Season.SUMMER, "过 15 天应入夏")
	WeatherTimeService.advance_day(15)
	expect(WeatherTimeService.get_season() == WorldEnums.Season.AUTUMN, "再过 15 天应入秋")
	WeatherTimeService.advance_day(15)
	expect(WeatherTimeService.get_season() == WorldEnums.Season.WINTER, "再过 15 天应入冬")
	WeatherTimeService.advance_day(15)
	expect(WeatherTimeService.get_season() == WorldEnums.Season.SPRING, "再过 15 天应回春")

func test_time_of_day_phases() -> void:
	WeatherTimeService.debug_set_time_of_day(3.0)
	expect(WeatherTimeService.get_time_of_day_phase() == WorldEnums.TimeOfDay.NIGHT, "3 点应为夜晚")
	WeatherTimeService.debug_set_time_of_day(12.0)
	expect(WeatherTimeService.get_time_of_day_phase() == WorldEnums.TimeOfDay.DAY, "12 点应为白昼")

func test_world_state_roundtrip() -> void:
	var snap: Dictionary = WeatherTimeService.debug_save_state()
	WeatherTimeService.advance_day(5)
	expect(WeatherTimeService.get_day() != int(snap["day"]), "推进后应不同于快照")
	WeatherTimeService.debug_load_state(snap)
	expect_eq(WeatherTimeService.get_day(), int(snap["day"]), "读档后天数应还原")
	expect(WeatherTimeService.get_season() == int(snap["season"]), "读档后季节应还原")

func test_player_money() -> void:
	var ps: PlayerState = GameManager.player_state
	ps.silver = 100
	expect(ps.spend_money(30) and ps.silver == 70, "花 30 后银两应为 70")
	expect(not ps.spend_money(999) and ps.silver == 70, "钱不够时不应扣款")
	ps.add_money(50)
	expect_eq(ps.silver, 120, "赚 50 后银两应为 120")

func test_player_defaults_and_roundtrip() -> void:
	var ps: PlayerState = GameManager.player_state
	expect_eq(ps.age, 18, "初始年龄应为 18")
	expect(ps.companion_ids.size() == 0, "初始队友槽位应为空")
	var ps_snap: Dictionary = ps.save()
	ps.age = 99
	ps.companion_ids = ["ally_001"]
	ps.load(ps_snap)
	expect_eq(ps.age, 18, "读档后年龄应还原")
	expect(ps.companion_ids.size() == 0, "读档后队友槽位应还原")

# === 07 图 W-R05 天气 roll 决定论：同日同季必同天气（可回放可单测） ===
func test_weather_roll_deterministic() -> void:
	WeatherTimeService.debug_set_day(1)
	WeatherTimeService.debug_set_season(WorldEnums.Season.SPRING)
	WeatherTimeService.advance_day(1)   # 推进触发 _roll_weather（决定论 seed=f(day,season)）
	var w1: int = WeatherTimeService.get_weather()
	# 重放：复位到同日同季再推进，天气必须一致
	WeatherTimeService.debug_set_day(1)
	WeatherTimeService.advance_day(1)
	var w2: int = WeatherTimeService.get_weather()
	expect_eq(w2, w1, "同日同季天气必须一致（W-R05 决定论）")
	expect(w1 != -1, "天气应为合法枚举值")
	# 不同日同季：seed 不同（结果可能相同也可能不同，但与日绑定可复现）
	WeatherTimeService.debug_set_day(2)
	WeatherTimeService.advance_day(1)
	expect(WeatherTimeService.get_weather() >= 0, "第3日天气应为合法枚举值")
