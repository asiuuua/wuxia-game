# tests/unit/test_defeat_rule.gd
# 胜负修正（用户铁律）：
#   - 友方 NPC 单独阵亡 ≠ 失败
#   - 主角阵亡但友方 NPC 存活 ≠ 失败
#   - 主角 + 全部友方 NPC 同时阵亡 = 失败
#   - 单玩家（无友方）主角阵亡仍判负（向后兼容）
extends TestBase

func _ally(id: String) -> CombatCharacter:
	var a := CombatCharacter.new()
	a.character_id = id
	a.is_player = true
	a.max_hp = 50; a.hp = 50
	return a

func test_ally_death_not_defeat() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	var st: CombatState = cs.get_state()
	st.player_party.append(_ally("ally_a"))
	# 友方 NPC 阵亡，主角存活
	st.player_party[0].is_dead = true
	st.player.is_dead = false
	expect(cs.get_result() == CombatEnums.CombatResult.VICTORY, "友方 NPC 死、主角活 → 不应判负，实际:%d" % cs.get_result())

func test_protagonist_dead_ally_alive_not_defeat() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	var st: CombatState = cs.get_state()
	st.player_party.append(_ally("ally_a"))
	# 主角阵亡，但友方 NPC 存活
	st.player.is_dead = true
	st.player_party[0].is_dead = false
	expect(cs.get_result() == CombatEnums.CombatResult.VICTORY, "主角死、友方 NPC 活 → 不能判负，实际:%d" % cs.get_result())

func test_all_player_side_dead_is_defeat() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	var st: CombatState = cs.get_state()
	st.player_party.append(_ally("ally_a"))
	st.player.is_dead = true
	st.player_party[0].is_dead = true
	expect(cs.get_result() == CombatEnums.CombatResult.DEFEAT, "主角+友方 NPC 全灭 → 判负，实际:%d" % cs.get_result())

func test_single_player_defeat_unchanged() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	cs.get_state().player.is_dead = true
	expect(cs.get_result() == CombatEnums.CombatResult.DEFEAT, "单玩家主角阵亡仍判负（向后兼容），实际:%d" % cs.get_result())

func test_allies_config_injected_to_player_party() -> void:
	# 战斗配置 allies 应注入玩家方，使友方 NPC 成为可控/计入胜负的单位
	var cs := CombatService.new()
	cs.start_combat("tactical_ally_inject")
	var st: CombatState = cs.get_state()
	var found := false
	for p in st.player_party:
		if p.character_id == "test_ally_npc" and p.is_player:
			found = true
	expect(found, "battle.allies 应把 test_ally_npc 注入 player_party 且 is_player=true")
	expect(st.player_party.size() >= 1, "player_party 应至少含注入的友方 NPC")
