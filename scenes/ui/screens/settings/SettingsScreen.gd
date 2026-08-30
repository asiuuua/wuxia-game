@tool
# scenes/ui/screens/settings/SettingsScreen.gd
# 设置弹窗（独立弹窗，非全屏界面）：
#   - 压暗遮罩(点击外部关闭) + 居中磨砂玻璃面板(GLASS_BG 风格，圆角/细白边/阴影) + 内部 header/左分类/右动态面板
#   - 三种关闭：返回按钮 / ESC(ui_cancel) / 点击遮罩
#   - 自适应视口尺寸并居中；语言切换只重建内部内容，弹窗框架保持
#   - 颜色集中引用 UIPalette；磨砂玻璃按钮样式对齐 ConfirmDialog（ui 美工设计规范）
# 业务：五分类（音频/画面/控制/游戏/语言）左侧导航 + 右侧动态面板；
#       滑块/下拉/开关/键位重绑定均实时生效并自动持久化到 user://settings.json。

@warning_ignore("shadowed_global_identifier")

extends PopupBase

const UIPalette = preload("res://core/constants/ui_theme.gd")

const CATEGORIES := ["audio", "graphics", "control", "game", "language"]
# 字典值统一存 tr 键，显示时再 tr() 解析，便于本地化切换
const CATEGORY_LABELS := {
	"audio": "cat_audio",
	"graphics": "cat_graphics",
	"control": "cat_control",
	"game": "cat_game",
	"language": "cat_language",
}

const ACTION_LABELS := {
	"move_up": "ctrl_move_up",
	"move_down": "ctrl_move_down",
	"move_left": "ctrl_move_left",
	"move_right": "ctrl_move_right",
	"toggle_inventory": "ctrl_inventory",
	"toggle_map": "ctrl_map",
	"toggle_attributes": "ctrl_attributes",
}

# B 路线（2026-08-29）：静态壳（压暗底 Backdrop + 磨砂玻璃 Panel + Header + Body 内
# CategoryList / PanelContainer / PanelVBox）已迁入 SettingsScreen.tscn，美术可在编辑器改框架
# 外观/边距；脚本只保留动态内容（分类按钮 + 各分类面板滑块/下拉/开关/键位重绑）与交互逻辑。
# B 路线（2026-08-30）：顶部栏三个静态节点（BackBtn / TitleLabel / HintLabel）一并迁入 .tscn。
# B 路线：Header / Body 已迁入 Panel 内部（受磨砂玻璃面板框住），故路径需带 $Panel 前缀
@onready var _backdrop: ColorRect = $Backdrop
@onready var _panel: Panel = $Panel
@onready var _category_list: VBoxContainer = $Panel/Body/CategoryList
@onready var _panel_container: ScrollContainer = $Panel/Body/PanelContainer
@onready var _panel_vbox: VBoxContainer = $Panel/Body/PanelContainer/PanelVBox
# B 路线（2026-08-30）：顶部栏三个静态节点已迁入 SettingsScreen.tscn，美术可直接改样式/顺序
@onready var _back_btn: Button = $Panel/Header/BackBtn
@onready var _title_label: Label = $Panel/Header/TitleLabel
@onready var _hint_label: Label = $Panel/Header/HintLabel

var _current_category: String = "audio"
var _category_buttons: Array = []      # 左侧分类按钮（Control）

# 键位重绑定临时态
var _rebinding_action: String = ""
var _rebinding_button: Button = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	popup_id = "Settings"
	_build_backdrop()
	_build_panel_frame()
	_build_header()
	_build_body()
	_build_categories()
	_select_category(_current_category)
	# 视口尺寸变化（分辨率/窗口缩放）时重新居中并限位，避免弹窗出界或错位
	if not get_viewport().size_changed.is_connected(_fit_panel):
		get_viewport().size_changed.connect(_fit_panel)
	# 键盘可达性：进入设置即把焦点落到返回按钮，明确焦点落点
	if _category_buttons.size() > 0:
		(_category_buttons[0] as Button).grab_focus()

# === 压暗遮罩：点击外部关闭弹窗 ===
func _build_backdrop() -> void:
	_backdrop.gui_input.connect(_on_backdrop_input)

func _on_backdrop_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_go_back()
		get_viewport().set_input_as_handled()

# === 磨砂玻璃面板框架（圆角/细白边/阴影），自适应居中 ===
# 面板与磨砂玻璃样式已迁移到 SettingsScreen.tscn（美术可改）；本函数只负责运行时按视口居中。
func _build_panel_frame() -> void:
	_fit_panel()

