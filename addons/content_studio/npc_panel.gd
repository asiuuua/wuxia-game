@tool
extends Control

# NPC 数据表编辑器（编辑器专用，随 content_studio 插件加载）。
# 读取/写回 res://data/configs/npcs/town_npcs.json，零代码改 NPC。

const NPC_PATH := "res://data/configs/npcs/town_npcs.json"

var _list: ItemList = null
var _fields: Dictionary = {}
var _status: Label = null

func _ready() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(h)

	_list = ItemList.new()
	_list.custom_minimum_size = Vector2(220, 0)
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(_list)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	_add_field(v, "id", "id（唯一，新建后勿改）", true)
	_add_field(v, "name", "名称")
	_add_field(v, "sprite", "立绘 sprite 路径")
	_add_field(v, "portrait", "头像 portrait 路径")
	_add_field(v, "dialog_id", "对话 id")
	_add_field(v, "quest_id", "任务 id")
	_add_field(v, "battle_id", "战斗 id")

	var btn := HBoxContainer.new()
	v.add_child(btn)
	_mk_btn(btn, "新建NPC", _on_new)
	_mk_btn(btn, "保存", _on_save)
	_mk_btn(btn, "删除", _on_del)
	_status = Label.new()
	_status.text = "就绪（数据文件：%s）" % NPC_PATH
	v.add_child(_status)

	_list.item_selected.connect(_on_select)
	_refresh_list()

func _add_field(parent: VBoxContainer, key: String, label: String, readonly: bool = false) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(240, 0)
	row.add_child(l)
	var ed := LineEdit.new()
	ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(ed)
	if readonly:
		ed.editable = false
	_fields[key] = ed

func _mk_btn(parent: HBoxContainer, txt: String, cb: Callable) -> void:
	var b := Button.new()
	b.text = txt
	b.pressed.connect(cb)
	parent.add_child(b)

func _refresh_list() -> void:
	_list.clear()
	var data := _load_json(NPC_PATH)
	var npcs: Array = data.get("npcs", [])
	for n in npcs:
		_list.add_item(String(n.get("id", "?")))

func _on_select(idx: int) -> void:
	if idx < 0 or idx >= _list.item_count:
		return
	var id: String = _list.get_item_text(idx)
	var data := _load_json(NPC_PATH)
	var npcs: Array = data.get("npcs", [])
	for n in npcs:
		if String(n.get("id", "")) == id:
			_set_field("id", String(n.get("id", "")))
			_set_field("name", String(n.get("name", "")))
			_set_field("sprite", String(n.get("sprite", "")))
			_set_field("portrait", String(n.get("portrait", "")))
			_set_field("dialog_id", String(n.get("dialog_id", "")))
			_set_field("quest_id", String(n.get("quest_id", "")))
			_set_field("battle_id", String(n.get("battle_id", "")))
			_status.text = "已载入 NPC：%s" % id
			return

func _set_field(key: String, val: String) -> void:
	if _fields.has(key):
		_fields[key].text = val

func _on_new() -> void:
	for k in _fields.keys():
		_fields[k].text = ""
	_status.text = "新建模式：填好 id 和名称后点「保存」"

func _on_save() -> void:
	var id: String = _fields["id"].text.strip_edges()
	if id == "":
		_status.text = "id 不能为空"
		return
	var data := _load_json(NPC_PATH)
	if not data.has("npcs"):
		data["npcs"] = []
	var npcs: Array = data["npcs"]
	var entry: Dictionary = {}
	var found := false
	for n in npcs:
		if String(n.get("id", "")) == id:
			entry = n
			found = true
			break
	if not found:
		entry = {"id": id, "pos_x": 0, "pos_y": 0}
	entry["id"] = id
	entry["name"] = _fields["name"].text
	entry["sprite"] = _fields["sprite"].text
	entry["portrait"] = _fields["portrait"].text
	entry["dialog_id"] = _fields["dialog_id"].text
	entry["quest_id"] = _fields["quest_id"].text
	entry["battle_id"] = _fields["battle_id"].text
	if not found:
		npcs.append(entry)
	data["npcs"] = npcs
	_write_json(NPC_PATH, data)
	_status.text = "已保存 NPC：%s（写回 town_npcs.json）" % id
	_refresh_list()
	for i in _list.item_count:
		if _list.get_item_text(i) == id:
			_list.select(i)
			_on_select(i)
			break

func _on_del() -> void:
	var id: String = _fields["id"].text.strip_edges()
	if id == "":
		_status.text = "请先选择一个 NPC"
		return
	var data := _load_json(NPC_PATH)
	var npcs: Array = data.get("npcs", [])
	var kept: Array = []
	for n in npcs:
		if String(n.get("id", "")) != id:
			kept.append(n)
	data["npcs"] = kept
	_write_json(NPC_PATH, data)
	_status.text = "已删除 NPC：%s" % id
	_refresh_list()
	_on_new()

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var p = JSON.parse_string(txt)
	if p is Dictionary:
		return p
	return {}

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_status.text = "写入失败：%s" % path
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
