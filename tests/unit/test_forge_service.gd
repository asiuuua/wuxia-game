# tests/unit/test_forge_service.gd
# 锻造服务单元测试（继承 TestBase，被 run_all.tscn 收录）
# 边界契约：未知配方不崩，返回安全值；describe_inputs 对未知配方返回字符串不崩。

extends TestBase
class_name TestForgeService

var _svc: ForgeService

func before_each() -> void:
	_svc = ForgeService.new()

func after_each() -> void:
	_svc = null

func test_can_forge_unknown() -> void:
	expect(not _svc.can_forge("no_such_recipe_999", 1), "未知配方不可锻造")

func test_describe_inputs_unknown_no_crash() -> void:
	var s: String = _svc.describe_inputs("no_such_recipe_999")
	expect(s is String, "未知配方 describe_inputs 返回字符串不崩")

# ── P0 修复回归：try_consume 返回值必须被检查（旧实现忽略返回值=扣除失败照样产出）──

func test_forge_missing_material_no_output() -> void:
	# 现配方 forge_iron_sword 的 material_iron_001 属 ID 基线存量悬空（materials.json 无此物），
	# 恰好构成「材料不可用」链路：应报 MISSING_MATERIAL、绝不产出、绝不误扣其他物品。
	# 「有材料但被锁定」的校验语义由 inventory 层 test_try_consume_respects_lock 覆盖，
	# forge 修复后完全信任 try_consume 的返回值（单一裁决）。
	var inv: InventoryService = GameManager.inventory_service
	expect(inv != null, "autoload inventory 应装配")
	if inv == null:
		return
	inv.reset()
	inv.add_item("material_ore_001", 10, "test")   # 干扰物：绝不应被误扣
	var r: int = _svc.forge("forge_iron_sword", 1)
	expect_eq(r, ForgeEnums.ForgeResult.FAIL_MISSING_MATERIAL, "缺料应报 MISSING_MATERIAL")
	expect_eq(inv.get_item_count("weapon_sword_iron_001"), 0, "缺料时绝不应有产出（白拿产出根因）")
	expect_eq(inv.get_item_count("material_ore_001"), 10, "失败时其他物品不应被误扣")
	inv.reset()

func test_can_forge_missing_material_false() -> void:
	# can_forge 口径与 forge 主流程一致：材料不可用即不可锻（UI 不出现可点但失败）
	expect(not _svc.can_forge("forge_iron_sword", 1), "材料悬空时 can_forge 应 false")
