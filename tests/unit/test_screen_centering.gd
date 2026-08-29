# tests/unit/test_screen_centering.gd
# 验证姻缘面板(BondRomance) 与 游戏主菜单(GameMenu) 的玻璃面板真正居中于屏幕中央。
# 回归防护：此前用 set_anchors_and_offsets_preset(PRESET_CENTER) 后设 panel.size，
# 而 PRESET_CENTER 用节点「当时 size=0」算 offset，随后设 size 会把面板顶偏（不居中）。
# 正确顺序是先给 size 再 PRESET_CENTER。

extends TestBase

const BondRomanceScreen = preload("res://scenes/ui/screens/bond_romance/BondRomanceScreen.gd")
const GameMenuScreen = preload("res://scenes/ui/screens/game_menu/GameMenuScreen.gd")

# 从屏幕节点里找出主玻璃面板（第一个 Panel 子节点）
func _find_panel(screen: Control) -> Panel:
	for c in screen.get_children():
		if c is Panel:
			return c as Panel
	return null

# 断言面板 anchor 全 0.5 且 offset 对称（中心对齐父节点中心）
func _assert_centered(panel: Panel, ctx: String) -> void:
	expect(is_equal_approx(panel.anchor_left, 0.5), "%s panel anchor_left 应为 0.5" % ctx)
	expect(is_equal_approx(panel.anchor_right, 0.5), "%s panel anchor_right 应为 0.5" % ctx)
	expect(is_equal_approx(panel.anchor_top, 0.5), "%s panel anchor_top 应为 0.5" % ctx)
	expect(is_equal_approx(panel.anchor_bottom, 0.5), "%s panel anchor_bottom 应为 0.5" % ctx)
	expect(is_equal_approx(panel.offset_left, -panel.size.x * 0.5),
		"%s panel offset_left 应 =-size.x/2（对称居中），实际 %f" % [ctx, panel.offset_left])
	expect(is_equal_approx(panel.offset_right, panel.size.x * 0.5),
		"%s panel offset_right 应 =size.x/2（对称居中），实际 %f" % [ctx, panel.offset_right])
	expect(is_equal_approx(panel.offset_top, -panel.size.y * 0.5),
		"%s panel offset_top 应 =-size.y/2（对称居中），实际 %f" % [ctx, panel.offset_top])
	expect(is_equal_approx(panel.offset_bottom, panel.size.y * 0.5),
		"%s panel offset_bottom 应 =size.y/2（对称居中），实际 %f" % [ctx, panel.offset_bottom])

func test_bond_romance_screen_centered() -> void:
	var s := BondRomanceScreen.new()
	s._ready()
	var p := _find_panel(s)
	expect(p != null, "BondRomanceScreen 应含主玻璃面板 Panel")
	if p != null:
		_assert_centered(p, "姻缘面板")
	s.free()

func test_game_menu_screen_centered() -> void:
	var s := GameMenuScreen.new()
	s._ready()
	var p := _find_panel(s)
	expect(p != null, "GameMenuScreen 应含主玻璃面板 Panel")
	if p != null:
		_assert_centered(p, "游戏主菜单面板")
	s.free()
