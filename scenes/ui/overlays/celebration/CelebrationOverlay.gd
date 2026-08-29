# scenes/ui/overlays/celebration/CelebrationOverlay.gd
# 欢庆模块 CG 播放界面（结缘窗口主权）：由 BondRomanceScreen 经 UIManager.open_screen 打开。
# 两种模式（经 _on_open(init_data) 注入）：
#   - mode="cg"      播放欢庆 CG：媒体(视频/图片/音乐预留) + 台词，最长 10 秒，结束后播放“end”内容
#   - mode="over_limit"  超配额对话框：内容来自 celebrations.json 的 over_limit 项（预留接口）
# ⚠️ 开放接口：所有媒体/台词均读 data/configs/bond/celebrations.json，后续你直接改该表即可
#    一键替换视频/图片/音乐/台词，无需动代码。媒体节点自动铺满媒体框；视频最长 10 秒，超时自动截断。

extends Control
class_name CelebrationOverlay

const ResourceManager = preload("res://core/resource_manager.gd")

const TABLE_PATH := "res://data/configs/bond/celebrations.json"
const MAX_CG_SECONDS := 10.0
const END_HOLD_SECONDS := 3.0

var _mode: String = "cg"
var _npc_id: String = ""
var _cg_id: String = "default"
var _media_box: Control = null
var _lines_label: Label = null
var _btn_row: HBoxContainer = null
var _bgm_player: AudioStreamPlayer = null
var _timer: Timer = null
var _built := false
# 已 acquire_async 的媒体/音乐路径，关闭/退出时须 release 归还引用计数，否则 CG 大媒体常驻不释放（P5 目标落空）。
var _media_path: String = ""
var _bgm_path: String = ""

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	if not _built:
		_build()

## UIManager.open_screen 注入初始化数据：{"mode": "cg"|"over_limit", "npc_id":, "cg_id":}
func _on_open(data: Variant) -> void:
	if data is Dictionary:
		_mode = String(data.get("mode", "cg"))
		_npc_id = String(data.get("npc_id", ""))
		_cg_id = String(data.get("cg_id", "default"))
	# UIManager 在 add_child 前先调 _on_open，_ready 尚未执行；此处兜底先构建。
	if not _built:
		_build()
	_build_content()

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.0, 0.0, 0.0, 0.92)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	var _psz := Vector2(760, 520)
	panel.custom_minimum_size = _psz
	panel.size = _psz
	panel.anchor_left = 0.5; panel.anchor_top = 0.5; panel.anchor_right = 0.5; panel.anchor_bottom = 0.5
	panel.offset_left = -_psz.x * 0.5; panel.offset_top = -_psz.y * 0.5
	panel.offset_right = _psz.x * 0.5; panel.offset_bottom = _psz.y * 0.5
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.08, 0.10, 0.14, 0.98)
	sb.border_color = Color(0.85, 0.7, 0.35, 0.9)
	sb.border_width_left = 1; sb.border_width_top = 1; sb.border_width_right = 1; sb.border_width_bottom = 1
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var title := Label.new()
	title.text = "欢庆" if _mode != "over_limit" else "欢庆 · 今日已尽"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.45))
	v.add_child(title)
	_media_box = Control.new()
	_media_box.custom_minimum_size = Vector2(700, 280)
	_media_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_media_box)
	_lines_label = Label.new()
	_lines_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_lines_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lines_label.add_theme_font_size_override("font_size", 18)
	_lines_label.add_theme_color_override("font_color", Color(0.95, 0.95, 0.92))
	v.add_child(_lines_label)
	_btn_row = HBoxContainer.new()
	_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_btn_row.add_theme_constant_override("separation", 12)
	v.add_child(_btn_row)
	_built = true

func _build_content() -> void:
	var table: Dictionary = _load_table()
	if _mode == "over_limit":
		_show_content(table.get("over_limit", {}))
		_add_button("关闭", true, _on_close_pressed)
		return
	var entry: Dictionary = table.get("default", {}) if _cg_id == "default" else table.get(_cg_id, table.get("default", {}))
	_show_content(entry.get("cg", {}))
	_add_button("跳过", true, _on_skip_pressed)
	_start_timer(MAX_CG_SECONDS, _on_cg_timeout)

## 把一段内容（媒体+台词）铺到界面
func _show_content(cfg: Dictionary) -> void:
	_clear_media()
	var lines: Array = cfg.get("lines", [])
	_lines_label.text = "\n".join(lines)
	_apply_media(cfg)
	_play_bgm(cfg)

