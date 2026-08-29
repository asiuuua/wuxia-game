# services/dialogue/dialogue_service.gd
# 对话服务（数据层 + 会话状态机）：把 NPC、台词、对话框三者解耦。
#   - NPC 配置只决定"跟谁说话"、外观、动作入口（quest_id/battle_id）。
#   - 台词表（dialogs.json）决定"说什么"，支持分支/选项/条件/事件（图模型）。
#   - DialogOverlay 只负责"怎么呈现"，通过本服务驱动；本服务持有全部跳转逻辑。
# 本服务为 ConfigManager 对话表的薄封装 + 跳转/条件/事件调度，符合"业务收敛 Service"。
# 性能说明：ConfigManager 启动只加载 KB 级对话索引（O(1) 查 dialog_id），分片内容 get_dialog 时按需懒加载、闲置自动卸载（pin 保护进行中对话）。
# 真正的重复开销在 start() 每次对全量 lines 做 duplicate(true) 深拷贝 + 重建 __id 索引。
# 故本服务再加一层"编译后对话缓存"：dialog_id -> {lines, index}，首次编译一次，之后同段对话直接命中。

class_name DialogueService
extends RefCounted

const PLAYER_ID := "player"

# ---- 编译后对话缓存：dialog_id -> {"lines":[...], "index":{id:line}} ----
# 缓存的是深拷贝后的lines与其索引，会话只读取不修改，故可在多次对话间安全复用。
var _parsed_cache: Dictionary = {}

# ---- 条件预检缓存（工业化扩容 P3）：cond 结果按 (kind|arg|npc) 缓存 1s ----
# 数百 NPC、分支/条件密集的对话中，每行推进与每个选项渲染都会 _check_condition，
# 直接打任务/背包/好感服务。1s TTL 内命中缓存，避免短时间内重复求值（条件在对话内通常不变）。
const COND_TTL_MS := 1000
var _cond_cache: Dictionary = {}   # key -> {"ts":int, "val":bool}

# ---- 运行时会话状态（仅本次对话有效，不进存档）----
var _npc_id: String = ""
var _dialog_id: String = ""
var _lines: Array = []
var _index: Dictionary = {}      # line_id -> line dict
var _current_id: String = ""
var _session_active: bool = false


## 取某段对话配置（原始条目）；不存在返回空字典
func get_dialog(dialog_id: String) -> Dictionary:
	return ConfigManager.get_dialog(dialog_id)

func has_dialog(dialog_id: String) -> bool:
	return ConfigManager.has_dialog(dialog_id)

## 为某 NPC 解析应播放的对话（显式 dialog_id 优先，否则以 npc_id 回退，再否则读 NPC 配置里的 dialog_id）
func resolve_for_npc(npc_id: String, dialog_id_hint: String = "") -> Dictionary:
	var resolved_id := ""
	if not dialog_id_hint.is_empty() and has_dialog(dialog_id_hint):
		resolved_id = dialog_id_hint
	elif not npc_id.is_empty() and has_dialog(npc_id):
		resolved_id = npc_id
	elif not npc_id.is_empty() and ConfigManager.has_npc(npc_id):
		var dn: String = ConfigManager.get_npc(npc_id).get("dialog_id", "")
		if not dn.is_empty() and has_dialog(dn):
			resolved_id = dn
	if resolved_id.is_empty():
		return {}
	var data: Dictionary = get_dialog(resolved_id)
	return {"dialog_id": resolved_id, "lines": data.get("lines", [])}


## 是否有正在进行的对话
func is_active() -> bool:
	return _session_active

## 当前对话的 NPC id（事件/好感判定用）
func get_npc_id() -> String:
	return _npc_id

## 当前对话 id（UI 关闭时发射 dialogue_ended 用）
func get_dialog_id() -> String:
	return _dialog_id


