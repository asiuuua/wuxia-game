# data/runtime/combat_character.gd
# 战斗单位运行时快照（玩家与敌人共用）
# 设计：战斗开始时由 PlayerState / EnemyData 构建，战斗结束再把 hp/mp 写回 PlayerState
# 业务层对象（RefCounted），不持有任何 Node 引用

extends RefCounted
class_name CombatCharacter

var character_id: String = ""
var name_key: String = ""
var is_player: bool = false
var is_dead: bool = false
var is_downed: bool = false          # 非致命击倒：hp 归零但不死（allow_non_lethal 时触发）
var damage_taken_mult: float = 1.0  # 受到攻击时的伤害倍率（敌人承受玩家伤害=玩家倍率；玩家承受敌人倍率）
var can_be_downed: bool = false     # 是否允许被非致命击倒（由难度 allow_non_lethal 注入）

var max_hp: int = 100
var hp: int = 100
var max_mp: int = 50
var mp: int = 50                 # 真气(Qi)：招式消耗、调息回复（对标逸剑黄条）

var speed: int = 8               # 集气速率（=逸剑「集气速率」），驱动 ATB 行动顺序
var charge: float = 0.0          # 当前集气值（ATB 运行时累积，M2 顺序条可视化用）

var attack: int = 10
var defense: int = 5
var crit_rate: float = 0.05
var crit_damage: float = 1.5
var hit_rate: float = 0.95
var dodge_rate: float = 0.05

var cooldowns: Dictionary = {}   # skill_id -> 剩余冷却回合
var status_effects: Array[StatusEffect] = []   # 当前挂载状态

# 受到伤害：命中/闪避/防御减伤/暴击（使用有效属性 + 可选注入随机源）
# rng 为 null 时回退全局 randf()（兼容直接调用）；CombatCore 会注入 SeededRNG 保证可复现
func take_damage(amount: int, _damage_type: int, source: CombatCharacter, rng: SeededRNG = null) -> Dictionary:
	if is_dead:
		return {"hit": false, "damage": 0, "crit": false, "dodged": false}
	var dodge: float = effective_dodge_rate()
	if (rng != null and rng.chance(dodge)) or (rng == null and randf() < dodge):
		return {"hit": false, "damage": 0, "crit": false, "dodged": true}
	var final_damage: int = max(1, amount - int(effective_defense() * 0.5))
	var crit: bool = false
	if source != null:
		var cr: float = source.effective_crit_rate()
		if (rng != null and rng.chance(cr)) or (rng == null and randf() < cr):
			crit = true
	if crit:
		final_damage = int(final_damage * source.crit_damage)
	final_damage = max(1, int(float(final_damage) * damage_taken_mult))
	hp = max(0, hp - final_damage)
	if hp <= 0:
		# 非致命开关开启且非玩家：倒地而非死亡（剧情/道德上保留活口）
		if can_be_downed and not is_player:
			is_downed = true
		else:
			is_dead = true
	return {"hit": true, "damage": final_damage, "crit": crit, "dodged": false}

# 基础攻击一次：返回伤害结果（供 AI 与玩家普攻复用）
func basic_attack(target: CombatCharacter, rng: SeededRNG = null) -> Dictionary:
	if target == null or target.is_dead:
		return {"hit": false, "damage": 0, "crit": false, "dodged": false}
	return target.take_damage(effective_attack(), CombatEnums.DamageType.PHYSICAL, self, rng)

func heal(amount: int) -> int:
	var before: int = hp
	hp = min(max_hp, hp + amount)
	return hp - before

# ─────────── 有效属性（基础值 + 状态修正，幅度 = value * stacks）───────────

func _status_total(stat: String, mode: int) -> float:
	var total: float = 0.0
	for se in status_effects:
		if se.stat == stat and se.mode == mode:
			total += se.value * se.stacks
	return total

func effective_attack() -> int:
	return int(max(1, attack + _status_total("attack", StatusEffect.MODE_FLAT)) * (1.0 + _status_total("attack", StatusEffect.MODE_PCT) / 100.0))

func effective_defense() -> int:
	return int(max(0, defense + _status_total("defense", StatusEffect.MODE_FLAT)) * (1.0 + _status_total("defense", StatusEffect.MODE_PCT) / 100.0))

func effective_crit_rate() -> float:
	return clampf(crit_rate + _status_total("crit", StatusEffect.MODE_PCT) / 100.0, 0.0, 1.0)

func effective_dodge_rate() -> float:
	return clampf(dodge_rate + _status_total("dodge", StatusEffect.MODE_PCT) / 100.0, 0.0, 1.0)

## 集气速率（ATB）：speed 基础 + 状态修正，M2 顺序条据此排序
func effective_charge_rate() -> float:
	return max(1.0, speed + _status_total("speed", StatusEffect.MODE_FLAT)) * (1.0 + _status_total("speed", StatusEffect.MODE_PCT) / 100.0)

func is_alive() -> bool:
	return not is_dead and not is_downed
