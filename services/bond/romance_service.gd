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
var spouses: Dictionary = {}          # npc_id -> {stage, wed_day, children: Array[String], pregnancy: Dictionary, quanquan: Dictionary}
var children: Dictionary = {}         # child_id -> {mother_id, born_day, name}
# 欢庆每日配额（按 npc_id 独立，与配偶字典解耦：避免非配偶欢庆时误写进 spouses 污染配偶列表）
var celebration_quotas: Dictionary = {}  # npc_id -> {day, quota, used}
# BUG-21 修复：special_portraits.json 静态配置解析结果缓存，避免每次取立绘列表都重读盘解析
var _special_portrait_cache: Dictionary = {}

# === 婘眷值（用户 2026-08-30 拍板：只保留婘眷值，去掉夫妻同心；2026-08-30 夜间修订为 5 级制） ===
# 规则：初始 0 级，1~5 级，每级 200 经验，合计 1000 经验封顶；结婚后仅下列功能增加：
#   同游旅行 +5 / 寝欢(欢庆) +10 / 一家人协同出游(有子嗣) +15
# 仅「3 级」与「5 级」各解锁 1 张特殊立绘（共 2 张，可在该 NPC 立绘里左右滑动查看；
# 勾选后对话框+属性面板解锁该形象）。特殊立绘图片资源由 data/configs/bond/special_portraits.json 配置（预留空表）。
const QQ_MAX_LEVEL := 5
const QQ_XP_PER_LEVEL := 200
const QQ_MAX_PORTRAITS := 2  # 仅 3 级与 5 级各解锁 1 张，共 2 张
const SPECIAL_PORTRAITS_PATH := "res://data/configs/bond/special_portraits.json"

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

# === 婚配资格（用户 2026-09-03 拍板：不娶血亲；师徒/结义非血亲、单身/鳏寡可娶；已婚者不娶；不限上限） ===
# 从 relations.json 顶层 kin_type 字符串映射到 BondEnums.KinType
func _kin_type_of(npc_id: String) -> int:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return BondEnums.KinType.NONE
	match String(npc.get("kin_type", "NONE")):
		"SWORN":
			return BondEnums.KinType.SWORN
		"MASTER":
			return BondEnums.KinType.MASTER
		"PARENT":
			return BondEnums.KinType.PARENT
		"CHILD":
			return BondEnums.KinType.CHILD
		"SIBLING":
			return BondEnums.KinType.SIBLING
		_:
			return BondEnums.KinType.NONE

# NPC 婚配状态：relations.json 顶层 marital_status；married 不可求娶，single/widowed 可（缺省 single）
func _marriage_status(npc_id: String) -> String:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return "single"
	return String(npc.get("marital_status", "single"))

# 婚配资格：非血亲（NONE/SWORN/MASTER 均可），且非「已嫁」；鳏寡(widowed)可再娶
func _kin_marriage_ok(npc_id: String) -> bool:
	if BondEnums.is_blood_kin(_kin_type_of(npc_id)):
		return false
	return _marriage_status(npc_id) != "married"

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
# 聘礼是否足额（非锁定可用数量）：与 propose() 共用同一判定，避免 can_propose 与
# propose 逻辑分叉（BUG-10）。dowry_required 可能含重复 item_id（"龙鳞×2"）。
func _dowry_satisfied(npc_id: String) -> bool:
	var cfg: Dictionary = _romance_cfg(npc_id)
	var dowry: Array = cfg.get("dowry_required", [])
	if dowry.is_empty():
		return true
	var need: Dictionary = {}
	for item_id in dowry:
		var k := String(item_id)
		need[k] = int(need.get(k, 0)) + 1
	for item_id in need.keys():
		if GameManager.inventory_service.get_unlocked_count(item_id) < int(need[item_id]):
			return false
	return true

func can_propose(npc_id: String) -> bool:
	if not _is_romanceable(npc_id):
		return false
	if not _gender_ok(npc_id):
		return false
	if is_spouse(npc_id):
		return false
	if not _kin_marriage_ok(npc_id):
		return false
	if GameManager.bond_service.get_affection(npc_id) < _propose_affection(npc_id):
		return false
	# BUG-10 修复：缺聘礼时按钮亦应禁用（与 propose() 一致），避免 enabled 却点击被拒。
	if not _dowry_satisfied(npc_id):
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

