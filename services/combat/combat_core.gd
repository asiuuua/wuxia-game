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

## 玩家普攻 → 返回本次行动的事件流（actor_id 默认主角；组队模式下可为任意同伴单位）
func player_basic(target_id: String = "", actor_id: String = "player") -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if state == null or not state.is_active:
		return events
	var actor: CombatCharacter = _unit_by_id(actor_id)
	if actor == null or not actor.is_alive():
		return events
	var target: CombatCharacter = _resolve(target_id)
	if target == null:
		return events
	events.append_array(tick_unit(actor))            # 自己回合开始先 tick 自身状态
	events.append(_ev(CombatEvent.Type.ACTION_BASIC, actor.character_id, target.character_id))
	var res: Dictionary = _resolve_hit(actor, target, actor.effective_attack())
	events.append_array(res.events)
	_try_down(target, events)
	return events

## 玩家招式（slot=快捷栏位）→ 返回事件流（含真气消耗 / 冷却 / 状态施加）
## 复用 _cast_skill 与敌人共用同一套施法结算，行为零变化（双闸门保护）
## actor_id 默认主角；组队模式下可为任意同伴单位（其招式取自共享快捷栏，组队独立配装为后续增量）
func player_skill(slot: int, target_id: String = "", actor_id: String = "player") -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if state == null or not state.is_active:
		return events
	var actor: CombatCharacter = _unit_by_id(actor_id)
	if actor == null or not actor.is_alive():
		return events
	if slot < 0 or slot >= GameManager.ability_service.equipped_combat.size():
		return events
	var ability_id: String = GameManager.ability_service.equipped_combat[slot]
	if ability_id == "":
		return events
	events.append_array(tick_unit(actor))          # 自己回合开始先 tick（含冷却递减）
	events.append_array(_cast_skill(actor, ability_id, target_id, slot))
	return events

## 通用施法结算（玩家 / 敌人共用）：真气消耗 + 冷却 + 目标解析 + 伤害 + 状态施加
## 返回事件流。mp 不足 / 冷却中 / 配置缺失 → 返回空（调用方据此普攻兜底）
## 修复：self / all_allies 目标（调息 / 心法 / 轻功等自buff）只施加状态、不再对自身造成 power 伤害
func _cast_skill(caster: CombatCharacter, ability_id: String, primary_target_id: String = "", slot: int = -1) -> Array[CombatEvent]:
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
		# 桥接大世界 HUD 技能栏实时冷却读秒（玩家施展且带 slot 时）：战斗计冷却(回合) → 大世界读秒(秒) 1:1 近似
		if caster.is_player and slot >= 0:
			GameManager.ability_service.set_cooldown(slot, float(cd))
	events.append(_ev(CombatEvent.Type.ACTION_SKILL, caster.character_id, primary_target_id, 0, false, false, "", 0, ability_id))
	var cfg_target: String = cfg.get("target", "enemy")
	var is_self: bool = (cfg_target == "self" or cfg_target == "all_allies")
	var targets: Array[CombatCharacter] = []
	if cfg_target == "all_enemies":
		# 玩家方招式打全体敌人；敌人招式打全体玩家方（组队模式下含同伴）—— 不再写死单人主角
		targets = state.get_alive_enemies() if caster.is_player else _alive_player_side()
	elif is_self:
		targets = [caster]
	else:
		var t: CombatCharacter = _resolve(primary_target_id) if caster.is_player else _pick_player_target(caster)
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

## 敌人阶段：所有存活敌人按当前回合序列依次行动（ATB 按速度插队，SEQUENTIAL 玩家先）
## M3：每个敌人先用 _pick_enemy_ability 按权重 + 条件选招，无可用招则普攻兜底
func enemy_phase() -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if state == null:
		return events
	for eid in get_round_sequence():
		if eid == "player":
			continue
		var enemy: CombatCharacter = _enemy_by_id(eid)
		if enemy == null or not enemy.is_alive():
			continue
		events.append_array(enemy_act(eid))
		if state.is_over():
			break
	return events

