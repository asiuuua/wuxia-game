# services/quest/quest_graph.gd
# 任务流程图解释器(QuestGraph)：对标巫师3 / 赛博朋克 QuestGraph 的任务节点图引擎。
# 设计：纯逻辑、不持有 Node。输入一段 quest_graph 配置 + 一个 FlagStore，走节点/读条件/写状态/判结局。
# 条件DSL + 副作用op + 节点流解释 + 结局判定 集中在同文件，向前兼容、可注入测试。
# 说明：dialog/battle/give_item 等"触发型"节点在 T1 以占位记录处理，真正的 UI/战斗/背包接入留 T2。
class_name QuestGraph
extends RefCounted

const OP_FLAG_SET := "flag_set"
const OP_FAVOR_ADD := "favor_add"
const OP_PROGRESS := "progress_set"
const OP_EMIT := "emit_event"
const MAX_STEPS := 800

# 触发型节点类型：T2 起会产出 action，交由上层 Handler 接到真实系统（对话/战斗/背包）
const NODE_DIALOG := "dialog"
const NODE_BATTLE := "battle"
const NODE_GIVE_ITEM := "give_item"
const _TRIGGER_NODES := [NODE_DIALOG, NODE_BATTLE, NODE_GIVE_ITEM]

var _log: Array = []
var _store: RefCounted = null
var _actions: Array = []
var _handler: Callable = Callable()

## 运行一张图；store 缺省时用内存独立存储（不落存档）。
## handler 可选：注入后，遇到 dialog/battle/give_item 触发型节点会把动作交给 handler（真实系统钩子），
## 并沿其 "next" 继续；未注入 handler 时回退为原纯逻辑直连（向后兼容、不破坏既有图/测试）。
## 返回 {steps, ending, log, actions}，actions 为本轮收集的触发型动作列表。
func run(quest: Dictionary, store: RefCounted = null, handler: Callable = Callable()) -> Dictionary:
	_log.clear()
	_actions.clear()
	_handler = handler
	_store = store if store != null else _make_local_store()
	var nodes: Dictionary = quest.get("nodes", {})
	var current: String = String(quest.get("start_node", ""))
	var steps: Array = []
	var guard := 0
	var ending := ""
	while current != "" and guard < MAX_STEPS:
		guard += 1
		if not nodes.has(current):
			_log.append("节点缺失:" + current)
			break
		var node: Dictionary = nodes[current]
		_log.append("步进:" + current + "(" + String(node.get("type", "")) + ")")
		steps.append(current)
		_apply(node.get("then", node.get("on_enter", [])))
		var ntype: String = String(node.get("type", ""))
		if ntype == "end":
			ending = String(node.get("ending", ""))
			current = ""
		elif ntype == "choice":
			current = _resolve_choice(node)
			if current == "":
				_log.append("choice: 无可匹配选项，中断")
		elif ntype == "flag_check":
			current = String(node.get("next", "")) if _cond(node.get("require", node.get("if", {}))) else String(node.get("else_next", ""))
		elif _TRIGGER_NODES.has(ntype):
			current = _trigger(node, ntype)
		else:
			current = String(node.get("next", ""))
	if guard >= MAX_STEPS and current != "":
		_log.append("警告: 疑似成环，已达最大步数")
	if ending == "":
		ending = _resolve_ending(quest)
	return {"steps": steps, "ending": ending, "log": _log.duplicate(), "actions": _actions.duplicate()}

