# services/inventory/inventory_service.gd
# 背包业务服务（规范 §2）：主背包/材料箱/任务栏三栏，自动归类、堆叠、负重
# 数据驱动：静态数据来自 ConfigManager；通过 EventBus 通知变化；不持有 Node（铁律）

extends ISaveable
class_name InventoryService

const MAX_MAIN_SLOTS := ItemConstants.DEFAULT_MAX_SLOTS
const MAX_MATERIAL_SLOTS := 200
const MAX_QUEST_SLOTS := 50
const BASE_MAX_WEIGHT := ItemConstants.BASE_MAX_WEIGHT

var main_slots: Array = []
var material_slots: Array = []
var quest_slots: Array = []
var current_weight: float = 0.0
var _dirty: bool = false
var _next_iid: int = 1   # 实例 ID 发号器：全局自增，随存档恢复，杜绝同毫秒撞车
var _count_index: Dictionary = {}   # item_id -> 总数量（含锁定）缓存索引；P2-7 优化 get_item_count 全扫

func _init() -> void:
	main_slots.resize(MAX_MAIN_SLOTS)
	material_slots.resize(MAX_MATERIAL_SLOTS)
	quest_slots.resize(MAX_QUEST_SLOTS)

## 添加物品：按类型自动归入对应栏位（材料->材料箱，任务物品->任务栏，其余->主背包）
func add_item(item_id: String, count: int, source: String = "") -> bool:
	if count <= 0:
		return false
	if not ConfigManager.has_item(item_id):
		push_error("[Inventory] 物品不存在: %s" % item_id)
		return false
	var bag: Array = _bag_for_item(item_id)
	var max_stack: int = ConfigManager.get_item(item_id).get("max_stack", 1)
	var added: int = 0
	if max_stack > 1:
		added += _stack_to_existing(bag, item_id, count)
		count -= added
	while count > 0:
		var idx: int = _find_empty(bag)
		if idx == -1:
			break
		var unit_w: float = ConfigManager.get_item(item_id).get("weight", 0.0)
		# 本件重量为正时，按"剩余重量还能容几件"限制单次放入量，避免整批被超重拒绝。
		# current_weight 在循环内增量更新（下方 +=），保证 weight_fit 基于实时负重，不会多放。
		var weight_fit: int = 2147483647
		if unit_w > 0.0:
			weight_fit = maxi(0, int((get_max_weight() - current_weight) / unit_w))
		if weight_fit <= 0:
			break   # 已达负重上限，停止放入，剩余走溢出事件
		var put: int = mini(mini(max_stack, count), weight_fit)
		var inst := ItemInstance.new()
		inst.instance_id = _new_instance_id(item_id)
		inst.item_id = item_id
		inst.count = put
		inst.acquired_source = source
		inst.acquired_time = int(Time.get_unix_time_from_system())
		bag[idx] = inst
		count -= inst.count
		current_weight += unit_w * float(put)
		added += inst.count
	# 重量重算与计数索引只在末尾统一维护一次（P2-5 修复：原实现每新建一格都全栏重算 280 格并多发 weight-changed 事件）
	if added > 0:
		_bump_count(item_id, added)
		_dirty = true
		EventBus.inventory_weight_changed.emit(current_weight, get_max_weight())
	if added > 0:
		EventBus.inventory_item_added.emit(item_id, added)
	if count > 0:
		# 溢出通知：走 can_add 预检的调用方不会到这里；掉落/发奖等未预检方据此提示玩家
		EventBus.inventory_add_overflow.emit(item_id, count)
	return count <= 0

## 批量事务添加：items 为 [{ "item_id": String, "count": int }, ...]
## 先聚合预检（每个 item_id 的全部数量都能装入）才逐个 add_item；任一装不下则整体返回 false、一个不加
## 适用：一次发多奖励 / 批量合成产物 / 多掉落统一入库，避免部分添加造成的中间态与重复扣料
func add_items(items: Array, source: String = "") -> bool:
	if items.is_empty():
		return false
	var need_by_id: Dictionary = {}
	for entry in items:
		var item_id: String = String(entry.get("item_id", ""))
		var need: int = int(entry.get("count", 1))
		if item_id == "" or need <= 0:
			return false
		if not ConfigManager.has_item(item_id):
			return false
		need_by_id[item_id] = int(need_by_id.get(item_id, 0)) + need
	# 事务预检：全部能装下才放行（add_item 是新增实例，不受锁定影响，故用 can_add 即可）
	for item_id in need_by_id:
		if not can_add(item_id, int(need_by_id[item_id])):
			return false
	for entry in items:
		add_item(String(entry.get("item_id", "")), int(entry.get("count", 1)), source)
	return true

