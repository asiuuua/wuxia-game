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
	# 原子写（13图 SV-6）：写 .tmp → 回读解析校验 → rename 替换主档；
	# 写入中途崩溃时主档保持完好（与 SaveManager 五步同款语义，公共 helper 随 Phase5 抽离统一）
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[JSON] 无法写入临时文件: %s" % tmp)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	var check: Variant = null
	var rf := FileAccess.open(tmp, FileAccess.READ)
	if rf != null:
		check = JSON.parse_string(rf.get_as_text())
		rf.close()
	if not (check is Dictionary):
		push_error("[JSON] 临时文件校验失败，放弃写入: %s" % tmp)
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("[JSON] 替换主档失败: %s" % path)
		DirAccess.remove_absolute(tmp)
		return false
	return true

static func _save_json_legacy(path: String, data: Dictionary) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[JSON] 写入失败: %s" % path)
		return false
	f.store_string(JSON.stringify(data))
	f.close()
	return true
