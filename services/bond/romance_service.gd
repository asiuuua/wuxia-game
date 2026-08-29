# services/bond/romance_service.gd
# 姻缘服务（结缘系统模块18 · M2：姻缘/婚姻分支）
# 只读 BondService 好感度，不重写好感逻辑；不持有 Node（铁律）。
# 跨模块只走 EventBus；存档走 SaveManager（key="romance"）。
#
# 可扩展性：配偶名单以 npc_id 为键存 Dictionary，天然无限；所有阈值/类型走 relations.json 的 romance 块；
# 子嗣(寝欢+怀胎十月)为预留数据层——时间源解耦为 advance_days(n)，由 TimeService 或休息动作后续喂天数。

extends ISaveable
class_name RomanceService

# === 运行时状态（全部进存档） ===
var spouses: Dictionary = {}          # npc_id -> {stage, wed_day, children: Array[String], pregnancy: Dictionary}
var children: Dictionary = {}         # child_id -> {mother_id, born_day, name}

# === 配置读取辅助 ===
func _romance_cfg(npc_id: String) -> Dictionary:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return {}
	return npc.get("romance", {})

func _is_romanceable(npc_id: String) -> bool:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	return not npc.is_empty() and bool(npc.get("is_romanceable", false))

# === 异性校验：玩家性别与 NPC required_gender 匹配；required_gender<0 表示不限 ===
func _gender_ok(npc_id: String) -> bool:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return false
	var req: int = int(npc.get("required_gender", -1))
	if req < 0:
		return true
	var pg: int = int(GameManager.player_state.gender)
	return pg == req

func _propose_affection(npc_id: String) -> int:
	var cfg: Dictionary = _romance_cfg(npc_id)
	return int(cfg.get("propose_affection", 100))

# === 查询 ===
# 是否已是配偶
func is_spouse(npc_id: String) -> bool:
	return spouses.has(npc_id)

# 某配偶是否处于孕期（寝欢后、分娩前）
func is_pregnant(npc_id: String) -> bool:
	if not spouses.has(npc_id):
		return false
	return not spouses[npc_id].get("pregnancy", {}).is_empty()

# 配偶数（天然无限，无上限）
func get_spouse_count() -> int:
	return spouses.size()

# 全部配偶 npc_id 列表
func get_spouses() -> Array:
	return spouses.keys()

# 某 NPC 当前姻缘阶段
func get_romance_stage(npc_id: String) -> int:
	if not spouses.has(npc_id):
		return BondEnums.RomanceStage.COURTING
	return int(spouses[npc_id].get("stage", BondEnums.RomanceStage.COURTING))

# 某 NPC 姻缘阶段中文名
func get_romance_stage_name(npc_id: String) -> String:
	return BondEnums.romance_stage_name(get_romance_stage(npc_id))

# 某配偶的子嗣 id 列表
func get_children_of(npc_id: String) -> Array:
	if not spouses.has(npc_id):
		return []
	return spouses[npc_id].get("children", [])

# 全部子嗣 id 列表
func get_all_children() -> Array:
	return children.keys()

# === 求婚 / 结婚 ===
# 能否求婚：可结缘 + 性别匹配 + 好感满 propose_affection + 还不是配偶
func can_propose(npc_id: String) -> bool:
	if not _is_romanceable(npc_id):
		return false
	if not _gender_ok(npc_id):
		return false
	if is_spouse(npc_id):
		return false
	if GameManager.bond_service.get_affection(npc_id) < _propose_affection(npc_id):
		return false
	return true

# 当前可求婚的 NPC id 列表（可结缘 + 好感达标 + 还不是配偶），供 HUD 红点与面板候选使用
func get_marriageable_npc_ids() -> Array:
	var out: Array = []
	for npc_id in ConfigManager.get_all_relation_ids():
		var npc: Dictionary = ConfigManager.get_relation(npc_id)
		if npc.is_empty():
			continue
		if not bool(npc.get("is_romanceable", false)):
			continue
		if is_spouse(npc_id):
			continue
		if can_propose(npc_id):
			out.append(npc_id)
	return out

