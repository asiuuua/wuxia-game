# services/quest/facts.gd
# 游戏事实适配器（P3 统一条件 2026-09-04）：把 QuestService / InventoryService /
# BondService / GameState 的查询收敛为一个鸭子接口，喂给 core/condition.gd 的
# ConditionService（纯求值器，不反向依赖服务层）。
# 接口：get_flag(key,def) / get_favor(npc) / get_progress(quest) / quest_active(id) / item_count(id)
# 全部带空安全降级：服务未装配时返回中性值（不崩，与"安全降级"铁律一致）。

class_name GameFacts
extends RefCounted

# ---------- flag / favor / progress：走 GameState 全局旗标（存档唯一真源） ----------
func get_flag(key: String, default_value: Variant = null) -> Variant:
	return GameState.get_global_flag(key, default_value)

func has_flag(key: String) -> bool:
	return GameState.has_global_flag(key)

func set_flag(key: String, value: Variant) -> void:
	GameState.set_global_flag(key, value)

func get_favor(npc_id: String) -> float:
	if GameManager != null and GameManager.bond_service != null and GameManager.bond_service.has_method("get_affection"):
		return float(GameManager.bond_service.get_affection(npc_id))
	return 0.0

func get_progress(quest_id: String) -> int:
	# 对齐 FlagStore 语义：进度旗标 "progress:<quest_id>"（quest_graph 条件/副作用即基于此）。
	# 注意：QuestService 的 objectives_progress 是另一套（P4 状态所有权时归一），此处不读它。
	return int(GameState.get_global_flag("progress:" + quest_id, 0))

# ---------- 任务 / 物品 ----------
func quest_active(quest_id: String) -> bool:
	if GameManager != null and GameManager.quest_service != null:
		return GameManager.quest_service.is_active(quest_id)
	return false

func item_count(item_id: String) -> int:
	if GameManager != null and GameManager.inventory_service != null and GameManager.inventory_service.has_method("get_item_count"):
		return int(GameManager.inventory_service.get_item_count(item_id))
	return 0

# ---------- 写入侧（P5 去服务定位器·quest 域示范 2026-09-04） ----------
# quest_service 的奖励/目标处理统一经本适配器，不再直取 GameManager.*；
# 其余域（战斗/背包/…）按同模式分批跟进。空安全降级：服务未装配时静默跳过。

func gain_exp(amount: int) -> void:
	if amount > 0 and GameManager != null and GameManager.player_state != null:
		GameManager.player_state.gain_exp(amount)

func add_silver(amount: int) -> void:
	if amount > 0 and GameManager != null and GameManager.player_state != null:
		# P0 修复：直改 silver 不发 player_money_changed 事件，UI 银两显示不同步；统一走 add_money
		GameManager.player_state.add_money(amount)

## 物品奖励能否全部装入（turn_in 前置预检用）。
## 服务缺失时降级放行（与写入侧 add_item 静默跳过的降级口径一致，不制造新的卡死面）。
func can_add_items(items: Array) -> bool:
	if GameManager == null or GameManager.inventory_service == null:
		return true
	return GameManager.inventory_service.can_add_batch(items)

func add_item(item_id: String, count: int, source: String) -> void:
	if item_id != "" and GameManager != null and GameManager.inventory_service != null:
		GameManager.inventory_service.add_item(item_id, count, source)

func learn_ability(ability_id: String) -> void:
	if ability_id != "" and GameManager != null and GameManager.ability_service != null:
		GameManager.ability_service.learn(ability_id)
