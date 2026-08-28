# tools/gen_ui_theme.gd
# P0 整改生成器：一键产出全局 UI 主题（中文字体 + 配色 + 控件样式）
# 运行：Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/武侠游戏" --script "D:/武侠游戏/tools/gen_ui_theme.gd"
#
# 设计原则（大厂风格·单一真源）：
#   1. 字体只在此处集中接线，界面脚本一律不散落字体/字号设置；
#   2. 配色直接复用 core/constants/ui_theme.gd 的 UIPalette，避免两套色值漂移；
#   3. 通过工程默认主题(gui/theme/custom)下发，代码动态生成的 Control 也自动继承，
#      无需逐个界面改造（零侵入）。

@warning_ignore("shadowed_global_identifier")

extends SceneTree

const REGULAR_PATH := "res://resources/fonts/SiYuanSongTiRegular/SourceHanSerifCN-Regular-1.otf"
const BOLD_PATH := "res://resources/fonts/SiYuanSongTiRegular/SourceHanSerifCN-Bold-2.otf"
const THEME_PATH := "res://resources/themes/ui_theme.tres"

# 复用既有调色板，保证与现有界面美术一致（来源：core/constants/ui_theme.gd）
const UIPalette = preload("res://core/constants/ui_theme.gd")

func _initialize() -> void:
	var regular: FontFile = load(REGULAR_PATH) as FontFile
	var bold: FontFile = load(BOLD_PATH) as FontFile
	if regular == null or bold == null:
		push_error("P0_FONT_FAIL: 字体加载失败，请确认 .otf 已正确放入 resources/fonts/ 并被引擎识别")
		quit(1)
		return

	# 字形自检：思源宋体必须包含「江湖」二字，否则中文会出方框
	if not regular.has_char(0x6C5F) or not regular.has_char(0x6E56):
		push_error("P0_GLYPH_FAIL: Regular 字体不含中文字形，CJK 渲染将失败")
		quit(1)
		return

	var theme := Theme.new()
	theme.default_font = regular
	theme.default_font_size = 18
	# Godot 4 的 Theme 无 bold_font 直接属性；粗体通过 RichTextLabel 的 "bold_font" 主题项提供，
	# 供正文里 [b] 等加粗标签使用（普通 Label/Button 不自带上粗体，需加粗时另行覆盖）
	theme.set_font("bold_font", "RichTextLabel", bold)

	var c_text_main := UIPalette.TEXT_MAIN
	var c_text_secondary := UIPalette.TEXT_SECONDARY
	var c_disabled := UIPalette.DISABLED
	var c_gold := UIPalette.GOLD
	var c_gold_dark := UIPalette.GOLD_DARK
	var c_panel := UIPalette.PANEL_DARK
	var c_btn_bg := Color(0.210, 0.176, 0.149)
	var c_btn_hover := Color(0.290, 0.235, 0.180)
	var c_btn_pressed := Color(0.149, 0.122, 0.102)
	var c_input_bg := Color(0.118, 0.098, 0.082)
	var c_pb_bg := Color(0.137, 0.114, 0.094)

	# --- 文字颜色基线（Control 未单独覆盖时使用）---
	theme.set_color("font_color", "Label", c_text_main)
	theme.set_color("font_color", "LineEdit", c_text_main)
	theme.set_color("font_placeholder_color", "LineEdit", c_text_secondary)
	theme.set_color("font_color", "RichTextLabel", c_text_main)
	theme.set_color("font_color", "Tree", c_text_main)
	theme.set_color("font_color", "ItemList", c_text_main)
	theme.set_color("font_color", "TabBar", c_text_main)
	theme.set_color("font_color", "OptionButton", c_text_main)

	# --- 按钮配色 ---
	theme.set_color("font_color", "Button", c_text_main)
	theme.set_color("font_hover_color", "Button", c_gold)
	theme.set_color("font_pressed_color", "Button", c_gold_dark)
	theme.set_color("font_focus_color", "Button", c_gold)
	theme.set_color("font_disabled_color", "Button", c_disabled)
	theme.set_color("icon_normal_color", "Button", c_text_main)
	theme.set_color("icon_hover_color", "Button", c_gold)
	theme.set_color("icon_pressed_color", "Button", c_gold_dark)
	theme.set_color("icon_disabled_color", "Button", c_disabled)

	# --- 面板样式（深棕底 + 金边）---
	var panel_sb := StyleBoxFlat.new()
	panel_sb.bg_color = c_panel
	panel_sb.border_color = c_gold
	panel_sb.set_border_width_all(2)
	panel_sb.set_corner_radius_all(8)
	panel_sb.set_content_margin_all(16)
	theme.set_stylebox("panel", "Panel", panel_sb)
	theme.set_stylebox("panel", "PanelContainer", panel_sb)

	# --- 按钮样式 ---
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = c_btn_bg
	btn_normal.border_color = c_gold
	btn_normal.set_border_width_all(1)
	btn_normal.set_corner_radius_all(6)
	btn_normal.set_content_margin_all(10)
	var btn_hover := btn_normal.duplicate() as StyleBoxFlat
	btn_hover.bg_color = c_btn_hover
	var btn_pressed := btn_normal.duplicate() as StyleBoxFlat
	btn_pressed.bg_color = c_btn_pressed
	var btn_disabled := btn_normal.duplicate() as StyleBoxFlat
	btn_disabled.bg_color = c_btn_pressed
	btn_disabled.border_color = c_disabled
	var btn_focus := btn_normal.duplicate() as StyleBoxFlat
	btn_focus.border_color = c_gold
	btn_focus.set_border_width_all(2)
	theme.set_stylebox("normal", "Button", btn_normal)
	theme.set_stylebox("hover", "Button", btn_hover)
	theme.set_stylebox("pressed", "Button", btn_pressed)
	theme.set_stylebox("disabled", "Button", btn_disabled)
	theme.set_stylebox("focus", "Button", btn_focus)

	# --- 输入框样式 ---
	var le_normal := StyleBoxFlat.new()
	le_normal.bg_color = c_input_bg
	le_normal.border_color = c_text_secondary
	le_normal.set_border_width_all(1)
	le_normal.set_corner_radius_all(4)
	le_normal.set_content_margin_all(8)
	var le_focus := le_normal.duplicate() as StyleBoxFlat
	le_focus.border_color = c_gold
	le_focus.set_border_width_all(2)
	theme.set_stylebox("normal", "LineEdit", le_normal)
	theme.set_stylebox("focus", "LineEdit", le_focus)
	theme.set_stylebox("read_only", "LineEdit", le_normal)

	# --- 进度条样式 ---
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = c_pb_bg
	pb_bg.set_corner_radius_all(4)
	var pb_fill := StyleBoxFlat.new()
	pb_fill.bg_color = c_gold
	pb_fill.set_corner_radius_all(4)
	theme.set_stylebox("bg", "ProgressBar", pb_bg)
	theme.set_stylebox("fill", "ProgressBar", pb_fill)

	# --- 保存主题资源 ---
	var err := ResourceSaver.save(theme, THEME_PATH)
	if err != OK:
		push_error("P0_THEME_SAVE_FAIL: 主题保存失败，错误码 %d" % err)
		quit(1)
		return

	# --- 接线为工程默认主题（所有界面自动继承，含代码动态生成的 Control）---
	ProjectSettings.set_setting("gui/theme/custom", THEME_PATH)
	var perr := ProjectSettings.save()
	if perr != OK:
		push_error("P0_PROJECT_SAVE_FAIL: 工程设置保存失败，错误码 %d" % perr)
		quit(1)
		return

	print("P0_THEME_OK default_font=%s bold_font=%s theme=%s" % [regular.resource_path, bold.resource_path, THEME_PATH])
	quit(0)