## 原样归还实例（P1-4 修复）：把已存在的 ItemInstance 重新入包，完整保留 instance_id / 耐久 / 来源 / 锁定，
## 不 mint 新 iid、不重置身份。装备系统卸下时应调此而非 add_item(item_id,1)（后者会生成新实例、丢失耐久与 iid）。
## 可堆叠物尽量并入同物实例（保留既有实例身份）；不可堆叠/无同物实例则放入空槽；满包返回 false。
func add_instance(inst: ItemInstance) -> bool:
	if inst == null or inst.item_id == "":
		return false
	var bag: Array = _bag_for_item(inst.item_id)
	var max_stack: int = ConfigManager.get_item(inst.item_id).get("max_stack", 1)
	if max_stack > 1:
		var remaining: int = inst.count
		for e in bag:
			if remaining <= 0:
				break
			if e != null and e.item_id == inst.item_id and e.count < max_stack:
				var put := mini(max_stack - e.count, remaining)
				e.count += put
				remaining -= put
		if remaining <= 0:
			_recalculate_weight()
			_bump_count(inst.item_id, inst.count)
			_dirty = true
			EventBus.inventory_item_added.emit(inst.item_id, inst.count)
			return true
		inst.count = remaining   # 剩余部分另开新槽（保留原实例身份）
	var idx: int = _find_empty(bag)
	if idx == -1:
		return false
	bag[idx] = inst
	_recalculate_weight()
	_bump_count(inst.item_id, inst.count)
	_dirty = true
	EventBus.inventory_item_added.emit(inst.item_id, inst.count)
	return true

## 实例 ID 发号器：全局自增序号，随存档 save/load 恢复，保证永不重复
func _new_instance_id(item_id: String) -> String:
	var id := "%s#%d" % [item_id, _next_iid]
	_next_iid += 1
	return id

## 纯计算预检：count 个 item_id 能装入对应栏位多少个（不改任何状态，不发光）
## 返回 { "added": int, "overflow": int }；shop/forge/alchemy 产出前必调
func query_add(item_id: String, count: int) -> Dictionary:
	var result := { "added": 0, "overflow": 0 }
	if count <= 0:
		return result
	if not ConfigManager.has_item(item_id):
		result["overflow"] = count
		return result
	var bag: Array = _bag_for_item(item_id)
	var max_stack: int = int(ConfigManager.get_item(item_id).get("max_stack", 1))
	var unit_w: float = ConfigManager.get_item(item_id).get("weight", 0.0)
	# 槽位余量
	var space: int = 0
	for inst in bag:
		if inst != null and max_stack > 1 and inst.item_id == item_id:
			space += max_stack - int(inst.count)
	for slot in bag:
		if slot == null:
			space += max_stack
	# 重量余量：每单位重量为正时受负重上限约束；无重量物品不受限
	var room: int = space
	if unit_w > 0.0:
		# 不抢先 maxi(0,...) 归零：已超重(current_weight>max_weight，如力量被 debuff 压低)时
		# weight_room 为负，再经下方 maxi(0, mini(...)) 夹紧为 0 —— 语义明确：超重时不可再加正重量物品
		# （需先丢物），且避免负 room 透传导致 added 为负、overflow 越界的边界陷阱（P2-8 修复）
		var weight_room: int = int((get_max_weight() - current_weight) / unit_w)
		room = mini(space, weight_room)
	var added: int = maxi(0, mini(count, room))
	result["added"] = added
	result["overflow"] = count - added
	return result

## 是否装得下 count 个（事务两段式的预检依据）
func can_add(item_id: String, count: int) -> bool:
	var q: Dictionary = query_add(item_id, count)
	return int(q["added"]) >= count