# === 会话生命周期 ===
## 取/编译某段对话的"会话就绪结构"（深拷贝 lines + __id 索引）。
## 命中缓存直接返回，避免每次 start 都 duplicate(true) + 重建索引。
func _get_compiled(dialog_id: String) -> Dictionary:
	if _parsed_cache.has(dialog_id):
		return _parsed_cache[dialog_id]
	var data: Dictionary = get_dialog(dialog_id)
	var lines: Array = data.get("lines", []).duplicate(true)   # 复制，避免改到 ConfigManager 缓存
	var index: Dictionary = {}
	for i in range(lines.size()):
		var lid: String = lines[i].get("id", "line_%d" % i)
		lines[i]["__id"] = lid
		index[lid] = lines[i]
	var compiled := {"lines": lines, "index": index}
	_parsed_cache[dialog_id] = compiled
	return compiled

## 开启一段对话，返回首行渲染数据；无内容返回 {"ended": true}
func start(npc_id: String, dialog_id_hint: String = "") -> Dictionary:
	# 多 NPC 并发/连续开场：先干净收尾上一个会话，杜绝状态串味（P3 状态栈隔离）
	if _session_active:
		_terminate_session()
	var resolved: Dictionary = resolve_for_npc(npc_id, dialog_id_hint)
	if resolved.is_empty():
		_terminate_session()
		return {"ended": true}
	_npc_id = npc_id
	_dialog_id = resolved.get("dialog_id", "")
	ConfigManager.pin_dialog(_dialog_id)   # 锁定当前分片，避免会话中途被闲置回收
	var compiled: Dictionary = _get_compiled(_dialog_id)   # 命中缓存则零深拷贝/零重建
	_lines = compiled["lines"]          # 会话只读取，与缓存共享引用安全
	_index = compiled["index"]
	_current_id = _lines[0].get("__id", "") if _lines.size() > 0 else ""
	_session_active = true
	EventBus.dialogue_started.emit(_dialog_id, _npc_id)
	return _present_current()

## 无选项时"继续"：按 next_id 前进；为空则结束
func next() -> Dictionary:
	if not _session_active:
		return {"ended": true}
	var line: Dictionary = _index.get(_current_id, {})
	var nid: String = line.get("next_id", "")
	if nid == "":
		_terminate_session()
		return {"ended": true}
	_current_id = nid
	return _present_current()

## 选择分支选项：跳转到 jump_id
func select_option(jump_id: String) -> Dictionary:
	if not _session_active or jump_id == "":
		return {"ended": true}
	_current_id = jump_id
	return _present_current()

## 结束会话（由 UI 关闭时调用；若已自然结束则为空操作）
func end() -> void:
	_terminate_session()

## 清空已解析对话缓存（如对话配置热重载后调用，避免复用过期编译结果）
func clear_cache() -> void:
	_parsed_cache.clear()

## 清空条件预检缓存（配置热重载/测试用）
func clear_condition_cache() -> void:
	_cond_cache.clear()

## 当前条件缓存条目数（测试/诊断用）
func get_condition_cache_size() -> int:
	return _cond_cache.size()


func _terminate_session() -> void:
	if not _dialog_id.is_empty():
		ConfigManager.unpin_dialog(_dialog_id)   # 释放分片锁定
	_session_active = false
	_npc_id = ""
	_dialog_id = ""
	_lines = []          # 重赋值（不动缓存中的共享数组）
	_index = {}          # 重赋值（不动缓存中的共享索引字典）
	_current_id = ""
	_cond_cache.clear()  # 会话结束清空条件缓存，保证下一段对话（另一 NPC）条件隔离


