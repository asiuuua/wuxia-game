# core/kernel/query/query.gd
# Kernel 契约（02 图 §5.2）：只读请求（01 §22）。
# 铁律：Query 只读、不改变 Domain State、不启动业务 Mutation（宪法第 111 节）。
# 无泛型替代约定：每个 Query 声明自己返回的 XxxSnapshot，QueryResult 只做传输壳（O-2 已追认）。

class_name Query
extends RefCounted

var _query_id: StringName
var _actor_id: EntityId
var _game_tick: int
var _correlation_id: StringName

func _init(query_id: StringName, actor_id: EntityId, game_tick: int, correlation_id: StringName = &"") -> void:
	_query_id = query_id
	_actor_id = actor_id
	_game_tick = game_tick
	_correlation_id = correlation_id

func get_query_id() -> StringName:
	return _query_id

func get_actor_id() -> EntityId:
	return _actor_id

func get_game_tick() -> int:
	return _game_tick

func get_correlation_id() -> StringName:
	return _correlation_id

func get_type() -> StringName:
	return &"Query"
