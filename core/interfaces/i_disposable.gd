# core/interfaces/i_disposable.gd
# 释放接口（抽象基类）：用于资源/对象清理

extends RefCounted
class_name IDisposable

func dispose() -> void:
	push_error("IDisposable.dispose() 未实现")