## 主动丢弃物品：玩家手动丢掉垃圾/杂物（区别于被动移除）
## 校验 DISCARDABLE flag（不可丢弃物如任务关键物会被拒）；锁定实例不可丢（提示先解锁）
## 返回 { "ok": bool, "reason": String, "item_id": String, "dropped": int }
func drop_item(iid: String, count: int = 1) -> Dictionary:
	var inst: ItemInstance = get_instance_by_id(iid)
	if inst == null:
		return { "ok": false, "reason": "NOT_FOUND", "item_id": "" }
	var item_id: String = inst.item_id
	var data: Dictionary = ConfigManager.get_item(item_id)
	var flags: int = int(data.get("flags", 0))
	if not ItemFlags.is_discardable(flags):
		return { "ok": false, "reason": "NOT_DISCARDABLE", "item_id": item_id }
	if inst.locked:
		return { "ok": false, "reason": "LOCKED", "item_id": item_id }
	if count <= 0:
		return { "ok": false, "reason": "BAD_COUNT", "item_id": item_id }
	var take: int = mini(count, inst.count)
	inst.count -= take
	if inst.count <= 0:
		for bag in [main_slots, material_slots, quest_slots]:
			var idx: int = bag.find(inst)
			if idx != -1:
				bag[idx] = null
				break
	_recalculate_weight()
	_bump_count(item_id, -take)
	_dirty = true
	EventBus.inventory_item_removed.emit(item_id, take)
	return { "ok": true, "reason": "SUCCESS", "item_id": item_id, "dropped": take }

## 原子扣料（事务语义）：items 为 [{ "item_id": String, "count": int }, ...]
## 先全量校验、再统一扣除；任一不足则整体不扣返回 false。锻造/炼药/批量消耗一律走此接口
func try_consume(items: Array, source: String = "") -> bool:
	if items.is_empty():
		return false
	# 聚合同 item_id 需求：避免同一物品在 items 里出现多条时，逐项校验各算各的、
	# 漏算总量，导致第二处 remove_item_by_id 库存不足却仍返回 true（少扣/误判成功）
	var need_by_id: Dictionary = {}
	for entry in items:
		var item_id: String = String(entry.get("item_id", ""))
		var need: int = int(entry.get("count", 1))
		if item_id == "":
			return false
		if need <= 0:
			return false
		need_by_id[item_id] = int(need_by_id.get(item_id, 0)) + need
	# 锁定实例不可被动消耗：用「非锁定可用量」校验，锁定物被排除在批量扣料外（原子：任一不足整体失败）
	for item_id in need_by_id:
		if get_unlocked_count(item_id) < int(need_by_id[item_id]):
			return false
	# 统一扣除（已按聚合量校验，remove_item_by_id 跳过锁定实例与校验一致）
	for item_id in need_by_id:
		remove_item_by_id(item_id, int(need_by_id[item_id]))
	return true

func _stack_to_existing(bag: Array, item_id: String, count: int) -> int:
	var max_stack: int = ConfigManager.get_item(item_id).get("max_stack", 1)
	var unit_w: float = ConfigManager.get_item(item_id).get("weight", 0.0)
	var remaining := count
	for inst in bag:
		if remaining <= 0:
			break
		if inst != null and inst.item_id == item_id and inst.count < max_stack:
			var put := mini(max_stack - inst.count, remaining)
			inst.count += put
			current_weight += unit_w * float(put)   # 增量同步负重（P2-5：移除循环内全栏重算后，堆叠路径也必须自更新）
			remaining -= put
	return count - remaining

func _find_empty(bag: Array) -> int:
	for i in bag.size():
		if bag[i] == null:
			return i
	return -1

func _bag_for_item(item_id: String) -> Array:
	var t: String = ConfigManager.get_item(item_id).get("type", "")
	match t:
		"material":
			return material_slots
		"quest":
			return quest_slots
		_:
			return main_slots

func remove_item_by_id(item_id: String, count: int) -> bool:
	var remaining := count
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if remaining <= 0:
				break
			# 锁定实例受保护：被动移除（售卖/分解/丢弃）跳过，避免误丢关键物
			if inst != null and inst.item_id == item_id and not inst.locked:
				var take := mini(remaining, inst.count)
				inst.count -= take
				remaining -= take
				if inst.count <= 0:
					var idx: int = bag.find(inst)
					bag[idx] = null
	if remaining < count:
		_recalculate_weight()
		_bump_count(item_id, -(count - remaining))
		_dirty = true
		EventBus.inventory_item_removed.emit(item_id, count - remaining)
		return true
	return false

## 背包内某 item_id 的总数量（含锁定实例）；走缓存索引 O(1)（P2-7）
## 锁定不改变总数，故缓存存 total 即可；非锁定量见 get_unlocked_count（需遍历 per-instance locked）
func get_item_count(item_id: String) -> int:
	return int(_count_index.get(item_id, 0))

