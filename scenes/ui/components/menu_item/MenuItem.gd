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

# B 路线：节点结构（_arrow/_icon/_label）已迁入 MenuItem.tscn，
# 美术可在编辑器直接编辑布局与外观；本脚本只负责状态、交互与数据填充。
@onready var _label: Label = $_label
@onready var _arrow: Label = $_arrow
@onready var _icon: TextureRect = $_icon

var _icon_id: String = ""        # 由消费方 set_icon() 传入；空=无图标（向后兼容）
var _is_selected: bool = false
var _is_enabled: bool = true
var _pending_text: String = ""   # _ready 创建 _label 之前调用 set_text 时暂存，建好后再应用
var _feedback: UIFeedback = null # 交互反馈（缩放动画 + 音效），配置表驱动
var _bg: TextureRect = null           # 按钮背景图（由 login_button_bg.json 驱动；默认无，置底渲染）
var _pending_bg_path: String = ""     # 进树前调用 set_background 时暂存路径

func _ready() -> void:
	custom_minimum_size = Vector2(280, 44)
	_configure_nodes()
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

func _configure_nodes() -> void:
	_arrow.text = ARROW
	_arrow.add_theme_font_size_override("font_size", FONT_SIZE)
	_arrow.add_theme_color_override("font_color", UIPalette.GOLD)
	# 有图标时箭头右移到图标右侧，避免与图标重叠
	_arrow.position = Vector2(2 if _icon_id == "" else 34, 10)
	_arrow.visible = false
	# 可选图标：menu/<key>，由消费方 set_icon() 传入；缺图则不显示（不占位、不崩）
	if _icon_id != "":
		_icon.texture = UIManager.get_icon(_icon_id)
		_icon.custom_minimum_size = Vector2(24, 24)
		_icon.size = Vector2(24, 24)
		_icon.position = Vector2(6, 10)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		_icon.visible = true
	else:
		_icon.visible = false
	# 默认留空：任何漏 set_text 的 MenuItem 会显示空白，比"菜单项"占位符更易暴露 bug
	_label.text = ""
	_label.add_theme_font_size_override("font_size", FONT_SIZE)
	_label.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	# 有图标时右移给图标留位（图标区约 6..30，label 从 56 起）
	_label.position = Vector2(56 if _icon_id != "" else 28, 10)
	# _label 已就绪：若 set_text 在 _ready 之前（节点未进树时）被调用过，此刻补应用
	if _pending_text != "":
		_label.text = _pending_text
	# 可选按钮背景图：由 login_button_bg.json 驱动；set_background 在 _ready 前调用则此处补应用。
	# 置底渲染（_bg 在最底层，其上叠一层轻量压暗保证米白文字可读），不抢交互。
	if _pending_bg_path != "" and ResourceLoader.exists(_pending_bg_path):
		var trx := TextureRect.new()
		trx.name = "_bg"
		trx.texture = ResourceLoader.load(_pending_bg_path, "Texture2D")
		trx.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		trx.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		trx.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(trx)
		move_child(trx, 0)
		_bg = trx
		# 轻量压暗层（0.25）：保证任意按钮背景图上米白文字仍可读；想更亮可调小到 0 或删掉
		var scrim := ColorRect.new()
		scrim.name = "_bg_scrim"
		scrim.color = Color(0, 0, 0, 0.25)
		scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(scrim)
		move_child(scrim, 1)

func set_text(text: String) -> void:
	if _label != null:
		_label.text = text
	else:
		# 尚未进树、_label 未创建：暂存，待 _configure_nodes 末尾应用
		_pending_text = text

## 设置图标 id（如 "menu/save_game"）。应在 add_child 之前调用，_configure_nodes 时据此创建图标。
## 留空则不显示图标（向后兼容旧菜单项）。美术按 id 丢 resources/icons/menu/<key>.png 即生效。
func set_icon(icon_id: String) -> void:
	_icon_id = icon_id

## 设置按钮背景图路径（res://...png）。由 data/configs/ui/login_button_bg.json 驱动；
## 应在 add_child 之前调用，_configure_nodes 时据此创建置底背景层（图 + 轻压暗），不抢交互。
func set_background(bg_path: String) -> void:
	_pending_bg_path = bg_path

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
		_label.position.x = 58.0 if _icon_id != "" else 30.0
	else:
		_label.remove_theme_color_override("font_color")
		_label.modulate = Color.WHITE
		_label.position.x = 56.0 if _icon_id != "" else 28.0

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
