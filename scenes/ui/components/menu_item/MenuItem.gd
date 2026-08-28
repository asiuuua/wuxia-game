# scenes/ui/components/menu_item/MenuItem.gd
# 主菜单选项组件（代码构建 Control，无 .tscn；对齐 LoadingScreen 惯例）
# 交互：鼠标悬停 → 选中（金色箭头 + 文字右移 2px + 变金）；点击/确认 → confirmed；禁用态灰显无交互
# 颜色集中引用 UIPalette，不硬编码（消费方已 preload UIPalette，详见 ui_theme.gd 头部说明）

@warning_ignore("shadowed_global_identifier")

extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

@warning_ignore("unused_signal")
signal selected
@warning_ignore("unused_signal")
signal confirmed

const ARROW := "▶"
const FONT_SIZE := 23

var _label: Label = null
var _arrow: Label = null
var _is_selected: bool = false
var _is_enabled: bool = true
var _pending_text: String = ""   # _build 创建 _label 之前调用 set_text 时暂存，建好后再应用
var _feedback: UIFeedback = null # 交互反馈（缩放动画 + 音效），配置表驱动

func _ready() -> void:
	_build()
	mouse_filter = Control.MOUSE_FILTER_STOP
	# 关键：子项不抢焦点。菜单键盘导航由父容器（EscMenu/MainMenu）经 _unhandled_input 统一处理；
	# 若此处默认 FOCUS_ALL，鼠标点选会 grab 焦点，而父菜单关闭（queue_free）后焦点会悬挂在
	# 已销毁的子项上，导致后续 ESC 等键盘输入被吞 —— 这正是「点击保存/读取后 ESC 失效」的根因。
	focus_mode = Control.FOCUS_NONE
	if not gui_input.is_connected(_on_gui_input):
		gui_input.connect(_on_gui_input)
	# 反馈组件：handle_mouse=false —— 鼠标已由本组件的 _on_gui_input 处理，
	# 若让 UIFeedback 再接管 mouse_entered 会双重触发（动画跳两遍 + 音效放两次）。
	# 统一收敛到 set_selected() -> notify_selection_changed() 这一个入口。
	_feedback = UIFeedback.attach(self, "focus", false)

func _build() -> void:
	custom_minimum_size = Vector2(280, 44)

	_arrow = Label.new()
	_arrow.text = ARROW
	_arrow.add_theme_font_size_override("font_size", FONT_SIZE)
	_arrow.add_theme_color_override("font_color", UIPalette.GOLD)
	_arrow.position = Vector2(2, 10)
	_arrow.visible = false
	add_child(_arrow)

	_label = Label.new()
	# 默认留空：任何漏 set_text 的 MenuItem 会显示空白，比"菜单项"占位符更易暴露 bug
	_label.text = ""
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_label.position = Vector2(28, 10)
	add_child(_label)
	# _label 已就绪：若 set_text 在 _build 之前（节点未进树时）被调用过，此刻补应用
	if _pending_text != "":
		_label.text = _pending_text

func set_text(text: String) -> void:
	if _label != null:
		_label.text = text
	else:
		# 尚未进树、_label 未创建：暂存，待 _build 末尾应用
		_pending_text = text

func set_selected(value: bool) -> void:
	_is_selected = value
	if _arrow != null:
		_arrow.visible = value
	# 反馈统一入口：缩放动画 + 音效都交给 UIFeedback。
	# 键盘导航（父容器 _unhandled_input 调 set_selected）也能触发，
	# 解决此前「鼠标有反馈、键盘选中完全没反应」的问题。
	if _feedback != null:
		_feedback.notify_selection_changed(value)
	if _label == null:
		return
	# 配色统一：选中与未选中都用 TEXT_MAIN（米白，与登录界面"开始新的旅程"一致），
	# 选中态额外通过箭头 + 文字右移 2px + 微微加亮(modulate) 标识，避开过去"GOLD 高亮"的视觉突兀。
	if value:
		_label.remove_theme_color_override("font_color")   # 落到全局默认 TEXT_MAIN
		_label.modulate = Color(1.08, 1.06, 1.02)           # 极轻加亮，肉眼不易察觉但强化焦点
		_label.position.x = 30.0
	else:
		_label.remove_theme_color_override("font_color")
		_label.modulate = Color.WHITE
		_label.position.x = 28.0

func set_enabled(enabled: bool) -> void:
	_is_enabled = enabled
	if _label == null:
		return
	if enabled:
		_label.modulate = Color.WHITE
	else:
		_label.modulate = UIPalette.DISABLED

func is_enabled() -> bool:
	return _is_enabled

func confirm() -> void:
	if not _is_enabled:
		return
	confirmed.emit()

func _on_gui_input(event: InputEvent) -> void:
	if not _is_enabled:
		return
	if event is InputEventMouseMotion:
		if not _is_selected:
			# 反馈（缩放动画 + 音效）由 UIFeedback 在 set_selected 内统一处理，
			# 此处不再单独播音效，避免与 UIFeedback 双重触发
			set_selected(true)
			selected.emit()
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		confirm()
