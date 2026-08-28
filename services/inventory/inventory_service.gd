# services/inventory/inventory_service.gd
# 背包业务服务（规范 §2）：主背包/材料箱/任务栏三栏，自动归类、堆叠、负重
# 数据驱动：静态数据来自 ConfigManager；通过 EventBus 通知变化；不持有 Node（铁律）

extends ISaveable
class_name InventoryService

@warning_ignore("unused_signal")
signal inventory_item_added(item_id: String, count: int)
@warning_ignore("unused_signal")
signal inventory_item_removed(item_id: String, count: int)
@warning_ignore("unused_signal")
signal inventory_weight_changed(current: float, max_weight: float)

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
		# 本件重量为正时，按"剩余重量还能容几件"限制单次放入量，避免整批被超重拒绝
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
	_recalculate_weight()
	_dirty = true
	if added > 0:
		inventory_item_added.emit(item_id, added)
		EventBus.inventory_item_added.emit(item_id, added)
	if count > 0:
		# 溢出通知：走 can_add 预检的调用方不会到这里；掉落/发奖等未预检方据此提示玩家
		EventBus.inventory_add_overflow.emit(item_id, count)
	return count <= 0

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
		var weight_room: int = maxi(0, int((get_max_weight() - current_weight) / unit_w))
		room = mini(space, weight_room)
	var added: int = mini(count, room)
	result["added"] = added
	result["overflow"] = count - added
	return result

## 是否装得下 count 个（事务两段式的预检依据）
func can_add(item_id: String, count: int) -> bool:
	var q: Dictionary = query_add(item_id, count)
	return int(q["added"]) >= count

## 原子扣料（事务语义）：items 为 [{ "item_id": String, "count": int }, ...]
## 先全量校验、再统一扣除；任一不足则整体不扣返回 false。锻造/炼药/批量消耗一律走此接口
func try_consume(items: Array, source: String = "") -> bool:
	if items.is_empty():
		return false
	for entry in items:
		var item_id: String = String(entry.get("item_id", ""))
		var need: int = int(entry.get("count", 1))
		if item_id == "" or need <= 0:
			return false
		# 锁定实例不可被动消耗：用「非锁定可用量」校验，锁定物被排除在批量扣料外
		if get_unlocked_count(item_id) < need:
			return false
	for entry in items:
		remove_item_by_id(String(entry.get("item_id", "")), int(entry.get("count", 1)))
	return true

func _stack_to_existing(bag: Array, item_id: String, count: int) -> int:
	var max_stack: int = ConfigManager.get_item(item_id).get("max_stack", 1)
	var remaining := count
	for inst in bag:
		if remaining <= 0:
			break
		if inst != null and inst.item_id == item_id and inst.count < max_stack:
			var put := mini(max_stack - inst.count, remaining)
			inst.count += put
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
		_dirty = true
		inventory_item_removed.emit(item_id, count - remaining)
		EventBus.inventory_item_removed.emit(item_id, count - remaining)
		return true
	return false

func get_item_count(item_id: String) -> int:
	var total := 0
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				total += inst.count
	return total

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
				var idx: int = bag.find(inst)
				bag[idx] = null
				_recalculate_weight()
				_dirty = true
				return true
	return false

## 使用消耗品：pill 类型或 flags 含 CONSUMABLE 的物品，按配置 heal_hp/heal_mp 生效
## context: "town" / "battle"（当前结算一致，预留战斗限制扩展位）
## 返回 { "ok": bool, "reason": String, "item_id": String, "effect": {hp, mp} }
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
	# 先读效果数值，再扣 1 个，最后结算并广播
	var heal_hp: int = int(data.get("heal_hp", 0))
	var heal_mp: int = int(data.get("heal_mp", 0))
	consume_instance(instance_id)
	var healed: int = 0
	var restored: int = 0
	if heal_hp > 0:
		healed = ps.heal(heal_hp)
	if heal_mp > 0:
		restored = ps.restore_mp(heal_mp)
	var effect := { "hp": healed, "mp": restored }
	EventBus.item_used.emit(item_id, effect)
	GameLogger.info("Inventory", "使用 %s (context=%s) hp+%d mp+%d" % [item_id, context, healed, restored])
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
				_dirty = true
				inventory_item_removed.emit(inst.item_id, 1)
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
			inventory_item_removed.emit(item_id, c)
			EventBus.inventory_item_removed.emit(item_id, c)
	return lost_ids

func _recalculate_weight() -> void:
	current_weight = 0.0
	for bag in [main_slots, material_slots, quest_slots]:
		for inst in bag:
			if inst != null:
				current_weight += ConfigManager.get_item(inst.item_id).get("weight", 0.0) * inst.count
	inventory_weight_changed.emit(current_weight, get_max_weight())

func reset() -> void:
	main_slots.clear(); main_slots.resize(MAX_MAIN_SLOTS)
	material_slots.clear(); material_slots.resize(MAX_MATERIAL_SLOTS)
	quest_slots.clear(); quest_slots.resize(MAX_QUEST_SLOTS)
	current_weight = 0.0
	_next_iid = 1
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

func _serialize_bag(bag: Array) -> Array:
	var out: Array = []
	for inst in bag:
		if inst != null:
			out.append(inst.serialize())
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
	_dirty = false

func _deserialize_bag(arr: Array, bag: Array) -> void:
	for entry in arr:
		var inst := ItemInstance.new()
		inst.deserialize(entry)
		var idx: int = bag.find(null)
		if idx != -1:
			bag[idx] = inst
