# services/quest/quest_service.gd
# 任务服务（规范 §6）：接取、目标推进、完成、交付发奖
# 数据驱动：配置来自 ConfigManager；通过 EventBus 通知；不持有 Node（铁律）

extends ISaveable
class_name QuestService

var active_quests: Dictionary = {}     # quest_id -> QuestState
var completed_quests: Dictionary = {}
var tracked_ids: Array[String] = []

# ---- P3 统一条件（2026-09-04）：前置/回写走 core/condition.gd + ServiceGameFacts ----
# （2026-09-06：原 GameFacts 适配器改名 ServiceGameFacts，kernel 冻结名 GameFacts 归 core/kernel/）
var _facts: ServiceGameFacts = ServiceGameFacts.new()
var _condition_service: ConditionService = ConditionService.new(_facts)
var _retrying: bool = false   # retry_completed_turn_ins 防重入闸门

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
## QD-R07 分相化（12 图 Phase2）：回调只入队，帧末 call_deferred 统一冲刷（禁回调内同步重入推进）
func _on_combat_finished(combat_id: String, victory: bool, _escaped: bool, _snapshots: Array) -> void:
	if victory:
		_enqueue_event({"type": "battle", "battle_id": combat_id})

# ---- 目标 handler 注册表（P3-c 2026-09-04）：新增目标类型 = 注册一个
# handler，不改本服务核心（整改路线 P3 验收标准）。类型推断：obj 显式 type 优先，
# 否则 target_battle→battle、need_item→give_item（存量数据零迁移）。
# 奖励/接交任务副作用已收编 EffectRegistry（12 图 QD-2 2026-09-06）：五类 kind 锁定，
# 统一 handler 签名 func(payload, ctx)，由 attach_effects 注册进域级共享注册表。
var _objective_handlers: Dictionary = {}   # type -> Callable(state, obj, event: Dictionary)
var effects: EffectRegistry = null         # 域级副作用注册表（_init 自足缺省；装配后换绑共享表）

func _init() -> void:
	register_objective_handler("battle", _objective_battle)
	register_objective_handler("give_item", _objective_give_item)
	# 自足缺省注册表：奖励发放为核心链路，禁依赖装配顺序（隔离测试/未装配场景奖励不丢）
	var def := EffectRegistry.new()
	_register_effects_into(def)
	effects = def

func register_objective_handler(type: String, handler: Callable) -> void:
	_objective_handlers[type] = handler

## QD-2 收编：换绑 GameManager 共享域表（与 DialogueEventExecutor 同一实例，
## executor.apply_inline 的 quest_accept/quest_complete 才能路由到本服务）。
## 重复 attach 同表时 register 返回 false（op 已在），无害。
func attach_effects(reg: EffectRegistry) -> void:
	_register_effects_into(reg)
	effects = reg

func _register_effects_into(reg: EffectRegistry) -> void:
	reg.register("exp", EffectRegistry.KIND_REWARD, _reward_exp)
	reg.register("silver", EffectRegistry.KIND_REWARD, _reward_silver)
	reg.register("items", EffectRegistry.KIND_REWARD, _reward_items)
	reg.register("abilities", EffectRegistry.KIND_REWARD, _reward_abilities)
	reg.register("quest_accept", EffectRegistry.KIND_PROGRESS, _effect_quest_accept)
	reg.register("quest_complete", EffectRegistry.KIND_PROGRESS, _effect_quest_complete)
	# P-Q1 死命令修复：quest_complete 直连 turn_in（旧 executor has_method("complete_quest")
	# 探测的对象方法不存在，端到端不可达=死命令，QD-R09 禁）。

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
## QD-R07 分相化：只入队（发奖触发的 add_item → 本回调 → 队列，与直接拾取同相消费）
func _on_inventory_added(item_id: String, _count: int) -> void:
	_enqueue_event({"type": "item", "item_id": item_id})

# ---- QD-R07 分相队列（12 图 Phase2 / P-Q2 回调重入链根治） ----
# P-Q2 链：_complete → auto_complete → turn_in → 奖励 add_item → inventory_item_added
# → _on_inventory_added → 遍历全部任务推进——事件回调内同步重入，无分相/入队。
# 拆相后：回调只入队；同帧稍后 call_deferred 统一冲刷；冲刷循环内新入队事件继续
# 按序消费（完成→发奖→再推进链不递归、不丢事件）。消费顺序冻结（12 图）：
# 先目标推进、后完成判定、最后奖励发放（即事件相 → 完成相 → 奖励相）。
var _event_queue: Array = []   # 待消费事件（内部队列载荷，非信号；GATE21 不涉）
var _flushing := false         # 冲刷闸门：正在冲刷中（嵌套调用弹回，事件留给外层循环）
var _deferred_pending := false # deferred 已挂接（防重复挂；与 _flushing 语义分离——
                               # 回归实录 2026-09-06：共用一标志时挂接期同步冲刷被误弹回）

func _enqueue_event(ev: Dictionary) -> void:
	_event_queue.append(ev)
	if not _flushing and not _deferred_pending:
		_deferred_pending = true
		_flush_events.call_deferred()

## 帧末冲刷：清空事件队列（同步可调，测试据此获得确定性）
func _flush_events() -> void:
	_deferred_pending = false
	if _flushing:
		return   # 重入防护：嵌套冲刷直接返回，事件由外层循环继续消费
	_flushing = true
	while not _event_queue.is_empty():
		var ev: Dictionary = _event_queue.pop_front()
		match str(ev.get("type", "")):
			"battle":
				_advance_on_victory(str(ev.get("battle_id", "")))
			"item":
				_consume_item_event(str(ev.get("item_id", "")))
	_flushing = false

