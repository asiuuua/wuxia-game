@tool
extends Control

# 剧情/对话表编辑器（编辑器专用，随 content_studio 插件加载）。
# 读取 _index.json → 分片文件，编辑台词 lines，零代码改剧情文本。

const INDEX_PATH := "res://data/configs/npcs/dialogs/_index.json"

var _dlg_list: ItemList = null
var _line_list: ItemList = null
var _fields: Dictionary = {}
var _status: Label = null
var _new_dlg: LineEdit = null
var _current_dlg: String = ""
var _current_shard: Dictionary = {}

func _ready() -> void:
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(h)

	_dlg_list = ItemList.new()
	_dlg_list.custom_minimum_size = Vector2(200, 0)
	_dlg_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(_dlg_list)

	_line_list = ItemList.new()
	_line_list.custom_minimum_size = Vector2(130, 0)
	_line_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(_line_list)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	h.add_child(scroll)

	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(v)

	var nd_row := HBoxContainer.new()
	v.add_child(nd_row)
	var lnd := Label.new(); lnd.text = "新对话id："; nd_row.add_child(lnd)
	_new_dlg = LineEdit.new(); _new_dlg.placeholder_text = "例如 dlg_chapter2"; _new_dlg.size_flags_horizontal = Control.SIZE_EXPAND_FILL; nd_row.add_child(_new_dlg)
	_mk_btn(nd_row, "新建对话", _on_new_dlg)

	_add_field(v, "id", "台词 id")
	_add_field(v, "speaker_id", "说话人 id")
	_add_field(v, "speaker_name", "说话人显示名(可选)")
	_add_text(v, "text", "台词文本")
	_add_field(v, "next_id", "下一句 id(空=结束)")
	_add_field(v, "trigger_events", "触发事件(逗号分隔,可选)")

	var btn := HBoxContainer.new()
	v.add_child(btn)
	_mk_btn(btn, "新建台词", _on_new_line)
	_mk_btn(btn, "保存台词", _on_save_line)
	_mk_btn(btn, "删除台词", _on_del_line)
	_mk_btn(btn, "删除对话", _on_del_dlg)

	_status = Label.new()
	_status.text = "就绪"
	v.add_child(_status)

	_dlg_list.item_selected.connect(_on_dlg_select)
	_line_list.item_selected.connect(_on_line_select)
	_refresh_dlg_list()

