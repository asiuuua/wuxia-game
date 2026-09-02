# data/runtime/player_state.gd
# 玩家运行时状态：所有业务模块的数据中心（规范 §1.3）
# 实现 ISaveable 接口契约；运行时战斗属性由 recalculate_stats 计算，不存档

extends ISaveable
class_name PlayerState

var player_id: String = "player_001"
var player_name: String = "李十五"
var level: int = 1
var experience: int = 0
var exp_to_next: int = 100

# === 生命资源 ===
var hp: int = 100
var max_hp: int = 100
var mp: int = 50
var max_mp: int = 50

# === 六维属性 ===
var strength: int = 10        # 力量：影响攻击/负重
var constitution: int = 10    # 根骨：影响 HP/防御
var agility: int = 10        # 敏捷：影响闪避/攻速
var wisdom: int = 10         # 悟性：影响内功上限/修炼
var luck: int = 10           # 福缘：影响掉落/暴击
var focus: int = 10          # 定力：影响抗控

# === 战斗属性（运行时计算）===
var attack: int = 0
var defense: int = 0
var crit_rate: float = 0.05
var crit_damage: float = 1.5
var dodge_rate: float = 0.05

# === 装备加成（由 EquipmentService 维护，重算属性时叠加） ===
var equipment_bonuses: Dictionary = {}

# === 金钱（统一货币）===
var silver: int = 0
var copper: int = 0
var gold: int = 0

# === 负债（团灭惩罚：无钱支付死亡代价时累计；独立字段，比银两为负更清晰） ===
var debt: int = 0

# === 年龄（生育系统依赖，阶段A 前置补齐） ===
var age: int = 18

# === 性别（姻缘系统异性结缘校验用；0=男 1=女） ===
var gender: int = 0

# === 队友槽位占位（CompanionService 阶段C 才落地，此处仅预留 ID 列表） ===
# 用 untyped Array 规避从 Dictionary 读档时的 typed-array 赋值报错（见工程红线 #3）
var companion_ids: Array = []

# === 状态效果 ===
var active_effects: Array[StatusEffect] = []

# === 背包增益丹药：按现实时间持续（独立计时器，到期由 GameManager 每秒清理） ===
# 元素：{ "stat": String, "value": int, "expire_at": int }（expire_at 为 unix 秒）
var time_buffs: Array = []

## 测试钩子：>0 时覆盖"当前现实时间"（unix 秒）用于单测模拟时间流逝；-1=用系统时间
var now_override: int = -1

func init_default(unit_name: String, start_level: int) -> void:
	player_name = unit_name
	level = start_level
	experience = 0
	exp_to_next = _exp_curve(level)
	_apply_level_base()
	equipment_bonuses = {}
	debt = 0
	recalculate_stats()
	hp = max_hp
	mp = max_mp

func _apply_level_base() -> void:
	# 等级基础属性已在 recalculate_stats 中随装备加成一并计算，此处不再单独处理
	pass

# 升级经验曲线：集中计算，避免魔法数字
func _exp_curve(lv: int) -> int:
	return 100 + (lv - 1) * 50

## 获得经验，返回是否升级（升级后回满气血内力）
func gain_exp(amount: int) -> bool:
	experience += amount
	var leveled := false
	while experience >= exp_to_next:
		experience -= exp_to_next
		level += 1
		_apply_level_base()
		exp_to_next = _exp_curve(level)
		leveled = true
	if leveled:
		hp = max_hp
		mp = max_mp
		recalculate_stats()
		EventBus.player_level_up.emit(level)
	EventBus.player_exp_changed.emit(experience, exp_to_next)
	return leveled

## 基础属性 + 装备加成 -> 战斗属性（规范 §1.4 重算流程的核心）
## 装备加成从 equipment_bonuses 读取，由 EquipmentService 装卸时维护
func recalculate_stats() -> void:
	var base_max_hp: int = 80 + level * 20
	var base_max_mp: int = 30 + level * 10
	max_hp = base_max_hp + int(equipment_bonuses.get("max_hp", 0))
	max_mp = base_max_mp + int(equipment_bonuses.get("max_mp", 0))
	attack = strength * 2 + level * 3 + int(equipment_bonuses.get("attack", 0)) + get_time_buff_total("attack")
	defense = int(constitution * 1.5) + level * 2 + int(equipment_bonuses.get("defense", 0)) + get_time_buff_total("defense")
	crit_rate = 0.05 + luck * 0.005
	dodge_rate = 0.05 + agility * 0.003
	EventBus.player_stats_changed.emit()

func take_damage(amount: int) -> int:
	var dmg: int = max(1, amount - int(defense * 0.5))
	hp = max(0, hp - dmg)
	EventBus.player_hp_changed.emit(hp, max_hp)
	if hp <= 0:
		EventBus.player_died.emit()
	return dmg

func heal(amount: int) -> int:
	var before: int = hp
	hp = min(max_hp, hp + amount)
	var healed: int = hp - before
	EventBus.player_hp_changed.emit(hp, max_hp)
	return healed

## 恢复内力（丹药/休息），返回实际恢复量（上限夹紧）
func restore_mp(amount: int) -> int:
	var before: int = mp
	mp = mini(max_mp, mp + amount)
	var restored: int = mp - before
	if restored > 0:
		EventBus.player_mp_changed.emit(mp, max_mp)
	return restored

