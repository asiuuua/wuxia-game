# services/combat/combat_service.gd
# 回合制战斗服务（规范 §5）：构建战斗状态、玩家行动、敌人 AI、结算与奖励回写
# 通过 EventBus 通知结果；不持有任何 Node 引用（业务层铁律）

extends RefCounted
class_name CombatService

var _state: CombatState = null
var _core: CombatCore = null   # 战斗逻辑内核（M1 起接管流程编排与结算）
var _escaped: bool = false   # 本场战斗是否以逃跑结束（finalize 据此判定结果）
var _grid_meta: Dictionary = {}   # 战棋底图元数据：{view_mode, background, pan_x, pan_y, zoom}（编辑器写入，渲染层读取）

## 取内核（测试可注入固定 seed 验证确定性）
func get_core() -> CombatCore:
	return _core

## 取战棋底图元数据（view_mode / background），供 TacticalBattleScene 传给 BattleGridNode 渲染底图。
## 缺省空字典（iso + 无底图，向后兼容）。
func get_grid_meta() -> Dictionary:
	return _grid_meta

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
	pc.speed = ps.agility             # 集气速率由敏捷派生（去魔法数；原硬编码 10，与敏捷基线一致）
	pc.damage_taken_mult = edm
	state.player = pc

	var _seen: Dictionary = {}
	for enemy_id in battle.get("enemy_ids", []):
		var edata: Dictionary = ConfigManager.get_enemy(enemy_id)
		if edata.is_empty():
			continue
		var uid: String = enemy_id
		if _seen.has(enemy_id):
			_seen[enemy_id] += 1
			uid = "%s#%d" % [enemy_id, _seen[enemy_id]]
		else:
			_seen[enemy_id] = 0
		var ec := CombatCharacter.new()
		ec.character_id = uid
		ec.name_key = enemy_id
		ec.max_hp = int(edata.get("hp", 40) * ehp); ec.hp = ec.max_hp
		ec.max_mp = int(edata.get("max_mp", 30)); ec.mp = ec.max_mp  # 敌真气上限取 enemies.json（缺省 30）
		ec.attack = edata.get("attack", 10)
		ec.defense = int(ec.attack * 0.5 * earm)
		ec.damage_taken_mult = pdm
		ec.can_be_downed = allow_nl
		ec.speed = int(edata.get("speed", 8))   # 消费 enemies.json.speed（此前全工程无人读取）
		ec.ai_kit = _normalize_abilities(edata.get("abilities", []))   # M3：AI 技能包归一化（字符串→{id,weight,condition}）
		state.enemies.append(ec)
	# 组队 / 友方 NPC（胜负修正 + 7.3.1）：把战斗配置 allies 与玩家 companion_ids 纳入玩家方
	# —— 这些单位与主角同属"玩家方"，单独阵亡不再判负；主角与它们全部阵亡才判负
	_build_player_side(battle, ps, edm, state)
	_state = state
	# 内核接管后续流程编排与结算；seed=0 由内核按时间派生（测试可改 get_core().rng.configure）
	_core = CombatCore.new()
	_core.configure(state)
	# 战术战棋：构建网格并部署单位（纯增量，非战棋战斗无 tactical 标志则跳过）
	var grid_cfg: Dictionary = battle.get("grid", {})
	if bool(battle.get("tactical", false)):
		_build_grid(grid_cfg, battle)
	EventBus.combat_started.emit(battle_id)
	GameLogger.info("Combat", "战斗开始: %s，敌人 %d，模式 %s" % [battle_id, state.enemies.size(), "ATB" if state.turn_mode == CombatEnums.TurnMode.ATB else "顺序"])

