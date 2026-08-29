# services/bond/sworn_service.gd
# 结义服务（结缘系统模块18 · M4：结义分支）
# 只读 BondService 好感度，不重写好感逻辑；不持有 Node（铁律）。
# 跨模块只走 EventBus；存档走 SaveManager（key="sworn"）。
#
# 可扩展性：结义兄弟以 npc_id 为键存 Dictionary，天然无限（可同时与多人结义）；
# 所有阈值/能力走 relations.json 的 is_swornable + sworn_affection(可选, 默认80) + sworn_ability/sworn_passive；
# 与 RomanceService 同构——UI 走 RelationshipService 统一关系图消费，不耦合本服务。

extends ISaveable
class_name SwornService

# === 运行时状态（全部进存档） ===
var sworn_brothers: Dictionary = {}   # npc_id -> {sworn_day, ability, passive}

# === 配置读取辅助 ===
func _is_swornable(npc_id: String) -> bool:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	return not npc.is_empty() and bool(npc.get("is_swornable", false))

func _sworn_affection(npc_id: String) -> int:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	return int(npc.get("sworn_affection", 80))

# === 查询 ===
# 是否已结义
func is_sworn(npc_id: String) -> bool:
	return sworn_brothers.has(npc_id)

# 结义人数（天然无限，无上限）
func get_sworn_count() -> int:
	return sworn_brothers.size()

# 全部结义兄弟 npc_id 列表
func get_sworn_brothers() -> Array:
	return sworn_brothers.keys()

# 某结义兄弟的能力（结义奖励，UI 展示用）
func get_sworn_ability(npc_id: String) -> String:
	if not sworn_brothers.has(npc_id):
		return ""
	return String(sworn_brothers[npc_id].get("ability", ""))

# === 结义 ===
# 能否结义：可结义 + 还不是兄弟 + 好感满 sworn_affection
func can_sworn(npc_id: String) -> bool:
	if not _is_swornable(npc_id):
		return false
	if is_sworn(npc_id):
		return false
	if GameManager.bond_service.get_affection(npc_id) < _sworn_affection(npc_id):
		return false
	return true

# 结义：通过则写入兄弟名单、广播事件
func sworn(npc_id: String) -> Dictionary:
	if is_sworn(npc_id):
		return {"ok": false, "reason": "ALREADY_SWORN"}
	if not _is_swornable(npc_id):
		return {"ok": false, "reason": "NOT_SWORNABLE"}
	if GameManager.bond_service.get_affection(npc_id) < _sworn_affection(npc_id):
		return {"ok": false, "reason": "AFFECTION_NOT_FULL"}
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	sworn_brothers[npc_id] = {
		"sworn_day": int(Time.get_unix_time_from_system()),
		"ability": String(npc.get("sworn_ability", "")),
		"passive": String(npc.get("sworn_passive", "")),
	}
	# stage=1 表示结义达成（与 bond_sworn_formed 的 int 参数约定一致）
	EventBus.bond_sworn_formed.emit(npc_id, 1)
	EventBus.bond_relationship_changed.emit()
	return {"ok": true, "reason": "SUCCESS"}

# === 重置 / 存档 ===
func reset() -> void:
	sworn_brothers.clear()

func get_save_key() -> String:
	return "sworn"

func save() -> Dictionary:
	return {"sworn_brothers": sworn_brothers.duplicate(true)}

func load(data: Dictionary) -> void:
	sworn_brothers = data.get("sworn_brothers", {})
