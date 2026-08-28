# services/combat/combat_core.gd
# 战斗逻辑内核（M1 核心）：对标逸剑风云决等商业 CRPG 的战斗深度
# 职责：
#   - 接管原 BattleScene 里的流程编排（攻击→敌人回合→判胜负→结算），逻辑层算完吐事件，不再一帧跑完
#   - ATB 行动值模型：speed(集气速率) 驱动行动顺序，供 M2 顺序条可视化
#   - 双资源：hp(气血) + mp(真气/Qi)；招式耗真气、调息回真气
#   - 招式分阶(普攻/二式/三式/绝世/轻功/心法/调息) + 冷却 + 施加状态
#   - 真实状态引擎：层数(上限) + 持续回合 + 每回合生效(DoT/HoT) + 属性修正(攻/防/暴击/闪避/集气速率)
#   - 确定性随机：所有随机走注入的 SeededRNG，同 seed 同结果（可存档/回放/单测）
# 不持有任何 Node 引用（业务层铁律）。战斗内高频有序流走返回值 Array[CombatEvent]，不走 EventBus。

extends RefCounted
class_name CombatCore

var rng: SeededRNG = SeededRNG.new()
var state: CombatState = null

var _status_db: Dictionary = {}

func configure(p_state: CombatState, seed_val: int = 0) -> void:
	state = p_state
	if seed_val == 0:
		seed_val = int(Time.get_unix_time_from_system()) & 0x7FFFFFFF
	rng.configure(seed_val)

# ───────────────────────── 玩家行动 ─────────────────────────

## 玩家普攻 → 返回本次行动的事件流
func player_basic(target_id: String = "") -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if state == null or not state.is_active:
		return events
	var target: CombatCharacter = _resolve(target_id)
	if target == null:
		return events
	events.append_array(tick_unit(state.player))            # 自己回合开始先 tick 自身状态
	events.append(_ev(CombatEvent.Type.ACTION_BASIC, state.player.character_id, target.character_id))
	var res: Dictionary = _resolve_hit(state.player, target, state.player.effective_attack())
	events.append_array(res.events)
	_try_down(target, events)
	return events

## 玩家招式（slot=快捷栏位）→ 返回事件流（含真气消耗 / 冷却 / 状态施加）
## 复用 _cast_skill 与敌人共用同一套施法结算，行为零变化（双闸门保护）
func player_skill(slot: int, target_id: String = "") -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if state == null or not state.is_active:
		return events
	if slot < 0 or slot >= GameManager.ability_service.equipped_combat.size():
		return events
	var ability_id: String = GameManager.ability_service.equipped_combat[slot]
	if ability_id == "":
		return events
	events.append_array(tick_unit(state.player))          # 自己回合开始先 tick（含冷却递减）
	events.append_array(_cast_skill(state.player, ability_id, target_id))
	return events

## 通用施法结算（玩家 / 敌人共用）：真气消耗 + 冷却 + 目标解析 + 伤害 + 状态施加
## 返回事件流。mp 不足 / 冷却中 / 配置缺失 → 返回空（调用方据此普攻兜底）
## 修复：self / all_allies 目标（调息 / 心法 / 轻功等自buff）只施加状态、不再对自身造成 power 伤害
func _cast_skill(caster: CombatCharacter, ability_id: String, primary_target_id: String = "") -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if caster == null or not caster.is_alive():
		return events
	var cfg: Dictionary = ConfigManager.get_ability(ability_id)
	if cfg.is_empty():
		return events
	var qi_cost: int = int(cfg.get("qi_cost", cfg.get("mp_cost", 0)))
	if caster.mp < qi_cost:
		return events
	var cd_key: String = ability_id
	if caster.cooldowns.has(cd_key) and caster.cooldowns[cd_key] > 0:
		return events
	caster.mp -= qi_cost
	var ev_qi := _ev(CombatEvent.Type.QI_COST, caster.character_id, "", qi_cost)
	ev_qi.actor_mp_after = caster.mp
	events.append(ev_qi)
	var cd: int = int(cfg.get("cooldown", 0))
	if cd > 0:
		caster.cooldowns[cd_key] = cd
		events.append(_ev(CombatEvent.Type.COOLDOWN_SET, caster.character_id, "", cd, false, false, "", 0, ability_id))
	events.append(_ev(CombatEvent.Type.ACTION_SKILL, caster.character_id, primary_target_id, 0, false, false, "", 0, ability_id))
	var cfg_target: String = cfg.get("target", "enemy")
	var is_self: bool = (cfg_target == "self" or cfg_target == "all_allies")
	var targets: Array[CombatCharacter] = []
	if cfg_target == "all_enemies":
		targets = state.get_alive_enemies() if caster.is_player else [state.player]   # 敌人群攻只打单人玩家
	elif is_self:
		targets = [caster]
	else:
		var t: CombatCharacter = state.player if not caster.is_player else _resolve(primary_target_id)
		if t != null and t.is_alive():
			targets.append(t)
	var power: int = int(cfg.get("power", 0)) + int(caster.effective_attack() * 0.3)
	for tgt in targets:
		if not is_self:
			var res: Dictionary = _resolve_hit(caster, tgt, power)
			events.append_array(res.events)
			_try_down(tgt, events)
		for eff in cfg.get("effects", []):
			var ev: CombatEvent = _apply_status(tgt, eff.get("status_id", ""), int(eff.get("stacks", 1)))
			if ev != null:
				events.append(ev)
	return events

