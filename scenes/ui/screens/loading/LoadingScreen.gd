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
# 加载界面元素布局（工作室「预加载界面」标签页自由拖拽可视化编辑后写入；坐标为视口归一化 0~1）。
# 缺省/字段缺失时回退到原预设位置，零破坏。
const LAYOUT_FILE := "res://data/configs/ui/loading_layout.json"

# 加载页背景图（与主菜单共用同款竹林图，风格统一；数据驱动，缺失则回退深墨色）
const BG_IMAGE_PATH := "res://assets/ui/main_menu_bg.png"
# 背景图上的压暗层透明度（保证标题/进度文字可读：0=不压暗，1=全黑）
const BG_IMAGE_SCRIM := 0.55

# B 路线（2026-08-29）：静态结构（提示语 TipLabel / 进度百分比 ProgressLabel / 进度条 ProgressBar
# / 版本号 VersionLabel，含进度条磨砂皮肤）已迁入 LoadingScreen.tscn，美术可在编辑器改外观；
# 背景（图片/深墨色，运行时择一）仍动态构建并压到最底层（BGHolder → index 0）。
@onready var _progress_bar: ProgressBar = $ProgressBar
@onready var _progress_label: Label = $ProgressLabel
@onready var _tip_label: Label = $TipLabel
@onready var _version_label: Label = $VersionLabel

var _total_steps := 0
var _completed_steps := 0
var _tips: Array = []
var _tip_index := 0
var _tip_timer := 0.0
var _ready_to_enter := false
var _auto_enter_timer := 0.0   # bootstrap_completed 后倒计时；归零自动进入主菜单
var _progress_tween: Tween = null   # 进度条平滑缓动句柄（避免每步叠加 tween）
var _applying_layout := false       # 工作室布局套用重入保护（resize 回调与初始化可能并发）

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_tips()
	_progress_label.text = tr("ui_loading_progress") % "0%"
	_connect_events()
	if not _tips.is_empty():
		_tip_label.text = _tips[0]
	# 工作室拖拽布局：延后一帧套用（等 .tscn 尺寸与文案定稿，拿到的内容宽才准）
	_apply_layout.call_deferred()
	# 窗口尺寸变化（含不同比例屏幕）时按新视口重算归一化坐标
	resized.connect(_on_resized)

func _build_ui() -> void:
	# B 路线（2026-08-29）：TipLabel / ProgressLabel / ProgressBar / VersionLabel 已迁入
	# LoadingScreen.tscn（美术可在编辑器改外观），此处不再 new 这 4 个节点，只保留动态背景。
	# 动态背景（图片/深墨色，运行时择一）构建进 BGHolder 并压到最底（index 0），
	# 让 .tscn 的 4 个静态节点始终位于背景之上（与 MainMenu._build_background 同款思路）。
	var bg_holder := Control.new()
	bg_holder.name = "BGHolder"
	bg_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var vw: float = maxf(get_viewport_rect().size.x, 1280.0)
	var vh: float = maxf(get_viewport_rect().size.y, 720.0)
	if ResourceLoader.exists(BG_IMAGE_PATH):
		_add_image_background(bg_holder, vw, vh)
	else:
		var bg: ColorRect = ColorRect.new()
		bg.color = UIPalette.BG_DARK
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		bg_holder.add_child(bg)
	add_child(bg_holder)
	move_child(bg_holder, 0)

	# 版本号文本（原 _build_ui 里 new Label 设置的内容，现赋给 .tscn 节点）
	_version_label.text = "v0.5.0 Build 20250827"

