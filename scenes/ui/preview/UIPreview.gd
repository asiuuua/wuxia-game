@tool
# scenes/ui/preview/UIPreview.gd
# 编辑器专用 UI 预览器（@tool，只在编辑器里干活，绝不进游戏/不打扰运行时）。
# 用法：在 Godot 编辑器里双击打开本 .tscn，顶部下拉选任意界面，
#       下方即实例化该界面并调用其 _editor_preview() 注入模拟数据，
#       于是文字/按钮/列表全显示出来，所见即所得。
# 设计约束：
#  - 生产界面脚本为非 @tool，编辑器里其 _ready 不跑、@onready 为空，故由本脚本手动触发 _editor_preview()。
#  - 预览实例 owner 置 null，绝不污染任何生产 .tscn。
#  - 不依赖任何运行态（GameManager/存档），只读配置 + 模拟数据。

extends Control

const SCREENS_FILE := "res://data/configs/ui/screens.json"

@onready var _picker: OptionButton = $TopBar/Picker
@onready var _holder: Control = $PreviewRoot

var _screen_names: Array[String] = []
var _screen_paths: Array[String] = []

func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	_load_registry()
	_build_picker()
	# 默认展示主菜单
	var def := _screen_names.find("MainMenu")
	if def < 0 and _screen_names.size() > 0:
		def = 0
	if def >= 0:
		_picker.select(def)
		_show_screen(def)

func _load_registry() -> void:
	_screen_names.clear()
	_screen_paths.clear()
	if not FileAccess.file_exists(SCREENS_FILE):
		return
	var f := FileAccess.open(SCREENS_FILE, FileAccess.READ)
	if f == null:
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	for key in parsed.keys():
		var v: Variant = parsed[key]
		var path: String
		if typeof(v) == TYPE_STRING:
			path = v
		elif typeof(v) == TYPE_DICTIONARY and (v as Dictionary).has("path"):
			path = (v as Dictionary)["path"]
		else:
			continue
		if not path.begins_with("res://"):
			path = "res://" + path
		_screen_names.append(key)
		_screen_paths.append(path)

func _build_picker() -> void:
	_picker.clear()
	for n in _screen_names:
		_picker.add_item(n)
	if not _picker.item_selected.is_connected(_on_pick):
		_picker.item_selected.connect(_on_pick)

func _on_pick(idx: int) -> void:
	if not Engine.is_editor_hint():
		return
	_show_screen(idx)

func _show_screen(idx: int) -> void:
	for c in _holder.get_children():
		c.queue_free()
	if idx < 0 or idx >= _screen_paths.size():
		return
	var path: String = _screen_paths[idx]
	if not ResourceLoader.exists(path):
		return
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return
	var inst: Control = packed.instantiate() as Control
	if inst == null:
		return
	_holder.add_child(inst)
	# 关键：预览实例不持久化，避免污染生产场景
	inst.owner = null
	if inst.has_method("_editor_preview"):
		inst._editor_preview()
