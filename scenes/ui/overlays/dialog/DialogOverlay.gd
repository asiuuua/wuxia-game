@tool
# scenes/ui/overlays/dialog/DialogOverlay.gd
# 对话叠加层（UI 主权 · 对话框外观/位置固定）：只负责"怎么呈现"。
# 数据来源：
#   - 台词、分支、条件、事件全部由 GameManager.dialogue_service 驱动（图模型）。
#   - NPC 元数据（名字、立绘、任务/战斗入口）来自 ConfigManager.get_npc(npc_id)。
# 双立绘规则（数据驱动，UI 零逻辑）：
#   - 左侧：永久固定主角半身立绘（开局加载一次）。
#   - 右侧：动态跟随说话人；NPC 说话显示其立绘、主角变暗；主角说话隐藏右侧。
# 解耦目标：NPC / 台词 / 对话框三者独立；改台词只动 dialogs.json，改外观只动本脚本/本场景。
#
# B 路线（2026-08-29）：静态结构（遮罩/玻璃面板/双立绘/标签/按钮/容器）下沉到
# DialogOverlay.tscn，美术可在编辑器改外观；脚本只保留动态逻辑与 @onready 引用。
# 生命周期：UIManager.open_screen 在 add_child 之前调用 _on_open（即 _ready 之前），
# 故用 _ready_done + _pending_open 把"打开"推迟到 _ready（@onready 节点就位）后执行，
# 与 CelebrationOverlay 同款处理。

@warning_ignore("shadowed_global_identifier")
extends Control

class_name DialogOverlay

const UIPalette = preload("res://core/constants/ui_theme.gd")
const PortraitCache = preload("res://core/portrait_cache_manager.gd")

var _npc_id: String = ""
var _dialog_id: String = ""
var _npc_data: Dictionary = {}

@onready var _speaker_label: Label = $Panel/SpeakerLabel
@onready var _dialog_label: Label = $Panel/DialogLabel
@onready var _next_button: Button = $Panel/NextButton
@onready var _action_container: VBoxContainer = $Panel/ActionContainer
@onready var _option_container: VBoxContainer = $Panel/OptionContainer
@onready var _left_bust: TextureRect = $LeftBust
@onready var _right_bust: TextureRect = $RightBust
@onready var _left_dim: ColorRect = $LeftDim
@onready var _right_dim: ColorRect = $RightDim

var _ready_done := false
var _pending_open: Variant = null
var _left_anim: AnimatedSprite2D = null   # 主角动态立绘（portrait_anim 配置时启用，否则为 null）


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	focus_mode = Control.FOCUS_NONE
	_init_static()
	_ready_done = true
	if _pending_open != null:
		var data: Variant = _pending_open
		_pending_open = null
		_open(data)


## 静态外观初始化（原 _build 中固定不变的部分）。其余动态内容由 _render / _update_portraits 驱动。
func _init_static() -> void:
	_next_button.text = tr("ui_dialog_next")
	_next_button.pressed.connect(_on_next_pressed)
	var pdata: Dictionary = ConfigManager.get_player()
	var pbust: Texture2D = _load_tex(pdata.get("bust", ""))
	if pbust != null:
		_left_bust.texture = pbust
	_left_bust.visible = (pbust != null)
	# 主角动态立绘：portrait_anim 指向 SpriteFrames 时在左侧半身位置叠加 AnimatedSprite2D 循环播放，
	# 隐藏原静态半身贴图（NPC 右侧仍走静态 TextureRect，不受影响）。
	var anim_path: String = pdata.get("portrait_anim", "")
	if anim_path != "" and ResourceLoader.exists(anim_path):
		var frames: SpriteFrames = load(anim_path) as SpriteFrames
		if frames != null and frames.has_animation("idle"):
			var anim := AnimatedSprite2D.new()
			anim.sprite_frames = frames
			anim.play("idle")
			anim.centered = false
			# 按 LeftBust 显示区高度缩放铺满（脚底对齐底部）
			var tex0: Texture2D = frames.get_frame_texture("idle", 0)
			var fh: float = float(tex0.get_height())
			var s: float = _left_bust.size.y / fh
			anim.scale = Vector2(s, s)
			anim.position = Vector2((_left_bust.size.x - tex0.get_width() * s) * 0.5, 0.0)
			_left_bust.add_child(anim)
			_left_anim = anim
			_left_bust.texture = null
			_left_bust.visible = true   # 容器仍可见，内部贴图由动画覆盖


## UIManager.open_screen 标准入口：data = {"npc_id": String, "dialog_id": String}
func _on_open(data: Variant) -> void:
	if _ready_done:
		_open(data)
	else:
		_pending_open = data


## 兼容入口：直接传入 NPC 配置字典（含 id、可选 dialog_id）
func show_for_npc(npc_data: Dictionary) -> void:
	if _ready_done:
		_open(npc_data)
	else:
		_pending_open = npc_data


func _open(data: Variant) -> void:
	var d: Dictionary = data if data is Dictionary else {}
	_npc_id = d.get("npc_id", d.get("id", ""))
	visible = true
	var render: Dictionary = GameManager.dialogue_service.start(_npc_id, d.get("dialog_id", ""))
	_dialog_id = GameManager.dialogue_service.get_dialog_id()
	PortraitCache.preload_portrait(GameManager.dialogue_service.resolve_half_body(_npc_id, false))  # 预热 NPC 半身立绘，避免首帧卡顿
	_render(render)


func _load_tex(path: String) -> Texture2D:
	# 工业化扩容 P2：走立绘 LRU 缓存，避免每次对话/每行重复 load 磁盘。
	return PortraitCache.get_portrait(path)


