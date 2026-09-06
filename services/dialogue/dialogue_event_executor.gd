# services/dialogue/dialogue_event_executor.gd
# 对话事件执行器（12 图 QD-2 收编 2026-09-06）：订阅 EventBus.dialogue_event_triggered，
# 把对话行配置的 trigger_events 查表效果 + 行内 effects DSL 统一落 EffectRegistry 执行。
# 数据驱动：事件键 -> 效果列表，见 data/configs/dialogs/dialogue_events.json。
# 本类只注册 story_flag / presentation 两类效果；reward / progress 由 QuestService.attach_effects
# 注册（与 executor 共享同一域级注册表实例，GameManager 装配注入）。
# 旧 CommandDispatcher 已退役（QD-2：执行统一落 Effect 注册表，命令分发器形态废止）。
# QD-R10：services 层禁 Node 演出——sfx 走 AudioManager（autoload 表现 API），
# shake 只经 EventBus.screen_shake_requested 产指令，相机演出由装配层执行。
# 配置缺失或注册表未注入时安全降级，绝不崩（与"事件未订阅仅不生效"哲学一致）。

class_name DialogueEventExecutor
extends RefCounted

## 域级共享注册表（GameManager 装配注入；QuestService 与本类共用同一实例）
var effects: EffectRegistry = null


## 装配入口：注入注册表 + 订阅对话事件总线（由 GameManager 调用一次）
func setup(effect_registry: EffectRegistry) -> void:
	setup_effects(effect_registry)
	if EventBus != null:
		EventBus.dialogue_event_triggered.connect(_on_event)


## 仅注册效果（测试/复用场景，不订阅总线）
func setup_effects(effect_registry: EffectRegistry) -> void:
	effects = effect_registry
	if effects == null:
		return
	effects.register("set_flag", EffectRegistry.KIND_STORY_FLAG, _effect_set_flag)
	effects.register("sfx", EffectRegistry.KIND_PRESENTATION, _effect_sfx)
	effects.register("shake", EffectRegistry.KIND_PRESENTATION, _effect_shake)
	# quest_accept / quest_complete（KIND_PROGRESS）由 QuestService.attach_effects 注册
	# ——P-Q1 死命令修复：quest_complete 直连 QuestService.turn_in（旧 has_method
	# ("complete_quest") 探测的对象方法不存在，命令端到端不可达=死命令，QD-R09 禁）。


## 取消订阅（GameManager 卸载 / 配置热重载时）
func teardown() -> void:
	if EventBus != null and EventBus.dialogue_event_triggered.is_connected(_on_event):
		EventBus.dialogue_event_triggered.disconnect(_on_event)


## 事件入口：event_key 来自对话行的 trigger_events（老协议查表，兼容期最后执行——12 图 QD-2 顺序冻结）
func _on_event(event_key: String) -> void:
	if event_key == "":
		return
	if effects == null:
		push_warning("[DialogueEvent] 注册表未注入，事件跳过: %s" % event_key)
		return
	var ctx := {"channel": "trigger_events", "event_key": event_key}
	var list: Array = ConfigManager.get_dialogue_event(event_key)
	for eff in list:
		effects.apply_dict(eff, ctx)


## 行内命令执行（新协议，行/选项 effects 优先执行——12 图 QD-2 执行顺序冻结）：
## 把 "set_flag:story_x=1" / "quest_accept:nv_quest_guard" 这类字符串命令直接执行。
## 未注册 op 由 EffectRegistry 报死命令（QD-R09），本层不再重复告警。
func apply_inline(cmd: String, ctx: Dictionary = {}) -> void:
	if cmd.strip_edges() == "" or effects == null:
		return
	var c := ctx.duplicate()
	c["channel"] = "effects"
	effects.apply_line(cmd, c)


## ---- 效果 handler（统一签名 func(payload, ctx)）----

## 剧情旗标（QD-R06 键域白名单）：kv 形态 "key=value" 或裸 key（默认 true）；
## 字典形态 {key, value}。违键域拒执 + ERROR。
## 白名单口径：story_/plot_（宪法 §70 剧情键域）+ nv_/mt_（区域分片存量兼容，
## Phase4 键域重映射随 _retired_ids.json 收编后移除——12 图迁移表 L131）。
func _effect_set_flag(payload: Variant, _ctx: Dictionary) -> void:
	var key := ""
	var val: Variant = true
	if payload is String:
		var s := String(payload)
		if s.find("=") != -1:
			var kv := s.split("=", true, 1)
			key = kv[0].strip_edges()
			val = kv[1].strip_edges()
		else:
			key = s.strip_edges()
	elif payload is Dictionary:
		key = String(payload.get("key", ""))
		val = payload.get("value", true)
	if key.is_empty():
		push_warning("[DialogueEvent] set_flag 缺键名: %s" % str(payload))
		return
	if not (key.begins_with("story_") or key.begins_with("plot_")
			or key.begins_with("nv_") or key.begins_with("mt_")):
		push_error("[DialogueEvent] set_flag 违键域白名单（story_/plot_/nv_/mt_ 存量）: %s 已拒执——QD-R06" % key)
		return
	FlagStore.new().set_flag(key, val)   # FlagStore 门面委托 GameState 全局旗标（唯一真源）


## 音效：缺失文件由 AudioManager 统一告警静默（QD-R10：本层不做 ResourceLoader 直查）
func _effect_sfx(payload: Variant, _ctx: Dictionary) -> void:
	var path := ""
	if payload is String:
		path = String(payload).strip_edges()
	elif payload is Dictionary:
		path = String(payload.get("path", "")).strip_edges()
	if path == "" or AudioManager == null:
		return
	AudioManager.play_sfx(path)


## 震屏：只产指令不碰相机（QD-R10 / P-Q10 收口）；相机 Tween 演出由 GameManager 订阅执行
func _effect_shake(payload: Variant, _ctx: Dictionary) -> void:
	var intensity := 6.0
	var duration := 0.35
	if payload is Dictionary:
		intensity = float(payload.get("intensity", 6.0))
		duration = float(payload.get("duration", 0.35))
	if intensity <= 0.0:
		return
	if EventBus != null:
		EventBus.screen_shake_requested.emit(intensity, duration)
