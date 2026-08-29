# scenes/gameplay/battle/battle_grid_node.gd
# 战术战棋网格视图层（战斗窗口主权）：用 _draw() 程序化绘制平整方格网格
# 不依赖任何 TileSet / 贴图资产，headless 可编译；方格布局与屏幕坐标对齐，点击拾取更简单。
# 职责：
#   - 绘制地形方格（可走 / 障碍两色）
#   - 绘制高亮层（蓝=可移动 / 绿=敌方威胁 / 红=技能范围），订阅 EventBus.grid_highlight_update
#   - 提供 cell_center / world_to_grid，把世界坐标反算回网格坐标（供场景层点击拾取）
# ⚠️ 本节点只画 + 反算坐标，不持有任何战斗逻辑；单位实体由 BattleEntity 负责。

extends Node2D
class_name BattleGridNode

# 高亮类型编码（与 EventBus.grid_highlight_update 的 dict key 对齐）
const HL_MOVE: int = 0      # 蓝色：玩家可移动格
const HL_THREAT: int = 1    # 绿色：敌方可达 / 威胁范围
const HL_SKILL: int = 2     # 红色：当前选中技能的可命中范围

var grid: BattleGrid = null
var cell_size: float = 48.0   # 方格边长
var _highlights: Dictionary = {}   # type(int) -> Array[Vector2i]

func _ready() -> void:
	if is_instance_valid(EventBus):
		EventBus.grid_highlight_update.connect(_on_highlight_update)

func _exit_tree() -> void:
	if is_instance_valid(EventBus) and EventBus.grid_highlight_update.is_connected(_on_highlight_update):
		EventBus.grid_highlight_update.disconnect(_on_highlight_update)

func set_grid(g: BattleGrid) -> void:
	grid = g
	queue_redraw()

func _on_highlight_update(dict: Dictionary) -> void:
	_highlights = dict
	queue_redraw()

## 直接设置高亮（不经 EventBus 的内部便捷通道）
func set_highlights(dict: Dictionary) -> void:
	_highlights = dict
	queue_redraw()

func clear_highlights() -> void:
	_highlights.clear()
	queue_redraw()

func _draw() -> void:
	if grid == null:
		return
	# 地形层：逐格画方格（可走 / 障碍两色）
	for x in range(grid.width):
		for y in range(grid.height):
			var p := Vector2i(x, y)
			_draw_cell(p, grid.is_obstacle_cell(p))
	# 高亮层
	for type_key in _highlights.keys():
		var cells: Array = _highlights[type_key]
		var col := _hl_color(int(type_key))
		for c in cells:
			_draw_cell_outline(c, col)

func _cell_rect(p: Vector2i) -> Rect2:
	var c := cell_center(p)
	return Rect2(c.x - cell_size * 0.5, c.y - cell_size * 0.5, cell_size, cell_size)

func _draw_cell(p: Vector2i, obstacle: bool) -> void:
	var rect := _cell_rect(p)
	var col := Color(0.18, 0.22, 0.30) if not obstacle else Color(0.42, 0.28, 0.22)
	draw_rect(rect, col)
	draw_rect(rect, Color(0.06, 0.08, 0.12), false, 1.0)

func _draw_cell_outline(p: Vector2i, col: Color) -> void:
	var rect := _cell_rect(p)
	var fill := col
	fill.a = 0.35
	draw_rect(rect, fill)
	draw_rect(rect, col, false, 2.0)

func _hl_color(type_: int) -> Color:
	match type_:
		HL_MOVE: return Color(0.25, 0.55, 0.95)
		HL_THREAT: return Color(0.3, 0.8, 0.4)
		HL_SKILL: return Color(0.95, 0.35, 0.3)
		_: return Color(1, 1, 1)

## 网格坐标 → 世界坐标（相对本节点原点，格子中心）
func cell_center(p: Vector2i) -> Vector2:
	return Vector2((p.x + 0.5) * cell_size, (p.y + 0.5) * cell_size)

## 世界坐标（相对本节点）→ 网格坐标（点击拾取反算）
func world_to_grid(local_world: Vector2) -> Vector2i:
	return Vector2i(int(local_world.x / cell_size), int(local_world.y / cell_size))

## 网格像素包围盒中心（供场景层把战场居中到屏幕）
func pixel_center() -> Vector2:
	if grid == null:
		return Vector2.ZERO
	return Vector2(grid.width * cell_size * 0.5, grid.height * cell_size * 0.5)
