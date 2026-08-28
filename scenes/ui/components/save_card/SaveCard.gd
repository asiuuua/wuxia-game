# scenes/ui/components/save_card/SaveCard.gd
# 存档卡片组件（代码构建 Control，无 .tscn；对齐 MenuItem / MainMenu 惯例）
# 交互约定：鼠标悬停高亮金边；点击卡片体或 [读取] 触发读取；[删除] 触发删除；空槽 [新的旅程] 触发新游戏
# 颜色集中引用 UIPalette，不硬编码。消费方用 const SaveCard = preload(...) 引用本类型

@warning_ignore("shadowed_global_identifier")

extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

@warning_ignore("unused_signal")
signal load_requested(slot: int)
@warning_ignore("unused_signal")
signal delete_requested(slot: int)
@warning_ignore("unused_signal")
signal new_game_requested(slot: int)
@warning_ignore("unused_signal")
signal save_requested(slot: int)
@warning_ignore("unused_signal")
signal card_focused(card: Control)

const CARD_W := 760.0
const CARD_H := 112.0
const THUMB_W := 120.0
const THUMB_H := 84.0

var _slot: int = 0
var _is_empty: bool = true
var _is_auto: bool = false
var _mode: String = "load"   # "load" 读取模式 / "save" 保存模式（ESC 菜单「保存游戏」进入）

var _bg: Panel = null
var _normal_sb: StyleBoxFlat = null
var _highlight_sb: StyleBoxFlat = null
var _number_label: Label = null
var _name_label: Label = null
var _level_label: Label = null
var _faction_label: Label = null
var _playtime_label: Label = null
var _savetime_label: Label = null
var _scene_label: Label = null
var _empty_label: Label = null
var _load_btn: Button = null
var _delete_btn: Button = null
var _new_game_btn: Button = null

func _ready() -> void:
	custom_minimum_size = Vector2(CARD_W, CARD_H)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)

func _build() -> void:
	_normal_sb = StyleBoxFlat.new()
	_normal_sb.bg_color = UIPalette.PANEL_DARK
	_normal_sb.border_width_left = 1
	_normal_sb.border_width_top = 1
	_normal_sb.border_width_right = 1
	_normal_sb.border_width_bottom = 1
	_normal_sb.border_color = UIPalette.TEXT_SECONDARY
	_normal_sb.set_content_margin_all(10)

	_highlight_sb = StyleBoxFlat.new()
	_highlight_sb.bg_color = UIPalette.PANEL_DARK
	_highlight_sb.border_width_left = 2
	_highlight_sb.border_width_top = 2
	_highlight_sb.border_width_right = 2
	_highlight_sb.border_width_bottom = 2
	_highlight_sb.border_color = UIPalette.GOLD
	_highlight_sb.set_content_margin_all(10)

	_bg = Panel.new()
	_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_bg.add_theme_stylebox_override("panel", _normal_sb)
	add_child(_bg)

	var content: HBoxContainer = HBoxContainer.new()
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.add_theme_constant_override("separation", 14)
	add_child(content)

	# --- 缩略图占位（真实截图后改用 TextureRect + thumbnail_path） ---
	var thumb: Panel = Panel.new()
	thumb.custom_minimum_size = Vector2(THUMB_W, THUMB_H)
	var thumb_sb := StyleBoxFlat.new()
	thumb_sb.bg_color = UIPalette.BG_DARK
	thumb_sb.border_width_left = 1
	thumb_sb.border_width_top = 1
	thumb_sb.border_width_right = 1
	thumb_sb.border_width_bottom = 1
	thumb_sb.border_color = UIPalette.GOLD_DARK
	thumb.add_theme_stylebox_override("panel", thumb_sb)
	var thumb_label: Label = Label.new()
	thumb_label.text = tr("ui_save_thumb")
	thumb_label.add_theme_font_size_override("font_size", UIPalette.FS_BODY)
	thumb_label.add_theme_color_override("font_color", UIPalette.GOLD_DARK)
	thumb_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	thumb_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	thumb_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	thumb.add_child(thumb_label)
	content.add_child(thumb)

	# --- 信息区 ---
	var info: VBoxContainer = VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.add_theme_constant_override("separation", 4)
	content.add_child(info)

	_number_label = Label.new()
	_number_label.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
	_number_label.add_theme_color_override("font_color", UIPalette.GOLD)
	info.add_child(_number_label)

	_name_label = Label.new()
	_name_label.add_theme_font_size_override("font_size", UIPalette.FS_NAME)
	_name_label.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	info.add_child(_name_label)

	_level_label = Label.new()
	_level_label.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
	_level_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	info.add_child(_level_label)

	_faction_label = Label.new()
	_faction_label.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
	_faction_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	info.add_child(_faction_label)

	_playtime_label = Label.new()
	_playtime_label.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	_playtime_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	info.add_child(_playtime_label)

	_savetime_label = Label.new()
	_savetime_label.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	_savetime_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	info.add_child(_savetime_label)

	_scene_label = Label.new()
	_scene_label.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	_scene_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	info.add_child(_scene_label)

	_empty_label = Label.new()
	_empty_label.text = tr("ui_save_empty")
	_empty_label.add_theme_font_size_override("font_size", UIPalette.FS_BODY)
	_empty_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	_empty_label.visible = false
	info.add_child(_empty_label)

	# --- 操作区 ---
	var actions: VBoxContainer = VBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.custom_minimum_size = Vector2(130, 0)
	content.add_child(actions)

	# 主操作按钮：读取/保存模式共用，文字与 emit 信号随 _mode 切换（见 _on_primary_pressed）
	_load_btn = Button.new()
	_load_btn.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_load_btn.pressed.connect(_on_primary_pressed)
	actions.add_child(_load_btn)

	_delete_btn = Button.new()
	_delete_btn.text = tr("ui_save_delete")
	_delete_btn.add_theme_color_override("font_color", UIPalette.DANGER)
	_delete_btn.pressed.connect(func(): delete_requested.emit(_slot))
	actions.add_child(_delete_btn)

	_new_game_btn = Button.new()
	_new_game_btn.text = tr("ui_save_new")
	_new_game_btn.add_theme_color_override("font_color", UIPalette.SUCCESS)
	_new_game_btn.pressed.connect(func(): new_game_requested.emit(_slot))
	_new_game_btn.visible = false
	actions.add_child(_new_game_btn)

	_refresh_mode_visuals()

