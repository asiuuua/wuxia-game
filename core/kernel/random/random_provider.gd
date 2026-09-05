# core/kernel/random/random_provider.gd
# Kernel 契约（02 图 §10）：确定性随机契约（01 §30）。
# 铁律：Domain / Kernel 禁止 randf() / randi() / RandomNumberGenerator.new()（K-R04）。
# 实现：SeededRandomProvider，位于 infrastructure/random/。
# 迁移映射（02 图 §10）：现有 SeededRNG 是良好基础，提升为 RandomProvider 实现即可。

@abstract
class_name RandomProvider
extends RefCounted

@abstract func set_seed(seed_value: int) -> void

@abstract func get_seed() -> int

@abstract func next_float() -> float

@abstract func next_int(min_value: int, max_value: int) -> int
