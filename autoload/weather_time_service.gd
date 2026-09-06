# autoload/weather_time_service.gd
# 世界时钟控制器（阶段A 基础设施）：时间 / 天气 / 季节 的全局真相源
# 设计：自身是 autoload Node（不写 class_name，避免与单例名冲突），
#       运行时状态放在 WorldTimeState（ISaveable，由本服务在 _ready 注册存档）。
# 铁律：跨模块只走 EventBus；时间只在被显式推进时流动（睡眠/赶路/事件触发），不自带 tick。
# 注：路线图原列 WeatherTimeService + TimeService 两个，此处将"天数推进"折入本服务，
#     避免再建一个近空壳的 TimeService autoload（符合"不造空壳"红线）。

@warning_ignore("shadowed_global_identifier")

extends Node

# 自包含依赖：headless / 非编辑器加载时，class_name 全局注册顺序不可靠，
# 故在此 preload 兜底，保证本服务与其依赖脚本稳定编译（不依赖全局注册时机）
const WorldEnums = preload("res://core/enums/world_enums.gd")
const WorldTimeState = preload("res://data/runtime/world_time_state.gd")

# 运行时状态（ISaveable，存读档由 SaveManager 统一处理）
var state: WorldTimeState = WorldTimeState.new()

# === 调试 / 测试访问器（仅改值，不触发事件；类型均为基础类型，保证 --script 测试可解析） ===
# 三级标签（宪法 §80 / 07图 P-8/WT-4）：以下 debug 直改面均属 Test Only / Development Only，禁入生产逻辑
## 直接设定天数【Development Only·宪法§80三级标签】
func debug_set_day(d: int) -> void:
	state.day = d

## 直接设定季节【Development Only·宪法§80三级标签】
func debug_set_season(s: int) -> void:
	state.season = s

## 直接设定当天时刻【Development Only·宪法§80三级标签】
func debug_set_time_of_day(t: float) -> void:
	state.time_of_day = t

## 取状态存档快照（Dictionary，测试可解析）【Test Only·宪法§80三级标签】
func debug_save_state() -> Dictionary:
	return state.save()

## 从快照恢复状态【Test Only·宪法§80三级标签】
func debug_load_state(data: Dictionary) -> void:
	state.load(data)

func _ready() -> void:
	# 先给一个合理默认；若之后 LoadManager 载入存档，会覆盖本值
	state.reset_to_default()
	SaveManager.register_saveable(state)

# === 查询 ===
## 当前游戏内天数
func get_day() -> int:
	return state.day

## 当前时刻（0.0 - 24.0 小时）
func get_time_of_day() -> float:
	return state.time_of_day

## 当前季节枚举（WorldEnums.Season）
func get_season() -> int:
	return state.season

## 当前天气枚举（WorldEnums.Weather）
func get_weather() -> int:
	return state.weather

## 当前时段枚举（WorldEnums.TimeOfDay），由 time_of_day 归段
func get_time_of_day_phase() -> int:
	var h: float = state.time_of_day
	if h < 6.0 or h >= 20.0:
		return WorldEnums.TimeOfDay.NIGHT
	if h < 10.0:
		return WorldEnums.TimeOfDay.DAWN
	if h < 17.0:
		return WorldEnums.TimeOfDay.DAY
	return WorldEnums.TimeOfDay.DUSK

# === TimeConsumer 注册制（07图 TX-2/W-R03，B6 2026-09-06）：消费面显式注册、分相消费 ===
# 分相语义（07图 SD-5/0-C.15 消费相冻结）：0=业务推进相（姻缘/子嗣等按天推进的业务）
#   → 1=派生刷新相（随天变化的派生数据）→ 2=通知相。注册消费先于广播信号（对外通知最后）。
# 拉式读（get_day()）仍是首选消费形态；注册制供需要「按天回调」的业务使用，禁私听信号直改。
const CONSUMER_PHASES := [0, 1, 2]
var _day_consumers := {}   # phase -> Array[Callable(day: int)]（注册序即相内调用序）

