# scenes/ui/screens/difficulty_select/DifficultySelect.gd
# 开局难度选择界面（阶段2 消费端入口）：读难度配置表渲染 5 档，选定后写入难度并开新游戏。
# HELL 强制二次确认警告；其余直接确认。文案经 tr() 本地化。
# 2026-08-29 迁移到 BaseScreen：铺满/安全区/键盘导航/返回 由基类统一处理，本文件只留业务

@warning_ignore("shadowed_global_identifier")

extends BaseScreen

var _diff_ids: Array = []   # 难度枚举顺序：EASY..HELL

func _init() -> void:
	keyboard_nav_enabled = true   # 上下键在难度项间导航
	close_on_cancel = true        # ESC / ui_cancel 返回上一级

func _ready() -> void:
	_diff_ids = CombatEnums.Difficulty.keys()
	super._ready()   # 基类：铺满 + 安全区 + _build_content() + _update_selection()

func _build_content() -> void:
	# 压暗底铺满整屏（含刘海区），内容放 add_content() 的容器里（自动避开刘海）
	_add_backdrop(0.7)

	var title: Label = Label.new()
	title.text = tr("diff_select_title")
	title.add_theme_font_size_override("font_size", UIPalette.FS_TITLE)
	title.add_theme_color_override("font_color", UIPalette.GOLD)
	title.anchor_left = 0.5; title.anchor_top = 0.06; title.anchor_right = 0.5; title.anchor_bottom = 0.06
	title.offset_left = -200.0; title.offset_top = 0.0; title.offset_right = 200.0; title.offset_bottom = 60.0
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_content(title)

	var list: VBoxContainer = VBoxContainer.new()
	list.anchor_left = 0.5; list.anchor_top = 0.22; list.anchor_right = 0.5; list.anchor_bottom = 0.82
	list.offset_left = -360.0; list.offset_top = 0.0; list.offset_right = 360.0; list.offset_bottom = 0.0
	list.add_theme_constant_override("separation", 12)
	add_content(list)

	for i in _diff_ids.size():
		var id: String = _diff_ids[i]
		var btn: Button = Button.new()
		btn.name = "Diff_%d" % i
		btn.custom_minimum_size = Vector2(0, 120)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.text = _entry_text(id)
		if id == "HELL":
			btn.add_theme_color_override("font_color", UIPalette.DANGER)
		btn.pressed.connect(_on_confirm_selection.bind(i))
		list.add_child(btn)
		# 填进 _nav_items 后，键盘上下导航由基类统一处理
		_nav_items.append(btn)

	var back: Button = Button.new()
	back.text = tr("diff_select_back")
	back.anchor_left = 0.5; back.anchor_top = 0.88; back.anchor_right = 0.5; back.anchor_bottom = 0.88
	back.offset_left = -100.0; back.offset_top = 0.0; back.offset_right = 100.0; back.offset_bottom = 44.0
	back.pressed.connect(_on_back)
	add_content(back)

func _entry_text(diff_id: String) -> String:
	var d: Dictionary = ConfigManager.get_difficulty(diff_id)
	var name: String = tr(String(d.get("display_name_text_id", "")))
	var desc: String = tr(String(d.get("desc_text_id", "")))
	return "%s\n%s\n%s%s" % [name, desc, tr("diff_penalty_prefix"), _penalty_text(diff_id)]

func _penalty_text(diff_id: String) -> String:
	var d: Dictionary = ConfigManager.get_difficulty(diff_id)
	var parts: Array = []
	var beh: int = int(CombatEnums.DefeatBehaviour.get(String(d.get("defeat_behaviour", "LOAD_LATEST_SAVE")), 0))
	match beh:
		CombatEnums.DefeatBehaviour.RESPAWN_CHECKPOINT:
			parts.append(tr("pen_respawn"))
		CombatEnums.DefeatBehaviour.LOAD_LATEST_SAVE:
			parts.append(tr("pen_loadsave"))
		CombatEnums.DefeatBehaviour.DELETE_SAVE:
			parts.append(tr("pen_delete"))
		_:
			parts.append(String(d.get("defeat_behaviour", "")))
	var money: int = int(d.get("defeat_lose_money", 0))
	if money > 0:
		parts.append(tr("pen_money") % money)
	if bool(d.get("defeat_lose_items", false)):
		parts.append(tr("pen_items") % int(d.get("defeat_lose_item_count", 1)))
	if bool(d.get("defeat_debt_if_broke", false)):
		parts.append(tr("pen_debt"))
	if String(d.get("defeat_cg_text_id", "")) != "":
		parts.append(tr("pen_cg"))
	return " · ".join(parts)

# === 选中态（基类在导航移动后自动调用）===
func _update_selection() -> void:
	for i in _nav_items.size():
		var btn: Button = _nav_items[i] as Button
		if btn == null:
			continue
		btn.modulate = Color(1, 1, 1) if i == _selected_index else Color(0.7, 0.7, 0.7)

# === 确认：ui_accept 由基类转发到这里，鼠标点击也走这里 ===
func _on_confirm_selection(_index: int) -> void:
	var index: int = _selected_index if _index < 0 else _index
	_selected_index = index
	_update_selection()
	var id: String = _diff_ids[index]
	if id == "HELL":
		var dlg: Control = UIManager.show_popup("ConfirmDialog")
		if dlg == null:
			return
		dlg.setup(tr("diff_select_hell_warn_title"), tr("diff_select_hell_warn_content"), func(): _proceed(id))
	else:
		_proceed(id)

func _proceed(diff_id: String) -> void:
	# 写入难度（DifficultyManager 同步更新 GameState 与缓存），随后开新游戏
	EventBus.cmd_set_difficulty.emit(diff_id, true)
	EventBus.game_started.emit()
	AudioManager.stop_bgm()
	UIManager.close_screen(self, func(): GameManager.start_new_game())

func _on_back() -> void:
	UIManager.close_screen(self)
