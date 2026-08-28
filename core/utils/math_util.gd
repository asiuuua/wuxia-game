# core/utils/math_util.gd
# 数学工具：纯函数，静态调用

extends RefCounted
class_name MathUtil

static func clamp_int(value: int, min_v: int, max_v: int) -> int:
	return mini(maxi(value, min_v), max_v)

static func rand_int(min_v: int, max_v: int) -> int:
	return randi_range(min_v, max_v)

static func chance(rate: float) -> bool:
	return randf() < rate
