# services/bond/bond_service.gd
# 结缘服务（模块18 · M1）：好感度等级 / 送礼反应 / 好感度事件
# 数据驱动：NPC 关系数据来自 ConfigManager.relations.json；不持有 Node（铁律）
# 跨模块只走 EventBus；送礼消耗走 InventoryService 公开 API，不碰其代码。
#
# 可扩展性：relations.json 已一次性铺齐 M2+ 字段（romanceable/swornable/masterable/
# 婚礼/师徒/好感事件），M1 只消费 好感度 / 送礼 / 好感度事件 三块；
# 婚礼/结义/师徒的公开 API 留待 M2 一次性补齐，不引入半吊子方法污染契约。

extends ISaveable
class_name BondService

# === 运行时状态（全部进存档） ===
var affections: Dictionary = {}          # npc_id -> 好感度(int, 0-100)
var affection_levels: Dictionary = {}    # npc_id -> 好感度等级(AffectionLevel)
var gift_count: Dictionary = {}          # npc_id -> 累计送礼次数（用于衰减）
var fired_events: Dictionary = {}        # npc_id -> Array[String]（一次性好感度事件已触发集合）
var interaction_log: Array = []          # 互动日志（Array of Dictionary，封顶 100 条）

# 注：结义/师徒关系状态已下沉至专用服务 SwornService / MasterService（唯一真源），
# 本服务仅管好感度，不再持有关系字典，避免「双写不同步 + 脏档」（BUG-03）

func _init() -> void:
	# 不在此访问 ConfigManager（autoload 就绪顺序无关），方法调用时再取
	pass

## ===== 好感度等级映射（数值 -> 等级） =====
func _level_of(value: int) -> int:
	if value >= 100: return BondEnums.AffectionLevel.DEVOTED
	elif value >= 80: return BondEnums.AffectionLevel.LOVED
	elif value >= 60: return BondEnums.AffectionLevel.CLOSE
	elif value >= 40: return BondEnums.AffectionLevel.FRIENDLY
	elif value >= 20: return BondEnums.AffectionLevel.ACQUAINTANCE
	else: return BondEnums.AffectionLevel.STRANGER

## ===== 好感度查询 =====
func get_affection(npc_id: String) -> int:
	return int(affections.get(npc_id, 0))

func get_affection_level(npc_id: String) -> int:
	return int(affection_levels.get(npc_id, BondEnums.AffectionLevel.STRANGER))

func get_affection_level_name(npc_id: String) -> String:
	return BondEnums.affection_level_name(get_affection_level(npc_id))

## 增加好感度（外部统一入口；内部 event 检查开启）
func add_affection(npc_id: String, amount: int, source: String = "") -> void:
	_apply_affection(npc_id, amount, source, true)

## 设置好感度（GM/任务奖励等直接赋值用）
func set_affection(npc_id: String, value: int) -> void:
	var clamped: int = clampi(value, 0, 100)
	affections[npc_id] = clamped
	var new_level: int = _level_of(clamped)
	affection_levels[npc_id] = new_level
	EventBus.bond_affection_changed.emit(npc_id, clamped, 0)

## 内部：好感度结算（emit_events=false 时跳过事件重入，避免奖励好感递归触发）
func _apply_affection(npc_id: String, amount: int, source: String, emit_events: bool) -> void:
	var current: int = int(affections.get(npc_id, 0))
	var old_level: int = _level_of(current)
	var new_value: int = clampi(current + amount, 0, 100)
	affections[npc_id] = new_value
	var new_level: int = _level_of(new_value)
	affection_levels[npc_id] = new_level
	if amount != 0:
		_add_log(npc_id, BondEnums.BondActionType.INTERACT, source, amount)
	EventBus.bond_affection_changed.emit(npc_id, new_value, amount)
	if emit_events and new_value != current:
		if new_level > old_level:
			EventBus.bond_affection_level_up.emit(npc_id, new_level)
		_check_affection_events(npc_id, new_value)

