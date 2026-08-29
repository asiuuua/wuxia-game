# tests/unit/test_sworn_service.gd
# 结义服务单元测试（模块18 · M4）：无限结义 / 好感阈值 / 结义能力 / 存档往返
extends TestBase

func before_each() -> void:
	GameManager.bond_service.reset()
	GameManager.sworn_service.reset()
	GameManager.inventory_service.reset()

func test_service_wired() -> void:
	expect(GameManager.sworn_service != null, "sworn_service 应已装配")
	expect(GameManager.bond_service != null, "bond_service 应已装配")

# 好感满 sworn_affection(80) 才能结义；79 不行
func test_sworn_requires_affection() -> void:
	var ss = GameManager.sworn_service
	GameManager.bond_service.set_affection("npc_zhang_brother", 79)
	expect(not ss.can_sworn("npc_zhang_brother"), "79 好感不可结义")
	GameManager.bond_service.set_affection("npc_zhang_brother", 80)
	expect(ss.can_sworn("npc_zhang_brother"), "80 好感可结义")

# 结义成功 -> 记为兄弟 + 计数 1
func test_sworn_success() -> void:
	var ss = GameManager.sworn_service
	GameManager.bond_service.set_affection("npc_zhang_brother", 100)
	var res: Dictionary = ss.sworn("npc_zhang_brother")
	expect(res.get("ok", false), "结义应成功")
	expect(ss.is_sworn("npc_zhang_brother"), "应记为兄弟")
	expect_eq(ss.get_sworn_count(), 1, "结义数应为1")

# 不可结义者拒绝（苏婉儿 is_swornable=false）
func test_non_swornable_rejected() -> void:
	var ss = GameManager.sworn_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	expect(not ss.can_sworn("npc_su_waner"), "苏婉儿不可结义")
	var res: Dictionary = ss.sworn("npc_su_waner")
	expect(not res.get("ok", false), "对非结义 NPC 结义应失败")

# 存档往返
func test_save_roundtrip() -> void:
	var ss = GameManager.sworn_service
	GameManager.bond_service.set_affection("npc_zhang_brother", 100)
	ss.sworn("npc_zhang_brother")
	var snap: Dictionary = ss.save()
	ss.reset()
	ss.load(snap)
	expect(ss.is_sworn("npc_zhang_brother"), "读档后应仍结义")
	expect_eq(ss.get_sworn_count(), 1, "读档结义数1")
