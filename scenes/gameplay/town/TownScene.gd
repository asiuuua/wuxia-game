# scenes/gameplay/town/TownScene.gd
# 城镇场景（区域枢纽式）：玩家移动、NPC 交互、触发对话/战斗
# 视觉：纯 2D 等距 + Y-sort 遮挡（角色原点钉脚底 + 椭圆阴影）
# 资产：场景底图 + 角色立绘（数据驱动；demo 阶段硬编码路径，后续迁 ConfigManager）
# 输入：WASD / 方向键移动；B 背包；M 地图；Tab 属性；Esc 关闭面板

extends Node2D
class_name TownScene

const MOVE_SPEED := 200.0
const PLAYER_SCENE_H := 140.0  # 玩家在场景里的目标高度（像素）
const NPC_SCENE_H := 140.0     # NPC 同
const SHADOW_BASE_W := 64      # 阴影纹理基准宽（运行时按角色实际宽度缩放）
const SHADOW_BASE_H := 18      # 阴影纹理基准高
const SHADOW_WIDTH_RATIO := 0.55  # 阴影宽 = 角色宽 × 此系数
const SHADOW_ALPHA := 0.45     # 阴影最深处不透明度

# 场景底图（demo 硬编码；后续迁 ConfigManager）
const SCENE_BG_PATH := "res://assets/scenes/town_main.png"
# 玩家立绘（demo 硬编码；后续从 PlayerState/存档读）
const PLAYER_SPRITE_PATH := "res://assets/characters/player.png"
# 玩家动态立绘帧序列（31 帧 matte idle 循环动画）；非空时主角世界体改用 AnimatedSprite2D 播放
const PLAYER_FRAMES_PATH := "res://assets/characters/matte/matte_idle.tres"
# 玩家动态立绘首帧 PNG（用于取真实尺寸做缩放；matte 序列固定 720×1280）
const PLAYER_FRAME_TEX := "res://assets/characters/matte/matte_00001.png"

const _MOVE_ACTIONS := {
	"move_up": [KEY_W, KEY_UP],
	"move_down": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
}
const _TOGGLE_ACTIONS := {
	"toggle_inventory": [KEY_B],
	"toggle_map": [KEY_M],
	"toggle_attributes": [KEY_TAB],
	"toggle_menu": [KEY_G],
	"rest": [KEY_R],
}
const _DEBUG_ACTIONS := {
	"debug_tactical_battle": [KEY_F9],
	"debug_party_tactical": [KEY_F8],
	"debug_riverside_test": [KEY_F11],
	"debug_swarm_test": [KEY_F12],
	"debug_celebration": [KEY_F10],
}
# 一次“休息/睡觉”推进的游戏天数：怀胎期 gestation_days=300，按月跳进（30天/次）
# 约 10 次休息可分娩，贴合“怀胎十月”设定且玩家可快速验证子嗣出生。
const REST_DAYS := 30

# === 调试热键（正式发布前把 DEBUG_QUICK_BATTLE / DEBUG_QUICK_CELEBRATION 置 false 即可禁用）===
# 城镇内按 F9 直接开战术战棋 demo，跳过“走过去→对话→战斗”链路，方便反复试战斗表现。
const DEBUG_QUICK_BATTLE := true
const DEBUG_TACTICAL_BATTLE_ID := "tactical_demo_001"
const DEBUG_PARTY_BATTLE_ID := "tactical_demo_party"
# 城镇内按 F11 一键进「竹林水畔」战棋测试场景（装饰层 demo：竹子/房屋遮挡 + 水面波纹 + 雾气）
const DEBUG_QUICK_RIVERSIDE := true
# 城镇内按 F12 一键进「群怪压力测试」战棋场景（20 小怪 + 友方，验证多 NPC 同场 + 飘字队列不丢字）
const DEBUG_QUICK_SWARM := true
# 城镇内按 F10 一键造配偶 + 触发欢庆：跳过求婚/结婚/好感流程，反复试受孕与 CG 表现。
const DEBUG_QUICK_CELEBRATION := true
const DEBUG_CELEBRATION_SPOUSE_ID := "npc_su_waner"

var _player: Node2D
var _npc_nodes: Dictionary = {}   # npc_id -> Node2D
var _nearby_npc: String = ""

