# tests/unit/test_terrain_height.gd
# P3 地形高度层：BattleGrid 存高、BattleGridNode.cell_center 按高度抬升（y 减小），逻辑格坐标不受影响。
extends TestBase

func test_height_stored() -> void:
	var g := BattleGrid.new()
	g.width = 4; g.height = 4
	g.set_height(Vector2i(2, 2), 3)
	expect(g.get_height(Vector2i(2, 2)) == 3, "高度层应存储 3")
	expect(g.get_height(Vector2i(0, 0)) == 0, "未设置格高度应为 0")

func test_cell_center_raised_by_height() -> void:
	var g := BattleGrid.new()
	g.width = 4; g.height = 4
	g.set_height(Vector2i(2, 2), 3)
	var gn := BattleGridNode.new()
	gn.grid = g
	# 同一格：带高度 vs 基准面（直接算 grid_to_world_iso）应差 3×HEIGHT_STEP
	var flat_y: float = BattleGrid.grid_to_world_iso(Vector2i(2, 2), gn.tile_width, gn.tile_height).y
	var raised_y: float = gn.cell_center(Vector2i(2, 2)).y
	expect(raised_y < flat_y, "高处格 y 应比基准面小（被抬升），%f vs %f" % [raised_y, flat_y])
	expect(abs((flat_y - raised_y) - 3 * BattleGridNode.HEIGHT_STEP) < 0.001, "抬升量应为 3×HEIGHT_STEP")
	# 平地格高度 0 时不应偏移
	expect(abs(gn.cell_center(Vector2i(0, 0)).y - BattleGrid.grid_to_world_iso(Vector2i(0,0), gn.tile_width, gn.tile_height).y) < 0.001, "高度 0 格不应偏移")
	# 逻辑格坐标反算仍走基准面（不随高度偏移），保证点选不漂移
	var wp := BattleGrid.grid_to_world_iso(Vector2i(2, 2), gn.tile_width, gn.tile_height)
	var back := BattleGrid.world_to_grid_iso(wp, gn.tile_width, gn.tile_height)
	expect(back == Vector2i(2, 2), "高度不影响逻辑格坐标反算往返")
