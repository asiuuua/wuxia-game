# scenes/ui/overlays/hud/quest_track_panel.gd
# HUD 任务追踪面板（v2 四面板之一）：展示当前追踪任务及目标进度。
# 数据源：GameManager.quest_service.get_tracked()（任务窗主权，只读消费）。
# 订阅 notify_quest_track_changed（列表增删）+ quest_objective_updated（进度推进）做增量刷新。
# 纯展示层，不修改业务数据。配色走 UIPalette。
#
# 交互增强（用户需求 2026-08-29）：
#  - 可自由拖动：根 Control 捕获左键，_process 跟随 global mouse 移动，松开落点持久化。
#  - 不可脱离屏幕：每次移动后 _clamp_to_screen 夹在可视矩形内。
#  - 屏幕固定：落点存 user://ui/hud_positions.json，重挂载/重开游戏后回到上次位置。
#  - 毛玻璃：半透 GLASS_BG + 圆角 + 阴影。
#  - 滚动列表：条目包进 ScrollContainer，内容超 MAX_VISIBLE 即出滚动条。
#
# ⚠️ 拖动修复关键（用户反馈「点了拖不动」）：根 Control 必须显式有 size，否则 rect=0×0、
#   鼠标悬停永远落在空区、_gui_input 永不触发 → 看似「不能拖」。_build / _apply_scroll_height
#   都调 _sync_root_size() 让根尺寸随内容同步，拖拽热区才真实存在。

extends Control
class_name QuestTrackPanel

const UIPalette = preload("res://core/constants/ui_theme.gd")

const PANEL_W := 300.0
const MAX_VISIBLE := 360.0            # 列表区最大可视高度，超出则滚动

# --- 初始位置：状态卡下方「2 指头」距离（用户 2026-08-29 明确要求） ---
# 状态卡：position(12,12)、设计尺寸 340×318、scale 0.667 → 渲染高 ≈ 212。
# 任务栏初始放在状态卡正下方，留 2 指头（FINGER×2）间隙，x 与状态卡左缘对齐。
const STATUS_CARD_POS := Vector2(12.0, 12.0)
const STATUS_CARD_SCALE := 0.667
const STATUS_CARD_W := 340.0
const STATUS_CARD_H := 318.0
const FINGER := 16.0
const DEFAULT_POS := Vector2(STATUS_CARD_POS.x, STATUS_CARD_POS.y + STATUS_CARD_H * STATUS_CARD_SCALE + 2.0 * FINGER)

const POS_SAVE_PATH := "user://ui/hud_positions.json"
const POS_KEY := "quest_track"

# B 路线（2026-08-30）：静态结构（毛玻璃面板 / 标题 / 滚动容器 / 条目容器）已迁入
# QuestTrackPanel.tscn，美术可改样式、圆角、最大可视高度；脚本只保留拖拽、位置持久化与动态条目。
@onready var _entries: VBoxContainer = $Panel/Margin/V/Scroll/Entries
@onready var _scroll: ScrollContainer = $Panel/Margin/V/Scroll

# --- 拖拽状态 ---
var _dragging := false
var _drag_offset := Vector2.ZERO

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_MOVE   # 悬停显示「可移动」光标，提示可拖动
	_make_drag_surface()                    # 静态结构已在 QuestTrackPanel.tscn，这里只统一输入靶
	_sync_root_size()                       # 关键：先给根真实尺寸，拖拽热区才存在
	_load_position()                        # 取存档位置（无存档/非法走默认）
	if is_instance_valid(EventBus):
		EventBus.notify_quest_track_changed.connect(_refresh)
		EventBus.quest_objective_updated.connect(_refresh)
	_refresh()
	# 入树后再夹一次（确保初始位置在屏内；_load_position 时 viewport 可能尚不可用）
	_clamp_to_screen()
	call_deferred("_clamp_to_screen")

# 让根成为唯一输入靶：子节点（含 ScrollContainer）全部 IGNORE，滚轮滚动由根手动驱动 _scroll.scroll_vertical
func _make_drag_surface() -> void:
	_set_mouse_filter_recursive(self, Control.MOUSE_FILTER_IGNORE)
	mouse_filter = Control.MOUSE_FILTER_STOP   # 根自身保持 STOP

func _set_mouse_filter_recursive(node: Node, mf: int) -> void:
	if node is Control:
		node.mouse_filter = mf
	for c in node.get_children():
		_set_mouse_filter_recursive(c, mf)

# 根尺寸随内容同步：保证拖拽热区真实存在、且面板不无限撑高
func _sync_root_size() -> void:
	var ms := get_combined_minimum_size()
	size = Vector2(maxf(PANEL_W, ms.x), maxf(ms.y, 80.0))

