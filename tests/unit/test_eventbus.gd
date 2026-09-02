# tests/unit/test_eventbus.gd
# GATE2 扩展：跨模块信号"接缝契约 + 发→收集成测试"
#
# 背景（用户踩过的"静默接缝 BUG"真实坑，零报错但功能坏）：
#   - EventBus 是全局唯一跨模块通道。若某信号被【删除/改名/改签名】，所有真实
#     订阅方（UI 面板 / 服务）会静默收不到，功能表面正常、零报错、GATE1 抓不到，
#     只有玩家踩了才知道（最阴的一类）。
#   - 例：背包溢出事件 inventory_add_overflow 若被改名，UIManager 的提示永远不弹；
#        player_hp_changed 若被改签名，血条面板不再刷新——都是"看起来没事其实坏了"。
#
# 本测试守两件事（全工程唯一覆盖此盲区）：
#   ① 信号在 EventBus 上【真实声明】（删除/改名即 ✗）
#   ② 信号参数个数【与契约一致】（签名漂移即 ✗）
#   ③ 对"通知/状态类"接缝，额外验证 emit 同步【抵达】订阅方（EventBus 机制未死；
#      若 autoload 崩溃，EventBus 为 null → 整类在 GATE2 报错，比"功能悄悄没反应"早暴露）
#
# 设计铁律（呼应"机器约束不能反向卡开发"）：
#   - 零副作用（重要）：run_all.tscn 为无头测试场，UIManager/GameManager/SaveManager 等
#     真实 autoload 订阅方【确实已加载并连接】。因此对"会触发真实动作的指令/流程类"信号
#     （cmd_* / game_saved / game_started / bootstrap_* / scene_changed / ui_action_requested /
#     game_error 等）【只做契约校验、不真实 emit】，避免：① 触发真实业务（如存档写入
#     user://、开启战斗）② 触发真实订阅方对合成载荷的防御性报错日志（误导其他 AI 窗口）。
#     "通知/状态类"信号（inventory_* / player_* / quest_* / notify_* / combat_* 等）emit 仅让
#     真实 UI 面板做无害刷新，无业务副作用，可安全做发→收验证。
#   - 不重复：真实生产者驱动（如背包满溢出）已由 test_inventory_service 覆盖，
#     本测试只补"契约 + 发→收"这一层，二者正交。
#
# 运行：作为 run_all.tscn 自动收录项，随双闸门 GATE2 一起跑。

extends TestBase
class_name TestEventBus

