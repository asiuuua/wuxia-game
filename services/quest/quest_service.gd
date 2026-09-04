# services/quest/quest_service.gd
# 任务服务（规范 §6）：接取、目标推进、完成、交付发奖
# 数据驱动：配置来自 ConfigManager；通过 EventBus 通知；不持有 Node（铁律）

extends ISaveable
class_name QuestService

var active_quests: Dictionary = {}     # quest_id -> QuestState
var completed_quests: Dictionary = {}
var tracked_ids: Array[String] = []

# ---- P3 统一条件（2026-09-04）：前置/回写走 core/condition.gd + GameFacts ----
var _facts: GameFacts = GameFacts.new()
var _condition_service: ConditionService = ConditionService.new(_facts)

func can_accept(quest_id: String) -> bool:
	if not ConfigManager.has_quest(quest_id):
		return false
	if active_quests.has(quest_id) or completed_quests.has(quest_id):
		return false
	# P3 统一条件：任务定义可携带 prerequisites 键值对（区域任务链驱动），
	# 编译为统一 DSL 求值；无法求值/不满足一律不可接（fail-closed 门禁语义）。
	var data: Dictionary = ConfigManager.get_quest(quest_id)
	var prereq: Dictionary = data.get("prerequisites", {})
	if not prereq.is_empty():
		if not _condition_service.evaluate(ConditionService.compile_keyvalue(prereq), "", false):
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

# ---- P3-c 目标/奖励 handler 注册表（2026-09-04）：新增目标/奖励类型 = 注册一个
# handler，不改本服务核心（整改路线 P3 验收标准）。类型推断：obj 显式 type 优先，
# 否则 target_battle→battle、need_item→give_item（存量数据零迁移）。
var _objective_handlers: Dictionary = {}   # type -> Callable(state, obj, event: Dictionary)
var _reward_handlers: Dictionary = {}      # key -> Callable(value, quest_id)

func _init() -> void:
	register_objective_handler("battle", _objective_battle)
	register_objective_handler("give_item", _objective_give_item)
	register_reward_handler("exp", _reward_exp)
	register_reward_handler("silver", _reward_silver)
	register_reward_handler("items", _reward_items)
	register_reward_handler("abilities", _reward_abilities)

func register_objective_handler(type: String, handler: Callable) -> void:
	_objective_handlers[type] = handler

func register_reward_handler(key: String, handler: Callable) -> void:
	_reward_handlers[key] = handler

func _objective_type(obj: Dictionary) -> String:
	var t := str(obj.get("type", ""))
	if t != "":
		return t
	if obj.has("target_battle"):
		return "battle"
	if obj.has("need_item"):
		return "give_item"
	return ""

# ---- 内置目标处理器 ----
func _objective_battle(state: QuestState, obj: Dictionary, event: Dictionary) -> void:
	if str(obj.get("target_battle", "")) == str(event.get("battle_id", "")):
		_progress(state, obj, 1)

func _objective_give_item(state: QuestState, obj: Dictionary, event: Dictionary) -> void:
	var item := str(obj.get("need_item", ""))
	if item == "" or str(event.get("item_id", "")) != item:
		return
	var need := int(obj.get("need_count", obj.get("need", 1)))
	var have := _facts.item_count(item)
	_sync_progress(state, obj, mini(have, need))

## 绝对值进度同步（give_item 类目标随持有量增减；battle 类走 _progress 增量）
func _sync_progress(state: QuestState, obj: Dictionary, absolute: int) -> void:
	var obj_id := String(obj.get("id", ""))
	if obj_id == "" or state.is_objective_completed(obj_id):
		return
	state.objectives_progress[obj_id] = absolute
	EventBus.quest_objective_updated.emit(state.quest_id, obj_id, absolute)
	if absolute >= int(obj.get("need_count", obj.get("need", 1))):
		state.objectives_completed[obj_id] = true
		EventBus.quest_objective_completed.emit(state.quest_id, obj_id)
		if state.are_all_required_objectives_completed([]):
			_complete(state)

## 事件路由入口：目标推进统一走 handler 注册表（战斗胜利 / 物品变动均汇入）
func _advance_on_victory(battle_id: String) -> void:
	for qid in active_quests.keys():
		var state: QuestState = active_quests[qid]
		var data: Dictionary = ConfigManager.get_quest(qid)
		for obj in data.get("objectives", []):
			_dispatch_objective(state, obj, {"battle_id": battle_id, "victory": true})

## 库存变动事件回调（GameManager 装配时连接 inventory_item_added；give_item 目标消费）
func _on_inventory_added(item_id: String, _count: int) -> void:
	for qid in active_quests.keys():
		var state: QuestState = active_quests[qid]
		var data: Dictionary = ConfigManager.get_quest(qid)
		for obj in data.get("objectives", []):
			_dispatch_objective(state, obj, {"item_id": item_id})

func _dispatch_objective(state: QuestState, obj: Dictionary, event: Dictionary) -> void:
	var h: Callable = _objective_handlers.get(_objective_type(obj), Callable())
	if h.is_valid():
		h.call(state, obj, event)

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
	# P3 统一条件：then_set 完成回写（区域任务链驱动，如 nv_flag_maiden_helped /
	# plot_advance=to_misty_town）。键值全量写入 GameState 全局旗标，随存档持久化。
	var then_set: Dictionary = data.get("then_set", {})
	for k in then_set.keys():
		_facts.set_flag(String(k), then_set[k])
	var rewards: Dictionary = data.get("rewards", {})
	# P3-c 奖励数据驱动分发：rewards 键 -> 注册表 handler（新奖励类型=注册，不改本函数）
	for key in rewards.keys():
		var h: Callable = _reward_handlers.get(String(key), Callable())
		if h.is_valid():
			h.call(rewards[key], quest_id)
		else:
			push_warning("[Quest] 未知奖励类型: %s（quest=%s）" % [key, quest_id])
	active_quests.erase(quest_id)
	completed_quests[quest_id] = state
	tracked_ids.erase(quest_id)
	EventBus.quest_turned_in.emit(quest_id)
	EventBus.notify_quest_track_changed.emit()
	return true

# ---- 内置奖励处理器（P3-c 注册表配对；P5 去定位器：经 GameFacts 适配器，不再直取 GameManager）----
func _reward_exp(value: Variant, _quest_id: String) -> void:
	_facts.gain_exp(int(value))

func _reward_silver(value: Variant, _quest_id: String) -> void:
	_facts.add_silver(int(value))

func _reward_items(value: Variant, quest_id: String) -> void:
	for item_reward in value:
		_facts.add_item(str(item_reward.get("item_id", "")), int(item_reward.get("count", 1)), "quest:%s" % quest_id)

func _reward_abilities(value: Variant, _quest_id: String) -> void:
	for ability_id in value:
		_facts.learn_ability(str(ability_id))

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
