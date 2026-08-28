# scenes/gameplay/battle/BattleScene.gd
# 战斗场景（表现层）：M2 重构后只做装配 + 输入转发，流程编排交给 CombatDirector
# 通过 combat_service 的「事件流」接口（*_events）取 Array[CombatEvent]，由 Director 逐个播放
# 不持有战斗逻辑（业务层铁律）；不读 CombatState 做血条判断（血条由 View 据 target_hp_after 直设）

extends Control
class_name BattleScene

var _state: CombatState = null
var _selected_enemy_id: String = ""
var _enemy_huds: Dictionary = {}      # character_id -> UnitHud
var _enemy_buttons: Dictionary = {}   # character_id -> Button（选择）
var _enemy_box: HBoxContainer = null
var _player_hud: UnitHud = null
var _director: CombatDirector = null
var _view: BattleView = null
var _order_bar: HBoxContainer = null
var _actions_container: HBoxContainer = null
var _auto_button: Button = null
var _speed_button: Button = null
var _item_menu: PopupMenu = null
var _item_instance_ids: Array[String] = []
var _log_label: Label = null
var _result_panel: Panel = null
var _result_label: Label = null
var _return_button: Button = null
var _over: bool = false
var _busy: bool = false
var _speed_idx: int = 0
var _speed_steps: Array[float] = [1.0, 2.0, 4.0]

func _ready() -> void:
	_build_ui()
	EventBus.scene_changed.emit("battle_001")
	GameManager.combat_service.start_combat(GameManager.pending_battle_id)
	_state = GameManager.combat_service.get_state()
	if _state == null:
		_log_label.text = "战斗配置缺失，无法开始。"
		return
	_build_units()
	_build_action_buttons()
	_refresh()
	_refresh_order()

func _build_ui() -> void:
	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(vb)
	# 演出层：Director（编排）+ View（视图）
	_director = CombatDirector.new()
	add_child(_director)
	_view = BattleView.new()
	vb.add_child(_view)
	_director.bind_view(_view)
	# 玩家 HUD
	_player_hud = UnitHud.new()
	vb.add_child(_player_hud)
	# 敌人区（HUD + 选择按钮）
	_enemy_box = HBoxContainer.new()
	vb.add_child(_enemy_box)
	# ATB 顺序条
	_order_bar = HBoxContainer.new()
	vb.add_child(_order_bar)
	# 行动按钮区
	_actions_container = HBoxContainer.new()
	vb.add_child(_actions_container)
	_auto_button = Button.new()
	_auto_button.text = "自动战斗"
	_auto_button.pressed.connect(_on_auto_pressed)
	vb.add_child(_auto_button)
	var escape_btn := Button.new()
	escape_btn.text = "逃跑"
	escape_btn.pressed.connect(_on_escape_pressed)
	vb.add_child(escape_btn)
	_speed_button = Button.new()
	_speed_button.text = "加速 x1"
	_speed_button.pressed.connect(_on_speed_pressed)
	vb.add_child(_speed_button)
	var skip_btn := Button.new()
	skip_btn.text = "跳过"
	skip_btn.pressed.connect(_on_skip_pressed)
	vb.add_child(skip_btn)
	# 用药菜单
	_item_menu = PopupMenu.new()
	_item_menu.id_pressed.connect(_on_item_menu_index)
	add_child(_item_menu)
	_log_label = Label.new()
	_log_label.custom_minimum_size = Vector2(0, 120)
	vb.add_child(_log_label)
	_result_panel = Panel.new()
	_result_panel.visible = false
	vb.add_child(_result_panel)
	_result_label = Label.new()
	_result_label.position = Vector2(20, 20)
	_result_panel.add_child(_result_label)
	_return_button = Button.new()
	_return_button.text = "返回城镇"
	_return_button.position = Vector2(20, 60)
	_return_button.pressed.connect(_on_return_pressed)
	_result_panel.add_child(_return_button)

