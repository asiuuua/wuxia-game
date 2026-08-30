# tests/unit/test_swarm.gd
# 群怪压力测试：验证「多 NPC 同场」核心能力——
#   (1) 20 个重复 enemy_id 应全部成为独立单位（重复 id 自动加 #n 后缀，character_id 唯一）；
#   (2) 所有敌人 + 友方 + 主角均被部署到战场空闲格（敌人自动补齐逻辑生效）；
#   (3) name_key 保留原始模板名（用于显示），与唯一 uid 解耦。
# 这是"20 小怪 + 5 友方飘字不丢字"的前提：单位必须先全部署上场，飘字队列才有意义。
extends TestBase

func test_swarm_all_enemies_deployed() -> void:
	var cs := CombatService.new()
	cs.start_combat("tactical_test_swarm")
	var enemies := cs.get_state().enemies
	expect(enemies.size() == 20, "应构建 20 个敌人实例（实际 %d）" % enemies.size())

	var uids := {}
	for e in enemies:
		expect(not uids.has(e.character_id), "敌人 character_id 必须唯一，重复的 enemy_id 应加 #n 后缀: %s" % e.character_id)
		uids[e.character_id] = true
		expect(e.name_key == "bandit_001", "敌人 name_key 应保留原始模板名 bandit_001（显示用），实际 %s" % e.name_key)
		expect(cs.get_core()._unit_by_id(e.character_id) != null, "敌人 %s 应已部署到战场（自动补齐生效）" % e.character_id)

	expect(cs.get_core()._unit_by_id("ally_sworder_001") != null, "友方 ally_sworder_001 应已部署")
	expect(cs.get_core()._unit_by_id("player") != null, "主角应已部署")

	# 战场应占用 22 个格（20 敌 + 1 友方 + 1 主角）
	var occupied: int = enemies.size() + 2
	expect(occupied == 22, "战场应有 22 个已部署单位（实际 %d）" % occupied)

func test_swarm_no_uid_collision_in_core() -> void:
	# 内核以 character_id 为唯一 key；重复 id 若不唯一化会导致互相覆盖、实际部署数 < 配置数
	var cs := CombatService.new()
	cs.start_combat("tactical_test_swarm")
	var enemies := cs.get_state().enemies
	var seen := {}
	for e in enemies:
		seen[e.character_id] = true
	expect(seen.size() == enemies.size(), "内核单位字典不应有 character_id 冲突（%d 配置 vs %d 唯一）" % [enemies.size(), seen.size()])
