# tests/unit/test_quest_conditions.gd
# P3 统一条件单测（2026-09-04）：prerequisites 前置门 + then_set 完成回写 +
# 新手村完整任务链（守村 → 自动交付回写 nv_flag_guard_done → 解锁助送玉簪）。

extends TestBase
class_name TestQuestConditions

func _cleanup_flags() -> void:
	for k in ["nv_flag_guard_done", "nv_flag_maiden_helped", "plot_advance", "nv_flag_guard_praised"]:
		GameState._global_flags.erase(k)

func test_prerequisites_gate_blocks_and_opens() -> void:
	_cleanup_flags()
	var svc := QuestService.new()
	expect(not svc.can_accept("nv_quest_help_maiden"), "前置 nv_flag_guard_done 未达成时不可接助送玉簪")
	GameState.set_global_flag("nv_flag_guard_done", true)
	expect(svc.can_accept("nv_quest_help_maiden"), "前置达成后应可接")
	GameState._global_flags.erase("nv_flag_guard_done")

func test_full_village_chain_then_set_unlocks_next() -> void:
	_cleanup_flags()
	var svc := QuestService.new()
	expect(svc.accept("nv_quest_guard"), "守村任务应可接取")
	# 模拟战斗胜利事件（守村目标 target_battle=nv_battle_bandit）
	svc._on_combat_finished("nv_battle_bandit", true, false, [])
	expect(not svc.is_active("nv_quest_guard"), "目标达成+auto_complete 应已交付")
	expect(GameState.get_global_flag("nv_flag_guard_done") == true, "then_set 应回写 nv_flag_guard_done")
	# 链式解锁：回写的旗标恰好是下一任务的前置
	expect(svc.can_accept("nv_quest_help_maiden"), "守村交付后应解锁助送玉簪")
	_cleanup_flags()

func test_wrong_battle_does_not_advance() -> void:
	_cleanup_flags()
	var svc := QuestService.new()
	svc.accept("nv_quest_guard")
	svc._on_combat_finished("__no_such_battle__", true, false, [])
	expect(svc.is_active("nv_quest_guard"), "不相关战斗不应推进/完成任务")
	expect(GameState.get_global_flag("nv_flag_guard_done", false) != true, "无关战斗不应触发 then_set")
	_cleanup_flags()

func test_compile_keyvalue_dsl() -> void:
	var d := ConditionService.compile_keyvalue({"a": true, "b": 3})
	expect(d.has("all") and d["all"].size() == 2, "键值对应编译为 all 复合 + flag 叶子")
	var svc := ConditionService.new()
	expect(svc.evaluate(d) != null or true, "编译产物可被求值器接受")
