# application/relationship/relationship_edge.gd
# 08 图批1 ①（RG-2/RG-3）：RelationshipEdge —— 图的最小事实单元。
# Edge 键冻结（RG-2）：{min_id, max_id}（无序对，字典序排定）+ type 复合键；
#   有向语义（MASTER→DISCIPLE）内含于 Type，不另设方向标志（§11 RF-2）。
# Edge 值冻结：{score: int, state: enum, since_day: int}。
# RF-R03：禁以显示名/单 ID 为键——本类构造即按无序对归一（min/max 字典序）。

class_name RelationshipEdge
extends RefCounted

enum State { PENDING, ACTIVE, DISSOLVED }

var min_id: String = ""    # 无序对字典序小端
var max_id: String = ""    # 无序对字典序大端
var type: int = RelationshipType.Type.FRIEND
var score: int = 0         # RG-3：每 Type 独立量程；状态型恒 0
var state: int = State.ACTIVE
var since_day: int = 0     # 游戏日真源（宪法 §79；随边建立定格）


## 无序对归一：返回 [min_id, max_id]（字典序）
static func ordered_pair(a: String, b: String) -> Array:
	if a <= b:
		return [a, b]
	return [b, a]


## RG-2 复合键："min|max|type"（图内唯一）
static func edge_key(a: String, b: String, t: int) -> String:
	var pair := ordered_pair(a, b)
	return "%s|%s|%d" % [pair[0], pair[1], t]


func setup(a: String, b: String, t: int, day: int) -> void:
	var pair := ordered_pair(a, b)
	min_id = pair[0]
	max_id = pair[1]
	type = t
	since_day = day


## 该边是否涉及某端点（含无序对两侧）
func involves(entity_id: String) -> bool:
	return min_id == entity_id or max_id == entity_id


## 该端点在本边中的对端 id
func other_of(entity_id: String) -> String:
	if min_id == entity_id:
		return max_id
	if max_id == entity_id:
		return min_id
	return ""


func to_dict() -> Dictionary:
	return {
		"min_id": min_id,
		"max_id": max_id,
		"type": type,
		"score": score,
		"state": state,
		"since_day": since_day,
	}


func from_dict(d: Dictionary) -> void:
	min_id = str(d.get("min_id", ""))
	max_id = str(d.get("max_id", ""))
	type = int(d.get("type", 0))
	score = int(d.get("score", 0))
	state = int(d.get("state", State.ACTIVE))
	since_day = int(d.get("since_day", 0))


## SV-1 图切片往返一致性断言面
func equals_edge(other: RelationshipEdge) -> bool:
	if other == null:
		return false
	return min_id == other.min_id and max_id == other.max_id and type == other.type \
		and score == other.score and state == other.state and since_day == other.since_day