## ===== 好感度事件触发（等级/数值跨阈值时） =====
## 规则：new_value >= 事件 threshold 即触发；is_one_time 事件只触发一次（fired_events 去重）。
## 触发可发奖励物品（InventoryService.add_item）与奖励好感（_apply_affection 关闭事件避免递归）。
func _check_affection_events(npc_id: String, new_value: int) -> void:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return
	var events: Array = npc.get("affection_events", [])
	var fired: Array = fired_events.get(npc_id, [])
	for ev in events:
		var ev_id: String = str(ev.get("event_id", ""))
		if ev_id == "":
			continue
		var threshold: int = int(ev.get("threshold", 0))
		if new_value < threshold:
			continue
		var is_one_time: bool = bool(ev.get("is_one_time", true))
		if is_one_time and fired.has(ev_id):
			continue
		if is_one_time:
			fired.append(ev_id)
		var reward_item: String = str(ev.get("reward_item", ""))
		if reward_item != "" and ConfigManager.has_item(reward_item):
			GameManager.inventory_service.add_item(reward_item, 1, "bond_event:%s" % ev_id)
		var reward_aff: int = int(ev.get("reward_affection", 0))
		if reward_aff != 0:
			_apply_affection(npc_id, reward_aff, "event:%s" % ev_id, false)
		EventBus.bond_affection_event_triggered.emit(npc_id, ev_id)
	fired_events[npc_id] = fired

## ===== 送礼 =====
## 纯计算反应（不消耗物品），供 UI 预览与测试
func get_gift_reaction(npc_id: String, item_id: String) -> int:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return BondEnums.GiftReaction.NEUTRAL
	if npc.get("loved_gifts", []).has(item_id):
		return BondEnums.GiftReaction.LOVED
	if npc.get("liked_gifts", []).has(item_id):
		return BondEnums.GiftReaction.LIKED
	if npc.get("disliked_gifts", []).has(item_id):
		return BondEnums.GiftReaction.DISLIKED
	return BondEnums.GiftReaction.NEUTRAL

## 送礼：消耗背包实例（按 iid），按 NPC 喜恶结算好感度，广播事件
## 返回 { "ok": bool, "reason": String, "reaction": int, "affection_gain": int }
func give_gift(npc_id: String, item_instance_id: String) -> Dictionary:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return {"ok": false, "reason": "NO_NPC", "reaction": -1, "affection_gain": 0}
	var inst: ItemInstance = GameManager.inventory_service.get_instance_by_id(item_instance_id)
	if inst == null:
		return {"ok": false, "reason": "NO_ITEM", "reaction": -1, "affection_gain": 0}
	if inst.locked:
		return {"ok": false, "reason": "ITEM_LOCKED", "reaction": -1, "affection_gain": 0}
	var item_id: String = inst.item_id
	var reaction: int = get_gift_reaction(npc_id, item_id)
	var gain: int = 3
	match reaction:
		BondEnums.GiftReaction.LOVED: gain = 20
		BondEnums.GiftReaction.LIKED: gain = 12
		BondEnums.GiftReaction.DISLIKED: gain = -5
		_: gain = 3
	var gc: int = int(gift_count.get(npc_id, 0))
	if gc > 5:
		gain = int(gain * 0.5)   # 送礼次数衰减：超过 5 次收益减半
	# consume_instance 按实例扣 1（与用药同源），整堆移除的 remove_instance 不适用于送礼
	if not GameManager.inventory_service.consume_instance(item_instance_id):
		return {"ok": false, "reason": "REMOVE_FAILED", "reaction": reaction, "affection_gain": 0}
	gift_count[npc_id] = gc + 1
	add_affection(npc_id, gain, "gift:%s" % item_id)
	if reaction == BondEnums.GiftReaction.DISLIKED:
		EventBus.bond_gift_disliked.emit(npc_id, item_id)
	EventBus.bond_gift_given.emit(npc_id, item_id, gain, reaction)
	return {"ok": true, "reason": "SUCCESS", "reaction": reaction, "affection_gain": gain}

## ===== 查询 =====
## 配置层该 NPC 的所有好感度事件（供 UI 展示进度）
func get_affection_events(npc_id: String) -> Array:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return []
	return npc.get("affection_events", [])

## 已触发的一次性事件 id 列表（unlocks 消费端用）
func get_unlocked_dialogues(npc_id: String) -> Array:
	return fired_events.get(npc_id, [])

## 关系状态快照（UI 面板用）
func get_relation_status(npc_id: String) -> Dictionary:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	return {
		"npc_id": npc_id,
		"affection": int(affections.get(npc_id, 0)),
		"level": int(affection_levels.get(npc_id, BondEnums.AffectionLevel.STRANGER)),
		"level_name": get_affection_level_name(npc_id),
		"gift_count": int(gift_count.get(npc_id, 0)),
		"is_romanceable": npc.get("is_romanceable", false),
		"is_swornable": npc.get("is_swornable", false),
		"is_masterable": npc.get("is_masterable", false),
	}

