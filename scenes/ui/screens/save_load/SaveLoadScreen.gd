# 存档选择界面（代码构建 Control，挂在 UIManager.FULLSCREEN 层级；对齐 MainMenu 惯例，不依赖 .tscn）
# 职责：展示手动存档列表 + 自动存档区；读取/删除/新游戏经 ConfirmDialog 组件确认（M5 已抽离）
# 业务逻辑调用 SaveManager（列表/删除）与 GameManager（读档/新游戏）。颜色集中引用 UIPalette
# 文案经 tr() 本地化（M6）：键在 data/configs/localization/strings.csv
# 2026-08-29 迁移到 BaseScreen：铺满/安全区/键盘导航/返回 由基类统一处理，本文件只留业务与外观

@warning_ignore("shadowed_global_identifier")

extends BaseScreen

const SaveCard = preload("res://scenes/ui/components/save_card/SaveCard.gd")
const UIBackground = preload("res://scenes/ui/components/ui_background/UIBackground.gd")

const TITLE := "save_title"
const TITLE_SAVE := "save_title_save"

# 主菜单背景图（数据驱动：有图用图叠压暗层+落叶，无图回退深墨）
const BG_IMAGE_PATH := "res://assets/ui/main_menu_bg.png"
const BG_IMAGE_SCRIM := 0.55

var _cards: Array = []           # SaveCard 实例（手动+自动，键盘可导航）
var _mode: String = "load"       # "load" 读取模式（主菜单/ESC 读取）/ "save" 保存模式（ESC 保存游戏）
var _name_dialog: Control = null # 命名弹窗（保存模式选槽位后弹出）
var _name_dialog_open: bool = false

# B 路线（2026-08-29）：静态壳（顶部栏 Header + 滚动区 Scroll 及其内 List 容器）已迁入
# SaveLoadScreen.tscn，美术可在编辑器改布局/边距；脚本只留业务与动态内容（存档卡片/命名弹窗）。
@onready var _header: HBoxContainer = $Header
@onready var _scroll: ScrollContainer = $Scroll
@onready var _list_container: VBoxContainer = $Scroll/List

## 接收打开参数（来自 EscMenu）；data = {"mode": "save" | "load"}
func _on_open(data: Variant) -> void:
	if data is Dictionary and data.has("mode"):
		_mode = data["mode"]

func _init() -> void:
	keyboard_nav_enabled = true   # 上下键在存档卡片间导航（基类统一处理）；ESC 返回由基类 close_on_cancel 负责

# === 构建内容（基类 _ready 调用：铺满 + 安全区已就绪，本函数只堆内容） ===
func _build_content() -> void:
	_build_background()
	_build_header()
	_build_list()
	_rebuild_list()

# === 背景（数据驱动：有竹林图用图叠压暗层+落叶，无图回退深墨） ===
# 背景全屏铺底，加在 self 并压到最底层（ContentRoot 之下），填满刘海/挖孔不留黑边
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
		var bg: ColorRect = ColorRect.new()
		bg.color = UIPalette.BG_DARK
		bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
		holder.add_child(bg)

# 图片背景：统一走 UIBackground 组件（与主菜单同源，视觉连贯，等比缩放不再露黑边）
func _add_image_background(parent: Control, _vw: float, _vh: float) -> void:
	var bg: UIBackground = UIBackground.new()
	bg.bg_image_path = BG_IMAGE_PATH
	bg.scrim_alpha = BG_IMAGE_SCRIM
	bg.leaves_enabled = true
	bg.layout_config_path = "res://data/configs/ui/login_bg_layout.json"
	parent.add_child(bg)

# === 顶部栏：返回 + 标题（内容放 add_content，已套安全区，避开刘海） ===
func _build_header() -> void:
	add_content(_header)

	var back_btn: Button = Button.new()
	back_btn.text = "← " + (tr("esc_save_game") if _mode == "save" else tr("menu_load"))
	back_btn.pressed.connect(_go_back)
	_apply_glass_to_button(back_btn, UIPalette.TEXT_SECONDARY)
	_header.add_child(back_btn)

	var title: Label = Label.new()
	title.text = tr(TITLE_SAVE if _mode == "save" else TITLE)
	title.add_theme_font_size_override("font_size", UIPalette.FS_HEADER)
	title.add_theme_color_override("font_color", UIPalette.GOLD)
	_header.add_child(title)

