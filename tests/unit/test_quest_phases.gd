# tests/unit/test_quest_phases.gd
# QD-R07 分相队列机制测试（12 图 Phase2 / P-Q2 回调重入链根治，2026-09-06）：
# 事件回调只入队 → 帧末 _flush_events 统一冲刷；嵌套冲刷保护；P-Q2 链分相复现。

extends TestBase
class_name TestQuestPhases

func _cleanup_flags() -> void:
	for k in ["nv_flag_guard_done", "nv_flag_maiden_helped", "plot_advance"]:
		GameState._global_flags.erase(k)

func after_each() -> void:
	_cleanup_flags()

## 回调只入队不即时推进（分相第一铁律）
func test_callbacks_enqueue_not_advance() -> void:
	var svc := QuestService.new()
	var log: Array = []
	svc.register_objective_handler("battle", func(_s, _o, ev): log.append(str(ev.get("battle_id"))))
	svc.accept("nv_quest_guard")
	svc._on_combat_finished("nv_battle_bandit", true, false, [])
	svc._on_inventory_added("nv_item_hairpin", 1)
	expect(log.is_empty(), "未冲刷前不得有任何目标推进（禁回调内同步重入）")
	expect(svc._event_queue.size() == 2, "两次事件应全部入队（实际 %d）" % svc._event_queue.size())
	svc._flush_events()
	expect(svc._event_queue.is_empty() and not svc._flushing, "冲刷后队列排干、闸门复位")

## 冲刷按 FIFO 路由消费
func test_flush_routes_fifo_and_drains() -> void:
	var svc := QuestService.new()
	var log: Array = []
	var spy := func(_s, _o, ev):
		if ev.has("battle_id"):
			log.append("b:" + str(ev.get("battle_id")))
	svc.register_objective_handler("battle", spy)
	svc.accept("nv_quest_guard")
	svc._on_inventory_added("x", 1)                       # item 事件先入队
	svc._on_combat_finished("nv_battle_bandit", true, false, [])   # battle 事件后入队
	svc._flush_events()
	expect(log == ["b:nv_battle_bandit"], "FIFO 冲刷：item 事件（无 battle 目标匹配物，spy 静默）+ battle 事件按序路由（实际 %s）" % [log])
	expect(svc._event_queue.is_empty(), "冲刷循环应一次排干全部事件")

## 嵌套冲刷保护（QD-R07：同帧递归禁绝）
func test_flush_reentrant_guard() -> void:
	var svc := QuestService.new()
	svc.accept("nv_quest_guard")
	svc._on_combat_finished("nv_battle_bandit", true, false, [])
	svc._flushing = true   # 模拟正处于冲刷循环内
	svc._flush_events()    # 嵌套调用 → 应直接返回，事件留给外层
	expect(svc._event_queue.size() == 1, "嵌套冲刷不得消费事件（防重入闸门）")
	svc._flushing = false
	svc._flush_events()
	expect(svc._event_queue.is_empty(), "外层冲刷应正常排干队列")

## P-Q2 链分相复现：冲刷循环内发奖 → add_item → 回调入队 → 同次冲刷继续消费
## （完成→交付→发奖→再推进链：不递归、不丢事件、按序到达）
func test_pq2_reward_chain_split_phase() -> void:
	_cleanup_flags()
	GameState.set_global_flag("nv_flag_guard_done", true)
	var svc := QuestService.new()
	var log: Array = []
	var spy_battle := func(_s, _o, ev):
		if ev.has("battle_id"):
			log.append("battle")
			# 模拟 P-Q2：战斗奖励发放 → add_item → inventory_item_added → 回调（分相后=入队）
			svc._on_inventory_added("nv_item_hairpin", 1)
		# item 事件（无 battle_id）路由到 battle 目标时静默（防测试自激）
	var spy_give := func(_s, _o, ev):
		if ev.has("item_id"):   # battle 事件广播到 give_item 目标时静默（真源行为：不匹配即零推进）
			log.append("item:" + str(ev.get("item_id")))
	svc.register_objective_handler("battle", spy_battle)
	svc.register_objective_handler("give_item", spy_give)
	expect(svc.accept("nv_quest_guard"), "守村任务应可接（无前置）")
	expect(svc.accept("nv_quest_help_maiden"), "前置达成后助送玉簪应可接")
	svc._on_combat_finished("nv_battle_bandit", true, false, [])
	svc._flush_events()   # 一次冲刷应消费完整链：battle → 派生 item（不递归、不丢）
	expect(log == ["battle", "item:nv_item_hairpin"],
		"P-Q2 链应分相按序到达且自然终止（实际 %s）" % [log])
	expect(svc._event_queue.is_empty() and not svc._flushing, "链终止后队列排干、闸门复位")

## 读档/重置清队列（防旧局残留事件串进新状态）
func test_load_and_reset_clear_queue() -> void:
	var svc := QuestService.new()
	svc._on_inventory_added("nv_item_hairpin", 1)
	svc.load({})
	expect(svc._event_queue.is_empty(), "load 应清空事件队列")
	svc._on_inventory_added("nv_item_hairpin", 1)
	svc.reset()
	expect(svc._event_queue.is_empty() and not svc._flushing, "reset 应清空事件队列并复位闸门")
