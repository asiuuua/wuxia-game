# scenes/gameplay/battle/tactical_battle_scene.gd
# 战术战棋场景（战斗窗口主权）：把已落地的逻辑层（BattleGrid / CombatCore 网格扩展 / CombatService 门面）
# 接到表现层。职责：
#   - 等轴测战场：BattleGridNode 画网格 + BattleEntity 站人，Camera2D 居中
#   - 四角 HUD：左下我方状态 / 右下目标卡 / 右上战场条件+自动开关 / 底部行动栏（本窗自绘，不碰全局 HUD 主权）
#   - 输入状态机：IDLE(可点蓝格移动) → 选行动 → AWAIT_TARGET(点红格敌人执行) → 结束回合
#   - 回合驱动：玩家行动 → 敌方阶段（复用 enemy_tactical_plan 走位 + enemy_act_events 结算）
#   - 自动战斗：简易策略（走近最近敌人→普攻），带回合上限防死循环
# ⚠️ 不持有战斗逻辑；伤害结算永远走 CombatCore（经 CombatService 门面）。无战棋网格的战斗不会路由到此场景。

extends Node2D
class_name TacticalBattleScene

const BASIC_RANGE: int = 1     # 普攻射程（曼哈顿<=1，近身）

enum Phase { PLAYER, ENEMY, OVER }
enum Mode { MOVE, AWAIT_TARGET }

var _state: CombatState = null
var _grid: BattleGrid = null
var _grid_node: BattleGridNode = null
var _entities_node: Node2D = null
var _entities: Dictionary = {}      # character_id -> BattleEntity

var _phase: int = Phase.PLAYER
var _mode: int = Mode.MOVE
var _turn: int = 1
var _auto: bool = false
var _busy: bool = false
var _pending: Dictionary = {}       # {kind:"basic"|"cast", ability_id, slot}
var _target_id: String = ""

# HUD 引用
var _hud_player_name: Label
var _hud_player_hp: Label
var _hud_player_mp: Label
var _hud_player_status: Label
var _hud_target_name: Label
var _hud_target_hp: Label
var _hud_conditions: Label
var _action_bar: HBoxContainer
var _auto_btn: Button
var _result_panel: Panel
var _result_label: Label
var _return_btn: Button
var _hint: Label
var _item_menu: PopupMenu
var _item_instance_ids: Array[String] = []

func _ready() -> void:
	GameManager.combat_service.start_combat(GameManager.pending_battle_id)
	_state = GameManager.combat_service.get_state()
	if _state == null:
		_build_fatal("战斗配置缺失，无法开始。")
		return
	_grid = GameManager.combat_service.get_grid()
	if _grid == null:
		_build_fatal("该战斗未配置战术网格，无法进入战棋模式。")
		return
	_build_world()
	_spawn_entities()
	_build_hud()
	EventBus.scene_changed.emit("tactical_battle")
	_turn = 0
	_start_player_turn()

# ───────────────────────── 世界搭建 ─────────────────────────

func _build_world() -> void:
	var bf := Node2D.new()
	bf.name = "Battlefield"
	add_child(bf)
	_grid_node = BattleGridNode.new()
	_grid_node.name = "GridNode"
	_grid_node.set_grid(_grid)
	bf.add_child(_grid_node)
	_entities_node = Node2D.new()
	_entities_node.name = "Entities"
	bf.add_child(_entities_node)
	# 居中：把战场像素中心对齐屏幕中心（根 Node2D 在屏幕左上角，所以直接 offset）
	var vc := get_viewport_rect().size * 0.5
	bf.position = vc - _grid_node.pixel_center()

func _spawn_entities() -> void:
	_spawn_one("player", true, "李十五", _state.player)
	for e in _state.enemies:
		if e.is_alive():
			var nm: String = ConfigManager.get_enemy(e.character_id).get("name", e.character_id)
			_spawn_one(e.character_id, false, nm, e)

func _spawn_one(uid: String, player: bool, nm: String, ch: CombatCharacter) -> void:
	var ent := CombatEntityPool.acquire_entity(uid, player, nm, ch.max_hp, ch.max_mp, _grid_node)
	ent.place_at(ch.grid_pos)
	_entities_node.add_child(ent)
	_entities[uid] = ent