# 求婚：通过则写入配偶名单、推进到已婚阶段、广播事件；聘礼不足则拒绝
func propose(npc_id: String) -> Dictionary:
	if is_spouse(npc_id):
		return {"ok": false, "reason": "ALREADY_SPOUSE", "stage": get_romance_stage(npc_id)}
	if not _is_romanceable(npc_id):
		return {"ok": false, "reason": "NOT_ROMANCEABLE", "stage": -1}
	if not _gender_ok(npc_id):
		return {"ok": false, "reason": "GENDER_MISMATCH", "stage": -1}
	if GameManager.bond_service.get_affection(npc_id) < _propose_affection(npc_id):
		return {"ok": false, "reason": "AFFECTION_NOT_FULL", "stage": -1}
	var cfg: Dictionary = _romance_cfg(npc_id)
	var dowry: Array = cfg.get("dowry_required", [])
	for item_id in dowry:
		if GameManager.inventory_service.get_item_count(String(item_id)) <= 0:
			return {"ok": false, "reason": "DOWRY_MISSING", "stage": -1}
	for item_id in dowry:
		GameManager.inventory_service.remove_item_by_id(String(item_id), 1)
	var rec: Dictionary = {
		"stage": BondEnums.RomanceStage.MARRIED,
		"wed_day": int(Time.get_unix_time_from_system()),
		"children": [],
		"pregnancy": {},
	}
	spouses[npc_id] = rec
	EventBus.bond_romance_formed.emit(npc_id, rec["stage"])
	# 婚礼演出信号（UI 婚礼场景消费；scene_path 取自 relations.json 的 wedding_scene）
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	var wt: int = BondEnums.wedding_type_from_name(String(cfg.get("wedding_type", "NORMAL")))
	var scene_path: String = String(npc.get("wedding_scene", ""))
	EventBus.bond_wedding_started.emit(npc_id, wt, scene_path)
	EventBus.bond_relationship_changed.emit()
	return {"ok": true, "reason": "SUCCESS", "stage": rec["stage"]}

# === 关系网数据（预留对接点） ===
# 返回整张关系图给关系网视图消费；后续可并入结义/师徒
func get_relationship_graph() -> Dictionary:
	var graph: Dictionary = {"spouses": [], "children": [], "sworn": [], "master": ""}
	for npc_id in spouses.keys():
		var rec: Dictionary = spouses[npc_id]
		graph["spouses"].append({
			"npc_id": npc_id,
			"stage": int(rec.get("stage", BondEnums.RomanceStage.COURTING)),
			"stage_name": BondEnums.romance_stage_name(int(rec.get("stage", BondEnums.RomanceStage.COURTING))),
			"children": rec.get("children", []),
		})
	for cid in children.keys():
		var c: Dictionary = children[cid]
		graph["children"].append({
			"child_id": cid,
			"mother_id": c.get("mother_id", ""),
			"born_day": int(c.get("born_day", 0)),
			"name": c.get("name", ""),
		})
	return graph

# === 子嗣（预留数据层：寝欢 + 怀胎十月，时间源解耦） ===
# 寝欢：配偶且已婚才可；启动孕期计时（游戏时间由 advance_days 推进）
func begin_intimacy(npc_id: String) -> Dictionary:
	if not is_spouse(npc_id):
		return {"ok": false, "reason": "NOT_SPOUSE"}
	if get_romance_stage(npc_id) != BondEnums.RomanceStage.MARRIED:
		return {"ok": false, "reason": "NOT_MARRIED"}
	var rec: Dictionary = spouses[npc_id]
	if not rec.get("pregnancy", {}).is_empty():
		return {"ok": false, "reason": "ALREADY_PREGNANT"}
	rec["pregnancy"] = {
		"start_day": int(Time.get_unix_time_from_system()),
		"gestation_days": 300,
		"progress": 0,
	}
	spouses[npc_id] = rec
	EventBus.bond_relationship_changed.emit()
	return {"ok": true, "reason": "SUCCESS"}

# 推进游戏天数：孕期进度累加，满 gestation_days 则分娩（由 TimeService/休息动作喂天数）
func advance_days(n: int) -> void:
	if n <= 0:
		return
	for npc_id in spouses.keys():
		var rec: Dictionary = spouses[npc_id]
		var preg: Dictionary = rec.get("pregnancy", {})
		if preg.is_empty():
			continue
		preg["progress"] = int(preg.get("progress", 0)) + n
		var due: int = int(preg.get("gestation_days", 300))
		if preg["progress"] >= due:
			_birth(npc_id, rec)
		else:
			rec["pregnancy"] = preg
			spouses[npc_id] = rec

func _birth(npc_id: String, rec: Dictionary) -> void:
	var cid: String = "child_%s_%d" % [npc_id, children.size() + 1]
	children[cid] = {
		"mother_id": npc_id,
		"born_day": int(Time.get_unix_time_from_system()),
		"name": "子嗣%d" % (children.size() + 1),
	}
	var kids: Array = rec.get("children", [])
	kids.append(cid)
	rec["children"] = kids
	rec["pregnancy"] = {}
	spouses[npc_id] = rec
	EventBus.bond_child_born.emit(npc_id, cid)
	EventBus.bond_relationship_changed.emit()

# === 重置 / 存档 ===
func reset() -> void:
	spouses.clear()
	children.clear()

func get_save_key() -> String:
	return "romance"

func save() -> Dictionary:
	return {"spouses": spouses.duplicate(true), "children": children.duplicate(true)}

func load(data: Dictionary) -> void:
	spouses = data.get("spouses", {})
	children = data.get("children", {})