## 增量维护 _count_index（add 传正、remove/consume/lose/remove_instance 传负）
func _bump_count(item_id: String, delta: int) -> void:
	var v: int = int(_count_index.get(item_id, 0)) + delta
	if v <= 0:
		_count_index.erase(item_id)
	else:
		_count_index[item_id] = v

## 从三栏重建数量索引（load/reset 后调用，确保缓存与实例一致）
func _rebuild_count_index() -> void:
	_count_index.clear()
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null:
				_bump_count(inst.item_id, inst.count)

## ===== 物品锁定（玩家保护关键物，防被动移除） =====
## 未锁定的可用数量（锁定实例不计入，供 try_consume 校验与 UI 提示）
func get_unlocked_count(item_id: String) -> int:
	var total := 0
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id and not inst.locked:
				total += inst.count
	return total

## 已锁定的数量（供 UI 展示「N 件已锁定」）
func get_locked_count(item_id: String) -> int:
	var total := 0
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id and inst.locked:
				total += inst.count
	return total

## 设置/查询单实例锁定状态（UI 锁图标操作调此；锁定后被动移除被拦截，主动吃药不受影响）
func set_item_locked(iid: String, locked: bool) -> bool:
	var inst: ItemInstance = get_instance_by_id(iid)
	if inst == null:
		return false
	inst.locked = locked
	_dirty = true
	return true

func is_item_locked(iid: String) -> bool:
	var inst: ItemInstance = get_instance_by_id(iid)
	if inst == null:
		return false
	return inst.locked

## ===== 容量查询 API（P2-3）=====
## 三栏总槽位 / 已用格 / 剩余格；供 shop/forge/UI 预检与 HUD 提示
func get_total_slots() -> int:
	return MAX_MAIN_SLOTS + MAX_MATERIAL_SLOTS + MAX_QUEST_SLOTS

func get_used_slots() -> int:
	var used := 0
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null:
				used += 1
	return used

func get_free_slots() -> int:
	return get_total_slots() - get_used_slots()

## 任一栏满（三栏任一无空位即视为满）；is_full() 保留主栏语义供旧调用方
func is_any_bag_full() -> bool:
	return _find_empty(main_slots) == -1 or _find_empty(material_slots) == -1 or _find_empty(quest_slots) == -1

func is_full() -> bool:
	return _find_empty(main_slots) == -1

## 指定栏位的剩余空槽数（分栏容量查询，UI/预检更精确）
## bag_type: "main" / "material" / "quest"；非法名返回 0
func get_free_capacity(bag_type: String) -> int:
	var bag: Array = _bag_by_name(bag_type)
	if bag.is_empty():
		return 0
	var free := 0
	for slot in bag:
		if slot == null:
			free += 1
	return free

## 负重比：current_weight / max_weight，0~1+（>1 即超重）。UI 进度条直接乘 100 即可
func get_weight_ratio() -> float:
	var mw: float = get_max_weight()
	if mw <= 0.0:
		return 0.0
	return current_weight / mw

## 按实例 ID 查找物品实例（装备系统装卸用）
func get_instance_by_id(iid: String) -> ItemInstance:
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null and inst.instance_id == iid:
				return inst
	return null

## 按实例 ID 从背包移除（装备时把物品抽离到装备槽，不再占背包格）
func remove_instance(iid: String) -> bool:
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null and inst.instance_id == iid:
				_bump_count(inst.item_id, -inst.count)
				var idx: int = bag.find(inst)
				bag[idx] = null
				_recalculate_weight()
				_dirty = true
				return true
	return false