# 工作室「预加载界面」自由拖拽布局：读取 loading_layout.json 的归一化(0~1)坐标套用到 4 个元素。
# 任意字段缺失/文件不存在 → 保持 .tscn 原预设位置（零破坏）。坐标以视口当前尺寸换算为偏移量。
func _apply_layout() -> void:
	if _applying_layout:
		return
	_applying_layout = true
	if not FileAccess.file_exists(LAYOUT_FILE):
		_applying_layout = false
		return
	var f: FileAccess = FileAccess.open(LAYOUT_FILE, FileAccess.READ)
	if f == null:
		_applying_layout = false
		return
	var json := JSON.new()
	if json.parse(f.get_as_text()) != OK:
		f.close()
		_applying_layout = false
		return
	f.close()
	var parsed: Variant = json.data
	if parsed == null or not parsed is Dictionary or not (parsed as Dictionary).has("elements"):
		_applying_layout = false
		return
	var els: Dictionary = (parsed as Dictionary)["elements"]
	var vw: float = get_viewport_rect().size.x
	var vh: float = get_viewport_rect().size.y
	_apply_one(_progress_bar, els.get("progress_bar", {}), vw, vh, true)
	_apply_one(_progress_label, els.get("progress_label", {}), vw, vh, false)
	_apply_one(_tip_label, els.get("tip_label", {}), vw, vh, false)
	_apply_one(_version_label, els.get("version_label", {}), vw, vh, false)
	_applying_layout = false

func _on_resized() -> void:
	# 窗口尺寸变化（含首次布局）时按新视口重算归一化坐标，避免错误位置
	_apply_layout.call_deferred()

# spec: {"x":0~1,"y":0~1,"w":0~1,"h":0~1(仅进度条用),"align":"left|center|right"}
# 定位语义（与工作室预览严格一致）：y = 元素顶部；x = 锚点，按 align 左/居中/右回退自身宽度。
func _apply_one(node: Control, spec: Dictionary, vw: float, vh: float, is_bar: bool) -> void:
	if spec.is_empty() or not spec.has("x") or not spec.has("y"):
		return
	var px: float = float(spec["x"]) * vw
	var py: float = float(spec["y"]) * vh
	var w: float
	var h: float
	if is_bar:
		w = float(spec.get("w", 0.5)) * vw
		h = maxf(float(spec.get("h", 0.02)) * vh, 4.0)
		node.custom_minimum_size = Vector2(w, h)
	else:
		# 文字类：宽度取内容宽与视口 60% 的较大值，保证文案变长时居中/右对齐依旧稳
		var mins: Vector2 = node.get_combined_minimum_size()
		w = maxf(mins.x, vw * 0.6)
		h = maxf(mins.y, 1.0)
	var align: String = String(spec.get("align", "center"))
	if align == "right":
		px -= w
	elif align == "center":
		px -= w * 0.5
	# 锚点归零到左上角后，用四个 offset 显式写死矩形：不依赖 anchor 等值的零宽陷阱，行为完全可控
	node.anchor_left = 0.0
	node.anchor_top = 0.0
	node.anchor_right = 0.0
	node.anchor_bottom = 0.0
	node.offset_left = px
	node.offset_top = py
	node.offset_right = px + w
	node.offset_bottom = py + h
	node.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	node.grow_vertical = Control.GROW_DIRECTION_BEGIN
	# horizontal_alignment 仅 Label 有；ProgressBar 无此属性，直接赋值会崩溃，故按类型分支
	if node is Label:
		if align == "right":
			node.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		elif align == "left":
			node.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		else:
			node.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _add_image_background(parent: Control, vw: float, vh: float) -> void:
	# 多分辨率变体：与主菜单共用同一套档位表（无变体表时原样用主图）
	# UIBackground 有全局 class_name，直接调用其静态方法即可，无需 preload
	var use_path := UIBackground.pick_bg_path(vw, BG_IMAGE_PATH)
	var img_rect := TextureRect.new()
	img_rect.texture = load(use_path) as Texture2D
	img_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(img_rect)

	var scrim: ColorRect = ColorRect.new()
	scrim.color = Color(UIPalette.BG_DARK.r, UIPalette.BG_DARK.g, UIPalette.BG_DARK.b, BG_IMAGE_SCRIM)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(scrim)

	# 复用主菜单的落叶氛围（保持两界面视觉连贯）
	var leaves := _build_leaves(vw, vh)
	parent.add_child(leaves)

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

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后填充示例进度/提示
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_progress_bar = $ProgressBar
	_progress_label = $ProgressLabel
	_tip_label = $TipLabel
	_version_label = $VersionLabel
	if _progress_bar == null or _version_label == null:
		return
	_version_label.text = "v0.5.0 Build 20250827"
	_progress_bar.value = 64.0
	_progress_label.text = "加载中 %d%%" % 64
	_tip_label.text = "江湖路远，且行且珍惜。"
