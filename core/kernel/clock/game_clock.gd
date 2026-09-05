# core/kernel/clock/game_clock.gd
# Kernel 契约（02 图 §9）：游戏时间契约（01 §29）。
# 铁律：游戏逻辑禁止直接读系统时间（Time.get_unix_time_from_system 等，K-R05）。
# 实现：RealClock / FakeClock / ReplayClock，位于 infrastructure/clock/。
# 迁移映射（02 图 §9）：weather_time_service 的时间职责收敛为 GameClock 实现，天气留 World 模块。

@abstract
class_name GameClock
extends RefCounted

## 当前游戏 tick（唯一权威时间）
@abstract func now_tick() -> int

## 游戏内时间戳（非系统时间）
@abstract func now_timestamp() -> int

## 推进时间。RealClock 实现应拒绝调用或空实现；Fake/Replay 实现有效
@abstract func advance(delta_tick: int) -> void

## 是否允许推进（RealClock = false）
@abstract func can_advance() -> bool