# ───────────────────────── 输入 ─────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if _busy or _phase != Phase.PLAYER:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var local := _grid_node.to_local(get_global_mouse_position())
		var gp := _grid_node.world_to_grid(local)
		_on_cell_clicked(gp)

func _on_cell_clicked(gp: Vector2i) -> void:
	if not _grid.in_bounds(gp):
		return
	if _mode == Mode.MOVE:
		var reach: Array[Vector2i] = GameManager.combat_service.compute_reachable("player")
		if gp in reach:
			_busy = true
			var evs: Array[CombatEvent] = GameManager.combat_service.move_unit("player", gp)
			await _play_events(evs)
			_busy = false
			_show_reachable()
			_refresh_hud()
	elif _mode == Mode.AWAIT_TARGET:
		if gp == _state.player.grid_pos:
			# 点击自身格 = 取消，回到移动模式
			_pending = {}
			_mode = Mode.MOVE
			_show_reachable()
			_refresh_hud()
			return
		var occ: String = _grid.occupant_at(gp)
		if occ != "" and occ != "player" and _is_alive(occ) and _target_valid(occ):
			_execute_pending_on(occ)

# ───────────────────────── 行动执行 ─────────────────────────

func _on_basic_pressed() -> void:
	if _busy or _phase != Phase.PLAYER:
		return
	_pending = {"kind": "basic"}
	_mode = Mode.AWAIT_TARGET
	_show_melee_range()

func _on_skill_pressed(slot: int, ability_id: String) -> void:
	if _busy or _phase != Phase.PLAYER:
		return
	var cfg: Dictionary = ConfigManager.get_ability(ability_id)
	var target_kind: String = String(cfg.get("target", "enemy"))
	if target_kind == "self" or target_kind == "all_allies" or int(cfg.get("range", 99)) == 0:
		# 自身/群体增益：立即执行，无需选目标
		_busy = true
		var evs: Array[CombatEvent] = GameManager.combat_service.player_cast_events(slot, "player")
		await _play_events(evs)
		_busy = false
		_after_player_action()
	else:
		_pending = {"kind": "cast", "ability_id": ability_id, "slot": slot}
		_mode = Mode.AWAIT_TARGET
		_show_skill_range(ability_id)

func _execute_pending_on(target_id: String) -> void:
	var p: Dictionary = _pending
	_pending = {}
	_mode = Mode.MOVE
	_busy = true
	var evs: Array[CombatEvent]
	if p.get("kind") == "basic":
		evs = GameManager.combat_service.player_attack_events(target_id)
	else:
		evs = GameManager.combat_service.player_cast_events(int(p.get("slot", 0)), target_id)
	await _play_events(evs)
	_busy = false
	_after_player_action()

func _target_valid(target_id: String) -> bool:
	if _pending.get("kind") == "basic":
		var t: CombatCharacter = _unit_by_state(target_id)
		if t == null:
			return false
		var md: int = abs(t.grid_pos.x - _state.player.grid_pos.x) + abs(t.grid_pos.y - _state.player.grid_pos.y)
		return md <= BASIC_RANGE
	var aid: String = _pending.get("ability_id", "")
	if aid == "":
		return false
	return GameManager.combat_service.is_target_in_range("player", target_id, aid)

func _on_item_pressed() -> void:
	if _busy or _phase != Phase.PLAYER:
		return
	_item_menu.clear()
	_item_instance_ids.clear()
	var inv: InventoryService = GameManager.inventory_service
	if inv != null:
		for bag in [inv.main_slots, inv.material_slots]:
			for inst in bag:
				if inst == null:
					continue
				var data: Dictionary = ConfigManager.get_item(inst.item_id)
				if data.is_empty():
					continue
				var is_consumable: bool = data.get("type", "") == "pill" \
						or (int(data.get("flags", 0)) & ItemEnums.ItemFlag.CONSUMABLE) != 0
				if not is_consumable:
					continue
				_item_menu.add_item("%s x%d" % [data.get("name", inst.item_id), inst.count])
				_item_instance_ids.append(inst.instance_id)
	if _item_instance_ids.is_empty():
		_item_menu.add_item("没有可用药品")
		_item_instance_ids.append("")
	_item_menu.popup_centered(Vector2i(360, 220))

