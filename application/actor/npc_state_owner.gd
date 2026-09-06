# application/actor/npc_state_owner.gd
# 06 图批1 ②（§7 State Owner 落位 / 冻结项 6·8）：NPC Runtime State 唯一 Owner。
# Owner=NPC 模块（01 §38 基线），非 GameState。现状 GameState._unit_runtime 的迁移目标
#   （§10 Phase2；AC-2 追认）——本批=落位骨架零破坏：Owner 先立，存量迁移随 Phase2。
# 命令化前置（SC-2 / A-R06）：下列写入口即未来 Command 的执行端形状——Phase2 起
#   Actor Tick 禁直改 Domain State，必经 Command → 本执行端。
# 白名单纪律（NP-2/A-R02）：本 Owner 只持 NPCState（六项）；_unit_runtime 现存的
#   faction → Actor Faction Ref 组件（AC-1）、affinity → 08 Relationship 域，迁移时各归其主，
#   不得塞进本 Owner。
# 存量迁移映射（Phase2 机械执行）：GameState.get_unit_status/set_unit_status/
#   apply_combat_snapshot → 本类同名语义；默认 ALIVE(0) 防误判语义原样保留（§1.1）。

class_name NpcStateOwner
extends RefCounted

const STATUS_ALIVE := 0    # UnitStatus 镜像（Phase2 枚举收编前先以常量锚定）
const STATUS_DOWNED := 1
const STATUS_DEAD := 2

var _states: Dictionary = {}   # unit_id(String) -> NPCState；Owner 唯一事实面


## 取或建（写路径）：默认 ALIVE 防误判
func ensure_state(unit_id: String) -> NPCState:
	if not _states.has(unit_id):
		var st := NPCState.new()
		_states[unit_id] = st
		return st
	var v = _states[unit_id]
	return v as NPCState


## 只读取（读路径）：不隐式创建——防读侧误写状态面；不存在返回 null
func state_of(unit_id: String) -> NPCState:
	var v = _states.get(unit_id, null)
	if v == null:
		return null
	return v as NPCState


func has_state(unit_id: String) -> bool:
	return _states.has(unit_id)


## 当前状态（缺省 ALIVE 防误判——§1.1 既有语义）
func status_of(unit_id: String) -> int:
	var st := state_of(unit_id)
	if st == null:
		return STATUS_ALIVE
	return st.status


## 写当前状态（Command 执行端形状；Phase2 前由存量兼容层调用）
func set_unit_status(unit_id: String, status: int) -> void:
	ensure_state(unit_id).status = status


## 战斗快照回写（§1.1 既有语义镜像：[{unit_id, status}, ...]）
func apply_combat_snapshot(snapshots: Array) -> void:
	for snap in snapshots:
		if snap is Dictionary:
			var uid := str(snap.get("unit_id", ""))
			if uid != "":
				set_unit_status(uid, int(snap.get("status", STATUS_ALIVE)))


## 存档切片导出（SV-1：Owner 自负责，GameState 禁代写）
func export_save() -> Dictionary:
	var out: Dictionary = {}
	for unit_id in _states.keys():
		var st = _states[unit_id]
		if st is NPCState:
			out[str(unit_id)] = NPCSaveDTO.from_state(st).to_dict()
	return out


## 存档切片恢复（SV-3 顺序位：State 先于 Materialize）
func import_save(data: Dictionary) -> void:
	_states.clear()
	for unit_id in data.keys():
		var st := NPCState.new()
		var raw = data[unit_id]
		if raw is Dictionary:
			st.from_dict(raw)
		_states[str(unit_id)] = st


func clear() -> void:
	_states.clear()


func state_count() -> int:
	return _states.size()
