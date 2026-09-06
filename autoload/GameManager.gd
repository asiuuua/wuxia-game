# autoload/GameManager.gd
# 游戏状态管理：持有玩家运行时状态与核心业务服务实例（01 图 §29 装配注入；旧「规范 §0.3」编号已废）
# 铁律：业务层不持有 Node；跨模块通信只走 EventBus；场景切换统一由本单例驱动

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

const ResourceManager = preload("res://core/resource_manager.gd")
const PortraitCacheManager = preload("res://core/portrait_cache_manager.gd")

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
var effect_registry: EffectRegistry = null   # Quest/Dialogue 域级副作用注册表（12 图 QD-2：五类 kind 锁定）
var bond_service: BondService = null
var romance_service: RomanceService = null
var sworn_service: SwornService = null          # 结义服务（M4：结义分支）
var master_service: MasterService = null        # 师徒服务（M4：师徒分支）
var relationship_service: RelationshipService = null   # 关系网数据中枢（M3：聚合门面，无状态不存档）

var pending_battle_id: String = ""     # 由 NPC/剧情设置，战斗场景读取
var debug_override_battle_id: String = ""  # 测试用：让战术测试场景壳(riverside)复用并加载指定战斗配置；空=用默认
var current_map_id: String = "town"     # 当前底图标识（世界区域）；战棋布局映射壳据此继承底图共享网格几何
var current_region_id: String = "newbie_village"  # 当前所在世界区域（P1 统一真源：区域ID=世界传送ID=内容分片ID，对应 regions/_map_index.json）
var current_slot: int = -1             # 当前游戏所在存档槽位（-1 表示尚未存档）；HELL 删档时定点删除
var _last_known_day: int = 1             # 姻缘子嗣推进用的天数基线（M3）             # 当前游戏所在存档槽位（-1 表示尚未存档）；HELL 删档时定点删除

var last_wedding := {}

# BUG-11 修复：城镇场景重载后玩家回原位（跨战斗/回城不再传送到 (0,0)）。
# 运行时坐标，存 autoload（切场景存活），不进存档（位置非存档数据）。
var town_player_spawn_pos: Vector2 = Vector2.ZERO

# === 区域枢纽读条切换：异步加载 + 加载覆盖层（2026-09-02 优化）===
# 覆盖层为 GameManager 自建 CanvasLayer（层 600，高于 SYSTEM_OVERLAY 500），
# 不触碰 UI 窗口主权的 scenes/ui/** 文件；提示文案取自 loading_tips.json。
const LOADING_TIPS_FILE := "res://data/configs/ui/loading_tips.json"
const LOADING_OVERLAY_LAYER := 600

var _async_loading: bool = false
var _async_loading_path: String = ""
var _preload_pending: Array[String] = []   # 后台预加载相邻区域场景（load_threaded_request 队列）
var _loading_overlay: CanvasLayer = null
var _loading_bg: ColorRect = null
var _loading_label: Label = null
var _loading_tips: Array[String] = []
var _loading_anim_t: float = 0.0

## 延迟一帧切换场景：避免在 UI 关闭/节点 queue_free 的同一帧内调用 change_scene_to_file，
## 触发 Godot "Parent node is busy adding/removing children" 内部死锁/卡死。
## 2026-09-02 实测：主菜单点击「继续游戏」后 freeze 根因即此。
func _deferred_change_scene(path: String) -> void:
	# 延迟一帧，等 UI 关闭 / queue_free 完成后再切场景，
	# 避免 Godot 内部 "Parent node is busy adding/removing children" 死锁/卡死。
	await get_tree().process_frame
	if is_instance_valid(get_tree()):
		get_tree().change_scene_to_file(path)

## 异步切换场景：后台线程加载 + 加载覆盖层（区域枢纽读条优化）。
## 加载完成后在 _process 轮询里收尾，避免阻塞主线程；启动失败回退同步加载。
func _async_change_scene(path: String) -> void:
	if _async_loading:
		GameLogger.warn("GameManager", "已有异步加载进行中，忽略新请求: %s" % path)
		return
	_show_loading_overlay()
	var err: int = ResourceLoader.load_threaded_request(path)
	if err != OK and err != ERR_ALREADY_IN_USE:
		GameLogger.error("GameManager", "异步加载启动失败(%d): %s" % [err, path])
		_hide_loading_overlay()
		_deferred_change_scene(path)
		return
	_async_loading_path = path
	_async_loading = true

