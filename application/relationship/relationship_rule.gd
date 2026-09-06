# application/relationship/relationship_rule.gd
# 08 图批1 ①（RG-4）：RelationshipRule —— 图内规则挂点。
# RG-4：只做图内判定（阈值/衰减/互斥如「已婚禁新结义」——跨模块互斥走 Query 查询
#   他模块只读投影，禁反向直写 RF-R04）。
# TY-4 启用三件套之第三件：新关系型启用=枚举+量程+规则齐备——本基类即规则承载面，
#   子类按 Type 注册到 Graph（批2 接 upsert 前置校验链）。
# 载体 RefCounted 零 Node（RG-5 同源）。

class_name RelationshipRule
extends RefCounted

## 规则 id（审计/回放足迹用）
var rule_id: StringName = &"REL_RULE_BASE"


## 图内判定：返回 ok 放行 / fail 拒绝（code+context 五元组同 0-C 语义）
## 默认实现=放行（无规则）；子类必须覆写并保留 rule_id 唯一性。
func evaluate(_graph: RelationshipGraph, _edge: RelationshipEdge) -> OperationResult:
	return OperationResult.ok()