## 使用消耗品：pill 类型或 flags 含 CONSUMABLE 的物品，按配置 heal_hp/heal_mp 生效
## context: "town" / "battle"（当前结算一致，预留战斗限制扩展位）
## 返回 { "ok": bool, "reason": String, "item_id": String, "effect": {hp, mp} }
## 使用消耗品：按配置 kind 分发到具体效果（heal/buff/cure/exp）
## 当前物品库仅有 heal 类（heal_hp/heal_mp）；buff/cure/exp 为预留扩展位，未配置数据时安全返回 NO_EFFECT 且不消耗
func use_item(instance_id: String, context: String = "town") -> Dictionary:
	var inst: ItemInstance = get_instance_by_id(instance_id)
	if inst == null:
		return { "ok": false, "reason": "NOT_FOUND", "item_id": "" }
	var item_id: String = inst.item_id
	var data: Dictionary = ConfigManager.get_item(item_id)
	if data.is_empty():
		return { "ok": false, "reason": "UNKNOWN_ITEM", "item_id": item_id }
	var flags: int = int(data.get("flags", 0))
	var is_consumable: bool = data.get("type", "") == "pill" \
			or (flags & ItemEnums.ItemFlag.CONSUMABLE) != 0
	if not is_consumable:
		return { "ok": false, "reason": "NOT_CONSUMABLE", "item_id": item_id }
	var ps: PlayerState = GameManager.player_state
	if ps == null:
		return { "ok": false, "reason": "NO_PLAYER", "item_id": item_id }
	var kind: String = data.get("kind", "heal")
	match kind:
		"heal":
			return _apply_use_heal(inst, data, context)
		"buff":
			return _apply_use_buff(inst, data, context)
		"cure":
			return _apply_use_cure(inst, data, context)
		"exp":
			return _apply_use_exp(inst, data, context)
		_:
			return { "ok": false, "reason": "UNKNOWN_KIND", "item_id": item_id, "kind": kind }

## 治疗类：按 heal_hp/heal_mp 生效（原 use_item 逻辑；无效果数值返回 NO_EFFECT 不消耗）
func _apply_use_heal(inst: ItemInstance, data: Dictionary, context: String) -> Dictionary:
	var item_id: String = inst.item_id
	var heal_hp: int = int(data.get("heal_hp", 0))
	var heal_mp: int = int(data.get("heal_mp", 0))
	if heal_hp <= 0 and heal_mp <= 0:
		return { "ok": false, "reason": "NO_EFFECT", "item_id": item_id }
	var effect := { "hp": heal_hp, "mp": heal_mp }
	if context == "battle":
		# 战斗用药：不直接改 PlayerState（避免背包耦合战斗状态/护盾/溢出/HUD），
		# 派发战斗用药请求，由战斗场景经战斗状态结算（P1-3 修复：原 context 仅用于日志，town/battle 同一直改）
		consume_instance(inst.instance_id)
		EventBus.item_used_in_battle.emit(item_id, effect)
		GameLogger.info("Inventory", "战斗用药 %s 已派发战斗结算(不直接改PlayerState) hp+%d mp+%d" % [item_id, heal_hp, heal_mp])
		return { "ok": true, "reason": "BATTLE_PENDING", "item_id": item_id, "effect": effect }
	consume_instance(inst.instance_id)
	var ps: PlayerState = GameManager.player_state
	var healed: int = 0
	var restored: int = 0
	if heal_hp > 0:
		healed = ps.heal(heal_hp)
	if heal_mp > 0:
		restored = ps.restore_mp(heal_mp)
	var applied := { "hp": healed, "mp": restored }
	EventBus.item_used.emit(item_id, applied)
	GameLogger.info("Inventory", "使用 %s (town) hp+%d mp+%d" % [item_id, healed, restored])
	return { "ok": true, "reason": "SUCCESS", "item_id": item_id, "effect": applied }

## 增益类（预留）：读取 data.buff_stat/buff_value 应用至 PlayerState。当前库未配置，安全返回 NO_EFFECT 不消耗
func _apply_use_buff(inst: ItemInstance, data: Dictionary, context: String) -> Dictionary:
	var item_id: String = inst.item_id
	# TODO(Phase 扩展): buff_stat/buff_value 应用至 PlayerState（如临时攻击/防御加成）
	return { "ok": false, "reason": "NO_EFFECT", "item_id": item_id }

## 治疗异常状态类（预留）：读取 data.cure_status 清除状态。当前库未配置，安全返回 NO_EFFECT 不消耗
func _apply_use_cure(inst: ItemInstance, data: Dictionary, context: String) -> Dictionary:
	var item_id: String = inst.item_id
	# TODO(Phase 扩展): cure_status 清除 PlayerState 上的异常状态（中毒/眩晕等）
	return { "ok": false, "reason": "NO_EFFECT", "item_id": item_id }

