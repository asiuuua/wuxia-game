# data/runtime/quest_state.gd
# 任务运行时状态（规范 §6.3）

extends RefCounted
class_name QuestState

var quest_id: String = ""
var status: int = QuestEnums.QuestStatus.INACTIVE
var objectives_progress: Dictionary = {}   # objective_id -> 当前进度
var objectives_completed: Dictionary = {}  # objective_id -> bool
var tracked: bool = false

func is_objective_completed(obj_id: String) -> bool:
	return objectives_completed.get(obj_id, false)

func get_objective_progress(obj_id: String) -> int:
	return objectives_progress.get(obj_id, 0)

func are_all_required_objectives_completed(_optional_ids: Array[String]) -> bool:
	var data: Dictionary = ConfigManager.get_quest(quest_id)
	for obj in data.get("objectives", []):
		if obj.get("optional", false):
			continue
		if not is_objective_completed(obj["id"]):
			return false
	return true

func serialize() -> Dictionary:
	return {
		"id": quest_id, "status": status,
		"progress": objectives_progress, "completed": objectives_completed,
		"tracked": tracked,
	}

func deserialize(data: Dictionary) -> void:
	quest_id = data.get("id", "")
	status = data.get("status", QuestEnums.QuestStatus.INACTIVE)
	objectives_progress = data.get("progress", {})
	objectives_completed = data.get("completed", {})
	tracked = data.get("tracked", false)