## 构建玩家方友军：战斗配置 allies（数据模板复用 enemies.json，可带战斗属性）与玩家 companion_ids（存档同伴）
## 全部以 is_player=true 加入 player_party，与主角同属"玩家方"——胜负判定、敌人 AI 集火、回合序列都含它们。
## 单玩家战斗（无 allies 且无 companion）则 player_party 为空，行为完全不变（向后兼容）。
func _build_player_side(battle: Dictionary, ps: PlayerState, edm: float, st: CombatState) -> void:
	var ids: Array = []
	for aid in battle.get("allies", []):
		if String(aid) != "" and not (String(aid) in ids):
			ids.append(String(aid))
	for cid in ps.companion_ids:
		if String(cid) != "" and not (String(cid) in ids):
			ids.append(String(cid))
	for uid in ids:
		var ch := CombatCharacter.new()
		ch.character_id = uid
		ch.is_player = true
		var edata: Dictionary = ConfigManager.get_enemy(uid)
		if not edata.is_empty():
			ch.name_key = uid
			ch.max_hp = int(edata.get("hp", 60)); ch.hp = ch.max_hp
			ch.max_mp = int(edata.get("max_mp", 30)); ch.mp = ch.max_mp
			ch.attack = int(edata.get("attack", 10))
			ch.defense = int(ch.attack * 0.5)
			ch.crit_rate = float(edata.get("crit_rate", 0.05))
			ch.speed = int(edata.get("speed", 8))
		else:
			# 无敌人模板：用主角属性的弱化版兜底，保证可参战（存档 companion 未配战斗数据时）
			ch.name_key = uid
			ch.max_hp = int(ps.max_hp * 0.7); ch.hp = ch.max_hp
			ch.max_mp = int(ps.max_mp * 0.7); ch.mp = ch.max_mp
			ch.attack = int(ps.attack * 0.8)
			ch.defense = int(ps.defense * 0.8)
			ch.speed = ps.agility
		ch.damage_taken_mult = edm   # 与主角一致：承受敌人伤害按敌伤倍率缩放
		st.player_party.append(ch)

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
## 注意：战斗中禁止用药（产品决策 2026-09-02）。增益请战斗前在背包提前服用。
## 本方法保留壳以兼容调用方，但一律拒绝，不扣物品、不结算。
func player_use_item(instance_id: String) -> Dictionary:
	if _state == null or not _state.is_active:
		return { "ok": false, "reason": "NOT_IN_COMBAT", "item_id": "" }
	return { "ok": false, "reason": "NOT_ALLOWED_IN_BATTLE", "item_id": "" }

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
## actor_id 默认主角；组队模式下可指定任意同伴单位（P2 多玩家单位）
func player_attack_events(target_id: String = "", actor_id: String = "player") -> Array[CombatEvent]:
	if _state == null or not _state.is_active:
		return []
	return _core.player_basic(target_id, actor_id)

## 玩家施展快捷栏武学：返回事件流
func player_cast_events(slot: int, target_id: String = "", actor_id: String = "player") -> Array[CombatEvent]:
	if _state == null or not _state.is_active:
		return []
	return _core.player_skill(slot, target_id, actor_id)

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

## 单个敌人行动（回合顺序驱动，ATB 按速度插队使用）：返回事件流
func enemy_act_events(enemy_id: String) -> Array[CombatEvent]:
	if _state == null:
		return []
	return _core.enemy_act(enemy_id)

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
	# 敌方全灭 = 胜利（优先级最高）
	if _state.get_alive_enemies().is_empty():
		return CombatEnums.CombatResult.VICTORY
	# 失败必须"主角 + 全部友方 NPC 同时阵亡"才算（友方 NPC 单独阵亡≠失败；主角阵亡但 NPC 存活≠失败）
	if _state.is_player_side_wiped():
		return CombatEnums.CombatResult.DEFEAT
	return CombatEnums.CombatResult.VICTORY

func get_state() -> CombatState:
	return _state

# ───────────────────────── 战术网格门面（M4 战棋 · 只增不改） ─────────────────────────

func get_grid() -> BattleGrid:
	if _core == null:
		return null
	return _core.grid

func deploy_unit(unit_id: String, pos: Vector2i) -> void:
	if _core != null:
		_core.deploy_unit(unit_id, pos)

