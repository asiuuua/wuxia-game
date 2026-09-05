# core/kernel/transaction/undo_strategy.gd
# Kernel 契约（02 图 §7.3）：回滚策略。由 State Owner 提供，持有 before 值。
# restore() 返回 true = 恢复成功；返回 false = undo 失败 → RECOVERY_REQUIRED。
# 铁律（01 §18）：undo 失败不得被 catch + print 掩盖。
# 禁止用反射 / Object.call() 字符串方法名做通用恢复（宪法第 153 节：禁止过度魔法）；
# 每个状态键由 Owner 提供具体 Strategy 类（O-3 已追认：每状态键一个类可接受）。
# Kernel 不感知业务类型：before/after 具体值封装在 Strategy 内。

@abstract
class_name UndoStrategy
extends RefCounted

@abstract func restore() -> bool