## 互动日志（最近 limit 条）
func get_interaction_log(limit: int = 50) -> Array:
	var out: Array = []
	var start: int = maxi(0, interaction_log.size() - limit)
	for i in range(start, interaction_log.size()):
		out.append(interaction_log[i])
	return out

## 结缘统计（成就/称号用）
func get_bond_stats() -> Dictionary:
	return {
		"tracked": affections.size(),
		"total_gifts": _sum_values(gift_count),
		"log_size": interaction_log.size(),
	}

## ===== 互动日志 =====
func _add_log(npc_id: String, action: int, detail: String, aff: int) -> void:
	interaction_log.append({
		"npc": npc_id,
		"t": int(Time.get_unix_time_from_system()),
		"act": action,
		"det": detail,
		"aff": aff,
	})
	while interaction_log.size() > 100:
		interaction_log.pop_front()

func _sum_values(d: Dictionary) -> int:
	var s: int = 0
	for k in d.keys():
		s += int(d[k])
	return s

## ===== 结义 / 师徒 / 婚礼（M3 公开 API，数据驱动；只增不改 M1/M2） =====
## 结义阈值（relations.json 可配 sworn_affection，缺省 60）
func _sworn_affection_req(npc_id: String) -> int:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	return int(npc.get("sworn_affection", 60))

## 师徒：玩家拜 NPC 为师
## 婚礼演出（M3）：配偶可举办婚礼，触发演出信号并返回婚礼场景路径
## 实际 CG/场景播放由 UI/演出层监听 bond_wedding_started 完成（场景缺失则仅提示）
func hold_wedding(npc_id: String) -> Dictionary:
	if not GameManager.romance_service.is_spouse(npc_id):
		return {"ok": false, "reason": "NOT_SPOUSE"}
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	var cfg: Dictionary = npc.get("romance", {})
	var wt_str: String = String(cfg.get("wedding_type", "NORMAL"))
	var wedding_type: int = BondEnums.WeddingType.NORMAL
	if wt_str == "SIMPLE":
		wedding_type = BondEnums.WeddingType.SIMPLE
	elif wt_str == "GRAND":
		wedding_type = BondEnums.WeddingType.GRAND
	var scene_path: String = String(npc.get("wedding_scene", ""))
	EventBus.bond_wedding_started.emit(npc_id, wedding_type, scene_path)
	EventBus.bond_relationship_changed.emit()
	return {"ok": true, "reason": "SUCCESS", "wedding_type": wedding_type, "scene_path": scene_path}

## ===== 重置 / 存档 =====
func reset() -> void:
	affections.clear()
	affection_levels.clear()
	gift_count.clear()
	fired_events.clear()
	interaction_log.clear()
	_init_affection_from_config()

## 从 relations.json 播种初始好感（initial_affection>0 的 NPC 开局即满/初始好感）
## 新游戏/测试 reset 后自动生效，保证"满好感可结缘"NPC 开箱即测。
func _init_affection_from_config() -> void:
	for npc_id in ConfigManager.get_all_relation_ids():
		var npc: Dictionary = ConfigManager.get_relation(npc_id)
		if npc.is_empty():
			continue
		var initial: int = int(npc.get("initial_affection", 0))
		if initial > 0:
			set_affection(npc_id, initial)

func get_save_key() -> String:
	return "bond"

func save() -> Dictionary:
	# 必须深拷贝内部容器：返回的是引用，若随后 reset() 调 .clear() 会连带清空快照，导致 load 还原为空
	return {
		"affections": affections.duplicate(true),
		"levels": affection_levels.duplicate(true),
		"gift_count": gift_count.duplicate(true),
		"fired": fired_events.duplicate(true),
		"log": interaction_log.duplicate(true),
	}

func load(data: Dictionary) -> void:
	affections = data.get("affections", {})
	affection_levels = data.get("levels", {})
	gift_count = data.get("gift_count", {})
	fired_events = data.get("fired", {})
	interaction_log.clear()
	for e in data.get("log", []):
		if e is Dictionary:
			interaction_log.append(e)
	while interaction_log.size() > 100:
		interaction_log.pop_front()