## 经验类：读取 data.gain_exp 直接结算经验。当前库未配置，安全返回 NO_EFFECT 不消耗
func _apply_use_exp(inst: ItemInstance, data: Dictionary, context: String) -> Dictionary:
	var item_id: String = inst.item_id
	var gain: int = int(data.get("gain_exp", 0))
	if gain <= 0:
		return { "ok": false, "reason": "NO_EFFECT", "item_id": item_id }
	var effect := { "exp": gain }
	if context == "battle":
		consume_instance(inst.instance_id)
		EventBus.item_used_in_battle.emit(item_id, effect)
		GameLogger.info("Inventory", "战斗用药 %s(经验) 已派发战斗结算" % item_id)
		return { "ok": true, "reason": "BATTLE_PENDING", "item_id": item_id, "effect": effect }
	consume_instance(inst.instance_id)
	var ps: PlayerState = GameManager.player_state
	if ps != null and ps.has_method("gain_exp"):
		ps.gain_exp(gain)
	EventBus.item_used.emit(item_id, effect)
	GameLogger.info("Inventory", "使用 %s (town) 经验+%d" % [item_id, gain])
	return { "ok": true, "reason": "SUCCESS", "item_id": item_id, "effect": effect }

## 公共扣件：扣除指定实例 1 个数量；耗尽则回收格子。城镇用药/战斗用药共用
## 返回 false 表示实例不存在
func consume_instance(iid: String) -> bool:
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null and inst.instance_id == iid:
				inst.count -= 1
				if inst.count <= 0:
					var idx: int = bag.find(inst)
					bag[idx] = null
				_recalculate_weight()
				_bump_count(inst.item_id, -1)
				_dirty = true
				EventBus.inventory_item_removed.emit(inst.item_id, 1)
				return true
	return false

## 返回背包主栏中所有可装备的物品实例（配置带 equip_slot 的）
## 注意：返回 Array 而非 Array[ItemInstance]。main_slots 是普通 Array，
## 迭代元素在编译期是 Variant，硬标 ItemInstance 会触发类型不匹配。
## UI 处用 var inst: ItemInstance = items[i] 取即可。
func get_equippable_instances() -> Array:
	var out: Array = []
	for inst in main_slots:
		if inst == null:
			continue
		var data: Dictionary = ConfigManager.get_item(inst.item_id)
		if not data.is_empty() and data.get("equip_slot", "") != "":
			out.append(inst)
	return out

func get_weight() -> float:
	return current_weight

## 负重上限（真负重）：基础值 + 力量 × 系数
## UI 窗口显示负重进度条必须调此接口，禁止再用 BASE_MAX_WEIGHT 常量（否则力量成长不反映）
func get_max_weight() -> float:
	var str_val: int = 10
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		str_val = ps.strength
	return BASE_MAX_WEIGHT + float(str_val) * ItemConstants.STRENGTH_WEIGHT_COEFF

## 团灭惩罚：丢失 n 件「符合难度表 defeat_lose_rarities 档位」的物品，返回丢失的 item_id 列表
## 规则已全部配置化（数值进 JSON，去除硬编码 rarity=="common"）：
##   - 可丢稀有度档位：DifficultyManager.get_defeat_lose_rarities()（默认 ["common"]，空数组=全部保护）
##   - 槽位范围：主栏恒含；材料栏/任务栏由 get_defeat_lose_include_material()/include_quest() 决定（默认均不含）
## 设计：只丢杂物，保护进度物；同一类丢多件也只记一次 id 供抵押物清单去重
## 注意：用带索引的 while 遍历（而非 for-in），确保堆叠物品（count>1）能在本轮被彻底扣空，
##       不会因 for-in 每实例只访问一次而少丢（例如 2 个丹药应丢 2 件而非 1 件）
func lose_some_non_rare_items(n: int) -> Array:
	var lost_ids: Array = []            # 返回：丢失的 item_id 列表（可含重复，便于表现层逐件呈现）
	var lost_counts: Dictionary = {}    # item_id -> 数量（用于发事件）
	if n <= 0:
		return lost_ids
	# 规则配置化：可丢稀有度 + 槽位范围全部读难度表（数值进 JSON）
	var rarities: Array = DifficultyManager.get_defeat_lose_rarities()
	var bags: Array = [main_slots]
	if DifficultyManager.get_defeat_lose_include_material():
		bags.append(material_slots)
	if DifficultyManager.get_defeat_lose_include_quest():
		bags.append(quest_slots)
	var remaining := n
	var bag_idx: int = 0
	while remaining > 0 and bag_idx < bags.size():
		var bag: Array = bags[bag_idx]
		bag_idx += 1
		var i: int = 0
		while remaining > 0 and i < bag.size():
			var inst = bag[i]
			i += 1
			if inst == null:
				continue
			if inst.locked:
				continue   # 锁定关键物团灭不丢
			var data: Dictionary = ConfigManager.get_item(inst.item_id)
			if not rarities.has(data.get("rarity", "")):
				continue
			# 从该实例尽量扣，直到满足需求或实例耗尽
			while remaining > 0 and inst.count > 0:
				inst.count -= 1
				remaining -= 1
				lost_ids.append(inst.item_id)
				lost_counts[inst.item_id] = int(lost_counts.get(inst.item_id, 0)) + 1
			if inst.count <= 0:
				bag[i - 1] = null
	if remaining < n:
		_recalculate_weight()
		_dirty = true
	for item_id in lost_counts:
		var c: int = lost_counts[item_id]
		_bump_count(item_id, -c)
		EventBus.inventory_item_removed.emit(item_id, c)
	return lost_ids

