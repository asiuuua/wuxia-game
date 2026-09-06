# application/relationship/relationship_type.gd
# 08 图批1 ①（TY-1/TY-3/RG-3）：关系十型统一登记。
# TY-1 十型（宪法原文全列）：FRIEND·RESPECT·TRUST·HATRED·ROMANCE·FAMILY·
#   MASTER·DISCIPLE·SWORN·FACTION。
# RG-3 量程：每 Type 独立量程，禁跨 Type 共用。好感（AFFECTION）按 TY-2 实现为
#   FRIEND/RESPECT/TRUST/HATRED 四象的复合 score（0-100 沿用现值，等级名沿用
#   affection_levels）；SWORN/MASTER/DISCIPLE 为状态型（无分值，state 表达）。
# TY-3 只读投影：ROMANCE（配偶真源=Marriage 模块）与 FACTION（成员真源=FactionMember
#   名册）在图中只经投影同步写入（upsert_projection），禁业务直写。
# TY-4 启用三件套：枚举+量程+规则齐备才许启用；未启用型 upsert 拒收（FAMILY 预留）。

class_name RelationshipType
extends RefCounted

enum Type {
	FRIEND = 0,
	RESPECT = 1,
	TRUST = 2,
	HATRED = 3,
	ROMANCE = 4,
	FAMILY = 5,      # 未启用（TY-4 预留）
	MASTER = 6,
	DISCIPLE = 7,
	SWORN = 8,
	FACTION = 9,
}

const TYPE_COUNT := 10

## 有向语义内含于 Type（RF-2）：MASTER 与 DISCIPLE 是两个 Type 的两条边
const DIRECTED_TYPES := [Type.MASTER, Type.DISCIPLE]

## RG-3 量程表：[min, max]；状态型 [0, 0]（score 恒 0，state 表达语义）
const RANGES := {
	Type.FRIEND: [0, 100],
	Type.RESPECT: [0, 100],
	Type.TRUST: [0, 100],
	Type.HATRED: [0, 100],
	Type.ROMANCE: [0, 100],
	Type.FAMILY: [0, 0],
	Type.MASTER: [0, 0],
	Type.DISCIPLE: [0, 0],
	Type.SWORN: [0, 0],
	Type.FACTION: [0, 0],
}

## TY-4 当前启用面：好感四象（AFFECTION 复合 score）+ 结义/师徒（状态型，真源
##   SwornService/MasterService，边=收编目标 Phase2）。FAMILY 未启用（预留）；
##   ROMANCE/FACTION 仅投影通道可写（TY-3）。
const ENABLED := [Type.FRIEND, Type.RESPECT, Type.TRUST, Type.HATRED, Type.SWORN, Type.MASTER, Type.DISCIPLE]

## 仅投影通道可写型（TY-3 只读投影：真源在 Marriage/Faction 模块）
const PROJECTION_ONLY := [Type.ROMANCE, Type.FACTION]


static func type_name(t: int) -> String:
	match t:
		Type.FRIEND: return "FRIEND"
		Type.RESPECT: return "RESPECT"
		Type.TRUST: return "TRUST"
		Type.HATRED: return "HATRED"
		Type.ROMANCE: return "ROMANCE"
		Type.FAMILY: return "FAMILY"
		Type.MASTER: return "MASTER"
		Type.DISCIPLE: return "DISCIPLE"
		Type.SWORN: return "SWORN"
		Type.FACTION: return "FACTION"
	return "UNKNOWN"


static func is_enabled(t: int) -> bool:
	return ENABLED.has(t)


static func is_projection_only(t: int) -> bool:
	return PROJECTION_ONLY.has(t)


static func is_directed(t: int) -> bool:
	return DIRECTED_TYPES.has(t)


static func is_state_based(t: int) -> bool:
	var r: Array = RANGES.get(t, [0, 0])
	return int(r[0]) == 0 and int(r[1]) == 0


## RG-3：score 是否落在该 Type 量程内
static func score_in_range(t: int, score: int) -> bool:
	var r: Array = RANGES.get(t, [0, 0])
	return score >= int(r[0]) and score <= int(r[1])
