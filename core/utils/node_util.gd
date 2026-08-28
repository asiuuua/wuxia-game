# core/utils/node_util.gd
# 节点工具：安全查找与信号连接，避免散落的 get_node 硬编码

extends RefCounted
class_name NodeUtil

static func find_child_by_name(parent: Node, child_name: String) -> Node:
	return parent.find_child(child_name, true, false)

# 连接信号前先判断是否已连接，避免重复连接报错
static func safe_connect(sig: Signal, callable: Callable) -> void:
	if not sig.is_connected(callable):
		sig.connect(callable)

# 断开信号前先判断是否已连接，避免重复断开报错
static func safe_disconnect(sig: Signal, callable: Callable) -> void:
	if sig.is_connected(callable):
		sig.disconnect(callable)
