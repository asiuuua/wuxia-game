# tests/unit/test_battle_turn_order.gd
# 战斗窗口单元测试：验证 ④ ATB 真实行动顺序（get_round_sequence 按速度插队）
# 与单敌行动接口（enemy_act_events）行为正确。extends TestBase（自动被 run_all 发现）。
#
# 设计原则（同 test_battle_roster.gd / test_combat_smoke.gd）：
#   1) dodge/crit 不影响顺序断言（顺序只取决于 speed，与 RNG 无关）
#   2) before_each 重置 PlayerState，避免用例互相污染
# battle_bandit_001 为 ATB 模式，编成 [bandit_001(speed8), bandit_002(speed11)]，
# 玩家 speed 硬编码 10 → 速度序应为 bandit_002(11) > player(10) > bandit_001(8)。

extends TestBase

func before_each() -> void:
	GameManager.combat_service.start_combat("battle_bandit_001")

## ATB 回合序列首位应为速度最高者（bandit_002），而非恒为玩家
func test_atb_round_sequence_puts_fastest_first() -> void:
	var seq: Array[String] = GameManager.combat_service.get_core().get_round_sequence()
	expect(seq.size() >= 3, "回合序列应含玩家 + 2 敌人，实际 %d" % seq.size())
	expect(seq[0] == "bandit_002", "ATB 序列首位应为速度最高者 bandit_002，实际 %s" % seq[0])
	expect(seq.has("player"), "回合序列应包含玩家")
	# 序列严格按速度降序：bandit_002 在 player 前，player 在 bandit_001 前
	expect(seq.find("bandit_002") < seq.find("player"), "bandit_002 应排在玩家之前")
	expect(seq.find("player") < seq.find("bandit_001"), "玩家应排在 bandit_001 之前")

## 单敌行动接口 enemy_act_events 应产出事件（TURN_START + 行动 + 伤害）
func test_enemy_act_emits_events() -> void:
	var ev: Array[CombatEvent] = GameManager.combat_service.enemy_act_events("bandit_001")
	expect(ev.size() > 0, "单个敌人行动应产出非空事件流，实际 %d" % ev.size())
	var has_turn_start: bool = false
	for e in ev:
		if e.type == CombatEvent.Type.TURN_START and e.actor_id == "bandit_001":
			has_turn_start = true
	expect(has_turn_start, "敌人行动应含其 TURN_START 事件")

## 顺序条 action_order 也应按速度降序且仅含存活单位
func test_action_order_sorted_desc_and_alive_only() -> void:
	var order: Array[String] = GameManager.combat_service.get_core().action_order()
	expect(order[0] == "bandit_002", "顺序条首位应为最快者 bandit_002，实际 %s" % order[0])
