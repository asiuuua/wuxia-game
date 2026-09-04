# services/dialogue/dialogue_event_executor.gd
# 对话事件执行器：订阅 EventBus.dialogue_event_triggered，把对话行配置的
# trigger_events 真正演出（音效 / 震屏 / 接任务 / 交任务）。
# 数据驱动：事件键 -> 效果列表，见 data/configs/dialogs/dialogue_events.json。
# 配置缺失或服务未就绪时安全降级，绝不崩（与"事件未订阅仅不生效"哲学一致）。

class_name DialogueEventExecutor
extends RefCounted

## 订阅对话事件总线；由 GameManager 装配时调用一次
func setup() -> void:
	if EventBus != null:
		EventBus.dialogue_event_triggered.connect(_on_event)

## 取消订阅（GameManager 卸载 / 配置热重载时）
func teardown() -> void:
	if EventBus != null and EventBus.dialogue_event_triggered.is_connected(_on_event):
		EventBus.dialogue_event_triggered.disconnect(_on_event)

## 事件入口：event_key 来自对话行的 trigger_events
func _on_event(event_key: String) -> void:
	if event_key == "":
		return
	var effects: Array = ConfigManager.get_dialogue_event(event_key)
	for eff in effects:
		if not (eff is Dictionary):
			continue
		_apply_effect(eff)

## 行内命令执行（P2 区域分片协议 2026-09-04）：
## 把 "set_flag:nv_flag_x" / "quest_accept:nv_quest_guard" 这类字符串命令直接执行。
## 与 trigger_events（事件键间接查 dialogue_events.json）并存分工：
##   - trigger_events：老协议，间接查表，保留兼容（dlg_tutorial 等存量分片在用）
##   - effects：新协议，行/选项直接携带命令字符串（工作室剧情设计台产出的格式）
## P3 统一 CommandDispatcher 时两者归一。未知命令仅告警不崩。
func apply_inline(cmd: String) -> void:
	if cmd == "":
		return
	var parts := cmd.split(":", true, 1)
	var c := parts[0].strip_edges()
	var arg := ""
	if parts.size() > 1:
		arg = parts[1].strip_edges()
	match c:
		"set_flag":
			# "set_flag:键"（默认true）或 "set_flag:键=值"
			var key := arg
			var val: Variant = true
			if arg.find("=") != -1:
				var kv := arg.split("=", true, 1)
				key = kv[0].strip_edges()
				val = kv[1].strip_edges()
			if key != "":
				FlagStore.new().set_flag(key, val)
		"quest_accept":
			_accept_quest(arg)
		"quest_complete":
			_complete_quest(arg)
		"sfx":
			_play_sfx(arg)
		_:
			push_warning("[DialogueEvent] 未知行内命令: %s" % cmd)

## 按效果类型分发；单条出错不影响其余，整体不崩
func _apply_effect(eff: Dictionary) -> void:
	var type: String = eff.get("type", "")
	match type:
		"sfx":
			_play_sfx(String(eff.get("path", "")))
		"shake":
			_shake(float(eff.get("intensity", 6.0)), float(eff.get("duration", 0.35)))
		"quest_accept":
			_accept_quest(String(eff.get("quest_id", "")))
		"quest_complete":
			_complete_quest(String(eff.get("quest_id", "")))
		_:
			push_warning("[DialogueEvent] 未知效果类型: %s" % type)

## 音效：缺失文件静默跳过（占位期音频未到位，避免日志噪声，与 UI 音效一致）
func _play_sfx(path: String) -> void:
	if path == "" or AudioManager == null:
		return
	if not ResourceLoader.exists(path):
		return
	AudioManager.play_sfx(path)

## 震屏：拿当前场景相机做短暂随机偏移 Tween；无相机或不可用时跳过
func _shake(intensity: float, duration: float) -> void:
	if intensity <= 0.0 or GameManager == null:
		return
	var tree := GameManager.get_tree()
	if tree == null or tree.get_current_scene() == null:
		return
	var vp := tree.get_current_scene().get_viewport()
	var cam := vp.get_camera_2d()
	if cam == null:
		return
	var base := cam.offset
	var steps := int(max(1, round(duration / 0.05)))
	var tw := tree.create_tween()
	tw.set_loops(steps)
	tw.tween_method(
		func(_v: float) -> void:
			if not is_instance_valid(cam):
				return
			cam.offset = base + Vector2(randf_range(-intensity, intensity), randf_range(-intensity, intensity)),
		0.0, 1.0, 0.05)
	tw.finished.connect(func() -> void:
		if is_instance_valid(cam):
			cam.offset = base)

## 接任务：委托 quest_service
func _accept_quest(quest_id: String) -> void:
	if quest_id == "" or GameManager == null or GameManager.quest_service == null:
		return
	GameManager.quest_service.accept(quest_id)

## 交任务：委托 quest_service（存在该方法时）
func _complete_quest(quest_id: String) -> void:
	if quest_id == "" or GameManager == null or GameManager.quest_service == null:
		return
	if GameManager.quest_service.has_method("complete_quest"):
		GameManager.quest_service.complete_quest(quest_id)