# —— 发→收验证接缝：[信号名, 期望参数个数, [示例载荷...]] ——
# 仅含"通知/状态类"（emit 仅驱动 UI 无害刷新，无业务副作用）。
const EMIT_SEAMS: Array = [
	# 背包模块
	["inventory_item_added", 2, ["item_x", 1]],
	["inventory_item_removed", 2, ["item_x", 1]],
	["inventory_weight_changed", 2, [10.0, 50.0]],
	["item_used", 2, ["item_x", {}]],
	["item_used_in_battle", 2, ["item_x", {}]],
	# 战斗 / 战术
	["combat_started", 1, ["c_001"]],
	["combat_ended", 2, ["c_001", 0]],
	["combat_character_died", 1, ["u_001"]],
	["grid_highlight_update", 1, [{}]],
	["grid_unit_moved", 3, ["u_001", Vector2i.ZERO, Vector2i.ZERO]],
	["combat_finished", 4, ["c_001", false, false, []]],
	["quest_failed", 2, ["q_001", "reason"]],
	["unit_downed", 2, ["u_001", false]],
	# 难度
	["notify_difficulty_changed", 1, ["NORMAL"]],
	["notify_player_party_wiped_out", 0, []],
	["notify_escape_success", 0, []],
	["notify_defeat_cg", 1, ["text_001"]],
	# 武学 / 装备
	["ability_learned", 1, ["ab_001"]],
	["ability_used", 2, ["ab_001", "u_001"]],
	["combat_skill_equipped", 2, ["ab_001", 0]],
	["equipment_equipped", 2, ["slot_001", "item_001"]],
	["equipment_unequipped", 2, ["slot_001", "item_001"]],
	["equipment_changed", 0, []],
	# 炼药 / 锻造 / 商店 / 门派 的"通知"类
	["alchemy_refined", 3, ["r_001", "o_001", 1]],
	["alchemy_failed", 2, ["r_001", "reason"]],
	["notify_forge_completed", 3, ["r_001", "o_001", 1]],
	["notify_forge_failed", 2, ["r_001", "reason"]],
	["notify_trade_completed", 4, ["shop_001", "item_001", 1, true]],
	["notify_trade_failed", 3, ["shop_001", "item_001", "reason"]],
	["notify_sect_joined", 1, ["sect_001"]],
	["notify_sect_reputation_changed", 2, ["sect_001", 1]],
	["notify_sect_rank_up", 2, ["sect_001", 1]],
	["notify_sect_join_failed", 2, ["sect_001", "reason"]],
	# 任务
	["quest_accepted", 1, ["q_001"]],
	["quest_objective_updated", 3, ["q_001", "o_001", 1]],
	["quest_objective_completed", 2, ["q_001", "o_001"]],
	["quest_completed", 1, ["q_001"]],
	["quest_ready_to_turn_in", 1, ["q_001"]],
	["quest_turned_in", 1, ["q_001"]],
	["quest_phase_changed", 1, [1]],
	# 玩家（血条/经验/金钱 等高敏感接缝）
	["player_level_up", 1, [9]],
	["player_exp_changed", 2, [10, 100]],
	["player_hp_changed", 2, [100, 120]],
	["player_mp_changed", 2, [50, 80]],
	["player_stats_changed", 0, []],
	["player_died", 0, []],
	["player_money_changed", 3, [1, 2, 3]],
	# 对话 / 流程通知
	["dialogue_started", 2, ["d_001", "npc_001"]],
	["dialogue_ended", 1, ["d_001"]],
	["dialogue_event_triggered", 1, ["e_001"]],
	["notification_show", 1, ["text_001"]],
	["patch_applied", 2, ["p_001", "v_001"]],
	["config_validation_failed", 1, [[]]],
	# UI 通知
	["ui_screen_opened", 1, ["bag"]],
	["ui_screen_closed", 1, ["bag"]],
	# 世界环境
	["world_day_advanced", 1, [5]],
	["world_weather_changed", 1, [1]],
	["world_time_changed", 4, [1, 12.0, 1, 1]],
	# 结缘 / 姻缘 / 欢庆
	["bond_affection_changed", 3, ["npc_001", 10, 1]],
	["bond_affection_level_up", 2, ["npc_001", 1]],
	["bond_affection_event_triggered", 2, ["npc_001", "e_001"]],
	["bond_gift_given", 4, ["npc_001", "item_001", 1, 1]],
	["bond_gift_disliked", 2, ["npc_001", "item_001"]],
	["bond_romance_formed", 2, ["npc_001", 1]],
	["bond_romance_stage_changed", 2, ["npc_001", 1]],
	["bond_relationship_changed", 0, []],
	["bond_child_born", 2, ["npc_001", "child_001"]],
	["bond_sworn_formed", 2, ["npc_001", 1]],
	["bond_master_set", 2, ["npc_001", 1]],
	["bond_apprentice_taken", 1, ["npc_001"]],
	["bond_wedding_started", 3, ["npc_001", 1, "scene_001"]],
	["celebration_started", 2, ["npc_001", "cg_001"]],
	["bond_special_portrait_unlocked", 2, ["npc_001", 1]],
	# HUD 常驻（v2 四面板接缝）
	["notify_quest_track_changed", 0, []],
	["notify_skill_bar_changed", 0, []],
	["notify_skill_cd_update", 2, ["skill_001", 1.0]],
]

