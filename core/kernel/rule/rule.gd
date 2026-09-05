# core/kernel/rule/rule.gd
# Kernel 契约（02 图 §6）：「一组业务判断为什么成立」（01 §24 / 宪法 RULE 005）。
# Rule 不负责 UI / Audio / Scene / Save / File / Godot Runtime。
# 返回值：满足条件返回 OperationResult.ok()，否则 fail(具体 ErrorCode)。

@abstract
class_name Rule
extends RefCounted

@abstract func evaluate(facts: GameFacts) -> OperationResult
