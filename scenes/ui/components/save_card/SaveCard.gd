# scenes/ui/components/save_card/SaveCard.gd
# 存档卡片组件（静态结构迁入 SaveCard.tscn，脚本只做连线与动态逻辑；对齐 B 路线 .tscn 化）
# 交互约定：鼠标悬停高亮金边；点击卡片体或 [读取] 触发读取；[删除] 触发删除；空槽 [新的旅程] 触发新游戏
# 颜色集中引用 UIPalette，不硬编码。消费方用 preload(SaveCard.tscn).instantiate() 实例化本类型

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

# 动态高亮用的两套 StyleBox（静态底由 .tscn 提供，这里只管悬停态）
var _normal_sb: StyleBoxFlat = null
var _highlight_sb: StyleBoxFlat = null

@onready var _bg: Panel = $BG
@onready var _number_label: Label = $Content/Info/NumberLabel
@onready var _name_label: Label = $Content/Info/NameLabel
@onready var _level_label: Label = $Content/Info/LevelLabel
@onready var _faction_label: Label = $Content/Info/FactionLabel
@onready var _playtime_label: Label = $Content/Info/PlaytimeLabel
@onready var _savetime_label: Label = $Content/Info/SavetimeLabel
@onready var _scene_label: Label = $Content/Info/SceneLabel
@onready var _empty_label: Label = $Content/Info/EmptyLabel
@onready var _load_btn: Button = $Content/Actions/LoadBtn
@onready var _delete_btn: Button = $Content/Actions/DeleteBtn
@onready var _new_game_btn: Button = $Content/Actions/NewGameBtn

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_dynamic_styles()
	_connect_signals()
	_refresh_mode_visuals()

# 悬停高亮态用代码生成的 StyleBox（金色描边 2px），静态底由 .tscn 提供
func _build_dynamic_styles() -> void:
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

	_bg.add_theme_stylebox_override("panel", _normal_sb)

func _connect_signals() -> void:
	if not mouse_entered.is_connected(_on_mouse_entered):
		mouse_entered.connect(_on_mouse_entered)
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	if not _load_btn.pressed.is_connected(_on_primary_pressed):
		_load_btn.pressed.connect(_on_primary_pressed)
	if not _delete_btn.pressed.is_connected(_on_delete_pressed):
		_delete_btn.pressed.connect(_on_delete_pressed)
	if not _new_game_btn.pressed.is_connected(_on_new_game_pressed):
		_new_game_btn.pressed.connect(_on_new_game_pressed)

func _on_delete_pressed() -> void:
	delete_requested.emit(_slot)

func _on_new_game_pressed() -> void:
	new_game_requested.emit(_slot)

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
