# tests/unit/test_dialogue_inline_effects.gd
# P2 区域分片协议单测（2026-09-04）：验证行内 effects 命令
# （set_flag / quest_accept / 未知命令安全降级）与区域分片完整链路。

extends TestBase
class_name TestDialogueInlineEffects

const FLAG_A := "__p2_test_flag_a__"
const FLAG_B := "__p2_test_flag_b__"

func test_apply_inline_set_flag_kv() -> void:
	var ex := DialogueEventExecutor.new()
	ex.apply_inline("set_flag:" + FLAG_A + "=1")
	expect(GameState.has_global_flag(FLAG_A), "set_flag:键=值 应写入 GameState 全局 flag")
	expect(String(GameState.get_global_flag(FLAG_A)) == "1", "flag 值应为 '1'")
	GameState._global_flags.erase(FLAG_A)   # 清理测试痕迹

func test_apply_inline_set_flag_default_true() -> void:
	var ex := DialogueEventExecutor.new()
	ex.apply_inline("set_flag:" + FLAG_B)
	expect(GameState.has_global_flag(FLAG_B), "set_flag:键 无等号时默认 true")
	expect(GameState.get_global_flag(FLAG_B) == true, "flag 默认值应为 true")
	GameState._global_flags.erase(FLAG_B)

func test_apply_inline_unknown_command_no_crash() -> void:
	var ex := DialogueEventExecutor.new()
	ex.apply_inline("")
	ex.apply_inline("__no_such_cmd__:arg")
	expect(true, "空命令/未知命令应安全降级不崩")

func test_region_maiden_option_effects_apply() -> void:
	# 完整链路：区域分片(新协议) → start 渲染 → select_option 执行选项 effects
	if GameManager == null or GameManager.quest_service == null:
		expect(false, "GameManager.quest_service 不可用")
		return
	var svc := DialogueService.new()
	var first: Dictionary = svc.start("nv_npc_maiden")
	expect(not bool(first.get("ended", true)), "nv_dialog_maiden 应能开场（区域分片新协议可被解释）")
	expect(int(first.get("options", []).size()) == 2, "首行应渲染 2 个选项")
	var r: Dictionary = svc.select_option("opt_help")
	expect(not bool(r.get("ended", true)), "选 opt_help 后应跳转到后续台词而非结束")
	expect(GameManager.quest_service.is_active("nv_quest_guard"), "选项 effects 的 quest_accept 应已接取 nv_quest_guard")
	expect(GameState.has_global_flag("nv_flag_offer_help"), "选项 effects 的 set_flag 应写入 nv_flag_offer_help")
	GameState._global_flags.erase("nv_flag_offer_help")

func test_region_elder_line_effects_apply_on_start() -> void:
	# 行级 effects：开场渲染该行时即执行（nv_dialog_elder → set_flag:nv_flag_guard_praised）
	var svc := DialogueService.new()
	var first: Dictionary = svc.start("nv_npc_elder")
	expect(not bool(first.get("ended", true)), "nv_dialog_elder 应能开场")
	expect(GameState.has_global_flag("nv_flag_guard_praised"), "行 effects 的 set_flag 应在渲染时写入")
	GameState._global_flags.erase("nv_flag_guard_praised")

func test_region_priest_chain_and_end() -> void:
	# 跨区域分片：misty_town 的 mt_dialog_priest 选项接任务 → 跳转行 → 继续到无 next_id 自然结束
	if GameManager == null or GameManager.quest_service == null:
		expect(false, "GameManager.quest_service 不可用")
		return
	var svc := DialogueService.new()
	var first: Dictionary = svc.start("mt_npc_priest")
	expect(not bool(first.get("ended", true)), "mt_dialog_priest 应能开场")
	var picked: Dictionary = svc.select_option("opt_accept")
	expect(GameManager.quest_service.is_active("mt_quest_deliver"), "mt_quest_deliver 应被接取")
	var last: Dictionary = svc.next()   # opt_accept 无 next_id → 自然结束
	expect(bool(last.get("ended", true)), "末行继续应自然结束会话")