# === 欢庆可用性（用户需求：所有可结缘 NPC，好感度满了即可使用欢庆） ===
# 好感是否已满（达到该 NPC 的 propose_affection 阈值，默认 100）
func _is_affection_full(npc_id: String) -> bool:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return false
	if not bool(npc.get("is_romanceable", false)):
		return false
	if GameManager.bond_service == null:
		return false
	var cfg: Dictionary = npc.get("romance", {})
	var need: int = int(cfg.get("propose_affection", 100))
	return GameManager.bond_service.get_affection(npc_id) >= need

# 能否欢庆：可结缘 + 好感满（是否已婚均可；已婚配偶天然好感满，也会被本方法放行）
func can_celebrate(npc_id: String) -> bool:
	if not _is_romanceable(npc_id):
		return false
	return _is_affection_full(npc_id)

# 求婚：通过则写入配偶名单、推进到已婚阶段、广播事件；聘礼不足则拒绝
func propose(npc_id: String) -> Dictionary:
	if is_spouse(npc_id):
		return {"ok": false, "reason": "ALREADY_SPOUSE", "stage": get_romance_stage(npc_id)}
	if not _is_romanceable(npc_id):
		return {"ok": false, "reason": "NOT_ROMANCEABLE", "stage": -1}
	if not _gender_ok(npc_id):
		return {"ok": false, "reason": "GENDER_MISMATCH", "stage": -1}
	if BondEnums.is_blood_kin(_kin_type_of(npc_id)):
		return {"ok": false, "reason": "BLOOD_KIN", "stage": -1}
	if _marriage_status(npc_id) == "married":
		return {"ok": false, "reason": "ALREADY_MARRIED", "stage": -1}
	if GameManager.bond_service.get_affection(npc_id) < _propose_affection(npc_id):
		return {"ok": false, "reason": "AFFECTION_NOT_FULL", "stage": -1}
	var cfg: Dictionary = _romance_cfg(npc_id)
	var dowry: Array = cfg.get("dowry_required", [])
	# 统计每种聘礼所需总数量（dowry_required 可能含重复 item_id，如“龙鳞×2”）
	var need: Dictionary = {}
	for item_id in dowry:
		var k := String(item_id)
		need[k] = int(need.get(k, 0)) + 1
	# 校验「非锁定」可用数量是否足额（与 can_propose 共用 _dowry_satisfied，单一真源）
	if not _dowry_satisfied(npc_id):
		return {"ok": false, "reason": "DOWRY_MISSING", "stage": -1}
	# 事务式扣除：逐项扣，任一失败则回滚已扣部分并拒绝，彻底杜绝白结婚。
	var deducted: Array = []  # 记录已扣 [{item_id, count}] 用于回滚
	for item_id in need.keys():
		var req: int = int(need[item_id])
		if GameManager.inventory_service.remove_item_by_id(item_id, req):
			deducted.append({"item_id": item_id, "count": req})
		else:
			for d in deducted:
				GameManager.inventory_service.add_item(String(d["item_id"]), int(d["count"]), "dowry_rollback")
			return {"ok": false, "reason": "DOWRY_MISSING", "stage": -1}
	var rec: Dictionary = {
		"stage": BondEnums.RomanceStage.MARRIED,
		"wed_day": int(Time.get_unix_time_from_system()),
		"rank": BondEnums.default_rank_for_order(spouses.size()),
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

# === 测试辅助（调试/验收用，非正式玩法；拉满好感以便快速试求婚/结婚流程） ===
# 一键拉满单个 NPC 好感：直接写 BondService.set_affection（自带 clamp 0-100 与 bond_affection_changed 广播）。
func debug_max_affection(npc_id: String) -> void:
	if GameManager.bond_service == null:
		return
	GameManager.bond_service.set_affection(npc_id, 100)

# 一键拉满所有可结缘对象好感（批量测试用）：遍历 relations.json 中 is_romanceable 的 NPC。
func debug_max_all_affection() -> void:
	if GameManager.bond_service == null:
		return
	for npc_id in ConfigManager.get_all_relation_ids():
		var npc: Dictionary = ConfigManager.get_relation(npc_id)
		if npc.is_empty() or not bool(npc.get("is_romanceable", false)):
			continue
		GameManager.bond_service.set_affection(npc_id, 100)

# 一键造已婚配偶（调试/验收专用，非正式玩法；跳过求婚的聘礼/婚礼演出副作用，
# 只写入已婚配偶记录，便于反复试欢庆/受孕/CG 表现）。已是配偶则跳过。
func debug_make_spouse(npc_id: String) -> void:
	if is_spouse(npc_id):
		return
	var rec: Dictionary = {
		"stage": BondEnums.RomanceStage.MARRIED,
		"wed_day": int(Time.get_unix_time_from_system()),
		"rank": BondEnums.default_rank_for_order(spouses.size()),
		"children": [],
		"pregnancy": {},
	}
	spouses[npc_id] = rec
	EventBus.bond_romance_formed.emit(npc_id, rec["stage"])
	EventBus.bond_relationship_changed.emit()

# === 后宅名分（用户 2026-09-03 拍板：大房~七房、小妾一~七、通房丫鬟；限名分、不限配偶数、不加成） ===
# 配偶在婚配词典中的次序（0起；用于旧档缺省名分回退，保持稳定）
func _order_of_spouse(npc_id: String) -> int:
	var order := 0
	for id in spouses.keys():
		if id == npc_id:
			return order
		order += 1
	return BondEnums.SpouseRank.CHAMBERMAID

# 某配偶的后宅名分；未存名分（旧档）按结婚次序默认
func get_spouse_rank(npc_id: String) -> int:
	if not spouses.has(npc_id):
		return BondEnums.SpouseRank.CHAMBERMAID
	var rec: Dictionary = spouses[npc_id]
	if not rec.has("rank"):
		return BondEnums.default_rank_for_order(_order_of_spouse(npc_id))
	return int(rec["rank"])

# 某配偶名分中文名
func get_spouse_rank_name(npc_id: String) -> String:
	return BondEnums.spouse_rank_name(get_spouse_rank(npc_id))

# 自定义后宅名分（可重排谁是大房/小妾/通房丫鬟）；rank 越界回退到通房丫鬟
func set_spouse_rank(npc_id: String, rank: int) -> bool:
	if not spouses.has(npc_id):
		return false
	var r := int(rank)
	if r < 0:
		r = BondEnums.SpouseRank.PRIMARY
	elif r > BondEnums.SpouseRank.CHAMBERMAID:
		r = BondEnums.SpouseRank.CHAMBERMAID
	spouses[npc_id]["rank"] = r
	EventBus.bond_relationship_changed.emit()
	return true

# 按名分排序后的配偶列表（同名分按婚配先后来）；供后宅面板顺位展示
func get_sorted_spouses() -> Array:
	var arr: Array = []
	for npc_id in spouses.keys():
		arr.append({"npc_id": npc_id, "rank": get_spouse_rank(npc_id), "rank_name": get_spouse_rank_name(npc_id)})
	arr.sort_custom(func(a, b): return int(a["rank"]) < int(b["rank"]))
	return arr

# === 子嗣阶段（出生 → 成年，按出生后天数分段；时间源仍为 advance_days） ===
# 子嗣成长阶段
func get_child_stage(child_id: String) -> int:
	if not children.has(child_id):
		return BondEnums.ChildStage.INFANT
	var age: int = int(children[child_id].get("age_days", 0))
	if age >= 1800:
		return BondEnums.ChildStage.ADULT
	if age >= 720:
		return BondEnums.ChildStage.TEEN
	if age >= 180:
		return BondEnums.ChildStage.CHILD
	if age >= 30:
		return BondEnums.ChildStage.TODDLER
	return BondEnums.ChildStage.INFANT

func get_child_stage_name(child_id: String) -> String:
	return BondEnums.child_stage_name(get_child_stage(child_id))

# 子嗣出生后天数
func get_child_age_days(child_id: String) -> int:
	if not children.has(child_id):
		return 0
	return int(children[child_id].get("age_days", 0))

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

# === 欢庆（原“寝欢”模块重构）：每日可点击，每配偶每自然日随机 2~3 次 ===
# 设计：配额状态存于 spouses[npc_id]["celebration"] = {day, quota, used}，随存档自动保存。
# 跨日（自然日，以系统时间戳按 86400s 取整）自动重置并重新随机配额。
# 超出当日配额返回 QUOTA_EXCEEDED，由 UI 弹出预留接口的对话框；否则计数+1 并广播 celebration_started 触发 CG。
# 注：欢庆与子嗣(孕期)对接——欢庆不再阻断于孕期（保持"每天都可以点击"），但若配偶当前未孕，则本次欢庆会启动孕期（受孕）；
# 孕期进行中的后续欢庆仍可每天点击并播 CG，只是不再重复受孕（与"怀胎十月"子嗣链一致）。受孕判定见 begin_celebration。

## 自然日键（按系统时间按天取整）
func _day_key() -> int:
	return int(Time.get_unix_time_from_system() / 86400)

## 确保当日配额已初始化（跨日则重置并随机 2~3）；配额独立存于 celebration_quotas，不污染 spouses
func _ensure_celebration_quota(npc_id: String) -> Dictionary:
	var cel: Dictionary = celebration_quotas.get(npc_id, {})
	var dk: int = _day_key()
	if int(cel.get("day", -1)) != dk:
		cel = {"day": dk, "quota": randi_range(2, 3), "used": 0}
	celebration_quotas[npc_id] = cel
	return cel

## 查询某 NPC 今日欢庆剩余次数（UI 展示用；不可欢庆返回 0）
func get_celebration_left(npc_id: String) -> int:
	if not can_celebrate(npc_id):
		return 0
	var cel: Dictionary = _ensure_celebration_quota(npc_id)
	return int(cel.get("quota", 0)) - int(cel.get("used", 0))

## 欢庆：可结缘 + 好感满即可每天点击；每 NPC 每自然日随机 2~3 次；超配额返回 QUOTA_EXCEEDED
## 同时对接子嗣链：若已是配偶且当前未孕，则本次欢庆启动孕期（受孕）；孕期进行中不影响后续欢庆点击（不再重复受孕）。
## cg_id 返回 npc_id，供 CelebrationOverlay 按 per-NPC 内容查找、缺省回退 default。
func begin_celebration(npc_id: String) -> Dictionary:
	if not can_celebrate(npc_id):
		return {"ok": false, "reason": "AFFECTION_NOT_FULL"}
	var cel: Dictionary = _ensure_celebration_quota(npc_id)
	if int(cel.get("used", 0)) >= int(cel.get("quota", 0)):
		return {"ok": false, "reason": "QUOTA_EXCEEDED", "used": cel.get("used", 0), "quota": cel.get("quota", 0)}
	cel["used"] = int(cel.get("used", 0)) + 1
	celebration_quotas[npc_id] = cel
	# 受孕：仅当已是配偶且未孕（非配偶的好感满 NPC 也能欢庆，但不受孕）；概率走 romance.conceive_chance（缺省 1.0）
	var conceived := false
	if is_spouse(npc_id):
		var rec: Dictionary = spouses[npc_id]
		if rec.get("pregnancy", {}).is_empty():
			var chance: float = float(_romance_cfg(npc_id).get("conceive_chance", 1.0))
			if randf() < chance:
				rec["pregnancy"] = {
					"start_day": int(Time.get_unix_time_from_system()),
					"gestation_days": 300,
					"progress": 0,
				}
				conceived = true
		spouses[npc_id] = rec
	EventBus.celebration_started.emit(npc_id, npc_id)
	var qq := add_quanquan(npc_id, 10)  # 寝欢 +10 婘眷值
	EventBus.bond_relationship_changed.emit()
	return {"ok": true, "reason": "SUCCESS", "cg_id": npc_id, "used": cel["used"], "quota": cel["quota"], "conceived": conceived, "quanquan": qq}

# === 婘眷值（婚后专属，仅经下列功能增加） ===
# 取得某配偶婘眷值状态；非配偶返回空字典。
func get_quanquan(npc_id: String) -> Dictionary:
	if not spouses.has(npc_id):
		return {}
	var rec: Dictionary = spouses[npc_id]
	if not rec.has("quanquan"):
		rec["quanquan"] = _new_quanquan()
	var qq: Dictionary = rec["quanquan"]
	var xp: int = int(qq.get("xp", 0))
	var level: int = int(qp_get_level(xp))
	var unlocked: int = int(qq.get("unlocked_portraits", 0))
	# 当前这一级还差多少经验升级（用于 UI 进度条）
	var xp_in_level: int = xp - level * QQ_XP_PER_LEVEL
	return {
		"level": level,
		"xp": xp,
		"xp_in_level": xp_in_level,
		"xp_per_level": QQ_XP_PER_LEVEL,
		"unlocked_portraits": unlocked,
		"max_portraits": QQ_MAX_PORTRAITS,
		# 下一张特殊立绘还需经验（仅 3 级 / 5 级触发；满级后返回 0）
		"xp_to_next_portrait": _xp_to_next_portrait(xp),
	}

func _new_quanquan() -> Dictionary:
	return {"level": 0, "xp": 0, "unlocked_portraits": 0}

# 等级 → 已解锁特殊立绘数：仅 3 级解锁第 1 张、5 级解锁第 2 张
func _unlocked_from_level(lv: int) -> int:
	return (1 if lv >= 3 else 0) + (1 if lv >= 5 else 0)

func _xp_to_next_portrait(xp: int) -> int:
	var lv: int = qp_get_level(xp)
	if lv >= QQ_MAX_LEVEL:
		return 0
	if lv < 3:
		return 3 * QQ_XP_PER_LEVEL - xp
	return 5 * QQ_XP_PER_LEVEL - xp

# 增加婘眷值（内部统一入口）；返回更新后的状态字典。
# 仅当等级跨过 3 级 / 5 级时解锁对应特殊立绘（共 2 张）。
func add_quanquan(npc_id: String, amount: int) -> Dictionary:
	if not spouses.has(npc_id):
		return {}
	if amount <= 0:
		return get_quanquan(npc_id)
	var rec: Dictionary = spouses[npc_id]
	if not rec.has("quanquan"):
		rec["quanquan"] = _new_quanquan()
	var qq: Dictionary = rec["quanquan"]
	var xp: int = int(qq.get("xp", 0)) + amount
	var level: int = int(qp_get_level(xp))
	var unlocked: int = int(qq.get("unlocked_portraits", 0))
	var new_unlocked: int = _unlocked_from_level(level)
	if new_unlocked > unlocked:
		# 解锁事件：广播供 UI 弹喜讯 / NPC 面板刷新
		EventBus.bond_special_portrait_unlocked.emit(npc_id, new_unlocked)
	qq["level"] = level
	qq["xp"] = xp
	qq["unlocked_portraits"] = new_unlocked
	rec["quanquan"] = qq
	spouses[npc_id] = rec
	EventBus.bond_relationship_changed.emit()
	return get_quanquan(npc_id)

# 经验 → 等级（初始 0 级，每 200 经验升 1 级，5 级封顶；0 经验即 0 级）
func qp_get_level(xp: int) -> int:
	return mini(int(xp / QQ_XP_PER_LEVEL), QQ_MAX_LEVEL)

# 同游旅行：+5 婘眷值（需已婚配偶）
func travel_together(npc_id: String) -> Dictionary:
	if not is_spouse(npc_id):
		return {"ok": false, "reason": "NOT_SPOUSE"}
	return {"ok": true, "quanquan": add_quanquan(npc_id, 5)}

# 一家人协同出游：+15 婘眷值（需已婚且有子嗣）
func family_outing(npc_id: String) -> Dictionary:
	if not is_spouse(npc_id):
		return {"ok": false, "reason": "NOT_SPOUSE"}
	if get_children_of(npc_id).is_empty():
		return {"ok": false, "reason": "NO_CHILDREN"}
	return {"ok": true, "quanquan": add_quanquan(npc_id, 15)}

# === 特殊立绘选择（对话框 / NPC 面板切换形象） ===
# 返回该 NPC 当前可滑动查看的立绘路径列表：第 0 张为半身立绘（基准），之后为已解锁的特殊立绘。
# 未解锁的特殊立绘不出现（玩家只能滑到「已解锁」范围）。非配偶返回仅 [基准]。
func get_portrait_list(npc_id: String) -> Array:
	var out: Array = []
	var base: String = ""
	if GameManager.dialogue_service != null:
		base = GameManager.dialogue_service.resolve_half_body(npc_id, false)
	else:
		var npc: Dictionary = ConfigManager.get_npc(npc_id)
		if not npc.is_empty():
			base = npc.get("half_body_portrait", npc.get("portrait", ""))
	if base != "":
		out.append(base)
	# 已解锁的特殊立绘（按 special_portraits.json 顺序，截断到已解锁数量）
	var unlocked: int = 0
	if spouses.has(npc_id) and spouses[npc_id].has("quanquan"):
		unlocked = int(spouses[npc_id]["quanquan"].get("unlocked_portraits", 0))
	if unlocked > 0:
		var cfg: Dictionary = _special_portrait_cfg(npc_id)
		var paths: Array = cfg.get("portraits", [])
		for i in range(mini(unlocked, paths.size())):
			out.append(String(paths[i]))
	return out

# 玩家当前勾选的立绘索引（0=基准，>=1 为第几张特殊立绘）；默认 0。
func get_selected_portrait_index(npc_id: String) -> int:
	if not spouses.has(npc_id):
		return 0
	var rec: Dictionary = spouses[npc_id]
	return int(rec.get("selected_portrait", 0))

# 勾选某张立绘（对话框/NPC 面板切换形象）；index 超出已解锁范围则忽略。
func select_portrait(npc_id: String, index: int) -> bool:
	if not spouses.has(npc_id):
		return false
	var list: Array = get_portrait_list(npc_id)
	if index < 0 or index >= list.size():
		return false
	spouses[npc_id]["selected_portrait"] = index
	EventBus.bond_relationship_changed.emit()
	return true

# 返回当前应显示的立绘路径（按勾选索引，越界回退基准）。
func get_active_portrait(npc_id: String) -> String:
	var list: Array = get_portrait_list(npc_id)
	var idx: int = get_selected_portrait_index(npc_id)
	if idx < 0 or idx >= list.size():
		idx = 0
	if list.is_empty():
		return ""
	return String(list[idx])

func _special_portrait_cfg(npc_id: String) -> Dictionary:
	if not FileAccess.file_exists(SPECIAL_PORTRAITS_PATH):
		return {}
	if not _special_portrait_cache.is_empty():
		return _special_portrait_cache.get(npc_id, _special_portrait_cache.get("default", {}))
	var f := FileAccess.open(SPECIAL_PORTRAITS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		_special_portrait_cache = parsed
		return parsed.get(npc_id, parsed.get("default", {}))
	return {}

# 推进游戏天数：孕期进度累加，满 gestation_days 则分娩；同时推进子嗣年龄（驱动成长阶段）。
# 由 TimeService/休息动作喂天数
func advance_days(n: int) -> void:
	if n <= 0:
		return
	# 子嗣年龄推进（出生后的累计天数，驱动婴儿→成年的成长阶段；先于受孕分娩，避免新生儿被同次加龄）
	for cid in children.keys():
		var c: Dictionary = children[cid]
		c["age_days"] = int(c.get("age_days", 0)) + n
		children[cid] = c
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
		"age_days": 0,
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
	celebration_quotas.clear()   # 同步重置当日欢庆配额，避免跨测试/新游戏残留配额污染

func get_save_key() -> String:
	return "romance"

func save() -> Dictionary:
	return {"spouses": spouses.duplicate(true), "children": children.duplicate(true), "celebration_quotas": celebration_quotas.duplicate(true)}

func load(data: Dictionary) -> void:
	spouses = data.get("spouses", {})
	children = data.get("children", {})
	celebration_quotas = data.get("celebration_quotas", {})
