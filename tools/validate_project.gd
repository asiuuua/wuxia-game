# tools/validate_project.gd
# 工程规范批量校验器（工业化扩容 P7 · 零硬编码 / JSON 有效 / 无 .tres / 命名规范）
#
# 运行：Godot console --headless --path "D:/武侠游戏" --script res://tools/validate_project.gd
# 设计：纯 FileAccess/DirAccess 文件系统扫描，不加载任何 autoload（规避 --script 假阳性）。
#
# 校验规则：
#   1) JSON 有效：res://data/**/*.json 全部可解析（配置表/分片/索引）。
#   2) 禁 .tres：游戏代码（非 tools/、非注释行）不得出现 .tres（JSON 铁律，资源不落 .tres）。
#   3) 禁硬编码数据路径：load/preload/FileAccess.open 的字符串字面量不得直接写
#      res://data/ 或 res://assets/（应走 ConfigManager / PathConstants）。
#      豁免：path_constants.gd、ConfigManager.gd、tools/、tests/、core/constants/、以及 .gd 脚本 preload。
#   4) class_name PascalCase：全大写开头 + 字母数字（见名知意、风格统一）。
#   5) class_name 不重复。
#
# 退出：扫描完毕打印汇总并 quit(0)；输出含 "✗" 表示有违规（可在 CI 用 grep 判定）。

extends SceneTree

const SKIP_DIRS := ["res://.godot", "res://.git", "res://addons"]

var _violations: Array[String] = []
var _gd_files: Array[String] = []
var _json_files: Array[String] = []

func _initialize() -> void:
	print("══════════════════════════════════════")
	print("武侠江湖 · 工程规范批量校验（P7）")
	print("══════════════════════════════════════")
	_collect_files("res://")
	print("扫描到 %d 个 .gd 文件，%d 个 data/*.json 文件" % [_gd_files.size(), _json_files.size()])

	_check_json_valid()
	_check_no_tres()
	_check_no_hardcoded_data_path()
	_check_class_name_pascal()
	_check_duplicate_class_name()

	_report()

func _collect_files(dir_path: String) -> void:
	if SKIP_DIRS.has(dir_path):
		return
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	d.list_dir_begin()
	var name: String = d.get_next()
	while name != "":
		if name == "." or name == "..":
			name = d.get_next()
			continue
		var full := dir_path.trim_suffix("/") + "/" + name
		if d.current_is_dir():
			_collect_files(full)
		else:
			if name.ends_with(".gd") and not SKIP_DIRS.has(full.get_base_dir()):
				_gd_files.append(full)
			elif name.ends_with(".json") and not SKIP_DIRS.has(dir_path):
				# 全量 JSON 校验（data 配置分片/索引/资源表均覆盖；跳过 .godot/.git/addons）
				_json_files.append(full)
		name = d.get_next()
	d.list_dir_end()

# ---- 规则 1：JSON 全部可解析 ----
func _check_json_valid() -> void:
	for p in _json_files:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			_add("JSON 无法打开: %s" % p)
			continue
		var txt := f.get_as_text()
		f.close()
		var parsed = JSON.parse_string(txt)
		if parsed == null:
			_add("JSON 解析失败: %s" % p)

# ---- 规则 2：禁 .tres（tools/ 与注释行豁免）----
func _check_no_tres() -> void:
	for p in _gd_files:
		if p.contains("/tools/"):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var idx := 0
		while not f.eof_reached():
			var line := f.get_line()
			idx += 1
			if line.strip_edges().begins_with("#"):
				continue
			if line.contains(".tres"):
				_add("%s:%d 出现 .tres（JSON 铁律禁止；应使用 .json/资源引用）" % [p, idx])
		f.close()

# ---- 规则 3：禁硬编码数据路径 ----
func _check_no_hardcoded_data_path() -> void:
	var exempt_file: Array[String] = ["res://core/constants/path_constants.gd", "res://autoload/ConfigManager.gd"]
	for p in _gd_files:
		if p.contains("/tools/") or p.contains("/tests/") or p.contains("/core/constants/"):
			continue
		if exempt_file.has(p):
			continue
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var idx := 0
		while not f.eof_reached():
			var line := f.get_line()
			idx += 1
			if line.strip_edges().begins_with("#"):
				continue
			# 捕获 load( / preload( / FileAccess.open( 后紧跟字符串字面量（双或单引号）
			var m := _extract_string_after_call(line)
			if m.is_empty():
				continue
			if m.begins_with("res://data/") or m.begins_with("res://assets/"):
				if m.ends_with(".gd"):
					continue   # 脚本 preload 属代码依赖，非内容硬编码
				_add("%s:%d 硬编码数据/资源路径: %s（应走 ConfigManager / PathConstants）" % [p, idx, m])
		f.close()