func _build_units() -> void:
	_player_hud.setup("李十五", _state.player.max_hp, _state.player.max_mp)
	_view.register_unit("player", _player_hud)
	for e in _state.enemies:
		var hud := UnitHud.new()
		var nm: String = ConfigManager.get_enemy(e.character_id).get("name", e.character_id)
		hud.setup(nm, e.max_hp, e.max_mp)
		_enemy_box.add_child(hud)
		_enemy_huds[e.character_id] = hud
		_view.register_unit(e.character_id, hud)
		var b := Button.new()
		b.text = "选 " + nm
		b.pressed.connect(_on_enemy_selected.bind(e.character_id))
		_enemy_box.add_child(b)
		_enemy_buttons[e.character_id] = b

func _build_action_buttons() -> void:
	var basic := Button.new()
	basic.text = "普通攻击"
	basic.pressed.connect(_on_action_pressed.bind(-1))
	_actions_container.add_child(basic)
	var equipped: Array[String] = GameManager.ability_service.equipped_combat
	for i in equipped.size():
		var ability_id: String = equipped[i]
		if ability_id == "":
			continue
		var data: Dictionary = ConfigManager.get_ability(ability_id)
		var b := Button.new()
		b.text = "%s (真气%d)" % [data.get("name", ability_id), int(data.get("qi_cost", data.get("mp_cost", 0)))]
		b.pressed.connect(_on_action_pressed.bind(i))
		_actions_container.add_child(b)
	var item_btn := Button.new()
	item_btn.text = "物品"
	item_btn.pressed.connect(_on_item_pressed)
	_actions_container.add_child(item_btn)

## 打开用药菜单：扫描背包消耗品，按实例列出
func _on_item_pressed() -> void:
	if _over or _state == null or _busy:
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
				_item_menu.add_item("%s x%d（气血+%d 内力+%d）" % [
					data.get("name", inst.item_id), inst.count,
					int(data.get("heal_hp", 0)), int(data.get("heal_mp", 0))])
				_item_instance_ids.append(inst.instance_id)
	if _item_instance_ids.is_empty():
		_item_menu.add_item("没有可用药品")
		_item_instance_ids.append("")
	_item_menu.popup_centered(Vector2i(380, 220))

func _on_item_menu_index(index: int) -> void:
	if _over or _state == null or _busy or index >= _item_instance_ids.size():
		return
	var iid: String = _item_instance_ids[index]
	if iid == "":
		return
	_busy = true
	var events: Array[CombatEvent] = GameManager.combat_service.use_item_events(iid)
	if events.is_empty():
		GameLogger.warn("Battle", "用药无效或失败")
		_busy = false
		return
	await _director.play_events(events)
	if not GameManager.combat_service.is_over():
		await _director.play_events(GameManager.combat_service.enemy_phase_events())
	_refresh()
	_refresh_order()
	_busy = false
	if GameManager.combat_service.is_over():
		GameManager.combat_service.finalize()
		_show_result()

func _refresh() -> void:
	if _state == null:
		return
	_player_hud.set_hp(_state.player.hp)
	_player_hud.set_mp(_state.player.mp)
	_sync_status("player", _state.player.status_effects)
	for e in _state.enemies:
		var hud: UnitHud = _enemy_huds.get(e.character_id)
		if hud == null:
			continue
		hud.set_hp(e.hp)
		hud.set_mp(e.mp)
		_sync_status(e.character_id, e.status_effects)
		var b: Button = _enemy_buttons.get(e.character_id)
		if b != null:
			b.disabled = not e.is_alive()
			b.modulate = Color(1, 1, 1) if e.character_id == _selected_enemy_id else Color(0.6, 0.6, 0.6)
	if _selected_enemy_id == "" or not _is_alive(_selected_enemy_id):
		var alive: Array[CombatCharacter] = _state.get_alive_enemies()
		_selected_enemy_id = alive[0].character_id if not alive.is_empty() else ""
	_log_label.text = "\n".join(_state.entries.slice(-8))

