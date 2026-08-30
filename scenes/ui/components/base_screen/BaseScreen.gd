# scenes/ui/components/base_screen/BaseScreen.gd
# 界面基类（2026-08-29 编排层落地）
#
# 统一处理全屏界面的公共关注点，消掉 MainMenu / SaveLoadScreen / EscMenu / DifficultySelect
# 各自重复的样板代码：
#   ① 铺满 + 安全区（安卓刘海/挖孔）
#   ② 全屏压暗底
#   ③ 键盘导航（ui_up / ui_down / ui_accept）与禁用项跳过
#   ④ 返回处理（ui_cancel，可关）
#   ⑤ 顶层守卫（非栈顶界面自动让权，弹窗打开时不响应键盘）
#
# 转场淡入淡出由 **UIManager** 统一负责（时长/缓动读 ui_anim.json 的 screen 预设），
# 基类**不重复**做淡入，否则会双重渐显。
#
# 分层结构（重要）：
#   self                 ← 铺满整个窗口（含刘海区）
#   ├── 压暗底(可选)      ← 加到 self，铺满含刘海，视觉上盖住整屏
#   └── ContentRoot      ← 套安全区，所有界面内容放这里，自动避开刘海
# 若把安全区直接套在根节点，压暗层会盖不住刘海区，露出一条亮边。
#
# 子类实现约定：
#   - 重写 _build_content() 构建内容；加节点用 add_content() 而非 add_child()
#   - 填充 _nav_items 并设 keyboard_nav_enabled = true 启用键盘导航
#   - 重写 _update_selection() / _on_confirm_selection() 处理选中与确认
#   - 需要额外按键时重写 _on_screen_input()，返回 true 表示已消费

extends Control
class_name BaseScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")

## 是否响应 ui_cancel 自行关闭。
## ⚠️ EscMenu 必须为 false —— TownScene 也监听 ui_cancel 来开关菜单，
## 若界面再处理一次会双重触发（按下 ESC 立刻开了又关）。
var close_on_cancel: bool = true
## 是否启用键盘上下导航（需子类填充 _nav_items 后才有效）
var keyboard_nav_enabled: bool = false
## 导航项列表：子类填充，支持 MenuItem / Button 等任意 Control
var _nav_items: Array = []
var _selected_index: int = 0
## 内容容器（已套安全区），子类内容放这里
var _content_root: Control = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 内容容器：套安全区，避开刘海/挖孔/系统手势条
	_content_root = Control.new()
	_content_root.name = "ContentRoot"
	_content_root.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_content_root)
	UIManager.apply_safe_area(_content_root)
	# ⚠️ 关键修复（2026-08-31）：消除「全屏界面弹出后首下点击被吞、需点两下」的 Godot 已知行为。
	# 直接 add_child 到 CanvasLayer 的 Control，进入场景树的当帧其 gui_input 尚未就绪，
	# 该帧的鼠标点击会被 viewport 首次重排吞掉。表现为：主菜单点「读取旧梦」第一下无反应，第二下才进。
	# 解法：把内容构建延迟到下一帧（call_deferred），让界面在第二帧才构建并接受输入，
	# 首帧吞输入窗口已过去。缓存复用路径不跑 _ready，无副作用。
	call_deferred("_build_deferred")

func _build_deferred() -> void:
	if _content_root == null or not is_instance_valid(_content_root):
		return
	_build_content()
	_update_selection()

## 子类重写：构建界面内容。基类已处理铺满与安全区，子类不要再设 PRESET_FULL_RECT
func _build_content() -> void:
	push_warning("BaseScreen 子类必须重写 _build_content()")

## 把节点加进内容容器（自动避开刘海）。子类应优先用这个而不是 add_child()
## ⚠️ B 路线兼容：节点可能已在 .tscn 里作为 root 子节点存在（如 EscMenu 的 Container、
## DifficultySelect 的 Title/List/Back），此时需要先脱离旧父节点再挂进 ContentRoot。
## Godot 4 的 add_child 对已带父节点的节点会直接报错（不会自动重挂），故此处显式重挂。
func add_content(node: Node) -> void:
	if _content_root != null:
		if node.get_parent() != null and node.get_parent() != _content_root:
			node.get_parent().remove_child(node)
		_content_root.add_child(node)
	else:
		if node.get_parent() != null and node.get_parent() != self:
			node.get_parent().remove_child(node)
		add_child(node)

## 加一层全屏压暗底（透出下层画面，表明处于弹窗/暂停态）。
## 加到 self 而非内容容器 —— 压暗层要盖住包括刘海在内的整屏。
func _add_backdrop(alpha: float = 0.55) -> ColorRect:
	var dim := ColorRect.new()
	dim.name = "Backdrop"
	dim.color = Color(0.0, 0.0, 0.0, alpha)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	move_child(dim, 0)   # 压到最底层，避免盖住内容
	return dim

## 子类重写：选中态视觉更新
func _update_selection() -> void:
	pass

## 子类重写：确认当前选中项（ui_accept 或鼠标点击）
func _on_confirm_selection(_index: int) -> void:
	pass

## 子类可重写：额外按键处理。返回 true 表示已消费，基类不再处理该事件
func _on_screen_input(_event: InputEvent) -> bool:
	return false

func _unhandled_input(event: InputEvent) -> void:
	# 顶层守卫：仅栈顶界面响应。弹窗(ConfirmDialog)打开时 _current_screen 变为弹窗，
	# 本界面自动让权，避免被遮挡时仍响应键盘
	if UIManager.get_current_screen() != self:
		return
	if _on_screen_input(event):
		get_viewport().set_input_as_handled()
		return
	if keyboard_nav_enabled and not _nav_items.is_empty():
		if event.is_action_pressed("ui_up"):
			_move_selection(-1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_down"):
			_move_selection(1)
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("ui_accept"):
			_on_confirm_selection(_selected_index)
			get_viewport().set_input_as_handled()
			return
	if close_on_cancel and event.is_action_pressed("ui_cancel"):
		UIManager.close_screen(self)
		get_viewport().set_input_as_handled()

## 循环移动选择，自动跳过禁用项（MenuItem 用 is_enabled()，Button 用 disabled 属性）
func _move_selection(direction: int) -> void:
	var count: int = _nav_items.size()
	if count == 0:
		return
	var new_index: int = _selected_index
	for _i in count:
		new_index = wrapi(new_index + direction, 0, count)
		var item: Control = _nav_items[new_index] as Control
		if item == null:
			continue
		if item.has_method("is_enabled"):
			if item.is_enabled():
				break
		elif "disabled" in item:
			if not item.disabled:
				break
		else:
			break
	_selected_index = new_index
	_update_selection()
