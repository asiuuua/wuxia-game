# application/content/schema_field_checker.gd
# Phase 3 Schema 系统运行期字段级校验器（03 图 §6.3 / 05 图 VA-2 第一层①）
# 双端同源：规则只存 data/configs/content_schemas.json（构建期 tools/schema_validator.py 同读），
# 本类实现「形状」语义（type / required / enum / regex），与 Python 侧逐条对齐：
#   · required 只在字段缺失时判违规（allow_empty 为元数据说明，Python 侧同样不拦空值）
#   · enum / regex 对 string 值无条件检查（含空串，与 re.match 语义一致）
#   · number 类型放行 integer 值（Python: t=="number" and got=="integer"）
#   · stable_id / *_ref / localization_key 属构建期专责（ID 白名单/引用存在性），运行期不重复实现
# 运行期语义 = 容错层登记（ERROR，不拒载）；FATAL 拒写由构建期 DataSink ② 步承担。

class_name SchemaFieldChecker
extends RefCounted

## glob 匹配（支持 * 与 ?；贪婪回溯，与 fnmatch 语义对齐）
static func glob_match(s: String, p: String) -> bool:
	var si := 0
	var pi := 0
	var star: int = -1
	var mark := 0
	while si < s.length():
		if pi < p.length() and (p[pi] == "?" or p[pi] == s[si]):
			si += 1
			pi += 1
		elif pi < p.length() and p[pi] == "*":
			star = pi
			mark = si
			pi += 1
		elif star != -1:
			pi = star + 1
			mark += 1
			si = mark
		else:
			return false
	while pi < p.length() and p[pi] == "*":
		pi += 1
	return pi == p.length()

static func glob_match_any(rel: String, patterns: Array) -> bool:
	for p in patterns:
		if glob_match(rel, String(p).replace("\\", "/")):
			return true
	return false

## 取 rel_path 命中的第一个 schema（未命中返回空字典）
static func schema_for(schemas: Dictionary, rel_path: String) -> Dictionary:
	var rel := rel_path.replace("\\", "/")
	for schema in schemas.values():
		if glob_match_any(rel, schema.get("files", [])):
			return schema
	return {}

## 条目字段表：entry_fields（数组型）或 value_schema（键值映射型）
static func entry_fields_of(schema: Dictionary) -> Dictionary:
	if schema.has("entry_fields"):
		return schema.get("entry_fields", {})
	return schema.get("value_schema", {})

static func type_of(v: Variant) -> String:
	if v is bool:
		return "boolean"
	match typeof(v):
		TYPE_INT:
			return "integer"
		TYPE_FLOAT:
			return "number"
		TYPE_STRING:
			return "string"
		TYPE_ARRAY:
			return "array"
		TYPE_DICTIONARY:
			return "object"
	return "unknown"

## 单字段形状检查（与 schema_validator.py _check_field 对齐）
static func _check_field(field: String, spec: Dictionary, v: Variant) -> String:
	var t := String(spec.get("type", "string"))
	var got := type_of(v)
	if got != t and not (t == "number" and got == "integer"):
		return "字段 %s 类型应为 %s，实际 %s" % [field, t, got]
	if got == "string":
		var sval := str(v)
		if spec.has("enum") and not (spec["enum"] is Array and (spec["enum"] as Array).has(sval)):
			return "字段 %s 值「%s」不在枚举 %s 内" % [field, sval, JSON.stringify(spec["enum"])]
		var pat := String(spec.get("regex", ""))
		if not pat.is_empty():
			var rx := RegEx.new()
			if rx.compile(pat) == OK and rx.search(sval) == null:
				return "字段 %s 值「%s」不合形态 %s（运行期 regex 需自锚定，与 re.match 对齐）" % [field, sval, pat]
	return ""

## 根条目 + 嵌套集合检查（nested 如 dialogue.lines / quest.objectives）
static func check_entry(schema: Dictionary, entry: Dictionary) -> Array[String]:
	var out: Array[String] = []
	var title := String(schema.get("title", ""))
	var fields := entry_fields_of(schema)
	for f in fields:
		var spec: Dictionary = fields[f]
		if not entry.has(f):
			if spec.get("required", false):
				out.append("缺必填字段 %s（Schema: %s）" % [f, title])
			continue
		var msg := _check_field(f, spec, entry[f])
		if not msg.is_empty():
			out.append("%s（Schema: %s）" % [msg, title])
	for nest_name in schema.get("nested", {}):
		var nest: Dictionary = schema["nested"][nest_name]
		var ncol := String(nest.get("collection", ""))
		if ncol.is_empty() or not (entry.get(ncol) is Array):
			continue
		var nfields: Dictionary = nest.get("entry_fields", {})
		var arr: Array = entry[ncol]
		for i in arr.size():
			var ne: Variant = arr[i]
			if not (ne is Dictionary):
				out.append("嵌套 %s[%d] 应为 object（Schema: %s）" % [ncol, i, title])
				continue
			for f in nfields:
				var spec: Dictionary = nfields[f]
				if not (ne as Dictionary).has(f):
					if spec.get("required", false):
						out.append("%s[%d] 缺必填字段 %s（Schema: %s）" % [ncol, i, f, title])
					continue
				var msg := _check_field(f, spec, (ne as Dictionary)[f])
				if not msg.is_empty():
					out.append("%s[%d] %s（Schema: %s）" % [ncol, i, msg, title])
	return out

## 便捷入口：按 rel_path 找 schema 并检查单条目；无命中 schema 返回空
static func violations_for(schemas: Dictionary, rel_path: String, entry: Dictionary) -> Array[String]:
	var schema := schema_for(schemas, rel_path)
	if schema.is_empty():
		return []
	return check_entry(schema, entry)