# === 椭圆阴影纹理（程序生成一次，所有角色共用）===
var _shadow_tex: Texture2D

func _ready() -> void:
	# 核心：开 Y-sort。子节点按其 Y 坐标自动排序绘制——Y 大（屏幕下）= 靠前，盖住 Y 小的。
	# 角色原点已钉脚底，所以"走到树后面"就是角色 Y < 树根 Y，自动被遮。
	y_sort_enabled = true
	_ensure_input_actions()
	_build_shadow_texture()
	_build_world()
	_spawn_npcs()
	EventBus.scene_changed.emit("town_001")
	GameState.set_last_safe_point("town_001", "safe_town")
	EventBus.player_hp_changed.connect(_on_player_changed)
	EventBus.player_level_up.connect(_on_player_changed)

# === 椭圆阴影：边缘羽化的半透明黑，模拟"脚下一团软影" ===
func _build_shadow_texture() -> void:
	var img := Image.create(SHADOW_BASE_W, SHADOW_BASE_H, false, Image.FORMAT_RGBA8)
	var cx := float(SHADOW_BASE_W) / 2.0
	var cy := float(SHADOW_BASE_H) / 2.0
	for y in range(SHADOW_BASE_H):
		for x in range(SHADOW_BASE_W):
			var dx := (float(x) - cx) / cx
			var dy := (float(y) - cy) / cy
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0) * SHADOW_ALPHA
			img.set_pixel(x, y, Color(0, 0, 0, a))
	_shadow_tex = ImageTexture.create_from_image(img)

# === 角色工厂：返回 Node2D，子节点 [0]=阴影 [1]=立绘(Sprite2D 或 AnimatedSprite2D) ===
# 关键：Node2D 的 position 即"脚下"——Y-sort 用的就是这个点。
# 立绘用 offset 把图片向上半身高，脚底刚好对齐 Node2D.position。
# frames_path 非空时改建 AnimatedSprite2D 播放帧序列（主角动态立绘）；否则静态 Sprite2D。
func _make_actor(sprite_path: String, scene_h: float, frames_path: String = "") -> Node2D:
	var actor := Node2D.new()
	# 阴影子节点：始终在 actor 位置（脚下）
	var shadow := Sprite2D.new()
	shadow.texture = _shadow_tex
	shadow.centered = true
	actor.add_child(shadow)
	# 立绘子节点
	if frames_path != "" and ResourceLoader.exists(frames_path):
		var anim := AnimatedSprite2D.new()
		var frames: SpriteFrames = load(frames_path) as SpriteFrames
		if frames != null and frames.has_animation("idle"):
			anim.sprite_frames = frames
			anim.play("idle")
			# 尺寸取首帧 PNG（直接 load，避免 headless 下 get_frame_texture 惰性返回 null）
			var tex0: Texture2D = load(PLAYER_FRAME_TEX) as Texture2D
			if tex0 == null:
				tex0 = frames.get_frame_texture("idle", 0)
			if tex0 != null:
				var fh: float = float(tex0.get_height())
				var s: float = scene_h / fh
				anim.scale = Vector2(s, s)
				anim.offset = Vector2(0, -fh / 2.0)
				var char_w := float(tex0.get_width()) * s
				var ss: float = (char_w * SHADOW_WIDTH_RATIO) / float(SHADOW_BASE_W)
				shadow.scale = Vector2(ss, ss)
				actor.add_child(anim)
				actor.set_meta("body", anim)
			else:
				# 帧纹理不可用降级：退回静态 Sprite2D（用玩家单图）
				anim.queue_free()
	elif sprite_path != "" and ResourceLoader.exists(sprite_path):
		var spr := Sprite2D.new()
		var tex: Texture2D = load(sprite_path) as Texture2D
		if tex != null:
			spr.texture = tex
			var s: float = scene_h / float(tex.get_height())
			spr.scale = Vector2(s, s)
			# offset 把"图片中心"拉回脚下：图心向上半身高 → 脚底在 actor.position
			spr.offset = Vector2(0, -float(tex.get_height()) / 2.0)
			# 阴影宽度跟随角色实际宽度——角色放大时影子同步放大，不会脱节
			var char_w := float(tex.get_width()) * s
			var ss: float = (char_w * SHADOW_WIDTH_RATIO) / float(SHADOW_BASE_W)
			shadow.scale = Vector2(ss, ss)
		actor.add_child(spr)
		actor.set_meta("body", spr)
	return actor

