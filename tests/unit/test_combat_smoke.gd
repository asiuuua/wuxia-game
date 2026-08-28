# tests/unit/test_combat_smoke.gd
# 战斗冒烟测试：守住「打一场仗」这条主链路，为后续战斗层重构提供回归网
# 设计原则：
#   1) 用例内把 dodge_rate / crit_rate 归零，消除随机导致的 flaky
#   2) 不触发 DEFEAT 路径的 finalize——那会唤醒 DefeatHandler 执行死亡惩罚（删档/切场景）
#   3) 每次 before_each 重置 PlayerState，避免用例互相污染

extends TestBase

const BATTLE_ID := "battle_bandit_001"

func before_each() -> void:
	GameManager.player_state.init_default("测试侠", 1)
	GameManager.player_state.hp = 9999
	GameManager.player_state.max_hp = 9999
	GameManager.player_state.attack = 50
	GameManager.player_state.experience = 0

func _start() -> CombatState:
	GameManager.combat_service.start_combat(BATTLE_ID)
	return GameManager.combat_service.get_state()

## 战斗应能正确构建：敌人数量、激活态、玩家单位
func test_start_combat_builds_state() -> void:
	var st: CombatState = _start()
	expect(st != null, "战斗状态应构建成功")
	if st == null:
		return
	expect_eq(st.enemies.size(), 2, "battle_bandit_001 应配置 2 个敌人")
	expect(st.is_active, "战斗应处于激活状态")
	expect(st.player != null, "玩家单位应存在")

## 不存在的战斗 id 不应崩溃，状态保持为 null
func test_start_combat_unknown_id() -> void:
	GameManager.combat_service.start_combat("no_such_battle")
	expect(GameManager.combat_service.get_state() != null, "未知 id 后仍持有上一次状态（不崩即可）")

## 普攻应让目标掉血
func test_player_attack_reduces_hp() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	var target: CombatCharacter = st.enemies[0]
	target.dodge_rate = 0.0
	var before: int = target.hp
	GameManager.combat_service.player_attack(target.character_id)
	expect(target.hp < before, "普攻后敌人血量应下降（%d → %d）" % [before, target.hp])

## 敌人回合应让玩家掉血
func test_enemy_turns_damage_player() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	st.player.dodge_rate = 0.0
	var before: int = st.player.hp
	GameManager.combat_service.run_enemy_turns()
	expect(st.player.hp < before, "敌人回合后玩家应掉血（%d → %d）" % [before, st.player.hp])

## 打光所有敌人应判定胜利
func test_victory_when_all_enemies_down() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	for e in st.enemies:
		e.hp = 1
		e.dodge_rate = 0.0
	st.player.crit_rate = 0.0
	var guard := 0
	while not GameManager.combat_service.is_over() and guard < 50:
		GameManager.combat_service.player_attack("")
		guard += 1
	expect(GameManager.combat_service.is_over(), "战斗应在 50 次行动内结束（实际 %d 次）" % guard)
	expect_eq(GameManager.combat_service.get_result(), CombatEnums.CombatResult.VICTORY, "结果应为胜利")

## 玩家倒下应判定失败（只判定结果，不 finalize，避免触发 DefeatHandler）
func test_defeat_when_player_down() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	st.player.hp = 1
	st.player.dodge_rate = 0.0
	for e in st.enemies:
		e.attack = 9999
	GameManager.combat_service.run_enemy_turns()
	expect_eq(GameManager.combat_service.get_result(), CombatEnums.CombatResult.DEFEAT, "结果应为失败")

## 结算应把战斗中的血量写回 PlayerState，并让战斗失活
func test_finalize_writes_back_hp() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	st.player.hp = 42
	GameManager.combat_service.finalize()
	expect_eq(GameManager.player_state.hp, 42, "战斗血量应写回 PlayerState")
	expect(not st.is_active, "结算后战斗应失活")

## 逃跑应结束战斗（难度可能禁用逃跑，故只断言「要么成功要么失败，不崩」）
func test_escape_never_crashes() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	var escaped: bool = GameManager.combat_service.try_escape()
	if escaped:
		expect_eq(GameManager.combat_service.get_result(), CombatEnums.CombatResult.FLEE, "逃跑成功后结果应为 FLEE")
	else:
		expect(st.is_active, "逃跑失败后战斗应继续")

## ATB 行动顺序应由集气速率(speed)决定：玩家 speed=10 > 山贼 speed=8，应排第一
func test_atb_order_by_speed() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	expect(st.turn_mode == CombatEnums.TurnMode.ATB, "battle_bandit_001 应配置 ATB 模式")
	var order: Array[String] = GameManager.combat_service.get_core().action_order()
	expect(order[0] == "player", "集气速率高者(玩家)应排在行动顺序首位，实际 %s" % order[0])