## 每帧轮询异步加载进度；完成后用已加载的 PackedScene 切场景（避免二次加载）
func _poll_async_loading() -> void:
	if not _async_loading:
		return
	var st: int = ResourceLoader.load_threaded_get_status(_async_loading_path)
	if st == ResourceLoader.THREAD_LOAD_LOADED:
		var packed: PackedScene = ResourceLoader.load_threaded_get(_async_loading_path)
		_async_loading = false
		_hide_loading_overlay()
		if packed != null:
			get_tree().change_scene_to_packed(packed)
		else:
			_deferred_change_scene(_async_loading_path)
	elif st == ResourceLoader.THREAD_LOAD_FAILED:
		GameLogger.error("GameManager", "异步加载失败: %s" % _async_loading_path)
		_async_loading = false
		_hide_loading_overlay()
		_deferred_change_scene(_async_loading_path)

## 预加载相邻区域场景（regions.json connections）：进入区域时后台预热，切过去秒开
func _preload_adjacent_regions(region_id: String) -> void:
	for conn in ConfigManager.get_region_connections(region_id):
		var r: Dictionary = ConfigManager.get_region(conn)
		var p: String = String(r.get("scene_path", ""))
		if p.is_empty() or ResourceLoader.has_cached(p):
			continue
		if ResourceLoader.load_threaded_request(p) == OK:
			_preload_pending.append(p)

## 每帧收尾预加载队列：加载完成的资源入缓存（后续 change_scene_to_file 秒切）
func _poll_preloads() -> void:
	if _preload_pending.is_empty():
		return
	var still: Array[String] = []
	for p in _preload_pending:
		var st: int = ResourceLoader.load_threaded_get_status(p)
		if st == ResourceLoader.THREAD_LOAD_LOADED:
			ResourceLoader.load_threaded_get(p)
		elif st == ResourceLoader.THREAD_LOAD_FAILED:
			GameLogger.warn("GameManager", "预加载区域失败: %s" % p)
		else:
			still.append(p)
	_preload_pending = still

## 构建加载覆盖层：全屏半透明底 + 居中提示文案（层 600，高于系统浮层 500）
func _show_loading_overlay() -> void:
	if _loading_overlay != null:
		return
	_load_loading_tips()
	var canvas := CanvasLayer.new()
	canvas.layer = LOADING_OVERLAY_LAYER
	canvas.name = "LoadingOverlay"
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.05, 0.08, 0.85)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	var label := Label.new()
	label.text = _pick_loading_tip()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 22)
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(label)
	# 树处于 setup 阶段（测试/启动期）时同步 add_child 会失败，延迟到帧末挂载；
	# 生产路径（goto_region 用户操作）树已就绪，行为不变
	_mount_loading_overlay.call_deferred(canvas)
	_loading_overlay = canvas
	_loading_bg = bg
	_loading_label = label
	_loading_anim_t = 0.0

## 延迟挂载覆盖层到根节点（树忙碌时 add_child 需延后到帧末；已被释放则跳过）
func _mount_loading_overlay(canvas: CanvasLayer) -> void:
	if not is_instance_valid(canvas):
		return
	get_tree().root.add_child(canvas)

## 移除加载覆盖层（已挂载则 queue_free 延迟释放，未挂载则直接 free，切场景帧内安全）
func _hide_loading_overlay() -> void:
	if _loading_overlay == null:
		return
	var ov: CanvasLayer = _loading_overlay
	_loading_overlay = null
	_loading_bg = null
	_loading_label = null
	if ov.is_inside_tree():
		ov.queue_free()
	else:
		ov.free()