## 单个敌人行动（供回合顺序驱动）：tick → 选招 / 普攻兜底 → 结算玩家受伤
## 组队模式：目标在玩家方（主角 + 存活同伴）中按"最低气血"选取，不再写死 state.player
func enemy_act(enemy_id: String) -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	if state == null:
		return events
	var enemy: CombatCharacter = _enemy_by_id(enemy_id)
	if enemy == null or not enemy.is_alive():
		return events
	events.append(_ev(CombatEvent.Type.TURN_START, enemy.character_id))
	events.append_array(tick_unit(enemy))            # 含冷却递减
	if not enemy.is_alive():
		return events
	var target: CombatCharacter = _pick_player_target(enemy)
	if target == null:
		return events
	var ab: Dictionary = _pick_enemy_ability(enemy, grid != null, target.character_id)
	if ab.is_empty():
		# 普攻兜底（ACTION_BASIC + DAMAGE）
		events.append(_ev(CombatEvent.Type.ACTION_BASIC, enemy.character_id, target.character_id))
		var res: Dictionary = _resolve_hit(enemy, target, enemy.effective_attack())
		events.append_array(res.events)
	else:
		events.append_array(_cast_skill(enemy, ab.get("id", ""), target.character_id))
	_try_down(target, events)
	return events

func _enemy_by_id(enemy_id: String) -> CombatCharacter:
	for e in state.enemies:
		if e.character_id == enemy_id:
			return e
	return null

## 敌人选目标：玩家方（主角 + 存活同伴）中优先打"最低气血"（集火弱者）；无存活玩家方单位返回 null
func _pick_player_target(_enemy: CombatCharacter) -> CombatCharacter:
	var best: CombatCharacter = null
	if state.player != null and state.player.is_alive():
		best = state.player
	for p in state.player_party:
		if p.is_alive() and (best == null or p.hp < best.hp):
			best = p
	return best

## 玩家方（主角 + 存活同伴）全体：供敌人"全体玩家方"类招式锁定（敌人眼里玩家方=敌方阵营）
func _alive_player_side() -> Array[CombatCharacter]:
	var list: Array[CombatCharacter] = []
	if state.player != null and state.player.is_alive():
		list.append(state.player)
	for p in state.player_party:
		if p.is_alive():
			list.append(p)
	return list

## 按权重从敌人 AI 技能包里选一个可用招式（确定性：rng.randf() 由内核 seed 驱动）
## 返回 {id, weight, condition} 或空字典（无可用的 → 调用方普攻兜底）
## respect_range=true（网格战术模式）：额外要求"技能射程内能命中玩家方目标"，杜绝够不到仍出手的越界施法（P2-8）
## respect_range=false（经典模式 / grid==null）：与原逻辑完全一致
## target_id：本回合敌人锁定的玩家方目标（组队模式下可为任意同伴）；为空时退回主角
func _pick_enemy_ability(enemy: CombatCharacter, respect_range: bool = false, target_id: String = "") -> Dictionary:
	if enemy.ai_kit == null or enemy.ai_kit.is_empty():
		return {}
	var tgt_id: String = target_id if target_id != "" else state.player.character_id
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
		if respect_range and grid != null and not is_target_in_range(enemy.character_id, tgt_id, id):
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
			_try_down(unit, events)        # 修致命 DoT 缺口：毒/灼致死也应触发死亡/复活
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
	var stype: int = CombatEnums.EffectType.get(cfg.get("type", "BUFF"))
	# SHIELD 特例：直接累加到 unit.shield 资源，不登记 StatusEffect（避免到期误扣已消耗护盾）
	if stype == CombatEnums.EffectType.SHIELD:
		var add: int = int(cfg.get("value", 0)) * stacks
		unit.shield = min(unit.shield + add, unit.max_hp)
		return _ev(CombatEvent.Type.STATUS_APPLIED, "", unit.character_id, 0, false, false, status_id, stacks)
	for se in unit.status_effects:
		if se.effect_id == status_id:
			se.stacks = min(se.max_stacks, se.stacks + stacks)
			se.remaining = max(se.remaining, int(cfg.get("duration", 2)))
			return _ev(CombatEvent.Type.STATUS_APPLIED, "", unit.character_id, 0, false, false, status_id, se.stacks)
	var se := StatusEffect.new()
	se.effect_id = status_id
	se.name_key = cfg.get("name", status_id)
	se.type = stype
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

