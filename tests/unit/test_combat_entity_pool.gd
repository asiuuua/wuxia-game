# tests/unit/test_combat_entity_pool.gd
# P4 战斗实体对象池单测：验证 复用 / 重置清零 / 有界回收 / HUD 复用归零
# 不依赖场景树（BattleEntity/UnitHud 的 setup 已惰化为无树也可构建子节点）。

extends TestBase
class_name TestCombatEntityPool

func before_each() -> void:
	CombatEntityPool.clear()

func after_each() -> void:
	CombatEntityPool.clear()

## 首次新建；release 后再次 acquire 应复用同一实例（零 new），且被重置为新阵营/名称/气血
func test_acquire_new_then_reuse() -> void:
	var e1 := CombatEntityPool.acquire_entity("a", false, "敌A", 100, 50, null)
	expect(e1 != null, "acquire 应返回实体")
	expect(e1._built, "首次 acquire 应已构建视觉子节点")
	CombatEntityPool.release_entity(e1)
	var e2 := CombatEntityPool.acquire_entity("b", true, "玩家", 200, 80, null)
	expect(e2 == e1, "release 后再次 acquire 应复用同一实例（零 new）")
	expect(e2.is_player == true, "复用实例应被重置为新的玩家阵营")
	expect(e2._name_lbl.text == "玩家", "复用实例名称应被重置为新名称")
	expect(e2._hp == 200 and e2._max_hp == 200, "复用实例气血应被重置为新上限")

## 复用前 reset 应立刻清空飘字，且再次 acquire 后气血回到满值（无残留）
func test_reset_clears_pops_on_reuse() -> void:
	var e := CombatEntityPool.acquire_entity("x", false, "敌", 100, 50, null)
	e.set_hp(30)
	e.pop_text("命中", Color(1, 0, 0))
	CombatEntityPool.release_entity(e)
	expect(e._pop_layer.get_child_count() == 0, "release/reset 后飘字应立刻清空")
	var e2 := CombatEntityPool.acquire_entity("y", false, "敌2", 100, 50, null)
	expect(e2 == e, "应复用同一实例")
	expect(e2._hp == 100, "复用后气血应被 setup 重置为满")

## 空闲表有界：超额 release 应被裁剪，内存恒定可控（不无限增长）
func test_entity_pool_bounded() -> void:
	for i in range(0, 80):
		var e := CombatEntityPool.acquire_entity("e%d" % i, false, "敌", 100, 50, null)
		CombatEntityPool.release_entity(e)
	expect(CombatEntityPool.get_free_entity_count() <= 64, "实体空闲表应被裁剪到上限 64 以内")

## HUD 复用 + 重置归零：状态行/护盾/飘字清空，名称与 _instant 被重置
func test_hud_acquire_reuse_and_reset() -> void:
	var h1 := CombatEntityPool.acquire_hud("敌1", 120, 60)
	expect(h1 != null, "acquire_hud 应返回 HUD")
	expect(h1._built, "HUD 应已构建")
	h1.set_status([["poison", 2]])
	h1.set_shield(30)
	CombatEntityPool.release_hud(h1)
	expect(h1._status.get_child_count() == 0, "release/reset 后状态行应清空")
	expect(h1._shield_fill.size.x == 0.0, "release/reset 后护盾条应归零")
	var h2 := CombatEntityPool.acquire_hud("敌2", 200, 90)
	expect(h2 == h1, "HUD 应复用同一实例")
	expect(h2._name.text == "敌2", "复用 HUD 名称应被重置")
	expect(h2._instant == false, "复用 HUD 的 _instant 应被重置为 false")

## HUD 空闲表有界
func test_hud_pool_bounded() -> void:
	for i in range(0, 80):
		var h := CombatEntityPool.acquire_hud("敌%d" % i, 100, 50)
		CombatEntityPool.release_hud(h)
	expect(CombatEntityPool.get_free_hud_count() <= 64, "HUD 空闲表应被裁剪到上限 64 以内")