## 从 loading_tips.json 读取加载提示文案（只读一次，缓存）
func _load_loading_tips() -> void:
	if not _loading_tips.is_empty():
		return
	if not FileAccess.file_exists(LOADING_TIPS_FILE):
		return
	var f := FileAccess.open(LOADING_TIPS_FILE, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		var arr: Array = parsed.get("tips", [])
		for t in arr:
			_loading_tips.append(String(t))

## 随机取一条加载提示（无配置时给兜底文案）
func _pick_loading_tip() -> String:
	if _loading_tips.is_empty():
		return "正在加载..."
	return _loading_tips[randi() % _loading_tips.size()]

## 加载覆盖层动效：提示文案透明度呼吸（轻微脉冲，避免死板）
func _animate_loading_overlay(delta: float) -> void:
	if _loading_label == null or not is_instance_valid(_loading_label):
		return
	_loading_anim_t += delta
	_loading_label.modulate.a = 0.6 + 0.4 * sin(_loading_anim_t * 3.0)

func _ready() -> void:
	player_state = PlayerState.new()
	player_state.init_default("李十五", 1)
	_init_services()
	# 工业化 P6：向全局资源管理器登记集中回收钩子（立绘 LRU）。
	# ResourceManager 仅触发钩子、不再反向耦合子系统；战斗实体池已改为每场自建/自清。
	ResourceManager.register_reclaim_hook(PortraitCacheManager.clear)
	_register_saveables()
	# 战斗结束 → 任务系统推进目标（事件闭环，替代原先战斗直调任务的反模式）
	EventBus.combat_finished.connect(quest_service._on_combat_finished)
	EventBus.inventory_item_added.connect(quest_service._on_inventory_added)   # P3-c：give_item 类目标推进
	# P0 修复：背包腾出空间后自动补交满包时暂缓的任务奖励（丢弃/卖出/消耗等任何移除都触发）
	EventBus.inventory_item_removed.connect(quest_service.retry_completed_turn_ins)
	# 指令接线：任务/对话发出 cmd_start_combat 后自动开战（解耦战斗入口，消除空壳）
	EventBus.cmd_start_combat.connect(_on_cmd_start_combat)
	# 对话事件演出：到达某行 trigger_events 经 EventBus 派发，由执行器演出音效/震屏/接任务
	# （12 图 QD-2 收编：executor 与 quest_service 共享同一 EffectRegistry 域表）
	dialogue_event_executor.setup(effect_registry)
	# 表现层指令：services 只产指令（QD-R10），相机演出在装配层执行
	EventBus.screen_shake_requested.connect(_on_screen_shake_requested)
	# 追踪当前存档槽位（读档/存档时更新），供 HELL 删档定点删除
	EventBus.game_saved.connect(_on_slot_event)
	EventBus.game_loaded.connect(_on_slot_event)
	# 时间推进 → 姻缘子嗣（怀胎十月）随天数推进（M3：接 TimeService/WeatherTimeService）
	# B6（07图 W-R03）：姻缘子嗣按天推进改为 TimeConsumer 注册制分相消费（业务推进相 0），
	# 不再私听 world_day_advanced 信号；信号保留对外广播（表现层可听）。
	WeatherTimeService.register_day_consumer(0, _on_world_day_advanced)
	# 婚礼演出：监听 bond_wedding_started 切到婚礼场景（M3：接 BondService.hold_wedding）
	EventBus.bond_wedding_started.connect(_on_bond_wedding_started)
	_sync_day_baseline()

var _buff_tick_accum: float = 0.0

# 每帧驱动武学快捷栏实时冷却递减（冷却状态源真值在 AbilityService.cd_remaining）；
# 同时驱动背包增益丹药的"现实时间独立计时器"：每秒检查一次过期并清理
func _process(delta: float) -> void:
	if ability_service != null:
		ability_service.tick_cooldowns(delta)
	_buff_tick_accum += delta
	if _buff_tick_accum >= 1.0:
		_buff_tick_accum = 0.0
		if player_state != null:
			player_state.purge_expired_time_buffs()
	_poll_async_loading()
	_poll_preloads()
	_animate_loading_overlay(delta)

## ADR-0007 批A：装配收敛开关（默认 false=旧路径零行为；true=经 ApplicationRoot 组装后引用转发）
const USE_APPLICATION_ROOT := true   # ADR-0007 批B：新装配路径转正（回滚=revert 本常量）

func _init_services() -> void:
	if USE_APPLICATION_ROOT:
		var root := ApplicationRoot.new()
		root.assemble()
		_adopt_from(root)
		return
	combat_service = CombatService.new()
	inventory_service = InventoryService.new()
	ability_service = AbilityService.new()
	quest_service = QuestService.new()
	equipment_service = EquipmentService.new()
	alchemy_service = AlchemyService.new()
	forge_service = ForgeService.new()
	shop_service = ShopService.new()
	sect_service = SectService.new()
	effect_registry = EffectRegistry.new()
	quest_service = QuestService.new()
	quest_service.attach_effects(effect_registry)   # QD-2：reward/progress 效果注册（quest_complete→turn_in 直连修 P-Q1）
	dialogue_service = DialogueService.new()
	dialogue_event_executor = DialogueEventExecutor.new()
	bond_service = BondService.new()
	romance_service = RomanceService.new()
	sworn_service = SwornService.new()
	master_service = MasterService.new()
	relationship_service = RelationshipService.new(bond_service, romance_service, sworn_service, master_service)

## 表现层执行器（12 图 QD-R10 / P-Q10 收口 2026-09-06）：services 只产
## screen_shake_requested 指令，相机随机偏移 Tween 演出在此执行（装配层表现自由）。
func _on_screen_shake_requested(intensity: float, duration: float) -> void:
	var tree := get_tree()
	if tree == null or tree.get_current_scene() == null:
		return
	var cam := tree.get_current_scene().get_viewport().get_camera_2d()
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

## ADR-0007 批A：ApplicationRoot 组装结果引用转发（成员同名拷贝，调用方/测试零改动）
func _adopt_from(root: ApplicationRoot) -> void:
	combat_service = root.combat_service
	inventory_service = root.inventory_service
	ability_service = root.ability_service
	quest_service = root.quest_service
	equipment_service = root.equipment_service
	alchemy_service = root.alchemy_service
	forge_service = root.forge_service
	shop_service = root.shop_service
	sect_service = root.sect_service
	effect_registry = root.effect_registry
	dialogue_service = root.dialogue_service
	dialogue_event_executor = root.dialogue_event_executor
	bond_service = root.bond_service
	romance_service = root.romance_service
	sworn_service = root.sworn_service
	master_service = root.master_service
	relationship_service = root.relationship_service


func _register_saveables() -> void:
	# ADR-0007 批B：服务 saveable 已由 ApplicationRoot.register_saveables() 注册（开关 true 路径）；
	# player_state / GameState 桥为时序敏感项暂留本处（批C 随装配段整体移交）。
	if USE_APPLICATION_ROOT:
		SaveManager.register_saveable(player_state)
		SaveManager.register_saveable(GameState.save_bridge())
		return
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
	# SV-4/P-S11：GameState 为 autoload Node 无法直接挂 ISaveable，经存档桥强类型注册
	SaveManager.register_saveable(GameState.save_bridge())

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
	set_current_region("newbie_village")
	_deferred_change_scene(PathConstants.SCENE_TOWN)

## 读取存档并进入游戏（主菜单"继续江湖路"调用，M2 新增）
func load_game(slot: int) -> void:
	ResourceManager.reclaim_all()
	if SaveManager.load_from_slot(slot):
		# 存档迁移整改：恢复存档时所在区域（1.1.0+ 记录 last_region_id），而非固定回起始城镇
		var rid := GameState.get_last_region()
		set_current_region(rid)
		var scene_path: String = String(ConfigManager.get_region(rid).get("scene_path", ""))
		_deferred_change_scene(scene_path if not scene_path.is_empty() else PathConstants.SCENE_TOWN)
	else:
		GameLogger.warn("GameManager", "读取存档失败: slot=%d" % slot)

## 开战：记录待打战斗并切换到战斗场景
## 战术战棋战斗（配置 tactical=true）路由到 TacticalBattleScene，其余走经典 BattleScene（旧战斗零影响）
## 设计拍版（2026-09-02）：HUD 为城镇常驻 UI，战斗中绝不出现——
## 战斗使用独立的战斗 UI（BattleScene / TacticalBattleScene 自带），与 HUD 互斥。
## 故所有开战入口都先卸载 HUD，确保战斗中不会残留 HUD 面板（视觉重叠风险），
## 不依赖"离开城镇"这个时机（旧链路在 TownScene._exit_tree 才卸载，任何非经城镇的
## 开战路径都可能让 HUD 残留）。
func start_battle(battle_id: String) -> void:
	# 进入战斗即卸载常驻 HUD（策略显式收口，与战斗 UI 互斥）
	UIManager.unmount_hud()
	# 工业化扩容 P6：切场景前集中回收温存/冷资源（CG/语音/立绘/战斗实体池统一释放口）
	ResourceManager.reclaim_all()
	pending_battle_id = battle_id
	if ConfigManager.get_battle(battle_id).get("tactical", false):
		_deferred_change_scene(PathConstants.SCENE_TACTICAL_BATTLE)
	else:
		_deferred_change_scene(PathConstants.SCENE_BATTLE)

## 调试/测试：进入「竹林水畔」战棋测试场景（包裹装饰层 demo），供 F11 一键验证遮挡/水面/雾气。
## 内部 TacticalBattleScene 子节点读 pending_battle_id 开局（与正式战斗逻辑完全一致），结束自动 return_to_town。
func start_test_riverside() -> void:
	ResourceManager.reclaim_all()
	debug_override_battle_id = ""
	pending_battle_id = "tactical_test_riverside"
	_deferred_change_scene("res://scenes/gameplay/battle/tactical_test_riverside.tscn")

## 调试/测试：进入「群怪压力测试」战棋场景（复用 riverside 装饰壳），供 F12 一键验证 20 小怪同场 + 飘字队列不丢字。
## 复用战术测试场景壳，仅覆盖 battle 配置为 tactical_test_swarm（20 敌 + 友方），装饰层照常生效。
func start_test_swarm() -> void:
	ResourceManager.reclaim_all()
	debug_override_battle_id = "tactical_test_swarm"
	_deferred_change_scene("res://scenes/gameplay/battle/tactical_test_riverside.tscn")

## 设置当前底图标识（世界区域切入时调用）。战棋布局映射壳据此让该底图所有小怪复用同一份共享网格几何。
func set_current_map(map_id: String) -> void:
	current_map_id = map_id

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
	_deferred_change_scene(PathConstants.SCENE_TOWN)

## 返回标题：清理 UI 栈并重新加载启动入口（Bootstrap 会再次打开加载界面并进入主菜单）
func return_to_title() -> void:
	UIManager.close_all_screens()
	ResourceManager.reclaim_all()
	_deferred_change_scene(PathConstants.SCENE_BOOTSTRAP)

## 读档/存档事件：记录当前槽位（仅真实槽位 >=1 才记；quick_save(-1) 忽略）
func _on_slot_event(slot: int) -> void:
	if slot >= 1:
		current_slot = slot
	_sync_day_baseline()  # 读档后天数可能跳变，重设基线避免子嗣孕期被错误快进（M3）

## 时间推进时驱动姻缘子嗣（advance_days 随天数推进孕期）
func _on_world_day_advanced(day: int) -> void:   # B6：现为 TimeConsumer 注册回调（非信号直连）
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
	_deferred_change_scene(scene_path)

## 回安全点（EASY 团灭）：切换到城镇场景并恢复队伍状态（由 DefeatHandler 调用）
func return_to_safe_point() -> void:
	var sp: Dictionary = GameState.get_last_safe_point()
	# 当前所有安全点都映射到城镇场景；marker 预留给后续扩展（客栈/营地等不同场景）
	GameLogger.info("GameManager", "回安全点: %s" % sp.get("marker", "town"))
	ResourceManager.reclaim_all()
	set_current_region("newbie_village")
	_deferred_change_scene(PathConstants.SCENE_TOWN)

## 统一区域切换入口（P4 整改）：改内存态同时写穿 GameState（随存档持久化），
## 防止"内存里在迷烟镇、存档里还是起始城镇"的真源分裂。
func set_current_region(rid: String) -> void:
	current_region_id = rid
	GameState.set_last_region(rid)

## 区域传送（填表模式）：查 regions.json 取 scene_path 切场景；scene_path 为空=尚未实装，飘字提示不卡死
func goto_region(id: String) -> void:
	var region: Dictionary = ConfigManager.get_region(id)
	if region.is_empty():
		GameLogger.warn("GameManager", "goto_region：区域不存在: %s" % id)
		EventBus.notification_show.emit("未知区域：%s" % id)
		return
	var scene_path: String = String(region.get("scene_path", ""))
	if scene_path.is_empty():
		GameLogger.warn("GameManager", "goto_region：区域尚未实装场景: %s" % id)
		EventBus.notification_show.emit("区域尚未实装：%s" % region.get("name", id))
		return
	GameLogger.info("GameManager", "传送至区域: %s (%s)" % [id, scene_path])
	ResourceManager.reclaim_all()
	set_current_region(id)
	current_map_id = id
	_preload_adjacent_regions(id)
	_async_change_scene(scene_path)

func _equip_starting_abilities() -> void:
	var slot := 0
	for ability_id in ConfigManager.get_all_ability_ids():
		var data: Dictionary = ConfigManager.get_ability(ability_id)
		if data.get("learned_by_default", false):
			ability_service.learn(ability_id)
			if data.get("type", 0) == AbilityEnums.AbilityType.EXTERNAL and slot < AbilityService.MAX_COMBAT_SKILLS:
				ability_service.equip_combat_skill(slot, ability_id)
				slot += 1