## ATB 行动顺序（供 M2 顺序条）：按集气速率(effective_charge_rate)降序（仅存活单位，含组队同伴）
func action_order() -> Array[String]:
	var list: Array[CombatCharacter] = [state.player]
	for p in state.player_party:
		if p.is_alive():
			list.append(p)
	for e in state.enemies:
		if e.is_alive():
			list.append(e)
	list.sort_custom(func(a: CombatCharacter, b: CombatCharacter) -> bool:
		return a.effective_charge_rate() > b.effective_charge_rate())
	var ids: Array[String] = []
	for u in list:
		ids.append(u.character_id)
	return ids

## 单回合行动序列（供演出层回合驱动）：
## SEQUENTIAL → 玩家先、再按编成顺序的存活敌人；ATB → 按 effective_charge_rate 降序（速度插队）
func get_round_sequence() -> Array[String]:
	var actors: Array[CombatCharacter] = [state.player]
	for p in state.player_party:
		if p.is_alive():
			actors.append(p)
	for e in state.enemies:
		if e.is_alive():
			actors.append(e)
	if state.turn_mode == CombatEnums.TurnMode.ATB:
		actors.sort_custom(func(a: CombatCharacter, b: CombatCharacter) -> bool:
			return a.effective_charge_rate() > b.effective_charge_rate())
	var ids: Array[String] = []
	for a in actors:
		ids.append(a.character_id)
	return ids

# ───────────────────────── 战术网格（M4 战棋）─────────────────────────
# 网格只做"目标过滤 / 可移动范围"，绝不改动 _resolve_hit 的伤害结算。
# 移动是单位行动内的子动作（先走位再出招），不单独消耗回合。

var grid: BattleGrid = null   # 战术网格数据层（非战棋战斗为 null）

func set_grid(g: BattleGrid) -> void:
	grid = g

func _unit_by_id(uid: String) -> CombatCharacter:
	if state == null:
		return null
	if state.player != null and state.player.character_id == uid:
		return state.player
	for p in state.player_party:
		if p.character_id == uid:
			return p
	for e in state.enemies:
		if e.character_id == uid:
			return e
	return null

## 部署单位到网格：设坐标 + 占格（重部署先清旧格）
func deploy_unit(unit_id: String, pos: Vector2i) -> void:
	var u := _unit_by_id(unit_id)
	if u == null or grid == null:
		return
	grid.clear_occupant(u.grid_pos)
	u.grid_pos = pos
	grid.set_occupant(pos, unit_id)

## 玩家可移动格（BFS 可达，不含自身当前格）
func compute_reachable(unit_id: String) -> Array[Vector2i]:
	var u := _unit_by_id(unit_id)
	if u == null or grid == null:
		return []
	return grid.bfs_reachable(u.grid_pos, u.move_range)

## 技能可染色范围格（菱形/方形/十字/自身），供视图红色高亮
func compute_skill_range(caster_id: String, ability_id: String) -> Array[Vector2i]:
	var u := _unit_by_id(caster_id)
	if u == null or grid == null:
		return []
	var cfg: Dictionary = ConfigManager.get_ability(ability_id)
	if cfg.is_empty():
		return []
	var range_val: int = int(cfg.get("range", 99))
	var shape: String = String(cfg.get("range_shape", "diamond"))
	return grid.skill_range(u.grid_pos, range_val, shape)

