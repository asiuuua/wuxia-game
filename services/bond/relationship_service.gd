# services/bond/relationship_service.gd
# 关系网数据中枢（结缘系统模块18 · M3：关系网数据查看对接点）
# 纯聚合门面：自身不持有任何状态、不进存档、不碰 screens.json。
# 只把 BondService（好感度）与 RomanceService（配偶/子嗣/孕期）的数据拼成一张
# 统一关系图，供"关系网视图"与"右上角姻缘按钮"直接消费。
#
# 可扩展性：结义(sworn)/师徒(master) 服务建成后，只需在下方 _node_of() 里补两个
# 状态来源（与现有 is_spouse/children 同构），图即自动包含，UI 零改。
# 跨模块只走 EventBus；读走 BondService/RomanceService 公开方法，禁调其私有成员。

extends RefCounted
class_name RelationshipService

# === RM-2（08图批1 ③/DoD3）：构造注入清零 GameManager.<service> 直连（RF-R02） ===
# 四域服务由 Composition Root（GameManager._create_services / ApplicationRoot.Create）
# 构造注入；本类内禁再出现任何 GameManager.* 引用——跨模块只走公共契约（02 契约底线）。
var _bond: BondService
var _romance: RomanceService
var _sworn: SwornService
var _master: MasterService

func _init(bond: BondService, romance: RomanceService, sworn: SwornService, master: MasterService) -> void:
	_bond = bond
	_romance = romance
	_sworn = sworn
	_master = master

# === 整张关系图（UI 关系网视图 / 右上角面板直接消费） ===
## 聚合好感 + 配偶 + 子嗣 + 结义 + 师徒，返回统一关系图
## 返回 { nodes:Array, spouses:Array, children:Array, sworn:Array, masters:Array, apprentices:Array, summary:Dictionary }
func get_relationship_graph() -> Dictionary:
	var nodes: Array = []
	for npc_id in ConfigManager.get_all_relation_ids():
		nodes.append(_node_of(npc_id))
	var spouses_out: Array = []
	for npc_id in _romance.get_spouses():
		var rec: Dictionary = _romance.get_spouse_record(npc_id)
		spouses_out.append({
			"npc_id": npc_id,
			"name": _name_of(npc_id),
			"stage": int(rec.get("stage", BondEnums.RomanceStage.COURTING)),
			"stage_name": _romance.get_romance_stage_name(npc_id),
			"children": rec.get("children", []),
			"pregnant": _romance.is_pregnant(npc_id),
		})
	var children_out: Array = []
	for c in _romance.get_children_brief():
		children_out.append({
			"child_id": String(c.get("child_id", "")),
			"name": c.get("name", ""),
			"mother_id": c.get("mother_id", ""),
			"mother_name": _name_of(String(c.get("mother_id", ""))),
			"born_day": int(c.get("born_day", 0)),
		})
	var sworn_out: Array = []
	for npc_id in _sworn.get_sworn_brothers():
		sworn_out.append({
			"npc_id": npc_id,
			"name": _name_of(npc_id),
			"ability": _sworn.get_sworn_ability(npc_id),
		})
	var masters_out: Array = []
	for npc_id in _master.get_masters():
		masters_out.append({
			"npc_id": npc_id,
			"name": _name_of(npc_id),
			"grade_level": _master.get_grade_level(npc_id),
			"teachable_abilities": _master.get_teachable_abilities(npc_id),
		})
	var apprentices_out: Array = []
	for npc_id in _master.get_apprentices():
		apprentices_out.append({
			"npc_id": npc_id,
			"name": _name_of(npc_id),
			"grade_level": _master.get_grade_level(npc_id),
		})
	return {
		"nodes": nodes,
		"spouses": spouses_out,
		"children": children_out,
		"sworn": sworn_out,
		"masters": masters_out,
		"apprentices": apprentices_out,
		"summary": _summary(nodes),
	}

# === 概览统计（右上角按钮角标用） ===
## 返回 { npc_total, spouse_count, child_count, sworn_count, master_count, marriageable:Array }
func get_summary() -> Dictionary:
	var nodes: Array = []
	for npc_id in ConfigManager.get_all_relation_ids():
		nodes.append(_node_of(npc_id))
	return _summary(nodes)

# === 全部关系节点（不含 spouses/children 冗余字段，轻量列表） ===
## 返回每个可结缘/结义/师徒 NPC 的关系节点数组
func get_all_relations() -> Array:
	var nodes: Array = []
	for npc_id in ConfigManager.get_all_relation_ids():
		nodes.append(_node_of(npc_id))
	return nodes

# === 可结缘 NPC 列表（右上角"有可结缘"红点判定） ===
## 返回当前好感已满、可立即求婚的 npc_id 列表
func get_marriageable_npc_ids() -> Array:
	var out: Array = []
	for npc_id in ConfigManager.get_all_relation_ids():
		if _romance.can_propose(npc_id):
			out.append(npc_id)
	return out

