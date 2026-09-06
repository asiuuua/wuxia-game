# application/actor/actor_identity.gd
# 06 图批1 ②（AC-3 / 冻结项 1·8）：Actor Carrier 双层载体之「唯一事实锚」层。
#   ActorIdentity（RefCounted）= EntityId + 类型 + 存活态；事实永远在这里。
#   ActorRuntime（场景侧呈现态）可销毁重建，两者以 EntityId 关联（AM-2：皮可撕，事实不能丢）。
# AC-2 禁吞清单（机器可查 → A-R01/GATE25）：本类禁出现 Quest / Relationship / Inventory /
#   Economy / Faction / Family / Combat / World 任一状态字段——模块事实各归其主（06 图 §7）。
# Player 与 NPC 共用同一 Carrier 契约（AC-4），差异只在挂载 Ref 集合与调度档位（批2+）。

class_name ActorIdentity
extends RefCounted

enum ActorType { PLAYER, NPC, ENEMY }
enum AliveState { ALIVE, DEAD }

var entity_id: EntityId          # 身份锚（kernel 只持 ID，AC-1 Ref=引用 ID 非内嵌对象）
var actor_type: int = ActorType.NPC
var alive_state: int = AliveState.ALIVE


static func of(id: EntityId, type: int) -> ActorIdentity:
	var a := ActorIdentity.new()
	a.entity_id = id
	a.actor_type = type
	return a


func is_alive() -> bool:
	return alive_state == AliveState.ALIVE


## 审计面：稳定描述（不含显示名——ID 不依赖名称，宪法第 26 节）
func describe() -> String:
	return "ActorIdentity(%s type=%d alive=%d)" % [str(entity_id), actor_type, alive_state]
