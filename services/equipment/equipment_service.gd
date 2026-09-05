# services/equipment/equipment_service.gd
# 装备系统（Phase 2）：把背包中的可装备物品抽到装备槽，按配置重算属性加成
# 数据驱动：装备项来自 ConfigManager（item 配置带 equip_slot + bonus_*）
# 通过 EventBus 通知变化；不持有 Node（铁律）。装备项从背包抽离，存档只存 槽->item_id

extends ISaveable
class_name EquipmentService

# 装备槽名：与配置 item.equip_slot 字符串保持一致
const SLOT_MAIN_HAND := "main_hand"
const SLOT_ARMOR := "armor"
const SLOT_ACCESSORY := "accessory"
const ALL_SLOTS: Array[String] = ["main_hand", "armor", "accessory"]

var equipped: Dictionary = {}   # 槽名(String) -> item_id(String)
var _equipped_inst: Dictionary = {}   # 槽名(String) -> ItemInstance（运行时保留实例身份/耐久；存档只存 item_id，耐久不入档为预存限制）

## 装备：从背包抽出实例装入对应槽，重算加成
## 换装顺序保证不丢物（P0 修复）：先抽新装备（腾出 1 格）→ 再卸旧装备退包（必成功）
func equip(instance_id: String) -> bool:
	var inst: ItemInstance = GameManager.inventory_service.get_instance_by_id(instance_id)
	if inst == null:
		GameLogger.warn("Equipment", "背包中无此物品实例: %s" % instance_id)
		return false
	var item_id: String = inst.item_id
	var data: Dictionary = ConfigManager.get_item(item_id)
	if data.is_empty():
		return false
	var slot: String = data.get("equip_slot", "")
	if slot == "":
		GameLogger.warn("Equipment", "物品不可装备: %s" % item_id)
		return false
	# 1) 先把新装备从背包抽出（保留实例引用，供卸下时原样归还——P1-4 修复根因）
	if not GameManager.inventory_service.remove_instance(instance_id):
		GameLogger.warn("Equipment", "从背包移除失败: %s" % instance_id)
		return false
	# 2) 同槽已有旧装备：摘下退包（腾格后必成功；万一失败则整体回滚）
	if equipped.has(slot):
		var old_id: String = equipped[slot]
		equipped.erase(slot)
		var old_inst: ItemInstance = _equipped_inst.get(slot, null)
		if old_inst != null:
			# 原样归还旧装备（保留 iid/耐久），而非 add_item 重置身份
			if not GameManager.inventory_service.add_instance(old_inst):
				equipped[slot] = old_id
				_equipped_inst[slot] = old_inst   # 回滚须连实例身份一并恢复（原 erase 会丢耐久/iid 归属）
				GameManager.inventory_service.add_instance(inst)   # 回滚：新装备退回背包
				GameLogger.warn("Equipment", "卸下旧装备失败，已回滚: %s" % old_id)
				return false
			_equipped_inst.erase(slot)
		else:
			if not GameManager.inventory_service.add_item(old_id, 1, "unequip"):
				equipped[slot] = old_id
				GameManager.inventory_service.add_instance(inst)
				GameLogger.warn("Equipment", "卸下旧装备失败，已回滚: %s" % old_id)
				return false
		_recompute()
		EventBus.equipment_unequipped.emit(slot, old_id)
		GameLogger.info("Equipment", "卸下 %s 从槽位 %s" % [old_id, slot])
	# 3) 装上新装备（保留实例，供卸下归还）
	equipped[slot] = item_id
	_equipped_inst[slot] = inst
	_recompute()
	EventBus.equipment_equipped.emit(slot, item_id)
	GameLogger.info("Equipment", "装备 %s 于槽位 %s" % [item_id, slot])
	return true

## 卸下：原样归还保留的实例（iid/耐久），满包则失败不丢（P1-4 修复：不再 add_item 重置身份）
func unequip(slot: String) -> bool:
	if not equipped.has(slot):
		return false
	var item_id: String = equipped[slot]
	var inst: ItemInstance = _equipped_inst.get(slot, null)
	if inst != null:
		if not GameManager.inventory_service.add_instance(inst):
			GameLogger.warn("Equipment", "背包已满，无法卸下 %s" % item_id)
			return false
		_equipped_inst.erase(slot)
	else:
		# 旧档/无保留实例：退回新实例（耐久重置，兼容旧存档只存 item_id 的限制）
		if not GameManager.inventory_service.add_item(item_id, 1, "unequip"):
			GameLogger.warn("Equipment", "背包已满，无法卸下 %s" % item_id)
			return false
	equipped.erase(slot)
	_recompute()
	EventBus.equipment_unequipped.emit(slot, item_id)
	GameLogger.info("Equipment", "卸下 %s 从槽位 %s" % [item_id, slot])
	return true

func get_equipped(slot: String) -> String:
	return equipped.get(slot, "")

func is_slot_filled(slot: String) -> bool:
	return equipped.has(slot)

## 依据当前 equipped 重算玩家装备加成并刷新属性
func _recompute() -> void:
	var ps: PlayerState = GameManager.player_state
	if ps == null:
		return
	ps.equipment_bonuses = {}
	for slot in equipped:
		_add_bonus(ps, equipped[slot])
	var old_max_hp: int = ps.max_hp
	var old_max_mp: int = ps.max_mp
	ps.recalculate_stats()
	# 上限提升则补满差额，降低则夹紧，保持当前气血/内力合理
	var d_hp: int = ps.max_hp - old_max_hp
	var d_mp: int = ps.max_mp - old_max_mp
	if d_hp > 0:
		ps.hp = mini(ps.max_hp, ps.hp + d_hp)
	if d_mp > 0:
		ps.mp = mini(ps.max_mp, ps.mp + d_mp)
	ps.hp = mini(ps.hp, ps.max_hp)
	ps.mp = mini(ps.mp, ps.max_mp)
	EventBus.equipment_changed.emit()

func _add_bonus(ps: PlayerState, item_id: String) -> void:
	var data: Dictionary = ConfigManager.get_item(item_id)
	if data.is_empty():
		return
	ps.equipment_bonuses["attack"] = ps.equipment_bonuses.get("attack", 0) + int(data.get("bonus_attack", 0))
	ps.equipment_bonuses["defense"] = ps.equipment_bonuses.get("defense", 0) + int(data.get("bonus_defense", 0))
	ps.equipment_bonuses["max_hp"] = ps.equipment_bonuses.get("max_hp", 0) + int(data.get("bonus_hp", 0))
	ps.equipment_bonuses["max_mp"] = ps.equipment_bonuses.get("max_mp", 0) + int(data.get("bonus_mp", 0))

# === ISaveable ===
func get_save_key() -> String:
	return "equipment"

## 读档依赖（13图 SV-4/P-S4）：load 内重算加成需读 player_state，必须晚于 player 模块恢复
func get_load_after() -> Array[String]:
	return ["player"]

func save() -> Dictionary:
	return {"slots": equipped.duplicate()}

func load(data: Dictionary) -> void:
	equipped = {}
	var slots: Dictionary = data.get("slots", {})
	for slot in slots:
		equipped[slot] = slots[slot]
	# 玩家状态先于本服务加载完成，此处直接重算加成
	if GameManager.player_state != null:
		_recompute()

func reset() -> void:
	equipped = {}
	_equipped_inst = {}
	if GameManager.player_state != null:
		GameManager.player_state.equipment_bonuses = {}
		GameManager.player_state.recalculate_stats()
