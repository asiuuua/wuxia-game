# core/utils/string_util.gd
# 字符串工具：纯函数，静态调用

extends RefCounted
class_name StringUtil

static func fallback(text: String, default_text: String) -> String:
	return default_text if text.is_empty() else text

# 生成武侠风格物品/武学 ID：<类型>_<名称>_<品级>
static func format_id(prefix: String, item_name: String, grade: String) -> String:
	return "%s_%s_%s" % [prefix, item_name, grade]