# —— 仅契约校验接缝：[信号名, 期望参数个数] ——
# 这些是"指令/流程类"信号：真实订阅方会据此【触发真实业务动作】
# （开启战斗 / 写存档 / 启动引导 / 切场景 / 路由菜单 / 记错误日志），
# 若合成 emit 会污染 user:// 或产生误导其他 AI 的防御性报错日志。
# 故只校验"声明存在 + 参数个数一致"（删除/改名/改签名即 ✗），不真实 emit。
const CONTRACT_ONLY: Array = [
	["cmd_start_combat", 2],
	["cmd_set_unit_faction", 2],
	["cmd_apply_story_buff", 2],
	["cmd_set_difficulty", 2],
	["cmd_forge", 2],
	["cmd_buy", 3],
	["cmd_sell", 3],
	["cmd_join_sect", 1],
	["cmd_contribute_sect", 2],
	["inventory_add_overflow", 2],
	["game_started", 0],
	["game_saved", 1],
	["game_loaded", 1],
	["scene_changed", 1],
	["bootstrap_started", 1],
	["bootstrap_step_started", 2],
	["bootstrap_step_completed", 2],
	["bootstrap_completed", 0],
	["game_error", 3],
	["ui_action_requested", 1],
	["config_loaded", 1],
]

var _hits: Array[String] = []
var _cur: String = ""

# 按 arity 分发的私有 spy：只记录"当前信号名"，证明 emit 抵达
func _spy0() -> void:
	_hits.append(_cur)

func _spy1(_a) -> void:
	_hits.append(_cur)

func _spy2(_a, _b) -> void:
	_hits.append(_cur)

func _spy3(_a, _b, _c) -> void:
	_hits.append(_cur)

func _spy4(_a, _b, _c, _d) -> void:
	_hits.append(_cur)

func _spy_for(arity: int) -> Callable:
	match arity:
		0: return Callable(self, "_spy0")
		1: return Callable(self, "_spy1")
		2: return Callable(self, "_spy2")
		3: return Callable(self, "_spy3")
		_: return Callable(self, "_spy4")

func _arity_of(name: String) -> int:
	for s in EventBus.get_signal_list():
		if String(s.get("name", "")) == name:
			var args: Array = s.get("args", [])
			return args.size()
	return -1

func test_eventbus_singleton_alive() -> void:
	# EventBus 单例必须可用（autoload 崩溃 = 全工程跨模块通信死透）
	expect(EventBus != null, "EventBus 单例应已加载（autoload 未崩溃）")

func test_signal_seams_contract_and_delivery() -> void:
	expect(EventBus != null, "前置：EventBus 单例可用")
	if EventBus == null:
		return

	# ① 发→收接缝：声明存在 + arity 正确 + emit 同步抵达
	var emit_checked := 0
	for entry in EMIT_SEAMS:
		var name: String = String(entry[0])
		var want_arity: int = int(entry[1])
		var payload: Array = entry[2]
		expect(EventBus.has_signal(name), "信号应已声明: %s" % name)
		if not EventBus.has_signal(name):
			continue
		expect_eq(_arity_of(name), want_arity, "信号参数个数应一致: %s" % name)
		var spy: Callable = _spy_for(want_arity)
		_hits.clear()
		_cur = name
		EventBus.connect(name, spy)
		match want_arity:
			0: EventBus.emit_signal(name)
			1: EventBus.emit_signal(name, payload[0])
			2: EventBus.emit_signal(name, payload[0], payload[1])
			3: EventBus.emit_signal(name, payload[0], payload[1], payload[2])
			_: EventBus.emit_signal(name, payload[0], payload[1], payload[2], payload[3])
		EventBus.disconnect(name, spy)
		expect(_hits.has(name), "emit 应同步抵达订阅方（无丢失）: %s" % name)
		emit_checked += 1
	expect(emit_checked == EMIT_SEAMS.size(), "应覆盖全部 %d 个发→收接缝，实际 %d" % [EMIT_SEAMS.size(), emit_checked])

	# ② 仅契约接缝：声明存在 + arity 正确（不 emit，避免触发真实业务）
	var contract_checked := 0
	for entry in CONTRACT_ONLY:
		var name: String = String(entry[0])
		var want_arity: int = int(entry[1])
		expect(EventBus.has_signal(name), "信号应已声明: %s" % name)
		if not EventBus.has_signal(name):
			continue
		expect_eq(_arity_of(name), want_arity, "信号参数个数应一致: %s" % name)
		contract_checked += 1
	expect(contract_checked == CONTRACT_ONLY.size(), "应覆盖全部 %d 个契约接缝，实际 %d" % [CONTRACT_ONLY.size(), contract_checked])
