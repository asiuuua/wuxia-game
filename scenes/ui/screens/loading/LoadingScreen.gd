# scenes/ui/screens/loading/LoadingScreen.gd
# 加载界面（代码构建 Control 覆盖层，挂在 UIManager.FULLSCREEN 层级）
# 进度来源：EventBus.bootstrap_started / bootstrap_step_completed / bootstrap_completed
#           （不新增 bootstrap_progress 信号，直接复用现有 bootstrap 信号累加算进度）
# 提示语来源：data/configs/ui/loading_tips.json（M6 再接 tr() 本地化）
# 完成（bootstrap_completed）后进度条平滑到 100%，短暂停顿（~1.1s）后自动进入主菜单。

@warning_ignore("shadowed_global_identifier")

extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")

const TIP_INTERVAL := 2.5
const TIPS_FILE := "res://data/configs/ui/loading_tips.json"

# 加载页背景图（与主菜单共用同款竹林图，风格统一；数据驱动，缺失则回退深墨色）
const BG_IMAGE_PATH := "res://assets/ui/main_menu_bg.jpg"
# 背景图上的压暗层透明度（保证标题/进度文字可读：0=不压暗，1=全黑）
const BG_IMAGE_SCRIM := 0.55

var _progress_bar: ProgressBar
var _progress_label: Label
var _tip_label: Label
var _version_label: Label

var _total_steps := 0
var _completed_steps := 0
var _tips: Array = []
var _tip_index := 0
var _tip_timer := 0.0
var _ready_to_enter := false
var _auto_enter_timer := 0.0   # bootstrap_completed 后倒计时；归零自动进入主菜单
var _progress_tween: Tween = null   # 进度条平滑缓动句柄（避免每步叠加 tween）

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_tips()
	_progress_label.text = tr("ui_loading_progress") % "0%"
	_connect_events()
	if not _tips.is_empty():
		_tip_label.text = _tips[0]

func _build_ui() -> void:
	# 背景：有竹林图用图（叠压暗层+落叶氛围），无图回退深墨色
	var vw: float = maxf(get_viewport_rect().size.x, 1280.0)
	var vh: float = maxf(get_viewport_rect().size.y, 720.0)
	if ResourceLoader.exists(BG_IMAGE_PATH):
		_add_image_background(vw, vh)
	else:
		var bg: ColorRect = ColorRect.new()
		bg.color = UIPalette.BG_DARK
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(bg)

	# === 布局：无 LOGO 标题（与主菜单统一精简）；提示语在中上部、进度百分比在进度条正上方、进度条居中靠底一指空隙 ===
	# 1) 提示语（中央偏上 0.55；完成态时再下移到进度条正上方，见 _on_bootstrap_completed）
	_tip_label = Label.new()
	_tip_label.text = ""
	_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_tip_label.add_theme_font_size_override("font_size", UIPalette.FS_SUB)
	_tip_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	_tip_label.anchor_left = 0.5
	_tip_label.anchor_right = 0.5
	_tip_label.anchor_top = 0.55
	_tip_label.anchor_bottom = 0.55
	_tip_label.offset_left = -400.0
	_tip_label.offset_right = 400.0
	add_child(_tip_label)

	# 3) 进度百分比（进度条正上方）
	_progress_label = Label.new()
	_progress_label.text = tr("ui_loading_progress") % "0%"
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_progress_label.add_theme_font_size_override("font_size", UIPalette.FS_BODY)
	_progress_label.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	_progress_label.anchor_left = 0.5
	_progress_label.anchor_right = 0.5
	_progress_label.anchor_top = 0.88
	_progress_label.anchor_bottom = 0.88
	_progress_label.offset_left = -100.0
	_progress_label.offset_right = 100.0
	add_child(_progress_label)

	# 4) 进度条（最底部、居中、用绝对偏移固定距底一指空隙，跨分辨率一致）
	# 一指空隙 ≈ 38px（中等手指宽度），进度条高 6；offset_top=-44 距底 38px。
	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(600, 6)
	_progress_bar.size = Vector2(600, 6)
	_progress_bar.max_value = 100.0
	_progress_bar.value = 0.0
	# 本地样式：圆角同步缩小、底槽半透明更收敛，不依赖全局主题（便于后续单独做加载动画）
	var bg_style := StyleBoxFlat.new()
	bg_style.bg_color = Color(0.1, 0.08, 0.06, 0.6)
	bg_style.corner_radius_top_left = 2
	bg_style.corner_radius_top_right = 2
	bg_style.corner_radius_bottom_left = 2
	bg_style.corner_radius_bottom_right = 2
	_progress_bar.add_theme_stylebox_override("bg", bg_style)
	var fill_style := StyleBoxFlat.new()
	fill_style.bg_color = UIPalette.GOLD
	fill_style.corner_radius_top_left = 2
	fill_style.corner_radius_top_right = 2
	fill_style.corner_radius_bottom_left = 2
	fill_style.corner_radius_bottom_right = 2
	_progress_bar.add_theme_stylebox_override("fill", fill_style)
	_progress_bar.anchor_left = 0.5
	_progress_bar.anchor_right = 0.5
	_progress_bar.anchor_top = 1.0
	_progress_bar.anchor_bottom = 1.0
	_progress_bar.offset_left = -300.0
	_progress_bar.offset_right = 300.0
	_progress_bar.offset_top = -44.0
	_progress_bar.offset_bottom = -38.0
	add_child(_progress_bar)

	# 版本号（右下角）
	_version_label = Label.new()
	_version_label.text = "v0.5.0 Build 20250827"
	_version_label.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
	_version_label.add_theme_color_override("font_color", UIPalette.DISABLED)
	_version_label.anchors_preset = Control.PRESET_BOTTOM_RIGHT
	_version_label.anchor_left = 1.0
	_version_label.anchor_top = 1.0
	_version_label.anchor_right = 1.0
	_version_label.anchor_bottom = 1.0
	_version_label.offset_left = -180.0
	_version_label.offset_top = -32.0
	_version_label.offset_right = -UIPalette.MARGIN
	_version_label.offset_bottom = -10.0
	_version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(_version_label)

