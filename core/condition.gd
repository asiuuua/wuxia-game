# core/condition.gd
# 统一条件求值器（Core 原语 · P3 整改 2026-09-04）
# ============================================================
# 目标：把项目里三套条件方言归一为一个 ConditionSpec DSL：
#   方言1 对话侧（dialogue_service 老格式）  {"kind":"quest_active"|"has_item"|"favor","arg":...}
#   方言2 任务图（quest_graph 顶层键格式）  {"all":[..]}/{"any":[..]}/{"not":{..}}/{"flag":k,...}/{"favor":npc,...}/{"progress":q,...}
#   方言3 区域任务 prerequisites            {"nv_flag_guard_done": true}（键值对，编译为 flag 叶子）
#
# 统一 DSL（新内容一律按此写）：
#   复合：  {"all":[...]} / {"any":[...]} / {"not":{...}}
#   叶子（kind 风格，推荐）：
#     {"kind":"flag","key":k} 或 + "eq"/"ne" 比较（缺省按布尔真值）
#     {"kind":"favor","npc":id,"gte":n}   npc 缺省=会话 NPC（对话上下文注入）
#     {"kind":"progress","quest":id,"gte":n}
#     {"kind":"quest_active","id":x}
#     {"kind":"has_item","id":x}
#   叶子（顶层键风格，为 quest_graph 存量数据保留）：
#     {"flag":k,"eq"/"ne"/"def"} / {"favor":npc,"gte"/"lte"/"eq"} / {"progress":q,"gte"}
#
# 依赖纪律：本类是纯求值器，**不 import 任何上层**。事实查询走鸭子类型 facts 对象：
#   get_flag(key,def) / get_favor(npc) / get_progress(quest) / quest_active(id) / item_count(id)
#   —— 方法缺失时该类叶子按 unknown_true 降级（安全不崩）。游戏侧适配器见
#   services/quest/facts.gd（ServiceGameFacts；kernel 冻结名 GameFacts 归 core/kernel/ 契约）；
#   quest_graph 直接传入其 FlagStore（前三方法即够）。

class_name ConditionService
extends RefCounted

var facts: Object = null   # 鸭子类型事实源；null 时全部叶子按 unknown_true 处理

func _init(facts_provider: Object = null) -> void:
	facts = facts_provider

## 统一入口。ctx_npc：对话会话 NPC（favor 缺省对象）；unknown_true：无法求值时的语义
## （对话侧老语义=恒真，任务图老语义=判否）。
func evaluate(cond: Variant, ctx_npc: String = "", unknown_true: bool = true) -> bool:
	if cond == null:
		return true
	if not (cond is Dictionary):
		return true
	var c: Dictionary = cond
	if c.is_empty():
		return true
	# ---- 复合节点 ----
	if c.has("all"):
		for sub in c["all"]:
			if not evaluate(sub, ctx_npc, unknown_true):
				return false
		return true
	if c.has("any"):
		for sub in c["any"]:
			if evaluate(sub, ctx_npc, unknown_true):
				return true
		return false
	if c.has("not"):
		return not evaluate(c["not"], ctx_npc, unknown_true)
	# ---- 顶层键叶子（quest_graph 存量格式）----
	if c.has("flag"):
		return _leaf_flag(str(c["flag"]), c, unknown_true)
	if c.has("favor"):
		return _leaf_favor(str(c["favor"]), c, unknown_true)
	if c.has("progress"):
		return _leaf_progress(str(c["progress"]), c, unknown_true)
	# ---- kind 叶子（统一推荐写法）----
	var kind := str(c.get("kind", ""))
	match kind:
		"flag":
			return _leaf_flag(str(c.get("key", c.get("arg", ""))), c, unknown_true)
		"favor":
			var npc := str(c.get("npc", ctx_npc))
			return _leaf_favor(npc, c, unknown_true)
		"progress":
			return _leaf_progress(str(c.get("quest", c.get("arg", ""))), c, unknown_true)
		"quest_active":
			return _leaf_quest_active(str(c.get("id", c.get("arg", ""))), unknown_true)
		"has_item":
			return _leaf_has_item(str(c.get("id", c.get("arg", ""))), unknown_true)
		_:
			return unknown_true

# ---------- 叶子实现（全部经 facts 鸭子调用，缺方法降级） ----------

func _leaf_flag(key: String, c: Dictionary, unknown_true: bool) -> bool:
	if key == "" or facts == null or not facts.has_method("get_flag"):
		return unknown_true
	var got: Variant = facts.get_flag(key, c.get("def", null))
	if c.has("eq"):
		return str(got) == str(c["eq"])
	if c.has("ne"):
		return str(got) != str(c["ne"])
	return bool(got)

func _leaf_favor(npc: String, c: Dictionary, unknown_true: bool) -> bool:
	if npc == "" or facts == null or not facts.has_method("get_favor"):
		return unknown_true
	var v: float = float(facts.get_favor(npc))
	# dialogue 老格式 {"kind":"favor","arg":20}：arg 视为 gte
	if not (c.has("gte") or c.has("lte") or c.has("eq")) and c.has("arg"):
		return v >= float(c["arg"])
	if c.has("gte"):
		return v >= float(c["gte"])
	if c.has("lte"):
		return v <= float(c["lte"])
	if c.has("eq"):
		return v == float(c["eq"])
	return v != 0.0

func _leaf_progress(quest_id: String, c: Dictionary, unknown_true: bool) -> bool:
	if quest_id == "" or facts == null or not facts.has_method("get_progress"):
		return unknown_true
	var p: int = int(facts.get_progress(quest_id))
	if c.has("gte"):
		return p >= int(c["gte"])
	return p >= 1

func _leaf_quest_active(quest_id: String, unknown_true: bool) -> bool:
	if quest_id == "" or facts == null or not facts.has_method("quest_active"):
		return unknown_true
	return bool(facts.quest_active(quest_id))

func _leaf_has_item(item_id: String, unknown_true: bool) -> bool:
	if item_id == "" or facts == null or not facts.has_method("item_count"):
		return unknown_true
	return int(facts.item_count(item_id)) > 0

# ---------- 便捷编译 ----------
## 把区域任务 prerequisites 键值对（方言3）编译为统一 DSL：
## {"a": true, "b": 3} → {"all":[{"kind":"flag","key":"a","eq":true},{"kind":"flag","key":"b","eq":3}]}
static func compile_keyvalue(prereq: Dictionary) -> Dictionary:
	if prereq.is_empty():
		return {}
	var subs: Array = []
	for k in prereq.keys():
		subs.append({"kind": "flag", "key": str(k), "eq": prereq[k]})
	return {"all": subs}
