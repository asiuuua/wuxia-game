# core/effect_registry.gd
# Effect 注册表（12 图 QD-2 / 01 §50-§51 落地）：Quest/Dialogue 域级副作用统一执行体系。
# 五类 kind 冻结（QD-R03 禁第六种副作用形态，注册期机器化拒绝）：
#   reward / story_flag / relationship / progress / presentation
# handler 统一签名：func(payload: Variant, ctx: Dictionary) -> void（02 Effect 契约 GDScript 锚点，
# 与 5a71907 kernel Phase B 的 core/kernel/effect/effect.gd 契约互补：契约定形，本表定执行）。
#   - payload：效果参数，任意形态（字符串 DSL 尾段 / 效果字典 / 数值 / 数组）
#   - ctx：执行上下文（quest_id / dialog_id / npc_id / channel 等），只读约定
# 双协议入口（QD-2 追认：字符串 DSL 保留作内容侧书写格式，执行落本注册表）：
#   - apply_line("op:payload")：行内命令书写格式，首冒号分隔（与旧 CommandDispatcher 语义一致）
#   - apply_dict({type/op, ...})：trigger_events 老协议查表形态，一版兼容后退役（QD-4）
# QD-R09 死命令禁令：apply 未注册 op = FATAL（push_error + 返回 false），绝不静默吞。
# 纯逻辑 RefCounted，不持有 Node；core 层零依赖（不引 services/autoload）。

class_name EffectRegistry
extends RefCounted

const KIND_REWARD := "reward"
const KIND_STORY_FLAG := "story_flag"
const KIND_RELATIONSHIP := "relationship"
const KIND_PROGRESS := "progress"
const KIND_PRESENTATION := "presentation"
const KINDS: Array[String] = [
	KIND_REWARD, KIND_STORY_FLAG, KIND_RELATIONSHIP, KIND_PROGRESS, KIND_PRESENTATION,
]

# op -> {"kind": String, "handler": Callable}
var _effects: Dictionary = {}


## 注册效果：kind 越界拒绝（QD-R03）；同名 op 重复注册拒绝（防双 handler 语义漂移）
func register(op: String, kind: String, handler: Callable) -> bool:
	if op.is_empty():
		push_error("[EffectRegistry] 注册 op 为空，已拒绝")
		return false
	if not KINDS.has(kind):
		push_error("[EffectRegistry] 拒绝注册非五类 kind=%s（op=%s）——QD-R03 禁第六种副作用形态" % [kind, op])
		return false
	if _effects.has(op):
		push_error("[EffectRegistry] op 重复注册被拒: %s" % op)
		return false
	if not handler.is_valid():
		push_error("[EffectRegistry] handler 无效: %s" % op)
		return false
	_effects[op] = {"kind": kind, "handler": handler}
	return true


func has_effect(op: String) -> bool:
	return _effects.has(op)


## 查 op 归属的 kind；未注册返回空串
func kind_of(op: String) -> String:
	var e: Dictionary = _effects.get(op, {})
	return String(e.get("kind", ""))


## 已注册 op 清单（按 kind 过滤可选，排序稳定）——契约测试/通报面用
func effect_names(kind: String = "") -> Array:
	var names: Array = []
	for op in _effects.keys():
		if kind == "" or kind_of(String(op)) == kind:
			names.append(String(op))
	names.sort()
	return names


## 统一执行入口：未注册 op = 死命令（QD-R09，FATAL 语义）
func apply(op: String, payload: Variant, ctx: Dictionary = {}) -> bool:
	if not _effects.has(op):
		push_error("[EffectRegistry] 死命令: op 未注册（op=%s）——QD-R09" % op)
		return false
	var e: Dictionary = _effects[op]
	var h: Callable = e["handler"]
	h.call(payload, ctx)
	return true


## 行内 DSL 入口："op:payload" 首冒号分隔；无冒号整串作 op、payload 置空串。
## kv 形态（如 "set_flag:story_x=1"）的解析交给 handler（payload 原样透传尾段）。
func apply_line(cmd_line: String, ctx: Dictionary = {}) -> bool:
	var s := cmd_line.strip_edges()
	if s.is_empty():
		return false
	var idx := s.find(":")
	if idx == -1:
		return apply(s, "", ctx)
	return apply(s.substr(0, idx), s.substr(idx + 1), ctx)


## 效果字典入口（trigger_events 老协议查表形态）：type（兼容 op）作 op、整字典作 payload；
## 字符串元素透传 apply_line。非法形态报错返回 false。
func apply_dict(eff: Variant, ctx: Dictionary = {}) -> bool:
	if eff is String:
		return apply_line(String(eff), ctx)
	if not (eff is Dictionary):
		push_error("[EffectRegistry] 非法效果形态（非字典/字符串）: %s" % str(eff))
		return false
	var d: Dictionary = eff
	var op := String(d.get("type", d.get("op", "")))
	if op.is_empty():
		push_error("[EffectRegistry] 效果字典缺 type/op 键: %s" % str(d))
		return false
	return apply(op, d, ctx)