# === 列表区（滚动容器，含手动存档 + 自动存档段） ===
func _build_list() -> void:
	add_content(_scroll)
	# _list_container 已在 SaveLoadScreen.tscn 静态声明，直接复用（滚动区内 VBox）

# === 读取存档列表 + 自动存档段 ===
func _rebuild_list() -> void:
	for child in _list_container.get_children():
		child.queue_free()
	_cards.clear()
	_selected_index = 0

	var saves: Array = SaveManager.list_saves()
	for info in saves:
		_add_card(info)

	var sep: Label = Label.new()
	sep.text = tr("auto_save_section")
	sep.add_theme_font_size_override("font_size", 16)
	sep.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	_list_container.add_child(sep)

	var autos: Array = SaveManager.list_auto_saves()
	if autos.is_empty():
		var none: Label = Label.new()
		none.text = tr("no_auto_save")
		none.add_theme_color_override("font_color", UIPalette.DISABLED)
		_list_container.add_child(none)
	else:
		for info in autos:
			_add_card(info)

	_nav_items = _cards   # 同步到基类导航列表，键盘上下键由基类统一转发
	_update_selection()

func _add_card(info: Dictionary) -> void:
	var card: SaveCard = SaveCard.new()
	card.card_focused.connect(_on_card_focused)
	card.load_requested.connect(_on_load_requested)
	card.delete_requested.connect(_on_delete_requested)
	card.new_game_requested.connect(_on_new_game_requested)
	card.save_requested.connect(_on_save_requested)
	_list_container.add_child(card)   # 先入树触发 _ready 建好控件，再 setup 填充数据
	card.setup(info)
	card.set_mode(_mode)
	_cards.append(card)

# === 选择高亮（基类在导航移动后自动调用） ===
func _update_selection() -> void:
	for i in _cards.size():
		var card: SaveCard = _cards[i] as SaveCard
		card.set_highlighted(i == _selected_index)

func _on_card_focused(card: Control) -> void:
	var idx: int = _cards.find(card)
	if idx >= 0:
		_selected_index = idx
		_update_selection()

# === 确认：ui_accept 由基类转发到这里 ===
func _on_confirm_selection(_index: int) -> void:
	if _selected_index < 0 or _selected_index >= _cards.size():
		return
	var card: SaveCard = _cards[_selected_index] as SaveCard
	card.trigger_primary()

# ESC 由基类 close_on_cancel 负责返回；这里只额外处理：命名弹窗打开时屏蔽键盘、DELETE 删除选中
func _on_screen_input(event: InputEvent) -> bool:
	# 命名弹窗打开时，ESC 由弹窗层拦截（关弹窗），本界面让权屏蔽键盘
	if _name_dialog_open:
		return true
	if event is InputEventKey and event.pressed and event.keycode == KEY_DELETE:
		_delete_selected()
		return true
	return false

# === 事件：读取 / 删除 / 新游戏（均经 ConfirmDialog 确认） ===
func _on_load_requested(slot: int) -> void:
	_confirm_dialog(tr("confirm_load_title"), tr("confirm_load_content"), func(): _do_load(slot))

func _on_delete_requested(slot: int) -> void:
	_confirm_dialog(tr("confirm_delete_title"), tr("confirm_delete_content"), func(): _do_delete(slot))

func _on_new_game_requested(slot: int) -> void:
	_confirm_dialog(tr("confirm_newgame_title"), tr("confirm_newgame_content"), func(): _do_new_game())

# === 保存模式（ESC 菜单「保存游戏」进入）：选槽位 → 命名弹窗（已有存档先确认覆盖） ===
func _on_save_requested(slot: int) -> void:
	if _slot_has_save(slot):
		_confirm_dialog(tr("save_overwrite_title"), tr("save_overwrite_content"), func(): _open_name_dialog(slot))
	else:
		_open_name_dialog(slot)

func _slot_has_save(slot: int) -> bool:
	for info in SaveManager.list_saves():
		if int(info.get("slot", 0)) == slot and info.get("exists", false):
			return true
	return false

