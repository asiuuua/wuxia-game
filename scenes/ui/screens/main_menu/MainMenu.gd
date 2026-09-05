@tool
# scenes/ui/screens/main_menu/MainMenu.gd
# 主菜单界面（B 路线：静态容器已迁入 MainMenu.tscn，动态按钮由 WuxiaMenuButton 预制实例化）
# M2 范围：5 选项 + 键盘/鼠标导航 + 快捷键 + 动态背景 + 主题常量
# UI 只做展示与输入，业务逻辑调用 GameManager / SaveManager
# 文案经 tr() 本地化（M6）：键在 data/configs/localization/strings.csv
# 2026-09-01 改用 WuxiaMenuButton 预制，水墨风格 hover 切图 + 图标高亮占位

@warning_ignore("shadowed_global_identifier")

extends BaseScreen

const WuxiaMenuButton = preload("res://scenes/ui/components/wuxia_menu_button/WuxiaMenuButton.gd")
const WuxiaMenuButtonScene = preload("res://scenes/ui/components/wuxia_menu_button/WuxiaMenuButton.tscn")
const UIBackground = preload("res://scenes/ui/components/ui_background/UIBackground.gd")

## 版本显示（18图 RH-1：真源=ProjectSettings application/config/version；Build 日期由
## build_release.py 写入 provenance.json 注入，禁手写日期；无 provenance=开发态显示 dev）
static func _version_text() -> String:
	var v: String = str(ProjectSettings.get_setting("application/config/version", "0.5.0"))
	var prov: Dictionary = _load_provenance()
	if prov.is_empty():
		return "v%s dev" % v
	var bid: String = str(prov.get("build_id", ""))
	var build_date: String = bid.substr(1, 8) if bid.begins_with("b") and bid.length() >= 9 else "dev"
	return "v%s Build %s" % [v, build_date]

static func _load_provenance() -> Dictionary:
	for p in [OS.get_executable_path().get_base_dir() + "/provenance.json", "res://provenance.json"]:
		if FileAccess.file_exists(p):
			var f: FileAccess = FileAccess.open(p, FileAccess.READ)
			if f != null:
				var parsed: Variant = JSON.parse_string(f.get_as_text())
				if parsed is Dictionary:
					return parsed
	return {}
const MENU_ITEMS := [
	{"key": "new_game", "text": "menu_new_game", "sub": "NEW GAME", "icon_idx": 0, "shortcut": "N"},
	{"key": "continue", "text": "menu_continue", "sub": "CONTINUE", "icon_idx": 1, "shortcut": "C"},
	{"key": "settings", "text": "menu_settings", "sub": "SETTINGS", "icon_idx": 2, "shortcut": "O"},
	{"key": "extra", "text": "menu_archive", "sub": "EXTRA", "icon_idx": 3, "shortcut": "G"},
	{"key": "quit", "text": "menu_quit", "sub": "QUIT", "icon_idx": 4, "shortcut": "Q"},
]

# 主菜单背景图（数据驱动：把图放到该路径即生效，缺失则回退到程序化水墨背景）
const BG_IMAGE_PATH := "res://assets/ui/main_menu_bg.png"
# 主菜单资源映射（可被工作室工具的「主菜单资源替换」覆盖）
const MAIN_MENU_ASSETS_PATH := "res://data/configs/ui/main_menu_assets.json"
# 标题、按钮 hover 墨迹底板、5 个图标路径（作为缺省回退）
const DEFAULT_TITLE_LOGO_PATH := "res://assets/ui/main_menu/title_logo.png"
const DEFAULT_BTN_HOVER_BG_PATH := "res://assets/ui/main_menu/btn_hover_bg.png"
const DEFAULT_ICON_PATHS := [
	"res://assets/ui/main_menu/icon_1.png",
	"res://assets/ui/main_menu/icon_2.png",
	"res://assets/ui/main_menu/icon_3.png",
	"res://assets/ui/main_menu/icon_4.png",
	"res://assets/ui/main_menu/icon_5.png",
]
var TITLE_LOGO_PATH: String = DEFAULT_TITLE_LOGO_PATH
var BTN_HOVER_BG_PATH: String = DEFAULT_BTN_HOVER_BG_PATH
var ICON_PATHS: Array = DEFAULT_ICON_PATHS.duplicate()
# 5 个菜单按钮的显示缩放（1.0=100%，来自 main_menu_assets.json 的 icon_scales，工作室「菜单按钮显示尺寸」可调）
var _icon_scales: Array = [1.0, 1.0, 1.0, 1.0, 1.0]
# 悬停浮动位移（像素，来自 main_menu_assets.json 的 hover_shift_x / hover_shift_y，工作室「悬停浮动」可调）
var _hover_shift_x: float = 5.0
var _hover_shift_y: float = 3.0
# 背景图上的压暗层透明度（保证标题/菜单文字可读）
const BG_IMAGE_SCRIM := 0.55

