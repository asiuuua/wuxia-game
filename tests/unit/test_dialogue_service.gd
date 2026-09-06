# tests/unit/test_dialogue_service.gd
# DialogueService 单测：验证 NPC / 台词 / 对话框解耦后的查询规则。

extends TestBase
class_name TestDialogueService

func test_get_existing_dialog() -> void:
	var svc := DialogueService.new()
	var d: Dictionary = svc.get_dialog("npc_merchant")
	expect(not d.is_empty(), "应能取到 npc_merchant 对话")
	expect(d.get("lines", []).size() > 0, "npc_merchant 对话应含台词")

func test_get_missing_dialog_returns_empty() -> void:
	var svc := DialogueService.new()
	var d: Dictionary = svc.get_dialog("not_exist_dialog_xxx")
	expect(d.is_empty(), "不存在的对话应返回空字典")

func test_has_dialog() -> void:
	var svc := DialogueService.new()
	expect(svc.has_dialog("npc_village_chief"), "应存在 npc_village_chief 对话")
	expect(not svc.has_dialog("missing"), "不存在的对话应返回 false")

func test_resolve_explicit_dialog_id() -> void:
	var svc := DialogueService.new()
	var r: Dictionary = svc.resolve_for_npc("npc_village_chief", "dlg_tutorial")
	expect(String(r.get("dialog_id", "")) == "dlg_tutorial", "显式 dialog_id 应优先命中")
	expect(r.get("lines", []).size() > 0, "显式 dialog_id 应有台词")

func test_resolve_fallback_to_npc_id() -> void:
	var svc := DialogueService.new()
	var r: Dictionary = svc.resolve_for_npc("npc_merchant", "")
	expect(String(r.get("dialog_id", "")) == "npc_merchant", "未传 dialog_id 时应以 npc_id 回退")
	expect(r.get("lines", []).size() == 2, "npc_merchant 应有 2 句台词")

func test_resolve_missing_returns_empty() -> void:
	var svc := DialogueService.new()
	var r: Dictionary = svc.resolve_for_npc("not_exist_npc_xxx", "")
	expect(r.is_empty(), "既无显式 dialog_id 也无 npc_id 键时应返回空")


# === 以下验证图模型：分支/条件/事件 ===
var _got_event: String = ""

func _on_dialogue_event(k: String) -> void:
	_got_event = k

func test_start_returns_first_render() -> void:
	var svc := DialogueService.new()
	var r: Dictionary = svc.start("npc_merchant", "")
	expect(not r.get("ended", false), "npc_merchant 首行不应 ended")
	expect(String(r.get("speaker_name", "")) == "货郎", "首行说话人应为货郎")
	expect(not r.get("is_player", false), "货郎不是主角")
	expect(r.get("options", []).size() == 0, "npc_merchant 首行无选项")

func test_linear_next_reaches_end() -> void:
	var svc := DialogueService.new()
	var r: Dictionary = svc.start("npc_merchant", "")
	r = svc.next()
	expect(not r.get("ended", false), "第二行不应 ended")
	r = svc.next()
	expect(r.get("ended", false), "npc_merchant 共 2 行，next 两次后应 ended")

func test_branch_select_option() -> void:
	var svc := DialogueService.new()
	var r: Dictionary = svc.start("npc_village_chief", "")
	expect(String(r.get("speaker_id", "")) == "npc_village_chief", "首句应为村长")
	r = svc.next()  # vc_2 含分支选项
	expect(r.get("options", []).size() >= 1, "vc_2 应含分支选项")
	var jump := ""
	for o in r.get("options", []):
		if o.get("text", "") == "义不容辞，这就去":
			jump = o.get("jump_id", "")
	expect(jump == "vc_yes", "应能找到 vc_yes 跳转")
	r = svc.select_option(jump)
	expect(r.get("is_player", false), "vc_yes 应为玩家说话")
	expect(String(r.get("speaker_id", "")) == "player", "vc_yes 说话人应为 player")

func test_option_condition_hides_when_unmet() -> void:
	var svc := DialogueService.new()
	var r: Dictionary = svc.start("npc_village_chief", "")
	r = svc.next()  # vc_2
	var has_toast := false
	for o in r.get("options", []):
		if o.get("jump_id", "") == "vc_toast":
			has_toast = true
	# 好感条件默认未满足（测试环境无 bond_service 或好感 <50），应隐藏该选项
	expect(not has_toast, "好感未满时 vc_toast 选项应被条件隐藏")

