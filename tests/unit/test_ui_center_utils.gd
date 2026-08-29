# tests/unit/test_ui_center_utils.gd
# 验证 UICenterUtils.center_panel 真正把面板居中（锚 0.5 + 对称 offset），
# 杜绝 Godot4.7.2 PRESET_CENTER 把 offset 清零导致「左边缘落在父中心」的坑。
# 各弹出面板（菜单/姻缘/背包/设置/读档/地图/属性/技艺/确认框）均改调本函数，
# 此测试防护其居中逻辑不被回退。

extends TestBase

func test_center_panel_centers_within_parent() -> void:
	var parent := Control.new()
	parent.size = Vector2(1920, 1080)
	var panel := Panel.new()
	panel.size = Vector2(600, 400)
	parent.add_child(panel)
	UICenterUtils.center_panel(panel)
	# 锚全 0.5 + 对称 offset（数学上保证父中心对齐，无需入树即可验证）
	expect(is_equal_approx(panel.anchor_left, 0.5), "anchor_left 应为 0.5")
	expect(is_equal_approx(panel.anchor_right, 0.5), "anchor_right 应为 0.5")
	expect(is_equal_approx(panel.anchor_top, 0.5), "anchor_top 应为 0.5")
	expect(is_equal_approx(panel.anchor_bottom, 0.5), "anchor_bottom 应为 0.5")
	expect(is_equal_approx(panel.offset_left, -300.0), "offset_left 应为 -size.x/2 = -300，实际 %f" % panel.offset_left)
	expect(is_equal_approx(panel.offset_right, 300.0), "offset_right 应为 size.x/2 = 300，实际 %f" % panel.offset_right)
	expect(is_equal_approx(panel.offset_top, -200.0), "offset_top 应为 -size.y/2 = -200，实际 %f" % panel.offset_top)
	expect(is_equal_approx(panel.offset_bottom, 200.0), "offset_bottom 应为 size.y/2 = 200，实际 %f" % panel.offset_bottom)
	parent.free()

func test_center_panel_null_safe() -> void:
	# 空引用不应崩溃
	UICenterUtils.center_panel(null)
	expect(true, "center_panel(null) 不崩溃")

func test_center_panel_uses_current_size() -> void:
	# 必须在设置 size 后调用；用 smaller size 验证读取的是传入 size 而非默认
	var panel := Panel.new()
	panel.size = Vector2(200, 100)
	UICenterUtils.center_panel(panel)
	expect(is_equal_approx(panel.offset_left, -100.0), "offset_left 应基于当前 size.x=200 → -100，实际 %f" % panel.offset_left)
	expect(is_equal_approx(panel.offset_top, -50.0), "offset_top 应基于当前 size.y=100 → -50，实际 %f" % panel.offset_top)
	panel.free()
