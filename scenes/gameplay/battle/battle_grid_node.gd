# scenes/gameplay/battle/battle_grid_node.gd
# 战术战棋网格视图层（战斗窗口主权）：用 _draw() 程序化绘制 45° 等轴测菱形网格
# 不依赖任何 TileSet / 贴图资产，headless 可编译；菱形布局与 Godot TileMap ISOMETRIC 约定一致。
# 职责：
#   - 绘制地形方格（可走 / 障碍两色菱形）
#   - 绘制高亮层（蓝=可移动 / 绿=敌方威胁 / 红=技能范围）
#   - 提供 cell_center / world_to_grid，把世界坐标反算回网格坐标（供场景层点击拾取）
# ⚠️ 本节点只画 + 反算坐标，不持有任何战斗逻辑；单位实体由 BattleEntity 负责。

extends Node2D
class_name BattleGridNode

# 高亮类型编码（与 EventBus.grid_highlight_update 的 dict key 对齐）
const HL_MOVE: int = 0      # 蓝色：玩家可移动格
const HL_THREAT: int = 1    # 绿色：敌方可达 / 威胁范围
const HL_SKILL: int = 2     # 红色：当前选中技能的可命中范围

var grid: BattleGrid = null
var cell_size: float = 48.0     # 菱形外接框宽度
var tile_width: float = cell_size
var tile_height: float = cell_size * 0.5
var _highlights: Dictionary = {}   # type(int) -> Array[Vector2i]
var _terrain: MultiMeshInstance2D = null   # P1 批处理：地形同色格一次性多实例绘制（单 draw call）

func _ready() -> void:
	if is_instance_valid(EventBus):
		EventBus.grid_highlight_update.connect(_on_highlight_update)

func _exit_tree() -> void:
	if is_instance_valid(EventBus) and EventBus.grid_highlight_update.is_connected(_on_highlight_update):
		EventBus.grid_highlight_update.disconnect(_on_highlight_update)

func set_grid(g: BattleGrid) -> void:
	grid = g
	_build_terrain_multimesh()   # 地形一次性批量绘制，与高亮层解耦（高亮变化不再重画几何）
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
	# 地形层已由 MultiMeshInstance2D 一次性批量绘制，本处只画高亮层（红/蓝/绿），点选重绘不再重画几何
	for type_key in _highlights.keys():
		var cells: Array = _highlights[type_key]
		var col := _hl_color(int(type_key))
		for c in cells:
			_draw_cell_outline(c, col)

## 地形批量绘制：用 MultiMeshInstance2D 把全部同色菱形网格合并为单次 draw call；
## 与高亮层解耦——移动/技能高亮变化时只 queue_redraw 高亮层，地形几何零重绘（P1 帧率硬化核心）
func _build_terrain_multimesh() -> void:
	if grid == null:
		return
	if _terrain != null:
		_terrain.queue_free()
		_terrain = null
	_terrain = MultiMeshInstance2D.new()
	add_child(_terrain)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_2D
	mm.use_colors = true          # 必须在 instance_count 仍为 0 时开启，否则 Godot 4 报 "Instance count must be 0 to toggle whether colors are used"
	mm.mesh = _diamond_mesh()
	var n := grid.width * grid.height
	mm.instance_count = n
	for x in range(grid.width):
		for y in range(grid.height):
			var idx: int = y * grid.width + x
			var p := Vector2i(x, y)
			mm.set_instance_transform_2d(idx, Transform2D(0.0, cell_center(p)))
			mm.set_instance_color(idx, Color(0.18, 0.22, 0.30) if not grid.is_obstacle_cell(p) else Color(0.42, 0.28, 0.22))
	_terrain.multimesh = mm

