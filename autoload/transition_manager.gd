# autoload/transition_manager.gd
# 转场管理器（无 class_name）：管理场景/界面切换的转场遮罩
# 当前用纯色遮罩 alpha 渐变实现水墨/黑屏等转场占位；真实水墨着色器/序列帧后替换
# transition_to(type, callback)：淡入(0.5s) → 中点回调(切场景/数据) → 淡出(0.5s) → 释放
# 设计稿 §7 实现

extends Node

enum TransitionType {
	INK,      # 水墨淡入淡出（主菜单↔游戏、场景切换）
	BLACK,    # 黑屏淡入淡出（死亡/重生、剧情跳转）
	SCROLL,   # 卷轴展开（备用）
	PAGE,     # 书页翻动（备用）
	SLASH,    # 剑气划过（备用）
	MIST,     # 云雾弥漫（备用）
}

var _is_transitioning: bool = false

func transition_to(type: int, callback: Callable = Callable()) -> void:
	if _is_transitioning:
		return
	_is_transitioning = true

	var overlay: ColorRect = ColorRect.new()
	overlay.color = _color_for(type)
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.modulate.a = 0.0

	var layer: Node = UIManager.get_layer(UIManager.Layer.TRANSITION)
	if layer == null:
		layer = get_tree().root
	layer.add_child(overlay)

	var tween := create_tween()
	tween.tween_property(overlay, "modulate:a", 1.0, 0.5)
	tween.tween_callback(func():
		if callback.is_valid():
			callback.call()
	)
	tween.tween_property(overlay, "modulate:a", 0.0, 0.5)
	tween.tween_callback(func():
		overlay.queue_free()
		_is_transitioning = false
	)

func is_transitioning() -> bool:
	return _is_transitioning

func _color_for(type: int) -> Color:
	match type:
		TransitionType.INK: return Color(0.102, 0.086, 0.071, 1.0)
		TransitionType.BLACK: return Color(0.0, 0.0, 0.0, 1.0)
		TransitionType.MIST: return Color(0.941, 0.902, 0.820, 1.0)
		_: return Color(0.0, 0.0, 0.0, 1.0)