## 调息（rest）：恢复少量气血与真气（逸剑核心指令之一）
func player_rest() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if state == null or not state.is_active:
		return events
	events.append_array(tick_unit(state.player))
	var heal_amt: int = int(state.player.max_hp * 0.08)
	var qi_amt: int = int(state.player.max_mp * 0.15)
	state.player.hp = min(state.player.max_hp, state.player.hp + heal_amt)
	state.player.mp = min(state.player.max_mp, state.player.mp + qi_amt)
	var ev_heal := _ev(CombatEvent.Type.HEAL, state.player.character_id, "", heal_amt)
	ev_heal.target_hp_after = state.player.hp
	ev_heal.target_max_hp = state.player.max_hp
	events.append(ev_heal)
	var ev_qigain := _ev(CombatEvent.Type.QI_GAIN, state.player.character_id, "", qi_amt)
	ev_qigain.target_mp_after = state.player.mp
	events.append(ev_qigain)
	# 调息清除标记了 clear_on_rest 的状态
	for i in range(state.player.status_effects.size() - 1, -1, -1):
		if state.player.status_effects[i].clear_on_rest:
			state.player.status_effects.remove_at(i)
	return events

# ───────────────────────── 敌人阶段 ─────────────────────────

## 敌人阶段：所有存活敌人依次行动（M2 演出层按事件逐个播放）
## M3：每个敌人先用 _pick_enemy_ability 按权重 + 条件选招，无可用招则普攻兜底
func enemy_phase() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if state == null:
		return events
	for enemy in state.get_alive_enemies():
		events.append(_ev(CombatEvent.Type.TURN_START, enemy.character_id))
		events.append_array(tick_unit(enemy))            # 含冷却递减
		if not enemy.is_alive():
			continue
		var ab: Dictionary = _pick_enemy_ability(enemy)
		if ab.is_empty():
			# 普攻兜底（ACTION_BASIC + DAMAGE）
			events.append(_ev(CombatEvent.Type.ACTION_BASIC, enemy.character_id, state.player.character_id))
			var res: Dictionary = _resolve_hit(enemy, state.player, enemy.effective_attack())
			events.append_array(res.events)
		else:
			events.append_array(_cast_skill(enemy, ab.get("id", ""), "player"))
		_try_down(state.player, events)
		if state.player.is_dead:
			break
	return events

## 按权重从敌人 AI 技能包里选一个可用招式（确定性：rng.randf() 由内核 seed 驱动）
## 返回 {id, weight, condition} 或空字典（无可用的 → 调用方普攻兜底）
func _pick_enemy_ability(enemy: CombatCharacter) -> Dictionary:
	if enemy.ai_kit == null or enemy.ai_kit.is_empty():
		return {}
	var candidates: Array = []
	var total: float = 0.0
	for entry in enemy.ai_kit:
		var id: String = entry.get("id", "")
		if id == "":
			continue
		if not _ability_usable(enemy, id):
			continue
		if not _condition_met(enemy, entry.get("condition", "always")):
			continue
		var w: float = float(entry.get("weight", 1))
		if w <= 0:
			continue
		candidates.append(entry)
		total += w
	if candidates.is_empty() or total <= 0:
		return {}
	var roll: float = rng.randf() * total
	for entry in candidates:
		roll -= float(entry.get("weight", 1))
		if roll < 0:
			return entry
	return candidates[candidates.size() - 1]

