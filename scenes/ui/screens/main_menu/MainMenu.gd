# scenes/ui/screens/main_menu/MainMenu.gd
# 主菜单界面（B 路线：静态容器 MenuContainer / BottomLeft / BottomRight 已迁入 MainMenu.tscn，美术可在编辑器改布局；动态内容 MenuItem / 底部按钮仍由代码构建）
# M2 范围：6 选项 + 键盘/鼠标导航 + 快捷键 + 动态背景占位 + 主题常量
# UI 只做展示与输入，业务逻辑调用 GameManager / SaveManager
# 文案经 tr() 本地化（M6）：键在 data/configs/localization/strings.csv
# 2026-08-29 迁移到 BaseScreen：铺满/安全区/键盘导航/返回 由基类统一处理，本文件只留业务与外观

@warning_ignore("shadowed_global_identifier")

extends BaseScreen

const MenuItem = preload("res://scenes/ui/components/menu_item/MenuItem.gd")
const MenuItemScene = preload("res://scenes/ui/components/menu_item/MenuItem.tscn")
const UIBackground = preload("res://scenes/ui/components/ui_background/UIBackground.gd")

const VERSION_TEXT := "v0.5.0 Build 20250827"
const MENU_ITEMS := [
	{"key": "new_game", "text": "menu_new_game", "shortcut": "N"},
	{"key": "continue", "text": "menu_continue", "shortcut": "C"},
	{"key": "load", "text": "menu_load", "shortcut": "L"},
	{"key": "settings", "text": "menu_settings", "shortcut": "O"},
	{"key": "archive", "text": "menu_archive", "shortcut": "G"},
	{"key": "quit", "text": "menu_quit", "shortcut": "Q"},
]

# 主菜单背景图（数据驱动：把图放到该路径即生效，缺失则回退到程序化水墨背景）
# 换背景：把图命名为 main_menu_bg.png（或改下面的路径）放进 assets/ui/ 即可。
const BG_IMAGE_PATH := "res://assets/ui/main_menu_bg.png"
# 各主菜单按钮背景图映射（工作室工具「登录界面」页写入：assets/ui/main_menu_btn/<menu_*>键.png）
# 缺文件/缺键则对应按钮不显示背景（向后兼容）。
const BTN_BG_MAP_PATH := "res://data/configs/ui/login_button_bg.json"
# 背景图上的压暗层透明度（保证标题/菜单文字可读：0=不压暗，1=全黑）
# 这张竹林图比较亮，调到 0.55 让金色字更清楚；想更亮就调小、更暗就调大。
const BG_IMAGE_SCRIM := 0.55

# 登录界面背景音乐（数据驱动：把 MP3 放到该路径即生效，缺失则静默不播）
const LOGIN_BGM := "res://resources/audio/bgm/login_bgm.mp3"

# B 路线（2026-08-29）：静态容器已迁入 MainMenu.tscn（美术可在编辑器改锚点/间距/位置），脚本只引用 + 填动态内容
# B 路线（2026-08-30）：底部栏三个按钮（设置/音量/语言）布局与轻样式一并迁入 .tscn，脚本只连线与设文案
@onready var _menu_container: VBoxContainer = $MenuContainer
@onready var _bottom_left: Label = $BottomLeft
@onready var _bottom_right: HBoxContainer = $BottomRight
@onready var _settings_btn: Button = $BottomRight/SettingsBtn
@onready var _vol_btn: Button = $BottomRight/VolBtn
@onready var _lang_btn: Button = $BottomRight/LangBtn

var _menu_items: Array = []   # MenuItem 实例（untyped，避免 --script 下 class_name 未注册的类型推断问题）
var _has_save: bool = false
var _last_music_vol: float = 0.6   # 静音前记录的 music 音量，恢复时使用

func _init() -> void:
	keyboard_nav_enabled = true   # 上下键在 6 项主菜单间导航（基类统一处理）