func _fit_panel() -> void:
	if _panel == null:
		return
	var vp: Vector2 = get_viewport_rect().size
	# 大屏封顶，小屏自适应留边（左右各 ~4%，上下各 ~5%）
	var w: float = mini(vp.x * 0.92, 960.0)
	var h: float = mini(vp.y * 0.90, 680.0)
	_panel.size = Vector2(w, h)
	_panel.custom_minimum_size = Vector2(w, h)
	UICenterUtils.center_panel(_panel)   # 修复 Godot4.7.2 PRESET_CENTER 不居中

# === 顶部栏（返回 + 标题 + 重绑提示）：静态节点在 SettingsScreen.tscn，这里只填文案与连线 ===
func _build_header() -> void:
	_back_btn.text = tr("back_btn")
	_back_btn.pressed.connect(_go_back)
	_title_label.text = tr("settings_title")
	_hint_label.text = ""

# === 主体布局：左分类 + 右面板（位于面板内部，header 之下撑满） ===
# 静态结构（Body + CategoryList + PanelContainer + PanelVBox）已迁入 SettingsScreen.tscn，
# 美术可改布局/边距；本函数保留为扩展钩子。
func _build_body() -> void:
	pass

# === 左侧分类按钮 ===
func _build_categories() -> void:
	for cat in CATEGORIES:
		var btn: Button = Button.new()
		btn.name = cat
		btn.text = tr(CATEGORY_LABELS[cat])
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.custom_minimum_size = Vector2(160, 42)
		_apply_glass_button_style(btn, UIPalette.TEXT_MAIN)
		btn.pressed.connect(_on_category_pressed.bind(cat))
		_category_list.add_child(btn)
		_category_buttons.append(btn)

func _on_category_pressed(cat: String) -> void:
	_select_category(cat)

func _select_category(cat: String) -> void:
	_current_category = cat
	for btn in _category_buttons:
		var b: Button = btn as Button
		var is_cur: bool = (b.name == cat)
		b.add_theme_color_override("font_color", UIPalette.GOLD if is_cur else UIPalette.TEXT_MAIN)
	# 清空右侧并重建
	for child in _panel_vbox.get_children():
		child.queue_free()
	match cat:
		"audio": _build_audio_panel()
		"graphics": _build_graphics_panel()
		"control": _build_control_panel()
		"game": _build_game_panel()
		"language": _build_language_panel()
	_add_reset_button(cat)

# === 通用行构造 ===
func _make_row(label_text: String) -> HBoxContainer:
	var row: HBoxContainer = HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	var label: Label = Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(160, 0)
	label.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_panel_vbox.add_child(row)
	return row

func _add_slider(row: HBoxContainer, value: float, cb: Callable) -> void:
	var slider: HSlider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = value
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size = Vector2(220, 0)
	var val_label: Label = Label.new()
	val_label.custom_minimum_size = Vector2(56, 0)
	val_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	val_label.text = "%d%%" % int(value * 100)
	slider.value_changed.connect(func(v: float):
		val_label.text = "%d%%" % int(v * 100)
		cb.call(v)
	)
	row.add_child(slider)
	row.add_child(val_label)

func _add_option(row: HBoxContainer, options: PackedStringArray, current: String, cb: Callable) -> void:
	var ob: OptionButton = OptionButton.new()
	ob.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ob.custom_minimum_size = Vector2(220, 0)
	var idx: int = 0
	for opt in options:
		ob.add_item(opt)
		if opt == current:
			idx = ob.get_item_count() - 1
	ob.select(idx)
	_apply_glass_button_style(ob, UIPalette.TEXT_MAIN)
	ob.item_selected.connect(func(i: int):
		cb.call(options[i])
	)
	row.add_child(ob)

func _add_toggle(row: HBoxContainer, value: bool, cb: Callable) -> void:
	var btn: Button = Button.new()
	btn.custom_minimum_size = Vector2(120, 0)
	# 毛砂玻璃样式（去掉默认棕色填充，与分类/下拉按钮视觉一致）
	_apply_glass_button_style(btn, UIPalette.SUCCESS if value else UIPalette.TEXT_SECONDARY)
	btn.text = tr("toggle_on") if value else tr("toggle_off")
	btn.pressed.connect(func():
		var nv: bool = not (btn.text == tr("toggle_on"))
		btn.text = tr("toggle_on") if nv else tr("toggle_off")
		# 开=绿、关=米灰，颜色随状态切换但底色始终毛玻璃
		btn.add_theme_color_override("font_color", UIPalette.SUCCESS if nv else UIPalette.TEXT_SECONDARY)
		cb.call(nv)
	)
	row.add_child(btn)

