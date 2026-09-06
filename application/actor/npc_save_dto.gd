# application/actor/npc_save_dto.gd
# 06 图批1 ④（NP-1 四态之三 / SV-1）：NPCSaveDTO —— 存档切片。
# SV-1：NPCSaveDTO = NP-2 白名单六项的持久化子集——位置/日程态按需、Flags 全量；
#   各自 Owner 负责 export/import，GameState 禁代写（A-R10/GATE05）。
# 本批切片面：position + status + schedule_ref + runtime_flags（生命归 Progression 域、
#   任务状态归 Quest 域——事实各归其主，持久化面同口径）。
# SV-2：切片随 SAVE_VERSION 1.1.0 迁移链走（LN-G09）；字段新增=MINOR，结构变更=MAJOR+迁移步。
# NP-3：禁存 Node/Scene/Texture/UI（构造即防 + 测试锚）。

class_name NPCSaveDTO
extends RefCounted

var position: Vector2 = Vector2.ZERO
var status: int = 0
var schedule_ref: String = ""
var runtime_flags: Dictionary = {}


static func from_state(state: NPCState) -> NPCSaveDTO:
	var dto := NPCSaveDTO.new()
	if state != null:
		dto.position = state.position
		dto.status = state.status
		dto.schedule_ref = state.schedule_ref
		dto.runtime_flags = state.runtime_flags.duplicate(true)
	return dto


func apply_to(state: NPCState) -> void:
	if state == null:
		return
	state.position = position
	state.status = status
	state.schedule_ref = schedule_ref
	state.runtime_flags = runtime_flags.duplicate(true)


## 存档形态（JSON 安全：Vector2 → [x, y]）
func to_dict() -> Dictionary:
	return {
		"position": [position.x, position.y],
		"status": status,
		"schedule_ref": schedule_ref,
		"runtime_flags": runtime_flags.duplicate(true),
	}


func from_dict(d: Dictionary) -> void:
	var pos = d.get("position", [0.0, 0.0])
	if pos is Vector2:
		position = pos
	elif pos is Array and pos.size() >= 2:
		position = Vector2(float(pos[0]), float(pos[1]))
	status = int(d.get("status", 0))
	schedule_ref = str(d.get("schedule_ref", ""))
	var flags = d.get("runtime_flags", {})
	if flags is Dictionary:
		runtime_flags = flags.duplicate(true)
	else:
		runtime_flags = {}