# === 构建内容（基类 _ready 调用：铺满 + 安全区已就绪，本函数只堆内容） ===
func _build_content() -> void:
	_build_background()
	_build_menu()
	_build_bottom_bar()
	_nav_items = _menu_items      # 填进基类导航列表，上下键由基类统一转发
	_check_saves()
	# 登录界面背景音乐（进入游戏时由 UIManager 统一转场关闭）
	if ResourceLoader.exists(LOGIN_BGM):
		AudioManager.play_bgm(LOGIN_BGM)
	else:
		GameLogger.warn("MainMenu", "登录 BGM 缺失: %s" % LOGIN_BGM)

# === 背景（数据驱动：有图片用图片，无图片回退到程序化水墨占位） ===
# 背景是「全屏铺底」，必须加在 self 上并压到最底层（ContentRoot 之下），
# 否则会盖住菜单；且全屏铺底能填满刘海/挖孔区域，不留黑边。
func _build_background() -> void:
	var vw: float = maxf(get_viewport_rect().size.x, 1280.0)
	var vh: float = maxf(get_viewport_rect().size.y, 720.0)
	var holder: Control = Control.new()
	holder.name = "BGHolder"
	holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	move_child(holder, 0)   # 压到最底，内容层(ContentRoot)在其上
	if ResourceLoader.exists(BG_IMAGE_PATH):
		_add_image_background(holder, vw, vh)
	else:
		_add_procedural_background(holder, vw, vh)

# 图片背景：统一走 UIBackground 组件
# 内部层次：渐变垫底 → 背景图（STRETCH_KEEP_ASPECT 等比不裁切）→ 压暗层 → 落叶粒子
# 渐变垫底解决等比缩放露黑边——空隙处露出的是与图片边缘同色系的渐变，而非项目清屏色
func _add_image_background(parent: Control, _vw: float, _vh: float) -> void:
	var bg: UIBackground = UIBackground.new()
	bg.bg_image_path = BG_IMAGE_PATH
	bg.scrim_alpha = BG_IMAGE_SCRIM
	bg.leaves_enabled = true
	bg.layout_config_path = "res://data/configs/ui/login_bg_layout.json"
	parent.add_child(bg)

# 程序化水墨占位（远山/云雾/水面/孤舟/落叶）；真实素材后同名覆盖
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

# 落叶粒子（图片背景与程序化背景共用）
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

# === 菜单（无顶部标题，菜单纵向居中） ===
# 内容放 add_content()（ContentRoot，已套安全区），自动避开刘海/挖孔
func _build_menu() -> void:
	# B 路线：菜单容器 MenuContainer 已迁入 MainMenu.tscn（美术可在编辑器调锚点/间距），此处仅引用并填动态 MenuItem
	var container: VBoxContainer = _menu_container
	add_content(container)
	# 读取工作室工具写入的「各按钮背景图」映射（menu_* 键 -> res:// 图路径），缺则空
	var btn_bg_map: Dictionary = _load_btn_bg_map()
	for i in MENU_ITEMS.size():
		var item: MenuItem = MenuItemScene.instantiate()
		item.name = "MenuItem_%d" % i
		item.set_text(tr(MENU_ITEMS[i]["text"]))
		item.set_icon("menu/" + MENU_ITEMS[i]["key"])
		var text_key: String = MENU_ITEMS[i]["text"]
		if btn_bg_map.has(text_key):
			item.set_background(btn_bg_map[text_key])
		item.selected.connect(_on_item_selected.bind(i))
		item.confirmed.connect(_on_confirm_selection.bind(i))
		container.add_child(item)
		_menu_items.append(item)

