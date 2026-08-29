# data/runtime/battle_grid.gd
# 战术战棋网格数据层（战斗窗口主权 · 纯 RefCounted，可 headless 单测）
# 职责（对标逸剑风云决斜45°方格）：
#   - 网格尺寸 / 障碍 / 占用表（一张表搞定"格子被谁占了"，避免多敌挤同格）
#   - BFS 可达集合（玩家可移动蓝格）、A* 最短路径（敌人走位）
#   - 技能范围（方/菱/十字/自身）—— 只算"哪些格在范围内"，不做伤害判定
#   - 等轴测 world<->grid 坐标换算（供 BattleEntity 站位 / BattleGridNode 拾取）
# ⚠️ 本类只算数据，绝不持有 Node、不判伤害；伤害结算永远走 CombatCore._resolve_hit。
# ⚠️ 等轴测换算依赖"菱形"布局约定：world = ((gx-gy)*tw/2, (gx+gy)*th/2)，
#    与 Godot TileMap 设 tile_shape=ISOMETRIC 时一致（见 BattleGridNode）。

extends RefCounted
class_name BattleGrid

var width: int = 10
var height: int = 8

# 障碍：key="x,y" -> true（地形/树木/石头，永远不可走）
var _obstacles: Dictionary = {}
# 占用：key="x,y" -> unit_id（某单位当前站在这格）
var _occupants: Dictionary = {}

func _key(p: Vector2i) -> String:
	return "%d,%d" % [p.x, p.y]

func in_bounds(p: Vector2i) -> bool:
	return p.x >= 0 and p.x < width and p.y >= 0 and p.y < height

## 该格是否能落脚（在界内 + 非障碍 + 未被"他人"占用）
## ignore_unit 用于校验"自己当前站的那格"不算阻挡
func is_walkable(p: Vector2i, ignore_unit: String = "") -> bool:
	if not in_bounds(p):
		return false
	if _obstacles.has(_key(p)):
		return false
	if _occupants.has(_key(p)) and _occupants[_key(p)] != ignore_unit:
		return false
	return true

## 该格是否为障碍（地形/树木/石头，永远不可走）—— 视图绘制地形层用
func is_obstacle_cell(p: Vector2i) -> bool:
	return _obstacles.has(_key(p))

func set_obstacle(p: Vector2i, val: bool) -> void:
	var k: String = _key(p)
	if val:
		_obstacles[k] = true
	else:
		_obstacles.erase(k)

func set_occupant(p: Vector2i, unit_id: String) -> void:
	_occupants[_key(p)] = unit_id

func clear_occupant(p: Vector2i) -> void:
	_occupants.erase(_key(p))

func occupant_at(p: Vector2i) -> String:
	return _occupants.get(_key(p), "")

func _dirs(allow_diag: bool) -> Array[Vector2i]:
	var d: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	if allow_diag:
		d.append_array([Vector2i(1,1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(-1,-1)])
	return d

## BFS 可达集合：从 start 出发，最多 max_steps 步，遇障碍/他人格阻断
## 返回不含 start 本身的可达格列表（用于蓝色可移动高亮）
func bfs_reachable(start: Vector2i, max_steps: int, allow_diag: bool = false) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if not in_bounds(start):
		return result
	var visited: Dictionary = {}
	var queue: Array = [{"pos": start, "d": 0}]
	visited[_key(start)] = true
	for dv in _dirs(allow_diag):
		var np: Vector2i = start + dv
		var k: String = _key(np)
		if visited.has(k) or not in_bounds(np) or not is_walkable(np, ""):
			continue
		var nd: int = 1
		if nd > max_steps:
			continue
		visited[k] = true
		result.append(np)
		queue.append({"pos": np, "d": nd})
	while not queue.is_empty():
		var cur: Dictionary = queue.pop_front()
		var p: Vector2i = cur["pos"]
		var d: int = int(cur["d"])
		for dv in _dirs(allow_diag):
			var np2: Vector2i = p + dv
			var k2: String = _key(np2)
			if visited.has(k2) or not in_bounds(np2) or not is_walkable(np2, ""):
				continue
			var nd2: int = d + 1
			if nd2 > max_steps:
				continue
			visited[k2] = true
			result.append(np2)
			queue.append({"pos": np2, "d": nd2})
	return result

## A* 最短路径（网格等权，BFS 即最优）：从 start 到 goal，返回不含 start、含 goal 的路径
## goal 必须可落脚（空地）；若不可达返回空数组
func astar_path(start: Vector2i, goal: Vector2i, allow_diag: bool = false) -> Array[Vector2i]:
	if not in_bounds(start) or not in_bounds(goal) or start == goal:
		return []
	var visited: Dictionary = {}
	var parent: Dictionary = {}
	var queue: Array = [start]
	visited[_key(start)] = true
	while not queue.is_empty():
		var p: Vector2i = queue.pop_front()
		for dv in _dirs(allow_diag):
			var np: Vector2i = p + dv
			var k: String = _key(np)
			if visited.has(k) or not in_bounds(np) or not is_walkable(np, ""):
				continue
			visited[k] = true
			parent[k] = p
			if np == goal:
				var path: Array[Vector2i] = [np]
				var cur: Vector2i = p
				while cur != start:
					path.append(cur)
					cur = parent[_key(cur)]
				path.reverse()
				return path
			queue.append(np)
	return []

## 技能范围：以 center 为中心，按 shape 返回所有在范围内的格（含 center 自身）
## shape: "diamond"(曼哈顿<=range) | "square"(切比雪夫<=range) | "cross"(十字<=range) | "self"(仅center)
## 说明：范围只决定"哪些格可以染红"，真正的目标合法性由 CombatCore 按距离+占用复核
func skill_range(center: Vector2i, range_val: int, shape: String) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if range_val <= 0 or shape == "self":
		return [center]
	for x in range(width):
		for y in range(height):
			var p: Vector2i = Vector2i(x, y)
			var md: int = abs(p.x - center.x) + abs(p.y - center.y)
			var cheb: int = max(abs(p.x - center.x), abs(p.y - center.y))
			var ok: bool = false
			match shape:
				"square":
					ok = (cheb <= range_val)
				"cross":
					ok = (md <= range_val and (p.x == center.x or p.y == center.y))
				_:
					ok = (md <= range_val)   # diamond 默认
			if ok:
				result.append(p)
	return result

# ─────────────── 等轴测坐标换算（菱形布局）───────────────
## 网格坐标 → 世界坐标：world = ((gx-gy)*tw/2, (gx+gy)*th/2)
static func grid_to_world_iso(pos: Vector2i, tile_w: float, tile_h: float) -> Vector2:
	return Vector2((pos.x - pos.y) * tile_w * 0.5, (pos.x + pos.y) * tile_h * 0.5)

## 世界坐标 → 网格坐标（四舍五入，供点击拾取反算）
static func world_to_grid_iso(world: Vector2, tile_w: float, tile_h: float) -> Vector2i:
	var a: float = tile_w * 0.5
	var b: float = tile_h * 0.5
	var gx: float = (world.x / a + world.y / b) * 0.5
	var gy: float = (world.y / b - world.x / a) * 0.5
	return Vector2i(roundi(gx), roundi(gy))
