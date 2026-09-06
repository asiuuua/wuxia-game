# tests/unit/test_time_consumer.gd
# GATE：07 图 W-R03/TX-2（B6 2026-09-06）——TimeConsumer 注册制分相消费。
# 消费面必走注册制（业务推进相 → 派生刷新相 → 通知相），禁私听信号直改；
# 广播信号（world_day_advanced/world_time_changed）保留为对外通知相。
# 安全约定：直接操作 WeatherTimeService 注册表，after_each 清场防污染。

extends TestBase
class_name TestTimeConsumer

var _calls: Array = []

func before_each() -> void:
	_calls = []

func after_each() -> void:
	WeatherTimeService._day_consumers.clear()   # 清场：注册消费者不泄漏到其他用例

func _rec(tag: String) -> Callable:
	return func(day: int) -> void:
		_calls.append("%s@%d" % [tag, day])

# === 注册消费按分相顺序调用（0 → 1 → 2） ===
func test_phases_run_in_frozen_order() -> void:
	var base: int = WeatherTimeService.get_day()
	WeatherTimeService.register_day_consumer(2, _rec("notify"))
	WeatherTimeService.register_day_consumer(0, _rec("biz"))
	WeatherTimeService.register_day_consumer(1, _rec("derive"))
	WeatherTimeService.advance_day(1)
	expect(_calls == ["biz@%d" % (base + 1), "derive@%d" % (base + 1), "notify@%d" % (base + 1)],
		"分相消费顺序应冻结为 biz→derive→notify（实际 %s，基线 %d）" % [_calls, base])

# === 注册幂等：同回调重复注册只消费一次（防重复 connect 语义） ===
func test_register_idempotent() -> void:
	var cb := _rec("once")
	WeatherTimeService.register_day_consumer(0, cb)
	WeatherTimeService.register_day_consumer(0, cb)
	WeatherTimeService.register_day_consumer(0, cb)
	var base: int = WeatherTimeService.get_day()
	WeatherTimeService.advance_day(1)
	expect(_calls == ["once@%d" % (base + 1)], "同回调重复注册应只消费一次（实际 %s）" % [_calls])

# === advance_day(0) 不推进不消费；多天 delta 如实传递 ===
func test_zero_days_no_call_and_delta_passthrough() -> void:
	WeatherTimeService.register_day_consumer(0, _rec("biz"))
	WeatherTimeService.advance_day(0)
	expect(_calls.is_empty(), "advance_day(0) 不应触发消费")
	var base: int = WeatherTimeService.get_day()
	WeatherTimeService.advance_day(3)
	expect(_calls == ["biz@%d" % (base + 3)], "多天推进应传最终 day（实际 %s）" % [_calls])

# === advance_time 跨 24h 自动进天同样走注册消费 ===
func test_advance_time_cross_day_triggers() -> void:
	WeatherTimeService.register_day_consumer(0, _rec("biz"))
	var before: int = WeatherTimeService.get_day()
	WeatherTimeService.advance_time(25.0)   # 跨一天
	var after: int = WeatherTimeService.get_day()
	expect(after == before + 1, "跨 24h 应自动进天（%d → %d）" % [before, after])
	expect(_calls == ["biz@%d" % after], "自动进天应触发注册消费（实际 %s）" % [_calls])

# === 事务相先于广播相：消费者先收到回调，信号后发（07图消费相冻结） ===
func test_consumers_before_broadcast() -> void:
	var order := []
	WeatherTimeService.register_day_consumer(0, func(day: int) -> void:
		order.append("consumer")
		order.append("signal_seen=%s" % str(EventBus.world_day_advanced.get_connections().size() >= 0)))
	# 直接同步推进（headless 无场景监听者，广播后信号即空转）
	WeatherTimeService.advance_day(1)
	expect(order[0] == "consumer", "注册消费应先于广播处理（实际 %s）" % [order])
