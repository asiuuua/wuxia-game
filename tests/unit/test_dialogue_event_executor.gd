# tests/unit/test_dialogue_event_executor.gd
# DialogueEventExecutor 单测：验证事件键 -> 效果演出，且缺失配置/资源时安全降级。
# QD-2 收编适配（2026-09-06）：executor 需注入 EffectRegistry；sfx 缺失检测收敛 AudioManager。

extends TestBase
class_name TestDialogueEventExecutor

func _make_executor() -> DialogueEventExecutor:
	var ex := DialogueEventExecutor.new()
	ex.setup_effects(GameManager.effect_registry)
	return ex

func test_unknown_event_key_no_crash() -> void:
	var ex := _make_executor()
	ex._on_event("__no_such_event__")
	expect(true, "未知事件键不应崩")

func test_missing_sfx_path_silent() -> void:
	var ex := _make_executor()
	ex._on_event("__missing_sfx_event__")   # 未配置：查表空数组，不崩
	ex._effect_sfx("", {})                   # 空路径：直接返回
	ex._effect_sfx("res://resources/audio/sfx/does_not_exist.ogg", {})  # 缺失文件：AudioManager 告警静默
	expect(true, "缺失音效路径不应崩")

func test_quest_accept_effect() -> void:
	if GameManager == null or GameManager.quest_service == null:
		expect(false, "GameManager.quest_service 不可用，无法验证接任务")
		return
	var ex := _make_executor()
	ex._on_event("accept_demo_quest")   # dialogue_events.json 映射到 demo_quest
	expect(GameManager.quest_service.is_active("demo_quest"), "触发 accept_demo_quest 后 demo_quest 应处于激活")

func test_quest_complete_effect_end_to_end() -> void:
	# QD-R09 端到端可达契约（P-Q1 死命令修复）：quest_complete → turn_in 直连发奖
	if GameManager == null or GameManager.quest_service == null:
		expect(false, "GameManager.quest_service 不可用")
		return
	var qs := GameManager.quest_service
	# 套件内状态隔离：test_quest_accept_effect 可能已接取 demo_quest，先清残留
	qs.active_quests.erase("demo_quest")
	qs.completed_quests.erase("demo_quest")
	if not qs.accept("demo_quest"):
		expect(false, "demo_quest 应可接取")
		return
	# 直接置 COMPLETED 模拟目标已达成，再经注册表命令交付
	var st = qs.active_quests.get("demo_quest")
	if st != null:
		st.status = QuestEnums.QuestStatus.COMPLETED
	var ok: bool = GameManager.effect_registry.apply("quest_complete", "demo_quest", {})
	expect(ok, "quest_complete 应注册可达（QD-R09 端到端）")
	expect(qs.completed_quests.has("demo_quest"), "quest_complete 应直连 turn_in 完成交付")