func _recalculate_weight() -> void:
	current_weight = 0.0
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null:
				current_weight += ConfigManager.get_item(inst.item_id).get("weight", 0.0) * inst.count
	EventBus.inventory_weight_changed.emit(current_weight, get_max_weight())

func reset() -> void:
	main_slots.clear(); main_slots.resize(MAX_MAIN_SLOTS)
	material_slots.clear(); material_slots.resize(MAX_MATERIAL_SLOTS)
	quest_slots.clear(); quest_slots.resize(MAX_QUEST_SLOTS)
	current_weight = 0.0
	_next_iid = 1
	_count_index.clear()
	_dirty = false

func get_save_key() -> String:
	return "inventory"

func save() -> Dictionary:
	return {
		"main": _serialize_bag(main_slots),
		"material": _serialize_bag(material_slots),
		"quest": _serialize_bag(quest_slots),
		"weight": current_weight,
		"next_iid": _next_iid,
	}

## 序列化单栏：保真槽位顺序，存 {idx, data}（idx=原槽位下标）。
## 旧档为裸 ItemInstance 字典数组（无 idx），_deserialize_bag 会兼容回退。
func _serialize_bag(bag: Array) -> Array:
	var out: Array = []
	for i in range(bag.size()):
		var inst = bag[i]
		if inst != null:
			out.append({"idx": i, "data": inst.serialize()})
	return out

func load(data: Dictionary) -> void:
	main_slots.clear(); main_slots.resize(MAX_MAIN_SLOTS)
	material_slots.clear(); material_slots.resize(MAX_MATERIAL_SLOTS)
	quest_slots.clear(); quest_slots.resize(MAX_QUEST_SLOTS)
	_deserialize_bag(data.get("main", []), main_slots)
	_deserialize_bag(data.get("material", []), material_slots)
	_deserialize_bag(data.get("quest", []), quest_slots)
	current_weight = float(data.get("weight", 0.0))  # 显式 float() 避免 Variant→float 推断歧义
	_next_iid = maxi(int(data.get("next_iid", 1)), 1)
	# 旧档不信任存档负重：配置可能已改物品重量，按当前配置重算
	_recalculate_weight()
	_rebuild_count_index()
	_dirty = false

## 反序列化单栏：
## - 新格式 {idx, data}：按 idx 直接放入保真槽位顺序（支持 UI 窗口 P2-1 拖拽 move_instance 的持久化）；
##   idx 越界则兜底塞第一个空位，避免坏档崩存档。
## - 旧格式（裸 ItemInstance 字典、无 idx 键）：按 find(null) 顺序塞回，兼容已发布存档。
func _deserialize_bag(arr: Array, bag: Array) -> void:
	for entry in arr:
		var inst := ItemInstance.new()
		if entry is Dictionary and entry.has("idx") and entry.has("data"):
			inst.deserialize(entry.get("data", {}))
			var idx: int = int(entry.get("idx", -1))
			if idx >= 0 and idx < bag.size():
				bag[idx] = inst
			else:
				var f: int = bag.find(null)
				if f != -1:
					bag[f] = inst
		else:
			# 旧格式兼容
			inst.deserialize(entry)
			var idx: int = bag.find(null)
			if idx != -1:
				bag[idx] = inst

## === UI 窗口 P2-1 新增（纯追加，不改动既有方法；跨窗口协调见 UI 窗口《变更通告》）===

## 取栏位数组（按名字）
func _bag_by_name(name: String) -> Array:
	match name:
		"main": return main_slots
		"material": return material_slots
		"quest": return quest_slots
	return []

