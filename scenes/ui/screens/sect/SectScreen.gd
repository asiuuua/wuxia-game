# scenes/ui/screens/sect/SectScreen.gd
# 门派界面（Phase 2 系统填充，纯代码构建）：列出门派、显示声望阶位、加入/贡献
# 铁律：UI 只做展示与输入，业务逻辑调用 GameManager / SectService
# 2026-08-29 新建：补齐 screens.json 里已注册但缺失的界面

extends Control
class_name SectScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const CONTRIBUTE_AMOUNT := 50

var _list: VBoxContainer
var _status: Label

func _ready() -> void:
	_build_ui()
	refresh()
	EventBus.notify_sect_joined.connect(_on_sect_joined)
	EventBus.notify_sect_join_failed.connect(_on_sect_join_failed)
	EventBus.notify_sect_reputation_changed.connect(_on_rep_changed)
	EventBus.notify_sect_rank_up.connect(_on_rank_up)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)

	var title := Label.new()
	title.text = tr("ui_sect_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status)

	_list = VBoxContainer.new()
	root.add_child(_list)

	var close := Button.new()
	close.text = tr("ui_sect_close")
	close.pressed.connect(UIManager.close_screen.bind(self))
	root.add_child(close)

func refresh() -> void:
	var svc: SectService = GameManager.sect_service
	if svc == null:
		return

	# 顶部状态：当前门派 + 声望 + 阶位
	var cur: String = svc.current_sect_id
	if cur == "":
		_status.text = "当前：散修"
	else:
		var sect: Dictionary = ConfigManager.get_sect(cur)
		_status.text = "当前：%s  %s %d  %s %s" % [
			sect.get("name", cur),
			tr("ui_sect_rep"), svc.get_reputation(cur),
			tr("ui_sect_rank"), svc.get_rank_name(svc.get_rank(cur)),
		]

	for child in _list.get_children():
		child.queue_free()

	var ids: Array[String] = ConfigManager.get_all_sect_ids()
	for sid in ids:
		_list.add_child(_build_row(sid))

func _build_row(sect_id: String) -> VBoxContainer:
	var svc: SectService = GameManager.sect_service
	var sect: Dictionary = ConfigManager.get_sect(sect_id)
	var v := VBoxContainer.new()

	var head := Label.new()
	head.text = "%s  %s %d  %s %s" % [
		sect.get("name", sect_id),
		tr("ui_sect_rep"), svc.get_reputation(sect_id),
		tr("ui_sect_rank"), svc.get_rank_name(svc.get_rank(sect_id)),
	]
	v.add_child(head)

	var desc := Label.new()
	desc.text = String(sect.get("description", ""))
	desc.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	v.add_child(desc)

	var h := HBoxContainer.new()

	var join_btn := Button.new()
	join_btn.text = tr("ui_sect_join")
	join_btn.disabled = svc.current_sect_id != ""
	join_btn.pressed.connect(_on_join_pressed.bind(sect_id))

	var contrib_btn := Button.new()
	contrib_btn.text = "%s +%d" % [tr("ui_sect_contribute"), CONTRIBUTE_AMOUNT]
	contrib_btn.pressed.connect(_on_contribute_pressed.bind(sect_id))

	h.add_child(join_btn)
	h.add_child(contrib_btn)
	v.add_child(h)
	return v

func _on_join_pressed(sect_id: String) -> void:
	GameManager.sect_service.join(sect_id)

func _on_contribute_pressed(sect_id: String) -> void:
	GameManager.sect_service.contribute(sect_id, CONTRIBUTE_AMOUNT)

func _on_sect_joined(_sect_id: String) -> void:
	EventBus.notification_show.emit(tr("ui_sect_joined"))
	refresh()

func _on_sect_join_failed(_sect_id: String, reason: String) -> void:
	var msg: String = tr("ui_sect_fail_rep")
	if reason == "ALREADY_IN_SECT":
		msg = tr("ui_sect_fail_already")
	EventBus.notification_show.emit(msg)
	refresh()

func _on_rep_changed(_sect_id: String, _new_reputation: int) -> void:
	refresh()

func _on_rank_up(sect_id: String, new_rank: int) -> void:
	var sect: Dictionary = ConfigManager.get_sect(sect_id)
	var svc: SectService = GameManager.sect_service
	EventBus.notification_show.emit("%s 晋升为 %s" % [
		sect.get("name", sect_id), svc.get_rank_name(new_rank)
	])
	refresh()

func _exit_tree() -> void:
	if EventBus.notify_sect_joined.is_connected(_on_sect_joined):
		EventBus.notify_sect_joined.disconnect(_on_sect_joined)
	if EventBus.notify_sect_join_failed.is_connected(_on_sect_join_failed):
		EventBus.notify_sect_join_failed.disconnect(_on_sect_join_failed)
	if EventBus.notify_sect_reputation_changed.is_connected(_on_rep_changed):
		EventBus.notify_sect_reputation_changed.disconnect(_on_rep_changed)
	if EventBus.notify_sect_rank_up.is_connected(_on_rank_up):
		EventBus.notify_sect_rank_up.disconnect(_on_rank_up)
