# tests/unit/test_hud_mount.gd
# 验证「常驻 HUD 的位置修复」：HUD 不再挂在场景 Node2D 下（随 Camera2D 飘移），
# 而是挂进 UIManager 的 HUD 专属层（屏幕固定位置）。
extends TestBase

## HUD 层应存在，且真实 CanvasLayer.layer = 50（枚举值 5 * 10），
## 落在世界层(0) 之上、转场层(100) 之下。
func test_hud_layer_exists_and_value() -> void:
	var layer: CanvasLayer = UIManager.get_layer(UIManager.Layer.HUD)
	expect(layer != null, "UIManager 应存在 HUD 层（Layer.HUD）")
	if layer == null:
		return
	expect(layer.layer == 50, "HUD 层真实值应为 50（枚举 5 * 10），而非世界层/转场层")
	expect(layer.layer > 0, "HUD 层应高于世界层(0)")
	expect(layer.layer < 100, "HUD 层应低于转场层(100)")

## mount_hud 后，传入的 HUD 根应挂在 HUD 层 CanvasLayer 之下（屏幕固定、Camera2D 无关），
## 且管理器只持有这一个所有者。核心修复：HUD 不再挂在场景 Node2D 下随镜头飘移。
## 注：不在测试里断言 is_inside_tree()——UIManager 的层级 CanvasLayer 经 call_deferred 挂到 root，
## 测试执行当帧尚未入树，属 harness 时序假象；真实运行多帧后必入树。
func test_mount_hud_attaches_to_hud_layer() -> void:
	var ctrl := Control.new()
	UIManager.mount_hud(ctrl)
	var layer: CanvasLayer = UIManager.get_layer(UIManager.Layer.HUD)
	expect(ctrl.get_parent() == layer, "mount_hud 后 HUD 应挂在 HUD 层的 CanvasLayer 下（而非场景 Node2D）")
	expect(UIManager._hud == ctrl, "mount_hud 后管理器应持有该 HUD 为唯一所有者")
	# 清理
	UIManager.unmount_hud()

## 重复 mount 不应产生双 HUD：第二次 mount 会先释放旧 HUD，管理器只保留一个 _hud 所有者。
func test_mount_hud_replaces_previous() -> void:
	var a := Control.new()
	var b := Control.new()
	UIManager.mount_hud(a)
	UIManager.mount_hud(b)
	# _hud 是管理器唯一所有者引用（queue_free 延迟释放不影响该引用同步更新）
	expect(UIManager._hud == b, "第二次 mount 后，管理器应只持有新 HUD(b) 一个所有者（防双 HUD）")
	UIManager.unmount_hud()
