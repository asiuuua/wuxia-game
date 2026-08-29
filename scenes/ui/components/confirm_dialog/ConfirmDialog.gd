# scenes/ui/components/confirm_dialog/ConfirmDialog.gd
# 通用确认弹窗（代码构建 Control，无 .tscn/无 class_name；经 UIManager.show_popup("ConfirmDialog") 实例化）
# 职责：标题 + 内容 + 确定/取消按钮；遮罩拦截点击；0.2s 淡入、0.2s 淡出关闭
#       键盘 ui_accept=确认 / ui_cancel=取消；确定回调可选
# 设计稿 §6 实现（动画用淡入淡出占位，真实缩放动画待美术资源）

@warning_ignore("shadowed_global_identifier")

extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

@warning_ignore("unused_signal")
signal confirmed()
@warning_ignore("unused_signal")
signal cancelled()

var _title_label: Label = null
var _content_label: Label = null
var _confirm_btn: Button = null
var _cancel_btn: Button = null

var _confirm_callback: Callable = Callable()
var _cancel_callback: Callable = Callable()
var _closing: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()

func _build_ui() -> void:
	var dim: ColorRect = ColorRect.new()
	dim.color = UIPalette.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel: Panel = Panel.new()
	panel.size = Vector2(440, 220)
	panel.custom_minimum_size = Vector2(440, 220)
	UICenterUtils.center_panel(panel)   # 修复 Godot4.7.2 PRESET_CENTER 不居中
	# === 磨砂玻璃面板（替代原棕底 + 金边）===
	# 背景半透冷调深蓝黑 + 细白边 + 柔和阴影，营造"漂浮在背景之上"的玻璃质感
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GLASS_BORDER
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	sb.shadow_color = UIPalette.GLASS_SHADOW
	# 内边距由内层 VBox 控制，这里留 1px 让边框不被内容压没
	sb.content_margin_left = 1
	sb.content_margin_right = 1
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)

	var vbox: VBoxContainer = VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 16)
	vbox.add_theme_constant_override("margin_left", 28)
	vbox.add_theme_constant_override("margin_top", 24)
	vbox.add_theme_constant_override("margin_right", 28)
	vbox.add_theme_constant_override("margin_bottom", 24)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override("font_size", 22)
	_title_label.add_theme_color_override("font_color", UIPalette.GOLD)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_title_label)

	_content_label = Label.new()
	_content_label.add_theme_font_size_override("font_size", 15)
	_content_label.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_content_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(_content_label)

	var btn_row: HBoxContainer = HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 20)
	vbox.add_child(btn_row)

	_confirm_btn = Button.new()
	# 文字由 setup(...) 运行时填充；这里只创建空按钮避免 Parse Error
	_confirm_btn.text = ""
	_apply_glass_button_style(_confirm_btn, UIPalette.SUCCESS)
	_confirm_btn.pressed.connect(_on_confirm)
	btn_row.add_child(_confirm_btn)

	_cancel_btn = Button.new()
	_cancel_btn.text = ""
	_apply_glass_button_style(_cancel_btn, UIPalette.TEXT_SECONDARY)
	_cancel_btn.pressed.connect(_on_cancel)
	btn_row.add_child(_cancel_btn)

## 应用"磨砂玻璃"按钮样式：透明半透冷调底 + 极细白边，无填充焦点描边，仅文字变色标识选中
## font_color: SUCCESS=确认(墨绿)/TEXT_SECONDARY=取消(次级灰白)
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
	sb_normal.content_margin_left = 20
	sb_normal.content_margin_right = 20
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
	btn.add_theme_stylebox_override("focus", sb_hover)  # 焦点：复用 hover 视觉
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_color_override("font_hover_color", UIPalette.TEXT_MAIN)
	btn.add_theme_color_override("font_pressed_color", font_color)
	btn.add_theme_font_size_override("font_size", UIPalette.FS_SUB)

## 填充内容并播放入场动画；按钮可选，缺省仅发信号
func setup(title: String, content: String, confirm_callback: Callable = Callable(), cancel_callback: Callable = Callable(), confirm_text: String = tr("ui_confirm_ok"), cancel_text: String = tr("ui_confirm_cancel")) -> void:
	if _title_label == null:
		return
	_title_label.text = title
	_content_label.text = content
	_confirm_btn.text = confirm_text
	_cancel_btn.text = cancel_text
	_confirm_callback = confirm_callback
	_cancel_callback = cancel_callback
	# 入场淡入已由 UIManager.open_screen 统一处理，此处仅聚焦首个按钮
	_confirm_btn.grab_focus()

# ⚠️ 去重：确认钮聚焦时按 Enter 会同时触发「pressed 信号」与「_unhandled_input(ui_accept)」两条路径。
# 若仅在 _close() 里守 _closing，回调仍会被两条路径各执行一次（对破坏性回调是真实双执行 bug）。
# 故将 _closing 守卫前置到 _on_confirm/_on_cancel 入口，确保回调与信号只触发一次。
func _on_confirm() -> void:
	if _closing:
		return
	_closing = true
	if _confirm_callback.is_valid():
		_confirm_callback.call()
	confirmed.emit()
	UIManager.close_screen(self)

func _on_cancel() -> void:
	if _closing:
		return
	_closing = true
	if _cancel_callback.is_valid():
		_cancel_callback.call()
	cancelled.emit()
	UIManager.close_screen(self)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_accept"):
		_on_confirm()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