func test_trigger_event_emitted() -> void:
	_got_event = ""
	EventBus.dialogue_event_triggered.connect(_on_dialogue_event)
	DialogueService.new().start("npc_bandit", "")  # bd_1 含 trigger_events: sfx_bandit_threat
	EventBus.dialogue_event_triggered.disconnect(_on_dialogue_event)
	expect(_got_event == "sfx_bandit_threat", "进入首句应触发绑定的剧情事件")

# === 已解析对话缓存层 ===
func test_parsed_cache_reuses_compiled() -> void:
	var svc := DialogueService.new()
	var r1: Dictionary = svc.start("npc_merchant", "")
	expect(svc._parsed_cache.has("npc_merchant"), "首次启动后应缓存 npc_merchant 编译结果")
	expect(not r1.get("ended", false), "首行不应 ended")
	svc.end()
	var r2: Dictionary = svc.start("npc_merchant", "")  # 再次启动同一对话
	expect(svc._parsed_cache.size() == 1, "重复启动同一对话不应重复编译（缓存命中）")
	expect(not r2.get("ended", false), "二次启动首行仍正常")
	svc.start("npc_village_chief", "")  # 不同对话应各自编译
	expect(svc._parsed_cache.size() == 2, "不同对话应各自编译并缓存，不互相覆盖")
	svc.clear_cache()
	expect(svc._parsed_cache.is_empty(), "clear_cache 应清空缓存")

# === 事件系统技术演示对话 ===
func test_event_demo_dialogue_loads() -> void:
	var svc := DialogueService.new()
	var r: Dictionary = svc.start("event_demo_npc", "")
	expect(not r.get("ended", false), "演示对话应正常加载、首行不 ended")
	var lines: Array = svc._lines
	expect(lines.size() == 6, "演示对话应含 6 行")
	var keys: Array[String] = []
	for ln in lines:
		for ev in ln.get("trigger_events", []):
			keys.append(String(ev))
	expect(keys.has("sfx_elder_appear"), "演示对话应含音效事件 sfx_elder_appear")
	expect(keys.has("bandit_threat_shake"), "演示对话应含震屏事件 bandit_threat_shake")
	expect(keys.has("accept_demo_quest"), "演示对话应含接任务事件 accept_demo_quest")

# === P1 工业化扩容：对话分片懒加载 / 闲置卸载 / pin 保护 ===
func test_dialog_lazy_load_and_unload() -> void:
	ConfigManager.unload_dialog("npc_merchant")  # 清掉可能来自其它测试的残留
	expect(not ConfigManager._shard_cache.has("npc_merchant"), "清理后分片不应在缓存")
	var d: Dictionary = ConfigManager.get_dialog("npc_merchant")
	expect(not d.is_empty(), "懒加载应取到 npc_merchant 分片")
	expect(ConfigManager._shard_cache.has("npc_merchant"), "取值后应进入缓存")
	ConfigManager.unload_dialog("npc_merchant")
	expect(not ConfigManager._shard_cache.has("npc_merchant"), "unload 后应释放")
	var d2: Dictionary = ConfigManager.get_dialog("npc_merchant")
	expect(not d2.is_empty(), "重新懒加载应再次取到")

func test_dialog_pin_blocks_unload() -> void:
	ConfigManager.unload_dialog("npc_bandit")
	ConfigManager.get_dialog("npc_bandit")
	ConfigManager.pin_dialog("npc_bandit")
	ConfigManager.unload_dialog("npc_bandit")  # pin 中不应释放
	expect(ConfigManager._shard_cache.has("npc_bandit"), "pin 中 unload 不释放")
	ConfigManager.unpin_dialog("npc_bandit")
	ConfigManager.unload_dialog("npc_bandit")
	expect(not ConfigManager._shard_cache.has("npc_bandit"), "unpin 后 unload 释放")

func test_active_session_pins_shard() -> void:
	ConfigManager.unload_dialog("npc_merchant")
	var svc := DialogueService.new()
	svc.start("npc_merchant", "")
	expect(ConfigManager._shard_cache.pin_count("npc_merchant") > 0, "会话开始应 pin 当前分片")
	svc.end()
	expect(ConfigManager._shard_cache.pin_count("npc_merchant") == 0, "会话结束应 unpin")
