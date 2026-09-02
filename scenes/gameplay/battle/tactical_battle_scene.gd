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

# P0-2：显式 preload 渲染器（不依赖编辑器全局类缓存，headless 验证可确定性解析）
const CombatEventRenderer = preload("res://core/combat_event_renderer.gd")

const BASIC_RANGE: int = 1     # 普攻射程（曼哈顿<=1，近身）

enum Phase { PLAYER, ENEMY, OVER }
enum Mode { MOVE, AWAIT_TARGET }

var _state: CombatState = null
var _grid: BattleGrid = null
var _grid_node: BattleGridNode = null
var _cam: Camera2D = null
var _entities_node: Node2D = null
var _entities: Dictionary = {}      # character_id -> BattleEntity
# P0-2：统一渲染查找闭包（character_id -> BattleEntity），供 CombatEventRenderer 委托
var _entity_lookup: Callable = func(id): return _entities.get(id)

# 战斗实体对象池（按场景作用域）：本场战斗持有实例，_exit_tree 时 clear() 释放空闲实例
var _entity_pool: CombatEntityPool = CombatEntityPool.new()

# 演出节奏控制（P0-1）：加速倍率 / 跳过模式；_aborted 为场景退出标志，用于打断在途协程防 use-after-free（P1-4）
var _speed_scale: float = 1.0
var _instant: bool = false
var _aborted: bool = false
var _speed_btn: Button
var _skip_btn: Button

var _phase: int = Phase.PLAYER
var _mode: int = Mode.MOVE
var _turn: int = 1
var _auto: bool = false
var _busy: bool = false
var _pending: Dictionary = {}       # {kind:"basic"|"cast", ability_id, slot}
var _target_id: String = ""

# 7.3.1 组队选择：玩家方单位（"player" + 存活同伴）列表、当前可操控单位、本回合已行动标记
var _roster: Array[String] = []
var _active_actor: String = "player"
var _actors_acted: Dictionary = {}

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
	# 战棋底图（工作室工具写入）：view_mode(45°等距/正交轴测) + 背景图（缺省程序化占位）
	var meta: Dictionary = GameManager.combat_service.get_grid_meta()
	if meta.get("view_mode", "iso") == "ortho":
		_grid_node.set_view_mode("ortho")
	if meta.get("background", "") != "":
		_grid_node.set_background(String(meta["background"]))
	# 棋盘平移/缩放（编辑器可调）：pan 是相对居中的额外像素偏移，zoom 是用户指定的棋盘缩放倍率。
	# 默认值 pan=0 / zoom=1.0 时等于原行为（仅镜头自动适配），向后兼容旧布局。
	var pan_x: float = float(meta.get("pan_x", 0))
	var pan_y: float = float(meta.get("pan_y", 0))
	var grid_zoom: float = clampf(float(meta.get("zoom", 1.0)), 0.2, 4.0)
	var grid_rot: float = float(meta.get("rotation", 0))
	# 场景底图是否跟随棋盘旋转（编辑器「场景底图跟随旋转」开关；默认 false = 底图不转）
	_grid_node.background_rotates_with_grid = bool(meta.get("bg_rotate", false))
	_grid_node.position = Vector2(pan_x, pan_y)
	_grid_node.scale = Vector2(grid_zoom, grid_zoom)
	_grid_node.rotation_degrees = grid_rot   # 棋盘整体绕自身原点旋转（地形/单位落点随之旋转）
	_grid_node.sync_background_rotation()    # 旋转应用后，按开关让底图同步/抵消旋转
	bf.add_child(_grid_node)
	_entities_node = Node2D.new()
	_entities_node.name = "Entities"
	_entities_node.y_sort_enabled = true
	bf.add_child(_entities_node)
	# 镜头自动适配（P0）：算出整张等轴测地图像素包围盒（含网格自身缩放），自动缩放+居中
	# —— 小地图放大、大地图缩小，不写死镜头参数；bf 保持原点，居中完全交给 Camera2D
	_cam = Camera2D.new()
	add_child(_cam)
	var bbox := _grid_pixel_rect()
	var view := get_viewport_rect().size
	var cam_zoom: float = min(view.x / max(bbox.size.x, 1.0), view.y / max(bbox.size.y, 1.0)) * 0.92
	cam_zoom = clampf(cam_zoom, 0.25, 1.5)
	_cam.zoom = Vector2(cam_zoom, cam_zoom)
	# bbox 已是 grid_node 局部坐标（已含 scale）；pan 偏移作用于 grid_node.position，镜头中心随之平移
	_cam.position = bbox.get_center() + Vector2(pan_x, pan_y)

