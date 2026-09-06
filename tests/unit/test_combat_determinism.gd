# tests/unit/test_combat_determinism.gd
# AB-6 确定性与回放（11 图 / VS-003，B7 锚 2026-09-06）：同 seed 双跑状态轨迹逐位相等。
# 只写测试不动战斗域生产代码（战斗窗主权）；确定性链 = seed → SeededRNG → dodge/crit/AI roll。
# 安全约定：同 test_combat_smoke——不触发 DEFEAT finalize（不唤醒 DefeatHandler 死亡惩罚）。

extends TestBase
class_name TestCombatDeterminism

const BATTLE_ID := "battle_bandit_001"
const STEPS := 12

func before_each() -> void:
	GameManager.player_state.init_default("测试侠", 1)
	GameManager.player_state.hp = 9999
	GameManager.player_state.max_hp = 9999
	GameManager.player_state.attack = 50
	GameManager.player_state.experience = 0

## 打一场固定脚本战斗，逐步记录全员 HP 快照轨迹
func _fight_trace(seed_val: int) -> Array:
	GameManager.player_state.init_default("测试侠", 1)
	GameManager.player_state.hp = 9999
	GameManager.player_state.max_hp = 9999
	GameManager.player_state.attack = 50
	GameManager.combat_service.start_combat(BATTLE_ID)
	var core = GameManager.combat_service.get_core()
	if core != null and core.rng != null:
		core.rng.configure(seed_val)   # AB-6：seed 显式注入（start 默认墙钟派生，此处覆盖）
	var st: CombatState = GameManager.combat_service.get_state()
	var trace := []
	for i in STEPS:
		if GameManager.combat_service.is_over():
			break
		GameManager.combat_service.player_attack("")
		trace.append(_snapshot(st))
		if GameManager.combat_service.is_over():
			trace.append("END:VICTORY" if GameManager.combat_service.get_result() == CombatEnums.CombatResult.VICTORY else "END:DEFEAT")
			break
		GameManager.combat_service.run_enemy_turns()
		trace.append(_snapshot(st))
	return trace

func _snapshot(st: CombatState) -> String:
	var parts := ["P%d" % st.player.hp]
	for e in st.enemies:
		parts.append("E%d" % e.hp)
	return "|".join(parts)

# === AB-6 核心：同 seed 双跑轨迹逐位相等（确定性回归锚） ===
func test_same_seed_identical_trace() -> void:
	var t1 := _fight_trace(424242)
	# 完全重置后第二跑（start_combat 每次 new CombatCore，rng 全新）
	var t2 := _fight_trace(424242)
	expect(t1.size() > 3, "轨迹应有足够步数（实际 %d 步）" % t1.size())
	expect(t1 == t2, "同 seed 双跑轨迹应逐位相等（K-R16/AB-6 确定性铁律）")
	# 逐位对比首尾快照帮助定位漂移点（首败时信息更足）
	if t1.size() == t2.size():
		for i in t1.size():
			if t1[i] != t2[i]:
				expect(false, "轨迹第 %d 步漂移: %s vs %s" % [i, t1[i], t2[i]])
				break

# === 不同 seed 轨迹应不同（随机性真实生效，防「假确定性」） ===
func test_different_seed_diverges() -> void:
	var t1 := _fight_trace(424242)
	var t2 := _fight_trace(999999)
	expect(t1.size() > 3 and t2.size() > 3, "两条轨迹都应有足够步数")
	# 12+ 步含多次 dodge/crit/AI roll，同轨迹概率可忽略（保守不设 flaky 风险断言）
	expect(t1 != t2, "不同 seed 的轨迹应分叉（随机性生效；若恒等需查 rng 注入）")

# === dodge/crit 归零（无随机分支）时战斗结果稳定（冒烟基线与确定性正交） ===
func test_zero_random_branches_stable_result() -> void:
	var results := []
	for run in 2:
		GameManager.player_state.init_default("测试侠", 1)
		GameManager.player_state.hp = 9999
		GameManager.player_state.max_hp = 9999
		GameManager.player_state.attack = 9999   # 一击必杀路径
		GameManager.combat_service.start_combat(BATTLE_ID)
		var st: CombatState = GameManager.combat_service.get_state()
		for e in st.enemies:
			e.hp = 1
			e.dodge_rate = 0.0
		st.player.crit_rate = 0.0
		st.player.dodge_rate = 0.0
		var guard := 0
		while not GameManager.combat_service.is_over() and guard < 20:
			GameManager.combat_service.player_attack("")
			guard += 1
		results.append(GameManager.combat_service.get_result())
	expect(results[0] == results[1] and results[0] == CombatEnums.CombatResult.VICTORY,
		"零随机分支下双跑结果应一致且胜利")
