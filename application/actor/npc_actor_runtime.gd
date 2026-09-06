# application/actor/npc_actor_runtime.gd
# 06 图批1 ④（NP-1 四态之四）：NPCActorRuntime —— 场景呈现态（「皮」）。
# AC-3：可销毁重建，与 ActorIdentity 以 EntityId 关联；销毁不得丢失任何业务状态（AM-2）。
# 本批=RefCounted 呈现记录骨架（EntityId/位置/状态镜像/激活标志）；TownScene Node2D
#   实体化接线归 Phase2（AM-4 批量 Materialize / Dematerialize 触发时机）。
# 禁存清单精神同 NP-3：本类不持 Node/Texture 引用——它是 Materializer 与未来场景节点
#   之间的纯数据中介（02 K-R02：Domain/Kernel 禁 Node；呈现装配在 scenes 侧完成）。

class_name NPCActorRuntime
extends RefCounted

var entity_id: String = ""      # 关联锚（Owner/Identity 同键）
var position: Vector2 = Vector2.ZERO
var status: int = 0             # 呈现镜像（真源在 NPCState Owner，AM-2 Scene 非事实源）
var is_active: bool = false     # Materialize=true / Dematerialize=false