# === 渲染数据组装 ===
## 推进到当前行并产出渲染数据；条件不满足自动跳过（带防环守卫，避免文档里递归爆栈）
func _present_current() -> Dictionary:
	var guard := 0
	while guard < 200:
		guard += 1
		var line: Dictionary = _index.get(_current_id, {})
		if line.is_empty():
			_terminate_session()
	
			return {"ended": true}
		if not _check_condition(line.get("cond", null)):
			var nid: String = line.get("next_id", "")
			if nid == "":
				_terminate_session()
		
				return {"ended": true}
			_current_id = nid
			continue
		# 触发本行绑定的剧情事件（配置化；事件未订阅仅不生效，不崩）
		for ev in line.get("trigger_events", []):
			if ev is String and ev != "":
				EventBus.dialogue_event_triggered.emit(ev)
		return _render_line(line)
	_terminate_session()
	EventBus.dialogue_ended.emit(_dialog_id)
	return {"ended": true}

func _render_line(line: Dictionary) -> Dictionary:
	var speaker_id: String = line.get("speaker_id", "")
	var is_player: bool = (speaker_id == PLAYER_ID)
	var name: String = line.get("speaker_name", "")
	if name == "":
		name = _resolve_name(speaker_id)
	var bust: String = _resolve_bust(speaker_id, is_player)
	var opts: Array = []
	for o in line.get("options", []):
		if _check_condition(o.get("cond", null)):
			opts.append({"text": o.get("text", ""), "jump_id": o.get("jump_id", "")})
	return {
		"speaker_name": name,
		"speaker_id": speaker_id,
		"is_player": is_player,
		"text": line.get("text", ""),
		"bust": bust,
		"options": opts,
		"ended": false,
	}

func _resolve_name(sid: String) -> String:
	if sid == "":
		return ""
	if sid == PLAYER_ID:
		return ConfigManager.get_player().get("name", "李十五")
	var npc: Dictionary = ConfigManager.get_npc(sid)
	if not npc.is_empty() and npc.has("name"):
		return npc["name"]
	return sid

func _resolve_bust(sid: String, is_player: bool) -> String:
	if is_player:
		return ConfigManager.get_player().get("bust", "")
	var npc: Dictionary = ConfigManager.get_npc(sid)
	if not npc.is_empty():
		var b: String = npc.get("bust", "")
		if b == "":
			b = npc.get("portrait", "")
		return b
	return ""

## 条件系统：对接任务/背包/好感；cond 为 null/空 表示恒真。
## cond 结构：{"kind":"quest_active"|"has_item"|"favor", "arg":<String|int>}
## 相关服务未初始化时条件判否（安全降级，不崩）。
## P3 优化：结果按 (kind|arg|npc) 缓存 1s，避免密集分支/选项中重复打服务。
func _check_condition(cond: Variant) -> bool:
	if cond == null:
		return true
	if cond is Dictionary and cond.is_empty():
		return true
	if not (cond is Dictionary):
		return true
	var key: String = _cond_key(cond)
	var cached: Variant = _cond_cache.get(key, null)
	if cached != null and (Time.get_ticks_msec() - int(cached.get("ts", 0))) < COND_TTL_MS:
		return bool(cached.get("val", true))
	var val: bool = _eval_condition(cond)
	_cond_cache[key] = {"ts": Time.get_ticks_msec(), "val": val}
	return val

## 条件缓存 key：favor 依赖 _npc_id，故并入 key 保证不同 NPC 条件隔离
func _cond_key(cond: Dictionary) -> String:
	return "%s|%s|%s" % [cond.get("kind", ""), str(cond.get("arg", "")), _npc_id]

## 实际条件求值（拆出便于缓存）
func _eval_condition(cond: Dictionary) -> bool:
	var kind: String = cond.get("kind", "")
	var arg = cond.get("arg", null)
	match kind:
		"quest_active":
			return GameManager.quest_service.is_active(String(arg)) if GameManager.quest_service else false
		"has_item":
			return GameManager.inventory_service.get_item_count(String(arg)) > 0 if GameManager.inventory_service else false
		"favor":
			var need: int = int(arg)
			return GameManager.bond_service.get_affection(_npc_id) >= need if GameManager.bond_service else false
		_:
			return true