# 登录界面背景音乐
const LOGIN_BGM := "res://resources/audio/bgm/login_bgm.mp3"

@onready var _title_group: Control = $TitleGroup
@onready var _title_logo: TextureRect = $TitleGroup/title_logo
@onready var _menu_container: VBoxContainer = $MenuContainer
@onready var _bottom_left: Label = $BottomLeft
@onready var _bottom_right: HBoxContainer = $BottomRight
@onready var _settings_btn: Button = $BottomRight/SettingsBtn
@onready var _vol_btn: Button = $BottomRight/VolBtn
@onready var _lang_btn: Button = $BottomRight/LangBtn

var _menu_items: Array = []
var _has_save: bool = false
var _last_music_vol: float = 0.6

func _init() -> void:
	keyboard_nav_enabled = true

# === 加载主菜单资源映射配置（可被工作室工具替换） ===
func _load_assets_config() -> void:
	if not ResourceLoader.exists(MAIN_MENU_ASSETS_PATH):
		return
	var cfg: Variant = load(MAIN_MENU_ASSETS_PATH)
	if cfg == null or not (cfg is JSON):
		return
	var data: Dictionary = cfg.data as Dictionary
	if typeof(data) != TYPE_DICTIONARY:
		return
	TITLE_LOGO_PATH = _as_path(data.get("title_logo", DEFAULT_TITLE_LOGO_PATH), DEFAULT_TITLE_LOGO_PATH)
	BTN_HOVER_BG_PATH = _as_path(data.get("btn_hover_bg", DEFAULT_BTN_HOVER_BG_PATH), DEFAULT_BTN_HOVER_BG_PATH)
	var icons: Variant = data.get("icons", DEFAULT_ICON_PATHS)
	if icons is Array:
		ICON_PATHS = icons
	else:
		ICON_PATHS = DEFAULT_ICON_PATHS.duplicate()
	var scales: Variant = data.get("icon_scales", null)
	if scales is Array:
		var tmp: Array = []
		for i in 5:
			var v: float = 1.0
			if i < scales.size() and scales[i] != null:
				v = float(scales[i])
			tmp.append(clampf(v, 0.4, 1.6))
		_icon_scales = tmp

	# 悬停浮动位移（工作室「悬停浮动」设置；负 X=左移，Y=上浮像素）
	var hx: Variant = data.get("hover_shift_x", 5.0)
	if (hx is float or hx is int) and hx != null:
		_hover_shift_x = clampf(float(hx), -15.0, 15.0)
	var hy: Variant = data.get("hover_shift_y", 3.0)
	if (hy is float or hy is int) and hy != null:
		_hover_shift_y = clampf(float(hy), 0.0, 15.0)


func _as_path(v: Variant, fallback: String) -> String:
	if v == null:
		return fallback
	var s: String = str(v)
	if s.strip_edges().is_empty():
		return fallback
	return s


# === 构建内容（基类 _ready 调用：铺满 + 安全区已就绪） ===
func _build_content() -> void:
	_load_assets_config()
	_build_background()
	_build_title()
	_build_menu()
	_build_bottom_bar()
	_nav_items = _menu_items
	_check_saves()
	if ResourceLoader.exists(LOGIN_BGM):
		AudioManager.play_bgm(LOGIN_BGM)
	else:
		GameLogger.warn("MainMenu", "登录 BGM 缺失: %s" % LOGIN_BGM)

	# 开场动画（仅运行时，编辑器预览不播放，避免污染布局）
	_play_enter_animation()


