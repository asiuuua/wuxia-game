# tools/performance_monitor.gd
# 性能监控器（规范 §4.6.1）：仅调试构建启用；记录帧率/卡顿/模块计时，守住性能红线。
# 注册为 Autoload 单例 PerformanceMonitor，发布版自动 queue_free。
# 注：autoload 脚本不写 class_name（与单例名冲突），通过全局单例名调用。

extends Node

var _frame_times: Array[float] = []
var _fps_history: Array[float] = []
var _frame_count: int = 0
var _spike_threshold: float = 33.0  # 超过 33ms（<30fps）记为卡顿
var _spike_count: int = 0
var _module_timers: Dictionary = {}

const MAX_HISTORY: int = 300  # 5 秒 @ 60fps

func _ready() -> void:
	if not OS.has_feature("debug"):
		queue_free()
		return
	set_process(true)

func _process(delta: float) -> void:
	_frame_count += 1
	_frame_times.append(delta * 1000.0)
	if _frame_times.size() > MAX_HISTORY:
		_frame_times.pop_front()
	var fps: float = 1.0 / delta if delta > 0 else 0.0
	_fps_history.append(fps)
	if _fps_history.size() > MAX_HISTORY:
		_fps_history.pop_front()
	if delta * 1000.0 > _spike_threshold:
		_spike_count += 1
		GameLogger.warn("Perf", "Frame spike: %.1fms (frame %d)" % [delta * 1000.0, _frame_count])

## 模块性能计时：start_timer/end_timer 包裹耗时逻辑
func start_timer(module: String) -> void:
	_module_timers[module] = Time.get_ticks_msec()

func end_timer(module: String) -> float:
	if not _module_timers.has(module):
		return 0.0
	var elapsed: float = Time.get_ticks_msec() - _module_timers[module]
	_module_timers.erase(module)
	if elapsed > 16.0:  # 超过一帧
		GameLogger.warn("Perf", "Module %s took %.1fms" % [module, elapsed])
	return elapsed

func get_average_fps() -> float:
	if _fps_history.is_empty():
		return 0.0
	var sum: float = 0.0
	for fps in _fps_history:
		sum += fps
	return sum / _fps_history.size()

func get_average_frame_time() -> float:
	if _frame_times.is_empty():
		return 0.0
	var sum: float = 0.0
	for t in _frame_times:
		sum += t
	return sum / _frame_times.size()

func get_spike_count() -> int:
	return _spike_count

func get_stats() -> Dictionary:
	return {
		"fps": Engine.get_frames_per_second(),
		"avg_fps": get_average_fps(),
		"avg_frame_ms": get_average_frame_time(),
		"spike_count": _spike_count,
		"frame_count": _frame_count,
		"memory_mb": float(OS.get_static_memory_usage()) / 1024.0 / 1024.0,
		# draw_calls / objects_in_frame 依赖 Godot 各版本 Performance 常量名差异，
		# 跨版本不稳定；按需启用时按目标引擎版本补对应 Performance.Monitor 常量
	}

func reset() -> void:
	_frame_times.clear()
	_fps_history.clear()
	_frame_count = 0
	_spike_count = 0
