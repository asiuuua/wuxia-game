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
}

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

# === 角色工厂：返回 Node2D，子节点 [0]=阴影 [1]=Sprite2D ===
# 关键：Node2D 的 position 即"脚下"——Y-sort 用的就是这个点。
# 立绘用 offset 把图片向上半身高，脚底刚好对齐 Node2D.position。
func _make_actor(sprite_path: String, scene_h: float) -> Node2D:
	var actor := Node2D.new()
	# 阴影子节点：始终在 actor 位置（脚下）
	var shadow := Sprite2D.new()
	shadow.texture = _shadow_tex
	shadow.centered = true
	actor.add_child(shadow)
	# 立绘子节点
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
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
	# 2) 玩家（Node2D 原点 = 脚下）
	_player = _make_actor(PLAYER_SPRITE_PATH, PLAYER_SCENE_H)
	_player.name = "Player"
	add_child(_player)
	_apply_breath(_player)
	# 相机挂玩家身上，自动跟随
	var cam := Camera2D.new()
	_player.add_child(cam)
	# 3) HUD（CanvasLayer，自带独立画布，不受本节点 Y-sort 影响）
	var hud: Hud = load(PathConstants.SCENE_HUD).instantiate()
	add_child(hud)

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
	elif event.is_action_pressed("ui_cancel"):
		_toggle_esc_menu()
	elif event.is_action_pressed("ui_accept") and _nearby_npc != "":
		_open_dialog(_nearby_npc)

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
	var overlay: Control = UIManager.open_screen("DialogOverlay", UIManager.Layer.FULLSCREEN)
	if overlay == null:
		return
	overlay.show_for_npc(ConfigManager.get_npc(npc_id))

# === 输入动作注册（仅首次注册，场景重载不重复添加） ===
func _ensure_input_actions() -> void:
	for action in _MOVE_ACTIONS:
		_register_action(action, _MOVE_ACTIONS[action])
	for action in _TOGGLE_ACTIONS:
		_register_action(action, _TOGGLE_ACTIONS[action])

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
	UIManager.close_all_screens()

func _on_player_changed(_p: Variant = null) -> void:
	pass
