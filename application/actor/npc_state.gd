# application/actor/npc_state.gd
# 06 图批1 ④（NP-1 四态之二 / NP-2 白名单）：NPCState —— Runtime 可变态。
# NP-2 白名单六项（01 §37 原文，之外进 NPCState 即违例 → A-R02/GATE25）：
#   位置 · 生命 · 当前状态 · 当前任务状态 · 当前日程状态 · Runtime Flags。
# NP-5：schedule_ref 只留挂点不建日程（VS-004 范围，YAGNI）。
# NP-3 禁存清单（A-R03/GATE22）：Node/Scene/Texture/UI 不得出现——本类无此类字段（构造即防）。
# status 值域 = UnitStatus（autoload/game_state：ALIVE=0/DOWNED=1/DEAD=2）；
#   Phase2 _unit_runtime 迁入时枚举随 Owner 收编 NPC 域。Vector2 出入 dict 一律 JSON 归一化
#   （宪法硬规：Variant(Vector2) JSON 往返不等）。

class_name NPCState
extends RefCounted

const WHITELIST_KEYS := ["position", "health", "status", "quest_state", "schedule_ref", "runtime_flags"]

var position: Vector2 = Vector2.ZERO   # 位置
var health: int = 0                    # 生命
var status: int = 0                    # 当前状态（UnitStatus；0=ALIVE 防误判默认）
var quest_state: String = ""           # 当前任务状态（Quest Owner 的只读镜像键，Phase2 接线）
var schedule_ref: String = ""          # 当前日程状态（NP-5 挂点，空=无日程）
var runtime_flags: Dictionary = {}     # Runtime Flags（全量持久化面，SV-1）


## 持久化形态：六键全出；Vector2 → [x, y]
func to_dict() -> Dictionary:
	return {
		"position": [position.x, position.y],
		"health": health,
		"status": status,
		"quest_state": quest_state,
		"schedule_ref": schedule_ref,
		"runtime_flags": runtime_flags.duplicate(true),
	}


## 从持久化形态恢复；接受 [x,y] 数组或 Vector2（宽容读档）
func from_dict(d: Dictionary) -> void:
	var pos = d.get("position", [0.0, 0.0])
	if pos is Vector2:
		position = pos
	elif pos is Array and pos.size() >= 2:
		position = Vector2(float(pos[0]), float(pos[1]))
	health = int(d.get("health", 0))
	status = int(d.get("status", 0))
	quest_state = str(d.get("quest_state", ""))
	schedule_ref = str(d.get("schedule_ref", ""))
	var flags = d.get("runtime_flags", {})
	if flags is Dictionary:
		runtime_flags = flags.duplicate(true)
	else:
		runtime_flags = {}


## 逐字段一致性比较（A-R05 回放断言的比对面）
func equals_state(other: NPCState) -> bool:
	if other == null:
		return false
	return position == other.position \
		and health == other.health \
		and status == other.status \
		and quest_state == other.quest_state \
		and schedule_ref == other.schedule_ref \
		and runtime_flags == other.runtime_flags


func duplicate_state() -> NPCState:
	var st := NPCState.new()
	st.from_dict(to_dict())
	return st
