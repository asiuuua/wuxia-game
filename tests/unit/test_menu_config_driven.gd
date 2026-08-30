# tests/unit/test_menu_config_driven.gd
# 验证「菜单数据驱动 + UI 只 emit / UIManager 路由」解耦：
# 1) menu_config.json 被加载、action_id 可解析到 screen/badge；
# 2) GameMenuScreen 读配置生成按钮，且每个按钮 pressed 只 emit 对应 action_id（不写死跳转）；
# 3) UIManager 订阅 ui_action_requested 后，能据配置把 open_bond 路由到 BondRomance 屏。

extends TestBase

const GameMenuScreen = preload("res://scenes/ui/screens/game_menu/GameMenuScreen.tscn")

# 递归收集菜单里所有 Button（排除"返回"关闭按钮，避免触发 close_screen）
func _collect_menu_buttons(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		if c is Button and c.text != "返回":
			out.append(c)
		out.append_array(_collect_menu_buttons(c))
	return out

func test_menu_config_loaded() -> void:
	var cfg: Dictionary = ConfigManager.get_menu_config()
	expect(cfg.has("categories"), "menu_config 应含 categories")

	var bond: Dictionary = ConfigManager.get_menu_item("open_bond")
	expect(not bond.is_empty(), "open_bond 应可解析")
	expect(String(bond.get("screen", "")) == "BondRomance", "open_bond 指向 BondRomance")
	expect(bool(bond.get("badge", false)) == true, "open_bond 带红点 badge")

	var settings: Dictionary = ConfigManager.get_menu_item("open_settings")
	expect(String(settings.get("screen", "")) == "SettingsScreen", "open_settings 指向 SettingsScreen")

	expect(ConfigManager.get_menu_item("__not_exist__").is_empty(), "未知 action_id 返回空 Dictionary")

func test_game_menu_emits_action_ids() -> void:
	# 临时断开 UIManager 真实路由，只验证「按钮 emit 正确 action_id」，避免测试里真开 12 个屏
	if EventBus.ui_action_requested.is_connected(UIManager._on_ui_action_requested):
		EventBus.ui_action_requested.disconnect(UIManager._on_ui_action_requested)
	var captured: Array = []
	var cb := func(id: String): captured.append(id)
	EventBus.ui_action_requested.connect(cb)

	var s: Control = GameMenuScreen.instantiate()
	s._ready()
	var btns: Array = _collect_menu_buttons(s)
	expect(btns.size() == 12, "应生成 12 个菜单按钮，实际 %d" % btns.size())
	for b in btns:
		b.emit_signal("pressed")

	EventBus.ui_action_requested.disconnect(cb)
	EventBus.ui_action_requested.connect(UIManager._on_ui_action_requested)

	expect(captured.has("open_bond"), "姻缘按钮应 emit open_bond")
	expect(captured.has("open_settings"), "设置按钮应 emit open_settings")
	expect(captured.has("open_forge"), "锻造按钮应 emit open_forge")
	expect(captured.size() == 12, "应 emit 12 个 action_id，实际 %d" % captured.size())
	s.free()

func test_ui_routes_menu_action_to_screen() -> void:
	EventBus.ui_action_requested.emit("open_bond")
	expect(UIManager.get_open_screen("BondRomance") != null, "路由应打开 BondRomance 屏")
	UIManager.close_all_screens()
