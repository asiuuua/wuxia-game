# services/combat/combat_service.gd
# 回合制战斗服务（规范 §5）：构建战斗状态、玩家行动、敌人 AI、结算与奖励回写
# 通过 EventBus 通知结果；不持有任何 Node 引用（业务层铁律）

extends RefCounted
class_name CombatService

var _state: CombatState = null
var _core: CombatCore = null   # 战斗逻辑内核（M1 起接管流程编排与结算）
var _escaped: bool = false   # 本场战斗是否以逃跑结束（finalize 据此判定结果）

## 取内核（测试可注入固定 seed 验证确定性）
func get_core() -> CombatCore:
	return _core

## 开始战斗：从配置构建玩家与敌人快照
func start_combat(battle_id: String) -> void:
	var battle: Dictionary = ConfigManager.get_battle(battle_id)
	if battle.is_empty():
		push_error("[Combat] 战斗配置不存在: %s" % battle_id)
		return
	var ps: PlayerState = GameManager.player_state
	var state := CombatState.new()
	state.combat_id = battle_id
	state.is_active = true
	state.combat_type = CombatEnums.CombatType.ENCOUNTER
	state.turn_mode = CombatEnums.TurnMode.get(String(battle.get("turn_mode", "SEQUENTIAL")).to_upper())

	# 难度修正：从 DifficultyManager 读取倍率（代码零 if 难度判断），注入到战斗单位
	var pdm: float = DifficultyManager.get_player_damage_scale()
	var edm: float = DifficultyManager.get_enemy_damage_scale()
	var ehp: float = DifficultyManager.get_enemy_hp_scale()
	var earm: float = DifficultyManager.get_enemy_armor_scale()
	var allow_nl: bool = DifficultyManager.get_allow_non_lethal()
	_escaped = false

	var pc := CombatCharacter.new()
	pc.character_id = "player"
	pc.name_key = "player_name"
	pc.is_player = true
	pc.max_hp = ps.max_hp; pc.hp = ps.hp
	pc.max_mp = ps.max_mp; pc.mp = ps.mp
	pc.attack = ps.attack
	pc.defense = ps.defense
	pc.crit_rate = ps.crit_rate
	pc.crit_damage = ps.crit_damage
	pc.dodge_rate = ps.dodge_rate
	pc.speed = 10                     # 玩家集气速率基线（后续接 PlayerState.speed）
	pc.damage_taken_mult = edm
	state.player = pc

	for enemy_id in battle.get("enemy_ids", []):
		var edata: Dictionary = ConfigManager.get_enemy(enemy_id)
		if edata.is_empty():
			continue
		var ec := CombatCharacter.new()
		ec.character_id = enemy_id
		ec.name_key = enemy_id
		ec.max_hp = int(edata.get("hp", 40) * ehp); ec.hp = ec.max_hp
		ec.max_mp = 30; ec.mp = 30
		ec.attack = edata.get("attack", 10)
		ec.defense = int(ec.attack * 0.5 * earm)
		ec.damage_taken_mult = pdm
		ec.can_be_downed = allow_nl
		ec.speed = int(edata.get("speed", 8))   # 消费 enemies.json.speed（此前全工程无人读取）
		ec.ai_kit = _normalize_abilities(edata.get("abilities", []))   # M3：AI 技能包归一化（字符串→{id,weight,condition}）
		state.enemies.append(ec)
	_state = state
	# 内核接管后续流程编排与结算；seed=0 由内核按时间派生（测试可改 get_core().rng.configure）
	_core = CombatCore.new()
	_core.configure(state)
	EventBus.combat_started.emit(battle_id)
	print("[Combat] 战斗开始: %s，敌人 %d，模式 %s" % [battle_id, state.enemies.size(), "ATB" if state.turn_mode == CombatEnums.TurnMode.ATB else "顺序"])

## 玩家普通攻击（门面：委托内核，返回首个伤害事件摘要供旧调用方兼容）
func player_attack(target_id: String = "") -> Dictionary:
	if _state == null or not _state.is_active:
		return {}
	var events: Array[CombatEvent] = _core.player_basic(target_id)
	return _events_to_res(events)

## 玩家施展快捷栏武学（门面：委托内核技能结算）
func player_cast(slot: int, target_id: String = "") -> Dictionary:
	if _state == null or not _state.is_active:
		return {}
	var events: Array[CombatEvent] = _core.player_skill(slot, target_id)
	return _events_to_res(events)

## 玩家调息（rest）：回血回真气
func player_rest() -> Array[CombatEvent]:
	if _state == null or not _state.is_active:
		return []
	return _core.player_rest()

