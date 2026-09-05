# tests/unit/test_quest_service.gd
# 任务服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 边界契约：未知任务/非法状态不崩，返回安全值；reset 清空活跃列表。

extends TestBase
class_name TestQuestService

const WEAPON := "weapon_sword_iron_001"
const ORE := "material_ore_001"

var _svc: QuestService

func before_each() -> void:
	_svc = QuestService.new()

func after_each() -> void:
	_svc = null
	# 满包交付用例改过全局单例（负重/背包），复位避免污染其他套件
	var ps: PlayerState = GameManager.player_state
	if ps != null:
		ps.strength = 10
	var inv: InventoryService = GameManager.inventory_service
	if inv != null:
		inv.reset()
	EventBus.cmd_set_difficulty.emit("NORMAL", true)

func test_can_accept_unknown() -> void:
	expect(not _svc.can_accept("no_such_quest_999"), "未知任务不可接")

func test_accept_unknown_returns_false() -> void:
	expect(not _svc.accept("no_such_quest_999"), "接受未知任务应返回 false 不崩")

func test_is_active_unknown() -> void:
	expect(not _svc.is_active("no_such_quest_999"), "未知任务不应处于活跃")

func test_reset_clears_active() -> void:
	_svc.reset()
	expect_eq(_svc.get_active_quest_ids().size(), 0, "reset 后无活跃任务")

# ── P0 修复回归：满包交付不丢奖励（前置预检 + 腾格自动补交）──

func test_turn_in_full_bag_defers_reward_then_retry() -> void:
	# 旧实现先置 TURNED_IN 再发奖：满包时物品奖励走溢出事件直接蒸发，且无手动补交入口。
	# 修复后：预检失败保持 COMPLETED、什么都不发（exp/silver/items 同批原子，补交不重发）；
	# 腾出空间后 retry_completed_turn_ins 自动补交全部奖励。
	# 选 q_sect_join_001：奖励物品 weapon_blade_iron_001 走主栏（max_stack=1 占独立格），
	# 用 30 把独立武器堵主栏即构成满包（材料类奖励会堆叠，堵栏方式见 ORE 的教训）。
	var qid := "q_sect_join_001"   # exp120 + silver50 + weapon_blade_iron_001×1 + abilities
	var reward_item := "weapon_blade_iron_001"
	var inv: InventoryService = GameManager.inventory_service
	var ps: PlayerState = GameManager.player_state
	expect(inv != null and ps != null, "autoload 服务应已装配")
	if inv == null or ps == null:
		return
	expect(ConfigManager.has_item(reward_item), "测试前提：%s 应存在" % reward_item)
	inv.reset()
	_svc.reset()
	ps.strength = 1000   # 顶高负重，纯槽位满包
	for i in 30:
		inv.add_item(WEAPON, 1, "test")   # 主栏 30 格满（max_stack=1，30 个独立实例）
	var state := QuestState.new()
	state.quest_id = qid
	state.status = QuestEnums.QuestStatus.COMPLETED
	_svc.active_quests[qid] = state
	var silver0: int = ps.silver
	# 满包交付：整体拒绝、保持 COMPLETED、绝不发任何奖励
	expect(not _svc.turn_in(qid), "满包时交付应被拒绝（奖励暂缓）")
	expect(_svc.active_quests.has(qid), "任务应保持在册")
	expect_eq(int(state.status), int(QuestEnums.QuestStatus.COMPLETED), "状态应保持 COMPLETED")
	expect_eq(inv.get_item_count(reward_item), 0, "物品奖励不应发放（更不应蒸发）")
	expect_eq(ps.silver, silver0, "银两奖励不应发放（同批原子）")
	# 腾出 1 格主栏 → 自动补交
	var drop_iid := ""
	for inst in inv.main_slots:
		if inst != null and inst.item_id == WEAPON:
			drop_iid = String(inst.instance_id)
			break
	expect(bool(inv.drop_item(drop_iid, 1)["ok"]), "腾格应成功")
	_svc.retry_completed_turn_ins(WEAPON, 1)   # 模拟 EventBus.inventory_item_removed 触发
	expect(not _svc.active_quests.has(qid), "补交后任务应移出活跃")
	expect(_svc.completed_quests.has(qid), "补交后应进入已完成")
	expect_eq(inv.get_item_count(reward_item), 1, "腾格后物品奖励应送达")
	expect_eq(ps.silver, silver0 + 50, "腾格后银两奖励应送达")
	_svc.reset()

func test_turn_in_bad_quest_safe() -> void:
	expect(not _svc.turn_in("no_such_quest_999"), "未知任务交付应返回 false 不崩")