func _on_item_menu_index(index: int) -> void:
	if _busy or _phase != Phase.PLAYER or index >= _item_instance_ids.size():
		return
	var iid: String = _item_instance_ids[index]
	if iid == "":
		return
	_busy = true
	var evs: Array[CombatEvent] = GameManager.combat_service.use_item_events(iid)
	await _play_events(evs)
	_busy = false
	_after_player_action()

func _on_end_turn_pressed() -> void:
	if _busy or _phase != Phase.PLAYER:
		return
	_pending = {}
	_mode = Mode.MOVE
	_start_enemy_phase()

func _on_auto_pressed() -> void:
	_auto = not _auto
	if _auto_btn != null:
		_auto_btn.text = "自动: 开" if _auto else "自动: 关"
	if _auto and _phase == Phase.PLAYER and not _busy:
		_auto_player_turn()

# ───────────────────────── 回合驱动 ─────────────────────────

func _start_player_turn() -> void:
	if GameManager.combat_service.is_over():
		_finish()
		return
	_turn += 1
	_phase = Phase.PLAYER
	_mode = Mode.MOVE
	_target_id = _nearest_alive_enemy_id()
	_show_reachable()
	_refresh_hud()
	if _auto:
		_auto_player_turn()

func _start_enemy_phase() -> void:
	if GameManager.combat_service.is_over():
		_finish()
		return
	_phase = Phase.ENEMY
	_mode = Mode.MOVE
	_pending = {}
	EventBus.grid_highlight_update.emit({})
	_refresh_hud()
	await _enemy_phase_impl()
	if GameManager.combat_service.is_over():
		_finish()
		return
	_start_player_turn()

func _enemy_phase_impl() -> void:
	var seq: Array[String] = GameManager.combat_service.get_core().get_round_sequence()
	for eid in seq:
		if eid == "player":
			continue
		if not _is_alive(eid):
			continue
		var plan: Dictionary = GameManager.combat_service.enemy_tactical_plan(eid)
		var mv: Vector2i = plan.get("move_to", Vector2i(-1, -1))
		var cur: CombatCharacter = _unit_by_state(eid)
		if cur != null and mv != Vector2i(-1, -1) and mv != cur.grid_pos:
			_busy = true
			var evs: Array[CombatEvent] = GameManager.combat_service.move_unit(eid, mv)
			await _play_events(evs)
			_busy = false
		if GameManager.combat_service.is_over():
			return
		if plan.get("ability_id", "") != "":
			_busy = true
			var evs2: Array[CombatEvent] = GameManager.combat_service.enemy_act_events(eid)
			await _play_events(evs2)
			_busy = false
		if GameManager.combat_service.is_over():
			return
		await _wait(0.15)

func _auto_player_turn() -> void:
	if GameManager.combat_service.is_over():
		_finish()
		return
	if _phase != Phase.PLAYER:
		return
	_busy = true
	var enemy_id: String = _nearest_alive_enemy_id()
	if enemy_id != "":
		var best: Vector2i = _best_move_toward(enemy_id)
		if best != _state.player.grid_pos:
			var evs: Array[CombatEvent] = GameManager.combat_service.move_unit("player", best)
			await _play_events(evs)
	if not GameManager.combat_service.is_over():
		var evs2: Array[CombatEvent] = GameManager.combat_service.player_attack_events("")
		await _play_events(evs2)
	_busy = false
	if GameManager.combat_service.is_over():
		_finish()
		return
	_start_enemy_phase()

func _after_player_action() -> void:
	_pending = {}
	_mode = Mode.MOVE
	_target_id = _nearest_alive_enemy_id()
	_refresh_hud()
	if GameManager.combat_service.is_over():
		_finish()
		return
	_start_enemy_phase()

# ───────────────────────── 高亮 ─────────────────────────