## 玩家战斗内使用物品（消耗品）：作用于战斗内玩家快照，finalize 时随 hp/mp 回写 PlayerState
## 注意：不可直接调 InventoryService.use_item（那会结算到 PlayerState，战斗面板不会刷新，
## 且结算回写时快照会覆盖掉 PlayerState 上的恢复量——吃过药等于白吃）
func player_use_item(instance_id: String) -> Dictionary:
	if _state == null or not _state.is_active:
		return { "ok": false, "reason": "NOT_IN_COMBAT", "item_id": "" }
	var inv: InventoryService = GameManager.inventory_service
	var inst: ItemInstance = inv.get_instance_by_id(instance_id)
	if inst == null:
		return { "ok": false, "reason": "NOT_FOUND", "item_id": "" }
	var item_id: String = inst.item_id
	var data: Dictionary = ConfigManager.get_item(item_id)
	var is_consumable: bool = (not data.is_empty()) and (data.get("type", "") == "pill" \
			or (int(data.get("flags", 0)) & ItemEnums.ItemFlag.CONSUMABLE) != 0)
	if not is_consumable:
		return { "ok": false, "reason": "NOT_CONSUMABLE", "item_id": item_id }
	if not inv.consume_instance(instance_id):
		return { "ok": false, "reason": "CONSUME_FAILED", "item_id": item_id }
	var healed: int = 0
	var restored: int = 0
	var heal_hp: int = int(data.get("heal_hp", 0))
	var heal_mp: int = int(data.get("heal_mp", 0))
	if heal_hp > 0:
		healed = mini(heal_hp, _state.player.max_hp - _state.player.hp)
		_state.player.hp = mini(_state.player.max_hp, _state.player.hp + heal_hp)
	if heal_mp > 0:
		restored = mini(heal_mp, _state.player.max_mp - _state.player.mp)
		_state.player.mp = mini(_state.player.max_mp, _state.player.mp + heal_mp)
	var effect := { "hp": healed, "mp": restored }
	_state.append_log("李十五 服下 %s：气血 +%d，内力 +%d" % [data.get("name", item_id), healed, restored])
	EventBus.item_used.emit(item_id, effect)
	return { "ok": true, "reason": "SUCCESS", "item_id": item_id, "effect": effect }

## 敌人回合（门面：委托内核，逐事件写日志）
func run_enemy_turns() -> void:
	if _state == null:
		return
	var events: Array[CombatEvent] = _core.enemy_phase()
	for e in events:
		if e.type == CombatEvent.Type.DAMAGE and e.target_id == "player" and e.value > 0:
			_state.append_log("%s 攻击李十五，造成 %d 伤害%s" % [e.actor_id, e.value, "（暴击）" if e.crit else ""])

# ───────────────────────── M2 事件流接口（只增不改，旧兼容方法保留） ─────────────────────────
## 玩家普攻：返回完整事件流，M2 演出层 play_events 消费（替代 player_attack 的兼容摘要）
func player_attack_events(target_id: String = "") -> Array[CombatEvent]:
	if _state == null or not _state.is_active:
		return []
	return _core.player_basic(target_id)

## 玩家施展快捷栏武学：返回事件流
func player_cast_events(slot: int, target_id: String = "") -> Array[CombatEvent]:
	if _state == null or not _state.is_active:
		return []
	return _core.player_skill(slot, target_id)

## 玩家调息：返回事件流
func player_rest_events() -> Array[CombatEvent]:
	if _state == null or not _state.is_active:
		return []
	return _core.player_rest()

## 敌人阶段：返回事件流
func enemy_phase_events() -> Array[CombatEvent]:
	if _state == null:
		return []
	return _core.enemy_phase()

## 玩家战斗内用药：返回事件流（HEAL/QI_GAIN，带行动后直设值），供 Director 播放
func use_item_events(instance_id: String) -> Array[CombatEvent]:
	var events: Array[CombatEvent] = []
	var res: Dictionary = player_use_item(instance_id)
	if not bool(res.get("ok", false)):
		return events
	var eff: Dictionary = res.get("effect", {})
	var heal: int = int(eff.get("hp", 0))
	var mp: int = int(eff.get("mp", 0))
	if heal > 0:
		var ev_h := _mk_ev(CombatEvent.Type.HEAL, _state.player.character_id, "", heal)
		ev_h.target_hp_after = _state.player.hp
		ev_h.target_max_hp = _state.player.max_hp
		events.append(ev_h)
	if mp > 0:
		var ev_m := _mk_ev(CombatEvent.Type.QI_GAIN, _state.player.character_id, "", mp)
		ev_m.target_mp_after = _state.player.mp
		events.append(ev_m)
	return events

func _resolve_target(target_id: String) -> CombatCharacter:
	if target_id != "":
		for e in _state.enemies:
			if e.character_id == target_id and e.is_alive():
				return e
	var alive: Array[CombatCharacter] = _state.get_alive_enemies()
	return alive[0] if not alive.is_empty() else null