# 读取 data/configs/ui/login_button_bg.json 的 map 字段（工作室工具「登录界面」页写入）。
# 返回 { "menu_new_game": "res://...png", ... }；文件/字段缺失则返回空字典（不显示按钮背景，向后兼容）。
func _load_btn_bg_map() -> Dictionary:
	if not FileAccess.file_exists(BTN_BG_MAP_PATH):
		return {}
	var f := FileAccess.open(BTN_BG_MAP_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	return parsed.get("map", {})

# === 底部栏（左：版本/制作组；右：设置/音量/语言 按钮） ===
# B 路线（2026-08-30）：按钮布局/轻样式/最小尺寸已在 MainMenu.tscn，这里只连线 + 设动态文案。
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

# === 存档可用性（决定「继续游戏」是否可点） ===
func _check_saves() -> void:
	_has_save = SaveManager.has_any_save()
	if _menu_items.size() > 1:
		var continue_item: MenuItem = _menu_items[1] as MenuItem
		continue_item.set_enabled(_has_save)
	_selected_index = 1 if _has_save else 0

# === 选中高亮（基类在导航移动后自动调用） ===
func _update_selection() -> void:
	for i in _menu_items.size():
		var item: MenuItem = _menu_items[i] as MenuItem
		item.set_selected(i == _selected_index)

# 鼠标悬停：同步选中态（键盘导航共用 _selected_index）
func _on_item_selected(index: int) -> void:
	_selected_index = index
	_update_selection()

# === 确认：ui_accept 由基类转发到这里，鼠标点击也走这里 ===
func _on_confirm_selection(index: int) -> void:
	if index >= 0 and index < _menu_items.size():
		_selected_index = index
		_update_selection()
	match _selected_index:
		0: _new_game()
		1: _continue_game()
		2: _open_load()
		3: _on_open_settings()
		4: _open_archive()
		5: _quit_game()

# ESC 在主菜单 = 退出游戏（弹确认框）；基类输入流先过这里，消费后不再继续
func _on_screen_input(event: InputEvent) -> bool:
	if event.is_action_pressed("ui_cancel"):
		_quit_game()
		return true
	return false

# === 各选项行为 ===
func _new_game() -> void:
	# 新游戏前先选难度：打开难度选择界面，选定后再进入游戏
	UIManager.open_screen("DifficultySelect", UIManager.Layer.FULLSCREEN)

func _continue_game() -> void:
	var slot: int = SaveManager.get_latest_save_slot()
	if slot < 0:
		GameLogger.warn("MainMenu", "无可用存档")
		return
	var target_slot: int = slot
	AudioManager.stop_bgm()
	# 委托 UIManager 统一淡出转场，淡出完成后再读档进入
	UIManager.close_screen(self, func(): GameManager.load_game(target_slot))

func _open_load() -> void:
	UIManager.open_screen("SaveLoadScreen", UIManager.Layer.FULLSCREEN)

func _on_open_settings() -> void:
	# 设置为独立弹窗：叠在底层界面之上（POPUP 层），关闭后回到原界面
	UIManager.show_popup("SettingsScreen")

func _open_archive() -> void:
	# TODO 后续里程碑：江湖图鉴
	print("[MainMenu] 江湖图鉴（待实现）")

func _quit_game() -> void:
	var dlg: Control = UIManager.show_popup("ConfirmDialog")
	if dlg == null:
		return
	dlg.setup(tr("menu_quit"), "确定要离开江湖吗？", func(): get_tree().quit())

# 静音/恢复切换：复用 SettingsManager.audio.music，控制 "Music" 总线 → 作用于登录 BGM
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

# === 编辑器预览（UIPreview 调用）：只填常量/配置，不碰 GameManager/存档 ===
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var container: VBoxContainer = get_node_or_null("MenuContainer")
	if container == null:
		return
	for i in MENU_ITEMS.size():
		var item: Control = MenuItemScene.instantiate()
		item.name = "MenuItem_%d" % i
		item.set_text(tr(MENU_ITEMS[i]["text"]))
		item.set_icon("menu/" + MENU_ITEMS[i]["key"])
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
