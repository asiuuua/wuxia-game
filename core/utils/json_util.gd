# core/utils/json_util.gd
# JSON 读写工具：统一封装 FileAccess，避免重复代码

extends RefCounted
class_name JSONUtil

static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[JSON] 文件不存在: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("[JSON] 解析失败: %s" % path)
		return {}
	return parsed

static func save_json(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[JSON] 写入失败: %s" % path)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true