## 归一化敌人 abilities 为 AI 技能包（M3）：向后兼容字符串元素
## 字符串 → {id, weight:1, condition:"always"}；对象 → 透传 {id, weight, condition}
func _normalize_abilities(raw: Array) -> Array:
	var out: Array = []
	for a in raw:
		if typeof(a) == TYPE_STRING:
			if a != "":
				out.append({"id": a, "weight": 1.0, "condition": "always"})
		elif a is Dictionary:
			var id: String = a.get("id", "")
			if id != "":
				out.append({"id": id, "weight": float(a.get("weight", 1.0)), "condition": a.get("condition", "always")})
	return out

func is_over() -> bool:
	return _state == null or _state.is_over()

func get_result() -> int:
	if _state == null:
		return CombatEnums.CombatResult.NONE
	if _escaped:
		return CombatEnums.CombatResult.FLEE
	if _state.player.is_dead:
		return CombatEnums.CombatResult.DEFEAT
	return CombatEnums.CombatResult.VICTORY

func get_state() -> CombatState:
	return _state

## 构造单个战斗事件（M2 事件流接口内部使用）
func _mk_ev(type_: int, actor: String = "", target: String = "", val: int = 0) -> CombatEvent:
	var e := CombatEvent.new()
	e.type = type_; e.actor_id = actor; e.target_id = target; e.value = val
	return e

## 从事件流抽取旧式伤害摘要（兼容仍读 {hit,damage,crit,dodged} 的调用方）
func _events_to_res(events: Array[CombatEvent]) -> Dictionary:
	for e in events:
		if e.type == CombatEvent.Type.DAMAGE:
			return {"hit": not e.dodged, "damage": e.value, "crit": e.crit, "dodged": e.dodged}
	return {"hit": false, "damage": 0, "crit": false, "dodged": false}

## 尝试逃跑：读难度配置（allow_escape / escape_bonus），成功则结束战斗并广播，失败则让敌人反击
## 返回 true 表示已脱身（调用方应停止后续行动并显示结果）
func try_escape() -> bool:
	if _state == null or not _state.is_active:
		return false
	if not DifficultyManager.get_allow_escape():
		EventBus.notify_escape_fail.emit()
		return false
	var chance: float = clampf(0.5 + DifficultyManager.get_escape_bonus(), 0.05, 0.95)
	if randf() < chance:
		_escaped = true
		EventBus.notify_escape_success.emit()
		finalize()
		return true
	EventBus.notify_escape_fail.emit()
	return false

## 结算：写回玩家 hp/mp、发放奖励、发事件（只调用一次）
## 不再直接调用任务模块——改为对外广播 combat_finished 快照事件，由任务系统订阅判定
func finalize() -> void:
	if _state == null or not _state.is_active:
		return
	_state.is_active = false
	var ps: PlayerState = GameManager.player_state
	var result: int = get_result()
	_state.result = result
	ps.hp = _state.player.hp
	ps.mp = _state.player.mp
	var victory: bool = (result == CombatEnums.CombatResult.VICTORY)
	var escaped: bool = (result == CombatEnums.CombatResult.FLEE)
	if victory:
		_grant_rewards()
	else:
		ps.hp = max(1, ps.hp)   # 败北留一口气，避免软锁
	EventBus.player_hp_changed.emit(ps.hp, ps.max_hp)
	EventBus.player_mp_changed.emit(ps.mp, ps.max_mp)
	EventBus.combat_ended.emit(_state.combat_id, result)
	# 对外广播战斗结果 + 全单位状态快照（任务系统据此判定，规避时序 BUG）
	EventBus.combat_finished.emit(_state.combat_id, victory, escaped, _build_snapshots())
	# 团灭：通知 DefeatHandler 按难度配置执行死亡惩罚（EASY 回安全点 / 读档 / 删档等）
	if result == CombatEnums.CombatResult.DEFEAT:
		EventBus.notify_player_party_wiped_out.emit()

func _grant_rewards() -> void:
	var ps: PlayerState = GameManager.player_state
	var battle: Dictionary = ConfigManager.get_battle(_state.combat_id)
	if battle.get("reward_exp", 0) > 0:
		ps.gain_exp(battle["reward_exp"])
	for enemy in _state.enemies:
		var edata: Dictionary = ConfigManager.get_enemy(enemy.character_id)
		for loot in edata.get("loot", []):
			GameManager.inventory_service.add_item(loot["item_id"], loot.get("count", 1), "drop:%s" % enemy.character_id)

## 构建参战单位状态快照：任务系统只读快照，不读战斗实时对象（规避时序 BUG）
## 快照元素：{ "unit_id": String, "is_player": bool, "status": int }
func _build_snapshots() -> Array:
	var snaps: Array = []
	snaps.append({"unit_id": "player", "is_player": true, "status": GameState.UnitStatus.ALIVE if _state.player.is_alive() else GameState.UnitStatus.DEAD})
	for enemy in _state.enemies:
		var status: int = GameState.UnitStatus.ALIVE if enemy.is_alive() else GameState.UnitStatus.DEAD
		snaps.append({"unit_id": enemy.character_id, "is_player": false, "status": status})
	return snaps
