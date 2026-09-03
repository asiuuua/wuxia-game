# tests/unit/test_relationship_service.gd
# 关系网数据中枢（M3）单元测试：聚合门面正确性 + 可结缘判定随好感变化 + 子嗣进图
extends TestBase

func before_each() -> void:
	GameManager.bond_service.reset()
	GameManager.romance_service.reset()

## 服务应已装配
func test_service_wired() -> void:
	expect(GameManager.relationship_service != null, "关系网服务应已装配")

## 关系图应聚合全部样例 NPC（6 个：4 旧 + 柳如烟/慕晚晴）
func test_graph_aggregates_all_npcs() -> void:
	var g: Dictionary = GameManager.relationship_service.get_relationship_graph()
	expect_eq(int(g["nodes"].size()), 6, "应有 6 个样例 NPC 节点")
	expect_eq(int(g["summary"].get("npc_total", 0)), 6, "概览 npc_total 应为 6")

## 满好感播种：新女性 NPC 开局即满好感、可直接求婚（结缘全流程起点）
func test_initial_affection_seeded_full() -> void:
	GameManager.bond_service.reset()
	expect_eq(GameManager.bond_service.get_affection("npc_liu_ruyan"), 100, "柳如烟开局好感应满 100")
	expect_eq(GameManager.bond_service.get_affection("npc_mu_wanqing"), 100, "慕晚晴开局好感应满 100")
	expect_eq(GameManager.bond_service.get_affection("npc_su_waner"), 0, "苏婉儿无 initial_affection 应仍 0")
	var rel: Array = GameManager.relationship_service.get_marriageable_npc_ids()
	expect(rel.find("npc_liu_ruyan") >= 0, "柳如烟开局即可结缘")
	expect(rel.find("npc_mu_wanqing") >= 0, "慕晚晴开局即可结缘")

## 结缘全流程：满好感播种 → 求婚 → 已婚 → 寝欢 → 怀胎 → 分娩（柳如烟）
func test_full_marriage_flow_liu_ruyan() -> void:
	var rs = GameManager.romance_service
	var bs = GameManager.bond_service
	bs.reset()
	# 播种后直接可求婚（无需送礼拉好感）
	expect(rs.can_propose("npc_liu_ruyan"), "柳如烟满好感应可求婚")
	var p: Dictionary = rs.propose("npc_liu_ruyan")
	expect(p.get("ok", false), "柳如烟求婚应成功")
	expect(rs.is_spouse("npc_liu_ruyan"), "柳如烟应记为配偶")
	expect_eq(rs.get_romance_stage("npc_liu_ruyan"), BondEnums.RomanceStage.MARRIED, "阶段应为已婚")
	# 寝欢启动孕期
	var im: Dictionary = rs.begin_intimacy("npc_liu_ruyan")
	expect(im.get("ok", false), "已婚配偶寝欢应成功")
	expect(rs.is_pregnant("npc_liu_ruyan"), "柳如烟应处于孕期")
	# 推进怀胎十月分娩
	rs.advance_days(300)
	expect_eq(rs.get_children_of("npc_liu_ruyan").size(), 1, "满孕期应出生 1 子")
	var g: Dictionary = GameManager.relationship_service.get_relationship_graph()
	expect_eq(int(g["summary"].get("spouse_count", 0)), 1, "配偶数应为 1")
	expect_eq(int(g["summary"].get("child_count", 0)), 1, "子嗣数应为 1")

## 结缘全流程：慕晚晴求婚 + 关系网含其节点
func test_full_marriage_flow_mu_wanqing() -> void:
	var rs = GameManager.romance_service
	var bs = GameManager.bond_service
	bs.reset()
	var p: Dictionary = rs.propose("npc_mu_wanqing")
	expect(p.get("ok", false), "慕晚晴求婚应成功")
	expect(rs.is_spouse("npc_mu_wanqing"), "慕晚晴应记为配偶")
	var g: Dictionary = GameManager.relationship_service.get_relationship_graph()
	var found := false
	for n in g["nodes"]:
		if String(n.get("npc_id", "")) == "npc_mu_wanqing":
			found = true
			expect(bool(n.get("is_spouse", false)), "慕晚晴节点应为配偶")
	expect(found, "关系图应含慕晚晴节点")

