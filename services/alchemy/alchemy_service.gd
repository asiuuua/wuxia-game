# services/alchemy/alchemy_service.gd
# 炼药系统（Phase 2）：读取配方配置，校验材料 -> 消耗 -> 产出丹药
# 纯配置驱动、无持久状态，故不实现 ISaveable。通过 EventBus 通知结果。

extends RefCounted
class_name AlchemyService

## 炼制：成功返回 true 并发 alchemy_refined；材料不足/背包装不下产出发 alchemy_failed 并返回 false
func refine(recipe_id: String) -> bool:
	var recipe: Dictionary = ConfigManager.get_recipe(recipe_id)
	if recipe.is_empty():
		GameLogger.warn("Alchemy", "配方不存在: %s" % recipe_id)
		return false
	var inv: InventoryService = GameManager.inventory_service
	var out_id: String = String(recipe.get("output_pill_id", ""))
	var out_count: int = int(recipe.get("output_count", 1))
	# 产出空间预检（P0 修复）：满包则整体失败，绝不"扣了材料丢丹药"
	if out_id != "" and not inv.can_add(out_id, out_count):
		EventBus.alchemy_failed.emit(recipe_id, "背包已满，无法放入产出")
		return false
	# 原子扣料：先全量校验再统一扣除（事务语义）
	var mats: Array = []
	for inp in recipe.get("inputs", []):
		mats.append({ "item_id": String(inp["item_id"]), "count": int(inp.get("count", 1)) })
	if not inv.try_consume(mats, "alchemy:%s" % recipe_id):
		EventBus.alchemy_failed.emit(recipe_id, "材料不足")
		return false
	# 产出丹药
	inv.add_item(out_id, out_count, "alchemy:%s" % recipe_id)
	EventBus.alchemy_refined.emit(recipe_id, out_id, out_count)
	GameLogger.info("Alchemy", "炼制 %s -> %s x%d" % [recipe_id, out_id, out_count])
	return true

## UI 用：当前材料是否满足配方
func can_refine(recipe_id: String) -> bool:
	var recipe: Dictionary = ConfigManager.get_recipe(recipe_id)
	if recipe.is_empty():
		return false
	for inp in recipe.get("inputs", []):
		if GameManager.inventory_service.get_item_count(inp["item_id"]) < int(inp.get("count", 1)):
			return false
	return true