func _render(render: Dictionary) -> void:
	if render.get("ended", false):
		_show_actions()
		return
	_speaker_label.text = render.get("speaker_name", "")
	_dialog_label.text = render.get("text", "")
	_update_portraits(render.get("is_player", false), render.get("bust", ""))
	# 工业化扩容 P5：每行可选语音，异步流式播放（缺省空串静默跳过，不卡对话）
	var voice: String = String(render.get("voice", ""))
	if voice != "":
		AudioManager.play_voice(voice)

	var opts: Array = render.get("options", [])
	_clear(_option_container)
	if opts.is_empty():
		_next_button.visible = true
		_option_container.visible = false
	else:
		_next_button.visible = false
		_option_container.visible = true
		for o in opts:
			var btn := Button.new()
			btn.text = o.get("text", "")
			btn.pressed.connect(_on_option_pressed.bind(o.get("jump_id", "")))
			_option_container.add_child(btn)


func _update_portraits(is_player: bool, bust: String) -> void:
	if is_player:
		_right_bust.visible = false
		_right_dim.visible = false
		_left_dim.visible = false          # 主角说话：左侧高亮
	else:
		_left_dim.visible = true           # 主角变暗
		# 优先用配偶「勾选中的立绘」（婘眷值解锁的特殊形象），否则用传入半身立绘
		var path: String = bust
		if GameManager.romance_service != null and GameManager.romance_service.is_spouse(_npc_id):
			var active: String = GameManager.romance_service.get_active_portrait(_npc_id)
			if active != "":
				path = active
		var tex: Texture2D = _load_tex(path)
		if tex != null:
			_fade_right_bust(tex)
			_right_bust.visible = true
			_right_dim.visible = false
		else:
			_right_bust.visible = false     # 无立绘 NPC：隐藏右侧


func _fade_right_bust(tex: Texture2D) -> void:
	if _right_bust.texture == tex:
		return
	var tw := create_tween()
	tw.tween_property(_right_bust, "modulate:a", 0.0, 0.1)
	tw.tween_callback(func(): _right_bust.texture = tex)
	tw.tween_property(_right_bust, "modulate:a", 1.0, 0.1)


func _on_next_pressed() -> void:
	_render(GameManager.dialogue_service.next())


func _on_option_pressed(jump_id: String) -> void:
	_render(GameManager.dialogue_service.select_option(jump_id))


func _clear(c: Container) -> void:
	for child in c.get_children():
		child.queue_free()


func _show_actions() -> void:
	_next_button.visible = false
	_clear(_option_container)
	_option_container.visible = false
	_action_container.visible = true
	_clear(_action_container)
	_npc_data = ConfigManager.get_npc(_npc_id)
	var quest_id: String = _npc_data.get("quest_id", "")
	var battle_id: String = _npc_data.get("battle_id", "")
	if quest_id != "" and GameManager.quest_service != null and not GameManager.quest_service.is_active(quest_id):
		var accept := Button.new()
		accept.text = tr("ui_dialog_accept") % ConfigManager.get_quest(quest_id).get("name", "")
		accept.pressed.connect(_on_accept_pressed.bind(quest_id, battle_id))
		_action_container.add_child(accept)
	elif battle_id != "":
		var fight := Button.new()
		fight.text = tr("ui_dialog_fight")
		fight.pressed.connect(_on_fight_pressed.bind(battle_id))
		_action_container.add_child(fight)
	else:
		var close := Button.new()
		close.text = tr("ui_dialog_end")
		close.pressed.connect(_on_close_pressed)
		_action_container.add_child(close)
	# 新增：打开该 NPC 的「详情面板」（数值/武学/好感/立绘等，预留接口）
	var detail := Button.new()
	detail.text = "查看详情"
	detail.focus_mode = Control.FOCUS_NONE
	detail.pressed.connect(_on_open_npc_panel.bind(_npc_id))
	_action_container.add_child(detail)


func _on_accept_pressed(quest_id: String, battle_id: String) -> void:
	GameManager.quest_service.accept(quest_id)
	if battle_id != "":
		_close_dialog()
		EventBus.cmd_start_combat.emit(["player"], [_npc_id])
	else:
		_close_dialog()


func _on_fight_pressed(battle_id: String) -> void:
	_close_dialog()
	EventBus.cmd_start_combat.emit(["player"], [_npc_id])


func _on_close_pressed() -> void:
	_close_dialog()


func _on_open_npc_panel(npc_id: String) -> void:
	_close_dialog()
	UIManager.open_screen("NpcPanel", UIManager.Layer.POPUP, {"npc_id": npc_id})


## 对话真正关闭时统一发射一次 dialogue_ended（避免与台词行耗尽重复发射）
func _close_dialog() -> void:
	EventBus.dialogue_ended.emit(_dialog_id)
	GameManager.dialogue_service.end()
	EventBus.popup_close_requested.emit(self)

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后填示例对话（规避 GameManager 对话服务）
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_speaker_label = $Panel/SpeakerLabel
	_dialog_label = $Panel/DialogLabel
	_next_button = $Panel/NextButton
	_action_container = $Panel/ActionContainer
	_option_container = $Panel/OptionContainer
	_left_bust = $LeftBust
	_right_bust = $RightBust
	_left_dim = $LeftDim
	_right_dim = $RightDim
	if _speaker_label == null or _dialog_label == null:
		return
	_next_button.text = tr("ui_dialog_next")
	_speaker_label.text = "柳如烟"
	_dialog_label.text = "「少侠远道而来，可是为了那卷《天书》？」"
	_next_button.visible = true
	_option_container.visible = false
	_action_container.visible = false