func _show_reachable() -> void:
	var hl := {}
	if _phase == Phase.PLAYER and _mode == Mode.MOVE:
		hl[BattleGridNode.HL_MOVE] = GameManager.combat_service.compute_reachable("player")
		var threat: Array[Vector2i] = []
		for e in _state.enemies:
			if e.is_alive():
				for c in GameManager.combat_service.compute_reachable(e.character_id):
					if not (c in threat):
						threat.append(c)
		hl[BattleGridNode.HL_THREAT] = threat
	EventBus.grid_highlight_update.emit(hl)

func _show_melee_range() -> void:
	var hl := {}
	hl[BattleGridNode.HL_MOVE] = GameManager.combat_service.compute_reachable("player")
	var skill_cells: Array[Vector2i] = []
	for e in _state.enemies:
		if e.is_alive():
			var md: int = abs(e.grid_pos.x - _state.player.grid_pos.x) + abs(e.grid_pos.y - _state.player.grid_pos.y)
			if md <= BASIC_RANGE:
				skill_cells.append(e.grid_pos)
	hl[BattleGridNode.HL_SKILL] = skill_cells
	EventBus.grid_highlight_update.emit(hl)

func _show_skill_range(ability_id: String) -> void:
	var hl := {}
	hl[BattleGridNode.HL_SKILL] = GameManager.combat_service.compute_skill_range("player", ability_id)
	hl[BattleGridNode.HL_MOVE] = GameManager.combat_service.compute_reachable("player")
	EventBus.grid_highlight_update.emit(hl)

# ───────────────────────── 事件播放（驱动实体表现）─────────────────────────

func _play_events(events: Array[CombatEvent]) -> void:
	for ev in events:
		match ev.type:
			CombatEvent.Type.GRID_MOVE:
				var e = _entities.get(ev.actor_id)
				if e != null:
					e.move_to(ev.to_grid)
				await _wait(0.28)
			CombatEvent.Type.DAMAGE:
				var e2 = _entities.get(ev.target_id)
				if e2 != null and ev.target_max_hp > 0:
					e2.set_hp(ev.target_hp_after)
				if ev.dodged:
					_pop(ev.target_id, "Miss", Color(0.8, 0.8, 0.8))
				elif ev.crit:
					_pop(ev.target_id, "-%d!" % ev.value, Color(1.0, 0.85, 0.2))
				elif ev.value > 0:
					_pop(ev.target_id, "-%d" % ev.value, Color(0.95, 0.3, 0.3))
				await _wait(0.12)
			CombatEvent.Type.HEAL:
				var uid: String = ev.target_id if ev.target_id != "" else ev.actor_id
				var e3 = _entities.get(uid)
				if e3 != null and ev.target_max_hp > 0:
					e3.set_hp(ev.target_hp_after)
				_pop(uid, "+%d" % ev.value, Color(0.4, 0.95, 0.5))
				await _wait(0.1)
			CombatEvent.Type.QI_COST:
				var e4 = _entities.get(ev.actor_id)
				if e4 != null:
					e4.set_mp(ev.actor_mp_after)
				await _wait(0.05)
			CombatEvent.Type.QI_GAIN:
				var uid5: String = ev.target_id if ev.target_id != "" else ev.actor_id
				var e5 = _entities.get(uid5)
				if e5 != null:
					e5.set_mp(ev.target_mp_after)
				await _wait(0.05)
			CombatEvent.Type.STATUS_APPLIED:
				_pop(ev.target_id, "状态", Color(0.6, 0.9, 0.6))
				await _wait(0.05)
			CombatEvent.Type.STATUS_TICK:
				var e6 = _entities.get(ev.target_id)
				if e6 != null and ev.target_max_hp > 0:
					e6.set_hp(ev.target_hp_after)
				_pop(ev.target_id, "%d" % ev.value, Color(0.95, 0.5, 0.2))
				await _wait(0.08)
			CombatEvent.Type.STATUS_EXPIRED:
				_pop(ev.target_id, "解除", Color(0.7, 0.7, 0.7))
				await _wait(0.05)
			CombatEvent.Type.SHIELD_ABSORB:
				_pop(ev.target_id, "盾%d" % ev.value, Color(0.4, 0.95, 0.95))
				await _wait(0.08)
			CombatEvent.Type.REFLECT:
				var e7 = _entities.get(ev.target_id)
				if e7 != null and ev.target_max_hp > 0:
					e7.set_hp(ev.target_hp_after)
				_pop(ev.target_id, "反弹%d" % ev.value, Color(0.85, 0.4, 0.95))
				await _wait(0.08)
			CombatEvent.Type.REVIVE:
				var e8 = _entities.get(ev.target_id)
				if e8 != null and ev.target_max_hp > 0:
					e8.set_hp(ev.target_hp_after)
				_pop(ev.target_id, "复活!", Color(1.0, 0.85, 0.2))
				await _wait(0.1)
			_:
				pass
	_refresh_hud()
	await _wait(0.03)