## 单个菱形网格（2D 三角面，中心在原点，z=0）：供 MultiMesh 复用，避免每格独立 draw_colored_polygon
## 注：Godot 4 的 SurfaceTool.add_vertex 仅接受 Vector3（2D 渲染忽略 z），故用 Vector3(x,y,0)
func _diamond_mesh() -> Mesh:
	var hw: float = tile_width * 0.5
	var hh: float = tile_height * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.add_vertex(Vector3(0.0, -hh, 0.0))
	st.add_vertex(Vector3(hw, 0.0, 0.0))
	st.add_vertex(Vector3(0.0, hh, 0.0))
	st.add_vertex(Vector3(0.0, -hh, 0.0))
	st.add_vertex(Vector3(0.0, hh, 0.0))
	st.add_vertex(Vector3(-hw, 0.0, 0.0))
	return st.commit()

## 返回菱形的四个顶点（上、右、下、左）
func _cell_diamond(p: Vector2i) -> PackedVector2Array:
	var c := cell_center(p)
	var hw := tile_width * 0.5
	var hh := tile_height * 0.5
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2(c.x, c.y - hh))        # top
	pts.append(Vector2(c.x + hw, c.y))        # right
	pts.append(Vector2(c.x, c.y + hh))        # bottom
	pts.append(Vector2(c.x - hw, c.y))        # left
	return pts

func _draw_cell(p: Vector2i, obstacle: bool) -> void:
	var pts := _cell_diamond(p)
	var col := Color(0.18, 0.22, 0.30) if not obstacle else Color(0.42, 0.28, 0.22)
	draw_colored_polygon(pts, col)
	# 边框
	draw_line(pts[0], pts[1], Color(0.06, 0.08, 0.12), 1.0)
	draw_line(pts[1], pts[2], Color(0.06, 0.08, 0.12), 1.0)
	draw_line(pts[2], pts[3], Color(0.06, 0.08, 0.12), 1.0)
	draw_line(pts[3], pts[0], Color(0.06, 0.08, 0.12), 1.0)

func _draw_cell_outline(p: Vector2i, col: Color) -> void:
	var pts := _cell_diamond(p)
	var fill := col
	fill.a = 0.35
	draw_colored_polygon(pts, fill)
	draw_line(pts[0], pts[1], col, 2.0)
	draw_line(pts[1], pts[2], col, 2.0)
	draw_line(pts[2], pts[3], col, 2.0)
	draw_line(pts[3], pts[0], col, 2.0)

func _hl_color(type_: int) -> Color:
	match type_:
		HL_MOVE: return Color(0.25, 0.55, 0.95)
		HL_THREAT: return Color(0.3, 0.8, 0.4)
		HL_SKILL: return Color(0.95, 0.35, 0.3)
		_: return Color(1, 1, 1)

## 网格坐标 → 世界坐标（相对本节点原点，格子中心）
## P3 地形高度：每格按 height 向上抬升 HEIGHT_STEP 像素，制造斜45°立体感（桥/台）。
## 注：高度只影响「渲染层」y 偏移；逻辑格坐标与 world_to_grid 拾取仍走基准面（不随高度偏移），
##     避免点选反算因高度而错位（高格的可见面靠基准格下半区仍可点中，符合等轴测惯例）。
const HEIGHT_STEP: float = 16.0
func cell_center(p: Vector2i) -> Vector2:
	var base := BattleGrid.grid_to_world_iso(p, tile_width, tile_height)
	if grid != null:
		var h: int = grid.get_height(p)
		if h != 0:
			base.y -= h * HEIGHT_STEP
	return base

## 世界坐标（相对本节点）→ 网格坐标（点击拾取反算）
func world_to_grid(local_world: Vector2) -> Vector2i:
	return BattleGrid.world_to_grid_iso(local_world, tile_width, tile_height)

## 网格像素包围盒中心（供场景层把战场居中到屏幕）
func pixel_center() -> Vector2:
	if grid == null:
		return Vector2.ZERO
	# 等轴测布局下，四个极值顶点对应的 cell center 范围
	var min_x: float = (0 - (grid.height - 1)) * tile_width * 0.5
	var max_x: float = ((grid.width - 1) - 0) * tile_width * 0.5
	var min_y: float = (0 + 0) * tile_height * 0.5
	var max_y: float = ((grid.width - 1) + (grid.height - 1)) * tile_height * 0.5
	return Vector2((min_x + max_x) * 0.5, (min_y + max_y) * 0.5)