func _add_field(parent: VBoxContainer, key: String, label: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(200, 0); row.add_child(l)
	var ed := LineEdit.new(); ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(ed)
	_fields[key] = ed

func _add_text(parent: VBoxContainer, key: String, label: String) -> void:
	var row := VBoxContainer.new()
	parent.add_child(row)
	var l := Label.new(); l.text = label; row.add_child(l)
	var ed := TextEdit.new(); ed.custom_minimum_size = Vector2(0, 80); ed.size_flags_horizontal = Control.SIZE_EXPAND_FILL; row.add_child(ed)
	_fields[key] = ed

func _mk_btn(parent: HBoxContainer, txt: String, cb: Callable) -> void:
	var b := Button.new(); b.text = txt; b.pressed.connect(cb); parent.add_child(b)

func _set_field(key: String, val: String) -> void:
	if _fields.has(key):
		_fields[key].text = val

func _join(arr: Array) -> String:
	var out := ""
	var first := true
	for x in arr:
		if not first:
			out += ","
		out += String(x)
		first = false
	return out

func _refresh_dlg_list() -> void:
	_dlg_list.clear()
	var idx := _load_json(INDEX_PATH)
	var shards: Dictionary = idx.get("shards", {})
	for k in shards.keys():
		_dlg_list.add_item(String(k))

func _on_dlg_select(idx: int) -> void:
	if idx < 0 or idx >= _dlg_list.item_count:
		return
	_current_dlg = _dlg_list.get_item_text(idx)
	var idx_data := _load_json(INDEX_PATH)
	var shards: Dictionary = idx_data.get("shards", {})
	var entry: Dictionary = shards.get(_current_dlg, {})
	var file: String = String(entry.get("file", ""))
	if file == "":
		_status.text = "索引中未找到 %s 的文件路径" % _current_dlg
		return
	_current_shard = _load_json(file)
	if not _current_shard.has("lines"):
		_current_shard["lines"] = []
	_line_list.clear()
	var lines: Array = _current_shard["lines"]
	for ln in lines:
		_line_list.add_item(String(ln.get("id", "?")))
	_status.text = "已载入对话：%s（文件 %s）" % [_current_dlg, file]

func _on_line_select(idx: int) -> void:
	if idx < 0 or idx >= _line_list.item_count:
		return
	var lid: String = _line_list.get_item_text(idx)
	var lines: Array = _current_shard.get("lines", [])
	for ln in lines:
		if String(ln.get("id", "")) == lid:
			_set_field("id", String(ln.get("id", "")))
			_set_field("speaker_id", String(ln.get("speaker_id", "")))
			_set_field("speaker_name", String(ln.get("speaker_name", "")))
			_set_field("text", String(ln.get("text", "")))
			_set_field("next_id", String(ln.get("next_id", "")))
			var te = ln.get("trigger_events", [])
			_set_field("trigger_events", _join(te))
			return

func _on_new_dlg() -> void:
	var id: String = _new_dlg.text.strip_edges()
	if id == "":
		_status.text = "请输入新对话 id"
		return
	var idx := _load_json(INDEX_PATH)
	var shards: Dictionary = idx.get("shards", {})
	if shards.has(id):
		_status.text = "该 id 已存在"
		return
	var file := "res://data/configs/npcs/dialogs/shards/%s.json" % id
	var new_shard := {"id": id, "lines": []}
	_write_json(file, new_shard)
	shards[id] = {"file": file, "npc_id": "", "chapter": "custom"}
	idx["shards"] = shards
	_write_json(INDEX_PATH, idx)
	_new_dlg.text = ""
	_status.text = "已新建对话 %s" % id
	_refresh_dlg_list()
	for i in _dlg_list.item_count:
		if _dlg_list.get_item_text(i) == id:
			_dlg_list.select(i); _on_dlg_select(i); break

func _on_new_line() -> void:
	if _current_dlg == "":
		_status.text = "请先选择一个对话"
		return
	if not _current_shard.has("lines"):
		_current_shard["lines"] = []
	var lines: Array = _current_shard["lines"]
	var nid := "line_%d" % (lines.size() + 1)
	var ln := {"id": nid, "speaker_id": "npc", "text": "新台词", "next_id": ""}
	lines.append(ln)
	_current_shard["lines"] = lines
	_write_shard()
	_line_list.add_item(nid)
	_status.text = "已新建台词 %s" % nid

func _on_save_line() -> void:
	if _current_dlg == "":
		_status.text = "请先选择一个对话"
		return
	var lid: String = _fields["id"].text.strip_edges()
	if lid == "":
		_status.text = "台词 id 不能为空"
		return
	var lines: Array = _current_shard.get("lines", [])
	var found := false
	for ln in lines:
		if String(ln.get("id", "")) == lid:
			ln["id"] = lid
			ln["speaker_id"] = _fields["speaker_id"].text
			ln["speaker_name"] = _fields["speaker_name"].text
			ln["text"] = _fields["text"].text
			ln["next_id"] = _fields["next_id"].text
			var te_str: String = _fields["trigger_events"].text.strip_edges()
			if te_str == "":
				ln["trigger_events"] = []
			else:
				var arr: Array = []
				for part in te_str.split(","):
					var s := String(part).strip_edges()
					if s != "":
						arr.append(s)
				ln["trigger_events"] = arr
			found = true
			break
	if not found:
		_status.text = "未找到台词 %s，请先点「新建台词」" % lid
		return
	_current_shard["lines"] = lines
	_write_shard()
	_status.text = "已保存台词 %s" % lid

func _on_del_line() -> void:
	if _current_dlg == "":
		_status.text = "请先选择一个对话"
		return
	var lid: String = _fields["id"].text.strip_edges()
	if lid == "":
		_status.text = "请先选择一条台词"
		return
	var lines: Array = []
	for ln in _current_shard.get("lines", []):
		if String(ln.get("id", "")) != lid:
			lines.append(ln)
	_current_shard["lines"] = lines
	_write_shard()
	_status.text = "已删除台词 %s" % lid
	_line_list.clear()
	for ln in lines:
		_line_list.add_item(String(ln.get("id", "?")))

func _on_del_dlg() -> void:
	if _current_dlg == "":
		_status.text = "请先选择一个对话"
		return
	var idx := _load_json(INDEX_PATH)
	var shards: Dictionary = idx.get("shards", {})
	if shards.has(_current_dlg):
		shards.erase(_current_dlg)
		idx["shards"] = shards
		_write_json(INDEX_PATH, idx)
	_status.text = "已从索引删除 %s（分片文件保留，可手动删）" % _current_dlg
	_refresh_dlg_list()
	_line_list.clear()
	_current_dlg = ""

func _write_shard() -> void:
	var idx := _load_json(INDEX_PATH)
	var shards: Dictionary = idx.get("shards", {})
	var entry: Dictionary = shards.get(_current_dlg, {})
	var file: String = String(entry.get("file", ""))
	if file == "":
		file = "res://data/configs/npcs/dialogs/shards/%s.json" % _current_dlg
	_write_json(file, _current_shard)

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