func _sync_status(id: String, effects: Array) -> void:
	var hud: UnitHud = _enemy_huds.get(id)
	if hud == null and id == "player":
		hud = _player_hud
	if hud == null:
		return
	var entries: Array = []
	for se in effects:
		entries.append([se.name_key, se.stacks])
	hud.set_status(entries)

func _refresh_order() -> void:
	if _order_bar == null or _state == null:
		return
	for c in _order_bar.get_children():
		c.queue_free()
	if GameManager.combat_service.get_core() == null:
		return
	var order: Array[String] = GameManager.combat_service.get_core().action_order()
	for uid in order:
		var lbl := Label.new()
		var nm: String = "李十五" if uid == "player" else ConfigManager.get_enemy(uid).get("name", uid)
		lbl.text = "→ " + nm
		_order_bar.add_child(lbl)

func _is_alive(enemy_id: String) -> bool:
	for e in _state.enemies:
		if e.character_id == enemy_id:
			return e.is_alive()
	return false

func _on_enemy_selected(enemy_id: String) -> void:
	_selected_enemy_id = enemy_id
	_refresh()

func _on_action_pressed(slot: int) -> void:
	if _over or _state == null or _busy:
		return
	_busy = true
	var events: Array[CombatEvent]
	if slot == -1:
		events = GameManager.combat_service.player_attack_events(_selected_enemy_id)
	else:
		events = GameManager.combat_service.player_cast_events(slot, _selected_enemy_id)
	await _director.play_events(events)
	if not GameManager.combat_service.is_over():
		await _director.play_events(GameManager.combat_service.enemy_phase_events())
	_refresh()
	_refresh_order()
	_busy = false
	if GameManager.combat_service.is_over():
		GameManager.combat_service.finalize()
		_show_result()

func _on_auto_pressed() -> void:
	if _over or _state == null or _busy:
		return
	_busy = true
	while not GameManager.combat_service.is_over():
		await _director.play_events(GameManager.combat_service.player_attack_events(""))
		if GameManager.combat_service.is_over():
			break
		await _director.play_events(GameManager.combat_service.enemy_phase_events())
	_refresh()
	_refresh_order()
	_busy = false
	if GameManager.combat_service.is_over():
		GameManager.combat_service.finalize()
		_show_result()

func _on_escape_pressed() -> void:
	if _over or _state == null or _busy:
		return
	_busy = true
	if GameManager.combat_service.try_escape():
		_refresh()
		_show_result()
		_busy = false
		return
	await _director.play_events(GameManager.combat_service.enemy_phase_events())
	_refresh()
	_refresh_order()
	_busy = false
	if GameManager.combat_service.is_over():
		GameManager.combat_service.finalize()
		_show_result()

func _on_speed_pressed() -> void:
	_speed_idx = (_speed_idx + 1) % _speed_steps.size()
	_director.set_speed_scale(_speed_steps[_speed_idx])
	_speed_button.text = "加速 x%d" % int(_speed_steps[_speed_idx])

func _on_skip_pressed() -> void:
	_director.set_instant(true)
	_speed_idx = 0
	_speed_button.text = "加速 x1"

func _show_result() -> void:
	_over = true
	_result_panel.visible = true
	var r: int = _state.result
	if r == CombatEnums.CombatResult.VICTORY:
		_result_label.text = "战斗结束：胜利！获得经验与战利品。"
		_return_button.visible = true
	elif r == CombatEnums.CombatResult.FLEE:
		_result_label.text = "战斗结束：你成功脱身了。"
		_return_button.visible = true
	else:
		_result_label.text = "战斗结束：你倒下了……"
		_return_button.visible = false

func _on_return_pressed() -> void:
	GameManager.return_to_town()