# === 音频面板 ===
func _build_audio_panel() -> void:
	var cats := ["master", "music", "sfx", "voice"]
	var labels := {"master": "aud_master", "music": "aud_music", "sfx": "aud_sfx", "voice": "aud_voice"}
	for c in cats:
		var row: HBoxContainer = _make_row(tr(labels[c]))
		_add_slider(row, SettingsManager.get_audio_volume(c), func(v): SettingsManager.set_audio_volume(c, v))

	var test_row: HBoxContainer = _make_row(tr("aud_test_label"))
	var test_btn: Button = Button.new()
	test_btn.text = tr("aud_test")
	_apply_glass_button_style(test_btn, UIPalette.TEXT_SECONDARY)
	test_btn.pressed.connect(func():
		if AudioManager != null and AudioManager.has_method("play_sfx"):
			# 当前无音效资源，仅打点；真实资源后接入
			GameLogger.info("Settings", "播放测试音效（资源待接入）")
	)
	test_row.add_child(test_btn)

# === 画面面板 ===
func _build_graphics_panel() -> void:
	var res_row: HBoxContainer = _make_row(tr("gfx_resolution"))
	var res_opts: PackedStringArray = PackedStringArray(SettingsManager.RESOLUTIONS)
	_add_option(res_row, res_opts, str(SettingsManager.get_graphics("resolution")), func(v): SettingsManager.set_graphics("resolution", v))

	var mode_row: HBoxContainer = _make_row(tr("gfx_display_mode"))
	# 显示模式选项本地化为中文（窗口模式/全屏模式/最大化），下拉显示 label、回写存储值
	var mode_labels := PackedStringArray()
	var current_mode: String = str(SettingsManager.get_graphics("display_mode"))
	var current_label: String = tr("gfx_mode_windowed")
	for mode_val in SettingsManager.DISPLAY_MODES:
		var lbl: String = tr(SettingsManager.DISPLAY_MODE_LABELS.get(mode_val, "gfx_mode_windowed"))
		mode_labels.append(lbl)
		if mode_val == current_mode:
			current_label = lbl
	_add_option(mode_row, mode_labels, current_label, func(v):
		# 把选中的中文 label 反查回存储值
		for mode_val in SettingsManager.DISPLAY_MODES:
			if tr(SettingsManager.DISPLAY_MODE_LABELS.get(mode_val, "gfx_mode_windowed")) == v:
				SettingsManager.set_graphics("display_mode", mode_val)
				break
	)

	var vsync_row: HBoxContainer = _make_row(tr("gfx_vsync"))
	_add_toggle(vsync_row, bool(SettingsManager.get_graphics("vsync")), func(v): SettingsManager.set_graphics("vsync", v))

	var fps_row: HBoxContainer = _make_row(tr("gfx_fps"))
	var fps_opts: PackedStringArray = PackedStringArray(["30", "60", "120", "144", "0"])
	_add_option(fps_row, fps_opts, str(int(SettingsManager.get_graphics("fps_limit"))), func(v): SettingsManager.set_graphics("fps_limit", int(v)))

	var qual_row: HBoxContainer = _make_row(tr("gfx_quality"))
	var qual_opts: PackedStringArray = PackedStringArray(SettingsManager.QUALITY_LEVELS)
	_add_option(qual_row, qual_opts, str(SettingsManager.get_graphics("quality")), func(v): SettingsManager.set_graphics("quality", v))

	var rs_row: HBoxContainer = _make_row(tr("gfx_render_scale"))
	# 渲染分辨率（内部渲染倍率）：中文标签显示百分比，回写对应 float 倍率
	var rs_labels := PackedStringArray()
	var cur_rs: float = float(SettingsManager.get_graphics("render_scale"))
	var cur_rs_label: String = tr("gfx_rs_100")
	for rs_val in SettingsManager.RENDER_SCALES:
		var lbl: String = tr(SettingsManager.RENDER_SCALE_LABELS.get(rs_val, "gfx_rs_100"))
		rs_labels.append(lbl)
		if abs(rs_val - cur_rs) < 0.001:
			cur_rs_label = lbl
	_add_option(rs_row, rs_labels, cur_rs_label, func(lbl):
		for rs_val in SettingsManager.RENDER_SCALES:
			if tr(SettingsManager.RENDER_SCALE_LABELS.get(rs_val, "gfx_rs_100")) == lbl:
				SettingsManager.set_graphics("render_scale", rs_val)
				break
	)

	# UI 缩放（界面/文字大小）：与上面「渲染分辨率」是两条独立设置，互不影响
	var ui_row: HBoxContainer = _make_row(tr("gfx_ui_scale"))
	var ui_labels := PackedStringArray()
	var cur_ui: float = float(SettingsManager.get_graphics("ui_scale"))
	var cur_ui_label: String = tr("gfx_ui_100")
	for ui_val in SettingsManager.UI_SCALES:
		var lbl: String = tr(SettingsManager.UI_SCALE_LABELS.get(ui_val, "gfx_ui_100"))
		ui_labels.append(lbl)
		if abs(ui_val - cur_ui) < 0.001:
			cur_ui_label = lbl
	_add_option(ui_row, ui_labels, cur_ui_label, func(lbl):
		for ui_val in SettingsManager.UI_SCALES:
			if tr(SettingsManager.UI_SCALE_LABELS.get(ui_val, "gfx_ui_100")) == lbl:
				SettingsManager.set_graphics("ui_scale", ui_val)
				break
	)