## 当前现实时间（unix 秒）；now_override>0 时用覆盖值（单测模拟时间流逝）
func _now_unix() -> int:
	return now_override if now_override > 0 else int(Time.get_unix_time_from_system())

## 背包增益丹药：登记一个"按现实时间持续"的临时加成（独立计时器，到期自动失效）
## 同属性可叠加：每次服用追加一条独立记录，各自按到期时间失效
func apply_time_buff(stat: String, value: int, duration_minutes: int) -> void:
	if value <= 0 or duration_minutes <= 0:
		return
	var expire_at: int = _now_unix() + duration_minutes * 60
	time_buffs.append({ "stat": stat, "value": value, "expire_at": expire_at })
	recalculate_stats()

## 清理已过期的现实时间增益，返回移除数量（GameManager 每秒调用一次）
func purge_expired_time_buffs() -> int:
	var now: int = _now_unix()
	var removed := 0
	var i := time_buffs.size() - 1
	while i >= 0:
		if int(time_buffs[i]["expire_at"]) <= now:
			time_buffs.remove_at(i)
			removed += 1
		i -= 1
	if removed > 0:
		recalculate_stats()
	return removed

## 查询某属性当前现实时间增益总值（未过期部分）
func get_time_buff_total(stat: String) -> int:
	var total := 0
	for b in time_buffs:
		if String(b["stat"]) == stat:
			total += int(b["value"])
	return total

## 查询某属性现实时间增益剩余秒数（取最晚到期；无则 0）
func get_time_buff_remaining(stat: String) -> int:
	var now: int = _now_unix()
	var latest := 0
	for b in time_buffs:
		if String(b["stat"]) == stat:
			latest = maxi(latest, int(b["expire_at"]) - now)
	return maxi(0, latest)

## 清除指定异常状态（解毒/解眩晕丹药），返回是否确实清除了
func clear_status(status_id: String) -> bool:
	for i in range(active_effects.size()):
		if active_effects[i].effect_id == status_id:
			active_effects.remove_at(i)
			recalculate_stats()
			return true
	return false

## 是否处于指定异常状态
func has_status(status_id: String) -> bool:
	for se in active_effects:
		if se.effect_id == status_id:
			return true
	return false

func consume_mp(amount: int) -> bool:
	if mp < amount:
		return false
	mp -= amount
	EventBus.player_mp_changed.emit(mp, max_mp)
	return true

## 花钱：优先扣银两；不足则不改动并返回 false（调用方据返回值决定是否放行）
func spend_money(amount: int) -> bool:
	if amount <= 0:
		return true
	if silver < amount:
		return false
	silver -= amount
	EventBus.player_money_changed.emit(silver, copper, gold)
	return true

## 赚钱：增加银两并广播变化（钓鱼/打造产出、任务奖励等调用）
func add_money(amount: int) -> void:
	if amount <= 0:
		return
	silver += amount
	EventBus.player_money_changed.emit(silver, copper, gold)

## 负债：累计债务并广播（团灭惩罚「无钱则负债」路径调用）
func add_debt(amount: int) -> void:
	if amount <= 0:
		return
	debt += amount
	EventBus.player_money_changed.emit(silver, copper, gold)

func get_hp_percent() -> float:
	return float(hp) / float(max_hp) if max_hp > 0 else 0.0

func is_dead() -> bool:
	return hp <= 0

# === ISaveable ===
func get_save_key() -> String:
	return "player"

func save() -> Dictionary:
	return {
		"player_name": player_name, "level": level, "experience": experience, "exp_to_next": exp_to_next,
		"hp": hp, "max_hp": max_hp, "mp": mp, "max_mp": max_mp,
		"strength": strength, "constitution": constitution, "agility": agility,
		"wisdom": wisdom, "luck": luck, "focus": focus,
		"silver": silver, "copper": copper, "gold": gold,
		"debt": debt,
		"age": age, "gender": gender, "companion_ids": companion_ids,
		"time_buffs": time_buffs,
	}

func load(data: Dictionary) -> void:
	player_name = data.get("player_name", player_name)
	level = data.get("level", level)
	experience = data.get("experience", experience)
	exp_to_next = data.get("exp_to_next", exp_to_next)
	hp = data.get("hp", hp)
	max_hp = data.get("max_hp", max_hp)
	mp = data.get("mp", mp)
	max_mp = data.get("max_mp", max_mp)
	strength = data.get("strength", strength)
	constitution = data.get("constitution", constitution)
	agility = data.get("agility", agility)
	wisdom = data.get("wisdom", wisdom)
	luck = data.get("luck", luck)
	focus = data.get("focus", focus)
	silver = data.get("silver", silver)
	copper = data.get("copper", copper)
	gold = data.get("gold", gold)
	debt = int(data.get("debt", 0))
	age = int(data.get("age", age))
	gender = int(data.get("gender", gender))
	# 从 Dictionary 取值为 Variant，赋给 untyped Array 不触发 typed-array 报错
	companion_ids = data.get("companion_ids", companion_ids)
	time_buffs = data.get("time_buffs", [])
	purge_expired_time_buffs()  # 读档后清理已过期的现实时间增益（离线期间时间仍在流逝）
	recalculate_stats()
