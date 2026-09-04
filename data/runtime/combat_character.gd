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
var shield: int = 0             # 护盾(Shield)：吸收伤害，优先于气血扣减，持续到被消耗（M3-2）

var speed: int = 8               # 集气速率（=逸剑「集气速率」），驱动 ATB 行动顺序

var attack: int = 10
var defense: int = 5
var crit_rate: float = 0.05
var crit_damage: float = 1.5
var hit_rate: float = 0.95
var dodge_rate: float = 0.05

# ── 阶段A 数值派生（对标逸剑三层模型：五维根属性→面板属性）──
# flat：min==max==attack、accuity=0，保持历史扁平行为；five_attr：由 five_attrs+attribute_table 换算派生。
# 未调用 apply_derive_panel() 前 _derive_applied=false，effective_attack_min/max 一律退回 attack，零回归。
var derive_mode: String = "flat"
var five_attrs: Dictionary = {}   # 五维根属性 {tizhi, yu, jin, min, shi}
var min_attack: int = 0           # 攻击区间下限
var max_attack: int = 0           # 攻击区间上限
var accuity_rate: float = 0.0     # 会意率/% 精准贯通（阶段B 判定用）
var _derive_applied: bool = false

var cooldowns: Dictionary = {}   # skill_id -> 剩余冷却回合
var status_effects: Array[StatusEffect] = []   # 当前挂载状态
var ai_kit: Array = []            # 敌人 AI 技能包（M3）：[{id, weight, condition}]；玩家恒为空

# ── 战术网格（战棋模式，M4 增量）──
var grid_pos: Vector2i = Vector2i.ZERO   # 战场网格坐标（非战棋模式恒为 0,0）
var move_range: int = 3                   # 每回合可移动格数（BFS 步数上限）
# 面朝方向：纯逻辑枚举，只由「逻辑坐标差值」计算，与屏幕/斜45°无关（P1·对标方案提醒）
enum FACING { UP, DOWN, LEFT, RIGHT }
var facing: int = FACING.DOWN

## 由「从→到」逻辑坐标差值推导面朝（绝不读屏幕尺寸）；逻辑层只用此枚举，贴图切换交给视图层
static func calc_facing(from: Vector2i, to: Vector2i) -> int:
	var d: Vector2i = to - from
	if d.y < 0:
		return FACING.UP
	elif d.y > 0:
		return FACING.DOWN
	elif d.x < 0:
		return FACING.LEFT
	else:
		return FACING.RIGHT

# ⚠️ 非战斗遗留路径（供 AbilityService 等战斗外伤害结算）：不走护盾 / 反弹 / 复活，
# 且 rng 为 null 时回退全局 randf()（不可复现）。【战斗内伤害必须走 CombatCore._resolve_hit】，
# 切勿在战斗流程里调用本方法，否则会绕过 M3-2 的护盾 / 反弹 / 复活机制。
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

# ─────────── 阶段A 派生管线（flat 默认，零回归）───────────

## 五维根属性→某面板换算系数（weights=attribute_table 整表；缺失返回 default）
func _weight(weights: Dictionary, attr: String, panel: String, fallback: float = 0.0) -> float:
	var node: Dictionary = weights.get("five_attr_weights", {}).get(attr, {})
	return float(node.get(panel, fallback))

## 接入 derive_mode 派生管线。
## - flat（默认）：min=max=attack、accuity=0，不动 hp/defense，历史行为完全不变；
## - five_attr：由 five_attrs 五维 + attribute_table 系数换算 max_hp/defense/min-max_attack/crit_rate/accuity_rate。
## weights 缺省时从 ConfigManager 读取整表（配置驱动，零硬编码）。
func apply_derive_panel(weights: Dictionary = {}) -> void:
	if weights.is_empty():
		weights = ConfigManager.get_combat_attr()
	derive_mode = String(weights.get("derive_mode", "flat"))
	if derive_mode == "flat":
		min_attack = attack
		max_attack = attack
		accuity_rate = 0.0
	else:
		var tizhi: float = float(five_attrs.get("tizhi", 0.0))
		var yu: float = float(five_attrs.get("yu", 0.0))
		var jin: float = float(five_attrs.get("jin", 0.0))
		var minzhi: float = float(five_attrs.get("min", 0.0))
		var shi: float = float(five_attrs.get("shi", 0.0))
		max_hp = int(max_hp + tizhi * _weight(weights, "tizhi", "max_hp", 62.0) + yu * _weight(weights, "yu", "max_hp", 16.95))
		defense = int(defense + yu * _weight(weights, "yu", "defense", 0.6))
		min_attack = int(max(1.0, attack + jin * _weight(weights, "jin", "min_attack", 0.17) + minzhi * _weight(weights, "min", "min_attack", 0.9)))
		max_attack = int(max(min_attack, attack + jin * _weight(weights, "jin", "max_attack", 1.41) + shi * _weight(weights, "shi", "max_attack", 0.9)))
		crit_rate = clampf(crit_rate + minzhi * _weight(weights, "min", "crit_rate", 0.081), 0.0, 0.8)
		accuity_rate = clampf(shi * _weight(weights, "shi", "accuity_rate", 0.035), 0.0, 0.4)
		if hp > max_hp:
			hp = max_hp
	_derive_applied = true

## 攻击区间下限（含状态修正）；未派生时退回 attack（兼容旧构建路径）
func effective_attack_min() -> int:
	var base: int = min_attack if _derive_applied else attack
	return int(max(1, base + _status_total("attack", StatusEffect.MODE_FLAT)) * (1.0 + _status_total("attack", StatusEffect.MODE_PCT) / 100.0))

## 攻击区间上限（含状态修正）；未派生时退回 attack
func effective_attack_max() -> int:
	var base: int = max(max_attack, min_attack) if _derive_applied else attack
	return int(max(1, base + _status_total("attack", StatusEffect.MODE_FLAT)) * (1.0 + _status_total("attack", StatusEffect.MODE_PCT) / 100.0))

## 本回合攻击取值（区间内平取；阶段B 接入擦伤/精准命中随机判定时替换）
func effective_attack_roll() -> int:
	return effective_attack_max()

func is_alive() -> bool:
	return not is_dead and not is_downed