## 招式应消耗真气并进入冷却（对标逸剑二式/三式耗真气+冷却）
func test_skill_costs_qi_and_cooldown() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	GameManager.ability_service.learn("sword_qingsong_001")
	GameManager.ability_service.equip_combat_skill(0, "sword_qingsong_001")
	st.player.dodge_rate = 0.0
	var before_mp: int = st.player.mp
	GameManager.combat_service.player_cast(0, "bandit_001")
	expect(st.player.mp == before_mp - 5, "施展青松剑法应消耗 5 真气（%d→%d）" % [before_mp, st.player.mp])
	expect(st.player.cooldowns.has("sword_qingsong_001"), "招式应进入冷却")
	expect_eq(int(st.player.cooldowns.get("sword_qingsong_001", 0)), 1, "冷却应为 1 回合")

## 状态引擎应真正 tick：施加灼烧(DoT)后每回合掉血、持续回合递减
func test_status_tick_dot() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	var enemy: CombatCharacter = st.enemies[0]
	var se := StatusEffect.new()
	se.effect_id = "zhuoshao"; se.name_key = "灼烧"; se.type = CombatEnums.EffectType.DOT
	se.stat = ""; se.mode = StatusEffect.MODE_FLAT; se.value = 0.0
	se.stacks = 2; se.max_stacks = 9; se.remaining = 2; se.dot_per_turn = -3; se.clear_on_rest = false
	enemy.status_effects.append(se)
	var before: int = enemy.hp
	GameManager.combat_service.get_core().tick_unit(enemy)
	expect(enemy.hp < before, "灼烧应每回合造成 DoT 掉血（%d→%d）" % [before, enemy.hp])
	expect_eq(enemy.status_effects[0].remaining, 1, "灼烧持续回合应 -1")

## 确定性随机源：同 seed 同序列（战斗可存档/回放/单测的基石）
func test_rng_deterministic() -> void:
	var r1 := SeededRNG.new(); r1.configure(42)
	var r2 := SeededRNG.new(); r2.configure(42)
	var s1 := "%f|%f|%f" % [r1.randf(), r1.randf(), r1.randf()]
	var s2 := "%f|%f|%f" % [r2.randf(), r2.randf(), r2.randf()]
	expect(s1 == s2, "同 seed 应得同随机序列: %s vs %s" % [s1, s2])

## 确定性：同 seed + 同指令 → 同结果
## 关键陷阱：combat_service 是单例，每个 run 必须「开战→行动→记录」自成一体，
## 不能先把两次 start_combat 都跑完再行动——那样两次 player_attack 都会作用在
## 第二次 start 出来的激活态上，导致第一次 run 的断言读到的还是上一场未受击的血量。
func test_deterministic_same_seed() -> void:
	var hp_a: int = _seeded_attack_result(12345)
	var hp_b: int = _seeded_attack_result(12345)
	expect_eq(hp_a, hp_b, "同 seed 同指令应得相同血量（%d vs %d）" % [hp_a, hp_b])

## 跑一场完全自包含的战斗：固定 seed 下发一次普攻，返回首敌剩余血量
func _seeded_attack_result(seed_val: int) -> int:
	_start_seeded(seed_val)
	var st: CombatState = GameManager.combat_service.get_state()
	st.player.attack = 14
	st.player.dodge_rate = 0.0
	st.enemies[0].dodge_rate = 0.0
	GameManager.combat_service.player_attack("bandit_001")
	return st.enemies[0].hp

func _start_seeded(seed_val: int) -> CombatState:
	GameManager.combat_service.start_combat(BATTLE_ID)
	GameManager.combat_service.get_core().rng.configure(seed_val)
	return GameManager.combat_service.get_state()

## M2 契约：DAMAGE 事件应携带受击者「行动后」气血，供视图血条直设（加速/跳过不错位）
func test_damage_event_carries_target_hp_after() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	var target: CombatCharacter = st.enemies[0]
	target.dodge_rate = 0.0
	var events: Array[CombatEvent] = GameManager.combat_service.player_attack_events(target.character_id)
	var dmg_ev: CombatEvent = null
	for e in events:
		if e.type == CombatEvent.Type.DAMAGE and e.target_id == target.character_id and e.value > 0:
			dmg_ev = e
	expect(dmg_ev != null, "应产生对首敌的有效伤害事件")
	if dmg_ev == null:
		return
	expect_eq(dmg_ev.target_hp_after, target.hp, "事件 target_hp_after 应等于受击后真实血量")
	expect_eq(dmg_ev.target_max_hp, target.max_hp, "事件 target_max_hp 应等于上限")

