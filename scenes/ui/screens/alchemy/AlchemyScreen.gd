# scenes/ui/screens/alchemy/AlchemyScreen.gd
# 炼药界面（Phase 2，纯代码构建）：列出配方、显示材料满足度、点击炼制
# 铁律：UI 只做展示与输入，业务逻辑调用 GameManager / AlchemyService

extends Control
class_name AlchemyScreen

var _list: VBoxContainer

func _ready() -> void:
	_build_ui()
	refresh()
	EventBus.alchemy_refined.connect(_on_alchemy_refined)
	EventBus.alchemy_failed.connect(_on_alchemy_failed)

func _build_ui() -> void:
	var root := VBoxContainer.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var title := Label.new()
	title.text = tr("ui_alchemy_title")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)
	_list = VBoxContainer.new()
	root.add_child(_list)
	var close := Button.new()
	close.text = tr("ui_alchemy_close")
	close.pressed.connect(UIManager.close_screen.bind(self))
	root.add_child(close)

func refresh() -> void:
	for child in _list.get_children():
		child.queue_free()
	var ids: Array[String] = ConfigManager.get_all_recipe_ids()
	if ids.is_empty():
		var e := Label.new()
		e.text = tr("ui_alchemy_empty")
		_list.add_child(e)
	for rid in ids:
		var recipe: Dictionary = ConfigManager.get_recipe(rid)
		var h := HBoxContainer.new()
		var info := Label.new()
		info.custom_minimum_size = Vector2(300, 0)
		info.text = _recipe_summary(rid, recipe)
		var btn := Button.new()
		btn.text = tr("ui_alchemy_refine")
		btn.disabled = not GameManager.alchemy_service.can_refine(rid)
		btn.pressed.connect(_on_refine_pressed.bind(rid))
		h.add_child(info)
		h.add_child(btn)
		_list.add_child(h)

func _recipe_summary(rid: String, recipe: Dictionary) -> String:
	var name: String = recipe.get("name", rid)
	var ins: String = ""
	for inp in recipe.get("inputs", []):
		var have: int = GameManager.inventory_service.get_item_count(inp["item_id"])
		var need: int = int(inp.get("count", 1))
		var n: String = ConfigManager.get_item(inp["item_id"]).get("name", inp["item_id"])
		ins += "%s %d/%d  " % [n, have, need]
	var out: String = ConfigManager.get_item(recipe.get("output_pill_id", "")).get("name", recipe.get("output_pill_id", ""))
	return "%s：[%s] -> %s" % [name, ins.strip_edges(), out]

func _on_refine_pressed(rid: String) -> void:
	GameManager.alchemy_service.refine(rid)
	refresh()

func _on_alchemy_refined(_rid: String, _oid: String, _c: int) -> void:
	refresh()

func _on_alchemy_failed(_rid: String, _reason: String) -> void:
	refresh()

func _exit_tree() -> void:
	if EventBus.alchemy_refined.is_connected(_on_alchemy_refined):
		EventBus.alchemy_refined.disconnect(_on_alchemy_refined)
	if EventBus.alchemy_failed.is_connected(_on_alchemy_failed):
		EventBus.alchemy_failed.disconnect(_on_alchemy_failed)
