# autoload/GameManager.gd
# 游戏状态管理：持有玩家运行时状态与核心业务服务实例（规范 §0.3 依赖注入）
# 铁律：业务层不持有 Node；跨模块通信只走 EventBus；场景切换统一由本单例驱动

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

const ResourceManager = preload("res://core/resource_manager.gd")

var player_state: PlayerState = null
var combat_service: CombatService = null
var inventory_service: InventoryService = null
var ability_service: AbilityService = null
var quest_service: QuestService = null
var equipment_service: EquipmentService = null
var alchemy_service: AlchemyService = null
var forge_service: ForgeService = null
var shop_service: ShopService = null
var sect_service: SectService = null
var dialogue_service: DialogueService = null
var dialogue_event_executor: DialogueEventExecutor = null   # 订阅对话事件演出音效/震屏/接任务
var bond_service: BondService = null
var romance_service: RomanceService = null
var sworn_service: SwornService = null          # 结义服务（M4：结义分支）
var master_service: MasterService = null        # 师徒服务（M4：师徒分支）
var relationship_service: RelationshipService = null   # 关系网数据中枢（M3：聚合门面，无状态不存档）

var pending_battle_id: String = ""     # 由 NPC/剧情设置，战斗场景读取
var current_slot: int = -1             # 当前游戏所在存档槽位（-1 表示尚未存档）；HELL 删档时定点删除
var _last_known_day: int = 1             # 姻缘子嗣推进用的天数基线（M3）             # 当前游戏所在存档槽位（-1 表示尚未存档）；HELL 删档时定点删除

var last_wedding := {}

func _ready() -> void:
	player_state = PlayerState.new()
	player_state.init_default("李十五", 1)
	_init_services()
	_register_saveables()
	# 战斗结束 → 任务系统推进目标（事件闭环，替代原先战斗直调任务的反模式）
	EventBus.combat_finished.connect(quest_service._on_combat_finished)
	# 指令接线：任务/对话发出 cmd_start_combat 后自动开战（解耦战斗入口，消除空壳）
	EventBus.cmd_start_combat.connect(_on_cmd_start_combat)
	# 对话事件演出：到达某行 trigger_events 经 EventBus 派发，由执行器演出音效/震屏/接任务
	dialogue_event_executor.setup()
	# 追踪当前存档槽位（读档/存档时更新），供 HELL 删档定点删除
	EventBus.game_saved.connect(_on_slot_event)
	EventBus.game_loaded.connect(_on_slot_event)
	# 时间推进 → 姻缘子嗣（怀胎十月）随天数推进（M3：接 TimeService/WeatherTimeService）
	EventBus.world_day_advanced.connect(_on_world_day_advanced)
	# 婚礼演出：监听 bond_wedding_started 切到婚礼场景（M3：接 BondService.hold_wedding）
	EventBus.bond_wedding_started.connect(_on_bond_wedding_started)
	_sync_day_baseline()

# 每帧驱动武学快捷栏实时冷却递减（冷却状态源真值在 AbilityService.cd_remaining）
func _process(delta: float) -> void:
	if ability_service != null:
		ability_service.tick_cooldowns(delta)

func _init_services() -> void:
	combat_service = CombatService.new()
	inventory_service = InventoryService.new()
	ability_service = AbilityService.new()
	quest_service = QuestService.new()
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
	relationship_service = RelationshipService.new()

func _register_saveables() -> void:
	SaveManager.register_saveable(player_state)
	SaveManager.register_saveable(inventory_service)
	SaveManager.register_saveable(ability_service)
	SaveManager.register_saveable(quest_service)
	SaveManager.register_saveable(equipment_service)
	# 门派系统有持久状态（当前门派 + 声望 + 阶位），需存档；锻造/商店为纯配置驱动无状态，不存档
	SaveManager.register_saveable(sect_service)
	SaveManager.register_saveable(bond_service)
	SaveManager.register_saveable(romance_service)
	SaveManager.register_saveable(sworn_service)
	SaveManager.register_saveable(master_service)
	# GameState 是全局状态中枢，作为存档序列化唯一来源之一
	SaveManager.register_saveable(GameState)

## 新游戏：重置全部状态并装配初始武学（规范 §4 学习）
func start_new_game() -> void:
	player_state.init_default("李十五", 1)
	inventory_service.reset()
	ability_service.reset()
	quest_service.reset()
	equipment_service.reset()
	sect_service.reset()
	bond_service.reset()
	romance_service.reset()
	sworn_service.reset()
	master_service.reset()
	GameState.reset()
	WeatherTimeService.reset()
	_sync_day_baseline()
	_equip_starting_abilities()
	get_tree().change_scene_to_file(PathConstants.SCENE_TOWN)

