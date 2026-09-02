# tests/unit/test_map_layout_binding.gd
# P0 底图→战棋布局映射壳：验证战斗几何可来自「内嵌 grid / layout 引用 / 当前底图 tactical_layout」三级解析，
# 且部署落点随战斗配置走。逻辑层零 Node 引用，headless 可跑。
extends TestBase

func test_layout_reference_reuses_geometry() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_mapbound_001")
	var grid: BattleGrid = cs.get_grid()
	expect(grid != null, "layout 引用应成功构建网格")
	expect(grid.width == 12 and grid.height == 10, "应复用 courtyard_12x10 几何 12x10，实际 %dx%d" % [grid.width, grid.height])
	expect(grid.occupant_at(Vector2i(1, 5)) == "player", "玩家应按 battle.deployment 部署 (1,5)")
	expect(grid.occupant_at(Vector2i(10, 5)) == "bandit_001", "敌人应按 battle.deployment 部署 (10,5)")

func test_map_binding_without_grid() -> void:
	var cs := CombatService.new()
	GameManager.current_map_id = "town"
	cs.start_combat("tactical_mapbound_002")
	var grid: BattleGrid = cs.get_grid()
	expect(grid != null, "纯底图绑定（无 grid 无 layout）也应构建网格")
	expect(grid.width == 12 and grid.height == 10, "应继承 town 底图的 courtyard_12x10 几何 12x10，实际 %dx%d" % [grid.width, grid.height])
	expect(grid.occupant_at(Vector2i(1, 5)) == "player", "玩家应部署 (1,5)")
	expect(grid.occupant_at(Vector2i(10, 5)) == "bandit_001", "敌人应部署 (10,5)")
	GameManager.current_map_id = "town"   # 复位全局态，避免污染其它测试

func test_explicit_grid_still_wins() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	var grid: BattleGrid = cs.get_grid()
	expect(grid != null, "原内嵌 grid 战斗仍应构建网格")
	expect(grid.width == 10 and grid.height == 8, "内嵌 grid 几何优先级最高，应为 10x8，实际 %dx%d" % [grid.width, grid.height])
	expect(grid.occupant_at(Vector2i(1, 4)) == "player", "玩家应部署在内嵌 grid 的 (1,4)")

func test_studio_preview_uses_preset_layout() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_studio_preview")
	var grid: BattleGrid = cs.get_grid()
	expect(grid != null, "工作室后台预览战棋（layout 引用 preset_12x12）应成功构建网格")
	expect(grid.width == 12 and grid.height == 12, "应复用 preset_12x12 几何 12x12，实际 %dx%d" % [grid.width, grid.height])
	expect(grid.occupant_at(Vector2i(1, 4)) == "player", "玩家应按 battle.deployment 部署 (1,4)")
	expect(grid.occupant_at(Vector2i(8, 4)) == "bandit_001", "敌人应按 battle.deployment 部署 (8,4)")
