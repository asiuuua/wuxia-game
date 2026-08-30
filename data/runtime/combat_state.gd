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
# 组队多玩家单位（P2）：主角为 player，其余同伴在此数组；为空则退化为单玩家模式。
# 逻辑层完全支持多玩家单位行动，但本窗战斗 UI 当前仅驱动 player（组队选择 UI 为后续增量）。
var player_party: Array[CombatCharacter] = []
var enemies: Array[CombatCharacter] = []
var entries: Array[String] = []

func get_alive_enemies() -> Array[CombatCharacter]:
	var alive: Array[CombatCharacter] = []
	for e in enemies:
		if e.is_alive():
			alive.append(e)
	return alive

func is_over() -> bool:
	# 敌方全灭 = 胜利，必然结束（保留原语义，否则战斗永不判定胜利）
	if get_alive_enemies().is_empty():
		return true
	# 玩家方全灭 = 失败，结束；组队/友方 NPC 模式下需主角与所有同伴均阵亡
	return is_player_side_wiped()

## 玩家方是否全灭：主角 + 组队同伴(player_party) + 友方 NPC(allies) 全部阵亡才算
## 单玩家（player_party 与 allies 皆空）退化为"仅看主角"
func is_player_side_wiped() -> bool:
	if player != null and player.is_alive():
		return false
	for p in player_party:
		if p.is_alive():
			return false
	for a in allies:
		if a.is_alive():
			return false
	return true

func append_log(text: String) -> void:
	entries.append(text)
	if entries.size() > CombatConstants.MAX_TURN_LOG:
		entries.pop_front()