## 目标是否在技能射程内（曼哈顿距离 <= range；无 range 配置视为经典模式全可达）
func is_target_in_range(caster_id: String, target_id: String, ability_id: String) -> bool:
	var c := _unit_by_id(caster_id)
	var t := _unit_by_id(target_id)
	if c == null or t == null or grid == null:
		return false
	var cfg: Dictionary = ConfigManager.get_ability(ability_id)
	if cfg.is_empty():
		return true
	var range_val: int = int(cfg.get("range", 99))
	var md: int = abs(c.grid_pos.x - t.grid_pos.x) + abs(c.grid_pos.y - t.grid_pos.y)
	return md <= range_val

## 移动单位到合法落点：校验在可达集合内 → 更新占用表 + 坐标 + 发 GRID_MOVE 事件
func move_unit(unit_id: String, to_pos: Vector2i) -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	var u := _unit_by_id(unit_id)
	if u == null or grid == null:
		return events
	var reach: Array[Vector2i] = grid.bfs_reachable(u.grid_pos, u.move_range)
	if not (to_pos in reach):
		return events   # 非法落点（越界/障碍/他人格）→ 忽略，等待合法点击
	grid.clear_occupant(u.grid_pos)
	grid.set_occupant(to_pos, unit_id)
	var from: Vector2i = u.grid_pos
	u.grid_pos = to_pos
	u.facing = CombatCharacter.calc_facing(from, to_pos)   # P1：朝向只由逻辑坐标差值决定，与地图尺寸无关
	events.append(_ev_move(unit_id, from, to_pos))
	return events

## 敌人战术计划：走位到距玩家最近的可达格，并选一个射程内可用招（否则仅走位普攻）
## 返回 {move_to, ability_id, target_id}；玩家托管与敌人共用本 AI，行为一致
func enemy_tactical_plan(enemy_id: String) -> Dictionary:
	var plan := {"move_to": Vector2i(-1, -1), "ability_id": "", "target_id": ""}
	var e := _enemy_by_id(enemy_id)
	if e == null or not e.is_alive() or grid == null:
		return plan
	var target: CombatCharacter = _pick_player_target(e)
	if target == null or not target.is_alive():
		return plan
	var reach: Array[Vector2i] = grid.bfs_reachable(e.grid_pos, e.move_range)
	var best: Vector2i = e.grid_pos
	var best_d: int = 999999
	for c in reach:
		var d: int = abs(c.x - target.grid_pos.x) + abs(c.y - target.grid_pos.y)
		if d < best_d:
			best_d = d
			best = c
	plan["move_to"] = best
	plan["target_id"] = target.character_id
	for ab in e.ai_kit:
		var aid: String = String(ab.get("id", ""))
		if aid == "":
			continue
		if not _ability_usable(e, aid):
			continue
		if not _condition_met(e, ab.get("condition", "always")):
			continue
		if is_target_in_range(e.character_id, target.character_id, aid):
			plan["ability_id"] = aid
			break
	return plan