# === 控制面板（键位重绑定） ===
func _build_control_panel() -> void:
	for action in SettingsManager.REBINDABLE_ACTIONS:
		var row: HBoxContainer = _make_row(tr(ACTION_LABELS.get(action, action)))
		var key_btn: Button = Button.new()
		key_btn.custom_minimum_size = Vector2(160, 0)
		key_btn.text = OS.get_keycode_string(SettingsManager.get_binding(action))
		_apply_glass_button_style(key_btn, UIPalette.TEXT_MAIN)
		key_btn.pressed.connect(_on_rebind_pressed.bind(action, key_btn))
		row.add_child(key_btn)

# === 游戏面板 ===
func _build_game_panel() -> void:
	var diff_row: HBoxContainer = _make_row(tr("game_difficulty"))
	var diff_opts: PackedStringArray = PackedStringArray(SettingsManager.DIFFICULTY_LEVELS)
	_add_option(diff_row, diff_opts, str(SettingsManager.get_game("difficulty")), func(v): SettingsManager.set_game("difficulty", v))

	var auto_row: HBoxContainer = _make_row(tr("game_autosave"))
	_add_toggle(auto_row, bool(SettingsManager.get_game("autosave")), func(v): SettingsManager.set_game("autosave", v))

	var speed_row: HBoxContainer = _make_row(tr("game_text_speed"))
	var speed_opts: PackedStringArray = PackedStringArray(SettingsManager.TEXT_SPEED_LEVELS)
	_add_option(speed_row, speed_opts, str(SettingsManager.get_game("text_speed")), func(v): SettingsManager.set_game("text_speed", v))

# === 语言面板 ===
func _build_language_panel() -> void:
	var row: HBoxContainer = _make_row(tr("lang_ui"))
	var opts: PackedStringArray = PackedStringArray(["简体中文", "繁體中文", "English"])
	var current_locale: String = SettingsManager.get_language()
	var current_text: String = "简体中文"
	match current_locale:
		"zh_TW": current_text = "繁體中文"
		"en": current_text = "English"
	_add_option(row, opts, current_text, func(v):
		var locale: String = "zh_CN"
		if v == "繁體中文":
			locale = "zh_TW"
		elif v == "English":
			locale = "en"
		SettingsManager.set_language(locale)
		if LocalizationManager != null and LocalizationManager.has_method("set_locale"):
			LocalizationManager.set_locale(locale)
		call_deferred("_rebuild_ui")
	)

# === 恢复默认 ===
func _rebuild_ui() -> void:
	# 语言切换后只重建内部内容（header 文案 + 分类 + 右面板），不动弹窗框架/遮罩
	if _title_label != null:
		_title_label.text = tr("settings_title")
	if _hint_label != null:
		_hint_label.text = ""
	_rebinding_action = ""
	_rebinding_button = null
	# 刷新左侧分类按钮文案（按各自 cat 重新 tr()），再重建右侧面板
	for b in _category_buttons:
		var btn: Button = b as Button
		if btn != null:
			btn.text = tr(CATEGORY_LABELS[String(btn.name)])
	_select_category(_current_category)
	# 语言切换重建后，恢复键盘焦点落点到首个分类按钮
	if not _category_buttons.is_empty():
		(_category_buttons[0] as Button).grab_focus()