# === 角色呼吸：从脚底锚点（Sprite2D 局部原点=脚）做纵向缩放 Tween ===
# 参数全部来自 ui_anim.json 的 breath 预设；幅度极小，营造「活着」的轻微起伏。
# 不缩放整个 Node2D（会连带阴影/相机），只动 [1]Sprite2D——脚底锚定使其缩放时脚不动。
func _apply_breath(actor: Node2D) -> void:
	var body: CanvasItem = actor.get_meta("body", null)
	if body == null:
		return
	if not ConfigManager.get_anim_value("breath", "enabled", true):
		return
	var base: Vector2 = body.scale
	var amp_y: float = ConfigManager.get_anim_value("breath", "scale_y_amp", 0.025)
	var amp_x: float = ConfigManager.get_anim_value("breath", "scale_x_amp", 0.012)
	var dur: float = ConfigManager.get_anim_preset_duration("breath", 1.6)
	var preset: Dictionary = ConfigManager.get_anim_preset("breath")
	var etoken: String = preset.get("easing", "smooth")
	var trans := ConfigManager.get_anim_trans(etoken)
	var ease := ConfigManager.get_anim_ease(etoken)
	# 随机初始相位：每个角色错开呼吸节奏，避免整齐划一的机械感
	if ConfigManager.get_anim_value("breath", "random_phase", true):
		var ph: float = randf() * PI
		body.scale = base * Vector2(1.0 + amp_x * sin(ph), 1.0 + amp_y * sin(ph))
	var t := actor.create_tween()
	t.set_loops(0)
	t.set_trans(trans)
	t.set_ease(ease)
	t.tween_property(body, "scale", base * Vector2(1.0 + amp_x, 1.0 + amp_y), dur)
	t.tween_property(body, "scale", base, dur)

func _build_world() -> void:
	# 1) 场景底图（必须在玩家/NPC 之前 add，否则 Y-sort 同 Y 时按插入序后绘）
	if ResourceLoader.exists(SCENE_BG_PATH):
		var bg := Sprite2D.new()
		var tex: Texture2D = load(SCENE_BG_PATH) as Texture2D
		bg.texture = tex
		bg.centered = true
		bg.position = Vector2(0, 0)
		bg.z_index = -10  # 兜底：万一和角色 Y 重合也能保证在所有角色之下
		bg.y_sort_enabled = false  # 底图自身不参与 Y-sort（它的 Y 是中心 = 0，会被排序坑）
		add_child(bg)
	# 2) 玩家（Node2D 原点 = 脚下）；有动态立绘帧序列时走 AnimatedSprite2D
	_player = _make_actor(PLAYER_SPRITE_PATH, PLAYER_SCENE_H, PLAYER_FRAMES_PATH)
	_player.name = "Player"
	add_child(_player)
	_apply_breath(_player)
	# 相机挂玩家身上，自动跟随
	var cam := Camera2D.new()
	_player.add_child(cam)
	# 3) HUD（常驻层，屏幕固定位置，不受本节点 Y-sort / Camera2D 影响）
	var hud: Hud = load(PathConstants.SCENE_HUD).instantiate()
	UIManager.mount_hud(hud)

func _spawn_npcs() -> void:
	for npc_id in ConfigManager.get_all_npc_ids():
		var data: Dictionary = ConfigManager.get_npc(npc_id)
		var sprite_path: String = data.get("sprite", "")
		var node: Node2D
		if sprite_path != "" and ResourceLoader.exists(sprite_path):
			node = _make_actor(sprite_path, NPC_SCENE_H)
		else:
			# 暂无立绘：占位黄方块（保持脚底锚点 + 阴影，尺寸对齐 140px 角色）
			node = Node2D.new()
			var shadow := Sprite2D.new()
			shadow.texture = _shadow_tex
			shadow.centered = true
			var ss: float = (60.0 * SHADOW_WIDTH_RATIO) / float(SHADOW_BASE_W)
			shadow.scale = Vector2(ss, ss)
			node.add_child(shadow)
			var body := ColorRect.new()
			body.size = Vector2(60, 120)
			body.position = Vector2(-30, -120)  # 120 高方块，底边对齐 node.position
			body.color = Color(0.9, 0.75, 0.2)
			body.mouse_filter = Control.MOUSE_FILTER_IGNORE
			# 呼吸绕中心缩放（ColorRect 默认绕左上角缩放会歪），与 Sprite2D 表现一致
			body.pivot_offset = body.size / 2.0
			node.add_child(body)
			# 占位身子也要标 meta，否则 _apply_breath 里 get_meta 找不到 key 会刷 ERROR
			node.set_meta("body", body)
		node.name = npc_id
		node.position = Vector2(data.get("pos_x", 0), data.get("pos_y", 0))
		add_child(node)
		_apply_breath(node)
		_npc_nodes[npc_id] = node