## 可结缘列表应随好感度变化
func test_marriageable_follows_affection() -> void:
	var rel: Array = GameManager.relationship_service.get_marriageable_npc_ids()
	expect(rel.find("npc_su_waner") < 0, "0 好感时 苏婉儿不应可结缘")
	GameManager.bond_service.add_affection("npc_su_waner", 100, "test")
	rel = GameManager.relationship_service.get_marriageable_npc_ids()
	expect(rel.find("npc_su_waner") >= 0, "好感满 100 时 苏婉儿应可结缘")

## 关系图应包含配偶与子嗣（寝欢→怀胎→出生链路）
func test_graph_includes_spouse_and_child() -> void:
	var rs = GameManager.romance_service
	var bs = GameManager.bond_service
	bs.add_affection("npc_su_waner", 100, "test")
	var p: Dictionary = rs.propose("npc_su_waner")
	expect(p.get("ok", false), "苏婉儿求婚应成功")
	var im: Dictionary = rs.begin_intimacy("npc_su_waner")
	expect(im.get("ok", false), "已婚配偶寝欢应成功")
	rs.advance_days(300)
	var g: Dictionary = GameManager.relationship_service.get_relationship_graph()
	expect_eq(int(g["summary"].get("spouse_count", 0)), 1, "配偶数应为 1")
	expect_eq(int(g["summary"].get("child_count", 0)), 1, "子嗣数应为 1")
	var found := false
	for n in g["nodes"]:
		if String(n.get("npc_id", "")) == "npc_su_waner":
			found = true
			expect(bool(n.get("is_spouse", false)), "苏婉儿节点应为配偶")
			expect_eq(int((n.get("children", []) as Array).size()), 1, "苏婉儿应有 1 子嗣")
	expect(found, "关系图应含苏婉儿节点")

## enriched 配偶列表应带名字，便于面板直接渲染
func test_spouses_enriched_has_name() -> void:
	var rs = GameManager.romance_service
	var bs = GameManager.bond_service
	bs.add_affection("npc_su_waner", 100, "test")
	rs.propose("npc_su_waner")
	var sp: Array = GameManager.relationship_service.get_spouses_enriched()
	expect_eq(int(sp.size()), 1, "enriched 配偶应有 1")
	expect(String(sp[0].get("name", "")).length() > 0, "配偶应有名字")

## 关系图应自动纳入结义与师徒（M4 扩展；UI 零改）
func test_graph_includes_sworn_and_master() -> void:
	var bs = GameManager.bond_service
	var rel = GameManager.relationship_service
	bs.add_affection("npc_zhang_brother", 100, "test")
	bs.add_affection("npc_master_li", 100, "test")
	GameManager.sworn_service.sworn("npc_zhang_brother")
	GameManager.master_service.become_apprentice("npc_master_li")
	var g: Dictionary = rel.get_relationship_graph()
	expect_eq(int(g["summary"].get("sworn_count", 0)), 1, "结义数应为 1")
	expect_eq(int(g["summary"].get("master_count", 0)), 1, "师父数应为 1")
	expect_eq(int(g["sworn"].size()), 1, "关系图 sworn 数组应含 1")
	expect_eq(int(g["masters"].size()), 1, "关系图 masters 数组应含 1")
	var zhang_ok := false
	var li_ok := false
	for n in g["nodes"]:
		var nid: String = String(n.get("npc_id", ""))
		if nid == "npc_zhang_brother":
			zhang_ok = bool(n.get("is_sworn", false))
			var kinds: Array = n.get("relation_kinds", [])
			expect(kinds.has("SWORN"), "张大彪节点 relation_kinds 应含 SWORN")
		if nid == "npc_master_li":
			li_ok = bool(n.get("is_master", false))
			var kinds: Array = n.get("relation_kinds", [])
			expect(kinds.has("MASTER"), "李苍松节点 relation_kinds 应含 MASTER")
	expect(zhang_ok, "张大彪节点应标记已结义")
	expect(li_ok, "李苍松节点应标记已拜师")
