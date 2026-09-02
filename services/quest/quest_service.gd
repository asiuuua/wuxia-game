# services/quest/quest_service.gd
# 任务服务（规范 §6）：接取、目标推进、完成、交付发奖
# 数据驱动：配置来自 ConfigManager；通过 EventBus 通知；不持有 Node（铁律）

extends ISaveable
class_name QuestService

var active_quests: Dictionary = {}     # quest_id -> QuestState
var completed_quests: Dictionary = {}
var tracked_ids: Array[String] = []

func can_accept(quest_id: String) -> bool:
	if not ConfigManager.has_quest(quest_id):
		return false
	if active_quests.has(quest_id) or completed_quests.has(quest_id):
		return false
	return true

func accept(quest_id: String) -> bool:
	if not can_accept(quest_id):
		return false
	var state := QuestState.new()
	state.quest_id = quest_id
	state.status = QuestEnums.QuestStatus.ACTIVE
	active_quests[quest_id] = state
	if tracked_ids.size() < 5:
		tracked_ids.append(quest_id)
		state.tracked = true
	EventBus.quest_accepted.emit(quest_id)
	EventBus.notify_quest_track_changed.emit()
	return true

## 战斗结束事件回调（订阅 EventBus.combat_finished，由 GameManager 连接）
## 战斗模块只发快照事件，本服务据此推进目标，不直接被战斗调用（蓝图铁律）
func _on_combat_finished(combat_id: String, victory: bool, _escaped: bool, _snapshots: Array) -> void:
	if victory:
		_advance_on_victory(combat_id)

## 战斗胜利后推进匹配该战斗的任务目标
func _advance_on_victory(battle_id: String) -> void:
	for qid in active_quests.keys():
		var state: QuestState = active_quests[qid]
		var data: Dictionary = ConfigManager.get_quest(qid)
		for obj in data.get("objectives", []):
			if obj.get("target_battle", "") == battle_id:
				_progress(state, obj, 1)

## 返回进行中任务 ID 列表（供 SaveValidator 遍历校验）
func get_active_quest_ids() -> Array[String]:
	var out: Array[String] = []
	for qid in active_quests.keys():
		out.append(qid)
	return out

## 将任务置为失败（多失败分支由 reason 区分）；并发出失败通知
func fail_quest(quest_id: String, reason: String = "FAILED") -> void:
	if not active_quests.has(quest_id):
		return
	var state: QuestState = active_quests[quest_id]
	match reason:
		"FAIL_DEAD_NPC":
			state.status = QuestEnums.QuestStatus.FAIL_DEAD_NPC
		"FAIL_ESCAPED":
			state.status = QuestEnums.QuestStatus.FAIL_ESCAPED
		_:
			state.status = QuestEnums.QuestStatus.FAILED
	EventBus.quest_failed.emit(quest_id, reason)

func _progress(state: QuestState, obj: Dictionary, count: int) -> void:
	var obj_id: String = String(obj.get("id", ""))
	if state.is_objective_completed(obj_id):
		return
	var current: int = state.get_objective_progress(obj_id) + count
	state.objectives_progress[obj_id] = current
	EventBus.quest_objective_updated.emit(state.quest_id, obj_id, current)
	if current >= obj.get("need", 1):
		state.objectives_completed[obj_id] = true
		EventBus.quest_objective_completed.emit(state.quest_id, obj_id)
		if state.are_all_required_objectives_completed([]):
			_complete(state)

func _complete(state: QuestState) -> void:
	state.status = QuestEnums.QuestStatus.COMPLETED
	EventBus.quest_completed.emit(state.quest_id)
	var data: Dictionary = ConfigManager.get_quest(state.quest_id)
	if data.get("auto_complete", true):
		turn_in(state.quest_id)

## 交付并发放奖励：经验 -> 玩家；物品 -> 背包；武学 -> 武学服务
func turn_in(quest_id: String) -> bool:
	if not active_quests.has(quest_id):
		return false
	var state: QuestState = active_quests[quest_id]
	if state.status != QuestEnums.QuestStatus.COMPLETED:
		return false
	var data: Dictionary = ConfigManager.get_quest(quest_id)
	state.status = QuestEnums.QuestStatus.TURNED_IN
	var rewards: Dictionary = data.get("rewards", {})
	if rewards.get("exp", 0) > 0:
		GameManager.player_state.gain_exp(rewards["exp"])
	if rewards.get("silver", 0) > 0:
		GameManager.player_state.silver += rewards["silver"]
	for item_reward in rewards.get("items", []):
		GameManager.inventory_service.add_item(item_reward.get("item_id", ""), item_reward.get("count", 1), "quest:%s" % quest_id)
	for ability_reward in rewards.get("abilities", []):
		GameManager.ability_service.learn(ability_reward)
	active_quests.erase(quest_id)
	completed_quests[quest_id] = state
	tracked_ids.erase(quest_id)
	EventBus.quest_turned_in.emit(quest_id)
	EventBus.notify_quest_track_changed.emit()
	return true

func get_tracked() -> Array[QuestState]:
	var out: Array[QuestState] = []
	for qid in tracked_ids:
		if active_quests.has(qid):
			var state: QuestState = active_quests[qid]
			out.append(state)
	return out

func is_active(quest_id: String) -> bool:
	return active_quests.has(quest_id)

# === 任务阶段（章节进度）===
# 实际状态由 GameState 持有（存档唯一真源），本服务仅作门面转发，保持调用入口一致
func get_phase() -> int:
	return GameState.get_quest_phase()

func set_phase(value: int) -> void:
	GameState.set_quest_phase(value)

func advance_phase() -> int:
	return GameState.advance_quest_phase()

func reset() -> void:
	active_quests.clear()
	completed_quests.clear()
	tracked_ids.clear()
	EventBus.notify_quest_track_changed.emit()

func get_save_key() -> String:
	return "quest"

func save() -> Dictionary:
	var out: Dictionary = {}
	for qid in active_quests:
		out[qid] = active_quests[qid].serialize()
	return {"active": out, "completed": completed_quests.keys(), "tracked": tracked_ids}

func load(data: Dictionary) -> void:
	active_quests.clear()
	completed_quests.clear()
	tracked_ids.clear()
	for qid in data.get("active", {}):
		var state := QuestState.new()
		state.deserialize(data["active"][qid])
		active_quests[qid] = state
	for qid in data.get("completed", []):
		completed_quests[qid] = true
	# data.get 返回 Variant Array；typed Array 赋值同 ability_service.gd:77 须显式 String() 循环
	tracked_ids.clear()
	for s in data.get("tracked", []):
		tracked_ids.append(String(s))
