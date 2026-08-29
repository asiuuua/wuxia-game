# scenes/ui/overlays/map/MapScreen.gd
# 地图面板（M 键开关）：当前区域 + 世界时钟 + 区域枢纽总览
# 铁律：UI 只展示与输入，数据来自 WeatherTimeService / ConfigManager

@warning_ignore("shadowed_global_identifier")
extends Control

class_name MapScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")

# 区域枢纽总览（后续接入真实场景注册表后改为配置驱动）
const REGION_KEYS := [
	"region_start_town", "region_sect_gate", "region_market", "region_frontier",
	"region_isle", "region_secret", "region_underworld", "region_desert", "region_snow",
]
const CURRENT_REGION_KEY := "region_start_town"

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_build()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	panel.size = Vector2(560, 480)
	UICenterUtils.center_panel(panel)   # 修复 Godot4.7.2 PRESET_CENTER 不居中
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var title := Label.new()
	title.text = tr("ui_map_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var area := Label.new()
	area.text = tr("ui_map_current") % tr(CURRENT_REGION_KEY)
	v.add_child(area)
	var clock := Label.new()
	clock.text = _world_clock_text()
	v.add_child(clock)
	var grid_title := Label.new()
	grid_title.text = tr("ui_map_hub")
	v.add_child(grid_title)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(grid)
	for key in REGION_KEYS:
		var cell := PanelContainer.new()
		var l := Label.new()
		l.text = tr(key)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if key == CURRENT_REGION_KEY:
			l.add_theme_color_override("font_color", UIPalette.GOLD)
		cell.add_child(l)
		grid.add_child(cell)
	var hint := Label.new()
	hint.text = tr("ui_map_hint")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var close := Button.new()
	close.text = tr("ui_map_close")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(UIManager.close_screen.bind(self))
	v.add_child(close)

func _world_clock_text() -> String:
	return "第 %d 天 · %s · %s" % [
		WeatherTimeService.get_day(),
		WorldEnums.season_name(WeatherTimeService.get_season()),
		WorldEnums.weather_name(WeatherTimeService.get_weather()),
	]