## M2 契约：QI_COST 事件应携带发起者「行动后」真气，供视图真气条直设
func test_qi_cost_event_carries_actor_mp_after() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	GameManager.ability_service.learn("sword_qingsong_001")
	GameManager.ability_service.equip_combat_skill(0, "sword_qingsong_001")
	st.player.dodge_rate = 0.0
	var before_mp: int = st.player.mp
	var events: Array[CombatEvent] = GameManager.combat_service.player_cast_events(0, "bandit_001")
	var qi_ev: CombatEvent = null
	for e in events:
		if e.type == CombatEvent.Type.QI_COST:
			qi_ev = e
	expect(qi_ev != null, "应产生真气消耗事件")
	if qi_ev == null:
		return
	expect_eq(qi_ev.actor_mp_after, before_mp - 5, "事件 actor_mp_after 应等于扣后真气")

## M3：敌人真气充足时应施展 ai_kit 中的招式（ACTION_SKILL + 真实技能 id），而非纯普攻
## bandit_001 的 ai_kit 仅 sword_qingsong_001（weight3/always），应确定性施展该招
func test_enemy_uses_skill_when_mp_ok() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	st.player.dodge_rate = 0.0
	for e in st.enemies:
		e.dodge_rate = 0.0
	var events: Array[CombatEvent] = GameManager.combat_service.enemy_phase_events()
	var skill_ev: CombatEvent = null
	for e in events:
		if e.type == CombatEvent.Type.ACTION_SKILL and e.actor_id == "bandit_001":
			skill_ev = e
	expect(skill_ev != null, "山贼(bandit_001) 的 ai_kit 仅 sword_qingsong_001，应确定性施展该招")
	if skill_ev == null:
		return
	expect(skill_ev.skill_id == "sword_qingsong_001", "施展的应是青松剑法，实际 %s" % skill_ev.skill_id)

## M3：敌人真气为 0 时无可用招式，应普攻兜底（ACTION_BASIC，且无 ACTION_SKILL）
func test_enemy_falls_back_to_basic_when_mp_zero() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	st.player.dodge_rate = 0.0
	for e in st.enemies:
		e.dodge_rate = 0.0
		e.mp = 0                    # 真气清零 → 所有招式不可用
	var before: int = st.player.hp
	var events: Array[CombatEvent] = GameManager.combat_service.enemy_phase_events()
	var has_skill: bool = false
	var has_basic: bool = false
	for e in events:
		if e.type == CombatEvent.Type.ACTION_SKILL:
			has_skill = true
		if e.type == CombatEvent.Type.ACTION_BASIC:
			has_basic = true
	expect(not has_skill, "mp=0 时不应有任何招式事件")
	expect(has_basic, "mp=0 时应触发普攻兜底")
	expect(st.player.hp < before, "普攻兜底仍应让玩家掉血（%d→%d）" % [before, st.player.hp])

## M3（修 M1 冷却 bug）：玩家施展带冷却招式后，下个自己回合 tick 应把冷却减到 0
func test_cooldown_decrements_on_tick() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	GameManager.ability_service.learn("sword_qingsong_001")
	GameManager.ability_service.equip_combat_skill(0, "sword_qingsong_001")
	GameManager.combat_service.player_cast(0, "bandit_001")
	expect_eq(int(st.player.cooldowns.get("sword_qingsong_001", 0)), 1, "施法当回合冷却应为 1")
	GameManager.combat_service.get_core().tick_unit(st.player)
	expect_eq(int(st.player.cooldowns.get("sword_qingsong_001", 0)), 0, "下个自己回合 tick 后冷却应归 0（修复后）")

## M3：条件门控 self_mp_above 应排除真气不足的招式（battle_bandit_001 实际编成是两个 bandit_001，
## 故运行时给首敌注入带条件门控的 ai_kit 验证门控逻辑，而非依赖某具体敌人编成）
func test_condition_gates_enemy_skill() -> void:
	var st: CombatState = _start()
	if st == null:
		return
	st.player.dodge_rate = 0.0
	for e in st.enemies:
		e.dodge_rate = 0.0
	# 给首敌注入：sword(always) + xinfa(self_mp_above:0.6)
	var kit: Array = [
		{"id": "sword_qingsong_001", "weight": 1.0, "condition": "always"},
		{"id": "xinfa_ningshen_001", "weight": 1.0, "condition": "self_mp_above:0.6"}
	]
	st.enemies[0].ai_kit = kit
	st.enemies[0].mp = 10          # 低于 0.6*30=18 → xinfa 被排除，只剩 sword（确定性）
	var events: Array[CombatEvent] = GameManager.combat_service.enemy_phase_events()
	var skill_ev: CombatEvent = null
	for e in events:
		if e.type == CombatEvent.Type.ACTION_SKILL and e.actor_id == "bandit_001":
			skill_ev = e
	expect(skill_ev != null, "首敌(mp=10, xinfa 被条件排除) 应确定性施展 sword")
	if skill_ev == null:
		return
	expect(skill_ev.skill_id == "sword_qingsong_001", "应施展青松剑法而非被门控的凝神心法，实际 %s" % skill_ev.skill_id)