func compute_reachable(unit_id: String) -> Array[Vector2i]:
	if _core == null:
		return []
	return _core.compute_reachable(unit_id)

func compute_skill_range(caster_id: String, ability_id: String) -> Array[Vector2i]:
	if _core == null:
		return []
	return _core.compute_skill_range(caster_id, ability_id)

func move_unit(unit_id: String, to_pos: Vector2i) -> Array[CombatEvent]:
	if _core == null:
		return []
	return _core.move_unit(unit_id, to_pos)

func enemy_tactical_plan(enemy_id: String) -> Dictionary:
	if _core == null:
		return {"move_to": Vector2i(-1, -1), "ability_id": "", "target_id": ""}
	return _core.enemy_tactical_plan(enemy_id)

func is_target_in_range(caster_id: String, target_id: String, ability_id: String) -> bool:
	if _core == null:
		return false
	return _core.is_target_in_range(caster_id, target_id, ability_id)

## 从战斗配置构建战术网格（资源驱动·三级几何解析，纯增量，逻辑层零 Node 引用）
## 几何解析优先级：battle.grid(显式内嵌) > battle.layout(引用共享布局) > 当前底图 tactical_layout(底图绑定)
##   —— 满足「任意底图遇到小怪只加载该地图战棋布局、所有底图复用同一套战斗逻辑」
## 部署优先级：battle.grid.deployment > battle.deployment > layout.deployment（单位落点随战斗走）
func _build_grid(grid_cfg: Dictionary, battle: Dictionary) -> void:
	var geom: Dictionary = {}
	if not grid_cfg.is_empty():
		geom = grid_cfg
	else:
		# 退而求其次：战斗内 layout 引用 → 当前底图 tactical_layout
		var layout_id: String = String(battle.get("layout", ""))
		if layout_id == "" and GameManager.current_map_id != "":
			var m: Dictionary = ConfigManager.get_map_layout(GameManager.current_map_id)
			if not m.is_empty() and m.has("tactical_layout"):
				layout_id = String(m["tactical_layout"])
		if layout_id != "":
			geom = ConfigManager.get_battle_layout(layout_id)
	if geom.is_empty():
		push_error("[Combat] 战术战斗缺少网格几何配置: %s（请检查 battle.grid / battle.layout / 底图 tactical_layout）" % _state.combat_id)
		return
	# 战棋底图元数据（编辑器写入）：view_mode(默认 iso) / background(默认空=程序化占位)
	# pan_x/pan_y(像素平移，默认 0) / zoom(缩放倍率，默认 1.0) / rotation(旋转角度，默认 0)：编辑器可调整棋盘位置/大小/朝向
	_grid_meta = {
		"view_mode": String(geom.get("view_mode", "iso")),
		"background": String(geom.get("background", "")),
		"pan_x": int(geom.get("pan_x", 0)),
		"pan_y": int(geom.get("pan_y", 0)),
		"zoom": float(geom.get("zoom", 1.0)),
		"rotation": float(geom.get("rotation", 0)),
		"bg_rotate": bool(geom.get("bg_rotate", false)),
	}
	var g := BattleGrid.new()
	g.width = int(geom.get("width", 10))
	g.height = int(geom.get("height", 8))
	for ob in geom.get("obstacles", []):
		var parts: PackedStringArray = String(ob).split(",")
		if parts.size() >= 2:
			g.set_obstacle(Vector2i(int(parts[0]), int(parts[1])), true)
	# P3：地形高度层（可选，缺省全 0 平面）
	if geom.has("heights"):
		for h in geom["heights"]:
			var hp: PackedStringArray = String(h).split(",")
			if hp.size() >= 3:
				g.set_height(Vector2i(int(hp[0]), int(hp[1])), int(hp[2]))
	_core.set_grid(g)
	# 部署优先级：battle.grid.deployment > battle.deployment > layout.deployment
	var dep: Dictionary = grid_cfg.get("deployment", {})
	if dep.is_empty():
		dep = battle.get("deployment", {})
	if dep.is_empty():
		dep = geom.get("deployment", {})
	if dep.has("player"):
		var pp: Array = dep["player"]
		_core.deploy_unit("player", Vector2i(int(pp[0]), int(pp[1])))
	var player_pos: Vector2i = _core._unit_by_id("player").grid_pos if _core._unit_by_id("player") != null else Vector2i(int(g.width * 0.3), int(g.height * 0.5))
	for e in _state.enemies:
		if dep.has(e.character_id):
			var ep: Array = dep[e.character_id]
			_core.deploy_unit(e.character_id, Vector2i(int(ep[0]), int(ep[1])))
	# 敌人自动补齐：enemy_ids 中未在 deployment 显式落点的，按扫描顺序分配到首个空闲格。
	# 向后兼容：已显式部署的照旧；仅补"没写格子"的敌人（多 NPC 同场 / 快速铺怪用）。
	for e in _state.enemies:
		if _core._unit_by_id(e.character_id) != null:
			continue
		var placed := false
		for yy in range(g.height):
			for xx in range(g.width):
				var c := Vector2i(xx, yy)
				if not g.in_bounds(c) or g.is_obstacle_cell(c):
					continue
				if g.occupant_at(c) != "":
					continue
				_core.deploy_unit(e.character_id, c)
				placed = true
				break
			if placed:
				break
	# 组队同伴部署（7.3.1）：优先用 deployment 显式位置；否则排在主角周围首个可走空闲格。
	# 单玩家模式（player_party 为空）不部署任何同伴，行为完全不变。
	var ally_offsets := [Vector2i(1,0), Vector2i(0,1), Vector2i(-1,0), Vector2i(0,-1), Vector2i(1,1), Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1)]
	for p in _state.player_party:
		var ppos: Vector2i = Vector2i.ZERO
		if dep.has(p.character_id):
			var pa: Array = dep[p.character_id]
			ppos = Vector2i(int(pa[0]), int(pa[1]))
		else:
			for off in ally_offsets:
				var c: Vector2i = player_pos + off
				if g.in_bounds(c) and not g.is_obstacle_cell(c) and g.occupant_at(c) == "":
					ppos = c
					break
			if ppos == Vector2i.ZERO:
				ppos = player_pos
		_core.deploy_unit(p.character_id, ppos)

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
	var roll_ok: bool = false
	if _core != null and _core.rng != null:
		roll_ok = _core.rng.randf() < chance      # 走内核 SeededRNG，保证可复现（非全局 randf）
	else:
		roll_ok = randf() < chance
	if roll_ok:
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
			GameManager.inventory_service.add_item(loot.get("item_id", ""), loot.get("count", 1), "drop:%s" % enemy.character_id)

## 构建参战单位状态快照：任务系统只读快照，不读战斗实时对象（规避时序 BUG）
## 快照元素：{ "unit_id": String, "is_player": bool, "status": int }
func _build_snapshots() -> Array:
	var snaps: Array = []
	snaps.append({"unit_id": "player", "is_player": true, "status": GameState.UnitStatus.ALIVE if _state.player.is_alive() else GameState.UnitStatus.DEAD})
	# 玩家方友军（组队同伴 / 友方 NPC）一并纳入快照，供任务判定（它们与主角同属玩家方）
	for p in _state.player_party:
		snaps.append({"unit_id": p.character_id, "is_player": true, "status": GameState.UnitStatus.ALIVE if p.is_alive() else GameState.UnitStatus.DEAD})
	for a in _state.allies:
		snaps.append({"unit_id": a.character_id, "is_player": true, "status": GameState.UnitStatus.ALIVE if a.is_alive() else GameState.UnitStatus.DEAD})
	for enemy in _state.enemies:
		var status: int = GameState.UnitStatus.ALIVE if enemy.is_alive() else GameState.UnitStatus.DEAD
		snaps.append({"unit_id": enemy.character_id, "is_player": false, "status": status})
	return snaps
