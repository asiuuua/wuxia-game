# tests/unit/test_dialogue_event_executor.gd
# DialogueEventExecutor 单测：验证事件键 -> 效果演出，且缺失配置/资源时安全降级。

extends TestBase
class_name TestDialogueEventExecutor

func test_unknown_event_key_no_crash() -> void:
	var ex := DialogueEventExecutor.new()
	ex._on_event("__no_such_event__")
	expect(true, "未知事件键不应崩")

func test_missing_sfx_path_silent() -> void:
	var ex := DialogueEventExecutor.new()
	ex._on_event("__missing_sfx_event__")   # 未配置：查表空数组，不崩
	ex._play_sfx("")                          # 空路径：直接返回
	ex._play_sfx("res://resources/audio/sfx/does_not_exist.ogg")  # 缺失文件：静默跳过
	expect(true, "缺失音效路径不应崩")

func test_quest_accept_effect() -> void:
	if GameManager == null or GameManager.quest_service == null:
		expect(false, "GameManager.quest_service 不可用，无法验证接任务")
		return
	var ex := DialogueEventExecutor.new()
	ex._on_event("accept_demo_quest")   # dialogue_events.json 映射到 demo_quest
	expect(GameManager.quest_service.is_active("demo_quest"), "触发 accept_demo_quest 后 demo_quest 应处于激活")
