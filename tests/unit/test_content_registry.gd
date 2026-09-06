# tests/unit/test_content_registry.gd
# ContentRegistry 单测（05 图 CT-3/LD-2/VE-1/IX/CO-R06/CO-R12 / CONTENT-RUNTIME v1.2.0）：
# adapter 装载 · 重复记错覆盖 · 条目校验 · DialogueByNPC 索引 · 指纹可复算 · fail-fast 骨架 · base 永驻。
# 假 loader 注入：零真实磁盘；错误走收集数组不污染引擎输出。

extends TestBase
class_name TestContentRegistry

var _files: Dictionary = {}
var _errors: Array[String] = []

func _fake_loader(path: String) -> Dictionary:
	return _files.get(path, {})

func _collect_error(msg: String) -> void:
	_errors.append(msg)

func _make_registry() -> ContentRegistry:
	_files.clear()
	_errors.clear()
	return ContentRegistry.new(Callable(self, "_fake_loader"), Callable(self, "_collect_error"))

# === adapter 装载（CT-4 通用化算法：行为保真）===

func test_adapter_load_and_version_last_wins() -> void:
	var reg := _make_registry()
	_files["res://t/abilities.json"] = {"version": "1.2.0", "skills": [{"id": "abi_a"}, {"id": "abi_b"}]}
	_files["res://t/items.json"] = {"version": "1.0.1", "items": [{"id": "itm_a"}]}
	var fa: Array[String] = ["res://t/abilities.json"]
	var fi: Array[String] = ["res://t/items.json"]
	expect(reg.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能")), "adapter 注册应成功")
	expect(reg.register_adapter(ContentTypeAdapter.new(&"item", fi, "items", "id", "物品")), "第二个 adapter 注册应成功")
	expect(reg.load_packs().is_ok(), "装载应成功")
	expect(reg.has_entry(&"ability", "abi_a") and reg.has_entry(&"ability", "abi_b"), "ability 条目应可达")
	expect_eq(reg.all_ids(&"item").size(), 1, "item 应一条")
	expect(reg.source_version(&"item") == "1.0.1", "version 逐文件最后者胜（ability 1.2.0 → item 1.0.1）")

func test_duplicate_entry_records_error_and_overwrites() -> void:
	var reg := _make_registry()
	_files["res://t/a.json"] = {"skills": [{"id": "d_x", "v": 1}]}
	_files["res://t/b.json"] = {"skills": [{"id": "d_x", "v": 2}]}
	var fa: Array[String] = ["res://t/a.json", "res://t/b.json"]
	reg.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	reg.load_packs()
	expect(_errors.size() > 0 and _errors[0].contains("技能 d_x 重复定义"), "重复 id 应记错（文案保真）")
	expect(int(reg.get_entry(&"ability", "d_x").get("v", 0)) == 2, "重复 id 后者覆盖")

func test_invalid_entries_skipped() -> void:
	var reg := _make_registry()
	_files["res://t/a.json"] = {"skills": ["not_a_dict", {"name": "无id"}, {"id": "ok_one"}]}
	var fa: Array[String] = ["res://t/a.json"]
	reg.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	reg.load_packs()
	expect(reg.has_entry(&"ability", "ok_one"), "合法条目应入表")
	expect_eq(reg.all_ids(&"ability").size(), 1, "非法条目应跳过（非对象/缺 id）")
	var joined := ",".join(_errors)
	expect(joined.contains("条目不是对象") and joined.contains("条目缺少字段"), "错误文案与容错层保真")

# === 五段 Loader（LD-2）===

func test_load_twice_rejected() -> void:
	var reg := _make_registry()
	var fa: Array[String] = ["res://t/a.json"]
	reg.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	expect(reg.load_packs().is_ok(), "首装应成功")
	var second := reg.load_packs()
	expect(second.is_failed(), "二次装载应拒绝（运行期内容不可变 CA-4）")
	expect(second.has_error_code(&"CONTENT_ALREADY_LOADED"), "错误码 CONTENT_ALREADY_LOADED")

func test_register_after_load_rejected() -> void:
	var reg := _make_registry()
	var fa: Array[String] = ["res://t/a.json"]
	reg.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	reg.load_packs()
	var fi: Array[String] = ["res://t/b.json"]
	expect(not reg.register_adapter(ContentTypeAdapter.new(&"item", fi, "items")), "load 后禁注册新 adapter（CA-4）")

func test_resolve_order_single_base() -> void:
	var reg := _make_registry()
	reg.load_packs()
	var order := reg.resolve_order()
	expect_eq(order.size(), 1, "单 base pack 拓扑序长度 1")
	expect(order.size() == 1 and String(order[0]) == "base", "顺序应含 base")

# === 索引（IX-1/IX-3/IX-4）===

func test_dialogue_by_npc_index_built() -> void:
	var reg := _make_registry()
	reg.attach_shard_registry({
		"dlg_a": {"file": "res://x.json", "npc_id": "npc_1"},
		"dlg_b": {"file": "res://y.json", "npc_id": "npc_1"},
		"dlg_c": {"file": "res://z.json"},
	})
	reg.load_packs()
	var hits := reg.query(&"dialogue_by_npc", "npc_1")
	expect_eq(hits.size(), 2, "npc_1 应命中两个对话")
	expect(hits.has("dlg_a") and hits.has("dlg_b"), "命中应回 ID 数组（IX-3）")
	expect(reg.query(&"dialogue_by_npc", "__none__").is_empty(), "未命中应空数组")
	expect(reg.query(&"bogus_index", "k").is_empty(), "十二张之外索引名应拒查")

# === 指纹（VE-1/C-4）===

func test_fingerprint_stable_and_recomputable() -> void:
	var fa: Array[String] = ["res://t/abilities.json"]
	var fp := ""
	var reg_a := _make_registry()
	_files["res://t/abilities.json"] = {"version": "1.2.0", "skills": [{"id": "abi_a"}]}
	reg_a.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	reg_a.load_packs()
	fp = reg_a.content_fingerprint()
	expect(fp.length() == 16, "指纹应为 SHA-256 前 16 位（VE-1）")
	expect(reg_a.content_fingerprint_list().has("base@1.2.0"), "指纹列表应含 base@semver（C-4 双存）")
	# 同输入复算一致
	var reg_b := _make_registry()
	_files["res://t/abilities.json"] = {"version": "1.2.0", "skills": [{"id": "abi_a"}]}
	reg_b.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	reg_b.load_packs()
	expect(reg_b.content_fingerprint() == fp, "同内容指纹可复算一致（VE-1）")
	# 内容变化指纹变化
	var reg_c := _make_registry()
	_files["res://t/abilities.json"] = {"version": "9.9.9", "skills": [{"id": "abi_a"}]}
	reg_c.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	reg_c.load_packs()
	expect(reg_c.content_fingerprint() != fp, "内容版本变化指纹应变化")

# === ContentReadyEvent（LD-2 ⑤）===

func test_ready_callback_fires_with_fingerprint() -> void:
	var reg := _make_registry()
	var fired: Array = []
	reg.set_ready_callback(func(fp: String) -> void: fired.append(fp))
	reg.load_packs()
	expect_eq(fired.size(), 1, "装载完成应发射一次 ContentReady")
	expect(fired.size() == 1 and String(fired[0]) == reg.content_fingerprint(), "载荷应为聚合指纹（COMMITTED 语义）")

# === Unload（CO-R12）===

func test_unload_base_forbidden() -> void:
	var reg := _make_registry()
	reg.load_packs()
	var r := reg.unload(&"base")
	expect(r.is_failed(), "base pack 永驻禁卸载（PK-2）")
	expect(r.has_error_code(&"CONTENT_UNLOAD_FORBIDDEN"), "错误码 CONTENT_UNLOAD_FORBIDDEN")
	expect(reg.unload(&"__nope__").has_error_code(&"CONTENT_PACK_NOT_FOUND"), "未知 pack 拒绝")

# === Validation 骨架（VA-1/VA-3）===

func test_binding_violation_recorded() -> void:
	var reg := _make_registry()
	reg.attach_shard_registry({"dlg_bad": {"file": ""}})
	reg.load_packs()
	var violations := reg.validate_all()
	expect_eq(violations.size(), 1, "空 file 指针应产生一条违规")
	var has_cor02 := false
	for v in violations:
		if v.get_code() == &"CO-R02_BINDING_MISSING":
			has_cor02 = true
	expect(has_cor02, "违规应带 rule_id（VA-3）")

# === discover 骨架（DM-4/DM-5）===

func test_discover_empty_on_dir_without_packs() -> void:
	var reg := _make_registry()
	var found := reg.discover("res://data/configs")
	expect(found.is_empty(), "无 pack.json 目录发现结果应为空（DM-5 YAGNI 骨架）")
