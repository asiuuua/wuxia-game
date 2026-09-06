# tests/unit/test_schema_field_checker.gd
# Phase 3 Schema 系统运行期双通道单测（03 图 §6.3 / 05 图 VA-2 第一层① / VA1-SCHEMA）：
#   · SchemaFieldChecker：glob 匹配 · 字段级形状（required/type/enum/number 放行 integer）·
#     嵌套集合（dialogue.lines）· 键值映射型（dialogue_index value_schema）
#   · ContentRegistry 集成：load_schemas 注入后，adapter 文件命中 schema 时记 VA1-SCHEMA
#     （ERROR 语义=登记不拒载，FATAL 拒写属构建期 DataSink ②）
# 规则真源与构建期 tools/schema_validator.py 同一份 content_schemas.json（本测内联镜像其结构）。

extends TestBase
class_name TestSchemaFieldChecker

# 内联镜像 data/configs/content_schemas.json 的 npc / dialogue / dialogue_index 三张表
const SCHEMAS := {
	"npc": {
		"title": "区域 NPC 演员表",
		"files": ["regions/region_*/npcs.json"],
		"collection": "npcs",
		"entry_fields": {
			"id": {"type": "string", "required": true, "stable_id": true},
			"name": {"type": "string", "required": true, "allow_empty": true},
			"scene": {"type": "string", "required": true},
			"pos_x": {"type": "number"},
			"portrait_type": {"type": "string", "enum": ["static", "skeleton"], "allow_empty": true},
		},
	},
	"dialogue": {
		"title": "对话分片（根条目 + lines 嵌套）",
		"files": ["npcs/dialogs/shards/*.json", "regions/region_*/dialogs/*.json"],
		"root_entry": true,
		"entry_fields": {
			"id": {"type": "string", "required": true, "stable_id": true},
			"npc_id": {"type": "string", "npc_ref": true, "allow_empty": true},
		},
		"nested": {
			"lines": {
				"collection": "lines",
				"entry_fields": {
					"id": {"type": "string", "required": true},
					"speaker_id": {"type": "string", "allow_empty": true},
					"text": {"type": "string", "required": true, "localization_key": true},
				},
			},
		},
	},
	"dialogue_index": {
		"title": "对话全局索引（shards 键值映射）",
		"files": ["npcs/dialogs/_index.json"],
		"value_key": "shards",
		"value_schema": {
			"file": {"type": "string", "required": true, "asset_ref": true},
			"npc_id": {"type": "string", "npc_ref": true, "allow_empty": true},
		},
	},
}

# === glob 匹配（region_* / shards/*）===

func test_glob_region_and_shard_patterns() -> void:
	expect(SchemaFieldChecker.glob_match("regions/region_misty_town/npcs.json", "regions/region_*/npcs.json"),
		"区域 npcs 路径应命中 region_* 通配")
	expect(SchemaFieldChecker.glob_match("npcs/dialogs/shards/dlg_a.json", "npcs/dialogs/shards/*.json"),
		"分片路径应命中 shards/* 通配")
	expect(not SchemaFieldChecker.glob_match("quests/quests.json", "regions/region_*/npcs.json"),
		"不匹配模式应拒绝")
	expect(SchemaFieldChecker.schema_for(SCHEMAS, "regions/region_x/dialogs/dlg_1.json").get("title", "") == "对话分片（根条目 + lines 嵌套）",
		"区域对白应命中 dialogue schema")

# === 字段级形状（required / type / enum / number 放行 integer）===

func test_npc_required_and_type_checks() -> void:
	var rel := "regions/region_misty_town/npcs.json"
	var valid := {"id": "npc_a", "name": "阿", "scene": "sc_1", "pos_x": 3}
	expect(SchemaFieldChecker.violations_for(SCHEMAS, rel, valid).is_empty(),
		"合法条目应零违规")
	var missing_scene := {"id": "npc_b", "name": "贝"}
	var v1 := SchemaFieldChecker.violations_for(SCHEMAS, rel, missing_scene)
	expect(v1.size() == 1 and v1[0].contains("缺必填字段 scene"), "缺必填字段应判违规（证据含字段名）")
	var wrong_type := {"id": "npc_c", "name": "测", "scene": "sc_1", "pos_x": "oops"}
	var v2 := SchemaFieldChecker.violations_for(SCHEMAS, rel, wrong_type)
	expect(v2.size() == 1 and v2[0].contains("类型应为 number"), "类型不符应判违规（number 字段收到 string）")
	var int_ok := {"id": "npc_d", "name": "丁", "scene": "sc_1", "pos_x": 5}
	expect(SchemaFieldChecker.violations_for(SCHEMAS, rel, int_ok).is_empty(),
		"number 字段放行 integer 值（与 Python 侧对齐）")
	var bad_enum := {"id": "npc_e", "name": "戊", "scene": "sc_1", "portrait_type": "3d"}
	var v3 := SchemaFieldChecker.violations_for(SCHEMAS, rel, bad_enum)
	expect(v3.size() == 1 and v3[0].contains("不在枚举"), "枚举外值应判违规")
	var name_empty_ok := {"id": "npc_f", "name": "", "scene": "sc_1"}
	expect(SchemaFieldChecker.violations_for(SCHEMAS, rel, name_empty_ok).is_empty(),
		"allow_empty 字段空串应放行（与 Python 侧一致：required 只拦缺失不拦空值）")

