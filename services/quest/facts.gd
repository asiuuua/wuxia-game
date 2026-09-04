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
