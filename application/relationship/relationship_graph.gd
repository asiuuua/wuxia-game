# application/relationship/relationship_graph.gd
# 08 图批1 ①（RG-1/RG-5/SV-1）：RelationshipGraph 本体 —— 关系唯一事实源骨架。
# RG-1 五件套落位：Graph（本类，边集合）· RelationshipEdge · RelationshipType ·
#   RelationshipEdge.State · RelationshipRule（挂点，relationship_rule.gd）。
# RG-5 载体：RefCounted 零 Node；边数上限与衰减参数 JSON 配置挂点（05 Definition
#   契约，批2 接线）。
# TY-2 收编映射（Phase2 迁移执行，本批=骨架）：好感→四象复合 score 边 · 结义→SWORN ·
#   师徒→MASTER/DISCIPLE 双边 · 配偶→ROMANCE 投影 · 门派→FACTION 投影边。
# SV-1：图切片（边集含 score/state/since_day）由本 Owner 导出/恢复；现 affections/
#   spouses/sworn/master 散存档键迁移期双读兼容（Phase2），迁移完成删旧键走迁移步。
# 用法（批1 契约面）：
#   var g := RelationshipGraph.new()
#   g.upsert_edge("npc_a", "npc_b", RelationshipType.Type.FRIEND, 66, day)   # 业务边
#   g.upsert_projection("npc_a", "sect_sword_001", RelationshipType.Type.FACTION, day)  # 投影边

class_name RelationshipGraph
extends RefCounted

var _edges: Dictionary = {}   # edge_key("min|max|type") -> RelationshipEdge


## 业务写入（TY-4 启用面）：类型须启用；score 须在量程内（RG-3）；状态型禁分值。
## 返回 OperationResult（ok / fail 带 code），调用方必须处理失败不得静默。
func upsert_edge(a: String, b: String, t: int, score: int, day: int, state: int = RelationshipEdge.State.ACTIVE) -> OperationResult:
	return _upsert(a, b, t, score, day, state, false)


## TY-3 投影通道：ROMANCE/FACTION 专用（真源在 Marriage/Faction 模块，投影失效即重查，
## 禁双写——本入口只做投影同步，score 恒 0、state=ACTIVE）。
func upsert_projection(a: String, b: String, t: int, day: int) -> OperationResult:
	if not RelationshipType.is_projection_only(t):
		return OperationResult.fail(&"REL_NOT_PROJECTION", "projection channel restricted to projection-only types", {"type": t})
	return _upsert(a, b, t, 0, day, RelationshipEdge.State.ACTIVE, true)


## 内部统一写入面：allow_projection 仅投影通道置真（TY-3 旁路，业务面无此权限）
func _upsert(a: String, b: String, t: int, score: int, day: int, state: int, allow_projection: bool) -> OperationResult:
	var type_allowed := RelationshipType.is_enabled(t) or (allow_projection and RelationshipType.is_projection_only(t))
	if not type_allowed:
		return OperationResult.fail(&"REL_TYPE_DISABLED", "type not enabled (TY-4)", {"type": t})
	if a == b:
		return OperationResult.fail(&"REL_SELF_LOOP", "self loop forbidden", {"id": a})
	if RelationshipType.is_state_based(t) and score != 0:
		return OperationResult.fail(&"REL_STATE_TYPE_SCORED", "state-based type forbids score", {"type": t})
	if not RelationshipType.score_in_range(t, score):
		return OperationResult.fail(&"REL_SCORE_OUT_OF_RANGE", "score out of type range (RG-3)",
			{"type": t, "score": score, "range": RelationshipType.RANGES.get(t, [0, 0])})
	var key := RelationshipEdge.edge_key(a, b, t)
	var e: RelationshipEdge = null
	if _edges.has(key):
		e = _edges[key]
	else:
		e = RelationshipEdge.new()
		e.setup(a, b, t, day)
		_edges[key] = e
	e.score = score
	e.state = state
	return OperationResult.ok()


## 只读查询（RG-2 复合键寻址）；不存在返回 null
func edge_of(a: String, b: String, t: int) -> RelationshipEdge:
	var v = _edges.get(RelationshipEdge.edge_key(a, b, t), null)
	if v == null:
		return null
	return v as RelationshipEdge


## 某实体的全部边（无序对两侧命中）
func edges_of(entity_id: String) -> Array:
	var out: Array = []
	for key in _edges.keys():
		var e = _edges[key]
		if e is RelationshipEdge and e.involves(entity_id):
			out.append(e)
	return out


## 全边快照（规则面/回放用）
func all_edges() -> Array:
	var out: Array = []
	for key in _edges.keys():
		var e = _edges[key]
		if e is RelationshipEdge:
			out.append(e)
	return out


## 解散边（软删除：state=DISSOLVED 保留事实，SV-4 可回放）；不存在返回 false
func dissolve(a: String, b: String, t: int) -> bool:
	var e := edge_of(a, b, t)
	if e == null:
		return false
	e.state = RelationshipEdge.State.DISSOLVED
	return true


func edge_count() -> int:
	return _edges.size()


## SV-1 图切片导出（Owner 自负责，GameState 禁代写 RF-R11）
func to_save() -> Array:
	var out: Array = []
	for key in _edges.keys():
		var e = _edges[key]
		if e is RelationshipEdge:
			out.append(e.to_dict())
	return out


## SV-1 图切片恢复（SV-3 顺序位：State 先于呈现）
func from_save(data: Array) -> void:
	_edges.clear()
	for d in data:
		if d is Dictionary:
			var e := RelationshipEdge.new()
			e.from_dict(d)
			_edges[RelationshipEdge.edge_key(e.min_id, e.max_id, e.type)] = e