## 触发型节点：构造 action 交给 handler（真系统钩子）；未注入 handler 时回退为"胜利默认路径"
func _trigger(node: Dictionary, ntype: String) -> String:
	var act := {"node": "", "type": ntype, "data": {}}
	act["node"] = str(node.get("self_id", node.get("id", "")))
	match ntype:
		NODE_DIALOG:
			act["data"] = {"dialog_ref": str(node.get("dialog_ref", "")), "lines_from": str(node.get("lines_from", ""))}
		NODE_BATTLE:
			act["data"] = {
				"battle_ref": str(node.get("battle_ref", "")),
				"on_win": node.get("on_win", []),
				"on_win_next": str(node.get("on_win_next", "")),
				"on_lose_next": node.get("on_lose_next"),
			}
		NODE_GIVE_ITEM:
			act["data"] = {"item": str(node.get("item", "")), "qty": int(node.get("qty", 1))}
	_actions.append(act)
	_log.append("触发:" + ntype + ":" + str(act["data"]))
	var next: String = String(node.get("next", ""))
	if ntype == NODE_BATTLE and next.is_empty():
		next = String(node.get("on_win_next", ""))
	if _handler.is_valid():
		_handler.call(act)
		return next
	# 无 handler（占位/T1 兼容）：触发视为顺利完成，沿胜利默认路径推进
	if ntype == NODE_BATTLE:
		_apply(node.get("on_win", []))
	return next

## 直接判定条件（供单元测试/上层复用）；store 缺省沿用最近一次
func evaluate_condition(cond, store: RefCounted = null) -> bool:
	if store != null:
		_store = store
	return _cond(cond)

func get_log() -> Array:
	return _log

# ---------- 条件 DSL（P3 统一 2026-09-04：委托 core/condition.gd ConditionService）----------
# 本图只保留 Bool/空 兼容特判；方言归一与求值全部在 ConditionService（顶层键格式
# flag/favor/progress 原生保留为存量兼容，新内容推荐 kind 风格）。unknown 语义保持
# 任务图老语义：无法求值判否（strict=false）。
var _cond_eval: ConditionService = ConditionService.new()

func _cond(cond) -> bool:
	if cond is bool:
		return cond
	if cond == null:
		return true
	if not (cond is Dictionary):
		return true
	_cond_eval.facts = _store   # 每次求值对齐当前图的 store（测试可逐 run 注入内存存储）
	return _cond_eval.evaluate(cond, "", false)

# ---------- 副作用 ops ----------
func _apply(ops) -> void:
	if ops == null:
		return
	for op in ops:
		if not (op is Dictionary):
			continue
		var o: Dictionary = op
		match String(o.get("op", "")):
			OP_FLAG_SET:
				_store.set_flag(str(o.get("key", "")), o.get("value", true))
			OP_FAVOR_ADD:
				_store.add_favor(str(o.get("target", "")), float(o.get("value", 0)))
			OP_PROGRESS:
				_store.set_progress(str(o.get("quest", "")), int(o.get("value", 1)))
			OP_EMIT:
				_log.append("emit:" + str(o.get("event", "")))
			_:
				_log.append("op-skip:" + str(o.get("op", "")))

# ---------- choice 分支：取首个满足 show 条件的选项 ----------
func _resolve_choice(node: Dictionary) -> String:
	for opt in node.get("options", []):
		if not (opt is Dictionary):
			continue
		if _cond(opt.get("show", {})):
			_apply(opt.get("then", []))
			var next: String = str(opt.get("next", ""))
			_log.append("选择:" + str(opt.get("text_key", "")) + " -> " + next)
			return next
	return ""

# ---------- 结局回退：走到非 end 终止时按 endings 表匹配 ----------
func _resolve_ending(quest: Dictionary) -> String:
	for e in quest.get("endings", []):
		if e is Dictionary and _cond(e.get("require", {})):
			return str(e.get("id", ""))
	return ""

func _make_local_store() -> RefCounted:
	return _MemStore.new()

# 内存独立存储（测试/无存档场景），接口与 FlagStore 对齐（duck-typed）
class _MemStore:
	extends RefCounted
	var _d: Dictionary = {}
	func get_flag(k: String, def: Variant = null) -> Variant:
		return _d.get(k, def)
	func set_flag(k: String, v: Variant) -> void:
		_d[k] = v
	func get_favor(id: String) -> float:
		return float(_d.get("favor:" + id, 0.0))
	func add_favor(id: String, delta: float) -> void:
		_d["favor:" + id] = get_favor(id) + delta
	func get_progress(q: String) -> int:
		return int(_d.get("progress:" + q, 0))
	func set_progress(q: String, v: int) -> void:
		_d["progress:" + q] = v