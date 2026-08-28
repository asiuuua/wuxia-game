# scenes/ui/screens/forge/ForgeScreen.gd
# 锻造界面（Phase 2 系统填充，纯代码构建）：列出配方、显示材料满足度、点击锻造
# 铁律：UI 只做展示与输入，业务逻辑调用 GameManager / ForgeService
# 2026-08-29 新建：补齐 screens.json 里已注册但缺失的界面

extends Control
class_name ForgeScreen

var _list: VBoxContainer

func _ready() -> void:
	_build_ui()
	refresh()
	EventBus.notify_forge_completed.connect(_on_forge_completed)
	EventBus.notify_forge_failed.connect(_on_forge_failed)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var title := Label.new()
	title.text = tr("ui_forge_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	_list = VBoxContainer.new()
	root.add_child(_list)
	var close := Button.new()
	close.text = tr("ui_forge_close")
	close.pressed.connect(UIManager.close_screen.bind(self))
	root.add_child(close)

func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var ids: Array[String] = ConfigManager.get_all_forge_recipe_ids()
	if ids.is_empty():
		var e := Label.new()
		e.text = tr("ui_forge_empty")
		_list.add_child(e)
		return
	for rid in ids:
		var recipe: Dictionary = ConfigManager.get_forge_recipe(rid)
		var h := HBoxContainer.new()
		var info := Label.new()
		info.custom_minimum_size = Vector2(360, 0)
		info.text = _recipe_summary(rid, recipe)
		var btn := Button.new()
		btn.text = tr("ui_forge_forge")
		btn.disabled = not GameManager.forge_service.can_forge(rid)
		btn.pressed.connect(_on_forge_pressed.bind(rid))
		h.add_child(info)
		h.add_child(btn)
		_list.add_child(h)

func _recipe_summary(rid: String, recipe: Dictionary) -> String:
	var nm: String = recipe.get("name", rid)
	var ins: String = GameManager.forge_service.describe_inputs(rid)
	var out_id: String = String(recipe.get("output_item_id", ""))
	var out: String = ConfigManager.get_item(out_id).get("name", out_id)
	var lv: int = int(recipe.get("level_req", 1))
	return "%s [Lv.%d]：[%s] -> %s" % [nm, lv, ins, out]

func _on_forge_pressed(rid: String) -> void:
	GameManager.forge_service.forge(rid, 1)
	refresh()

func _on_forge_completed(_rid: String, _out_id: String, _count: int) -> void:
	EventBus.notification_show.emit(tr("ui_forge_success"))
	refresh()

func _on_forge_failed(_rid: String, reason: String) -> void:
	var msg: String = tr("ui_forge_fail_material")
	if reason == "LEVEL_TOO_LOW":
		msg = tr("ui_forge_fail_level")
	elif reason == "UNKNOWN_RECIPE" or reason == "INVALID_COUNT":
		msg = tr("ui_forge_fail_material")
	EventBus.notification_show.emit("%s%s" % [tr("ui_forge_result_prefix"), msg])
	refresh()

func _exit_tree() -> void:
	if EventBus.notify_forge_completed.is_connected(_on_forge_completed):
		EventBus.notify_forge_completed.disconnect(_on_forge_completed)
	if EventBus.notify_forge_failed.is_connected(_on_forge_failed):
		EventBus.notify_forge_failed.disconnect(_on_forge_failed)
