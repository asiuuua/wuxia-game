# tests/unit/test_party.gd
# P2 多玩家单位（组队）：逻辑层支持主角 + 同伴（player_party）各自行动、纳入回合序列、is_over 考虑同伴。
# 注意：本窗战斗 UI 当前仅驱动主角，组队选择 UI 为后续增量；本测试只验证内核能力，向后兼容单玩家模式。
extends TestBase

func _make_ally(id: String) -> CombatCharacter:
	var a := CombatCharacter.new()
	a.character_id = id
	a.is_player = true
	a.max_hp = 100; a.hp = 100
	a.max_mp = 50; a.mp = 50
	return a

func test_party_in_round_sequence() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	cs.get_state().player_party.append(_make_ally("ally_001"))
	cs.deploy_unit("ally_001", Vector2i(2, 4))
	var seq: Array[String] = cs.get_core().get_round_sequence()
	expect("ally_001" in seq, "组队同伴应进入回合序列")
	expect(seq.has("player"), "主角仍在序列中")

func test_party_actor_can_attack() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	cs.get_state().player_party.append(_make_ally("ally_001"))
	cs.deploy_unit("ally_001", Vector2i(7, 4))   # 敌人 bandit_001 在 (8,4)
	var enemy: CombatCharacter = cs.get_state().enemies[0]
	enemy.dodge_rate = 0.0; enemy.crit_rate = 0.0   # 消除随机，防 flaky
	var hp_before: int = enemy.hp
	var evs: Array = cs.player_attack_events("bandit_001", "ally_001")
	expect(evs.size() > 0, "同伴普攻应产生事件流")
	expect(enemy.hp < hp_before, "同伴普攻后敌人气血应下降（%d -> %d）" % [hp_before, enemy.hp])

func test_is_over_considers_party() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	cs.get_state().player_party.append(_make_ally("ally_001"))
	# 主角阵亡但同伴存活 → 不应结束
	cs.get_state().player.is_dead = true
	expect(cs.is_over() == false, "主角阵亡但同伴存活时战斗不应结束")
	cs.get_state().player_party[0].is_dead = true
	expect(cs.is_over() == true, "主角与同伴均阵亡时战斗应结束")

func test_single_player_mode_unchanged() -> void:
	# 无组队时行为与改造前完全一致
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	expect(cs.is_over() == false, "单玩家模式开局不应结束")
	cs.get_state().player.is_dead = true
	expect(cs.is_over() == true, "单玩家模式主角阵亡应立即结束")
