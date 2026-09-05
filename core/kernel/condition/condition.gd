# core/kernel/condition/condition.gd
# Kernel 契约（02 图 §6）：「能不能做」。
# 冻结名：KERNEL-CONTRACT v1.2.0（02 图 §13 Freeze 清单）。
# 铁律（01 §24 / 宪法 RULE 005）：evaluate() 只读，不得修改任何状态（宪法 0-B.15）。

@abstract
class_name Condition
extends RefCounted

@abstract func evaluate(facts: GameFacts) -> bool
