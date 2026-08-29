# scenes/ui/screens/esc_menu/EscMenu.gd
# 游戏内 ESC 暂停菜单（POPUP 层级）；由 TownScene 监听 ui_cancel 开关
# 复用 MenuItem 组件 + UIPalette 配色，与 MainMenu 交互一致
# 文案经 tr() 本地化；键在 data/configs/localization/strings.csv
# 注意：本界面只做 UI 与输入，业务逻辑调用 GameManager / SaveManager / UIManager
# 2026-08-29 迁移到 BaseScreen：铺满/安全区/键盘导航 由基类统一处理，本文件只留业务

@warning_ignore("shadowed_global_identifier")

extends BaseScreen

const MenuItem = preload("res://scenes/ui/components/menu_item/MenuItem.gd")

const MENU_ITEMS := [
	{"key": "return_game", "text": "esc_return_game"},
	{"key": "save_game", "text": "esc_save_game"},
	{"key": "load_game", "text": "esc_load_game"},
	{"key": "unstuck", "text": "esc_unstuck"},
	{"key": "settings", "text": "esc_settings"},
	{"key": "tutorial", "text": "esc_tutorial"},
	{"key": "achievements", "text": "esc_achievements"},
	{"key": "to_title", "text": "esc_to_title"},
	{"key": "quit_game", "text": "esc_quit_game"},
]

func _init() -> void:
	keyboard_nav_enabled = true
	# ⚠️ 必须为 false：TownScene 也监听 ui_cancel 来开关本菜单。
	# 若这里再处理一次，按下 ESC 会「开了又立刻关」，菜单闪一下就没了。
	close_on_cancel = false

func _build_content() -> void:
	_add_backdrop(0.55)   # 压暗底铺满整屏（含刘海），透出底层游戏画面

	var container: VBoxContainer = VBoxContainer.new()
	container.anchor_left = 0.5
	container.anchor_top = 0.5
	container.anchor_right = 0.5
	container.anchor_bottom = 0.5
	container.offset_left = -200.0
	container.offset_top = -230.0
	container.offset_right = 200.0
	container.offset_bottom = 230.0
	container.add_theme_constant_override("separation", 8)
	add_content(container)

	for i in MENU_ITEMS.size():
		var item: MenuItem = MenuItem.new()
		item.name = "EscItem_%d" % i
		item.set_text(tr(MENU_ITEMS[i]["text"]))
		item.set_icon("menu/" + MENU_ITEMS[i]["key"])
		item.selected.connect(_on_item_selected.bind(i))
		item.confirmed.connect(_on_item_confirmed.bind(i))
		container.add_child(item)
		# 填进 _nav_items 后，键盘上下导航由基类统一处理；
		# MenuItem 的选中动画与音效由 UIFeedback 在 set_selected 内触发
		_nav_items.append(item)

# === 选中态（基类在导航移动后自动调用）===
func _update_selection() -> void:
	for i in _nav_items.size():
		var item: MenuItem = _nav_items[i] as MenuItem
		if item == null:
			continue
		item.set_selected(i == _selected_index)

func _on_item_selected(index: int) -> void:
	_selected_index = index
	_update_selection()

# === 确认：ui_accept 由基类转发到这里；走 MenuItem.confirm() 保持原有事件流 ===
func _on_confirm_selection(index: int) -> void:
	var item: MenuItem = _nav_items[index] as MenuItem
	if item != null:
		item.confirm()

func _on_item_confirmed(index: int) -> void:
	match index:
		0: _return_game()
		1: _save_game()
		2: _load_game()
		3: _unstuck()
		4: _open_settings()
		5: _open_tutorial()
		6: _open_achievements()
		7: _to_title()
		8: _quit_game()

# === 各选项行为 ===
func _return_game() -> void:
	UIManager.close_screen(self)

func _save_game() -> void:
	# 自定义保存：打开存档界面「保存模式」，玩家选槽位 + 命名（不再默默 quick_save 导致无法自定义）
	_release_focus_and_close(func(): UIManager.open_screen("SaveLoadScreen", UIManager.Layer.FULLSCREEN, {"mode": "save"}))

func _load_game() -> void:
	# 打开存档界面「读取模式」
	_release_focus_and_close(func(): UIManager.open_screen("SaveLoadScreen", UIManager.Layer.FULLSCREEN, {"mode": "load"}))

## 关闭本菜单前释放焦点（双保险：MenuItem 已设 FOCUS_NONE，这里再清一次，彻底杜绝焦点悬挂吞 ESC），
## 随后执行回调（如打开存档界面），回调在淡出完成（queue_free 前）才触发
func _release_focus_and_close(on_closed: Callable) -> void:
	release_focus()
	UIManager.close_screen(self, on_closed)

func _unstuck() -> void:
	# 脱离卡死：关闭全部 UI 并重新加载当前场景（autoload 持有的玩家状态保留）
	UIManager.close_all_screens()
	get_tree().reload_current_scene()

func _open_settings() -> void:
	# 设置为独立弹窗：叠在 ESC 菜单之上（POPUP 层），关闭后回到 ESC 菜单
	UIManager.show_popup("SettingsScreen")

func _open_tutorial() -> void:
	EventBus.notification_show.emit(tr("esc_tutorial_todo"))
	UIManager.close_screen(self)

func _open_achievements() -> void:
	EventBus.notification_show.emit(tr("esc_achievements_todo"))
	UIManager.close_screen(self)

func _to_title() -> void:
	var dlg: Control = UIManager.show_popup("ConfirmDialog")
	if dlg == null:
		return
	dlg.setup(tr("esc_confirm_to_title_title"), tr("esc_confirm_to_title_content"), func():
		UIManager.close_all_screens()
		GameManager.return_to_title()
	)

func _quit_game() -> void:
	var dlg: Control = UIManager.show_popup("ConfirmDialog")
	if dlg == null:
		return
	dlg.setup(tr("esc_confirm_quit_title"), tr("esc_confirm_quit_content"), func(): get_tree().quit())
