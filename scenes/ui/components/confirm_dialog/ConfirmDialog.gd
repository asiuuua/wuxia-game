@tool
# scenes/ui/components/confirm_dialog/ConfirmDialog.gd
# 通用确认弹窗（代码构建 Control，无 .tscn/无 class_name；经 UIManager.show_popup("ConfirmDialog") 实例化）
# 职责：标题 + 内容 + 确定/取消按钮；遮罩拦截点击；0.2s 淡入、0.2s 淡出关闭
#       键盘 ui_accept=确认 / ui_cancel=取消；确定回调可选
# 设计稿 §6：入场透明度淡入由 UIManager.open_screen 统一处理；本脚本额外叠加
#       中心缩放弹入（Tween，0.18s TRANS_BACK），替代原「纯淡入占位」动画。

@warning_ignore("shadowed_global_identifier")

extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

@warning_ignore("unused_signal")
signal confirmed()
@warning_ignore("unused_signal")
signal cancelled()

# B 路线（2026-08-29）：静态壳（压暗底 Dim + 磨砂玻璃 Panel + VBox + 标题/内容/按钮行）已迁入
# ConfirmDialog.tscn，美术可在编辑器改外观；脚本只保留动态填充（setup）与交互逻辑。
# 按钮的磨砂玻璃皮肤仍走 _apply_glass_button_style（与设置/存档一致的复用 helper）。
@onready var _title_label: Label = $Panel/VBox/TitleLabel
@onready var _content_label: Label = $Panel/VBox/ContentLabel
@onready var _confirm_btn: Button = $Panel/VBox/BtnRow/ConfirmBtn
@onready var _cancel_btn: Button = $Panel/VBox/BtnRow/CancelBtn

var _confirm_callback: Callable = Callable()
var _cancel_callback: Callable = Callable()
var _closing: bool = false

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build_ui()
	_play_show_anim()

## 入场中心缩放弹入（替代原「纯淡入占位」动画）：与 UIManager 的透明度淡入叠加，
## 让确认框从 92% 弹出到 100%，带轻微回弹。纯代码 Tween，无需美术资源。
## 绑定到 $Panel 的生命周期，弹窗被关闭时 Tween 随节点一并释放，不会悬空。
func _play_show_anim() -> void:
	await get_tree().process_frame  # 等首帧布局完成以取到正确 size，再定中心轴
	var panel := $Panel as Control
	if panel == null:
		return
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.92, 0.92)
	var tw := panel.create_tween()
	tw.tween_property(panel, "scale", Vector2.ONE, 0.18).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)

func _build_ui() -> void:
	# 静态结构（Dim / Panel / VBox / 标题 / 内容 / 按钮行）已迁入 ConfirmDialog.tscn；
	# 此处仅接线按钮信号并套用磨砂玻璃皮肤（与设置/存档弹窗一致）。
	_apply_glass_button_style(_confirm_btn, UIPalette.SUCCESS)
	_apply_glass_button_style(_cancel_btn, UIPalette.TEXT_SECONDARY)
	_confirm_btn.pressed.connect(_on_confirm)
	_cancel_btn.pressed.connect(_on_cancel)

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
	sb_pressed.bg_color = UIPalette.GLASS_BG_PRESSED
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

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后填示例确认框
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_title_label = $Panel/VBox/TitleLabel
	_content_label = $Panel/VBox/ContentLabel
	_confirm_btn = $Panel/VBox/BtnRow/ConfirmBtn
	_cancel_btn = $Panel/VBox/BtnRow/CancelBtn
	if _title_label == null or _confirm_btn == null:
		return
	_apply_glass_button_style(_confirm_btn, UIPalette.SUCCESS)
	_apply_glass_button_style(_cancel_btn, UIPalette.TEXT_SECONDARY)
	setup("确认操作？", "这是一段示例确认文本，用于编辑器预览。点击按钮不会发生任何事。")