# 从一行里找 load(/preload(/FileAccess.open( 后的字符串字面量；找不到返回 ""
func _extract_string_after_call(line: String) -> String:
	for kw in ["load(", "preload(", "FileAccess.open("]:
		var at := line.find(kw)
		if at < 0:
			continue
		var rest := line.substr(at + kw.length())
		# 跳过空白与可选的 "res://"? 直接找第一个引号
		var q1 := _find_quote(rest)
		if q1 < 0:
			continue
		var q := rest[q1]
		var end := rest.find(q, q1 + 1)
		if end < 0:
			continue
		return rest.substr(q1 + 1, end - q1 - 1)
	return ""

func _find_quote(s: String) -> int:
	for i in range(s.length()):
		var c: String = s[i]
		if c == "\"" or c == "'":
			return i
	return -1

# ---- 规则 4：class_name PascalCase ----
func _check_class_name_pascal() -> void:
	for p in _gd_files:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		var idx := 0
		while not f.eof_reached():
			var line := f.get_line()
			idx += 1
			if line.strip_edges().begins_with("#"):
				continue
			var stripped := line.strip_edges()
			if not stripped.begins_with("class_name "):
				continue   # 仅匹配真正的声明行（忽略注释/字符串中的 class_name 文本）
			var name := stripped.substr("class_name ".length()).strip_edges()
			# 去掉行尾注释
			var hc := name.find("#")
			if hc >= 0:
				name = name.substr(0, hc).strip_edges()
			if not _is_pascal(name):
				_add("%s:%d class_name '%s' 非 PascalCase（须大写字母开头、仅字母数字）" % [p, idx, name])
		f.close()

func _is_pascal(s: String) -> bool:
	if s == "" or s[0] < "A" or s[0] > "Z":
		return false
	for c in s:
		if not ((c >= "A" and c <= "Z") or (c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			return false
	return true

# ---- 规则 5：class_name 不重复 ----
func _check_duplicate_class_name() -> void:
	var seen: Dictionary = {}
	for p in _gd_files:
		var f := FileAccess.open(p, FileAccess.READ)
		if f == null:
			continue
		while not f.eof_reached():
			var line := f.get_line()
			if line.strip_edges().begins_with("#"):
				continue
			var stripped := line.strip_edges()
			if not stripped.begins_with("class_name "):
				continue
			var name := stripped.substr("class_name ".length()).strip_edges()
			var hc := name.find("#")
			if hc >= 0:
				name = name.substr(0, hc).strip_edges()
			if seen.has(name):
				_add("class_name '%s' 重复定义（%s 与 %s）" % [name, seen[name], p])
			else:
				seen[name] = p
		f.close()

func _add(msg: String) -> void:
	_violations.append(msg)

func _report() -> void:
	var log_path := "user://project_validation.log"
	var f := FileAccess.open(log_path, FileAccess.WRITE)
	if f != null:
		f.store_line("【武侠江湖 工程规范校验报告】生成时间: " + Time.get_datetime_string_from_system())
		f.store_line("扫描: %d 个 .gd，%d 个 data/*.json" % [_gd_files.size(), _json_files.size()])
		if _violations.is_empty():
			f.store_line("结果：全部通过 ✓")
		else:
			f.store_line("发现 %d 处违规：" % _violations.size())
			for v in _violations:
				f.store_line("  - " + v)
		f.close()

	print("──────────────────────────────────────")
	if _violations.is_empty():
		print("✓ 工程校验通过（5 项规则）：%d 个 .gd，%d 个 data/*.json" % [_gd_files.size(), _json_files.size()])
	else:
		print("✗ 发现 %d 处违规：" % _violations.size())
		for v in _violations:
			print("  ✗ " + v)
	print("报告已写入: %s" % ProjectSettings.globalize_path(log_path))
	print("══════════════════════════════════════")
	quit(0)
