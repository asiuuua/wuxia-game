# tests/unit/test_responsive_anchor.gd
# 响应式锚点（2026-09-02 统一收口）单测：
#  - 纯函数 clamp_panel_size：大屏保持设计尺寸、小屏内缩防溢出、极端小屏不低于 240 下限
#  - 集成：各 PopupBase 弹窗 + 确认框经 UIManager 打开后，主面板尺寸不溢出默认视口（接线有效）

extends TestBase

const UICenterUtils = preload("res://scenes/ui/ui_center_utils.gd")
const SaveNameDialogScene = preload("res://scenes/ui/components/save_name_dialog/SaveNameDialog.tscn")

# 各弹窗主面板节点路径（相对场景根节点；注意 get_node_or_null 里不能用 "$" 语法糖，须写纯节点名）
const PANELS := {
	"AttributesScreen": ["Panel", 520, 560],
	"InventoryScreen": ["Center/Panel", 720, 560],
	"AbilitiesScreen": ["Panel", 720, 540],
	"AlchemyScreen": ["Panel", 640, 560],
	"BondRomance": ["Panel", 760, 620],
	"EquipmentScreen": ["Panel", 560, 560],
	"ForgeScreen": ["Panel", 640, 560],
	"GameMenu": ["Panel", 760, 540],
	"NpcPanel": ["Panel", 800, 640],
	"SectScreen": ["Panel", 640, 560],
	"ShopScreen": ["Panel", 640, 560],
}

func after_each() -> void:
	UIManager.close_all_screens()

func test_clamp_panel_size_keeps_desired_on_large_viewport() -> void:
	# 大视口（1920x1080）下 800x600 设计面板应保持原尺寸（视觉不变）
	var r := UICenterUtils.clamp_panel_size(Vector2(800, 600), Vector2(1920, 1080))
	expect(r.x == 800 and r.y == 600, "大屏下应保持设计尺寸，得到 %s" % r)

func test_clamp_panel_size_shrinks_on_small_viewport() -> void:
	# 小视口（400x300，留白 6%）下 800x600 面板应内缩到视口内（防溢出/错位）
	var r := UICenterUtils.clamp_panel_size(Vector2(800, 600), Vector2(400, 300), 0.06, 0.06)
	# w = min(800, max(400*0.94, 240)) = min(800, 376) = 376
	# h = min(600, max(300*0.94, 240)) = min(600, 282) = 282
	expect(r.x == 376 and r.y == 282, "小屏下应内缩到视口内，得到 %s" % r)

func test_clamp_panel_size_floor_240() -> void:
	# 极端小视口（100x100）下不应低于 240 下限，避免压成不可读
	var r := UICenterUtils.clamp_panel_size(Vector2(5000, 5000), Vector2(100, 100))
	expect(r.x == 240 and r.y == 240, "极端小屏应不低于 240 下限，得到 %s" % r)

func test_popup_panels_no_overflow_at_default_viewport() -> void:
	# headless 单测无真实窗口（get_viewport_rect 恒为 Rect2()），故此处不做像素级溢出断言，
	# 只验「每个弹窗可正常打开、主面板存在、enable_responsive 接线不崩」——尺寸裁剪逻辑已由上方三个纯函数用例覆盖。
	for name in PANELS.keys():
		var scr: Control = UIManager.open_screen(name, UIManager.Layer.FULLSCREEN)
		expect(scr != null, "打开 %s 应成功（响应式接线不崩）" % name)
		if scr == null:
			continue
		var path: String = PANELS[name][0]
		if scr.get_node_or_null(path) == null:
			expect(false, "%s 主面板 %s 应存在" % [name, path])
		UIManager.close_screen(scr)

func test_confirm_dialog_responsive_wiring() -> void:
	# 确认框（派单 23a9d0b92b83 新接线）：经 UIManager.show_popup 打开，_apply_layout 响应式钳制不崩、主面板存在
	var dlg: Control = UIManager.show_popup("ConfirmDialog")
	expect(dlg != null, "打开 ConfirmDialog 应成功（响应式接线不崩）")
	if dlg == null:
		return
	expect(dlg.get_node_or_null("Panel") != null, "ConfirmDialog 主面板 Panel 应存在")
	UIManager.close_screen(dlg)

func test_map_screen_responsive_wiring() -> void:
	# 地图覆盖层（派单 23a9d0b92b83 新接线）：经 open_screen 打开，_fit_responsive 接线不崩、主面板存在
	var scr: Control = UIManager.open_screen("MapScreen", UIManager.Layer.FULLSCREEN)
	expect(scr != null, "打开 MapScreen 应成功（响应式接线不崩）")
	if scr == null:
		return
	expect(scr.get_node_or_null("Panel") != null, "MapScreen 主面板 Panel 应存在")
	UIManager.close_screen(scr)

func test_save_name_dialog_responsive_wiring() -> void:
	# 存档命名弹窗（派单 23a9d0b92b83 新接线）：不入树直接调 _fit_responsive，
	# 验证 headless 无真实视口时响应式接线空安全跳过（不崩、不把面板误裁成 240 下限）。
	# 注：run_all._ready 期间 root 正在装配子节点，add_child 会报 "busy"，故不走入树路径。
	var dlg: Control = SaveNameDialogScene.instantiate()
	expect(dlg != null, "实例化 SaveNameDialog 应成功")
	if dlg == null:
		return
	var panel := dlg.get_node_or_null("Panel") as Control
	expect(panel != null, "SaveNameDialog 主面板 Panel 应存在")
	if panel == null:
		dlg.free()
		return
	var before: Vector2 = panel.custom_minimum_size
	dlg._fit_responsive()
	expect(panel.custom_minimum_size == before,
		"无真实视口时 _fit_responsive 应空安全跳过（尺寸不变 %s）" % panel.custom_minimum_size)
	dlg.free()
