# core/kernel/effect/effect.gd
# Kernel 契约（02 图 §6）：「状态发生什么变化」（01 §24）。
# 铁律：Effect 在事务内执行，必须可登记进 Mutation Journal（可回滚）。

@abstract
class_name Effect
extends RefCounted

@abstract func apply(ctx: MutationContext) -> OperationResult
