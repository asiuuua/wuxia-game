# tests/unit/test_loading_overlay.gd
# 验证区域枢纽读条切换的加载覆盖层：构建/清理/提示文案/相邻区域预加载守卫
extends TestBase

func before_each() -> void:
	_force_clear_overlay()

func after_each() -> void:
	_force_clear_overlay()

## 硬清理：测试间不残留全屏覆盖层（避免遮挡后续测试的 UI 交互）
func _force_clear_overlay() -> void:
	if GameManager._loading_overlay != null and is_instance_valid(GameManager._loading_overlay):
		GameManager._loading_overlay.free()
	GameManager._loading_overlay = null
	GameManager._loading_bg = null
	GameManager._loading_label = null
	GameManager._preload_pending = []

## 显示加载覆盖层：应创建命名 LoadingOverlay 的 CanvasLayer 并持有引用
func test_show_creates_overlay() -> void:
	GameManager._show_loading_overlay()
	expect(GameManager._loading_overlay != null, "显示后应持有覆盖层引用")
	if GameManager._loading_overlay == null:
		return
	expect(GameManager._loading_overlay.name == "LoadingOverlay", "覆盖层应命名 LoadingOverlay")
	expect(GameManager._loading_overlay.layer == 600, "覆盖层应位于层 600（高于系统浮层 500）")
	expect(GameManager._loading_bg != null, "覆盖层应包含半透明底色")
	expect(GameManager._loading_label != null, "覆盖层应包含提示文案 Label")

## 隐藏加载覆盖层：应清空引用（queue_free 延迟释放，不残留引用）
func test_hide_clears_overlay() -> void:
	GameManager._show_loading_overlay()
	GameManager._hide_loading_overlay()
	expect(GameManager._loading_overlay == null, "隐藏后应清空覆盖层引用")
	expect(GameManager._loading_bg == null, "隐藏后应清空底色引用")
	expect(GameManager._loading_label == null, "隐藏后应清空文案引用")

## 重复显示不应重复创建：二次调用直接复用已有覆盖层
func test_show_idempotent() -> void:
	GameManager._show_loading_overlay()
	var first: CanvasLayer = GameManager._loading_overlay
	GameManager._show_loading_overlay()
	expect(GameManager._loading_overlay == first, "重复显示应复用同一覆盖层，不重复创建")

## 加载提示文案：从 loading_tips.json 读取且非空
func test_loading_tips_loaded() -> void:
	GameManager._load_loading_tips()
	expect(GameManager._loading_tips.size() > 0, "loading_tips.json 应加载出至少一条提示")
	var tip: String = GameManager._pick_loading_tip()
	expect(not tip.is_empty(), "加载提示不应为空")

## 相邻区域预加载守卫：未实装场景（scene_path 为空）的相邻区域不应进入预加载队列
func test_preload_skips_unimplemented() -> void:
	GameManager._preload_pending = []
	GameManager._preload_adjacent_regions("region_start_town")
	# 起始城镇连接 3 个区域，均未实装 scene_path（空），故不应入队
	expect(GameManager._preload_pending.is_empty(), "未实装场景的相邻区域不应进入预加载队列")
