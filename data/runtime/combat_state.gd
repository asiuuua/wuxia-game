# data/runtime/combat_state.gd
# 单场战斗的运行时状态容器（规范 §5.3）
# 由 CombatService 构建与驱动；表现层（BattleScene）只读它来刷新 UI

extends RefCounted
class_name CombatState

var combat_id: String = ""
var is_active: bool = false
var combat_type: int = CombatEnums.CombatType.ENCOUNTER
var turn_mode: int = CombatEnums.TurnMode.SEQUENTIAL   # ATB / 固定顺序（battles.json 可配）
var result: int = CombatEnums.CombatResult.NONE

var player: CombatCharacter = null
var allies: Array[CombatCharacter] = []
var enemies: Array[CombatCharacter] = []
var entries: Array[String] = []

func get_alive_enemies() -> Array[CombatCharacter]:
	var alive: Array[CombatCharacter] = []
	for e in enemies:
		if e.is_alive():
			alive.append(e)
	return alive

func is_over() -> bool:
	if player == null or player.is_dead:
		return true
	return get_alive_enemies().is_empty()

func append_log(text: String) -> void:
	entries.append(text)
	if entries.size() > CombatConstants.MAX_TURN_LOG:
		entries.pop_front()