## 整张等轴测地图的像素包围盒（grid_node 局部坐标）：用于镜头自动缩放/居中
func _grid_pixel_rect() -> Rect2:
	var min_x: float = 1e9
	var max_x: float = -1e9
	var min_y: float = 1e9
	var max_y: float = -1e9
	for x in range(_grid.width):
		for y in range(_grid.height):
			var c := _grid_node.cell_center(Vector2i(x, y))
			min_x = min(min_x, c.x); max_x = max(max_x, c.x)
			min_y = min(min_y, c.y); max_y = max(max_y, c.y)
	var hw: float = _grid_node.tile_width * 0.5
	var hh: float = _grid_node.tile_height * 0.5
	return Rect2(min_x - hw, min_y - hh, (max_x - min_x) + hw * 2.0, (max_y - min_y) + hh * 2.0)

func _spawn_entities() -> void:
	var pname: String = "李十五"
	if GameManager.player_state != null and GameManager.player_state.player_name != "":
		pname = GameManager.player_state.player_name
	_spawn_one("player", true, pname, _state.player)
	for p in _state.player_party:
		if p.is_alive():
			_spawn_one(p.character_id, true, p.name_key, p)
	for e in _state.enemies:
		if e.is_alive():
			var nm: String = ConfigManager.get_enemy(e.character_id).get("name", e.character_id)
			_spawn_one(e.character_id, false, nm, e)

func _spawn_one(uid: String, player: bool, nm: String, ch: CombatCharacter) -> void:
	# 主角才走动态立绘帧序列；同伴追随者走 npc 头像图标（frames_path 传空→battle_entity 落 _apply_body_visual），
	# 避免副手误套主角脸。敌人同理走 enemies 头像，缺图回退阵营色块。
	var frames: String = "res://assets/characters/matte/matte_idle.tres" if (player and uid == "player") else ""
	var ent := _entity_pool.acquire_entity(uid, player, nm, ch.max_hp, ch.max_mp, _grid_node, frames)
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
			if _aborted:
				return
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
		if _aborted:
			return
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
	if _aborted:
		return
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

## P0-1 加速：在 ×1/×2/×4 间循环，作用于所有 _wait 时长
func _on_speed_pressed() -> void:
	var scales := [1.0, 2.0, 4.0]
	var idx: int = scales.find(_speed_scale)
	idx = (idx + 1) % scales.size()
	_speed_scale = scales[idx]
	if _skip_btn != null and _instant:
		# 跳过模式下倍率已无意义，仅更新文案提示
		pass
	if _speed_btn != null:
		_speed_btn.text = "加速x%d" % int(_speed_scale)

## P0-1 跳过：拉满节奏 + 通知实体瞬移/不飘字，整场演出瞬间完成
func _on_skip_pressed() -> void:
	_instant = not _instant
	if _skip_btn != null:
		_skip_btn.text = "跳过: 开" if _instant else "跳过: 关"
	if _instant:
		_speed_scale = 999.0
	else:
		_speed_scale = 1.0
	if _speed_btn != null:
		_speed_btn.text = "加速x%d" % int(_speed_scale)

# ───────────────────────── 回合驱动 ─────────────────────────

func _start_player_turn() -> void:
	if _aborted:
		return
	if GameManager.combat_service.is_over():
		_finish()
		return
	_turn += 1
	_phase = Phase.PLAYER
	_mode = Mode.MOVE
	_actors_acted = {}
	_refresh_roster()
	_active_actor = _first_unacted()
	_enter_actor_turn()

## 重建玩家方单位列表（仅存活者），供选择条与回合遍历
func _refresh_roster() -> void:
	_roster = ["player"]
	for p in _state.player_party:
		if p.is_alive():
			_roster.append(p.character_id)

## 下一个本回合尚未行动的单位；都为空返回 ""
func _first_unacted() -> String:
	for id in _roster:
		if not _actors_acted.get(id, false) and _alive_side(id):
			return id
	return ""

