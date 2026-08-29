@tool
extends Control

# 欢庆内容管理面板（编辑器专用，无 class_name，仅由 plugin.gd 在编辑器加载）。
# 让作者（小白友好）可视化地：选/绑 NPC → 导入 CG 视频·图片 / 音乐 / 台词 → 编辑 → 一键保存写回
# res://data/configs/bond/celebrations.json（按 npc_id 分键，CelebrationOverlay 自动回退 default）。

const RELATIONS_PATH := "res://data/configs/bond/relations.json"
const CELEBRATIONS_PATH := "res://data/configs/bond/celebrations.json"
const CG_DIR := "res://resources/cg"

var _vbox: VBoxContainer = null
var _npc_sel: OptionButton = null
var _new_id: LineEdit = null
var _mtype: OptionButton = null
var _media_path: LineEdit = null
var _bgm_path: LineEdit = null
var _lines: TextEdit = null
var _end_lines: TextEdit = null
var _status: Label = null
var _fd: EditorFileDialog = null

var _current_npc: String = ""
var _pending_import: String = ""   # "cg" | "bgm" | "txt"
var _mtype_val: String = "none"

func _ready() -> void:
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 6)
	scroll.add_child(_vbox)

	var title := Label.new()
	title.text = "欢庆内容管理器 (Celebration Manager)"
	title.add_theme_font_size_override("font_size", 16)
	_vbox.add_child(title)
	_vbox.add_child(_sep())

	# --- NPC 选择 / 绑定 ---
	var hint := Label.new()
	hint.text = "① 选一个可结缘的 NPC（或绑定新 id），再编辑它的欢庆内容："
	_vbox.add_child(hint)
	var npc_row := HBoxContainer.new()
	_vbox.add_child(npc_row)
	var l1 := Label.new(); l1.text = "NPC："; npc_row.add_child(l1)
	_npc_sel = OptionButton.new(); npc_row.add_child(_npc_sel)
	var refresh := Button.new(); refresh.text = "刷新列表"; npc_row.add_child(refresh)
	var bind := Button.new(); bind.text = "＋绑定新NPC"; npc_row.add_child(bind)

	var bind_row := HBoxContainer.new()
	_vbox.add_child(bind_row)
	_new_id = LineEdit.new()
	_new_id.placeholder_text = "输入 NPC 的 id，例如 npc_xiao_ying"
	_new_id.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bind_row.add_child(_new_id)
	var bind2 := Button.new(); bind2.text = "绑定"; bind_row.add_child(bind2)

	_vbox.add_child(_sep())
	var cg_hint := Label.new(); cg_hint.text = "② 编辑该 NPC 的欢庆 CG 内容："; _vbox.add_child(cg_hint)

	# 媒体类型
	var mt_row := HBoxContainer.new(); _vbox.add_child(mt_row)
	var l2 := Label.new(); l2.text = "媒体类型："; mt_row.add_child(l2)
	_mtype = OptionButton.new(); mt_row.add_child(_mtype)
	_mtype.add_item("none"); _mtype.add_item("image"); _mtype.add_item("video")

	# 媒体路径 + 导入按钮
	var mp_row := HBoxContainer.new(); _vbox.add_child(mp_row)
	var l3 := Label.new(); l3.text = "CG媒体："; mp_row.add_child(l3)
	_media_path = LineEdit.new(); _media_path.placeholder_text = "留空=无；或点右侧导入"; _media_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mp_row.add_child(_media_path)
	var imp_cg := Button.new(); imp_cg.text = "导入CG(视频/图片)…"; mp_row.add_child(imp_cg)

	# bgm
	var bm_row := HBoxContainer.new(); _vbox.add_child(bm_row)
	var l4 := Label.new(); l4.text = "背景音乐："; bm_row.add_child(l4)
	_bgm_path = LineEdit.new(); _bgm_path.placeholder_text = "留空=无；或点右侧导入"; _bgm_path.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bm_row.add_child(_bgm_path)
	var imp_bgm := Button.new(); imp_bgm.text = "导入音乐…"; bm_row.add_child(imp_bgm)

	# 台词
	var ll := Label.new(); ll.text = "欢庆台词（每行一条）："; _vbox.add_child(ll)
	_lines = TextEdit.new(); _lines.custom_minimum_size = Vector2(0, 120); _lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_lines)

	var el := Label.new(); el.text = "结束内容台词："; _vbox.add_child(el)
	_end_lines = TextEdit.new(); _end_lines.custom_minimum_size = Vector2(0, 80); _end_lines.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_child(_end_lines)

	# 动作
	var act := HBoxContainer.new(); _vbox.add_child(act)
	var imp_txt := Button.new(); imp_txt.text = "导入台词.txt"; act.add_child(imp_txt)
	var save := Button.new(); save.text = "保存"; act.add_child(save)
	var del := Button.new(); del.text = "删除该NPC"; act.add_child(del)
	var prev := Button.new(); prev.text = "预览JSON"; act.add_child(prev)

	_status = Label.new(); _status.text = "就绪"; _vbox.add_child(_status)

	# 文件选择对话框（编辑器专用）
	_fd = EditorFileDialog.new()
	_fd.access = EditorFileDialog.ACCESS_FILESYSTEM
	_fd.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	add_child(_fd)

	# 信号
	_npc_sel.item_selected.connect(_on_npc_selected)
	refresh.pressed.connect(_populate_npcs)
	bind.pressed.connect(_bind_new_npc)
	bind2.pressed.connect(_bind_new_npc)
	_mtype.item_selected.connect(_on_mtype_selected)
	imp_cg.pressed.connect(_open_import.bind("cg"))
	imp_bgm.pressed.connect(_open_import.bind("bgm"))
	imp_txt.pressed.connect(_open_import.bind("txt"))
	save.pressed.connect(_save)
	del.pressed.connect(_delete)
	prev.pressed.connect(_preview)
	_fd.file_selected.connect(_on_file_selected)

	_populate_npcs()

