# services/sect/sect_service.gd
# 门派系统（Phase 2 系统填充）：玩家加入门派、积累声望、晋升阶位
# 有持久状态（当前门派 + 每门派声望 + 阶位），故实现 ISaveable
# 2026-08-29 叶子层实现：join() / contribute() 补全

extends ISaveable
class_name SectService

var current_sect_id: String = ""        # 当前所属门派（空串表示散修）
var reputation: Dictionary = {}          # sect_id -> 声望值(int)
var rank: Dictionary = {}                # sect_id -> 阶位(SectEnums.Rank int)

func get_save_key() -> String:
	return "sect"

func save() -> Dictionary:
	# 返回快照（duplicate），避免外部持有后 mutate 影响内部状态
	return {
		"current_sect_id": current_sect_id,
		"reputation": reputation.duplicate(),
		"rank": rank.duplicate(),
	}

func load(data: Dictionary) -> void:
	current_sect_id = data.get("current_sect_id", "")
	# get() 返回 Variant Dictionary，显式 duplicate 转成本地 Dictionary（避免外部引用）
	reputation = data.get("reputation", {}).duplicate()
	rank = data.get("rank", {}).duplicate()

func reset() -> void:
	current_sect_id = ""
	reputation.clear()
	rank.clear()

# === 业务逻辑 ===

## 加入门派：校验未入门派 / 声望足够 / 入门道具，置 current_sect_id 并初始化声望阶位
## 返回 SectEnums.JoinResult
func join(sect_id: String) -> int:
	var sect: Dictionary = ConfigManager.get_sect(sect_id)
	if sect.is_empty():
		EventBus.notify_sect_join_failed.emit(sect_id, "UNKNOWN_SECT")
		return SectEnums.JoinResult.FAIL_UNKNOWN_SECT

	if current_sect_id != "":
		EventBus.notify_sect_join_failed.emit(sect_id, "ALREADY_IN_SECT")
		return SectEnums.JoinResult.FAIL_ALREADY_IN_SECT

	var need: int = int(sect.get("join_reputation_req", 0))
	if int(reputation.get(sect_id, 0)) < need:
		EventBus.notify_sect_join_failed.emit(sect_id, "REPUTATION_TOO_LOW")
		return SectEnums.JoinResult.FAIL_REPUTATION_TOO_LOW

	# 入门道具（可为空，为空表示不需要）
	var req_item: String = String(sect.get("join_req_item", ""))
	if req_item != "":
		var inv: InventoryService = GameManager.inventory_service
		if inv == null or inv.get_item_count(req_item) <= 0:
			EventBus.notify_sect_join_failed.emit(sect_id, "MISSING_ITEM")
			return SectEnums.JoinResult.FAIL_REPUTATION_TOO_LOW

	current_sect_id = sect_id
	if not reputation.has(sect_id):
		reputation[sect_id] = 0
	if not rank.has(sect_id):
		rank[sect_id] = SectEnums.Rank.OUTSIDER
	EventBus.notify_sect_joined.emit(sect_id)
	return SectEnums.JoinResult.SUCCESS

## 贡献声望：累加并检查是否跨过阶位阈值，跨过则晋升并 emit
func contribute(sect_id: String, amount: int) -> void:
	if amount <= 0:
		return
	var cur: int = int(reputation.get(sect_id, 0))
	cur += amount
	reputation[sect_id] = cur
	EventBus.notify_sect_reputation_changed.emit(sect_id, cur)

	var new_rank: int = _rank_for_reputation(sect_id, cur)
	var old_rank: int = int(rank.get(sect_id, SectEnums.Rank.OUTSIDER))
	if new_rank > old_rank:
		rank[sect_id] = new_rank
		EventBus.notify_sect_rank_up.emit(sect_id, new_rank)

## 当前门派声望
func get_reputation(sect_id: String) -> int:
	return int(reputation.get(sect_id, 0))

## 当前门派阶位（SectEnums.Rank）
func get_rank(sect_id: String) -> int:
	return int(rank.get(sect_id, SectEnums.Rank.OUTSIDER))

## UI 用：阶位显示名（ranks[].rank 字符串 -> 中文）
func get_rank_name(rank_value: int) -> String:
	match rank_value:
		SectEnums.Rank.INNER: return "内门弟子"
		SectEnums.Rank.CORE: return "核心弟子"
		SectEnums.Rank.ELDER: return "长老"
		SectEnums.Rank.LEADER: return "掌门"
		_: return "外门弟子"

## 按声望算出应得阶位：遍历 ranks 取"已达成的最高档"
func _rank_for_reputation(sect_id: String, rep: int) -> int:
	var sect: Dictionary = ConfigManager.get_sect(sect_id)
	if sect.is_empty():
		return SectEnums.Rank.OUTSIDER
	var best: int = SectEnums.Rank.OUTSIDER
	for r in sect.get("ranks", []):
		var threshold: int = int(r.get("rep_threshold", 0))
		if rep >= threshold:
			var rk: int = _rank_from_string(String(r.get("rank", "OUTSIDER")))
			if rk > best:
				best = rk
	return best

func _rank_from_string(name_str: String) -> int:
	match name_str:
		"INNER": return SectEnums.Rank.INNER
		"CORE": return SectEnums.Rank.CORE
		"ELDER": return SectEnums.Rank.ELDER
		"LEADER": return SectEnums.Rank.LEADER
		_: return SectEnums.Rank.OUTSIDER