func _physics_process(delta: float) -> void:
	if UIManager.is_any_screen_open():
		return
	var dir := Vector2.ZERO
	if Input.is_action_pressed("move_up"):
		dir.y -= 1
	if Input.is_action_pressed("move_down"):
		dir.y += 1
	if Input.is_action_pressed("move_left"):
		dir.x -= 1
	if Input.is_action_pressed("move_right"):
		dir.x += 1
	if dir != Vector2.ZERO:
		_player.position += dir.normalized() * MOVE_SPEED * delta
	_nearby_npc = ""
	for npc_id in _npc_nodes:
		if _player.position.distance_to(_npc_nodes[npc_id].position) < 60:
			_nearby_npc = npc_id
			break

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		_toggle_overlay("InventoryScreen")
	elif event.is_action_pressed("toggle_map"):
		_toggle_overlay("MapScreen")
	elif event.is_action_pressed("toggle_attributes"):
		_toggle_overlay("AttributesScreen")
	elif event.is_action_pressed("toggle_menu"):
		_toggle_overlay("GameMenu")
	elif event.is_action_pressed("rest"):
		_do_rest()
	elif event.is_action_pressed("ui_cancel"):
		_toggle_esc_menu()
	elif event.is_action_pressed("ui_accept") and _nearby_npc != "":
		_open_dialog(_nearby_npc)
	elif event.is_action_pressed("debug_tactical_battle") and DEBUG_QUICK_BATTLE:
		_launch_debug_tactical()
	elif event.is_action_pressed("debug_party_tactical") and DEBUG_QUICK_BATTLE:
		_launch_debug_party_tactical()
	elif event.is_action_pressed("debug_riverside_test") and DEBUG_QUICK_RIVERSIDE:
		_launch_debug_riverside_test()
	elif event.is_action_pressed("debug_swarm_test") and DEBUG_QUICK_SWARM:
		_launch_debug_swarm_test()
	elif event.is_action_pressed("debug_celebration") and DEBUG_QUICK_CELEBRATION:
		_launch_debug_celebration()

func _toggle_overlay(screen_name: String) -> void:
	var existing: Control = UIManager.get_open_screen(screen_name)
	if existing != null:
		UIManager.close_screen(existing)
	else:
		UIManager.open_screen(screen_name, UIManager.Layer.FULLSCREEN)

func _toggle_esc_menu() -> void:
	var existing: Control = UIManager.get_open_screen("EscMenu")
	if existing != null:
		UIManager.close_screen(existing)
		return
	if UIManager.is_any_screen_open():
		UIManager.close_all_screens()
		return
	UIManager.open_screen("EscMenu", UIManager.Layer.POPUP)

func _open_dialog(npc_id: String) -> void:
	var npc_data: Dictionary = ConfigManager.get_npc(npc_id)
	var dialog_id: String = npc_data.get("dialog_id", "")
	UIManager.open_screen("DialogOverlay", UIManager.Layer.FULLSCREEN,
		{"npc_id": npc_id, "dialog_id": dialog_id})

# 休息/睡觉：推进游戏天数（走 WeatherTimeService 真日历），其 world_day_advanced 会经
# GameManager 扇入 romance_service.advance_days 驱动孕期/分娩，并广播事件刷新面板/天气。
func _do_rest() -> void:
	if UIManager.is_any_screen_open():
		return
	GameManager.weather_time_service.advance_day(REST_DAYS)
	EventBus.notification_show.emit("你沉沉睡去，恍惚间过去了 %d 天" % REST_DAYS)

# 调试：直接开战术战棋 demo（跳过 NPC 对话链路），反复试战斗表现用。由 F9 触发，受 DEBUG_QUICK_BATTLE 门控。
func _launch_debug_tactical() -> void:
	if UIManager.is_any_screen_open():
		return
	GameManager.start_battle(DEBUG_TACTICAL_BATTLE_ID)