func _pop(uid: String, txt: String, color: Color) -> void:
	var e = _entities.get(uid)
	if e != null:
		e.pop_text(txt, color)

# ───────────────────────── 结束 ─────────────────────────

func _finish() -> void:
	_phase = Phase.OVER
	EventBus.grid_highlight_update.emit({})
	GameManager.combat_service.finalize()
	_refresh_hud()
	_show_result()

func _show_result() -> void:
	if _result_panel == null:
		return
	_result_panel.visible = true
	var r: int = _state.result
	if r == CombatEnums.CombatResult.VICTORY:
		_result_label.text = "战斗结束：胜利！获得经验与战利品。"
		_return_btn.visible = true
	elif r == CombatEnums.CombatResult.FLEE:
		_result_label.text = "战斗结束：你成功脱身了。"
		_return_btn.visible = true
	else:
		_result_label.text = "战斗结束：你倒下了……"
		_return_btn.visible = false

## 战斗结束回城前：把本场实体归还对象池（脱离父节点 + 清零），供下一场复用
func _release_all() -> void:
	for uid in _entities.keys():
		var ent: BattleEntity = _entities[uid]
		if ent != null:
			CombatEntityPool.release_entity(ent)
	_entities.clear()

func _on_return_pressed() -> void:
	_release_all()
	GameManager.return_to_town()

# ───────────────────────── 工具 ─────────────────────────

func _nearest_alive_enemy_id() -> String:
	var best: String = ""
	var best_d: int = 999999
	for e in _state.enemies:
		if not e.is_alive():
			continue
		var d: int = abs(e.grid_pos.x - _state.player.grid_pos.x) + abs(e.grid_pos.y - _state.player.grid_pos.y)
		if d < best_d:
			best_d = d
			best = e.character_id
	return best

func _best_move_toward(enemy_id: String) -> Vector2i:
	var enemy: CombatCharacter = _unit_by_state(enemy_id)
	if enemy == null:
		return _state.player.grid_pos
	var best: Vector2i = _state.player.grid_pos
	var best_d: int = abs(best.x - enemy.grid_pos.x) + abs(best.y - enemy.grid_pos.y)
	for c in GameManager.combat_service.compute_reachable("player"):
		var d: int = abs(c.x - enemy.grid_pos.x) + abs(c.y - enemy.grid_pos.y)
		if d < best_d:
			best_d = d
			best = c
	return best

func _is_alive(uid: String) -> bool:
	for e in _state.enemies:
		if e.character_id == uid:
			return e.is_alive()
	return false

func _unit_by_state(uid: String) -> CombatCharacter:
	if uid == "player":
		return _state.player
	for e in _state.enemies:
		if e.character_id == uid:
			return e
	return null

func _wait(dur: float) -> void:
	if dur <= 0.0:
		return
	await get_tree().create_timer(dur).timeout