## 读取存档并进入游戏（主菜单"继续江湖路"调用，M2 新增）
func load_game(slot: int) -> void:
	ResourceManager.reclaim_all()
	if SaveManager.load_from_slot(slot):
		get_tree().change_scene_to_file(PathConstants.SCENE_TOWN)
	else:
		GameLogger.warn("GameManager", "读取存档失败: slot=%d" % slot)

## 开战：记录待打战斗并切换到战斗场景
## 战术战棋战斗（配置 tactical=true）路由到 TacticalBattleScene，其余走经典 BattleScene（旧战斗零影响）
func start_battle(battle_id: String) -> void:
	# 工业化扩容 P6：切场景前集中回收温存/冷资源（CG/语音/立绘/战斗实体池统一释放口）
	ResourceManager.reclaim_all()
	pending_battle_id = battle_id
	if ConfigManager.get_battle(battle_id).get("tactical", false):
		get_tree().change_scene_to_file(PathConstants.SCENE_TACTICAL_BATTLE)
	else:
		get_tree().change_scene_to_file(PathConstants.SCENE_BATTLE)

## 指令接线：任务/对话发出 cmd_start_combat(attacker_list, defender_list) 后自动开战。
## defender_list 元素为 NPC id（或 enemy id），优先按 NPC 的 battle_id 解析战斗配置。
func _on_cmd_start_combat(attacker_list: Array, defender_list: Array) -> void:
	var battle_id: String = ""
	for d in defender_list:
		var npc: Dictionary = ConfigManager.get_npc(String(d))
		if not npc.is_empty() and npc.get("battle_id", "") != "":
			battle_id = npc["battle_id"]
			break
	if battle_id == "":
		GameLogger.warn("GameManager", "cmd_start_combat 无法解析 battle_id，defenders=%s" % defender_list)
		return
	start_battle(battle_id)

## 回城：从战斗/其他场景返回城镇
func return_to_town() -> void:
	# 工业化扩容 P6：回城前集中回收（战斗实体已在本窗 finalize 释放，此处清温存/冷资源 + 立绘缓存）
	ResourceManager.reclaim_all()
	get_tree().change_scene_to_file(PathConstants.SCENE_TOWN)

## 返回标题：清理 UI 栈并重新加载启动入口（Bootstrap 会再次打开加载界面并进入主菜单）
func return_to_title() -> void:
	UIManager.close_all_screens()
	ResourceManager.reclaim_all()
	get_tree().change_scene_to_file(PathConstants.SCENE_BOOTSTRAP)

## 读档/存档事件：记录当前槽位（仅真实槽位 >=1 才记；quick_save(-1) 忽略）
func _on_slot_event(slot: int) -> void:
	if slot >= 1:
		current_slot = slot
	_sync_day_baseline()  # 读档后天数可能跳变，重设基线避免子嗣孕期被错误快进（M3）

## 时间推进时驱动姻缘子嗣（advance_days 随天数推进孕期）
func _on_world_day_advanced(day: int) -> void:
	var delta: int = day - _last_known_day
	if delta > 0 and romance_service != null:
		romance_service.advance_days(delta)
	_last_known_day = day

## 同步天数基线（新游戏/读档后避免子嗣孕期被错误快进）
func _sync_day_baseline() -> void:
	_last_known_day = WeatherTimeService.get_day()

## 婚礼演出：监听 bond_wedding_started，记录婚礼信息并切换到婚礼场景（路径为空则仅提示）
func _on_bond_wedding_started(npc_id: String, wedding_type: int, scene_path: String) -> void:
	last_wedding = {"npc_id": npc_id, "wedding_type": wedding_type, "scene_path": scene_path}
	if scene_path == null or scene_path.is_empty():
		GameLogger.info("GameManager", "婚礼场景路径为空，跳过切换（npc=%s）" % npc_id)
		return
	get_tree().change_scene_to_file(scene_path)

## 回安全点（EASY 团灭）：切换到城镇场景并恢复队伍状态（由 DefeatHandler 调用）
func return_to_safe_point() -> void:
	var sp: Dictionary = GameState.get_last_safe_point()
	# 当前所有安全点都映射到城镇场景；marker 预留给后续扩展（客栈/营地等不同场景）
	GameLogger.info("GameManager", "回安全点: %s" % sp.get("marker", "town"))
	ResourceManager.reclaim_all()
	get_tree().change_scene_to_file(PathConstants.SCENE_TOWN)

func _equip_starting_abilities() -> void:
	var slot := 0
	for ability_id in ConfigManager.get_all_ability_ids():
		var data: Dictionary = ConfigManager.get_ability(ability_id)
		if data.get("learned_by_default", false):
			ability_service.learn(ability_id)
			if data.get("type", 0) == AbilityEnums.AbilityType.EXTERNAL and slot < AbilityService.MAX_COMBAT_SKILLS:
				ability_service.equip_combat_skill(slot, ability_id)
				slot += 1
