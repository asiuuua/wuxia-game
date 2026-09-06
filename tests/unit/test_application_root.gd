# tests/unit/test_application_root.gd
# ADR-0007 批A/B（2026-09-06）：ApplicationRoot 装配契约测试。
# 批B：Register 段已移交（assemble 注册 9 个服务 saveable）——测试用 SaveManager 隔离范式
# （备份/清空/恢复，同 test_save_header），防与生产装配实例撞 SV-4 注册锁。
# adopt 转发语义在开关 true 下由生产装配直接承载，本文件只测数据面。

extends TestBase
class_name TestApplicationRoot

var _saved_saveables: Array = []
var _saveables_touched := false

func before_each() -> void:
	# SV-4 隔离：清空 saveables 注册表，root.assemble 的注册落在干净表上
	_saved_saveables = SaveManager._saveables.duplicate()
	_saveables_touched = true
	SaveManager._saveables.clear()

func after_each() -> void:
	if _saveables_touched:
		SaveManager._saveables = _saved_saveables
		_saveables_touched = false
	SaveManager._content_version_cache = ""   # 清 content_version 缓存（防用例间泄漏）

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

func test_assemble_registers_nine_service_saveables() -> void:
	# ADR-0007 批B：Register 段移交——assemble 注册 9 个服务 saveable（隔离表上精确计数）
	var root := ApplicationRoot.new()
	root.assemble()
	expect_eq(SaveManager.get_saveable_count(), 9,
		"Register 段应注册 9 个服务 saveable（实际 %d）" % SaveManager.get_saveable_count())

func test_trade_runtime_factory_injected() -> void:
	# ADR-0007 批B 升表口：ShopTrade Runtime 工厂注入（每笔产新实例，0-C.12 合法形态）
	var root := ApplicationRoot.new()
	root.assemble()
	expect(root.trade_runtime_factory.is_valid(), "工厂应已建立")
	var rt1: TransactionRuntime = root.trade_runtime_factory.call()
	var rt2: TransactionRuntime = root.trade_runtime_factory.call()
	expect(rt1 != null and rt2 != null and rt1 != rt2, "工厂每次应产独立 Runtime 实例")

func test_adoption_semantics_documented() -> void:
	# ADR-0007 批B：adopt 转发语义由 GameManager._init_services 生产路径承载
	# （USE_APPLICATION_ROOT=true 下 root.assemble → _adopt_from 引用转发）。
	# 本用例锚定装配链纪律：GM 三服务引用与 saveable 注册一致（生产装配后读真状态）。
	expect(GameManager.inventory_service != null and GameManager.quest_service != null
		and GameManager.shop_service != null, "生产装配后三件服务应就绪")
	expect(GameManager.quest_service.effects != null, "生产装配后 quest 注入应生效")
	expect(GameManager.shop_service._trade_runtime_factory.is_valid(),
		"生产装配后 ShopTrade Runtime 工厂注入保持（批B 升表口）")
