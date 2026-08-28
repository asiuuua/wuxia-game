# scenes/ui/overlays/dialog/DialogOverlay.gd
# 对话叠加层（规范 §8）：播放 NPC 对话，结束时提供 接受任务/开始战斗/结束 动作
# 数据驱动：对话内容来自 NPC 配置；动作触发走 GameManager / QuestService

@warning_ignore("shadowed_global_identifier")
extends Control

class_name DialogOverlay

const UIPalette = preload("res://core/constants/ui_theme.gd")

var _npc_data: Dictionary = {}
var _lines: Array = []
var _line_index: int = 0
var _speaker_label: Label
var _dialog_label: Label
var _next_button: Button
var _action_container: VBoxContainer
var _portrait: TextureRect

func show_for_npc(npc_data: Dictionary) -> void:
	_npc_data = npc_data
	_lines = npc_data.get("dialogs", [])
	_line_index = 0
	_build()
	_refresh_portrait()
	visible = true
	EventBus.dialogue_started.emit(npc_data.get("id", ""), npc_data.get("id", ""))
	_show_line()

func _refresh_portrait() -> void:
	var path: String = _npc_data.get("portrait", "")
	if path != "" and ResourceLoader.exists(path):
		_portrait.texture = load(path) as Texture2D
		_portrait.visible = true
	else:
		_portrait.visible = false

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UIPalette.DIM
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	var panel := Panel.new()
	panel.position = Vector2(200, 380)
	panel.size = Vector2(640, 220)
	add_child(panel)
	# 头像（有 portrait 字段才显示，否则隐藏）
	_portrait = TextureRect.new()
	_portrait.position = Vector2(16, 40)
	_portrait.size = Vector2(84, 84)
	_portrait.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	_portrait.visible = false
	panel.add_child(_portrait)
	_speaker_label = Label.new()
	_speaker_label.position = Vector2(116, 14)
	_speaker_label.size = Vector2(504, 24)
	panel.add_child(_speaker_label)
	_dialog_label = Label.new()
	_dialog_label.position = Vector2(116, 48)
	_dialog_label.size = Vector2(504, 80)
	panel.add_child(_dialog_label)
	_next_button = Button.new()
	_next_button.text = tr("ui_dialog_next")
	_next_button.position = Vector2(540, 180)
	_next_button.pressed.connect(_on_next_pressed)
	panel.add_child(_next_button)
	_action_container = VBoxContainer.new()
	_action_container.position = Vector2(20, 135)
	_action_container.size = Vector2(360, 80)
	panel.add_child(_action_container)

func _show_line() -> void:
	if _line_index >= _lines.size():
		_show_actions()
		return
	var line: Dictionary = _lines[_line_index]
	_speaker_label.text = line.get("speaker", "")
	_dialog_label.text = line.get("text", "")
	_next_button.visible = true
	_action_container.visible = false

func _on_next_pressed() -> void:
	_line_index += 1
	_show_line()

func _show_actions() -> void:
	_next_button.visible = false
	_action_container.visible = true
	for child in _action_container.get_children():
		child.queue_free()
	var quest_id: String = _npc_data.get("quest_id", "")
	var battle_id: String = _npc_data.get("battle_id", "")
	if quest_id != "" and not GameManager.quest_service.is_active(quest_id):
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
	EventBus.dialogue_ended.emit(_npc_data.get("id", ""))
	if battle_id != "":
		# 走指令总线：cmd_start_combat 由 GameManager 解析 NPC→battle_id 并开战（自动接线）
		EventBus.cmd_start_combat.emit(["player"], [_npc_data.get("id", "")])
	else:
		UIManager.close_screen(self)

func _on_fight_pressed(battle_id: String) -> void:
	EventBus.cmd_start_combat.emit(["player"], [_npc_data.get("id", "")])

func _on_close_pressed() -> void:
	EventBus.dialogue_ended.emit(_npc_data.get("id", ""))
	UIManager.close_screen(self)