func _sep() -> HSeparator:
	return HSeparator.new()

# === NPC 列表 ===
func _populate_npcs() -> void:
	_npc_sel.clear()
	var rel := _load_json(RELATIONS_PATH)
	var ids: Array = []
	for r in Array(rel.get("relations", [])):
		if bool(r.get("is_romanceable", false)):
			ids.append(String(r.get("id", "")))
	# 也纳入已在 celebrations.json 中、但可能不在 relations 的 npc 键
	var cel := _load_json(CELEBRATIONS_PATH)
	for k in cel.keys():
		if String(k).begins_with("_"):
			continue
		if k == "default" or k == "over_limit":
			continue
		if not ids.has(k):
			ids.append(String(k))
	for id in ids:
		_npc_sel.add_item(id)
	if _npc_sel.item_count > 0:
		_npc_sel.select(0)
		_on_npc_selected(0)

func _on_npc_selected(idx: int) -> void:
	if idx < 0 or idx >= _npc_sel.item_count:
		return
	_current_npc = _npc_sel.get_item_text(idx)
	_load_into_fields(_current_npc)

func _bind_new_npc() -> void:
	var id := _new_id.text.strip_edges()
	if id == "":
		_status.text = "请输入 NPC id 再绑定"
		return
	for i in _npc_sel.item_count:
		if _npc_sel.get_item_text(i) == id:
			_npc_sel.select(i)
			_on_npc_selected(i)
			return
	_npc_sel.add_item(id)
	_npc_sel.select(_npc_sel.item_count - 1)
	_on_npc_selected(_npc_sel.item_count - 1)
	_new_id.text = ""
	_status.text = "已绑定新 NPC：%s（点「保存」后写入配置）" % id

func _load_into_fields(npc_id: String) -> void:
	var cel := _load_json(CELEBRATIONS_PATH)
	var entry: Dictionary = cel.get(npc_id, {})
	var cg: Dictionary = entry.get("cg", {})
	var end: Dictionary = entry.get("end", {})
	_set_mtype(String(cg.get("media_type", "none")))
	_media_path.text = String(cg.get("media_path", ""))
	_bgm_path.text = String(cg.get("bgm", ""))
	_lines.text = "\n".join(Array(cg.get("lines", [])))
	_end_lines.text = "\n".join(Array(end.get("lines", [])))
	_status.text = "已载入 %s" % npc_id

# === 媒体类型 ===
func _on_mtype_selected(idx: int) -> void:
	_mtype_val = _mtype.get_item_text(idx)

func _set_mtype(val: String) -> void:
	_mtype_val = val
	for i in _mtype.item_count:
		if _mtype.get_item_text(i) == val:
			_mtype.select(i)
			return

