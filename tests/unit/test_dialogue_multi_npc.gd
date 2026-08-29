# tests/unit/test_dialogue_multi_npc.gd
# P3 多 NPC 剧情隔离单测：会话状态隔离 / 条件预检缓存去重 / 对话-NPC 绑定归属

extends TestBase
class_name TestDialogueMultiNpc

func test_session_isolation_repeated_start() -> void:
	var svc := DialogueService.new()
	svc.start("npc_merchant", "")        # 2 行对话
	expect(svc.get_npc_id() == "npc_merchant", "首会话应归属 npc_merchant")
	svc.start("demo_npc", "")            # 未结束直接开第二段（多 NPC 连续/并发场景）
	expect(svc.get_npc_id() == "demo_npc", "二次 start 应干净切换到 demo_npc（状态隔离，不串味）")
	expect(svc.get_dialog_id() == "demo_npc", "二次 start 的 dialog_id 应为 demo_npc")
	svc.end()
	expect(not svc.is_active(), "end 后会话应结束")

func test_condition_cache_dedups_keys() -> void:
	var svc := DialogueService.new()
	svc._check_condition({"kind": "quest_active", "arg": "q1"})
	svc._check_condition({"kind": "quest_active", "arg": "q1"})   # 同 key，应命中缓存不新增
	expect_eq(svc.get_condition_cache_size(), 1, "相同 cond 只应缓存 1 条")
	svc._check_condition({"kind": "quest_active", "arg": "q2"})   # 不同 arg，新 key
	expect_eq(svc.get_condition_cache_size(), 2, "不同 arg 应新增缓存条目")
	svc.clear_condition_cache()
	expect_eq(svc.get_condition_cache_size(), 0, "clear_condition_cache 后应清空")

func test_condition_eval_safe() -> void:
	var svc := DialogueService.new()
	expect(svc._check_condition(null) == true, "null cond 应恒真")
	expect(svc._check_condition({}) == true, "空 dict cond 应恒真")
	expect(svc._check_condition("not_a_dict") == true, "非 dict cond 应恒真")
	expect(svc._check_condition({"kind": "unknown_kind"}) == true, "未知 kind 应恒真（安全降级）")
	# quest_active 在单测环境应返回 bool 而不崩（服务未就绪则判否）
	var r := svc._check_condition({"kind": "quest_active", "arg": "demo_quest"})
	expect(r == false or r == true, "quest_active 求值应返回 bool 不崩")

func test_get_dialog_npc_id() -> void:
	expect(ConfigManager.get_dialog_npc_id("npc_merchant") == "npc_merchant", "npc_merchant 对话应绑定 npc_merchant")
	expect(ConfigManager.get_dialog_npc_id("dlg_tutorial") == "", "dlg_tutorial 未绑定 NPC 应返回空串")
	expect(ConfigManager.get_dialog_npc_id("not_exist_dialog_xyz") == "", "不存在对话应返回空串")
