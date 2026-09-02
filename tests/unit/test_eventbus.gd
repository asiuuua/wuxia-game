# tests/unit/test_eventbus.gd
# GATE2 扩展：跨模块信号"接缝契约"静态集成测试（防静默接缝 BUG）
#
# 背景（用户踩过的真实坑，零报错但功能坏）：
#   EventBus 是全局唯一跨模块通道。若某信号被【删除 / 改名 / 改签名】，所有真实
#   订阅方（UI 面板 / 服务）会静默收不到，功能表面正常、零报错、GATE1 抓不到，
#   只有玩家踩了才知道（最阴的一类静默 BUG）。本测试是全工程唯一守此盲区的点。
#
# 本测试只守一件事（高价值、零副作用）：
#   ① 信号在 EventBus 上【真实声明】（删除 / 改名即 ✗）
#   ② 信号参数个数【与契约一致】（签名漂移即 ✗）
#   上述两点即可抓住"静默接缝"全部三种形态（删除 / 改名 / 改签名）。
#
# 设计铁律 —— 呼应"机器约束绝不能反向卡开发 / 误导其他 AI"（关键）：
#   - 【绝不 emit 任何信号】。EventBus 是单例，一旦 emit 会同步触发全部真实订阅方
#     （UIManager / 战斗 / 任务 / 存档…），既产生误导其他 AI 的防御性报错日志，
#     又会污染单例状态导致后续测试偶发失败（失败指向错误测试 = 越走越偏）。
#     "EventBus 单例是否活着 / emit 能否抵达"由 GATE2 其余几十个测试间接覆盖
#     （单例崩溃则整包测试必崩），无需本测试再 emit 验证。
#   - 【✗ 文案自带指引】：一旦某接缝 ✗，文案会明确写"若信号签名确有意为之，
#     请修改本测试的 SEAMS 表，而非改游戏逻辑"。这样未来任何 AI 看到 ✗ 都不会
#     误读成游戏 BUG、不会去动战斗 / 背包 / 结缘等真实代码。
#   - 不重复：背包满溢出的【真实生产者驱动】已由 test_inventory_service 覆盖，
#     本测试只补"契约层"，二者正交。
#
# 运行：作为 run_all.tscn 自动收录项，随双闸门 GATE2 一起跑。

extends TestBase
class_name TestEventBus

# —— 接缝契约表：[信号名, 期望参数个数] —— 全工程跨模块信号契约的唯一登记处。
# 若某信号确有意为之要改名 / 改签名，请同步改这里（并改真实订阅方），不要动游戏逻辑。
const SEAMS: Array = [
	["inventory_item_added", 2],	["inventory_item_removed", 2],	["inventory_weight_changed", 2],	["item_used", 2],	["item_used_in_battle", 2],	["combat_started", 1],	["combat_ended", 2],	["combat_character_died", 1],	["grid_highlight_update", 1],	["grid_unit_moved", 3],	["combat_finished", 4],	["quest_failed", 2],	["unit_downed", 2],	["notify_difficulty_changed", 1],	["notify_player_party_wiped_out", 0],	["notify_escape_success", 0],	["notify_defeat_cg", 1],	["ability_learned", 1],	["ability_used", 2],	["combat_skill_equipped", 2],	["equipment_equipped", 2],	["equipment_unequipped", 2],	["equipment_changed", 0],	["alchemy_refined", 3],	["alchemy_failed", 2],	["notify_forge_completed", 3],	["notify_forge_failed", 2],	["notify_trade_completed", 4],	["notify_trade_failed", 3],	["notify_sect_joined", 1],	["notify_sect_reputation_changed", 2],	["notify_sect_rank_up", 2],	["notify_sect_join_failed", 2],	["quest_accepted", 1],	["quest_objective_updated", 3],	["quest_objective_completed", 2],	["quest_completed", 1],	["quest_ready_to_turn_in", 1],	["quest_turned_in", 1],	["quest_phase_changed", 1],	["player_level_up", 1],	["player_exp_changed", 2],	["player_hp_changed", 2],	["player_mp_changed", 2],	["player_stats_changed", 0],	["player_died", 0],	["player_money_changed", 3],	["dialogue_started", 2],	["dialogue_ended", 1],	["dialogue_event_triggered", 1],	["notification_show", 1],	["patch_applied", 2],	["config_validation_failed", 1],	["ui_screen_opened", 1],	["ui_screen_closed", 1],	["world_day_advanced", 1],	["world_weather_changed", 1],	["world_time_changed", 4],	["bond_affection_changed", 3],	["bond_affection_level_up", 2],	["bond_affection_event_triggered", 2],	["bond_gift_given", 4],	["bond_gift_disliked", 2],	["bond_romance_formed", 2],	["bond_romance_stage_changed", 2],	["bond_relationship_changed", 0],	["bond_child_born", 2],	["bond_sworn_formed", 2],	["bond_master_set", 2],	["bond_apprentice_taken", 1],	["bond_wedding_started", 3],	["celebration_started", 2],	["bond_special_portrait_unlocked", 2],	["notify_quest_track_changed", 0],	["notify_skill_bar_changed", 0],	["notify_skill_cd_update", 2],	["cmd_start_combat", 2],	["cmd_set_unit_faction", 2],	["cmd_apply_story_buff", 2],	["cmd_set_difficulty", 2],	["cmd_forge", 2],	["cmd_buy", 3],	["cmd_sell", 3],	["cmd_join_sect", 1],	["cmd_contribute_sect", 2],	["inventory_add_overflow", 2],	["game_started", 0],	["game_saved", 1],	["game_loaded", 1],	["scene_changed", 1],	["bootstrap_started", 1],	["bootstrap_step_started", 2],	["bootstrap_step_completed", 2],	["bootstrap_completed", 0],	["game_error", 3],	["ui_action_requested", 1],	["config_loaded", 1],]

func test_eventbus_singleton_alive() -> void:
	# EventBus 单例必须可用（autoload 崩溃 = 全工程跨模块通信死透；若 null 后续断言无意义）
	expect(EventBus != null, "前置：EventBus 单例应已加载（autoload 未崩溃）；若为 null 说明 autoload 装配问题，与本测试无关")


func test_signal_seams_contract() -> void:
	# 纯契约校验：只查"声明存在 + 参数个数一致"，绝不 emit（零副作用、零噪音、零状态污染）。
	expect(EventBus != null, "前置：EventBus 单例可用")
	if EventBus == null:
		return
	var checked := 0
	for entry in SEAMS:
		var name: String = String(entry[0])
		var want_arity: int = int(entry[1])
		expect(EventBus.has_signal(name),
			"信号契约缺失/改名: %s 应在 EventBus 声明。若确有意为之，请改本测试 SEAMS 表，勿改游戏逻辑" % name)
		if not EventBus.has_signal(name):
			continue
		var got := -1
		for s in EventBus.get_signal_list():
			if String(s.get("name", "")) == name:
				got = s.get("args", []).size()
				break
		expect_eq(got, want_arity,
			"信号契约漂移: %s 参数个数应为 %d（实际 %d）。若签名确有意为之，请改本测试 SEAMS 表，勿改游戏逻辑" % [name, want_arity, got])
		checked += 1
	expect(checked == SEAMS.size(), "应覆盖全部 %d 个接缝契约，实际 %d" % [SEAMS.size(), checked])