func register_day_consumer(phase: int, cb: Callable) -> void:
	assert(CONSUMER_PHASES.has(phase), "TimeConsumer 相位必须 ∈ CONSUMER_PHASES")
	if not _day_consumers.has(phase):
		_day_consumers[phase] = []
	if not _day_consumers[phase].has(cb):
		_day_consumers[phase].append(cb)   # 幂等注册（防重复 connect 语义）

func _notify_day_consumers(day: int) -> void:
	for phase in CONSUMER_PHASES:
		for cb in _day_consumers.get(phase, []):
			cb.call(day)

# === 推进 ===
## 推进若干小时；跨过 24 时自动进天（并重掷天气/季节）
func advance_time(hours: float) -> void:
	if hours <= 0.0:
		return
	state.time_of_day += hours
	while state.time_of_day >= 24.0:
		state.time_of_day -= 24.0
		advance_day(1)
	EventBus.world_time_changed.emit(state.day, state.time_of_day, state.season, state.weather)

## 推进若干天：累加天数、按 season_days 更新季节、重掷天气
func advance_day(days: int = 1) -> void:
	if days <= 0:
		return
	state.day += days
	_update_season()
	_roll_weather()
	_notify_day_consumers(state.day)   # B6：注册消费分相先行（W-R03 禁私听信号直改）
	EventBus.world_day_advanced.emit(state.day)   # 广播相：对外通知（表现层/UI 可听）
	EventBus.world_time_changed.emit(state.day, state.time_of_day, state.season, state.weather)

## 强制设定天气（调试 / 剧情事件用）
func set_weather(weather: int) -> void:
	state.weather = weather
	EventBus.world_weather_changed.emit(state.weather)
	EventBus.world_time_changed.emit(state.day, state.time_of_day, state.season, state.weather)

# === 便捷判断 ===
func is_season(s: int) -> bool:
	return state.season == s

func is_weather(w: int) -> bool:
	return state.weather == w

## 新游戏：重置世界时钟到默认
func reset() -> void:
	state.reset_to_default()
	EventBus.world_time_changed.emit(state.day, state.time_of_day, state.season, state.weather)

# === 内部 ===
## 按 day / season_days 推算当前季节（依赖 world_config.json）
func _update_season() -> void:
	var cfg: Dictionary = ConfigManager.get_world_config()
	var season_days: int = int(cfg.get("season_days", 15))
	if season_days <= 0:
		season_days = 15
	@warning_ignore("integer_division")
	var idx: int = (state.day - 1) / season_days
	# 余数对应 WorldEnums.Season 顺序（0=春 1=夏 2=秋 3=冬）
	state.season = idx % 4

## 按当前季节的权重表重掷天气（依赖 world_config.json 的 weather_weights）
func _roll_weather() -> void:
	var cfg: Dictionary = ConfigManager.get_world_config()
	var weights: Dictionary = cfg.get("weather_weights", {})
	var key: String = str(state.season)
	if not weights.has(key):
		key = "0"
	var table: Dictionary = weights.get(key, {})
	var total: int = 0
	for w in table.values():
		total += int(w)
	if total <= 0:
		state.weather = WorldEnums.Weather.CLEAR
		return
	# 天气 roll 按日+季决定论（07图 W-R01/W-R05：禁全局 randi，同日同季必同天气，可回放可单测；
	# RandomProvider 注入随 02 图 Kernel 契约 Phase2 收编）
	var w_rng := SeededRNG.new()
	w_rng.configure(hash("weather:v1:%d:%d" % [state.day, state.season]))
	var roll: int = w_rng.randi_range(0, total - 1)
	var accum: int = 0
	for w_key in table.keys():
		accum += int(table[w_key])
		if roll < accum:
			state.weather = int(w_key)
			return
	state.weather = WorldEnums.Weather.CLEAR
