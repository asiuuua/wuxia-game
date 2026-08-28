# data/runtime/world_time_state.gd
# 世界时间与天气的运行时状态（阶段A 基础设施）
# 实现 ISaveable 契约；由 WeatherTimeService（autoload）持有并驱动，自身不持有 Node
# 铁律：静态调参在 world_config.json，本类只存运行时数值 + 序列化

@warning_ignore("shadowed_global_identifier")
extends ISaveable

class_name WorldTimeState

# 自包含依赖（同 WeatherTimeService 说明）：headless 下 class_name 全局注册顺序不可靠，
# 此处 preload 兜底，保证本类稳定编译
const WorldEnums = preload("res://core/enums/world_enums.gd")

# === 运行时状态 ===
var day: int = 1                      # 游戏内天数（从 1 起）
var time_of_day: float = 8.0          # 当天时刻，0.0 - 24.0 小时
var season: int = 0  # 默认春（WorldEnums.Season.SPRING == 0）
var weather: int = 0  # 默认晴（WorldEnums.Weather.CLEAR == 0）

## 读 world_config.json 重置为默认起始值（新游戏 / 构造后调用）
func reset_to_default() -> void:
	var cfg: Dictionary = ConfigManager.get_world_config()
	day = int(cfg.get("start_day", 1))
	time_of_day = float(cfg.get("start_time_of_day", 8.0))
	season = int(cfg.get("start_season", WorldEnums.Season.SPRING))
	weather = int(cfg.get("start_weather", WorldEnums.Weather.CLEAR))

# === ISaveable ===
func get_save_key() -> String:
	return "world_time"

func save() -> Dictionary:
	return {
		"day": day,
		"time_of_day": time_of_day,
		"season": season,
		"weather": weather,
	}

func load(data: Dictionary) -> void:
	day = int(data.get("day", 1))
	time_of_day = float(data.get("time_of_day", 8.0))
	season = int(data.get("season", WorldEnums.Season.SPRING))
	weather = int(data.get("weather", WorldEnums.Weather.CLEAR))
