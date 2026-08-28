# core/extensions/node_extension.gd
# 节点扩展方法：复用常见节点操作（如淡入）

extends RefCounted
class_name NodeExtension

static func fade_in(node: CanvasItem, duration: float = 0.3) -> void:
	node.modulate.a = 0.0
	var tween := node.create_tween()
	tween.tween_property(node, "modulate:a", 1.0, duration)