# === 导入 ===
func _open_import(kind: String) -> void:
	_pending_import = kind
	if _current_npc == "" and kind != "txt":
		# txt 导入不依赖当前 NPC，但 cg/bgm 需要
		pass
	_fd.clear_filters()
	if kind == "cg":
		_fd.add_filter("*.ogv ; Theora 视频")
		_fd.add_filter("*.webm ; WebM 视频")
		_fd.add_filter("*.mp4 ; MP4 视频")
		_fd.add_filter("*.png ; 图片")
		_fd.add_filter("*.jpg ; 图片")
		_fd.add_filter("*.jpeg ; 图片")
	elif kind == "bgm":
		_fd.add_filter("*.ogg ; Ogg 音乐")
		_fd.add_filter("*.mp3 ; MP3 音乐")
		_fd.add_filter("*.wav ; WAV 音乐")
	elif kind == "txt":
		_fd.add_filter("*.txt ; 台词文本")
	_fd.popup_centered(Vector2i(900, 600))

func _on_file_selected(path: String) -> void:
	if _pending_import == "txt":
		_import_lines_txt(path)
		return
	if _current_npc == "":
		_status.text = "请先选择/绑定一个 NPC，再导入 CG 或音乐"
		return
	var fname := path.get_file()
	var dest_rel := "%s/%s/%s" % [CG_DIR, _current_npc, fname]
	var dest_abs := ProjectSettings.globalize_path(dest_rel)
	var dir := DirAccess.open("res://")
	var mk := dir.make_dir_recursive("%s/%s" % [CG_DIR, _current_npc])
	if mk != OK:
		_status.text = "创建目录失败：%s" % error_string(mk)
		return
	var err := dir.copy(path, dest_abs)
	if err != OK:
		_status.text = "复制失败：%s" % error_string(err)
		return
	if _pending_import == "cg":
		_media_path.text = dest_rel
		var ext := fname.get_extension().to_lower()
		if ext in ["ogv", "webm", "mp4"]:
			_set_mtype("video")
		else:
			_set_mtype("image")
		_status.text = "已导入 CG：%s（类型=%s）" % [fname, _mtype_val]
	else:
		_bgm_path.text = dest_rel
		_status.text = "已导入音乐：%s" % fname

func _import_lines_txt(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		_status.text = "无法打开台词文件"
		return
	var txt := f.get_as_text()
	f.close()
	_lines.text = txt.strip_edges()
	_status.text = "已从 %s 导入台词（每行一条）" % path.get_file()

# === 保存 / 删除 / 预览 ===
func _build_entry() -> Dictionary:
	var lines_arr: Array = []
	for ln in _lines.text.split("\n"):
		var s := String(ln).strip_edges()
		if s != "":
			lines_arr.append(s)
	var end_arr: Array = []
	for ln in _end_lines.text.split("\n"):
		var s := String(ln).strip_edges()
		if s != "":
			end_arr.append(s)
	return {
		"cg": {
			"media_type": _mtype_val,
			"media_path": _media_path.text,
			"bgm": _bgm_path.text,
			"lines": lines_arr,
		},
		"end": {
			"media_type": "none",
			"media_path": "",
			"lines": end_arr,
		}
	}

func _save() -> void:
	if _current_npc == "":
		_status.text = "请先选择/绑定一个 NPC"
		return
	var cel := _load_json(CELEBRATIONS_PATH)
	cel[_current_npc] = _build_entry()
	_write_json(CELEBRATIONS_PATH, cel)
	_status.text = "已保存 %s 的欢庆内容（写回 celebrations.json）" % _current_npc
	_populate_npcs()
	for i in _npc_sel.item_count:
		if _npc_sel.get_item_text(i) == _current_npc:
			_npc_sel.select(i)
			break

func _delete() -> void:
	if _current_npc == "":
		return
	var cel := _load_json(CELEBRATIONS_PATH)
	if cel.has(_current_npc):
		cel.erase(_current_npc)
		_write_json(CELEBRATIONS_PATH, cel)
		_status.text = "已删除 %s 的欢庆配置" % _current_npc
		_populate_npcs()

func _preview() -> void:
	var s := JSON.stringify(_build_entry(), "\t")
	_status.text = "预览 %s：%s" % [_current_npc, s]
	print("[CelebrationManager] 预览 ", _current_npc, ": ", s)

# === JSON 读写辅助 ===
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