# ───────────────────────── HUD 搭建 ─────────────────────────

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.name = "HUDLayer"
	add_child(cl)
	var hud := Control.new()
	hud.name = "HUDRoot"
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 关键：hud 全屏但不能 STOP 鼠标事件，否则所有按钮/底层网格都收不到输入
	hud.mouse_filter = Control.MOUSE_FILTER_PASS
	cl.add_child(hud)

	# 标题（左上）
	var title := _panel()
	title.anchor_left = 0.0; title.anchor_top = 0.0; title.anchor_right = 0.0; title.anchor_bottom = 0.0
	title.offset_left = 12.0; title.offset_top = 12.0; title.offset_right = 240.0; title.offset_bottom = 48.0
	hud.add_child(title)
	var tl := Label.new()
	tl.text = "竹林遭遇（战棋）"
	tl.position = Vector2(12, 8)
	tl.add_theme_font_size_override("font_size", 16)
	tl.add_theme_color_override("font_color", Color(0.95, 0.9, 0.7))
	title.add_child(tl)

	# 我方状态卡（左下）
	var pp := _panel()
	pp.anchor_left = 0.0; pp.anchor_top = 1.0; pp.anchor_right = 0.0; pp.anchor_bottom = 1.0
	pp.offset_left = 12.0; pp.offset_top = -120.0; pp.offset_right = 220.0; pp.offset_bottom = -12.0
	hud.add_child(pp)
	_hud_player_name = Label.new(); _hud_player_name.position = Vector2(10, 8); pp.add_child(_hud_player_name)
	_hud_player_hp = Label.new(); _hud_player_hp.position = Vector2(10, 30); pp.add_child(_hud_player_hp)
	_hud_player_mp = Label.new(); _hud_player_mp.position = Vector2(10, 50); pp.add_child(_hud_player_mp)
	_hud_player_status = Label.new(); _hud_player_status.position = Vector2(10, 70); pp.add_child(_hud_player_status)
	_hud_player_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

	# 目标卡（右下）
	var tp := _panel()
	tp.anchor_left = 1.0; tp.anchor_top = 1.0; tp.anchor_right = 1.0; tp.anchor_bottom = 1.0
	tp.offset_left = -220.0; tp.offset_top = -96.0; tp.offset_right = -12.0; tp.offset_bottom = -12.0
	hud.add_child(tp)
	_hud_target_name = Label.new(); _hud_target_name.position = Vector2(10, 8); tp.add_child(_hud_target_name)
	_hud_target_hp = Label.new(); _hud_target_hp.position = Vector2(10, 30); tp.add_child(_hud_target_hp)

	# 战场条件 + 自动（右上）
	var cp := _panel()
	cp.anchor_left = 1.0; cp.anchor_top = 0.0; cp.anchor_right = 1.0; cp.anchor_bottom = 0.0
	cp.offset_left = -220.0; cp.offset_top = 12.0; cp.offset_right = -12.0; cp.offset_bottom = 40.0
	hud.add_child(cp)
	_hud_conditions = Label.new(); _hud_conditions.position = Vector2(10, 8); cp.add_child(_hud_conditions)

	# 行动栏（底部居中）
	var bar := HBoxContainer.new()
	bar.name = "ActionBar"
	bar.anchor_left = 0.5; bar.anchor_top = 1.0; bar.anchor_right = 0.5; bar.anchor_bottom = 1.0
	bar.offset_left = -300.0; bar.offset_right = 300.0; bar.offset_top = -56.0; bar.offset_bottom = -12.0
	bar.add_theme_constant_override("separation", 6)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_PASS
	hud.add_child(bar)
	_action_bar = bar
	_build_action_buttons(bar)

	# 提示条（行动栏上方）
	_hint = Label.new()
	_hint.text = "点击蓝格移动；选行动后点击红色高亮敌人执行（点自身格取消）"
	_hint.anchor_left = 0.5; _hint.anchor_top = 1.0; _hint.anchor_right = 0.5; _hint.anchor_bottom = 1.0
	_hint.offset_left = -260.0; _hint.offset_right = 260.0; _hint.offset_top = -78.0; _hint.offset_bottom = -60.0
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(0.85, 0.85, 0.7))
	hud.add_child(_hint)

	# 结果面板（居中）
	_result_panel = Panel.new()
	_result_panel.anchor_left = 0.5; _result_panel.anchor_top = 0.5; _result_panel.anchor_right = 0.5; _result_panel.anchor_bottom = 0.5
	_result_panel.offset_left = -200.0; _result_panel.offset_right = 200.0; _result_panel.offset_top = -80.0; _result_panel.offset_bottom = 80.0
	_result_panel.visible = false
	hud.add_child(_result_panel)
	_result_label = Label.new(); _result_label.position = Vector2(20, 20); _result_panel.add_child(_result_label)
	_return_btn = Button.new(); _return_btn.text = "返回城镇"; _return_btn.position = Vector2(20, 60)
	_return_btn.pressed.connect(_on_return_pressed)
	_result_panel.add_child(_return_btn)

	# 用药菜单
	_item_menu = PopupMenu.new()
	_item_menu.id_pressed.connect(_on_item_menu_index)
	hud.add_child(_item_menu)

