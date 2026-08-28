# core/extensions/resource_extension.gd
# 资源扩展方法：安全加载资源

extends RefCounted
class_name ResourceExtension

static func load_or_null(path: String) -> Resource:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path)
