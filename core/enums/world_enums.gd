# core/enums/world_enums.gd
# 世界环境相关枚举：季节 / 天气 / 时段（阶段A 基础设施，钓鱼/打造/结缘/生育四系统共享）

extends RefCounted
class_name WorldEnums

# 季节：按 day / season_days 自动轮换，顺序与 world_config.json 的 weather_weights 键对应
enum Season { SPRING, SUMMER, AUTUMN, WINTER }

# 天气：钓鱼出没、事件触发等系统条件
enum Weather { CLEAR, CLOUDY, RAIN, FOG, WIND, SNOW, THUNDER }

# 一天内的时段：由 time_of_day（0-24 小时）归段，供 UI 与系统判断昼夜
enum TimeOfDay { DAWN, DAY, DUSK, NIGHT }

# 中文名（UI 直接显示，不硬编码在调用方）
const SEASON_NAMES := ["春", "夏", "秋", "冬"]
const WEATHER_NAMES := ["晴", "阴", "雨", "雾", "风", "雪", "雷"]
const TIME_OF_DAY_NAMES := ["拂晓", "白昼", "黄昏", "夜晚"]

## 取季节中文名（越界回退空串，调用方自行兜底）
static func season_name(s: int) -> String:
	if s < 0 or s >= SEASON_NAMES.size():
		return ""
	return SEASON_NAMES[s]

## 取天气中文名
static func weather_name(w: int) -> String:
	if w < 0 or w >= WEATHER_NAMES.size():
		return ""
	return WEATHER_NAMES[w]

## 取时段中文名
static func time_of_day_name(t: int) -> String:
	if t < 0 or t >= TIME_OF_DAY_NAMES.size():
		return ""
	return TIME_OF_DAY_NAMES[t]
