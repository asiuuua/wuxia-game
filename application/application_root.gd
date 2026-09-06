# application/application_root.gd
# Composition Root（01 图 §73 / ADR-0007 批A，2026-09-06）：
# 唯一 Create / Inject / Register 装配点——负责组装，不负责业务规则，禁止演变成 GameManager 2.0。
# 批A 范围：Create + Inject 段（零行为，经 GameManager.USE_APPLICATION_ROOT 开关启用，
# 默认 false=旧路径 _init_services 原样保留）；Register 段（saveable 注册清单）暂留
# GameManager._register_saveables——清单含 player_state/GameState 桥等时序敏感项，批B 随服务迁移逐步移交。
# 装配期纪律（01 §73）：组装段禁读存档、禁发业务事件——由 test_application_root 锚定。

class_name ApplicationRoot
extends RefCounted

# === 服务引用（与 GameManager 同名成员；批A 经 adopt() 引用转发，调用方零改动） ===
var combat_service: CombatService = null
var inventory_service: InventoryService = null
var ability_service: AbilityService = null
var quest_service: QuestService = null
var equipment_service: EquipmentService = null
var alchemy_service: AlchemyService = null
var forge_service: ForgeService = null
var shop_service: ShopService = null
var sect_service: SectService = null
var effect_registry: EffectRegistry = null
var dialogue_service: DialogueService = null
var dialogue_event_executor: DialogueEventExecutor = null
var bond_service: BondService = null
var romance_service: RomanceService = null
var sworn_service: SwornService = null
var master_service: MasterService = null
var relationship_service: RelationshipService = null

var trade_runtime_factory: Callable = Callable()   # ADR-0007 批B 升表口：ShopTrade Runtime 工厂

var _assembled := false

func is_assembled() -> bool:
	return _assembled

## Create：全部服务单次实例化（ADR-0007 §5 批A——旧路径 quest_service 误 double-new 的修正形态）
func create() -> void:
	combat_service = CombatService.new()
	inventory_service = InventoryService.new()
	ability_service = AbilityService.new()
	effect_registry = EffectRegistry.new()
	quest_service = QuestService.new()   # 注册表就绪后再建（注入顺序：先 effect_registry 后 quest）
	equipment_service = EquipmentService.new()
	alchemy_service = AlchemyService.new()
	forge_service = ForgeService.new()
	shop_service = ShopService.new()
	sect_service = SectService.new()
	dialogue_service = DialogueService.new()
	dialogue_event_executor = DialogueEventExecutor.new()
	bond_service = BondService.new()
	romance_service = RomanceService.new()
	sworn_service = SwornService.new()
	master_service = MasterService.new()
	relationship_service = RelationshipService.new(bond_service, romance_service, sworn_service, master_service)

## Inject：域级共享注册表注入（QD-2 收编口径；组装段禁业务事件/禁读档）
func inject() -> void:
	quest_service.attach_effects(effect_registry)          # QD-2：reward/progress 效果注册
	dialogue_event_executor.setup(effect_registry)         # 12 图 QD-2：executor 与 quest 同源注册表
	# ADR-0007 批B 升表口：ShopTrade Runtime 工厂注入（每笔仍产新实例，0-C.12 合法形态）
	trade_runtime_factory = func() -> TransactionRuntime: return TransactionRuntime.new()
	shop_service.set_trade_runtime_factory(trade_runtime_factory)
	# 08图批1 TX-1 升表口：GiftTransaction Runtime 工厂注入（同款形态）
	bond_service.set_gift_runtime_factory(trade_runtime_factory)

## Register（ADR-0007 批B 移交）：服务 saveable 注册清单自 GameManager 移交本段；
## player_state / GameState 桥为时序敏感项，批C 随装配段整体移交（暂留 GameManager）。
func register_saveables() -> void:
	SaveManager.register_saveable(inventory_service)
	SaveManager.register_saveable(ability_service)
	SaveManager.register_saveable(quest_service)
	SaveManager.register_saveable(equipment_service)
	SaveManager.register_saveable(sect_service)
	SaveManager.register_saveable(bond_service)
	SaveManager.register_saveable(romance_service)
	SaveManager.register_saveable(sworn_service)
	SaveManager.register_saveable(master_service)

## 组装入口（Create → Inject → Register；01 §73 三段齐；装配完整性自检）
func assemble() -> void:
	create()
	inject()
	register_saveables()
	_assembled = true
	_assert_assembly_complete()

## 装配完整性自检（01 §73 纪律：全部引用非空 + 注入同源）
func _assert_assembly_complete() -> void:
	var missing := []
	if combat_service == null: missing.append("combat_service")
	if inventory_service == null: missing.append("inventory_service")
	if ability_service == null: missing.append("ability_service")
	if quest_service == null: missing.append("quest_service")
	if equipment_service == null: missing.append("equipment_service")
	if alchemy_service == null: missing.append("alchemy_service")
	if forge_service == null: missing.append("forge_service")
	if shop_service == null: missing.append("shop_service")
	if sect_service == null: missing.append("sect_service")
	if effect_registry == null: missing.append("effect_registry")
	if dialogue_service == null: missing.append("dialogue_service")
	if dialogue_event_executor == null: missing.append("dialogue_event_executor")
	if bond_service == null: missing.append("bond_service")
	if romance_service == null: missing.append("romance_service")
	if sworn_service == null: missing.append("sworn_service")
	if master_service == null: missing.append("master_service")
	if relationship_service == null: missing.append("relationship_service")
	if not missing.is_empty():
		push_error("[ApplicationRoot] 装配不完整，缺: %s" % ", ".join(missing))
		return
	if quest_service.effects != effect_registry:
		push_error("[ApplicationRoot] 注入失同源: quest_service.effects != effect_registry")