## 进入某玩家方单位的行动子回合：重置模式、选最近敌人、高亮其可达格
func _enter_actor_turn() -> void:
	if _aborted:
		return
	if _active_actor == "":
		_start_enemy_phase()
		return
	_mode = Mode.MOVE
	_target_id = _nearest_alive_enemy_id()
	_show_reachable()
	_refresh_hud()
	if _auto:
		_auto_player_turn()

func _is_player_side(uid: String) -> bool:
	if uid == "player":
		return true
	for p in _state.player_party:
		if p.character_id == uid:
			return true
	return false

func _alive_side(uid: String) -> bool:
	var c: CombatCharacter = _unit_by_state(uid)
	return c != null and c.is_alive()

func _active_char() -> CombatCharacter:
	return _unit_by_state(_active_actor)

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
	if _aborted:
		return
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
		if _aborted:
			return

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
			if _aborted:
				return
		if not GameManager.combat_service.is_over():
			var evs2: Array[CombatEvent] = GameManager.combat_service.player_attack_events("")
			await _play_events(evs2)
		if _aborted:
			return
	_busy = false
	if GameManager.combat_service.is_over():
		_finish()
		return
	_start_enemy_phase()

func _after_player_action() -> void:
	if _aborted:
		return
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
	if _aborted:
		return
	for ev in events:
		if _aborted:
			return
		if ev.type == CombatEvent.Type.GRID_MOVE:
			# 移动是战术专有表现，仍由 BattleEntity 直接处理（含跳过瞬移）
			var e = _entities.get(ev.actor_id)
			if e != null:
				e.move_to(ev.to_grid, _instant)
			await _wait(0.28)
			if _aborted:
				return
		else:
			# P0-2：HUD 事件统一委托 CombatEventRenderer，与 BattleView 共用一套渲染逻辑
			CombatEventRenderer.render(ev, _entity_lookup, _instant)
			await _wait(CombatEventRenderer.duration(ev))
			if _aborted:
				return
	_refresh_hud()
	if _aborted:
		return
	await _wait(0.03)

# P0-2：战术飘字现统一经 CombatEventRenderer（instant 时由渲染器跳过），本场景不再保留独立 _pop

# ───────────────────────── 结束 ─────────────────────────

func _finish() -> void:
	if _aborted:
		return
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
			_entity_pool.release_entity(ent)
	_entities.clear()

func _on_return_pressed() -> void:
	_release_all()
	# 分帧释放（P2）：把重场景切换推迟一帧，先让结算面板/末帧渲染完，避免卸载瞬间掉帧
	call_deferred("_deferred_return")

func _deferred_return() -> void:
	if _aborted:
		return
	GameManager.return_to_town()

## 场景退出：置 _aborted 打断在途协程，再释放对象池空闲实例（随场景销毁，无跨场景泄漏累积）
func _exit_tree() -> void:
	_aborted = true
	if _entity_pool != null:
		_entity_pool.clear()

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

## 节奏等待：加速时按 _speed_scale 缩短；跳过(_instant)或场景已退出(_aborted)时立即返回不挂起
func _wait(dur: float) -> void:
	if _aborted:
		return
	if _instant:
		return
	if dur <= 0.0:
		return
	var d: float = dur / max(_speed_scale, 0.0001)
	await get_tree().create_timer(d).timeout

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
	tl.text = ConfigManager.get_battle(GameManager.pending_battle_id).get("name", "战棋战斗")
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

	# P0-1 演出节奏：加速循环 ×1/×2/×4 + 跳过开关
	_speed_btn = Button.new()
	_speed_btn.text = "加速x1"
	_speed_btn.custom_minimum_size = Vector2(72, 40)
	_speed_btn.pressed.connect(_on_speed_pressed)
	bar.add_child(_speed_btn)

	_skip_btn = Button.new()
	_skip_btn.text = "跳过: 关"
	_skip_btn.custom_minimum_size = Vector2(72, 40)
	_skip_btn.pressed.connect(_on_skip_pressed)
	bar.add_child(_skip_btn)

func _refresh_hud() -> void:
	if _state == null:
		return
	if _hud_player_name != null:
		_hud_player_name.text = GameManager.player_state.player_name
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
