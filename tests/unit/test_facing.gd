# tests/unit/test_facing.gd
# P1 朝向：纯逻辑枚举由「逻辑坐标差值」推导，与地图尺寸/屏幕无关
extends TestBase

func test_facing_from_delta() -> void:
	expect(CombatCharacter.calc_facing(Vector2i(0, 0), Vector2i(0, -1)) == CombatCharacter.FACING.UP, "向上位移应为 UP")
	expect(CombatCharacter.calc_facing(Vector2i(0, 0), Vector2i(0, 1)) == CombatCharacter.FACING.DOWN, "向下位移应为 DOWN")
	expect(CombatCharacter.calc_facing(Vector2i(0, 0), Vector2i(-1, 0)) == CombatCharacter.FACING.LEFT, "向左位移应为 LEFT")
	expect(CombatCharacter.calc_facing(Vector2i(0, 0), Vector2i(1, 0)) == CombatCharacter.FACING.RIGHT, "向右位移应为 RIGHT")

func test_facing_set_on_move() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	var player: CombatCharacter = cs.get_state().player
	expect(player.grid_pos == Vector2i(1, 4), "玩家初始应在 (1,4)")
	var evs: Array = cs.move_unit("player", Vector2i(2, 4))
	expect(evs.size() == 1, "移动应产生 1 个事件")
	expect(player.facing == CombatCharacter.FACING.RIGHT, "右移后玩家应面朝 RIGHT，实际 %d" % player.facing)
	cs.move_unit("player", Vector2i(2, 5))
	expect(player.facing == CombatCharacter.FACING.DOWN, "下移后玩家应面朝 DOWN，实际 %d" % player.facing)