## 拆分实例：从 iid 拆出 count 个到新实例，原实例数量减少。
## 约束：可堆叠(max_stack>1)、0<count<inst.count、count<=max_stack、目标栏有空槽。
## 返回 { "ok": bool, "reason": String, "new_iid": String }
func split_instance(iid: String, count: int) -> Dictionary:
	var inst: ItemInstance = get_instance_by_id(iid)
	if inst == null:
		return { "ok": false, "reason": "NOT_FOUND", "new_iid": "" }
	if count <= 0 or count >= int(inst.count):
		return { "ok": false, "reason": "BAD_COUNT", "new_iid": "" }
	var data: Dictionary = ConfigManager.get_item(inst.item_id)
	if data.is_empty():
		return { "ok": false, "reason": "UNKNOWN_ITEM", "new_iid": "" }
	var max_stack: int = int(data.get("max_stack", 1))
	if max_stack <= 1:
		return { "ok": false, "reason": "NOT_STACKABLE", "new_iid": "" }
	if count > max_stack:
		return { "ok": false, "reason": "EXCEEDS_STACK", "new_iid": "" }
	var bag: Array = []
	for b in [main_slots, material_slots, quest_slots]:
		if b.has(inst):
			bag = b
			break
	if bag.is_empty():
		return { "ok": false, "reason": "NO_BAG", "new_iid": "" }
	var empty: int = _find_empty(bag)
	if empty == -1:
		return { "ok": false, "reason": "BAG_FULL", "new_iid": "" }
	var new_inst := ItemInstance.new()
	new_inst.instance_id = _new_instance_id(inst.item_id)
	new_inst.item_id = inst.item_id
	new_inst.count = count
	new_inst.acquired_source = inst.acquired_source
	new_inst.acquired_time = int(Time.get_unix_time_from_system())
	bag[empty] = new_inst
	inst.count -= count
	_recalculate_weight()
	_dirty = true
	return { "ok": true, "reason": "SUCCESS", "new_iid": new_inst.instance_id }

## 移动实例到目标栏位指定索引（拖拽排序/跨栏移动）。
## target_bag: "main"/"material"/"quest"；target_index 越界自动夹紧。
## 目标槽被占用则与源槽交换，保证实例总数不变。返回是否成功。
func move_instance(iid: String, target_bag: String, target_index: int) -> bool:
	var src_bag: Array = []
	var found: ItemInstance = null
	for b in [main_slots, material_slots, quest_slots]:
		for it in b:
			if it != null and it.instance_id == iid:
				src_bag = b
				found = it
				break
		if found != null:
			break
	if found == null:
		return false
	# 类型不变式：物品只能落在与其 type 对应的栏（weapon/pill/armor/accessory -> main，
	# material -> material，quest -> quest）。拒绝跨类型乱移，否则会破坏 add_item 路由不变量
	# （如装备系统只扫主栏、_bag_for_item 按 type 归类），并造成重量/查询错乱。
	if _bag_by_name(target_bag) != _bag_for_item(found.item_id):
		return false
	var src_idx: int = src_bag.find(found)
	var tgt: Array = _bag_by_name(target_bag)
	if tgt.is_empty():
		return false
	var clamped: int = clampi(target_index, 0, tgt.size() - 1)
	src_bag[src_idx] = null
	var displaced: ItemInstance = tgt[clamped]
	tgt[clamped] = found
	if displaced != null:
		src_bag[src_idx] = displaced
	_recalculate_weight()
	_dirty = true
	return true

## 整理栏位：按 名称→类型→稀有度 排序，非空实例排前、空槽靠后。仅改顺序。
func sort_bag(bag_name: String) -> void:
	var bag: Array = _bag_by_name(bag_name)
	if bag.is_empty():
		return
	var items: Array = []
	for inst in bag:
		if inst != null:
			items.append(inst)
	items.sort_custom(func(a, b):
		var da: Dictionary = ConfigManager.get_item(a.item_id)
		var db: Dictionary = ConfigManager.get_item(b.item_id)
		var na: String = da.get("name", a.item_id)
		var nb: String = db.get("name", b.item_id)
		if na != nb:
			return na < nb
		var ta: String = da.get("type", "")
		var tb: String = db.get("type", "")
		if ta != tb:
			return ta < tb
		return da.get("rarity", "") < db.get("rarity", "")
	)
	for i in range(bag.size()):
		bag[i] = items[i] if i < items.size() else null
	_dirty = true