# === 开场动画：菜单整列从左滑入，按钮依次淡入（递进出场） ===
func _play_enter_animation() -> void:
	if Engine.is_editor_hint() or _menu_container == null:
		return
	if _menu_items.is_empty():
		return

	# 1) 整列容器从左侧滑入 + 整体淡入
	var base_x: float = _menu_container.position.x
	_menu_container.position.x = base_x - 70.0
	_menu_container.modulate.a = 0.0
	var slide := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	slide.tween_property(_menu_container, "position:x", base_x, 0.5)
	slide.parallel().tween_property(_menu_container, "modulate:a", 1.0, 0.5)

	# 2) 每个按钮错峰淡入（不被 VBox 容器布局干扰，仅动 alpha）
	for i in _menu_items.size():
		var item: Control = _menu_items[i] as Control
		if item == null:
			continue
		item.modulate.a = 0.0
		var tw := create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(item, "modulate:a", 1.0, 0.35).set_delay(0.18 + i * 0.09)

	# 兜底保险：入场 tween 若因任何异常未跑完，1.2s 后强制全部可见，
	# 避免「菜单永久停留在 alpha=0 的不可见状态」这类灾难级故障。
	var guard := get_tree().create_timer(1.2)
	guard.timeout.connect(func() -> void:
		_menu_container.modulate.a = 1.0
		for it in _menu_items:
			if it is Control:
				(it as Control).modulate.a = 1.0
	)

# === 标题组 ===
func _build_title() -> void:
	add_content(_title_group)
	_title_logo.texture = _load_texture(TITLE_LOGO_PATH)
	_title_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	# 强制按控件 rect 区域缩放，而不是按纹理原始尺寸显示（否则大 PNG 会铺满屏幕）
	# TextureRect.ExpandMode 枚举：KEEP_SIZE=0, IGNORE_SIZE=1, EXPAND=2
	_title_logo.expand_mode = 2
	_title_logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER


func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return ResourceLoader.load(path, "Texture2D") as Texture2D
	return null


# === 背景 ===
func _build_background() -> void:
	var vw: float = maxf(get_viewport_rect().size.x, 1280.0)
	var vh: float = maxf(get_viewport_rect().size.y, 720.0)
	var holder: Control = Control.new()
	holder.name = "BGHolder"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	move_child(holder, 0)
	if ResourceLoader.exists(BG_IMAGE_PATH):
		_add_image_background(holder, vw, vh)
	else:
		_add_procedural_background(holder, vw, vh)


func _add_image_background(parent: Control, _vw: float, _vh: float) -> void:
	var bg: UIBackground = UIBackground.new()
	bg.bg_image_path = BG_IMAGE_PATH
	bg.scrim_alpha = BG_IMAGE_SCRIM
	bg.leaves_enabled = true
	bg.layout_config_path = "res://data/configs/ui/login_bg_layout.json"
	parent.add_child(bg)


