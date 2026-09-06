# tests/integration/test_integration_quest_save_chain.gd
# GATE03 Integration 最小实体（04 图 LN-G03 / 宪法 §88 / 待办清单 A1，2026-09-06）：
# 跨模块链 = ConfigManager(任务定义) → GameState(旗标前置) → Inventory(交件)
#           → QuestService(分相队列推进 + auto_complete 交付) → PlayerState(奖励结算)
#           → SaveManager(存读档回环)
# 服务经装配根访问（GameManager.inventory_service / quest_service，Phase3 装配收敛前形态）。
# 行为注记（实测复查 2026-09-06）：全部任务 JSON 均未写 auto_complete 字段（grep data/ 零命中，
#   初判「null 语义缺陷」系侦察失误——python dict.get() 键缺失也返回 None 被误读为 null）。
#   运行时 data.get("auto_complete", true) 走缺省 true → 交足 need_item 自动交付，此为
#   12 图 QuestDefinition 可选字段的缺省语义，非缺陷，无需改数据或代码。
# 安全约定：只占用 save_99.json（UI 槽位之外探针槽），用完即删；
#           after_each 恢复内存态（任务出册/奖励回冲/背包清场/旗标复位）防用例间污染。

extends TestBase
class_name TestIntegrationQuestSaveChain

const QUEST_ID := "nv_quest_help_maiden"
const NEED_ITEM := "nv_item_hairpin"
const REWARD_ITEM := "nv_item_wine"
const REWARD_ITEM_COUNT := 2
const REWARD_SILVER := 60
const PROBE_SLOT := 99

var _base_silver := 0

func before_each() -> void:
	# nv_quest_help_maiden.prerequisites = {"nv_flag_guard_done": true}（fail-closed 前置）
	GameState.set_global_flag("nv_flag_guard_done", true)
	_base_silver = GameManager.player_state.silver

func after_each() -> void:
	var path := SaveManager.SAVE_DIR + "save_%d.json" % PROBE_SLOT
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var qs := GameManager.quest_service
	var inv := GameManager.inventory_service
	qs.active_quests.erase(QUEST_ID)
	qs.completed_quests.erase(QUEST_ID)
	qs.tracked_ids.erase(QUEST_ID)
	if GameManager.player_state != null:
		GameManager.player_state.silver = _base_silver   # 奖励回冲到测试前基线
	if inv.get_item_count(REWARD_ITEM) > 0:
		inv.remove_item_by_id(REWARD_ITEM, REWARD_ITEM_COUNT)
	if inv.get_item_count(NEED_ITEM) > 0:
		inv.remove_item_by_id(NEED_ITEM, 1)
	GameState.set_global_flag("nv_flag_guard_done", false)

# === 链 1：接取 → 交件推进 → 自动交付 → 奖励结算（跨 5 模块全链） ===
func test_chain_accept_progress_autoturn_in_reward() -> void:
	if not expect(ConfigManager.has_quest(QUEST_ID), "区域任务应已入 ConfigManager（newbie_village/quests.json）"):
		return
	var qs := GameManager.quest_service
	var inv := GameManager.inventory_service
	if not expect(qs.can_accept(QUEST_ID), "旗标前置满足后应可接取"):
		return
	expect(qs.accept(QUEST_ID), "接取应成功")
	expect(qs.active_quests.has(QUEST_ID), "接取后应入 active_quests")
	# 交件：背包加玉簪 → inventory_item_added 事件 → QuestService 分相队列（只入队）
	expect(inv.add_item(NEED_ITEM, 1, "integration_test"), "背包加入玉簪应成功")
	# 分相纪律（QD-R07）：外部直调 _on_* 后须冲刷才见推进（_flush_events 同步可调，测试确定性入口）
	qs._flush_events()
	# auto_complete 字段全任务未写 → 缺省 true → 交足后自动交付（见文件头注记）
	expect(qs.completed_quests.has(QUEST_ID), "交足玉簪后应自动交付并入 completed_quests")
	expect(not qs.active_quests.has(QUEST_ID), "交付后应移出 active_quests")
	expect_eq(GameManager.player_state.silver, _base_silver + REWARD_SILVER, "银两奖励 +60 应入账")
	expect(inv.get_item_count(REWARD_ITEM) >= REWARD_ITEM_COUNT, "物品奖励（酒×2）应入包")

# === 链 2：任务状态跨存读档回环（save → 破坏内存 → load → 恢复） ===
func test_quest_state_persists_across_save_load() -> void:
	var qs := GameManager.quest_service
	var inv := GameManager.inventory_service
	expect(qs.accept(QUEST_ID), "接取应成功")
	expect(inv.add_item(NEED_ITEM, 1, "integration_test"), "背包加入玉簪应成功")
	qs._flush_events()
	expect(qs.completed_quests.has(QUEST_ID), "交足后应已自动交付")
	var silver_after := GameManager.player_state.silver
	expect(SaveManager.save_to_slot(PROBE_SLOT, "integration_probe"), "探针档保存应成功")
	# 破坏内存态：任务出册 + 奖励回冲
	qs.completed_quests.erase(QUEST_ID)
	GameManager.player_state.silver = _base_silver
	inv.remove_item_by_id(REWARD_ITEM, REWARD_ITEM_COUNT)
	# 读档回环：任务状态与奖励应整体恢复
	expect(SaveManager.load_from_slot(PROBE_SLOT), "探针档读档应成功")
	expect(qs.completed_quests.has(QUEST_ID), "读档后已完成任务应恢复")
	expect_eq(GameManager.player_state.silver, silver_after, "读档后银两应恢复至存档时点")
	expect(inv.get_item_count(REWARD_ITEM) >= REWARD_ITEM_COUNT, "读档后奖励物品应恢复")

# === 链 3：读档后奖励不重复发放（存读档回环 + 幂等语义，P-RH9 发布前老档读入验证同族） ===
func test_load_does_not_regrant_rewards() -> void:
	var qs := GameManager.quest_service
	var inv := GameManager.inventory_service
	expect(qs.accept(QUEST_ID), "接取应成功")
	expect(inv.add_item(NEED_ITEM, 1, "integration_test"), "背包加入玉簪应成功")
	qs._flush_events()
	expect(qs.completed_quests.has(QUEST_ID), "交足后应已自动交付（奖励已发一轮）")
	expect(SaveManager.save_to_slot(PROBE_SLOT, "integration_probe"), "探针档保存应成功")
	# 破坏内存态（模拟重启）：任务清空 + 奖励回冲 + 背包清场
	qs.completed_quests.erase(QUEST_ID)
	GameManager.player_state.silver = _base_silver
	inv.remove_item_by_id(REWARD_ITEM, REWARD_ITEM_COUNT)
	expect(SaveManager.load_from_slot(PROBE_SLOT), "读档应成功")
	# 读档恢复：任务在册（TURNED_IN 态）且奖励只到账一轮——存档快照覆盖，不经再次交付重发
	expect(qs.completed_quests.has(QUEST_ID), "读档后已交付任务应恢复")
	expect_eq(GameManager.player_state.silver, _base_silver + REWARD_SILVER, "读档后银两应恰为奖励一轮（不重复发放）")
	expect(inv.get_item_count(REWARD_ITEM) >= REWARD_ITEM_COUNT, "读档后奖励物品应恢复")
