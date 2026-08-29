# tests/unit/test_popup_lifecycle.gd
# P2 弹窗生命周期单测（同步断言，run_all 不 await 协程）：
#  - 缓存模式（设置/存档 cache:true）：打开入缓存、关闭保留、重开复用同一实例（不重建）
#  - 销毁模式（默认）：不进缓存，关闭走 queue_free
#  - PopupBase 解耦契约：request_close 只 emit popup_close_requested(self)，绝不自毁

extends TestBase

const SettingsScreen = preload("res://scenes/ui/screens/settings/SettingsScreen.gd")
const EquipmentScreen = preload("res://scenes/ui/screens/equipment/EquipmentScreen.gd")
const PopupBase = preload("res://scenes/ui/screens/popup_base.gd")

var _popup_fired: bool = false
var _popup_payload = null

func after_each() -> void:
	UIManager.close_all_screens()
	_popup_fired = false
	_popup_payload = null

func _on_popup_test_close(p: Control) -> void:
	_popup_fired = true
	_popup_payload = p

func test_cached_screen_reused_not_destroyed() -> void:
	# 设置弹窗标记 cache:true：打开→实例入缓存；关闭→隐藏而非销毁；重开→同一实例
	var s1: Control = UIManager.open_screen("SettingsScreen", UIManager.Layer.FULLSCREEN)
	expect(s1 != null, "SettingsScreen 应能打开")
	var cached1: Control = UIManager.get_cached_screen("SettingsScreen")
	expect(cached1 != null and cached1 == s1, "cache:true 打开后实例应进入缓存")
	UIManager.close_screen(s1)
	var cached2: Control = UIManager.get_cached_screen("SettingsScreen")
	expect(cached2 != null and is_instance_valid(cached2), "cache:true 关闭后实例应保留在缓存（不销毁）")
	var s2: Control = UIManager.open_screen("SettingsScreen", UIManager.Layer.FULLSCREEN)
	expect(s2 != null and s2 == s1, "cache:true 重开应复用同一实例（避免重建开销）")
	UIManager.close_screen(s2)

func test_destroy_screen_not_cached() -> void:
	# 装备弹窗未标记 cache：打开后不在缓存；关闭走销毁路径（不缓存）
	var e: Control = UIManager.open_screen("EquipmentScreen", UIManager.Layer.FULLSCREEN)
	expect(e != null, "EquipmentScreen 应能打开")
	expect(UIManager.get_cached_screen("EquipmentScreen") == null, "未标记 cache 的弹窗不应进入缓存")
	UIManager.close_screen(e)
	expect(UIManager.get_cached_screen("EquipmentScreen") == null, "销毁模式：关闭后不应残留在缓存")

func test_popup_base_request_close_emits_signal() -> void:
	# PopupBase 解耦契约：request_close 只 emit 信号，绝不自己销毁
	var pb: PopupBase = PopupBase.new()
	expect(EventBus.has_signal("popup_close_requested"), "EventBus 应有 popup_close_requested 信号（解耦总线）")
	EventBus.popup_close_requested.connect(_on_popup_test_close)
	pb.request_close()
	expect(_popup_fired, "request_close 应经 EventBus emit popup_close_requested 信号")
	expect(_popup_payload == pb, "信号载荷应为弹窗自身（Service 据此关闭）")
	EventBus.popup_close_requested.disconnect(_on_popup_test_close)

func test_sub_screen_extends_popup_base_decoupled_close() -> void:
	# 迁移后：子屏继承 PopupBase；关闭只 emit 事件总线，由 UIManager 收口（视图不自行销毁）
	var scr: Control = load("res://scenes/ui/screens/forge/ForgeScreen.gd").new()
	expect(scr is PopupBase, "锻造界面应继承 PopupBase（统一弹窗基类）")
	_popup_fired = false
	_popup_payload = null
	EventBus.popup_close_requested.connect(_on_popup_test_close)
	scr.request_close()
	expect(_popup_fired, "request_close 应经事件总线 emit popup_close_requested")
	expect(_popup_payload == scr, "信号载荷为弹窗自身，Service 据此定位关闭")
	EventBus.popup_close_requested.disconnect(_on_popup_test_close)

func test_sub_screen_open_and_close_via_bus() -> void:
	# 真实路径：经 UIManager 打开锻造界面，request_close 后由 UIManager 收口关闭（不依赖按名查找）
	var scr: Control = UIManager.open_screen("ForgeScreen", UIManager.Layer.FULLSCREEN)
	expect(scr != null, "锻造界面应经 UIManager 成功打开")
	expect(scr is PopupBase, "打开的界面应继承 PopupBase")
	expect(UIManager.is_any_screen_open(), "打开后应有界面处于打开态")
	scr.request_close()
	expect(not UIManager.is_any_screen_open(), "request_close 经事件总线关闭后不应再有打开的界面")

func test_remaining_screens_migrated_and_unified() -> void:
	# P2.5 收尾：属性/背包/结缘/技艺/设置/菜单根 6 屏统一继承 PopupBase（关闭只 emit 事件总线，UIManager 收口）。
	var names: Array[String] = ["AttributesScreen", "InventoryScreen", "BondRomance", "AbilitiesScreen", "SettingsScreen", "GameMenu"]
	for n in names:
		var scr: Control = UIManager.open_screen(n, UIManager.Layer.FULLSCREEN)
		expect(scr != null, "打开 %s 应成功（迁移后不崩）" % n)
		expect(scr is PopupBase, "%s 应继承 PopupBase（统一弹窗基类/关闭逻辑）" % n)
		UIManager.close_screen(scr)