## 招式是否当前可用：配置存在 + 真气足够 + 不在冷却
func _ability_usable(enemy: CombatCharacter, ability_id: String) -> bool:
	var cfg: Dictionary = ConfigManager.get_ability(ability_id)
	if cfg.is_empty():
		return false
	if enemy.mp < int(cfg.get("qi_cost", cfg.get("mp_cost", 0))):
		return false
	var cd: int = int(cfg.get("cooldown", 0))
	if cd > 0 and enemy.cooldowns.has(ability_id) and enemy.cooldowns[ability_id] > 0:
		return false
	return true

## 条件门控（M3 文法）：always | player_hp_below:<0-1> | self_hp_below:<0-1> | self_mp_above:<0-1>
func _condition_met(enemy: CombatCharacter, cond: String) -> bool:
	if cond == "" or cond == "always":
		return true
	var parts: PackedStringArray = cond.split(":", false)
	if parts.size() < 2:
		return true
	var key: String = parts[0]
	var thr: float = float(parts[1])
	if key == "player_hp_below":
		return state.player.hp <= state.player.max_hp * thr
	if key == "self_hp_below":
		return enemy.hp <= enemy.max_hp * thr
	if key == "self_mp_above":
		return enemy.mp >= enemy.max_mp * thr
	return true

# ───────────────────────── 状态 ─────────────────────────

## 单位回合开始 tick：冷却递减(M1 修复) + DoT/HoT 生效 + 持续回合递减 + 到期移除
## 冷却递减必须在「单位行动之前」执行：player_skill / enemy_phase 都在 tick 之后才写 cd，
## 故此处递减不会误伤「刚设的 cd」，且能让上回合的招式在下一回合恢复可用。
func tick_unit(unit: CombatCharacter) -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	# ── 冷却递减（修复 M1：此前全工程从未递减 cooldowns，招式一旦放出即永久进冷却）──
	var cd_keys := unit.cooldowns.keys()
	for k in cd_keys:
		unit.cooldowns[k] = max(0, int(unit.cooldowns[k]) - 1)
		if unit.cooldowns[k] <= 0:
			unit.cooldowns.erase(k)
	for i in range(unit.status_effects.size() - 1, -1, -1):
		var se: StatusEffect = unit.status_effects[i]
		if se.dot_per_turn != 0:
			var amt: int = se.dot_per_turn * se.stacks
			unit.hp = clampi(unit.hp + amt, 0, unit.max_hp)
			var ev_tick := _ev(CombatEvent.Type.STATUS_TICK, "", unit.character_id, amt, false, false, se.effect_id, se.stacks)
			ev_tick.target_hp_after = unit.hp
			ev_tick.target_max_hp = unit.max_hp
			events.append(ev_tick)
		se.remaining -= 1
		if se.remaining <= 0:
			unit.status_effects.remove_at(i)
			events.append(_ev(CombatEvent.Type.STATUS_EXPIRED, "", unit.character_id, 0, false, false, se.effect_id, se.stacks))
	return events

## 对某单位施加状态（合并层数 / 刷新持续）
func _apply_status(unit: CombatCharacter, status_id: String, stacks: int) -> CombatEvent:
	var cfg: Dictionary = _get_status_cfg(status_id)
	if cfg.is_empty() or unit == null:
		return null
	for se in unit.status_effects:
		if se.effect_id == status_id:
			se.stacks = min(se.max_stacks, se.stacks + stacks)
			se.remaining = max(se.remaining, int(cfg.get("duration", 2)))
			return _ev(CombatEvent.Type.STATUS_APPLIED, "", unit.character_id, 0, false, false, status_id, se.stacks)
	var se := StatusEffect.new()
	se.effect_id = status_id
	se.name_key = cfg.get("name", status_id)
	se.type = CombatEnums.EffectType.get(cfg.get("type", "BUFF"))
	se.stat = cfg.get("stat", "")
	se.mode = StatusEffect.mode_from_str(cfg.get("mode", "flat"))
	se.value = float(cfg.get("value", 0))
	se.max_stacks = int(cfg.get("max_stacks", 9))
	se.stacks = stacks
	se.remaining = int(cfg.get("duration", 2))
	se.dot_per_turn = int(cfg.get("dot_per_turn", 0))
	se.clear_on_rest = bool(cfg.get("clear_on_rest", false))
	unit.status_effects.append(se)
	return _ev(CombatEvent.Type.STATUS_APPLIED, "", unit.character_id, 0, false, false, status_id, se.stacks)

