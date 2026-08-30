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
const UIPalette = preload("res://core/constants/ui_theme.gd")
const PortraitCache = preload("res://core/portrait_cache_manager.gd")

const TABLE_PATH := "res://data/configs/bond/celebrations.json"
const MAX_CG_SECONDS := 10.0
const END_HOLD_SECONDS := 3.0

var _mode: String = "cg"
var _npc_id: String = ""
var _cg_id: String = "default"
# B 路线（2026-08-29）：静态外壳（Dim/Panel/Margin/VBox/TitleLabel/MediaBox/LinesLabel/BtnRow）
# 已迁入 CelebrationOverlay.tscn，美术可在编辑器改外观；脚本只保留动态逻辑（异步媒体/台词/计时）。
@onready var _title_label: Label = $Panel/Margin/VBox/TitleLabel
@onready var _media_box: Control = $Panel/Margin/VBox/MediaBox
@onready var _lines_label: Label = $Panel/Margin/VBox/LinesLabel
@onready var _btn_row: HBoxContainer = $Panel/Margin/VBox/BtnRow
var _bgm_player: AudioStreamPlayer = null
var _timer: Timer = null
# _on_open 先于 _ready 执行（UIManager 在 add_child 前注入 init_data）：用 _ready_done + _pending_open 延迟到 _ready 后构建内容
var _ready_done := false
var _pending_open: Variant = null
# 已进入关闭流程（跳过/超时/主动关闭/_exit_tree）。置位后所有在途异步回调直接丢弃，
# 防止 CG 媒体/音乐在节点已 queue_free 后才加载完成、把节点挂到已释放容器上导致崩溃/泄漏。
var _is_closing: bool = false
# 已 acquire_async 的媒体/音乐路径，关闭/退出时须 release 归还引用计数，否则 CG 大媒体常驻不释放（P5 目标落空）。
var _media_path: String = ""
var _bgm_path: String = ""

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_ready_done = true
	if _pending_open != null:
		var d: Variant = _pending_open
		_pending_open = null
		_open(d)

## UIManager.open_screen 注入初始化数据：{"mode": "cg"|"over_limit", "npc_id":, "cg_id":}
func _on_open(data: Variant) -> void:
	if data is Dictionary:
		_mode = String(data.get("mode", "cg"))
		_npc_id = String(data.get("npc_id", ""))
		_cg_id = String(data.get("cg_id", "default"))
	# UIManager 在 add_child 前先调 _on_open，_ready 尚未执行、@onready 节点未就绪；
	# 延迟到 _ready 后再构建内容（与 DialogOverlay 同款处理）。
	if _ready_done:
		_open(data)
	else:
		_pending_open = data

## 构建内容（在 _ready 之后调用，确保 @onready 节点已就绪）
func _open(_data: Variant) -> void:
	_title_label.text = _resolve_title()
	_build_content()

## 标题：优先用 celebrations.json 的 name 字段（模块改名开放接口），缺省回退默认文案
func _resolve_title() -> String:
	var table: Dictionary = _load_table()
	if _mode == "over_limit":
		return String(table.get("over_limit", {}).get("name", "欢庆 · 今日已尽"))
	return String(table.get("default", {}).get("name", "欢庆"))

## 立绘回退：视频/图片不可用时，播放该 NPC 的半身立绘占位，保证窗口「有立绘可看」
## （用户反馈：欢庆窗口只显示文字、不显示立绘 → 视频 mp4 官方构建不支持 → 静默丢弃；
##  此处用半身立绘兜底，后续美术导入 ogv/webm 或图片即自动生效。）
func _npc_half_body_path() -> String:
	if _npc_id == "":
		return ""
	if GameManager.dialogue_service != null:
		return GameManager.dialogue_service.resolve_half_body(_npc_id, false)
	var npc: Dictionary = ConfigManager.get_npc(_npc_id)
	if not npc.is_empty():
		var b: String = npc.get("half_body_portrait", "")
		if b == "":
			b = npc.get("portrait", "")
		return b
	return ""

# B 路线：静态外壳（Dim/Panel/Margin/VBox/标题/媒体框/台词/按钮行）已迁入 CelebrationOverlay.tscn，
# 美术可在编辑器改外观；脚本不再 new 这些节点。

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
		# 媒体缺失：直接立绘兜底（不空等异步）
		_show_fallback_portrait()
		return
	_media_path = mpath
	ResourceManager.acquire_async(mpath, _media_type_hint(mtype), _on_media_ready.bind(mpath))

## 加载完成回调：依资源实际类型建节点（视频/图片），铺满媒体框。
func _on_media_ready(path: String, res: Variant) -> void:
	# 竞态 guard：界面已关闭、节点/容器已释放、或这是被替换/清除的旧媒体回调，一律丢弃。
	if _is_closing or not is_instance_valid(self) or not is_instance_valid(_media_box):
		return
	if path != _media_path:
		return
	if res == null:
		# 资源加载失败（如 mp4 官方构建不支持）→ 立绘兜底，避免「只有文字」的空窗
		_show_fallback_portrait()
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
	else:
		_show_fallback_portrait()

## 立绘兜底：把该 NPC 半身立绘铺到媒体框（视频/图片不可用时保证窗口有立绘）
func _show_fallback_portrait() -> void:
	if _is_closing or not is_instance_valid(self) or not is_instance_valid(_media_box):
		return
	var p: String = _npc_half_body_path()
	if p == "" or not ResourceLoader.exists(p):
		return
	var tex := PortraitCache.get_portrait(p)
	if tex == null:
		return
	_clear_media()
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_media_box.add_child(tr)

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
	if _is_closing or not is_instance_valid(self):
		return
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
	_is_closing = true
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
	_is_closing = true
	_stop_timer()
	if _bgm_player != null and is_instance_valid(_bgm_player):
		_bgm_player.stop()
	_clear_media()
