@tool
# scenes/ui/screens/alchemy/AlchemyScreen.gd
# 炼药界面（B 路线：静态壳在 AlchemyScreen.tscn，脚本只填动态内容）
# 铁律：UI 只做展示与输入，业务逻辑调用 GameManager / AlchemyService

extends PopupBase
class_name AlchemyScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")

@onready var _title: Label = $Panel/Margin/VLayout/Title
@onready var _list: VBoxContainer = $Panel/Margin/VLayout/BodyAnchor/List
@onready var _close: Button = $Panel/Margin/VLayout/Close

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	popup_id = "AlchemyScreen"
	_build_ui()
	refresh()
	EventBus.alchemy_refined.connect(_on_alchemy_refined)
	EventBus.alchemy_failed.connect(_on_alchemy_failed)

func _build_ui() -> void:
	_title.text = tr("ui_alchemy_title")
	_close.text = tr("ui_alchemy_close")
	_close.pressed.connect(request_close)

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

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后渲染配方列表（规避 GameManager）
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_title = $Panel/Margin/VLayout/Title
	_list = $Panel/Margin/VLayout/BodyAnchor/List
	_close = $Panel/Margin/VLayout/Close
	if _title == null or _list == null:
		return
	_title.text = tr("ui_alchemy_title")
	_close.text = tr("ui_alchemy_close")
	_editor_refresh()

## 预览专用：仅读配置（ConfigManager），不碰 GameManager
func _editor_refresh() -> void:
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
		info.text = _recipe_summary_safe(rid, recipe)
		var btn := Button.new()
		btn.text = tr("ui_alchemy_refine")
		btn.disabled = false
		h.add_child(info)
		h.add_child(btn)
		_list.add_child(h)

func _recipe_summary_safe(rid: String, recipe: Dictionary) -> String:
	var name: String = recipe.get("name", rid)
	var ins: String = ""
	for inp in recipe.get("inputs", []):
		var n: String = ConfigManager.get_item(inp["item_id"]).get("name", inp["item_id"])
		var need: int = int(inp.get("count", 1))
		ins += "%s %d/%d  " % [n, need, need]
	var out: String = ConfigManager.get_item(recipe.get("output_pill_id", "")).get("name", recipe.get("output_pill_id", ""))
	return "%s：[%s] -> %s" % [name, ins.strip_edges(), out]
