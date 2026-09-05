# core/kernel/condition/game_facts.gd
# Kernel 契约（02 图 §6）：只读事实门面，供 Condition / Rule 求值。
# 实现由各 Module 或 Application 提供；Kernel 只定义契约。
# 铁律：GameFacts 只读，不得反向修改 Domain State。
# 禁止把 GameFacts 做成万能 Dictionary —— 取值方法必须强类型。
# 迁移备注（02 图 §15）：存量适配器 services/quest/facts.gd 已改名 ServiceGameFacts；
# 其升级为实现本契约（补 get_int/get_bool/get_entity_id）属 Phase D 各模块批次。

@abstract
class_name GameFacts
extends RefCounted

@abstract func get_int(key: StringName) -> int

@abstract func get_bool(key: StringName) -> bool

@abstract func get_entity_id(key: StringName) -> EntityId
