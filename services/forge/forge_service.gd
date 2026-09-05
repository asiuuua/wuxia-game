# services/forge/forge_service.gd
# 锻造系统（Phase 2 系统填充）：消费材料 -> 产出装备/道具
# 纯配置驱动、无持久状态，故不实现 ISaveable（同 AlchemyService 模式）
# 2026-08-29 叶子层实现：forge() / can_forge() 补全

extends RefCounted
class_name ForgeService

## 锻造：校验等级与材料 -> 扣除材料 -> 产出物品 -> emit 结果事件
## 返回 ForgeEnums.ForgeResult
func forge(recipe_id: String, count: int) -> int:
	if count <= 0:
		EventBus.notify_forge_failed.emit(recipe_id, "INVALID_COUNT")
		return ForgeEnums.ForgeResult.FAIL_INVALID_COUNT

	var recipe: Dictionary = ConfigManager.get_forge_recipe(recipe_id)
	if recipe.is_empty():
		EventBus.notify_forge_failed.emit(recipe_id, "UNKNOWN_RECIPE")
		return ForgeEnums.ForgeResult.FAIL_UNKNOWN_RECIPE

	var ps: PlayerState = GameManager.player_state
	var inv: InventoryService = GameManager.inventory_service

	var out_id: String = String(recipe.get("output_item_id", ""))
	var out_count: int = int(recipe.get("output_count", 1)) * count

	# 等级校验
	var level_req: int = int(recipe.get("level_req", 1))
	if ps != null and ps.level < level_req:
		EventBus.notify_forge_failed.emit(recipe_id, "LEVEL_TOO_LOW")
		return ForgeEnums.ForgeResult.FAIL_LEVEL_TOO_LOW

	# 产出空间预检（P0 修复）：满包则整体失败，绝不"扣了材料丢产出"
	if inv != null and out_id != "" and not inv.can_add(out_id, out_count):
		EventBus.notify_forge_failed.emit(recipe_id, "BAG_FULL")
		return ForgeEnums.ForgeResult.FAIL_BAG_FULL

	# 材料原子扣除（单一裁决，P0 修复）：try_consume 内部先按「非锁定可用量」全量校验、
	# 再统一扣除，任一不足整体不扣并返回 false。
	# 旧实现两个洞：① 校验用 get_item_count（含锁定实例）→ 锁定材料蒙混过关；
	# ② try_consume 返回值被忽略 → 扣除失败照样走到产出 = 白拿产出。
	if inv != null:
		var mats: Array = []
		for inp in recipe.get("inputs", []):
			var item_id: String = String(inp.get("item_id", ""))
			if item_id == "":
				continue
			mats.append({ "item_id": item_id, "count": int(inp.get("count", 1)) * count })
		if not mats.is_empty() and not inv.try_consume(mats, "forge:%s" % recipe_id):
			EventBus.notify_forge_failed.emit(recipe_id, "MISSING_MATERIAL")
			return ForgeEnums.ForgeResult.FAIL_MISSING_MATERIAL

	# 产出
	if out_id != "" and inv != null:
		inv.add_item(out_id, out_count, "forge")

	EventBus.notify_forge_completed.emit(recipe_id, out_id, out_count)
	return ForgeEnums.ForgeResult.SUCCESS

## UI 用：材料与等级是否都满足（count 与 forge() 的批量数保持一致，默认 1）
## 口径对齐 forge 主流程（try_consume 按非锁定可用量校验）：锁定材料实际不可消耗，
## can_forge 若按含锁定的 get_item_count 判定会「按钮可点、实际失败」
func can_forge(recipe_id: String, count: int = 1) -> bool:
	var recipe: Dictionary = ConfigManager.get_forge_recipe(recipe_id)
	if recipe.is_empty():
		return false

	var ps: PlayerState = GameManager.player_state
	var level_req: int = int(recipe.get("level_req", 1))
	if ps != null and ps.level < level_req:
		return false

	var inv: InventoryService = GameManager.inventory_service
	if inv == null:
		return false
	for inp in recipe.get("inputs", []):
		var item_id: String = String(inp.get("item_id", ""))
		if item_id == "":
			continue
		var need: int = int(inp.get("count", 1)) * count
		if inv.get_unlocked_count(item_id) < need:
			return false
	return true

## UI 用：把配方材料渲染成 "铁石 2/3" 形式（have 口径同 can_forge：非锁定可用量）
func describe_inputs(recipe_id: String) -> String:
	var recipe: Dictionary = ConfigManager.get_forge_recipe(recipe_id)
	if recipe.is_empty():
		return ""
	var inv: InventoryService = GameManager.inventory_service
	var parts: Array[String] = []
	for inp in recipe.get("inputs", []):
		var item_id: String = String(inp.get("item_id", ""))
		if item_id == "":
			continue
		var have: int = inv.get_unlocked_count(item_id) if inv != null else 0
		var need: int = int(inp.get("count", 1))
		var nm: String = ConfigManager.get_item(item_id).get("name", item_id)
		parts.append("%s %d/%d" % [nm, have, need])
	return "  ".join(parts)