func _ev_move(unit_id: String, from: Vector2i, to: Vector2i) -> CombatEvent:
	var e := CombatEvent.new()
	e.type = CombatEvent.Type.GRID_MOVE
	e.actor_id = unit_id
	e.from_grid = from
	e.to_grid = to
	return e

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
	# ── 护盾吸收：伤害先扣盾再扣血，持续到被消耗 ──
	var dealt: int = dmg
	if target.shield > 0:
		var absorbed: int = min(target.shield, dealt)
		target.shield -= absorbed
		dealt -= absorbed
		var ev_sh := _ev(CombatEvent.Type.SHIELD_ABSORB, attacker.character_id, target.character_id, absorbed)
		ev_sh.target_shield_after = target.shield
		ev_sh.target_hp_after = target.hp
		ev_sh.target_max_hp = target.max_hp
		events.append(ev_sh)
	target.hp = max(0, target.hp - dealt)
	var ev_hit := _ev(CombatEvent.Type.DAMAGE, attacker.character_id, target.character_id, dealt, crit, false)
	ev_hit.target_hp_after = target.hp
	ev_hit.target_max_hp = target.max_hp
	events.append(ev_hit)
	# ── 反弹（荆棘）：把所承受伤害的一部分反弹给攻击者（直写，绕过 _resolve_hit 防连锁）──
	if attacker != null and attacker != target and attacker.is_alive():
		var rp: float = _reflect_pct(target)
		if rp > 0.0:
			var r: int = int(dealt * rp)
			if r > 0:
				attacker.hp = max(0, attacker.hp - r)
				_try_down(attacker, events)
				var ev_re := _ev(CombatEvent.Type.REFLECT, target.character_id, attacker.character_id, r)
				ev_re.target_hp_after = attacker.hp
				ev_re.target_max_hp = attacker.max_hp
				events.append(ev_re)
	return {"events": events, "damage": dmg, "crit": crit, "dodged": false}

func _try_down(target: CombatCharacter, events: Array[CombatEvent]) -> void:
	if target.hp <= 0 and target.is_alive():
		# ── 复活（不屈）：消耗一层 REVIVE 状态，原地拉起 ──
		var rv: int = _revive_amount(target)
		if rv > 0:
			target.hp = max(1, rv)
			target.is_dead = false
			target.is_downed = false
			_consume_revive(target)
			var ev_rv := _ev(CombatEvent.Type.REVIVE, target.character_id, target.character_id, target.hp)
			ev_rv.target_hp_after = target.hp
			ev_rv.target_max_hp = target.max_hp
			events.append(ev_rv)
			return
		if target.can_be_downed and not target.is_player:
			target.is_downed = true
		else:
			target.is_dead = true

## 反弹百分比(0.0~1.0)：扫描目标身上 REFLECT 状态，sum(value*stacks)/100
func _reflect_pct(target: CombatCharacter) -> float:
	var total: float = 0.0
	for se in target.status_effects:
		if se.type == CombatEnums.EffectType.REFLECT:
			total += se.value * se.stacks
	return clampf(total / 100.0, 0.0, 1.0)

## 复活量：扫描 REVIVE 状态，返回应复活到的气血（0=无复活）。不消耗。
func _revive_amount(unit: CombatCharacter) -> int:
	for se in unit.status_effects:
		if se.type == CombatEnums.EffectType.REVIVE:
			var v: int = int(se.value)
			if v >= 100:
				return min(v, unit.max_hp)
			return int(unit.max_hp * v / 100.0)
	return 0

## 消耗一层 REVIVE 状态（递归删一层）
func _consume_revive(unit: CombatCharacter) -> void:
	for i in range(unit.status_effects.size() - 1, -1, -1):
		if unit.status_effects[i].type == CombatEnums.EffectType.REVIVE:
			unit.status_effects[i].stacks -= 1
			if unit.status_effects[i].stacks <= 0:
				unit.status_effects.remove_at(i)
			return

func _ev(type_: int, actor: String = "", target: String = "", val: int = 0,
		crit: bool = false, dodged: bool = false, status_id: String = "",
		stacks: int = 0, skill_id: String = "") -> CombatEvent:
	var e := CombatEvent.new()
	e.type = type_; e.actor_id = actor; e.target_id = target; e.value = val
	e.crit = crit; e.dodged = dodged; e.status_id = status_id; e.stacks = stacks; e.skill_id = skill_id
	return e

func _get_status_cfg(id: String) -> Dictionary:
	if _status_db.is_empty():
		# 工业化扩容 P7：经 ConfigManager 集中取用，杜绝硬编码数据路径
		_status_db = ConfigManager.get_status_effect_table()
	return _status_db.get(id, {})
