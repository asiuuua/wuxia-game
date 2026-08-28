# autoload/save_validator.gd
# 存档校验 & 自动修复器（蓝图 1-3）：读档完成、业务模块启动前执行。
# 职责：检测「任务配置条件」与「GameState 单位真实状态」的矛盾，自动置失败 phase，
#       抛出修复通知，并写修复日志。只修正数据矛盾，绝不修改战斗/任务业务逻辑。
# 触发：订阅 EventBus.game_loaded（SaveManager.load_from_slot 读档后发出）。

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错。

var last_repair_log: Array = []   # 最近一次修复记录（便于调试 / UI 展示）

func _ready() -> void:
	EventBus.game_loaded.connect(_on_game_loaded)

## 读档后入口
func _on_game_loaded(_slot: int) -> void:
	validate()

## 核心校验：遍历进行中任务，按 fail_conditions 比对单位真实状态
func validate() -> Array:
	last_repair_log.clear()
	var quest_svc = GameManager.quest_service
	if quest_svc == null:
		return last_repair_log
	for quest_id in quest_svc.get_active_quest_ids():
		var cfg: Dictionary = ConfigManager.get_quest(quest_id)
		var fail_conditions: Array = cfg.get("fail_conditions", [])
		for cond in fail_conditions:
			var unit_id: String = cond.get("unit_id", "")
			var must_alive: bool = cond.get("must_alive", false)
			if unit_id == "":
				continue
			if must_alive and not GameState.is_unit_alive(unit_id):
				# 检测到矛盾：任务要求单位存活，但世界态记录其已死亡
				_repair(quest_id, unit_id, "FAIL_DEAD_NPC")
				break   # 同一任务只置一次失败
	return last_repair_log

## 执行一次修复：置任务失败 + 抛通知 + 记日志
func _repair(quest_id: String, unit_id: String, reason: String) -> void:
	GameManager.quest_service.fail_quest(quest_id, reason)
	EventBus.quest_failed.emit(quest_id, reason)
	var entry := "存档修复：任务 %s 因单位 %s 状态冲突被置为失败(%s)" % [quest_id, unit_id, reason]
	last_repair_log.append(entry)
	GameLogger.warn("SaveValidator", entry)
