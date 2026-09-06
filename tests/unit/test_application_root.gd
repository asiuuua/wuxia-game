# tests/unit/test_application_root.gd
# ADR-0007 批A（2026-09-06）：ApplicationRoot 装配骨架契约测试。
# 01 图 §73 纪律锚定：Create/Inject/组装完整性/注入同源——装配段禁业务事件禁读档（结构性：本测试
# 装配前后 SaveManager saveable 计数不因 assemble 变化=Register 段未越界移交前的纪律快照）。

extends TestBase
class_name TestApplicationRoot

func test_assemble_completes_all_services() -> void:
	var root := ApplicationRoot.new()
	root.assemble()
	expect(root.is_assembled(), "assemble 后应为已装配态")
	expect(root.combat_service != null, "combat_service 应就绪")
	expect(root.quest_service != null, "quest_service 应就绪")
	expect(root.effect_registry != null, "effect_registry 应就绪")
	expect(root.relationship_service != null, "relationship_service 应就绪")

func test_inject_shares_same_registry() -> void:
	var root := ApplicationRoot.new()
	root.assemble()
	# QD-2 同源纪律：quest 与 dialogue_event_executor 共享同一 EffectRegistry
	expect(root.quest_service.effects == root.effect_registry,
		"quest_service.effects 应与 effect_registry 同源")
	expect(root.dialogue_event_executor != null, "dialogue_event_executor 应就绪")

func test_assemble_no_saveable_side_effect() -> void:
	# 01 §73：组装段禁 Register 越界——saveable 注册权留 GameManager（批B 移交）
	var before := SaveManager.get_saveable_count()
	var root := ApplicationRoot.new()
	root.assemble()
	expect_eq(SaveManager.get_saveable_count(), before, "assemble 不得注册 saveable（Register 段未移交）")

func test_adopt_forwards_references() -> void:
	var root := ApplicationRoot.new()
	root.assemble()
	# 引用转发语义：adopt 后 GameManager 成员与 root 同一实例（非拷贝重建）
	GameManager._adopt_from(root)
	expect(GameManager.quest_service == root.quest_service, "adopt 后 quest_service 应同实例")
	expect(GameManager.effect_registry == root.effect_registry, "adopt 后 effect_registry 应同实例")
	expect(GameManager.quest_service.effects == GameManager.effect_registry,
		"adopt 后注入同源关系保持")
