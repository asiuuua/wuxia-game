# tests/unit/test_quest_graph.gd
# 任务流程图解释器 QuestGraph 单元测试（继承 TestBase，被 run_all.tscn 收录）
# 覆盖：条件DSL(all/any/not/flag/favor/progress)、choice 分支、副作用、结局判定、成环保护。
# 与 regions/newbie_village/quests.json 的 nv_qg_demo 分支图语义一致。
extends TestBase
class_name TestQuestGraph

var _store: RefCounted = null

func _b(cond: bool) -> int:
	return 1 if cond else 0

func before_each() -> void:
	_store = FlagStore.new(false)   # 内存独立存储，避免污染存档

func _graph() -> Dictionary:
	return {
		"start_node": "n_start",
		"nodes": {
			"n_start": {"type": "start", "then": [{"op": "flag_set", "key": "nv_qg_started", "value": true}], "next": "n_choice"},
			"n_choice": {"type": "choice", "options": [
				{"text_key": "opt_help", "show": {"flag": "nv_flag_maiden_helped", "eq": true},
				 "then": [{"op": "flag_set", "key": "nv_qg_accepted", "value": true}], "next": "n_give"},
				{"text_key": "opt_refuse", "show": {"flag": "nv_flag_maiden_helped", "eq": false},
				 "then": [], "next": "n_end_refuse"}
			]},
			"n_give": {"type": "flag_set", "then": [
				{"op": "favor_add", "target": "npc_village_chief", "value": 15},
				{"op": "flag_set", "key": "nv_qg_rewarded", "value": true}], "next": "n_end_good"},
			"n_end_good": {"type": "end", "ending": "good"},
			"n_end_refuse": {"type": "end", "ending": "neutral"}
		},
		"endings": [
			{"id": "good", "require": {"flag": "nv_qg_accepted", "eq": true}},
			{"id": "neutral", "require": {"flag": "nv_qg_accepted", "eq": false}}
		]
	}

func test_condition_flag_gate() -> void:
	var g := QuestGraph.new()
	expect(g.evaluate_condition({"flag": "a", "eq": true}, _store) == false, "缺失 flag 默认 null，eq true 应为 false")
	_store.set_flag("a", true)
	expect(g.evaluate_condition({"flag": "a", "eq": true}, _store), "flag=true 应通过")
	_store.set_flag("a", "yes")
	expect(_b(g.evaluate_condition({"flag": "a", "eq": "yes"}, _store)), "字符串值比较一致")

func test_condition_all_any_not() -> void:
	var g := QuestGraph.new()
	expect(g.evaluate_condition({"all": [{"flag": "b", "eq": true}, {"flag": "c", "eq": true}]}, _store) == false, "缺一不成立")
	_store.set_flag("b", true)
	_store.set_flag("c", true)
	expect(g.evaluate_condition({"all": [{"flag": "b", "eq": true}, {"flag": "c", "eq": true}]}, _store), "皆具成立")
	expect(g.evaluate_condition({"any": [{"flag": "b", "eq": true}, {"flag": "x", "eq": true}]}, _store), "任一成立")
	expect(g.evaluate_condition({"not": {"flag": "z", "eq": true}}, _store), "not-缺失 flag 通过")

func test_condition_favor_progress() -> void:
	var g := QuestGraph.new()
	expect(g.evaluate_condition({"favor": "npc_liu", "gte": 10}, _store) == false, "好感初始不足")
	_store.add_favor("npc_liu", 20)
	expect(g.evaluate_condition({"favor": "npc_liu", "gte": 10}, _store), "好感足够")
	expect(g.evaluate_condition({"progress": "q_demo", "gte": 2}, _store) == false, "进度不足")
	_store.set_progress("q_demo", 2)
	expect(g.evaluate_condition({"progress": "q_demo", "gte": 2}, _store), "进度达标")

func test_branch_help_good() -> void:
	_store.set_flag("nv_flag_maiden_helped", true)
	var g := QuestGraph.new()
	var r: Dictionary = g.run(_graph(), _store)
	expect(_b(str(r.get("ending", "")) == "good"), "帮过 -> 好结局")
	expect(_b(bool(_store.get_flag("nv_qg_started", false))), "入场 flag 已写入")
	expect(_b(bool(_store.get_flag("nv_qg_accepted", false))), "接受选择已记录")
	expect(_b(bool(_store.get_flag("nv_qg_rewarded", false))), "发奖已记录")
	expect(_b(float(_store.get_favor("npc_village_chief")) > 0.0), "好感已增加")

func test_branch_refuse_neutral() -> void:
	_store.set_flag("nv_flag_maiden_helped", false)
	var g := QuestGraph.new()
	var r: Dictionary = g.run(_graph(), _store)
	expect(_b(str(r.get("ending", "")) == "neutral"), "未帮 -> 中立结局")
	expect(_b(not bool(_store.get_flag("nv_qg_accepted", false))), "未接受选择不记录")
	expect(_b(not bool(_store.get_flag("nv_qg_rewarded", false))), "未发奖")

func test_ending_fallback() -> void:
	var store2: RefCounted = FlagStore.new(false)
	store2.set_flag("nv_qg_accepted", true)
	var g := QuestGraph.new()
	var cfg := {
		"start_node": "n1",
		"nodes": {"n1": {"type": "flag_set", "then": [], "next": ""}},
		"endings": [
			{"id": "good", "require": {"flag": "nv_qg_accepted", "eq": true}},
			{"id": "other", "require": {"flag": "q_unset", "eq": true}}
		]
	}
	var r: Dictionary = g.run(cfg, store2)
	expect(_b(str(r.get("ending", "")) == "good"), "无 end 节点时按 endings 表回退匹配")

func test_loop_guard() -> void:
	var g := QuestGraph.new()
	var cfg := {
		"start_node": "n1",
		"nodes": {
			"n1": {"type": "flag_set", "then": [], "next": "n2"},
			"n2": {"type": "flag_set", "then": [], "next": "n1"}
		},
		"endings": []
	}
	var r: Dictionary = g.run(cfg, FlagStore.new(false))
	expect(_b(r.get("steps", []).size() > 0), "成环图仍能返回不挂起（有步数保护）")
	expect(_b(str(r.get("ending", "")) == ""), "成环无结局")