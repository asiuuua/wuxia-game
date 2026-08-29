# scenes/ui/overlays/dialog/DialogOverlay.gd
# 对话叠加层（UI 主权 · 对话框外观/位置固定）：只负责"怎么呈现"。
# 数据来源：
#   - 台词、分支、条件、事件全部由 GameManager.dialogue_service 驱动（图模型）。
#   - NPC 元数据（名字、立绘、任务/战斗入口）来自 ConfigManager.get_npc(npc_id)。
# 双立绘规则（数据驱动，UI 零逻辑）：
#   - 左侧：永久固定主角半身立绘（开局加载一次）。
#   - 右侧：动态跟随说话人；NPC 说话显示其立绘、主角变暗；主角说话隐藏右侧。
# 解耦目标：NPC / 台词 / 对话框三者独立；改台词只动 dialogs.json，改外观只动本脚本。

@warning_ignore("shadowed_global_identifier")
extends Control

class_name DialogOverlay

const UIPalette = preload("res://core/constants/ui_theme.gd")
const PortraitCache = preload("res://core/portrait_cache_manager.gd")

var _npc_id: String = ""
var _dialog_id: String = ""
var _npc_data: Dictionary = {}

var _speaker_label: Label
var _dialog_label: Label
var _next_button: Button
var _action_container: VBoxContainer
var _option_container: VBoxContainer
var _left_bust: TextureRect
var _right_bust: TextureRect
var _left_dim: ColorRect
var _right_dim: ColorRect
var _built := false


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_ensure_built()


## UIManager.open_screen 标准入口：data = {"npc_id": String, "dialog_id": String}
func _on_open(data: Variant) -> void:
	var d: Dictionary = data if data is Dictionary else {}
	_npc_id = d.get("npc_id", "")
	_ensure_built()
	visible = true
	var render: Dictionary = GameManager.dialogue_service.start(_npc_id, d.get("dialog_id", ""))
	_dialog_id = GameManager.dialogue_service.get_dialog_id()
	PortraitCache.preload_portrait(ConfigManager.get_npc(_npc_id).get("bust", ""))  # 预热 NPC 立绘，避免首帧卡顿
	_render(render)


## 兼容入口：直接传入 NPC 配置字典（含 id、可选 dialog_id）
func show_for_npc(npc_data: Dictionary) -> void:
	_npc_id = npc_data.get("id", "")
	_ensure_built()
	visible = true
	var render: Dictionary = GameManager.dialogue_service.start(_npc_id, npc_data.get("dialog_id", ""))
	_dialog_id = GameManager.dialogue_service.get_dialog_id()
	PortraitCache.preload_portrait(ConfigManager.get_npc(_npc_id).get("bust", ""))  # 预热 NPC 立绘，避免首帧卡顿
	_render(render)


func _ensure_built() -> void:
	if _built:
		return
	_build()


func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UIPalette.DIM
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(backdrop)

	var panel := Panel.new()
	panel.position = Vector2(80, 400)
	panel.size = Vector2(880, 200)
	add_child(panel)

	# 左侧固定主角半身立绘
	_left_bust = TextureRect.new()
	_left_bust.position = Vector2(40, 180)
	_left_bust.size = Vector2(150, 220)
	_left_bust.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_left_bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var pbust: Texture2D = _load_tex(ConfigManager.get_player().get("bust", ""))
	if pbust != null:
		_left_bust.texture = pbust
	_left_bust.visible = (pbust != null)
	add_child(_left_bust)
	_left_dim = ColorRect.new()
	_left_dim.color = Color(0, 0, 0, 0.55)
	_left_dim.position = _left_bust.position
	_left_dim.size = _left_bust.size
	_left_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_dim.visible = false
	add_child(_left_dim)

	# 右侧动态说话人半身立绘
	_right_bust = TextureRect.new()
	_right_bust.position = Vector2(890, 180)
	_right_bust.size = Vector2(150, 220)
	_right_bust.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_right_bust.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_right_bust.visible = false
	add_child(_right_bust)
	_right_dim = ColorRect.new()
	_right_dim.color = Color(0, 0, 0, 0.55)
	_right_dim.position = _right_bust.position
	_right_dim.size = _right_bust.size
	_right_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_right_dim.visible = false
	add_child(_right_dim)

	_speaker_label = Label.new()
	_speaker_label.position = Vector2(100, 410)
	_speaker_label.size = Vector2(840, 28)
	panel.add_child(_speaker_label)

	_dialog_label = Label.new()
	_dialog_label.position = Vector2(100, 444)
	_dialog_label.size = Vector2(840, 90)
	_dialog_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(_dialog_label)

	_next_button = Button.new()
	_next_button.text = tr("ui_dialog_next")
	_next_button.position = Vector2(800, 545)
	_next_button.pressed.connect(_on_next_pressed)
	panel.add_child(_next_button)

	_option_container = VBoxContainer.new()
	_option_container.position = Vector2(100, 540)
	_option_container.size = Vector2(700, 56)
	panel.add_child(_option_container)

	_action_container = VBoxContainer.new()
	_action_container.position = Vector2(100, 540)
	_action_container.size = Vector2(700, 56)
	_action_container.visible = false
	panel.add_child(_action_container)

	_built = true


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
		var tex: Texture2D = _load_tex(bust)
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


## 对话真正关闭时统一发射一次 dialogue_ended（避免与台词行耗尽重复发射）
func _close_dialog() -> void:
	EventBus.dialogue_ended.emit(_dialog_id)
	GameManager.dialogue_service.end()
	UIManager.close_screen(self)
