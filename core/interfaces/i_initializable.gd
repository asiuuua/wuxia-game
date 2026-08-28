# core/interfaces/i_initializable.gd
# 初始化接口（抽象基类）

extends RefCounted
class_name IInitializable

func initialize() -> void:
	push_error("IInitializable.initialize() 未实现")
