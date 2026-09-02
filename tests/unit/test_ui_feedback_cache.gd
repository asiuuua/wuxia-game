# tests/unit/test_ui_feedback_cache.gd
# UIFeedback 令牌解析结果缓存回归（审计派单 fdfcce7396ed）：
# 悬停动效高频触发时，令牌→Tween 枚举解析结果应被缓存复用，避免每次重复查表。

extends TestBase

const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

func test_token_cache_populated_and_reused() -> void:
	# 清空静态缓存，确保从零验证
	UIFeedback._trans_cache.clear()
	UIFeedback._ease_cache.clear()
	var fx := UIFeedback.new()
	var target := Control.new()
	fx._target = target
	# 首次解析：应填充静态缓存
	var t1: int = fx._cached_trans("standard")
	var e1: int = fx._cached_ease("standard")
	expect(UIFeedback._trans_cache.has("standard"), "首次解析后 _trans_cache 应缓存 standard 令牌")
	expect(UIFeedback._ease_cache.has("standard"), "首次解析后 _ease_cache 应缓存 standard 令牌")
	# 二次解析：应命中缓存并返回相同值
	expect(fx._cached_trans("standard") == t1, "二次解析应返回与首次一致的 trans 值")
	expect(fx._cached_ease("standard") == e1, "二次解析应返回与首次一致的 ease 值")
	# 跨实例共享：新实例也应命中同一静态缓存
	var fx2 := UIFeedback.new()
	expect(fx2._cached_trans("standard") == t1, "静态缓存应跨实例共享")
	expect(fx2._cached_ease("standard") == e1, "静态 ease 缓存应跨实例共享")
	fx.free()
	fx2.free()
	target.free()

func test_instance_cache_populated_after_use() -> void:
	var fx := UIFeedback.new()
	fx._preset = "hover"
	var target := Control.new()
	fx._target = target
	# 首次取用：应填充实例级缓存
	var hs: float = fx._hover_scale()
	expect(fx._cached_hover_scale_f > 0.0, "首次取用后 _cached_hover_scale_f 应被填充，实际 %f" % fx._cached_hover_scale_f)
	expect(fx._hover_scale() == hs, "重复取用应返回一致缩放值")
	var dur: float = fx._cached_duration()
	expect(fx._cached_duration_f > 0.0, "首次取用后 _cached_duration_f 应被填充，实际 %f" % fx._cached_duration_f)
	expect(fx._cached_duration() == dur, "重复取用应返回一致时长")
	# _cached_preset 由 _easing_token() 填充（预设 dict 缓存）
	var tok: String = fx._easing_token()
	expect(tok != "", "预设应能解析出 easing 令牌")
	expect(not fx._cached_preset.is_empty(), "首次取用后 _cached_preset 应被填充")
	fx.free()
	target.free()

func test_animate_to_uses_cached_values() -> void:
	UIFeedback._trans_cache.clear()
	UIFeedback._ease_cache.clear()
	var fx := UIFeedback.new()
	var target := Control.new()
	fx._target = target
	fx._animate_to(1.1)   # 应走缓存路径且不崩
	expect(UIFeedback._trans_cache.size() > 0, "_animate_to 后静态 trans 缓存应非空")
	expect(UIFeedback._ease_cache.size() > 0, "_animate_to 后静态 ease 缓存应非空")
	expect(fx._cached_duration_f > 0.0, "_animate_to 后实例时长缓存应被填充")
	fx.free()
	target.free()
