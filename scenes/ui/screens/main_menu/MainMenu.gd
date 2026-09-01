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

const VERSION_TEXT := "v0.5.0 Build 20250827"
const MENU_ITEMS := [
	{"key": "new_game", "text": "menu_new_game", "sub": "NEW GAME", "icon_idx": 0, "shortcut": "N"},
	{"key": "continue", "text": "menu_continue", "sub": "CONTINUE", "icon_idx": 1, "shortcut": "C"},
	{"key": "settings", "text": "menu_settings", "sub": "SETTINGS", "icon_idx": 2, "shortcut": "O"},
	{"key": "extra", "text": "menu_archive", "sub": "EXTRA", "icon_idx": 3, "shortcut": "G"},
	{"key": "quit", "text": "menu_quit", "sub": "QUIT", "icon_idx": 4, "shortcut": "Q"},
]

# 主菜单背景图（数据驱动：把图放到该路径即生效，缺失则回退到程序化水墨背景）
const BG_IMAGE_PATH := "res://assets/ui/main_menu_bg.png"
# 标题、副标题、按钮 hover 墨迹底板、5 个图标路径
const TITLE_LOGO_PATH := "res://assets/ui/main_menu/title_logo.jpg"
const TITLE_SUB_PATH := "res://assets/ui/main_menu/title_sub.png"
const BTN_HOVER_BG_PATH := "res://assets/ui/main_menu/btn_hover_bg.jpg"
const ICON_PATHS := [
	"res://assets/ui/main_menu/icon_1.jpg",
	"res://assets/ui/main_menu/icon_2.png",
	"res://assets/ui/main_menu/icon_3.jpg",
	"res://assets/ui/main_menu/icon_4.jpg",
	"res://assets/ui/main_menu/icon_5.jpg",
]
# 背景图上的压暗层透明度（保证标题/菜单文字可读）
const BG_IMAGE_SCRIM := 0.55

# 登录界面背景音乐
const LOGIN_BGM := "res://resources/audio/bgm/login_bgm.mp3"

# 主菜单布局（工作室工具「登录界面 → 主菜单布局」自由拖拽写入）
const MAIN_MENU_LAYOUT_PATH := "res://data/configs/ui/main_menu_layout.json"

@onready var _title_group: VBoxContainer = $TitleGroup
@onready var _title_logo: TextureRect = $TitleGroup/title_logo
@onready var _title_sub: TextureRect = $TitleGroup/title_sub
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

# === 构建内容（基类 _ready 调用：铺满 + 安全区已就绪） ===
func _build_content() -> void:
	_apply_layout()
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

# === 主菜单布局（数据驱动） ===
func _apply_layout() -> void:
	if not FileAccess.file_exists(MAIN_MENU_LAYOUT_PATH):
		return
	var f := FileAccess.open(MAIN_MENU_LAYOUT_PATH, FileAccess.READ)
	if f == null:
		return
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY or not parsed.has("elements"):
		return
	var elements: Dictionary = parsed["elements"]

	_apply_block(_title_group, elements.get("title_group", {}))
	_apply_block(_menu_container, elements.get("menu_container", {}))
	_apply_block(_bottom_left, elements.get("bottom_left", {}))
	_apply_block(_bottom_right, elements.get("bottom_right", {}))

	if elements.has("menu_container") and typeof(elements["menu_container"]) == TYPE_DICTIONARY:
		var mc: Dictionary = elements["menu_container"]
		if mc.has("separation"):
			_menu_container.add_theme_constant_override("separation", int(mc["separation"]))


func _apply_block(node: Control, spec: Dictionary) -> void:
	if node == null or typeof(spec) != TYPE_DICTIONARY:
		return
	if spec.has("anchor_left"):
		node.anchor_left = float(spec["anchor_left"])
	if spec.has("anchor_top"):
		node.anchor_top = float(spec["anchor_top"])
	if spec.has("anchor_right"):
		node.anchor_right = float(spec["anchor_right"])
	if spec.has("anchor_bottom"):
		node.anchor_bottom = float(spec["anchor_bottom"])
	if spec.has("offset_left"):
		node.offset_left = float(spec["offset_left"])
	if spec.has("offset_top"):
		node.offset_top = float(spec["offset_top"])
	if spec.has("offset_right"):
		node.offset_right = float(spec["offset_right"])
	if spec.has("offset_bottom"):
		node.offset_bottom = float(spec["offset_bottom"])


# === 标题组 ===
func _build_title() -> void:
	add_content(_title_group)
	_title_logo.texture = _load_texture(TITLE_LOGO_PATH)
	_title_sub.texture = _load_texture(TITLE_SUB_PATH)
	_title_logo.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_title_sub.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	if _title_logo.texture != null:
		_title_logo.custom_minimum_size = _title_logo.texture.get_size() * 0.45
	if _title_sub.texture != null:
		_title_sub.custom_minimum_size = _title_sub.texture.get_size() * 0.45


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

	var cloud: ColorRect = ColorRect.new()
	cloud.color = UIPalette.ART_CLOUD
	cloud.position = Vector2(-vw * 0.3, 70)
	cloud.custom_minimum_size = Vector2(vw, 150)
	cloud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cloud)
	var cloud_tween := create_tween()
	cloud_tween.set_loops()
	cloud_tween.tween_property(cloud, "position:x", vw * 0.3, 30.0)

	var water: ColorRect = ColorRect.new()
	water.color = UIPalette.ART_WATER
	water.position = Vector2(0, vh - 200)
	water.custom_minimum_size = Vector2(vw, 200)
	water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(water)
	var water_tween := create_tween()
	water_tween.set_loops()
	water_tween.tween_property(water, "modulate:a", 0.6, 2.5)
	water_tween.tween_property(water, "modulate:a", 1.0, 2.5)

	var boat: ColorRect = ColorRect.new()
	boat.color = UIPalette.GOLD_DARK
	boat.position = Vector2(120, vh - 180)
	boat.custom_minimum_size = Vector2(40, 14)
	boat.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(boat)
	var boat_tween := create_tween()
	boat_tween.set_loops()
	boat_tween.tween_property(boat, "position:x", vw - 160, 20.0)

	parent.add_child(_build_leaves(vw, vh))


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
		item.selected.connect(_on_item_selected.bind(i))
		item.confirmed.connect(_on_confirm_selection.bind(i))
		container.add_child(item)
		_menu_items.append(item)


# === 底部栏 ===
func _build_bottom_bar() -> void:
	var bl: Label = _bottom_left
	bl.text = "%s  |  %s" % [VERSION_TEXT, tr("studio_name")]
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
	var tg: VBoxContainer = get_node_or_null("TitleGroup")
	if tg != null:
		_title_group = tg
		_title_logo = tg.get_node_or_null("title_logo")
		_title_sub = tg.get_node_or_null("title_sub")
		_title_logo.texture = _load_texture(TITLE_LOGO_PATH)
		_title_sub.texture = _load_texture(TITLE_SUB_PATH)
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
		bl.text = "%s  |  %s" % [VERSION_TEXT, tr("studio_name")]
	var sb: Button = get_node_or_null("BottomRight/SettingsBtn")
	if sb != null:
		sb.text = tr("btn_settings")
	var vb: Button = get_node_or_null("BottomRight/VolBtn")
	if vb != null:
		vb.text = "有声"
	var lb: Button = get_node_or_null("BottomRight/LangBtn")
	if lb != null:
		lb.text = tr("btn_language")
