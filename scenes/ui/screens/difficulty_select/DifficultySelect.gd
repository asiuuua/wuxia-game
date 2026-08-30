@tool
# scenes/ui/screens/difficulty_select/DifficultySelect.gd
# 开局难度选择界面（阶段2 消费端入口）：读难度配置表渲染 5 档，选定后写入难度并开新游戏。
# HELL 强制二次确认警告；其余直接确认。文案经 tr() 本地化。
# B 路线：静态壳（Backdrop/Title/List/Back）在 DifficultySelect.tscn，代码只填动态内容。
# 2026-08-29 迁移到 BaseScreen：铺满/安全区/键盘导航/返回 由基类统一处理，本文件只留业务

@warning_ignore("shadowed_global_identifier")

extends BaseScreen

@onready var _title: Label = $Title
@onready var _list: VBoxContainer = $List
@onready var _back: Button = $Back

var _diff_ids: Array = []   # 难度枚举顺序：EASY..HELL

func _init() -> void:
	keyboard_nav_enabled = true   # 上下键在难度项间导航
	close_on_cancel = true        # ESC / ui_cancel 返回上一级

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_diff_ids = CombatEnums.Difficulty.keys()
	super._ready()   # 基类：铺满 + 安全区 + _build_content() + _update_selection()

func _build_content() -> void:
	# 静态壳在 .tscn；此处把节点挂进安全区 ContentRoot 并填动态内容
	add_content(_title)
	add_content(_list)
	add_content(_back)
	_title.text = tr("diff_select_title")
	_title.add_theme_font_size_override("font_size", UIPalette.FS_TITLE)
	_title.add_theme_color_override("font_color", UIPalette.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back.text = tr("diff_select_back")
	_back.pressed.connect(_on_back)
	_build_list()

func _build_list() -> void:
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
		_apply_glass_to_button(btn, UIPalette.TEXT_MAIN)
		if id == "HELL":
			btn.add_theme_color_override("font_color", UIPalette.DANGER)
		_list.add_child(btn)
		# 填进 _nav_items 后，键盘上下导航由基类统一处理
		_nav_items.append(btn)

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
	# 一次性关掉所有 UI 屏幕（含 MainMenu）：autoload 的 CanvasLayer 跨场景常驻，
	# 不关的话切到 TownScene 后 MainMenu 仍挡在 TownScene 上方 → 玩家看不到 TownScene 以为"没进游戏" → 重复点开始 → 选2遍模式。
	# 与 SaveLoadScreen._do_new_game 行为一致（UI 入口自行清理 UI，符合主权边界）。
	UIManager.close_all_screens()
	GameManager.start_new_game()

func _on_back() -> void:
	UIManager.close_screen(self)

## 给按钮套磨砂玻璃样式（对齐 SettingsScreen / SaveLoadScreen 玻璃按钮规范）
func _apply_glass_to_button(btn: Button, font_color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GLASS_BORDER
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_font_size_override("font_size", UIPalette.FS_SUB)

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后渲染难度列表
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_title = $Title
	_list = $List
	_back = $Back
	if _title == null or _list == null:
		return
	_diff_ids = CombatEnums.Difficulty.keys()
	_title.text = tr("diff_select_title")
	_title.add_theme_font_size_override("font_size", UIPalette.FS_TITLE)
	_title.add_theme_color_override("font_color", UIPalette.GOLD)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back.text = tr("diff_select_back")
	for i in _diff_ids.size():
		var id: String = _diff_ids[i]
		var btn: Button = Button.new()
		btn.name = "Diff_%d" % i
		btn.custom_minimum_size = Vector2(0, 120)
		btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.text = _entry_text(id)
		if id == "HELL":
			btn.add_theme_color_override("font_color", UIPalette.DANGER)
		_apply_glass_to_button(btn, UIPalette.TEXT_MAIN)
		_list.add_child(btn)
