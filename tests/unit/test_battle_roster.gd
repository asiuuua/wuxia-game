# tests/unit/test_battle_roster.gd
# 战斗内容扩张切片 A（2026-08-29，战斗窗口主权）：真实编成驱动 AI
# 目标：证明「enemies.json 配置 → combat_service 归一化 ai_kit → 权重/条件选技 →
#       整场战斗跑到胜利」整条链路在真实数据（而非注入 kit）下跑通。
# 背景：此前 battle_bandit_001 是两个相同山贼，头目 bandit_002（带 self_mp_above:0.6
#       条件技）只活在 battle_sect_trials，M3-1 的权重/条件选技从未在首战真实编成里被验证。
# 设计原则（与 test_combat_smoke.gd 一致）：
#   1) dodge_rate / crit_rate 归零，消除随机导致的 flaky
#   2) 不触发 DEFEAT finalize（避免唤醒 DefeatHandler）
#   3) before_each 重置 PlayerState，避免用例互相污染

extends TestBase

const BATTLE_ID := "battle_bandit_001"

func before_each() -> void:
	GameManager.player_state.init_default("测试侠", 1)
	GameManager.player_state.hp = 9999
	GameManager.player_state.max_hp = 9999
	GameManager.player_state.attack = 60
	GameManager.player_state.experience = 0

## 数据锁：第一战编成应包含头目 bandit_002（接 M3-1 条件门控样例）
func test_first_battle_includes_headman() -> void:
	var b: Dictionary = ConfigManager.get_battle(BATTLE_ID)
	expect(not b.is_empty(), "battle_bandit_001 应存在")
	if b.is_empty():
		return
	var ids: Array = b.get("enemy_ids", [])
	expect(ids.has("bandit_002"), "首战编成应包含头目 bandit_002，实际 %s" % str(ids))

## 头目从真实 ai_kit 释放招式：bandit_002 起始 mp=30，self_mp_above:0.6(=18) 条件满足，
## 单回合 enemy_phase 必产生其 ACTION_SKILL（blade 或 xinfa）。证明配置→ai_kit→选技整链。
func test_headman_casts_skill_from_real_kit() -> void:
	GameManager.combat_service.start_combat(BATTLE_ID)
	var st: CombatState = GameManager.combat_service.get_state()
	if st == null:
		expect(false, "战斗状态应构建成功")
		return
	st.player.dodge_rate = 0.0
	for e in st.enemies:
		e.dodge_rate = 0.0
	var events: Array[CombatEvent] = GameManager.combat_service.enemy_phase_events()
	var skill_ev: CombatEvent = null
	for e in events:
		if e.type == CombatEvent.Type.ACTION_SKILL and e.actor_id == "bandit_002":
			skill_ev = e
	expect(skill_ev != null, "头目 bandit_002 应从真实 ai_kit 释放招式（ACTION_SKILL）")
	if skill_ev == null:
		return
	expect(skill_ev.skill_id == "blade_duanshui_001" or skill_ev.skill_id == "xinfa_ningshen_001",
		"释放的应是 blade 或 xinfa，实际 %s" % skill_ev.skill_id)

## 端到端：跑完整场真实编成战斗至胜利，且全程至少捕获一个敌人 ACTION_SKILL
## （证明权重/条件选技在真实数据下被消费，而非退化为纯普攻）
func test_roster_battle_runs_to_victory() -> void:
	GameManager.combat_service.start_combat(BATTLE_ID)
	var st: CombatState = GameManager.combat_service.get_state()
	if st == null:
		expect(false, "战斗状态应构建成功")
		return
	st.player.dodge_rate = 0.0
	st.player.crit_rate = 0.0
	for e in st.enemies:
		e.dodge_rate = 0.0
		e.crit_rate = 0.0
	var all_events: Array[CombatEvent] = []
	var guard := 0
	while not GameManager.combat_service.is_over() and guard < 80:
		GameManager.combat_service.player_attack("")
		if GameManager.combat_service.is_over():
			break
		all_events.append_array(GameManager.combat_service.enemy_phase_events())
		guard += 1
	expect(GameManager.combat_service.is_over(), "真实编成战斗应在 80 回合内结束（实际 %d）" % guard)
	expect_eq(GameManager.combat_service.get_result(), CombatEnums.CombatResult.VICTORY, "结果应为胜利")
	var skill_count := 0
	for e in all_events:
		if e.type == CombatEvent.Type.ACTION_SKILL and (e.actor_id == "bandit_001" or e.actor_id == "bandit_002"):
			skill_count += 1
	expect(skill_count >= 1, "真实编成战斗中敌人应至少释放 1 次招式（权重/条件选技生效），实际 %d" % skill_count)
