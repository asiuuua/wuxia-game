# core/kernel/event/domain_event.gd
# Kernel 契约（02 图 §5.3）：已发生的事实（01 §23）。
# 命名铁律：过去时。ItemPurchasedEvent / MarriageFormedEvent / QuestCompletedEvent。
# 禁止：StartMarriageEvent / DoQuestEvent / ChangeNPCEvent（这些是 Command 语义，K-R12）。
# 跨业务事实一律用 Typed Domain Event；禁止 signal something_happened(data: Dictionary)（0-B.12）。

class_name DomainEvent
extends RefCounted

enum Phase { PENDING, COMMITTED }

var _event_id: StringName
var _event_type: StringName
var _phase: Phase
var _occurred_tick: int
var _causation_id: StringName      # 由哪个 Command 触发
var _correlation_id: StringName
var _transaction_id: StringName

func _init(
	event_id: StringName,
	event_type: StringName,
	phase: Phase = Phase.PENDING,
	occurred_tick: int = 0,
	causation_id: StringName = &"",
	correlation_id: StringName = &"",
	transaction_id: StringName = &""
) -> void:
	_event_id = event_id
	_event_type = event_type
	_phase = phase
	_occurred_tick = occurred_tick
	_causation_id = causation_id
	_correlation_id = correlation_id
	_transaction_id = transaction_id

func get_event_id() -> StringName:
	return _event_id

func get_event_type() -> StringName:
	return _event_type

func get_occurred_tick() -> int:
	return _occurred_tick

func get_causation_id() -> StringName:
	return _causation_id

func get_correlation_id() -> StringName:
	return _correlation_id

func get_transaction_id() -> StringName:
	return _transaction_id

## 铁律（01 §19）：只有 COMMITTED 才能驱动 Presentation / Persistence / Projection
func is_committed() -> bool:
	return _phase == Phase.COMMITTED

func get_type() -> StringName:
	return _event_type