# ───────────────────────── ATB ─────────────────────────

## ATB 行动顺序（供 M2 顺序条）：按集气速率(effective_charge_rate)降序
func action_order() -> Array[String]:
	var list: Array[CombatCharacter] = [state.player]
	list.append_array(state.enemies)
	list.sort_custom(func(a: CombatCharacter, b: CombatCharacter) -> bool:
		return a.effective_charge_rate() > b.effective_charge_rate())
	var ids: Array[String] = []
	for u in list:
		ids.append(u.character_id)
	return ids

# ───────────────────────── 内部 ─────────────────────────

func _resolve(target_id: String) -> CombatCharacter:
	if target_id != "":
		for e in state.enemies:
			if e.character_id == target_id and e.is_alive():
				return e
	var alive: Array[CombatCharacter] = state.get_alive_enemies()
	return alive[0] if not alive.is_empty() else null

## 命中结算：闪避 → 伤害(防御减伤 + 暴击 + 伤害倍率) → 写血；返回事件流
func _resolve_hit(attacker: CombatCharacter, target: CombatCharacter, power: int) -> Dictionary:
	var events: Array[CombatEvent] = []
	if target == null or not target.is_alive():
		return {"events": events, "damage": 0, "crit": false, "dodged": true}
	if rng.chance(target.effective_dodge_rate()):
		var ev_dodge := _ev(CombatEvent.Type.DAMAGE, attacker.character_id, target.character_id, 0, false, true)
		ev_dodge.target_hp_after = target.hp
		ev_dodge.target_max_hp = target.max_hp
		events.append(ev_dodge)
		return {"events": events, "damage": 0, "crit": false, "dodged": true}
	var dmg: int = max(1, power - int(target.effective_defense() * 0.5))
	var crit: bool = rng.chance(attacker.effective_crit_rate())
	if crit:
		dmg = int(dmg * attacker.crit_damage)
	dmg = max(1, int(float(dmg) * target.damage_taken_mult))
	target.hp = max(0, target.hp - dmg)
	var ev_hit := _ev(CombatEvent.Type.DAMAGE, attacker.character_id, target.character_id, dmg, crit, false)
	ev_hit.target_hp_after = target.hp
	ev_hit.target_max_hp = target.max_hp
	events.append(ev_hit)
	return {"events": events, "damage": dmg, "crit": crit, "dodged": false}

func _try_down(target: CombatCharacter, events: Array[CombatEvent]) -> void:
	if target.hp <= 0 and target.is_alive():
		if target.can_be_downed and not target.is_player:
			target.is_downed = true
		else:
			target.is_dead = true

func _ev(type_: int, actor: String = "", target: String = "", val: int = 0,
		crit: bool = false, dodged: bool = false, status_id: String = "",
		stacks: int = 0, skill_id: String = "") -> CombatEvent:
	var e := CombatEvent.new()
	e.type = type_; e.actor_id = actor; e.target_id = target; e.value = val
	e.crit = crit; e.dodged = dodged; e.status_id = status_id; e.stacks = stacks; e.skill_id = skill_id
	return e

func _get_status_cfg(id: String) -> Dictionary:
	if _status_db.is_empty():
		var f := FileAccess.open("res://data/configs/abilities/status_effects.json", FileAccess.READ)
		if f != null:
			var txt := f.get_as_text(); f.close()
			var parsed = JSON.parse_string(txt)
			if parsed != null:
				for s in parsed.get("status_effects", []):
					_status_db[s.get("id", "")] = s
	return _status_db.get(id, {})
