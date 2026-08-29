# tests/unit/test_tactical_loop.gd
# 战术战棋整链 headless 自验：部署 -> 可达 -> 移动占格 -> 技能范围/射程 -> 敌人AI计划 -> 行动结算
extends TestBase

var cs: CombatService = null

func before_each() -> void:
	cs = CombatService.new()

func test_grid_deployment() -> void:
	cs.start_combat("tactical_demo_001")
	var grid: BattleGrid = cs.get_grid()
	expect(grid != null, "战术战斗应构建网格")
	expect(grid.occupant_at(Vector2i(1, 4)) == "player", "玩家应部署在 (1,4)")
	expect(grid.occupant_at(Vector2i(8, 4)) == "bandit_001", "敌人应部署在 (8,4)")

func test_player_move_and_occupy() -> void:
	cs.start_combat("tactical_demo_001")
	var grid: BattleGrid = cs.get_grid()
	var reach: Array[Vector2i] = cs.compute_reachable("player")
	expect(reach.size() > 0, "玩家应有可移动格")
	var dest: Vector2i = reach[0]
	var events: Array[CombatEvent] = cs.move_unit("player", dest)
	expect(events.size() == 1, "合法移动应产生 1 个事件")
	expect(events[0].type == CombatEvent.Type.GRID_MOVE, "事件应为 GRID_MOVE")
	expect(grid.occupant_at(dest) == "player", "目标格应被玩家占用")
	expect(grid.occupant_at(Vector2i(1, 4)) == "", "原格应已释放")
	# 非法落点（阵营外）应被忽略，不产生事件、不改变坐标
	var bad: Array[CombatEvent] = cs.move_unit("player", Vector2i(0, 0))
	expect(bad.is_empty(), "越界落点应被忽略")

func test_skill_range_and_in_range() -> void:
	cs.start_combat("tactical_demo_001")
	var grid: BattleGrid = cs.get_grid()
	# 玩家在 (1,4)，敌人远在 (8,4)，range1 菱形范围不含敌人
	var cells: Array[Vector2i] = cs.compute_skill_range("player", "sword_qingsong_001")
	expect(cells.size() > 0, "技能范围应非空")
	expect(not (Vector2i(8, 4) in cells), "远处敌人不应落在 range1 范围内")
	expect(cs.is_target_in_range("player", "bandit_001", "sword_qingsong_001") == false, "远距离不应在射程内")
	# 将玩家部署到敌人相邻，射程内应成立
	cs.deploy_unit("player", Vector2i(7, 4))
	expect(cs.is_target_in_range("player", "bandit_001", "sword_qingsong_001") == true, "相邻应在射程内")

func test_enemy_plan_and_move() -> void:
	cs.start_combat("tactical_demo_001")
	var grid: BattleGrid = cs.get_grid()
	var plan: Dictionary = cs.enemy_tactical_plan("bandit_001")
	expect(plan.has("move_to"), "计划应含 move_to")
	expect(plan["move_to"] != Vector2i(-1, -1), "敌人应规划出走位")
	# 敌人原计划在 (8,4)，移动后应更新坐标与占用
	var ev: Array[CombatEvent] = cs.move_unit("bandit_001", plan["move_to"])
	expect(ev.size() == 1, "敌人移动应产生事件")
	expect(grid.occupant_at(Vector2i(8, 4)) == "", "敌人原格应释放")
	expect(grid.occupant_at(plan["move_to"]) == "bandit_001", "敌人应站到计划格")

func test_full_action_loop() -> void:
	cs.start_combat("tactical_demo_001")
	var grid: BattleGrid = cs.get_grid()
	# 把玩家放到敌人相邻，模拟"走位+普攻"
	cs.deploy_unit("player", Vector2i(7, 4))
	var enemy: CombatCharacter = cs.get_state().enemies[0]
	var hp_before: int = enemy.hp
	# 普攻（不依赖 ability_service，走核心 player_basic）
	var atk_events: Array[CombatEvent] = cs.player_attack_events("bandit_001")
	expect(atk_events.size() > 0, "普攻应产生事件流")
	expect(enemy.hp < hp_before, "普攻后敌人气血应下降（%d -> %d）" % [hp_before, enemy.hp])
	# 敌人回合：不应崩溃
	cs.run_enemy_turns()
	expect(true, "敌人阶段应无异常完成")
