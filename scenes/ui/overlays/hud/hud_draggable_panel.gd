@tool
# scenes/ui/overlays/hud/hud_draggable_panel.gd
# HUD 常驻面板拖拽基类（2026-08-31，用户需求4：常驻 UI 全部可拖拽/坐标操控）
# 把 QuestTrackPanel 已验证的拖拽逻辑抽成共享基类，供状态卡/右上菜单/技能栏复用，避免重复 170 行。
# QuestTrackPanel 因已落地且含滚动特例，保持独立实现不改动（避免回归）。
#
# 行为约定：
#  - 根 Control 清零锚点、mouse_filter=STOP、MOVE 光标，可作为拖拽热区。
#  - 子节点中 Button / TextureButton 保留 STOP（可点击）；其余 Control（Panel/Label/StatusBar 等背景与展示节点）改为 IGNORE，
#    让点击透传到根 → 空白处拖动、按钮正常点击。
#  - 拖动：根 _gui_input 处理按下/松开，_process 跟随 global mouse，落点持久化到 user://ui/hud_positions.json。
#  - 不可脱离屏幕：每次移动后 _clamp_to_screen 夹在可视矩形内。
#  - 屏幕固定：重挂载/重开回到上次位置；无存档/非法回退 default_pos。

extends Control
class_name HudDraggablePanel

const POS_SAVE_PATH := "user://ui/hud_positions.json"

# --- 拖拽状态 ---
var _drag_key := ""
var _dragging := false
var _drag_offset := Vector2.ZERO

# --- 缩放状态（uniform scale，拖右下角手柄改大小，不改内部布局比例，0.5~2.5） ---
var _resizing := false
var _resize_start_scale := 1.0
var _resize_start_pointer := Vector2.ZERO
var _resize_origin := Vector2.ZERO

# 子类 _ready 调一次：drag_key=存档键名；default_pos=首开/无存档时的默认位置（屏幕绝对坐标）
func _init_drag(drag_key: String, default_pos: Vector2) -> void:
	_drag_key = drag_key
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE
	# 清零锚点：让 position/size 直接控制布局（否则 FULL_RECT 预设会让根铺满并吞掉全屏输入）
	anchor_left = 0.0
	anchor_top = 0.0
	anchor_right = 0.0
	anchor_bottom = 0.0
	# 背景/展示节点透传、可交互按钮保留
	for c in get_children():
		_config_mouse(c)
	_apply_root_size()
	_load_position(default_pos)
	_apply_scale()                 # 应用工作室默认 / 玩家缩放偏好
	_make_resize_handle()          # 右下角拖拽缩放手柄（游戏内也能改大小）
	if not gui_input.is_connected(_on_drag_gui_input):
		gui_input.connect(_on_drag_gui_input)
	_clamp_to_screen()
	call_deferred("_clamp_to_screen")

# 背景类(非按钮)IGNORE、按钮 STOP：空白区可拖、按钮可点
func _config_mouse(node: Node) -> void:
	if node is Button or node is TextureButton:
		node.mouse_filter = Control.MOUSE_FILTER_STOP
	elif node is Control:
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for cc in node.get_children():
			_config_mouse(cc)

# 根尺寸跟随内容最小尺寸（保证拖拽热区真实存在）
func _apply_root_size() -> void:
	var ms := get_combined_minimum_size()
	if ms.x > 0 and ms.y > 0:
		size = ms

# 应用缩放：先取工作室默认（hud_layout.json），再用玩家 user:// 偏好覆盖
func _apply_scale() -> void:
	var s: float = UILayout.hud_default_scale(_drag_key, 1.0)
	var d := _read_json()
	if d.has(_drag_key) and d[_drag_key] is Dictionary:
		var kv: Dictionary = d[_drag_key]
		var ks = kv.get("scale", null)
		if (ks is float or ks is int) and is_finite(float(ks)):
			s = clampf(float(ks), 0.5, 2.5)
	scale = Vector2(s, s)

# 右下角缩放手柄：拖它改 uniform scale（保持内部布局比例）
func _make_resize_handle() -> void:
	var h := Control.new()
	h.name = "ResizeHandle"
	h.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	h.anchor_left = 1.0
	h.anchor_top = 1.0
	h.anchor_right = 1.0
	h.anchor_bottom = 1.0
	h.offset_left = -18.0
	h.offset_top = -18.0
	h.offset_right = 0.0
	h.offset_bottom = 0.0
	h.mouse_filter = Control.MOUSE_FILTER_STOP
	h.mouse_default_cursor_shape = Control.CURSOR_BDIAGSIZE
	h.tooltip_text = "拖拽缩放面板"
	h.gui_input.connect(_on_resize_gui_input)
	var grip := ColorRect.new()
	grip.color = Color(0.55, 0.78, 1.0, 0.45)
	grip.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(grip)
	add_child(h)

func _on_resize_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_resizing = true
			_resize_start_scale = scale.x
			_resize_start_pointer = get_global_mouse_position()
			_resize_origin = global_position
			accept_event()
		else:
			if _resizing:
				_resizing = false
				_save_position()
				accept_event()
	elif event is InputEventMouseMotion and _resizing:
		var cur := get_global_mouse_position()
		var dist_now := (cur - _resize_origin).length()
		var dist_start := (_resize_start_pointer - _resize_origin).length()
		var ratio := 1.0
		if dist_start > 1.0:
			ratio = dist_now / dist_start
		var ns := clampf(_resize_start_scale * ratio, 0.5, 2.5)
		scale = Vector2(ns, ns)
		_clamp_to_screen()
		accept_event()

func _on_drag_gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			accept_event()
		else:
			if _dragging:
				_dragging = false
				_save_position()
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_to_screen()
		accept_event()

func _process(_delta: float) -> void:
	if _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_to_screen()

func _clamp_to_screen() -> void:
	if size.x <= 0 or size.y <= 0:
		return
	var g := get_global_rect()
	var vps := _screen_size()
	var max_x := maxf(0.0, vps.x - g.size.x)
	var max_y := maxf(0.0, vps.y - g.size.y)
	var x := clampf(g.position.x, 0.0, max_x)
	var y := clampf(g.position.y, 0.0, max_y)
	global_position = Vector2(x, y)

func _screen_size() -> Vector2:
	if get_viewport() != null:
		return get_viewport().get_visible_rect().size
	return Vector2(1920, 1080)

# === 位置持久化 ===
func _load_position(default_pos: Vector2) -> void:
	var pos := default_pos
	var d := _read_json()
	if d.has(_drag_key) and d[_drag_key] is Dictionary:
		var kv: Dictionary = d[_drag_key]
		var sx: float = float(kv.get("x", default_pos.x))
		var sy: float = float(kv.get("y", default_pos.y))
		if is_finite(sx) and is_finite(sy) and sx > -2000.0 and sy > -2000.0:
			pos = Vector2(sx, sy)
	global_position = pos

func _save_position() -> void:
	var d := _read_json()
	d[_drag_key] = {"x": global_position.x, "y": global_position.y, "scale": scale.x}
	_write_json(d)

func _read_json() -> Dictionary:
	if not FileAccess.file_exists(POS_SAVE_PATH):
		return {}
	var f := FileAccess.open(POS_SAVE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}

func _write_json(d: Dictionary) -> void:
	var da := DirAccess.open("user://")
	if da != null and not da.dir_exists("ui"):
		da.make_dir("ui")
	var f := FileAccess.open(POS_SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(d))
	f.close()