func _add_image_background(vw: float, vh: float) -> void:
	var img_rect := TextureRect.new()
	img_rect.texture = load(BG_IMAGE_PATH) as Texture2D
	img_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(img_rect)

	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(UIPalette.BG_DARK.r, UIPalette.BG_DARK.g, UIPalette.BG_DARK.b, BG_IMAGE_SCRIM)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

	# 复用主菜单的落叶氛围（保持两界面视觉连贯）
	var leaves := _build_leaves(vw, vh)
	add_child(leaves)

func _build_leaves(vw: float, _vh: float) -> CPUParticles2D:
	var leaves := CPUParticles2D.new()
	leaves.emitting = true
	leaves.amount = 24
	leaves.lifetime = 9.0
	leaves.gravity = Vector2(0, 26)
	leaves.initial_velocity_min = 18.0
	leaves.initial_velocity_max = 55.0
	leaves.direction = Vector2(0.15, 1.0)
	leaves.spread = 18.0
	leaves.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	leaves.emission_rect_extents = Vector2(vw / 2.0, 24.0)
	leaves.position = Vector2(vw / 2.0, -24.0)
	leaves.scale = Vector2(1.6, 1.6)
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(UIPalette.GOLD)
	leaves.texture = ImageTexture.create_from_image(img)
	return leaves

func _load_tips() -> void:
	if not FileAccess.file_exists(TIPS_FILE):
		_tips = [tr("ui_loading_tip_fallback")]
		return
	var f: FileAccess = FileAccess.open(TIPS_FILE, FileAccess.READ)
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or not parsed.has("tips"):
		_tips = [tr("ui_loading_tip_fallback")]
		return
	_tips = parsed["tips"]

func _connect_events() -> void:
	if not EventBus.bootstrap_started.is_connected(_on_bootstrap_started):
		EventBus.bootstrap_started.connect(_on_bootstrap_started)
	if not EventBus.bootstrap_step_completed.is_connected(_on_step_completed):
		EventBus.bootstrap_step_completed.connect(_on_step_completed)
	if not EventBus.bootstrap_completed.is_connected(_on_bootstrap_completed):
		EventBus.bootstrap_completed.connect(_on_bootstrap_completed)

func _on_bootstrap_started(total: int) -> void:
	_total_steps = total

func _on_step_completed(_step_name: String, _index: int) -> void:
	_completed_steps += 1
	_update_progress()

func _on_bootstrap_completed() -> void:
	_update_progress()   # 内部触发 _set_progress_smooth(100.0)，平滑 tween ~0.4s
	_ready_to_enter = true
	# 完成态强调：提示语下沉到进度条正上方（"接近下方黄条"），字号加大+变金，视觉重心从"过程"转"准备进入"
	# 进度条顶边距底 44px，让 tip 底边距底 50px → 提示语与黄条之间留 6px 呼吸
	_tip_label.anchor_top = 1.0
	_tip_label.anchor_bottom = 1.0
	_tip_label.offset_top = -80.0
	_tip_label.offset_bottom = -52.0
	_tip_label.add_theme_font_size_override("font_size", UIPalette.FS_NAME)
	_tip_label.text = "「%s」" % tr("ui_loading_ready")
	_tip_label.add_theme_color_override("font_color", UIPalette.GOLD)
	# 完成态强调：提示语呼吸脉冲作为视觉提示；不再需要玩家点击，由 _process 倒计时自动进游戏
	var pulse := create_tween()
	pulse.set_loops()
	pulse.tween_property(_tip_label, "modulate:a", 0.45, 0.7)
	pulse.tween_property(_tip_label, "modulate:a", 1.0, 0.7)
	# 进度 tween(~0.4s) + 短暂停顿(~0.7s) → 用户能看到「100% 完成态」，再自动切到主菜单
	_auto_enter_timer = 1.1

func _update_progress() -> void:
	var pct: float = 0.0
	if _total_steps > 0:
		pct = float(_completed_steps) / float(_total_steps) * 100.0
	_set_progress_smooth(pct)
	_progress_label.text = tr("ui_loading_progress") % ("%d%%" % int(pct))

## 进度条平滑缓动：每步到位不再跳变，缓出过渡更顺眼
func _set_progress_smooth(pct: float) -> void:
	if _progress_tween != null and _progress_tween.is_valid():
		_progress_tween.kill()
	_progress_tween = create_tween()
	_progress_tween.tween_property(_progress_bar, "value", pct, 0.4).set_ease(Tween.EASE_OUT)

func _process(delta: float) -> void:
	# 完成态：倒计时归零自动进入主菜单（替原来的手动点击确认）
	if _ready_to_enter:
		_auto_enter_timer -= delta
		if _auto_enter_timer <= 0.0:
			_auto_enter_timer = 0.0
			_enter_main_menu()
		return
	_tip_timer += delta
	if _tip_timer >= TIP_INTERVAL:
		_tip_timer = 0.0
		_next_tip()

func _next_tip() -> void:
	if _tips.is_empty():
		return
	_tip_index = (_tip_index + 1) % _tips.size()
	_tip_label.text = _tips[_tip_index]

func _enter_main_menu() -> void:
	UIManager.open_screen("MainMenu", UIManager.Layer.FULLSCREEN)
	UIManager.close_screen(self)