func _build_action_buttons(bar: HBoxContainer) -> void:
	var basic := Button.new()
	basic.text = "普攻"
	basic.custom_minimum_size = Vector2(64, 40)
	basic.mouse_filter = Control.MOUSE_FILTER_STOP  # 按钮必须 STOP 才能拦截点击、阻止透到网格
	basic.pressed.connect(_on_basic_pressed)
	bar.add_child(basic)

	var equipped: Array[String] = GameManager.ability_service.equipped_combat
	for i in range(equipped.size()):
		var aid: String = equipped[i]
		if aid == "":
			continue
		var cfg: Dictionary = ConfigManager.get_ability(aid)
		var b := Button.new()
		b.text = "%s(%d)" % [cfg.get("name", aid), int(cfg.get("qi_cost", cfg.get("mp_cost", 0)))]
		b.custom_minimum_size = Vector2(84, 40)
		if UIManager.has_icon("skills/" + aid):
			b.icon = UIManager.get_icon("skills/" + aid)
		b.pressed.connect(_on_skill_pressed.bind(i, aid))
		bar.add_child(b)

	var item_btn := Button.new()
	item_btn.text = "物品"
	item_btn.custom_minimum_size = Vector2(64, 40)
	item_btn.pressed.connect(_on_item_pressed)
	bar.add_child(item_btn)

	var end_btn := Button.new()
	end_btn.text = "结束回合"
	end_btn.custom_minimum_size = Vector2(84, 40)
	end_btn.pressed.connect(_on_end_turn_pressed)
	bar.add_child(end_btn)

	_auto_btn = Button.new()
	_auto_btn.text = "自动: 关"
	_auto_btn.custom_minimum_size = Vector2(72, 40)
	_auto_btn.pressed.connect(_on_auto_pressed)
	bar.add_child(_auto_btn)

func _refresh_hud() -> void:
	if _state == null:
		return
	if _hud_player_name != null:
		_hud_player_name.text = "李十五"
	if _hud_player_hp != null:
		_hud_player_hp.text = "气血 %d/%d" % [_state.player.hp, _state.player.max_hp]
	if _hud_player_mp != null:
		_hud_player_mp.text = "真气 %d/%d" % [_state.player.mp, _state.player.max_mp]
	if _hud_player_status != null:
		var se: Array = []
		for s in _state.player.status_effects:
			se.append("%s%d" % [s.name_key, s.stacks])
		_hud_player_status.text = "状态: " + (", ".join(se) if not se.is_empty() else "无")
	var t: CombatCharacter = _unit_by_state(_target_id)
	if _hud_target_name != null:
		if t != null and t.is_alive():
			_hud_target_name.text = ConfigManager.get_enemy(t.character_id).get("name", t.character_id)
		else:
			_hud_target_name.text = "（无目标）"
	if _hud_target_hp != null:
		if t != null and t.is_alive():
			_hud_target_hp.text = "气血 %d/%d" % [t.hp, t.max_hp]
		else:
			_hud_target_hp.text = ""
	if _hud_conditions != null:
		_hud_conditions.text = "回合 %d · 战棋%s" % [_turn, " · 自动" if _auto else ""]
	if _action_bar != null:
		for c in _action_bar.get_children():
			var b := c as Button
			if b != null:
				b.disabled = _busy or _phase != Phase.PLAYER

func _panel() -> Panel:
	var p := Panel.new()
	p.mouse_filter = Control.MOUSE_FILTER_PASS  # 面板不拦截鼠标，让点击透到网格或按钮
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.10, 0.12, 0.16, 0.82)
	sb.border_color = Color(0.35, 0.4, 0.5, 0.6)
	sb.border_width_left = 1; sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
	return p

func _build_fatal(msg: String) -> void:
	var l := Label.new()
	l.text = msg
	l.position = Vector2(40, 40)
	l.add_theme_color_override("font_color", Color(1, 0.5, 0.5))
	add_child(l)
