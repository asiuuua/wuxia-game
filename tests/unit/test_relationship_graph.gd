# tests/unit/test_relationship_graph.gd
# 08 图批1 ①：RelationshipGraph 本体契约（RG-1~RG-5 / TY-1~TY-4 / SV-1 切片往返）。
# 覆盖：十型枚举全列、无序对复合键、量程执行（RG-3）、状态型禁分值、TY-4 启用面、
#       TY-3 投影通道、软删除（DISSOLVED 保留事实=SV-4 可回放面）、图切片往返。

extends TestBase


func test_ten_types_frozen() -> void:
	expect_eq(RelationshipType.TYPE_COUNT, 10, "宪法十型全列")
	var names := ["FRIEND", "RESPECT", "TRUST", "HATRED", "ROMANCE", "FAMILY", "MASTER", "DISCIPLE", "SWORN", "FACTION"]
	for i in range(10):
		expect(RelationshipType.type_name(i) == names[i], "十型序位冻结：%s（实际 %s）" % [names[i], RelationshipType.type_name(i)])
	expect(RelationshipType.is_directed(RelationshipType.Type.MASTER), "MASTER 有向（RF-2）")
	expect(RelationshipType.is_directed(RelationshipType.Type.DISCIPLE), "DISCIPLE 有向（RF-2）")
	expect(not RelationshipType.is_directed(RelationshipType.Type.FRIEND), "FRIEND 无向")


func test_edge_key_unordered_pair() -> void:
	var k1 := RelationshipEdge.edge_key("npc_b", "npc_a", RelationshipType.Type.FRIEND)
	var k2 := RelationshipEdge.edge_key("npc_a", "npc_b", RelationshipType.Type.FRIEND)
	expect(k1 == k2, "RG-2 无序对：双方向同键")
	var pair := RelationshipEdge.ordered_pair("npc_zhao", "npc_an")
	expect(pair[0] == "npc_an" and pair[1] == "npc_zhao", "字典序归一 min/max")


func test_upsert_and_bidirectional_query() -> void:
	var g := RelationshipGraph.new()
	var r := g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.FRIEND, 66, 100)
	expect(not r.is_failed(), "合法边 upsert 放行")
	var e1 := g.edge_of("npc_a", "npc_b", RelationshipType.Type.FRIEND)
	var e2 := g.edge_of("npc_b", "npc_a", RelationshipType.Type.FRIEND)
	expect(e1 != null, "正向可查")
	expect(e1 == e2, "RG-2：双方向命中同一条边（无序对唯一）")
	expect_eq(e1.score, 66, "score 落边")
	expect_eq(e1.since_day, 100, "since_day 定格（游戏日真源）")
	expect_eq(g.edge_count(), 1, "边数=1")


func test_score_range_enforced_per_type() -> void:
	var g := RelationshipGraph.new()
	expect(g.upsert_edge("a", "b", RelationshipType.Type.FRIEND, 101, 1).is_failed(), "越上界拒收（RG-3）")
	expect(g.upsert_edge("a", "b", RelationshipType.Type.FRIEND, -1, 1).is_failed(), "越下界拒收（RG-3）")
	expect(not g.upsert_edge("a", "b", RelationshipType.Type.FRIEND, 100, 1).is_failed(), "边界值 100 放行")


func test_state_type_forbids_score() -> void:
	var g := RelationshipGraph.new()
	var r := g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.SWORN, 5, 1)
	expect(r.is_failed(), "状态型禁分值（RG-3）")
	expect(r.get_error().get_code() == &"REL_STATE_TYPE_SCORED", "失败码=REL_STATE_TYPE_SCORED")
	expect(not g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.SWORN, 0, 1).is_failed(), "状态型零分值放行")


func test_disabled_type_rejected() -> void:
	var g := RelationshipGraph.new()
	var r := g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.FAMILY, 0, 1)
	expect(r.is_failed(), "TY-4：未启用型拒收（枚举冻结、实现后补）")
	expect(r.get_error().get_code() == &"REL_TYPE_DISABLED", "失败码=REL_TYPE_DISABLED")


func test_projection_channel_restricted() -> void:
	var g := RelationshipGraph.new()
	expect(g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.ROMANCE, 50, 1).is_failed(), "TY-3：ROMANCE 禁业务直写")
	expect(g.upsert_edge("npc_a", "sect_sword_001", RelationshipType.Type.FACTION, 0, 1).is_failed(), "TY-3：FACTION 禁业务直写")
	expect(not g.upsert_projection("npc_a", "npc_b", RelationshipType.Type.ROMANCE, 1).is_failed(), "投影通道放行 ROMANCE（真源=Marriage 模块）")
	expect(not g.upsert_projection("npc_a", "sect_sword_001", RelationshipType.Type.FACTION, 1).is_failed(), "投影通道放行 FACTION（真源=FactionMember 名册）")
	expect(g.upsert_projection("npc_a", "npc_b", RelationshipType.Type.FRIEND, 1).is_failed(), "投影通道不收业务型")
	expect_eq(g.edge_of("npc_a", "npc_b", RelationshipType.Type.ROMANCE).score, 0, "投影边 score 恒 0")


func test_dissolve_soft_delete() -> void:
	var g := RelationshipGraph.new()
	g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.TRUST, 40, 1)
	expect(g.dissolve("npc_b", "npc_a", RelationshipType.Type.TRUST), "软删除命中（无序对双方向）")
	var e := g.edge_of("npc_a", "npc_b", RelationshipType.Type.TRUST)
	expect(e != null, "SV-4：DISSOLVED 保留事实（可回放）")
	expect(e.state == RelationshipEdge.State.DISSOLVED, "状态=DISSOLVED")
	expect(not g.dissolve("npc_x", "npc_y", RelationshipType.Type.TRUST), "不存在边返回 false")


func test_edges_of_both_sides() -> void:
	var g := RelationshipGraph.new()
	g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.FRIEND, 10, 1)
	g.upsert_edge("npc_c", "npc_a", RelationshipType.Type.RESPECT, 20, 1)
	g.upsert_edge("npc_c", "npc_d", RelationshipType.Type.TRUST, 30, 1)
	expect_eq(g.edges_of("npc_a").size(), 2, "a 的边=2（两侧命中）")
	expect_eq(g.edges_of("npc_e").size(), 0, "孤点无边")


func test_save_slice_roundtrip() -> void:
	var g := RelationshipGraph.new()
	g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.FRIEND, 66, 100)
	g.upsert_edge("npc_a", "npc_c", RelationshipType.Type.SWORN, 0, 101)
	g.upsert_projection("npc_a", "npc_b", RelationshipType.Type.ROMANCE, 102)
	g.dissolve("npc_a", "npc_b", RelationshipType.Type.FRIEND)
	var blob: Array = g.to_save()
	var g2 := RelationshipGraph.new()
	g2.from_save(blob)
	expect_eq(g2.edge_count(), g.edge_count(), "SV-1：边数一致")
	for e in g.all_edges():
		var e2: RelationshipEdge = g2.edge_of(e.min_id, e.max_id, e.type)
		expect(e2 != null and e2.equals_edge(e), "逐边一致（含 score/state/since_day）")