func _add_procedural_background(parent: Control, vw: float, vh: float) -> void:
	# Phase2 放权：特效参数来自 data/configs/ui/skin/main_menu.vfx.json（UIVFX 装载，缺文件回退默认，视觉不变）。
	var vfx := UIVFX.load_vfx("main_menu")
	var bg: ColorRect = ColorRect.new()
	bg.color = UIPalette.BG_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bg)

	var mountains: ColorRect = ColorRect.new()
	mountains.color = UIPalette.ART_MOUNTAIN
	mountains.position = Vector2(0, 0)
	mountains.custom_minimum_size = Vector2(vw, 300)
	mountains.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(mountains)

	if vfx.get("enabled_cloud", true):
		var cloud: ColorRect = ColorRect.new()
		cloud.color = UIPalette.ART_CLOUD
		cloud.position = Vector2(-vw * 0.3, 70)
		cloud.custom_minimum_size = Vector2(vw, 150)
		cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(cloud)
		var cloud_tween := create_tween()
		cloud_tween.set_loops()
		cloud_tween.tween_property(cloud, "position:x", vw * 0.3, float(vfx.get("cloud_speed", 30.0)))

	if vfx.get("enabled_water", true):
		var water: ColorRect = ColorRect.new()
		water.color = UIPalette.ART_WATER
		water.position = Vector2(0, vh - 200)
		water.custom_minimum_size = Vector2(vw, 200)
		water.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(water)
		var water_tween := create_tween()
		water_tween.set_loops()
		var wa_min: float = vfx.get("water_min_alpha", 0.6)
		var wa_max: float = vfx.get("water_max_alpha", 1.0)
		var wp: float = vfx.get("water_period", 2.5)
		water_tween.tween_property(water, "modulate:a", wa_min, wp)
		water_tween.tween_property(water, "modulate:a", wa_max, wp)

	if vfx.get("enabled_boat", true):
		var boat: ColorRect = ColorRect.new()
		boat.color = UIPalette.GOLD_DARK
		boat.position = Vector2(120, vh - 180)
		boat.custom_minimum_size = Vector2(40, 14)
		boat.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(boat)
		var boat_tween := create_tween()
		boat_tween.set_loops()
		boat_tween.tween_property(boat, "position:x", vw - 160, float(vfx.get("boat_speed", 20.0)))

	if vfx.get("enabled_leaves", true):
		parent.add_child(_build_leaves(vw, vh, vfx))


func _build_leaves(vw: float, _vh: float, vfx: Dictionary) -> CPUParticles2D:
	# Phase2 放权：飘叶粒子参数来自 main_menu.vfx.json（UIVFX 装载，缺省回退原写死值）。
	var leaves := CPUParticles2D.new()
	leaves.emitting = true
	leaves.amount = int(vfx.get("leaves_amount", 24))
	leaves.lifetime = float(vfx.get("leaves_lifetime", 9.0))
	leaves.gravity = Vector2(0, float(vfx.get("leaves_gravity_y", 26.0)))
	leaves.initial_velocity_min = float(vfx.get("leaves_vel_min", 18.0))
	leaves.initial_velocity_max = float(vfx.get("leaves_vel_max", 55.0))
	leaves.direction = Vector2(0.15, 1.0)
	leaves.spread = 18.0
	leaves.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	leaves.emission_rect_extents = Vector2(vw / 2.0, 24.0)
	leaves.position = Vector2(vw / 2.0, -24.0)
	var ls: float = float(vfx.get("leaves_scale", 1.6))
	leaves.scale = Vector2(ls, ls)
	leaves.texture = _make_leaf_texture()
	return leaves


func _make_leaf_texture() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(UIPalette.GOLD)
	var tex := ImageTexture.create_from_image(img)
	return tex


# === 菜单 ===
func _build_menu() -> void:
	var container: VBoxContainer = _menu_container
	add_content(container)
	var hover_bg: Texture2D = _load_texture(BTN_HOVER_BG_PATH)
	for i in MENU_ITEMS.size():
		var item: WuxiaMenuButton = WuxiaMenuButtonScene.instantiate()
		item.name = "MenuItem_%d" % i
		var spec: Dictionary = MENU_ITEMS[i]
		item.text_key = spec["text"]
		item.sub_text = spec["sub"]
		var icon_path: String = ICON_PATHS[spec["icon_idx"]]
		item.icon_normal = _load_texture(icon_path)
		item.bg_hover = hover_bg
		item.base_scale = _icon_scales[i] if i < _icon_scales.size() else 1.0
		item.hover_shift_x = _hover_shift_x
		item.hover_shift_y = _hover_shift_y
		item.selected.connect(_on_item_selected.bind(i))
		item.confirmed.connect(_on_confirm_selection.bind(i))
		container.add_child(item)
		_menu_items.append(item)


# === 底部栏 ===
func _build_bottom_bar() -> void:
	var bl: Label = _bottom_left
	bl.text = "%s  |  %s" % [_version_text(), tr("studio_name")]
	bl.add_theme_font_size_override("font_size", UIPalette.FS_SMALL)
	bl.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	add_content(bl)

	add_content(_bottom_right)

	_settings_btn.text = tr("btn_settings")
	_settings_btn.pressed.connect(_on_open_settings)

	_vol_btn.text = _music_vol_label()
	_vol_btn.pressed.connect(_toggle_mute)

	_lang_btn.text = tr("btn_language")
	_lang_btn.pressed.connect(_on_language_placeholder)


