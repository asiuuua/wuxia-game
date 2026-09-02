@tool
# scenes/ui/overlays/map/MapScreen.gd
# 地图面板（M 键开关）：当前区域 + 世界时钟 + 区域枢纽总览
# 铁律：UI 只展示与输入，数据来自 WeatherTimeService / ConfigManager
# B 路线：静态壳（压暗底 + 居中玻璃面板 + 标题/区域/时钟/枢纽网格/提示/关闭）在 MapScreen.tscn，
# 美术可直接编辑布局与外观；本脚本只填动态文本与枢纽网格（按配置建/复用槽位）。

@warning_ignore("shadowed_global_identifier")

extends Control

class_name MapScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UICenterUtils = preload("res://scenes/ui/ui_center_utils.gd")

# 响应式锚点（派单 23a9d0b92b83）：面板设计尺寸，小视口自动内缩防溢出/错位
const MAP_PANEL_SIZE := Vector2(560, 480)

# 区域枢纽总览：区域列表来自 data/configs/world/regions.json（填表模式，ConfigManager 读取），不再硬编码

@onready var _title: Label = $Panel/Margin/VLayout/Title
@onready var _area: Label = $Panel/Margin/VLayout/Area
@onready var _clock: Label = $Panel/Margin/VLayout/Clock
@onready var _grid_title: Label = $Panel/Margin/VLayout/GridTitle
@onready var _grid: GridContainer = $Panel/Margin/VLayout/Grid
@onready var _hint: Label = $Panel/Margin/VLayout/Hint
@onready var _close: Button = $Panel/Margin/VLayout/Close

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	focus_mode = Control.FOCUS_NONE
	_build()
	# 响应式锚点：小视口内缩防溢出 + 分辨率变化自动重排居中
	_fit_responsive()
	var vp := get_viewport()
	if vp != null and not vp.size_changed.is_connected(_fit_responsive):
		vp.size_changed.connect(_fit_responsive)
	if not tree_exiting.is_connected(_cleanup_responsive):
		tree_exiting.connect(_cleanup_responsive)

func _fit_responsive() -> void:
	var panel := $Panel as Control
	if panel == null:
		return
	UICenterUtils.fit_panel_to_viewport(panel, MAP_PANEL_SIZE)

func _cleanup_responsive() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_fit_responsive):
		vp.size_changed.disconnect(_fit_responsive)

func _build() -> void:
	_title.text = tr("ui_map_title")
	_refresh_area_label()
	_clock.text = _world_clock_text()
	_grid_title.text = tr("ui_map_hub")
	_fill_grid()
	_hint.text = tr("ui_map_hint")
	_close.text = tr("ui_map_close")
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(UIManager.close_screen.bind(self))

func _refresh_area_label() -> void:
	var cur: Dictionary = ConfigManager.get_region(GameManager.current_region_id)
	_area.text = tr("ui_map_current") % cur.get("name", GameManager.current_region_id)

func _fill_grid() -> void:
	for id in ConfigManager.get_all_region_ids():
		var region: Dictionary = ConfigManager.get_region(id)
		var name: String = region.get("name", id)
		var btn := Button.new()
		btn.text = name
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
		if id == GameManager.current_region_id:
			btn.add_theme_color_override("font_color", UIPalette.GOLD)
		btn.pressed.connect(_on_region_pressed.bind(id))
		_grid.add_child(btn)

func _on_region_pressed(id: String) -> void:
	GameManager.goto_region(id)

func _world_clock_text() -> String:
	return "第 %d 天 · %s · %s" % [
		WeatherTimeService.get_day(),
		WorldEnums.season_name(WeatherTimeService.get_season()),
		WorldEnums.weather_name(WeatherTimeService.get_weather()),
	]

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后填充示例地图（规避 GameManager）
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_title = $Panel/Margin/VLayout/Title
	_area = $Panel/Margin/VLayout/Area
	_clock = $Panel/Margin/VLayout/Clock
	_grid_title = $Panel/Margin/VLayout/GridTitle
	_grid = $Panel/Margin/VLayout/Grid
	_hint = $Panel/Margin/VLayout/Hint
	_close = $Panel/Margin/VLayout/Close
	if _title == null or _grid == null:
		return
	_title.text = tr("ui_map_title")
	_area.text = "当前区域：%s" % _first_region_name()
	_clock.text = "第 12 天 · 春 · 晴"
	_grid_title.text = tr("ui_map_hub")
	_close.text = tr("ui_map_close")
	_hint.text = tr("ui_map_hint")
	for id in ConfigManager.get_all_region_ids():
		var region: Dictionary = ConfigManager.get_region(id)
		var name: String = region.get("name", id)
		var btn := Button.new()
		btn.text = name
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 16)
		_grid.add_child(btn)

## 取区域表第一个区域名（仅配置，不碰 GameManager）
func _first_region_name() -> String:
	var ids: Array = ConfigManager.get_all_region_ids()
	if ids.is_empty():
		return "未知"
	var reg: Dictionary = ConfigManager.get_region(String(ids[0]))
	return String(reg.get("name", ids[0]))