func _consume_item_event(item_id: String) -> void:
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
## P0 修复（满包不丢奖励）：发奖前先预检物品奖励能否全部装入；装不下则保持 COMPLETED
## 状态与任务在册，什么都不发（奖励原子性：exp/silver/items 必须同批，避免补交时重发一部分），
## 待背包腾出空间后由 retry_completed_turn_ins 自动补交。
func turn_in(quest_id: String) -> bool:
	if not active_quests.has(quest_id):
		return false
	var state: QuestState = active_quests[quest_id]
	if state.status != QuestEnums.QuestStatus.COMPLETED:
		return false
	var data: Dictionary = ConfigManager.get_quest(quest_id)
	var rewards: Dictionary = data.get("rewards", {})
	if rewards.has("items") and not _facts.can_add_items(rewards["items"]):
		push_warning("[Quest] 交付 %s 时背包空间不足，奖励暂缓发放（腾出空间后自动补交）" % quest_id)
		EventBus.notify_quest_track_changed.emit()
		return false
	state.status = QuestEnums.QuestStatus.TURNED_IN
	# P3 统一条件：then_set 完成回写（区域任务链驱动，如 nv_flag_maiden_helped /
	# plot_advance=to_misty_town）。键值全量写入 GameState 全局旗标，随存档持久化。
	var then_set: Dictionary = data.get("then_set", {})
	for k in then_set.keys():
		_facts.set_flag(String(k), then_set[k])
	# QD-2 奖励数据驱动分发：rewards 键 -> EffectRegistry（新奖励类型=注册，不改本函数）。
	# apply 返回 false = 死命令（注册缺失，QD-R09 FATAL）或注册表未注入，告警不断链
	# （奖励原子性由满包预检保证，单 key 缺失不中断其余奖励分发）。
	for key in rewards.keys():
		if effects != null and effects.apply(String(key), rewards[key], {"quest_id": quest_id, "channel": "quest_rewards"}):
			continue
		push_warning("[Quest] 未知奖励类型: %s（quest=%s）" % [key, quest_id])
	active_quests.erase(quest_id)
	completed_quests[quest_id] = state
	tracked_ids.erase(quest_id)
	EventBus.quest_turned_in.emit(quest_id)
	EventBus.notify_quest_track_changed.emit()
	return true

## 背包腾出空间后的自动补交：扫描仍处 COMPLETED 态的任务重试 turn_in。
## 由 GameManager 连接 EventBus.inventory_item_removed 触发（丢弃/卖出/消耗等任何移除都触发）。
## _retrying 防重入闸门：防未来行为变化引发移除事件连锁；keys() 为副本，turn_in 内 erase 安全。
func retry_completed_turn_ins(_item_id: String = "", _count: int = 0) -> void:
	if _retrying:
		return
	_retrying = true
	for qid in active_quests.keys():
		var st: QuestState = active_quests.get(qid)
		if st != null and st.status == QuestEnums.QuestStatus.COMPLETED:
			turn_in(qid)
	_retrying = false

# ---- 内置奖励处理器（QD-2 收编：统一签名 func(payload, ctx)，quest_id 经 ctx 传递；
# P5 去定位器：经 ServiceGameFacts 适配器，不再直取 GameManager）----
func _reward_exp(payload: Variant, _ctx: Dictionary) -> void:
	_facts.gain_exp(int(payload))

func _reward_silver(payload: Variant, _ctx: Dictionary) -> void:
	_facts.add_silver(int(payload))

func _reward_items(payload: Variant, ctx: Dictionary) -> void:
	var quest_id := String(ctx.get("quest_id", ""))
	for item_reward in payload:
		_facts.add_item(str(item_reward.get("item_id", "")), int(item_reward.get("count", 1)), "quest:%s" % quest_id)

func _reward_abilities(payload: Variant, _ctx: Dictionary) -> void:
	for ability_id in payload:
		_facts.learn_ability(str(ability_id))

# ---- 接/交任务效果（QD-2 收编 progress 类；DSL 尾段或字典 {quest_id} 双形态）----
func _effect_quest_accept(payload: Variant, _ctx: Dictionary) -> void:
	var quest_id := _quest_id_from_payload(payload)
	if quest_id == "":
		push_warning("[Quest] quest_accept 缺 quest_id: %s" % str(payload))
		return
	accept(quest_id)

## P-Q1 死命令修复（QD-R09 端到端可达）：直连 turn_in——仅对已 COMPLETED 任务生效
## （交付发奖）；未完成由 turn_in 内部拒绝（返回 false 不崩）。
func _effect_quest_complete(payload: Variant, _ctx: Dictionary) -> void:
	var quest_id := _quest_id_from_payload(payload)
	if quest_id == "":
		push_warning("[Quest] quest_complete 缺 quest_id: %s" % str(payload))
		return
	turn_in(quest_id)

func _quest_id_from_payload(payload: Variant) -> String:
	if payload is String:
		return String(payload).strip_edges()
	if payload is Dictionary:
		return String(payload.get("quest_id", ""))
	return ""

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
	_event_queue.clear()   # QD-R07：重置随队列清场（防跨局残留事件串推进）
	_flushing = false
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
	_event_queue.clear()   # QD-R07：读档清事件队列（防旧局残留事件串进新状态）
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