## 媒体按类型异步流式加载（工业化扩容 P5/P6）：非阻塞发起后台加载，
## 加载完成回调 _on_media_ready 再建播放节点，避免大视频/图片同步 load 卡开场。
## 台词/文字仍立即显示，媒体"流式"补位。
func _apply_media(cfg: Dictionary) -> void:
	var mtype: String = String(cfg.get("media_type", "none"))
	var mpath: String = String(cfg.get("media_path", ""))
	if mpath == "" or not ResourceLoader.exists(mpath):
		return
	_media_path = mpath
	ResourceManager.acquire_async(mpath, _media_type_hint(mtype), _on_media_ready.bind(mpath))

## 加载完成回调：依资源实际类型建节点（视频/图片），铺满媒体框。
func _on_media_ready(path: String, res: Variant) -> void:
	if res == null:
		return
	if res is VideoStream:
		# ⚠️ 必须用 full-rect 锚点铺满父容器：布局尚未结算时 _media_box.size 可能是 (0,0)，
		# 直接设 .size 会让视频节点尺寸为 0，导致“有声音但看不见画面”。
		var vp := VideoStreamPlayer.new()
		vp.stream = res
		vp.expand = true
		vp.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		vp.play()
		_media_box.add_child(vp)
	elif res is Texture2D:
		var tex := TextureRect.new()
		tex.texture = res
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_media_box.add_child(tex)

## 媒体类型 → ResourceLoader 类型提示（视频需显式 VideoStream，图片/其它留空推断）。
func _media_type_hint(mtype: String) -> String:
	if mtype == "video":
		return "VideoStream"
	return ""

func _play_bgm(cfg: Dictionary) -> void:
	var bgm: String = String(cfg.get("bgm", ""))
	if bgm == "" or not ResourceLoader.exists(bgm):
		return
	_bgm_path = bgm
	ResourceManager.acquire_async(bgm, "", _on_bgm_ready)

func _on_bgm_ready(res: Variant) -> void:
	if res == null or not (res is AudioStream):
		return
	_bgm_player = AudioStreamPlayer.new()
	_bgm_player.stream = res
	add_child(_bgm_player)
	_bgm_player.play()

func _clear_media() -> void:
	if _media_box == null or not is_instance_valid(_media_box):
		return
	for c in _media_box.get_children():
		c.queue_free()
	# 归还媒体/音乐引用计数，使 ResourceManager 分级回收能真正释放 CG 大视频/贴图（修复常驻泄漏）。
	if _media_path != "":
		ResourceManager.evict(_media_path)
		_media_path = ""
	if _bgm_path != "":
		ResourceManager.evict(_bgm_path)
		_bgm_path = ""

func _add_button(text: String, enabled: bool, cb: Callable) -> void:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	_btn_row.add_child(b)

func _start_timer(sec: float, cb: Callable) -> void:
	_stop_timer()
	_timer = Timer.new()
	_timer.wait_time = sec
	_timer.one_shot = true
	_timer.timeout.connect(cb)
	add_child(_timer)
	_timer.start()

func _stop_timer() -> void:
	if _timer != null and is_instance_valid(_timer):
		_timer.stop()
		_timer.queue_free()
		_timer = null

# 10 秒到：停止媒体/音乐，切换到 end 内容，短暂停留后自动关闭
func _on_cg_timeout() -> void:
	_finish_to_end()

# 跳过：立即进入 end
func _on_skip_pressed() -> void:
	_finish_to_end()

func _finish_to_end() -> void:
	_stop_timer()
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_player.stop()
		_bgm_player = null
	_clear_media()
	var table: Dictionary = _load_table()
	var entry: Dictionary = table.get("default", {}) if _cg_id == "default" else table.get(_cg_id, table.get("default", {}))
	_show_content(entry.get("end", {}))
	for b in _btn_row.get_children():
		b.queue_free()
	_add_button("关闭", true, _on_close_pressed)
	_start_timer(END_HOLD_SECONDS, _on_close_pressed)

func _on_close_pressed() -> void:
	_stop_timer()
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_player.stop()
		_bgm_player = null
	_clear_media()
	UIManager.close_screen(self)

# === 读内容表（直接 FileAccess，不碰冻结的 ConfigManager） ===
func _load_table() -> Dictionary:
	if not FileAccess.file_exists(TABLE_PATH):
		return {}
	var f := FileAccess.open(TABLE_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if parsed is Dictionary:
		return parsed
	return {}

func _exit_tree() -> void:
	_stop_timer()
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_player.stop()
	_clear_media()