## info: SaveManager.list_saves() 返回的单个槽位摘要 dict
func setup(info: Dictionary) -> void:
	_slot = int(info.get("slot", 0))
	_is_empty = not info.get("exists", false)
	_is_auto = info.get("is_auto", false)
	if _is_empty:
		_show_empty()
	else:
		_show_info(info)

## 设置卡片模式（load/save）；SaveLoadScreen 在 _add_card 时调用，切换后刷新按钮
func set_mode(m: String) -> void:
	_mode = m
	_refresh_mode_visuals()

func _show_empty() -> void:
	_number_label.text = tr("ui_save_slot") % _slot
	_name_label.visible = false
	_level_label.visible = false
	_faction_label.visible = false
	_playtime_label.visible = false
	_savetime_label.visible = false
	_scene_label.visible = false
	_empty_label.visible = true
	# 按钮可见性/文字交由模式统一刷新
	_refresh_mode_visuals()

func _show_info(info: Dictionary) -> void:
	_number_label.text = tr("ui_save_slot") % _slot
	if info.get("is_auto", false):
		_number_label.text = tr("ui_save_auto") % _slot
	_name_label.visible = true
	_name_label.text = info.get("player_name", tr("ui_save_default_name"))
	_level_label.visible = true
	_level_label.text = "Lv.%d" % int(info.get("level", 1))
	_faction_label.visible = true
	_faction_label.text = tr("ui_save_faction") % info.get("faction", tr("ui_save_no_sect"))
	_playtime_label.visible = true
	_playtime_label.text = tr("ui_save_playtime") % info.get("playtime", tr("ui_save_dash"))
	_savetime_label.visible = true
	_savetime_label.text = tr("ui_save_savetime") % info.get("save_time", tr("ui_save_dash"))
	_scene_label.visible = true
	_scene_label.text = tr("ui_save_scene") % info.get("scene", tr("ui_save_unknown_scene"))
	_empty_label.visible = false
	# 按钮可见性/文字交由模式统一刷新
	_refresh_mode_visuals()

## 根据 _mode（load/save）+ 空槽状态刷新主按钮文字与三个按钮可见性
func _refresh_mode_visuals() -> void:
	if _mode == "save":
		_load_btn.text = tr("ui_save_save")
		_load_btn.visible = true
		_new_game_btn.visible = false
		# 保存模式下自动存档不可手动覆盖（与不可删除一致）
		_delete_btn.visible = (not _is_empty) and (not _is_auto)
	else:
		if _is_empty:
			_load_btn.visible = false
			_new_game_btn.visible = true
		else:
			_load_btn.text = tr("ui_save_load")
			_load_btn.visible = true
			_new_game_btn.visible = false
		_delete_btn.visible = (not _is_empty) and (not _is_auto)

func set_highlighted(highlight: bool) -> void:
	if _bg == null:
		return
	_bg.add_theme_stylebox_override("panel", _highlight_sb if highlight else _normal_sb)

## 主按钮点击（鼠标 / 键盘确认）：保存模式统一发 save_requested，读取模式按空槽分流
func trigger_primary() -> void:
	if _mode == "save":
		save_requested.emit(_slot)
	elif _is_empty:
		new_game_requested.emit(_slot)
	else:
		load_requested.emit(_slot)

## 按钮 pressed 入口（复用 trigger_primary 逻辑，保持单一出口）
func _on_primary_pressed() -> void:
	trigger_primary()

func trigger_delete() -> void:
	if not _is_empty:
		delete_requested.emit(_slot)

func _on_mouse_entered() -> void:
	card_focused.emit(self)

func _on_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		trigger_primary()