# === 配偶明细（含名字，便于面板直接渲染） ===
## 返回所有配偶的 enriched 列表（name/stage/children/pregnant）
func get_spouses_enriched() -> Array:
	var out: Array = []
	for npc_id in _romance.get_spouses():
		var rec: Dictionary = _romance.get_spouse_record(npc_id)
		out.append({
			"npc_id": npc_id,
			"name": _name_of(npc_id),
			"stage": int(rec.get("stage", BondEnums.RomanceStage.COURTING)),
			"stage_name": _romance.get_romance_stage_name(npc_id),
			"children": rec.get("children", []),
			"pregnant": _romance.is_pregnant(npc_id),
		})
	return out

# === 子嗣列表（含母亲名） ===
## 返回全部子嗣的 enriched 列表
func get_children() -> Array:
	var out: Array = []
	for c in _romance.get_children_brief():
		out.append({
			"child_id": String(c.get("child_id", "")),
			"name": c.get("name", ""),
			"mother_id": c.get("mother_id", ""),
			"mother_name": _name_of(String(c.get("mother_id", ""))),
			"born_day": int(c.get("born_day", 0)),
		})
	return out

# === 结义兄弟明细（含名字） ===
## 返回所有结义兄弟的 enriched 列表
func get_sworn_enriched() -> Array:
	var out: Array = []
	for npc_id in _sworn.get_sworn_brothers():
		out.append({
			"npc_id": npc_id,
			"name": _name_of(npc_id),
			"ability": _sworn.get_sworn_ability(npc_id),
		})
	return out

# === 师父/徒弟明细（含名字与阶位） ===
## 返回所有师父的 enriched 列表（npc 是你的师父）
func get_masters_enriched() -> Array:
	var out: Array = []
	for npc_id in _master.get_masters():
		out.append({
			"npc_id": npc_id,
			"name": _name_of(npc_id),
			"grade_level": _master.get_grade_level(npc_id),
			"teachable_abilities": _master.get_teachable_abilities(npc_id),
		})
	return out

# === 内部：单个 NPC 关系节点 ===
func _node_of(npc_id: String) -> Dictionary:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	var is_sp: bool = _romance.is_spouse(npc_id)
	var stage: int = _romance.get_romance_stage(npc_id)
	var is_sw: bool = _sworn.is_sworn(npc_id)
	var is_mt: bool = _master.is_master(npc_id)
	# 关系种类（统一归类，UI 直接展示）：此 NPC 与玩家当前成立的关系
	var kinds: Array = []
	if is_sp:
		kinds.append("ROMANCE")
	if is_sw:
		kinds.append("SWORN")
	if is_mt:
		kinds.append("MASTER")
	return {
		"npc_id": npc_id,
		"name": npc.get("name", ""),
		"gender": int(npc.get("gender", 0)),
		"relation_flags": {
			"romanceable": bool(npc.get("is_romanceable", false)),
			"swornable": bool(npc.get("is_swornable", false)),
			"masterable": bool(npc.get("is_masterable", false)),
		},
		"affection": _bond.get_affection(npc_id),
		"affection_level": _bond.get_affection_level(npc_id),
		"affection_level_name": _bond.get_affection_level_name(npc_id),
		"relation_kinds": kinds,
		"is_spouse": is_sp,
		"romance_stage": stage,
		"romance_stage_name": _romance.get_romance_stage_name(npc_id),
		"is_sworn": is_sw,
		"is_master": is_mt,
		"children": _romance.get_children_of(npc_id),
		"pregnant": _romance.is_pregnant(npc_id),
		"can_propose": _romance.can_propose(npc_id),
		"can_intimacy": is_sp and stage == BondEnums.RomanceStage.MARRIED,
		"can_sworn": _sworn.can_sworn(npc_id),
		"can_apprentice": _master.can_apprentice(npc_id),
	}

func _summary(nodes: Array) -> Dictionary:
	var marriageable: Array = []
	var spouses := 0
	var children := 0
	var sworn := 0
	var masters := 0
	for n in nodes:
		if bool(n.get("can_propose", false)):
			marriageable.append(n.get("npc_id", ""))
		if bool(n.get("is_spouse", false)):
			spouses += 1
		if bool(n.get("is_sworn", false)):
			sworn += 1
		if bool(n.get("is_master", false)):
			masters += 1
		children += int((n.get("children", []) as Array).size())
	return {
		"npc_total": nodes.size(),
		"spouse_count": spouses,
		"child_count": children,
		"sworn_count": sworn,
		"master_count": masters,
		"marriageable": marriageable,
	}

func _name_of(npc_id: String) -> String:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return ""
	return String(npc.get("name", ""))
