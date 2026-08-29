# services/bond/master_service.gd
# 师徒服务（结缘系统模块18 · M4：师徒分支）
# 只读 BondService 好感度，不重写好感逻辑；不持有 Node（铁律）。
# 跨模块只走 EventBus；存档走 SaveManager（key="master"）。
#
# 双向模型：
#   - masters:     NPC 是你的师父（你拜入其门下，is_masterable 触发）
#   - apprentices: NPC 是你的徒弟（你收其为徒，前向兼容，暂无量产配置）
# 所有阈值走 relations.json 的 is_masterable + master_affection(可选, 默认60) + teachable_abilities/graduation_level。
# 与 RomanceService/SwornService 同构——UI 走 RelationshipService 统一关系图消费，不耦合本服务。

extends ISaveable
class_name MasterService

# role 约定（bond_master_set 第二参数）：0 = npc 是玩家师父；1 = npc 是玩家徒弟
const ROLE_MASTER := 0
const ROLE_APPRENTICE := 1

# === 运行时状态（全部进存档） ===
var masters: Dictionary = {}       # npc_id -> {grade_level, teachable_abilities: Array}
var apprentices: Dictionary = {}   # npc_id -> {grade_level}

# === 配置读取辅助 ===
func _is_masterable(npc_id: String) -> bool:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	return not npc.is_empty() and bool(npc.get("is_masterable", false))

func _master_affection(npc_id: String) -> int:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	return int(npc.get("master_affection", 60))

# === 查询 ===
# npc 是否已是你的师父
func is_master(npc_id: String) -> bool:
	return masters.has(npc_id)

# npc 是否已是你的徒弟
func is_apprentice(npc_id: String) -> bool:
	return apprentices.has(npc_id)

func get_master_count() -> int:
	return masters.size()

func get_apprentice_count() -> int:
	return apprentices.size()

func get_masters() -> Array:
	return masters.keys()

func get_apprentices() -> Array:
	return apprentices.keys()

# 某师父可传授的武学（配置 teachable_abilities）
func get_teachable_abilities(npc_id: String) -> Array:
	if not masters.has(npc_id):
		return []
	return Array(masters[npc_id].get("teachable_abilities", []))

# 某师父/徒弟当前阶位
func get_grade_level(npc_id: String) -> int:
	if masters.has(npc_id):
		return int(masters[npc_id].get("grade_level", 1))
	if apprentices.has(npc_id):
		return int(apprentices[npc_id].get("grade_level", 1))
	return 0

# === 拜师（npc 是师父，玩家为其徒） ===
func can_apprentice(npc_id: String) -> bool:
	if not _is_masterable(npc_id):
		return false
	if is_master(npc_id):
		return false
	if GameManager.bond_service.get_affection(npc_id) < _master_affection(npc_id):
		return false
	return true

func become_apprentice(npc_id: String) -> Dictionary:
	if is_master(npc_id):
		return {"ok": false, "reason": "ALREADY_MASTER"}
	if not _is_masterable(npc_id):
		return {"ok": false, "reason": "NOT_MASTERABLE"}
	if GameManager.bond_service.get_affection(npc_id) < _master_affection(npc_id):
		return {"ok": false, "reason": "AFFECTION_NOT_FULL"}
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	masters[npc_id] = {
		"grade_level": int(npc.get("graduation_level", 10)),
		"teachable_abilities": Array(npc.get("teachable_abilities", [])),
	}
	EventBus.bond_master_set.emit(npc_id, ROLE_MASTER)
	EventBus.bond_relationship_changed.emit()
	return {"ok": true, "reason": "SUCCESS"}

# === 收徒（npc 是徒弟，玩家为其师；前向兼容，暂无 is_apprenticeable 配置门控） ===
func can_take_apprentice(npc_id: String) -> bool:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return false
	if is_apprentice(npc_id):
		return false
	return true

func take_apprentice(npc_id: String) -> Dictionary:
	if is_apprentice(npc_id):
		return {"ok": false, "reason": "ALREADY_APPRENTICE"}
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return {"ok": false, "reason": "NPC_NOT_FOUND"}
	apprentices[npc_id] = {"grade_level": 1}
	EventBus.bond_master_set.emit(npc_id, ROLE_APPRENTICE)
	EventBus.bond_apprentice_taken.emit(npc_id)
	EventBus.bond_relationship_changed.emit()
	return {"ok": true, "reason": "SUCCESS"}

# 师徒阶位提升（出师/授艺进度；前向兼容）
func advance_grade(npc_id: String, delta: int = 1) -> bool:
	if masters.has(npc_id):
		var rec: Dictionary = masters[npc_id]
		rec["grade_level"] = int(rec.get("grade_level", 1)) + delta
		masters[npc_id] = rec
		EventBus.bond_relationship_changed.emit()
		return true
	if apprentices.has(npc_id):
		var rec: Dictionary = apprentices[npc_id]
		rec["grade_level"] = int(rec.get("grade_level", 1)) + delta
		apprentices[npc_id] = rec
		EventBus.bond_relationship_changed.emit()
		return true
	return false

# === 重置 / 存档 ===
func reset() -> void:
	masters.clear()
	apprentices.clear()

func get_save_key() -> String:
	return "master"

func save() -> Dictionary:
	return {
		"masters": masters.duplicate(true),
		"apprentices": apprentices.duplicate(true),
	}

func load(data: Dictionary) -> void:
	masters = data.get("masters", {})
	apprentices = data.get("apprentices", {})
