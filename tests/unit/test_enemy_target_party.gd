# tests/unit/test_enemy_target_party.gd
# 7.3.2 敌人 AI targeting 组队：敌人应把"玩家方（主角+存活同伴）中最低气血"作为目标，
# 不再写死 state.player；单玩家模式（无组队）保持只打主角（向后兼容）。
extends TestBase

func _make_ally(id: String, hp: int) -> CombatCharacter:
	var a := CombatCharacter.new()
	a.character_id = id
	a.is_player = true
	a.max_hp = 100; a.hp = hp
	a.max_mp = 50; a.mp = 50
	return a

func test_enemy_targets_lowest_hp_in_party() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	var st: CombatState = cs.get_state()
	# 主角 100 血，同伴只有 20 血 → 敌人应集火同伴
	st.player.hp = 100
	st.player.dodge_rate = 0.0
	var ally := _make_ally("ally_low", 20)
	ally.dodge_rate = 0.0
	st.player_party.append(ally)
	cs.deploy_unit("ally_low", Vector2i(2, 4))
	var enemy: CombatCharacter = st.enemies[0]
	enemy.crit_rate = 0.0
	enemy.ai_kit = []   # 强制普攻兜底，避免权重随机
	var evs: Array = cs.get_core().enemy_act(enemy.character_id)
	# ACTION_BASIC 的 target 应为最低气血的同伴
	var targeted := ""
	for ev in evs:
		if ev.type == CombatEvent.Type.ACTION_BASIC:
			targeted = ev.target_id
	expect(targeted == "ally_low", "敌人应锁定最低气血的玩家方单位（同伴），实际: %s" % targeted)
	expect(ally.hp < 20, "同伴应受到伤害（%d < 20）" % ally.hp)
	expect(st.player.hp == 100, "主角不应受到普攻伤害（敌人集火弱者）")

func test_enemy_falls_back_to_player_when_ally_full_hp() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	var st: CombatState = cs.get_state()
	st.player.hp = 30   # 主角更低血
	st.player.dodge_rate = 0.0
	var ally := _make_ally("ally_high", 100)
	ally.dodge_rate = 0.0
	st.player_party.append(ally)
	cs.deploy_unit("ally_high", Vector2i(2, 4))
	var enemy: CombatCharacter = st.enemies[0]
	enemy.crit_rate = 0.0
	enemy.ai_kit = []
	var evs: Array = cs.get_core().enemy_act(enemy.character_id)
	var targeted := ""
	for ev in evs:
		if ev.type == CombatEvent.Type.ACTION_BASIC:
			targeted = ev.target_id
	expect(targeted == "player", "主角更低血时应被锁定，实际: %s" % targeted)

func test_single_player_mode_enemy_targets_player() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_demo_001")
	var st: CombatState = cs.get_state()
	st.player.dodge_rate = 0.0
	var enemy: CombatCharacter = st.enemies[0]
	enemy.crit_rate = 0.0
	enemy.ai_kit = []
	var evs: Array = cs.get_core().enemy_act(enemy.character_id)
	var targeted := ""
	for ev in evs:
		if ev.type == CombatEvent.Type.ACTION_BASIC:
			targeted = ev.target_id
	expect(targeted == "player", "无组队时敌人仍只打主角（向后兼容），实际: %s" % targeted)