# === 拖拽：_gui_input 只负责按下/松开，移动交给 _process 跟随 global mouse（可拖出面板边界）===
func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_offset = get_global_mouse_position() - global_position
			accept_event()
		else:
			if _dragging:
				_dragging = false
				_save_position()   # 落点持久化
				accept_event()
	elif event is InputEventMouseMotion and _dragging:
		global_position = get_global_mouse_position() - _drag_offset
		_clamp_to_screen()
		accept_event()
	elif event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
		# 滚轮滚动列表（ScrollContainer 子节点 IGNORE，由根手动驱动）
		if _scroll != null:
			var step := 40
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_scroll.scroll_vertical += step
			else:
				_scroll.scroll_vertical -= step
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
	return Vector2(1920, 1080)   # 无 viewport（构建期/测试）时假设 1080p

# === 位置持久化（user://，运行时可写，不污染项目资源）===
func _load_position() -> void:
	var pos := DEFAULT_POS
	var d := _read_json()
	if d.has(POS_KEY) and d[POS_KEY] is Dictionary:
		var kv: Dictionary = d[POS_KEY]
		var sx: float = float(kv.get("x", DEFAULT_POS.x))
		var sy: float = float(kv.get("y", DEFAULT_POS.y))
		# 合法性守卫：非有限数或明显越界（屏外）则回退默认，避免脏存档把面板丢到屏外
		if is_finite(sx) and is_finite(sy) and sx > -PANEL_W and sy > -200.0:
			pos = Vector2(sx, sy)
	global_position = pos

func _save_position() -> void:
	var d := _read_json()
	d[POS_KEY] = {"x": global_position.x, "y": global_position.y}
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

func _exit_tree() -> void:
	_dragging = false
	if not is_instance_valid(EventBus):
		return
	if EventBus.notify_quest_track_changed.is_connected(_refresh):
		EventBus.notify_quest_track_changed.disconnect(_refresh)
	if EventBus.quest_objective_updated.is_connected(_refresh):
		EventBus.quest_objective_updated.disconnect(_refresh)

# 全量重建追踪列表（列表增删与进度推进都走全量重建，逻辑简单且追踪任务数量极少）
func _refresh(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	if _entries == null:
		return
	# 清旧条目（free 立即释放，避免 queue_free 幽灵节点残留）
	for child in _entries.get_children():
		child.free()
	if not is_instance_valid(GameManager) or GameManager.quest_service == null:
		_add_empty("（暂无追踪任务）")
		_apply_scroll_height()
		return
	var tracked: Array[QuestState] = GameManager.quest_service.get_tracked()
	if tracked.is_empty():
		_add_empty("（暂无追踪任务）")
		_apply_scroll_height()
		return
	for state in tracked:
		_add_quest_entry(state)
	_apply_scroll_height()

# 列表高度按内容动态封顶：内容少则贴合，内容多则锁 MAX_VISIBLE 出滚动条
func _apply_scroll_height() -> void:
	if _scroll == null or _entries == null:
		return
	var content_h := _entries.get_combined_minimum_size().y
	var capped := clampf(content_h, 60.0, MAX_VISIBLE)
	_scroll.custom_minimum_size.y = capped
	_scroll.size.y = capped   # 同步显式尺寸，保证同步断言/渲染即刻生效（EXPAND_FILL 布局后亦一致）
	_sync_root_size()        # 根随内容同步尺寸（保证可拖拽 + 不无限撑高）
	_clamp_to_screen()       # 尺寸变化后重新夹在屏内
	call_deferred("_apply_scroll_height_deferred")   # 布局完成后用真实测量值再校准一次

# 引擎完成本帧布局后，_entries 的最小尺寸才准确；延迟一帧用真实值封顶
func _apply_scroll_height_deferred() -> void:
	if _scroll == null or _entries == null:
		return
	var content_h := _entries.get_combined_minimum_size().y
	var capped := clampf(content_h, 60.0, MAX_VISIBLE)
	_scroll.custom_minimum_size.y = capped
	_scroll.size.y = capped
	_sync_root_size()
	_clamp_to_screen()

func _add_empty(text: String) -> void:
	var lab := Label.new()
	lab.text = text
	lab.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	lab.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	_entries.add_child(lab)

func _add_quest_entry(state: QuestState) -> void:
	var cfg: Dictionary = ConfigManager.get_quest(state.quest_id) if ConfigManager.has_quest(state.quest_id) else {}
	var title: String = cfg.get("name", state.quest_id)
	var title_lab := Label.new()
	title_lab.text = "◆ " + str(title)
	title_lab.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	title_lab.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
	title_lab.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_entries.add_child(title_lab)
	for obj in cfg.get("objectives", []):
		var obj_id: String = obj["id"]
		var need: int = int(obj.get("need", 1))
		var cur: int = state.get_objective_progress(obj_id)
		var done: bool = state.is_objective_completed(obj_id)
		var line := Label.new()
		var mark := "✔" if done else "▢"
		line.text = "  %s %s  %d/%d" % [mark, obj.get("desc", obj_id), cur, need]
		line.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY if not done else UIPalette.SUCCESS)
		line.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_entries.add_child(line)
