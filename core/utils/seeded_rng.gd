# core/utils/seeded_rng.gd
# 确定性随机源：战斗所有随机（闪避 / 暴击 / 范围抖动）都走它
# 目的：同 seed + 同指令序列 = 同结果 → 战斗可存档、可回放、可单测（对标大厂回归标准）
# 严禁在战斗逻辑里直接调用全局 randf()——那会破坏可复现性

extends RefCounted
class_name SeededRNG

var seed_value: int = 0

func configure(seed_val: int) -> void:
	seed_value = seed_val
	# RandomNumberGenerator 的 seed 是属性（非方法），直接赋值即可
	var r := RandomNumberGenerator.new()
	r.seed = seed_val
	_rng = r

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()

func chance(p: float) -> bool:
	return _rng.randf() < p

func randf() -> float:
	return _rng.randf()

func randi_range(a: int, b: int) -> int:
	return _rng.randi_range(a, b)

func randf_range(a: float, b: float) -> float:
	return _rng.randf_range(a, b)
