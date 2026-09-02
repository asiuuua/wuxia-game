@tool
# scenes/ui/components/save_name_dialog/SaveNameDialog.gd
# 存档命名弹窗（B 路线：静态结构全部进 SaveNameDialog.tscn，美术可在编辑器改布局/配色；脚本只管行为与信号）
# 用法：instantiate() → add_child() → 连 confirmed / cancelled 信号 → setup() 可填默认名
# 本组件不持有任何存档业务逻辑（不认识 SaveManager），只负责「收一个名字并回报」，便于复用。
extends Control

const UICenterUtils = preload("res://scenes/ui/ui_center_utils.gd")

# 响应式锚点（派单 23a9d0b92b83）：面板设计尺寸，小视口自动内缩防溢出/错位
const SAVE_NAME_PANEL_SIZE := Vector2(460, 190)

## 确认保存：参数为输入框当前文本（未做去空格/兜底，交给调用方按业务处理）
signal confirmed(save_name: String)
## 取消 / 点遮罩 / ESC 关闭
signal cancelled()

@onready var _dim: ColorRect = $Dim
@onready var _title: Label = $Panel/VBox/TitleLabel
@onready var _edit: LineEdit = $Panel/VBox/NameEdit
@onready var _ok_btn: Button = $Panel/VBox/BtnRow/OkBtn
@onready var _cancel_btn: Button = $Panel/VBox/BtnRow/CancelBtn

func _ready() -> void:
	_title.text = tr("ui_save_name_title")
	_edit.placeholder_text = tr("ui_save_name_placeholder")
	_ok_btn.text = tr("ui_confirm_ok")
	_cancel_btn.text = tr("ui_confirm_cancel")
	_ok_btn.pressed.connect(_on_ok)
	_cancel_btn.pressed.connect(_on_cancel)
	_edit.text_submitted.connect(func(_t: String): _on_ok())
	_dim.gui_input.connect(_on_dim_gui_input)
	_edit.grab_focus.call_deferred()   # 延后一帧：等节点真正进树拿到焦点
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
	UICenterUtils.fit_panel_to_viewport(panel, SAVE_NAME_PANEL_SIZE)

func _cleanup_responsive() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_fit_responsive):
		vp.size_changed.disconnect(_fit_responsive)

## 可选：预填默认名（不传则为空，只显示占位提示）
func setup(default_name: String = "") -> void:
	_edit.text = default_name

# === 事件出口 ===
func _on_ok() -> void:
	confirmed.emit(_edit.text)

func _on_cancel() -> void:
	cancelled.emit()

# 点遮罩空白处 = 取消（与 ESC 同义）
func _on_dim_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		cancelled.emit()
		get_viewport().set_input_as_handled()

# ESC 关闭本弹窗，并阻止事件继续冒泡到下层界面（否则会连带关掉整个存档界面）
# 用 _unhandled_input：输入框获得焦点且不消费 ESC，事件会走到这里
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		cancelled.emit()
		get_viewport().set_input_as_handled()
