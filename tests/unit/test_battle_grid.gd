# tests/unit/test_battle_grid.gd
# BattleGrid 纯逻辑单测：BFS 可达 / A* 路径 / 技能范围 / 占用表 / 等轴测换算
extends TestBase

func test_bfs_reachable_basic() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	var reach: Array[Vector2i] = g.bfs_reachable(Vector2i(0, 0), 2)
	# 角落起点(0,0) 曼哈顿<=2 且不含起点：(1,0)(0,1)(2,0)(1,1)(0,2) = 5
	expect(reach.size() == 5, "5x5 角落起点(0,0)步数2 应得5格，实际 %d" % reach.size())
	expect(not (Vector2i(0, 0) in reach), "可达集合不应含起点自身")
	expect(Vector2i(2, 0) in reach, "应包含 (2,0)")

func test_bfs_obstacle_blocks_path() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	g.set_obstacle(Vector2i(1, 0), true)   # 挡住 (0,0)->(2,0) 的唯一通道
	var reach: Array[Vector2i] = g.bfs_reachable(Vector2i(0, 0), 2)
	expect(not (Vector2i(1, 0) in reach), "障碍格不应可达")
	expect(not (Vector2i(2, 0) in reach), "被障碍切断的 (2,0) 不应可达")
	expect(Vector2i(0, 1) in reach, "应可绕到 (0,1)")

func test_occupant_blocks_reachable() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	g.set_occupant(Vector2i(1, 0), "enemy_x")
	var reach: Array[Vector2i] = g.bfs_reachable(Vector2i(0, 0), 2)
	expect(not (Vector2i(2, 0) in reach), "被他人占用的后续格不应可达")
	# 自己占的格用 ignore 后应可落脚（部署/重部署用）
	expect(g.is_walkable(Vector2i(1, 0), "enemy_x"), "ignore 自身时应可走")

func test_astar_path_basic() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	var path: Array[Vector2i] = g.astar_path(Vector2i(0, 0), Vector2i(2, 2))
	expect(path.size() == 4, "曼哈顿距离4 路径应含4格，实际 %d" % path.size())
	expect(path[-1] == Vector2i(2, 2), "终点应为 (2,2)")
	expect(path[0] != Vector2i(0, 0), "路径不应含起点")
	# 路径连续性：每步曼哈顿距离1
	for i in range(1, path.size()):
		var d: int = abs(path[i].x - path[i-1].x) + abs(path[i].y - path[i-1].y)
		expect(d == 1, "路径第%d步应为相邻格" % i)

func test_astar_blocked_returns_empty() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	# 竖墙挡住 x=2 整列（y=0..4），(0,0)->(4,0) 不可达
	for y in range(5):
		g.set_obstacle(Vector2i(2, y), true)
	var path: Array[Vector2i] = g.astar_path(Vector2i(0, 0), Vector2i(4, 0))
	expect(path.is_empty(), "被墙完全隔断应返回空路径")

func test_skill_range_diamond() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	var cells: Array[Vector2i] = g.skill_range(Vector2i(2, 2), 1, "diamond")
	expect(cells.size() == 5, "菱形 range1 应5格(中心+4正交)，实际 %d" % cells.size())
	expect(Vector2i(2, 2) in cells, "应含中心")
	expect(Vector2i(3, 2) in cells and Vector2i(1, 2) in cells, "应含左右正交")
	expect(not (Vector2i(3, 3) in cells), "对角线不应在菱形内")

func test_skill_range_square() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	var cells: Array[Vector2i] = g.skill_range(Vector2i(2, 2), 1, "square")
	expect(cells.size() == 9, "方形 range1 应9格，实际 %d" % cells.size())
	expect(Vector2i(3, 3) in cells, "对角线应在方形内")

func test_skill_range_self() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	var cells: Array[Vector2i] = g.skill_range(Vector2i(2, 2), 0, "self")
	expect(cells.size() == 1 and cells[0] == Vector2i(2, 2), "self 应仅中心1格")

func test_iso_roundtrip() -> void:
	var tw: float = 128.0
	var th: float = 64.0
	for gx in range(6):
		for gy in range(6):
			var p := Vector2i(gx, gy)
			var w := BattleGrid.grid_to_world_iso(p, tw, th)
			var back := BattleGrid.world_to_grid_iso(w, tw, th)
			expect(back == p, "等轴测换算应往返一致：%s -> %s -> %s" % [p, w, back])

func test_occupant_api() -> void:
	var g := BattleGrid.new()
	g.width = 5; g.height = 5
	g.set_occupant(Vector2i(3, 3), "u1")
	expect(g.occupant_at(Vector2i(3, 3)) == "u1", "占用查询应返回 unit id")
	g.clear_occupant(Vector2i(3, 3))
	expect(g.occupant_at(Vector2i(3, 3)) == "", "清除后应为空")