func _add_reset_button(cat: String) -> void:
	var spacer: Control = Control.new()
	spacer.custom_minimum_size = Vector2(0, 12)
	_panel_vbox.add_child(spacer)
	var btn: Button = Button.new()
	btn.text = tr("reset_btn") % tr(CATEGORY_LABELS[cat])
	btn.custom_minimum_size = Vector2(200, 36)
	_apply_glass_button_style(btn, UIPalette.TEXT_SECONDARY)
	btn.pressed.connect(func():
		SettingsManager.reset_category(cat)
		_select_category(cat)
	)
	_panel_vbox.add_child(btn)

# === 关闭 ===
func _go_back() -> void:
	request_close()

# === 键位重绑定捕获 + ESC 关闭 ===
func _on_rebind_pressed(action: String, btn: Button) -> void:
	_rebinding_action = action
	_rebinding_button = btn
	_hint_label.text = tr("rebind_hint") % tr(ACTION_LABELS.get(action, action))
	btn.text = tr("rebind_prompt")

func _unhandled_input(event: InputEvent) -> void:
	# 顶层守卫：仅栈顶（当前弹窗）响应，避免被底层界面吞/抢输入
	if UIManager.get_current_screen() != self:
		return
	if _rebinding_action != "":
		if event is InputEventKey and event.pressed and not event.echo:
			var keycode: int = event.keycode
			SettingsManager.rebind(_rebinding_action, keycode)
			if _rebinding_button != null:
				_rebinding_button.text = OS.get_keycode_string(keycode)
			_rebinding_action = ""
			_rebinding_button = null
			_hint_label.text = ""
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_go_back()
		get_viewport().set_input_as_handled()

# === 磨砂玻璃按钮样式（对齐 ConfirmDialog，ui 美工规范） ===
# font_color: 常态文字色；hover 白、pressed 更亮边框
func _apply_glass_button_style(btn: Button, font_color: Color) -> void:
	var sb_normal := StyleBoxFlat.new()
	sb_normal.bg_color = UIPalette.GLASS_BG
	sb_normal.border_width_left = 1
	sb_normal.border_width_top = 1
	sb_normal.border_width_right = 1
	sb_normal.border_width_bottom = 1
	sb_normal.border_color = UIPalette.GLASS_BORDER
	sb_normal.corner_radius_top_left = 8
	sb_normal.corner_radius_top_right = 8
	sb_normal.corner_radius_bottom_left = 8
	sb_normal.corner_radius_bottom_right = 8
	sb_normal.content_margin_left = 18
	sb_normal.content_margin_right = 18
	sb_normal.content_margin_top = 8
	sb_normal.content_margin_bottom = 8

	var sb_hover := sb_normal.duplicate() as StyleBoxFlat
	sb_hover.bg_color = UIPalette.GLASS_BG_HOVER
	sb_hover.border_color = UIPalette.GLASS_BORDER_FOCUS

	var sb_pressed := sb_normal.duplicate() as StyleBoxFlat
	sb_pressed.bg_color = Color(0.05, 0.06, 0.09, 0.90)
	sb_pressed.border_color = UIPalette.GLASS_BORDER_FOCUS

	btn.add_theme_stylebox_override("normal", sb_normal)
	btn.add_theme_stylebox_override("hover", sb_hover)
	btn.add_theme_stylebox_override("pressed", sb_pressed)
	btn.add_theme_stylebox_override("focus", sb_hover)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", UIPalette.TEXT_MAIN)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_font_size_override("font_size", UIPalette.FS_SUB)

# === 编辑器预览（UIPreview 调用）：手动赋值 @onready 后调真实构建方法；面板内容在 SettingsManager 可用时展开 ===
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_back_btn = get_node_or_null("Panel/Header/BackBtn")
	_title_label = get_node_or_null("Panel/Header/TitleLabel")
	_hint_label = get_node_or_null("Panel/Header/HintLabel")
	_category_list = get_node_or_null("Panel/Body/CategoryList")
	_panel_vbox = get_node_or_null("Panel/Body/PanelContainer/PanelVBox")
	_current_category = "audio"
	if _back_btn == null or _title_label == null or _category_list == null or _panel_vbox == null:
		return
	_build_header()
	_build_categories()
	if is_instance_valid(SettingsManager):
		_select_category("audio")
