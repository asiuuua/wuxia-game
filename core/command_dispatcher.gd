# core/command_dispatcher.gd
# 统一命令分发器（Core 原语 · P3-b 整改 2026-09-04）
# ============================================================
# 目标：命令只有一条通路——各领域把处理器注册进来，数据里写 "cmd:arg" 字符串即可，
# 新增一种命令 = 注册一个 handler，**不改任何核心服务**（整改路线 P3 验收标准）。
#
# 现状归一：DialogueEventExecutor 的行内命令（set_flag/quest_accept/quest_complete/sfx）
# 全部改为经本分发器注册+路由；后续 quest_graph handler、奖励分发（P3-c）共用同一注册表。
#
# 设计纪律：
#   - 纯逻辑 RefCounted，不 import 上层；handler 由装配方（服务层）注入 Callable。
#   - execute() 单条失败只告警不崩（与"安全降级"铁律一致），返回是否命中。
#   - cmd_line 格式："cmd" 或 "cmd:arg"（首个冒号分隔，arg 可含冒号）。

class_name CommandDispatcher
extends RefCounted

var _handlers: Dictionary = {}   # cmd(String) -> Callable(arg: String)

## 注册/覆盖一个命令处理器（arg 为冒号后的原始字符串，可能为空）
func register(cmd: String, handler: Callable) -> void:
	var c := cmd.strip_edges()
	if c == "":
		push_warning("[CommandDispatcher] 注册命令名为空，已忽略")
		return
	_handlers[c] = handler

func has_command(cmd: String) -> bool:
	return _handlers.has(cmd)

func command_names() -> Array[String]:
	var out: Array[String] = []
	out.assign(_handlers.keys())
	return out

## 执行 "cmd:arg"；返回 true=命中处理器，false=未知命令（由调用方决定告警/回退）
func execute(cmd_line: String) -> bool:
	var s := cmd_line.strip_edges()
	if s == "":
		return false
	var parts := s.split(":", true, 1)
	var cmd := parts[0].strip_edges()
	var arg := ""
	if parts.size() > 1:
		arg = parts[1].strip_edges()
	if not _handlers.has(cmd):
		return false
	var h: Callable = _handlers[cmd]
	if not h.is_valid():
		return false
	h.call(arg)
	return true
