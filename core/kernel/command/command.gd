# core/kernel/command/command.gd
# Kernel 契约（02 图 §5.1）：意图（01 §21）。可记录 / 可测试 / 可排序 / 可重放。
# Command 不修改 UI，不直接修改 Domain State。
# 具体命令命名：BuyItemCommand / ProposeMarriageCommand / AttackCommand（意图式）；
# 禁止 SetNPCStateCommand 这类暴露内部实现的命令（宪法第 112 节）。

class_name Command
extends RefCounted

var _command_id: StringName
var _sequence: int                 # 排序主键（01 §65）
var _source: StringName            # player / ai / story / debug / replay / editor
var _actor_id: EntityId
var _game_tick: int
var _correlation_id: StringName
var _causation_id: StringName

func _init(
	command_id: StringName,
	sequence: int,
	source: StringName,
	actor_id: EntityId,
	game_tick: int,
	correlation_id: StringName = &"",
	causation_id: StringName = &""
) -> void:
	_command_id = command_id
	_sequence = sequence
	_source = source
	_actor_id = actor_id
	_game_tick = game_tick
	_correlation_id = correlation_id
	_causation_id = causation_id

func get_command_id() -> StringName:
	return _command_id

func get_sequence() -> int:
	return _sequence

func get_source() -> StringName:
	return _source

func get_actor_id() -> EntityId:
	return _actor_id

func get_game_tick() -> int:
	return _game_tick

func get_correlation_id() -> StringName:
	return _correlation_id

func get_causation_id() -> StringName:
	return _causation_id

## 子类覆写，返回具体命令类型名（用于 Contract Registry 与 replay）
func get_type() -> StringName:
	return &"Command"
