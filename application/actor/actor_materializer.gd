# application/actor/actor_materializer.gd
# 06 图批1 ③（AM-1~AM-3 / 冻结项 2·8）：Materialization 四相循环骨架（VS-005）。
#   World State → Materialize → Actor Runtime → Active → Dematerialize → World State → Rematerialize
# AM-3：Application 层服务（RefCounted）；输入=NPC Definition（05 收编源）+ World State
#   （NpcStateOwner）；输出=ActorRuntime；本类零 Node——TownScene Node2D 实体化接线归 Phase2。
# AM-2：Scene 非事实源——dematerialize 先回写事实到 Owner 再弃皮；_npc_nodes 类渲染索引
#   禁业务读写（A-R04/GATE05）。
# SV-3：读档恢复顺序=State 先于 Node——materialize 只从 Owner 事实灌皮，禁先造皮再灌状态。
# A-R05：Rematerialize 后状态逐字段一致（tests/unit/test_actor_skeleton.gd 回放断言）。

class_name ActorMaterializer
extends RefCounted

var _owner: NpcStateOwner
var _runtimes: Dictionary = {}   # entity_id(String) -> NPCActorRuntime；本批=纯记录索引（非渲染层）


func _init(state_owner: NpcStateOwner) -> void:
	_owner = state_owner


## 相一：World State → Actor Runtime（皮从事实里长出来）
func materialize(def: NPCDefinition) -> NPCActorRuntime:
	var st := _owner.ensure_state(def.id)
	var rt := NPCActorRuntime.new()
	rt.entity_id = def.id
	rt.position = st.position
	rt.status = st.status
	rt.is_active = true
	_runtimes[def.id] = rt
	return rt


## 相二：Actor Runtime → World State（事实落 Owner，皮可弃）；无皮返回 false
func dematerialize(entity_id: String) -> bool:
	var rt := runtime_of(entity_id)
	if rt == null:
		return false
	var st := _owner.ensure_state(entity_id)
	st.position = rt.position
	st.status = rt.status
	rt.is_active = false
	_runtimes.erase(entity_id)
	return true


## 相三：Dematerialize + Materialize（A-R05 断言面：前后状态逐字段一致）
func rematerialize(def: NPCDefinition) -> NPCActorRuntime:
	dematerialize(def.id)
	return materialize(def)


## 只读取皮；不存在返回 null
func runtime_of(entity_id: String) -> NPCActorRuntime:
	var v = _runtimes.get(entity_id, null)
	if v == null:
		return null
	return v as NPCActorRuntime


func is_materialized(entity_id: String) -> bool:
	return _runtimes.has(entity_id)


func materialized_count() -> int:
	return _runtimes.size()