# === 存档可用性 ===
func _check_saves() -> void:
	_has_save = SaveManager.has_any_save()
	if _menu_items.size() > 1:
		var continue_item: WuxiaMenuButton = _menu_items[1] as WuxiaMenuButton
		continue_item.set_enabled(_has_save)
	_selected_index = 1 if _has_save else 0


# === 选中高亮 ===
func _update_selection() -> void:
	for i in _menu_items.size():
		var item: WuxiaMenuButton = _menu_items[i] as WuxiaMenuButton
		item.set_selected(i == _selected_index)


func _on_item_selected(index: int) -> void:
	_selected_index = index
	_update_selection()


func _on_confirm_selection(index: int) -> void:
	if index >= 0 and index < _menu_items.size():
		_selected_index = index
		_update_selection()
	match _selected_index:
		0: _new_game()
		1: _continue_game()
		2: _on_open_settings()
		3: _open_archive()
		4: _quit_game()


func _on_screen_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		_quit_game()
		return true
	return false


func _new_game() -> void:
	UIManager.open_screen("DifficultySelect", UIManager.Layer.FULLSCREEN)


func _continue_game() -> void:
	var slot: int = SaveManager.get_latest_save_slot()
	if slot < 0:
		GameLogger.warn("MainMenu", "无可用存档")
		return
	AudioManager.stop_bgm()
	UIManager.close_all_screens()
	GameManager.load_game(slot)


func _on_open_settings() -> void:
	UIManager.show_popup("SettingsScreen")


func _open_archive() -> void:
	print("[MainMenu] 江湖图鉴/额外内容（待实现）")


func _quit_game() -> void:
	var dlg: Control = UIManager.show_popup("ConfirmDialog")
	if dlg == null:
		return
	dlg.setup(tr("menu_quit"), "确定要离开江湖吗？", func(): get_tree().quit())


func _toggle_mute() -> void:
	var cur: float = SettingsManager.get_audio_volume("music")
	if cur > 0.001:
		_last_music_vol = cur
		_set_music(0.0)
		_vol_btn.text = "静音"
	else:
		_set_music(_last_music_vol)
		_vol_btn.text = "有声"


func _set_music(v: float) -> void:
	SettingsManager.set_audio_volume("music", v)


func _music_vol_label() -> String:
	return "有声" if SettingsManager.get_audio_volume("music") > 0.001 else "静音"


func _on_language_placeholder() -> void:
	print("[MainMenu] 语言（本地化待 M6 实现）")


# === 编辑器预览 ===
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_load_assets_config()
	var tg: Control = get_node_or_null("TitleGroup")
	if tg != null:
		_title_group = tg
		_title_logo = tg.get_node_or_null("title_logo")
		_title_logo.texture = _load_texture(TITLE_LOGO_PATH)
	var container: VBoxContainer = get_node_or_null("MenuContainer")
	if container == null:
		return
	var hover_bg: Texture2D = _load_texture(BTN_HOVER_BG_PATH)
	for i in MENU_ITEMS.size():
		var item: Control = WuxiaMenuButtonScene.instantiate()
		item.name = "MenuItem_%d" % i
		var spec: Dictionary = MENU_ITEMS[i]
		item.text_key = spec["text"]
		item.sub_text = spec["sub"]
		item.icon_normal = _load_texture(ICON_PATHS[spec["icon_idx"]])
		item.bg_hover = hover_bg
		container.add_child(item)
		item.owner = null
	var bl: Label = get_node_or_null("BottomLeft")
	if bl != null:
		bl.text = "%s  |  %s" % [_version_text(), tr("studio_name")]
	var sb: Button = get_node_or_null("BottomRight/SettingsBtn")
	if sb != null:
		sb.text = tr("btn_settings")
	var vb: Button = get_node_or_null("BottomRight/VolBtn")
	if vb != null:
		vb.text = "有声"
	var lb: Button = get_node_or_null("BottomRight/LangBtn")
	if lb != null:
		lb.text = tr("btn_language")
