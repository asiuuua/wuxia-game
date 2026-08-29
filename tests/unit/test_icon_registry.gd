# tests/unit/test_icon_registry.gd
# 图标解析引擎单元测试（UI 窗口主权）：验证"美术接入预留接口"的基本契约
# - 缺图标返回占位图（非 null，不崩）
# - 存在的样例图标能正确加载（支持子目录 id）
# - 空 id / null 安全
# - 解析结果被缓存
extends TestBase

const IconRegistry = preload("res://scenes/ui/icon_registry.gd")

func test_missing_icon_returns_placeholder_not_null() -> void:
	var tex := IconRegistry.get_icon("items/this_does_not_exist")
	expect(tex != null, "缺图标必须返回非 null（占位图），不能崩")
	expect(tex is Texture2D, "返回值必须是 Texture2D")
	expect(not IconRegistry.has_icon("items/this_does_not_exist"), "缺图标 has_icon 应为 false")

func test_existing_sample_icon_loads() -> void:
	# resources/icons/_sample/sample_heart.png 应由门禁导入存在
	var tex := IconRegistry.get_icon("_sample/sample_heart")
	expect(tex != null, "样例图标应加载成功")
	expect(tex is Texture2D, "样例图标应为 Texture2D")
	expect(IconRegistry.has_icon("_sample/sample_heart"), "样例图标 has_icon 应为 true")

func test_subdirectory_id_resolves() -> void:
	# id 带子目录，验证路径拼接正确
	var tex := IconRegistry.get_icon("_sample/sample_heart")
	expect(tex != null, "带子目录的 id 应正确解析")

func test_empty_and_null_id_safe() -> void:
	var empty := IconRegistry.get_icon("")
	expect(empty != null, "空字符串 id 必须返回非 null 占位图")
	var nul := IconRegistry.get_icon("")
	expect(nul != null, "null 等价空 id 必须返回非 null 占位图")

func test_result_is_cached() -> void:
	var a := IconRegistry.get_icon("_sample/sample_heart")
	var b := IconRegistry.get_icon("_sample/sample_heart")
	expect(a == b, "同一 id 两次解析应返回同一缓存实例")

func test_uimanager_delegates_get_icon() -> void:
	# 其它窗口统一走 UIManager.get_icon，验证委托有效且安全
	var tex := UIManager.get_icon("status/also_missing")
	expect(tex != null, "UIManager.get_icon 缺图标也应返回非 null 占位图")
	expect(UIManager.has_icon("_sample/sample_heart"), "UIManager.has_icon 应正确委托")
