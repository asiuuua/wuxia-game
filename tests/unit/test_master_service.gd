# tests/unit/test_master_service.gd
# 师徒服务单元测试（模块18 · M4）：双向拜师收徒 / 好感阈值 / 可授武学 / 存档往返
extends TestBase

func before_each() -> void:
	GameManager.bond_service.reset()
	GameManager.master_service.reset()
	GameManager.inventory_service.reset()

func test_service_wired() -> void:
	expect(GameManager.master_service != null, "master_service 应已装配")
	expect(GameManager.bond_service != null, "bond_service 应已装配")

# 好感满 master_affection(60) 才能拜师；59 不行
func test_apprentice_requires_affection() -> void:
	var ms = GameManager.master_service
	GameManager.bond_service.set_affection("npc_master_li", 59)
	expect(not ms.can_apprentice("npc_master_li"), "59 好感不可拜师")
	GameManager.bond_service.set_affection("npc_master_li", 60)
	expect(ms.can_apprentice("npc_master_li"), "60 好感可拜师")

# 拜师成功 -> 记为师父 + 读取可授武学（来自 relations.json teachable_abilities）
func test_become_apprentice() -> void:
	var ms = GameManager.master_service
	GameManager.bond_service.set_affection("npc_master_li", 100)
	var res: Dictionary = ms.become_apprentice("npc_master_li")
	expect(res.get("ok", false), "拜师应成功")
	expect(ms.is_master("npc_master_li"), "李苍松应为师父")
	expect_eq(ms.get_master_count(), 1, "师父数应为1")
	var ab: Array = ms.get_teachable_abilities("npc_master_li")
	expect(ab.has("sword_qingsong_001"), "应读取可授武学 sword_qingsong_001")

# 收徒（玩家为师，前向兼容）：任意已知 NPC 可收徒
func test_take_apprentice() -> void:
	var ms = GameManager.master_service
	var res: Dictionary = ms.take_apprentice("npc_xiao_ying")
	expect(res.get("ok", false), "收徒应成功")
	expect(ms.is_apprentice("npc_xiao_ying"), "小樱应为徒弟")
	expect_eq(ms.get_apprentice_count(), 1, "徒弟数应为1")

# 不可拜师者拒绝（苏婉儿 is_masterable=false）
func test_non_masterable_rejected() -> void:
	var ms = GameManager.master_service
	GameManager.bond_service.set_affection("npc_su_waner", 100)
	expect(not ms.can_apprentice("npc_su_waner"), "苏婉儿不可拜师")
	var res: Dictionary = ms.become_apprentice("npc_su_waner")
	expect(not res.get("ok", false), "对非可拜师 NPC 拜师应失败")

# 存档往返
func test_save_roundtrip() -> void:
	var ms = GameManager.master_service
	GameManager.bond_service.set_affection("npc_master_li", 100)
	ms.become_apprentice("npc_master_li")
	var snap: Dictionary = ms.save()
	ms.reset()
	ms.load(snap)
	expect(ms.is_master("npc_master_li"), "读档后应仍师父")
	expect_eq(ms.get_master_count(), 1, "读档师父数1")