# === 嵌套集合（dialogue.lines）===

func test_dialogue_nested_lines_checks() -> void:
	var rel := "npcs/dialogs/shards/dlg_x.json"
	var valid := {"id": "dlg_x", "lines": [
		{"id": "l1", "speaker_id": "npc_a", "text": "d_x.l1"},
	]}
	expect(SchemaFieldChecker.violations_for(SCHEMAS, rel, valid).is_empty(), "合法分片应零违规")
	var bad := {"id": "dlg_y", "lines": [
		{"id": "l1", "text": "d_y.l1"},
		{"id": "l2"},
	]}
	var v := SchemaFieldChecker.violations_for(SCHEMAS, rel, bad)
	expect(v.size() == 1 and v[0].contains("lines[1]") and v[0].contains("缺必填字段 text"),
		"嵌套行缺必填 text 应判违规（证据含嵌套下标与字段名）")

# === 键值映射型（dialogue_index value_schema）===

func test_dialogue_index_value_schema() -> void:
	var rel := "npcs/dialogs/_index.json"
	var ok_entry := {"file": "npcs/dialogs/shards/dlg_x.json", "npc_id": "npc_a"}
	expect(SchemaFieldChecker.violations_for(SCHEMAS, rel, ok_entry).is_empty(),
		"索引条目含 file 应零违规")
	var no_file := {"npc_id": "npc_a"}
	var v := SchemaFieldChecker.violations_for(SCHEMAS, rel, no_file)
	expect(v.size() == 1 and v[0].contains("缺必填字段 file"), "索引条目缺 file 应判违规（value_schema 生效）")

# === 未命中 schema 静默 ==

func test_no_schema_matched_silent() -> void:
	expect(SchemaFieldChecker.violations_for(SCHEMAS, "items/weapons.json", {"id": ""}).is_empty(),
		"未命中 schema 的文件应零违规（ability/item 当前无 schema=no-op）")

# === ContentRegistry 集成（VA1-SCHEMA，ERROR 语义=登记不拒载）===

var _files: Dictionary = {}
var _errors: Array[String] = []

func _fake_loader(path: String) -> Dictionary:
	return _files.get(path, {})

func _collect_error(msg: String) -> void:
	_errors.append(msg)

func test_registry_records_va1_schema_violation() -> void:
	_files.clear()
	_errors.clear()
	var reg := ContentRegistry.new(Callable(self, "_fake_loader"), Callable(self, "_collect_error"))
	var npc_file := "res://data/configs/regions/region_misty_town/npcs.json"
	_files[npc_file] = {"version": "1.0.0", "npcs": [
		{"id": "npc_ok", "name": "良", "scene": "sc_1"},
		{"id": "npc_bad", "name": "缺场景"},
	]}
	var fa: Array[String] = [npc_file]
	reg.register_adapter(ContentTypeAdapter.new(&"npc", fa, "npcs", "id", "NPC"))
	reg.load_schemas(SCHEMAS)
	expect(reg.load_packs().is_ok(), "VA1-SCHEMA 为 ERROR 语义：登记不拒载，装载应成功")
	expect(reg.has_entry(&"npc", "npc_bad"), "违规条目仍入表（容错层登记，构建期才拒写）")
	var found := false
	for v in reg.validate_all():
		if v.get_code() == &"VA1-SCHEMA" and v.get_detail().contains("缺必填字段 scene"):
			found = true
	expect(found, "validate_all 应含 VA1-SCHEMA 违规（rule_id + 证据保真）")