# 调试：一键开「主角 + 随行剑客 vs 山贼」组队战，验证多 NPC 同场 + 飘字可见。由 F8 触发，受 DEBUG_QUICK_BATTLE 门控。
func _launch_debug_party_tactical() -> void:
	if UIManager.is_any_screen_open():
		return
	GameManager.start_battle(DEBUG_PARTY_BATTLE_ID)

# 调试：一键进「竹林水畔」战棋测试场景（竹子/房屋遮挡 + 水面波纹 + 雾气装饰层 demo）。
# 由 F11 触发，受 DEBUG_QUICK_RIVERSIDE 门控。复用真实战术战斗逻辑，仅外层多套一层装饰。
func _launch_debug_riverside_test() -> void:
	if UIManager.is_any_screen_open():
		return
	GameManager.start_test_riverside()

# 调试：一键进「群怪压力测试」战棋场景（20 小怪 + 友方），验证多 NPC 同场 + 飘字队列不丢字。
# 由 F12 触发，受 DEBUG_QUICK_SWARM 门控。复用 riverside 装饰壳，仅加载 tactical_test_swarm 战斗配置。
func _launch_debug_swarm_test() -> void:
	if UIManager.is_any_screen_open():
		return
	GameManager.start_test_swarm()

# 调试：一键造已婚配偶 + 触发欢庆，反复试受孕与 CG 表现。由 F10 触发，受 DEBUG_QUICK_CELEBRATION 门控。
# 复用与面板 _on_celebration 完全一致的开界面流程（成功开 CG / 超配额开 over_limit 对话框 / 受孕弹喜讯）。
func _launch_debug_celebration() -> void:
	if UIManager.is_any_screen_open():
		return
	var sid: String = DEBUG_CELEBRATION_SPOUSE_ID
	# 造已婚配偶（无聘礼/婚礼副作用）；已是配偶则跳过。好感拉满以满足任何前置。
	GameManager.bond_service.set_affection(sid, 100)
	GameManager.romance_service.debug_make_spouse(sid)
	var r: Dictionary = GameManager.romance_service.begin_celebration(sid)
	if not r.get("ok", false):
		var reason: String = String(r.get("reason", "UNKNOWN"))
		if reason == "QUOTA_EXCEEDED":
			UIManager.open_screen("CelebrationOverlay", UIManager.Layer.FULLSCREEN, {"mode": "over_limit"})
		else:
			EventBus.notification_show.emit("未能欢庆：%s" % reason)
		return
	var nm: String = sid
	var rel: Dictionary = ConfigManager.get_relation(sid)
	if not rel.is_empty() and rel.has("name"):
		nm = String(rel["name"])
	UIManager.open_screen("CelebrationOverlay", UIManager.Layer.FULLSCREEN,
		{"mode": "cg", "npc_id": sid, "cg_id": String(r.get("cg_id", "default"))})
	if bool(r.get("conceived", false)):
		EventBus.notification_show.emit("喜讯：与 %s 珠胎暗结……" % nm)

# === 输入动作注册（仅首次注册，场景重载不重复添加） ===
func _ensure_input_actions() -> void:
	for action in _MOVE_ACTIONS:
		_register_action(action, _MOVE_ACTIONS[action])
	for action in _TOGGLE_ACTIONS:
		_register_action(action, _TOGGLE_ACTIONS[action])
	for action in _DEBUG_ACTIONS:
		_register_action(action, _DEBUG_ACTIONS[action])

func _register_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		if not InputMap.action_has_event(action, ev):
			InputMap.action_add_event(action, ev)

func _exit_tree() -> void:
	if EventBus.player_hp_changed.is_connected(_on_player_changed):
		EventBus.player_hp_changed.disconnect(_on_player_changed)
	if EventBus.player_level_up.is_connected(_on_player_changed):
		EventBus.player_level_up.disconnect(_on_player_changed)
	# HUD 挂在 autoload 的 HUD 层、不随本场景树销毁，须显式卸载，否则切场景后残留双 HUD
	UIManager.unmount_hud()
	UIManager.close_all_screens()

func _on_player_changed(_p: Variant = null) -> void:
	pass
