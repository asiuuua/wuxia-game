# services/ability/ability_service.gd
# 武学服务（规范 §4）：学习、装备外功到快捷栏、战斗中施展
# 数据驱动：静态数据来自 ConfigManager；不持有 Node（铁律）

extends ISaveable
class_name AbilityService

const MAX_COMBAT_SKILLS := 6

var learned: Dictionary = {}              # ability_id -> 修炼等级（>=1 表示已学）
var equipped_combat: Array[String] = []   # 快捷栏武学 id，长度 MAX_COMBAT_SKILLS
var cd_remaining: Dictionary = {}         # 快捷栏实时冷却（slot:int -> 剩余秒数:float），大世界/战斗桥接共用

func _init() -> void:
	equipped_combat.resize(MAX_COMBAT_SKILLS)

func learn(ability_id: String) -> bool:
	if not ConfigManager.has_ability(ability_id):
		push_error("[Ability] 武学不存在: %s" % ability_id)
		return false
	if learned.has(ability_id):
		return false
	learned[ability_id] = 1
	EventBus.ability_learned.emit(ability_id)
	return true

func is_learned(ability_id: String) -> bool:
	return learned.has(ability_id)

func equip_combat_skill(slot: int, ability_id: String) -> bool:
	if slot < 0 or slot >= MAX_COMBAT_SKILLS:
		return false
	if not learned.has(ability_id):
		return false
	equipped_combat[slot] = ability_id
	cd_remaining.erase(slot)
	EventBus.combat_skill_equipped.emit(ability_id, slot)
	EventBus.notify_skill_bar_changed.emit()
	return true

func unequip_combat_skill(slot: int) -> void:
	if slot >= 0 and slot < MAX_COMBAT_SKILLS:
		equipped_combat[slot] = ""
		cd_remaining.erase(slot)
		EventBus.notify_skill_bar_changed.emit()

## @deprecated 战斗中施展快捷栏武学：返回伤害结果字典 {hit, damage, crit, dodged}
##   该路径绕过 CombatCore.player_skill 直调 take_damage/mp，可能与战斗桥接双重结算。
##   新代码请走 CombatCore.player_skill（combat_core）统一结算；保留仅为兼容旧调用方。
func use_combat_skill(slot: int, caster: CombatCharacter, target: CombatCharacter) -> Dictionary:
	if slot < 0 or slot >= equipped_combat.size():
		return {"hit": false, "damage": 0, "crit": false, "dodged": false}
	var ability_id: String = equipped_combat[slot]
	if ability_id == "":
		return {"hit": false, "damage": 0, "crit": false, "dodged": false}
	var data: Dictionary = ConfigManager.get_ability(ability_id)
	if data.is_empty():
		return {"hit": false, "damage": 0, "crit": false, "dodged": false}
	var mp_cost: int = data.get("mp_cost", 0)
	if caster.mp < mp_cost:
		return {"hit": false, "damage": 0, "crit": false, "dodged": false}
	caster.mp -= mp_cost
	var level: int = learned.get(ability_id, 1)
	var level_mult: float = 1.0 + (level - 1) * 0.15
	var damage_base: int = data.get("power", 0)
	var damage: int = int((damage_base + caster.attack * 0.5) * level_mult)
	var result: Dictionary = target.take_damage(damage, CombatEnums.DamageType.PHYSICAL, caster)
	EventBus.ability_used.emit(ability_id, caster.character_id)
	# 字段/大世界施展也进入冷却读秒（与战斗桥接共用 ability_service.cd_remaining；本方法目前非战斗主路径）
	var cd: int = int(data.get("cooldown", 0))
	if cd > 0:
		set_cooldown(slot, float(cd))
	return result

## 设定某快捷栏槽位的实时冷却（秒）。归零/负值即清除并推送 remain=0。
## 由战斗桥接（combat_core 玩家施展）与大世界施展调用；HUD 技能栏订阅 notify_skill_cd_update 展示。
func set_cooldown(slot: int, seconds: float) -> void:
	if slot < 0 or slot >= MAX_COMBAT_SKILLS:
		return
	var ability_id: String = equipped_combat[slot] if slot < equipped_combat.size() else ""
	if ability_id == "":
		return
	if seconds <= 0.0:
		cd_remaining.erase(slot)
		EventBus.notify_skill_cd_update.emit(ability_id, 0.0)
	else:
		cd_remaining[slot] = seconds
		EventBus.notify_skill_cd_update.emit(ability_id, seconds)

## 每帧递减所有槽位冷却并推送；归零自动清除。由 GameManager._process 驱动。
func tick_cooldowns(delta: float) -> void:
	if cd_remaining.is_empty():
		return
	for slot in cd_remaining.keys():
		var remain: float = cd_remaining[slot] - delta
		var ability_id: String = equipped_combat[slot] if slot < equipped_combat.size() else ""
		if remain <= 0.0:
			cd_remaining.erase(slot)
			if ability_id != "":
				EventBus.notify_skill_cd_update.emit(ability_id, 0.0)
		else:
			cd_remaining[slot] = remain
			if ability_id != "":
				EventBus.notify_skill_cd_update.emit(ability_id, remain)

func reset() -> void:
	learned.clear()
	equipped_combat.clear()
	equipped_combat.resize(MAX_COMBAT_SKILLS)
	cd_remaining.clear()

func get_save_key() -> String:
	return "ability"

func save() -> Dictionary:
	return {"learned": learned, "equipped": equipped_combat}

func load(data: Dictionary) -> void:
	learned = data.get("learned", {})
	# data.get 返回 Variant Array；typed Array 赋值时 `as Array[String]` 只换包装不转元素，
	# 必须显式 String() 循环 append 才能正确恢复。详见 2026-08-28 memory 踩坑。
	equipped_combat.clear()
	for s in data.get("equipped", []):
		equipped_combat.append(String(s))
	equipped_combat.resize(MAX_COMBAT_SKILLS)