## 命名弹窗：遮罩 + 磨砂玻璃面板 + LineEdit + 确认/取消；ESC 关闭、确认写入自定义名
func _open_name_dialog(slot: int) -> void:
	if _name_dialog_open:
		return
	_name_dialog_open = true
	var dialog := Control.new()
	dialog.name = "NameDialog"
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dialog.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dialog)
	_name_dialog = dialog

	var dim := ColorRect.new()
	dim.color = UIPalette.DIM
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dialog.add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(460, 190)
	panel.custom_minimum_size = Vector2(460, 190)
	UICenterUtils.center_panel(panel)   # 修复 Godot4.7.2 PRESET_CENTER 不居中
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GLASS_BORDER
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	sb.shadow_color = UIPalette.GLASS_SHADOW
	panel.add_theme_stylebox_override("panel", sb)
	dialog.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vbox.add_theme_constant_override("separation", 14)
	vbox.add_theme_constant_override("margin_left", 24)
	vbox.add_theme_constant_override("margin_top", 20)
	vbox.add_theme_constant_override("margin_right", 24)
	vbox.add_theme_constant_override("margin_bottom", 20)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(vbox)

	var title := Label.new()
	title.text = tr("ui_save_name_title")
	title.add_theme_font_size_override("font_size", UIPalette.FS_TITLE)
	title.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var line := LineEdit.new()
	line.placeholder_text = tr("ui_save_name_placeholder")
	line.max_length = 20
	line.add_theme_color_override("font_color", UIPalette.TEXT_MAIN)
	line.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(line)

	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var ok_btn := Button.new()
	ok_btn.text = tr("ui_confirm_ok")
	btn_row.add_child(ok_btn)
	var cancel_btn := Button.new()
	cancel_btn.text = tr("ui_confirm_cancel")
	btn_row.add_child(cancel_btn)
	_apply_glass_to_button(ok_btn, UIPalette.SUCCESS)
	_apply_glass_to_button(cancel_btn, UIPalette.TEXT_SECONDARY)

	ok_btn.pressed.connect(func(): _do_save(slot, line.text))
	cancel_btn.pressed.connect(_close_name_dialog)
	line.text_submitted.connect(func(_t: String): _do_save(slot, line.text))
	# 弹窗层拦截 ESC：关闭命名框而非整个存档界面
	dialog.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventKey and ev.pressed and ev.keycode == KEY_ESCAPE:
			_close_name_dialog()
			get_viewport().set_input_as_handled()
	)
	line.grab_focus()

## 确认保存：写自定义名到槽位，关闭弹窗，刷新列表 + 提示
func _do_save(slot: int, save_name: String) -> void:
	var final_name: String = save_name.strip_edges()
	if final_name == "":
		final_name = tr("ui_save_default_name")
	SaveManager.save_to_slot(slot, final_name)
	_close_name_dialog()
	_rebuild_list()
	EventBus.notification_show.emit(tr("save_custom_success"))

func _close_name_dialog() -> void:
	if _name_dialog != null and is_instance_valid(_name_dialog):
		_name_dialog.queue_free()
	_name_dialog = null
	_name_dialog_open = false

## 给按钮套磨砂玻璃样式（独立 helper，避免与 ConfirmDialog 耦合）
func _apply_glass_to_button(btn: Button, font_color: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GLASS_BORDER
	sb.corner_radius_top_left = 8
	sb.corner_radius_top_right = 8
	sb.corner_radius_bottom_left = 8
	sb.corner_radius_bottom_right = 8
	sb.content_margin_left = 18
	sb.content_margin_right = 18
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	btn.add_theme_stylebox_override("normal", sb)
	btn.add_theme_stylebox_override("hover", sb)
	btn.add_theme_stylebox_override("pressed", sb)
	btn.add_theme_stylebox_override("focus", sb)
	btn.add_theme_color_override("font_color", font_color)
	btn.add_theme_font_size_override("font_size", UIPalette.FS_SUB)

func _do_load(slot: int) -> void:
	UIManager.close_all_screens()
	GameManager.load_game(slot)

func _do_delete(slot: int) -> void:
	if SaveManager.delete_save(slot):
		_rebuild_list()

func _do_new_game() -> void:
	UIManager.close_all_screens()
	GameManager.start_new_game()

func _go_back() -> void:
	UIManager.close_screen(self)

# === 确认弹窗（M5 起统一走 ConfirmDialog 组件） ===
func _confirm_dialog(title: String, content: String, callback: Callable) -> void:
	var dlg: Control = UIManager.show_popup("ConfirmDialog")
	if dlg == null:
		return
	dlg.setup(title, content, callback)

func _delete_selected() -> void:
	if _selected_index < 0 or _selected_index >= _cards.size():
		return
	var card: SaveCard = _cards[_selected_index] as SaveCard
	card.trigger_delete()
