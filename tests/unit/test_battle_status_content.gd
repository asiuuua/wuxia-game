# tests/unit/test_battle_status_content.gd
# 战斗内容扩张切片 B（2026-08-29，战斗窗口主权）：状态机制内容化
# 目标：让 M3-2 的「护盾 / 反弹 / 复活」状态引擎在**真实战斗内容**里被调用，
#       而不只是 M3-2 单元测里的注入式用例。
# 做法：
#   1) 配置完整性（确定性，无 RNG）：新敌人 bandit_warden_001 / bandit_fanatic_001 的
#      abilities 必须指向 skills.json 中真实存在的技能，且这些技能确实施加
#      huti(护盾) / jingci(反弹) / buqu(复活) 三种 M3-2 状态。
#   2) 运行时：真实跑完 battle_bandit_elite，断言战斗内确实产生了
#      STATUS_APPLIED(huti/jingci/buqu) 与 SHIELD_ABSORB / REFLECT / REVIVE 事件——
#      证明三种状态机制已通过真实 ai_kit 在真实战斗里触发。
# 设计原则（同 test_battle_roster.gd / test_combat_smoke.gd）：
#   1) dodge_rate / crit_rate 归零，消除随机导致的 flaky
#   2) 不触发 DEFEAT finalize（玩家 hp 拉满，避免唤醒 DefeatHandler）
#   3) before_each 重置 PlayerState，避免用例互相污染
#   4) 注入固定 RNG 种子（见 test_elite_battle_shows_status_mechanics 内
#      `get_core().rng.configure(FIXED_SEED)`）：combat_core.configure(0) 默认用
#      系统时间戳当种子，导致每次事件序列不同、下游反应式事件(REFLECT/REVIVE/SHIELD_ABSORB)
#      概率性出现 → 非确定性失败。固定种子后全链路确定性可回归。

extends TestBase

const BATTLE_ID := "battle_bandit_elite"

func before_each() -> void:
	GameManager.player_state.init_default("测试侠", 1)
	GameManager.player_state.hp = 9999
	GameManager.player_state.max_hp = 9999
	GameManager.player_state.attack = 22
	GameManager.player_state.experience = 0

## 辅助：判断某敌人的 abilities 链路里是否存在「施加指定 status_id」的技能
func _enemy_has_status_skill(enemy_id: String, status_id: String) -> bool:
	var e: Dictionary = ConfigManager.get_enemy(enemy_id)
	if e.is_empty():
		return false
	for ab in e.get("abilities", []):
		if not (ab is Dictionary):
			continue
		var sid: String = ab.get("id", "")
		var skill: Dictionary = ConfigManager.get_ability(sid)
		if skill.is_empty():
			continue
		for eff in skill.get("effects", []):
			if eff is Dictionary and eff.get("status_id", "") == status_id:
				return true
	return false

## 配置完整性（确定性，无 RNG）：
## 新敌人 → 技能存在 → 技能施加 M3-2 状态。证明状态机制已接入真实战斗内容。
func test_elite_enemies_wire_status_mechanics() -> void:
	# 编成与敌人存在性
	var b: Dictionary = ConfigManager.get_battle(BATTLE_ID)
	expect(not b.is_empty(), "battle_bandit_elite 应存在")
	if b.is_empty():
		return
	var ids: Array = b.get("enemy_ids", [])
	expect(ids.has("bandit_warden_001"), "精英战编成应包含山贼盾卫")
	expect(ids.has("bandit_fanatic_001"), "精英战编成应包含山贼狂信徒")

	# 盾卫：护盾(huti) + 反弹(jingci)
	expect(not ConfigManager.get_enemy("bandit_warden_001").is_empty(), "山贼盾卫应存在于 enemies.json")
	expect(_enemy_has_status_skill("bandit_warden_001", "huti"), "盾卫应会施护盾(huti)")
	expect(_enemy_has_status_skill("bandit_warden_001", "jingci"), "盾卫应会施荆棘反弹(jingci)")

	# 狂信徒：复活(buqu)
	expect(not ConfigManager.get_enemy("bandit_fanatic_001").is_empty(), "山贼狂信徒应存在于 enemies.json")
	expect(_enemy_has_status_skill("bandit_fanatic_001", "buqu"), "狂信徒应会施不屈复活(buqu)")

## 运行时：真实战斗跑到胜利，且 M3-2 三种状态机制均被真实 ai_kit 触发
## 关键：注入固定 RNG 种子，消除「combat_core.configure(0) 用时间戳种子」导致的非确定性。
## 固定种子后，敌人选招/事件序列完全确定，6 条断言稳定成立、不再 2 败 1 过。
func test_elite_battle_shows_status_mechanics() -> void:
	GameManager.combat_service.start_combat(BATTLE_ID)
	# 覆盖 start_combat 内部按时间戳派生的种子，改为固定值 → 确定性回归
	GameManager.combat_service.get_core().rng.configure(20260829)
	var st: CombatState = GameManager.combat_service.get_state()
	if st == null:
		expect(false, "战斗状态应构建成功")
		return
	st.player.dodge_rate = 0.0
	st.player.crit_rate = 0.0
	for e in st.enemies:
		e.dodge_rate = 0.0
		e.crit_rate = 0.0

	# 累计玩家行动事件（含 DAMAGE / SHIELD_ABSORB / REFLECT / REVIVE）
	# 与敌人阶段事件（含 ACTION_SKILL / STATUS_APPLIED）
	var all_events: Array[CombatEvent] = []
	var guard := 0
	while not GameManager.combat_service.is_over() and guard < 200:
		all_events.append_array(GameManager.combat_service.player_attack_events(""))
		if GameManager.combat_service.is_over():
			break
		all_events.append_array(GameManager.combat_service.enemy_phase_events())
		guard += 1

	expect(GameManager.combat_service.is_over(),
		"精英战应在 200 回合内结束（实际 %d）" % guard)
	expect_eq(GameManager.combat_service.get_result(),
		CombatEnums.CombatResult.VICTORY, "结果应为胜利")

	# 统计三种 M3-2 状态被施加的次数 + 护盾吸收次数
	var applied := { "huti": 0, "jingci": 0, "buqu": 0 }
	var shield_absorb := 0
	var reflect := 0
	var revive := 0
	for e in all_events:
		if e.type == CombatEvent.Type.STATUS_APPLIED:
			var sid: String = e.status_id
			if applied.has(sid):
				applied[sid] += 1
		elif e.type == CombatEvent.Type.SHIELD_ABSORB:
			shield_absorb += 1
		elif e.type == CombatEvent.Type.REFLECT:
			reflect += 1
		elif e.type == CombatEvent.Type.REVIVE:
			revive += 1

	# 核心断言：三种状态机制确实在真实战斗里被敌人施放
	expect(applied["huti"] >= 1, "精英战中盾卫应真实施放护盾(huti)，实际 %d" % applied["huti"])
	expect(applied["jingci"] >= 1, "精英战中盾卫应真实施放荆棘(jingci)，实际 %d" % applied["jingci"])
	expect(applied["buqu"] >= 1, "精英战中狂信徒应真实施放不屈(buqu)，实际 %d" % applied["buqu"])
	expect(shield_absorb >= 1, "精英战中应发生护盾吸收(SHIELD_ABSORB)，实际 %d" % shield_absorb)
	# 反弹 / 复活为链路下游事件（需「施放后挨打 / 施放后阵亡」），确定性 RNG 下稳定出现
	expect(reflect >= 1, "精英战中应发生反弹(REFLECT)，实际 %d" % reflect)
	expect(revive >= 1, "精英战中应发生复活(REVIVE)，实际 %d" % revive)
