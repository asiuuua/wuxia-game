# autoload/GameManager.gd
# 游戏状态管理：持有玩家运行时状态与核心业务服务实例（规范 §0.3 依赖注入）
# 铁律：业务层不持有 Node；跨模块通信只走 EventBus；场景切换统一由本单例驱动

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

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

var pending_battle_id: String = ""     # 由 NPC/剧情设置，战斗场景读取
var current_slot: int = -1             # 当前游戏所在存档槽位（-1 表示尚未存档）；HELL 删档时定点删除

func _ready() -> void:
	player_state = PlayerState.new()
	player_state.init_default("李十五", 1)
	_init_services()
	_register_saveables()
	# 战斗结束 → 任务系统推进目标（事件闭环，替代原先战斗直调任务的反模式）
	EventBus.combat_finished.connect(quest_service._on_combat_finished)
	# 指令接线：任务/对话发出 cmd_start_combat 后自动开战（解耦战斗入口，消除空壳）
	EventBus.cmd_start_combat.connect(_on_cmd_start_combat)
	# 追踪当前存档槽位（读档/存档时更新），供 HELL 删档定点删除
	EventBus.game_saved.connect(_on_slot_event)
	EventBus.game_loaded.connect(_on_slot_event)

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

func _register_saveables() -> void:
	SaveManager.register_saveable(player_state)
	SaveManager.register_saveable(inventory_service)
	SaveManager.register_saveable(ability_service)
	SaveManager.register_saveable(quest_service)
	SaveManager.register_saveable(equipment_service)
	# 门派系统有持久状态（当前门派 + 声望 + 阶位），需存档；锻造/商店为纯配置驱动无状态，不存档
	SaveManager.register_saveable(sect_service)
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
	GameState.reset()
	WeatherTimeService.reset()
	_equip_starting_abilities()
	get_tree().change_scene_to_file(PathConstants.SCENE_TOWN)

## 读取存档并进入游戏（主菜单"继续江湖路"调用，M2 新增）
func load_game(slot: int) -> void:
	if SaveManager.load_from_slot(slot):
		get_tree().change_scene_to_file(PathConstants.SCENE_TOWN)
	else:
		GameLogger.warn("GameManager", "读取存档失败: slot=%d" % slot)

## 开战：记录待打战斗并切换到战斗场景
func start_battle(battle_id: String) -> void:
	pending_battle_id = battle_id
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
	get_tree().change_scene_to_file(PathConstants.SCENE_TOWN)

## 返回标题：清理 UI 栈并重新加载启动入口（Bootstrap 会再次打开加载界面并进入主菜单）
func return_to_title() -> void:
	UIManager.close_all_screens()
	get_tree().change_scene_to_file(PathConstants.SCENE_BOOTSTRAP)

## 读档/存档事件：记录当前槽位（仅真实槽位 >=1 才记；quick_save(-1) 忽略）
func _on_slot_event(slot: int) -> void:
	if slot >= 1:
		current_slot = slot

## 回安全点（EASY 团灭）：切换到城镇场景并恢复队伍状态（由 DefeatHandler 调用）
func return_to_safe_point() -> void:
	var sp: Dictionary = GameState.get_last_safe_point()
	# 当前所有安全点都映射到城镇场景；marker 预留给后续扩展（客栈/营地等不同场景）
	GameLogger.info("GameManager", "回安全点: %s" % sp.get("marker", "town"))
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
