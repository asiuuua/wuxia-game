# tests/unit/test_content_dod.gd
# 05 图批2 DoD3~6（2026-09-06，D1）：规则表 JSON 化 / Build 期索引 / fingerprint 注入链 / Mod 拒载。
# 假 loader 范式同 test_content_registry（零真实磁盘——DoD6 的假 pack 用 user:// 临时目录，用完即删）。

extends TestBase
class_name TestContentDoD

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

func _rule_table() -> Dictionary:
	var f := FileAccess.open("res://data/configs/content_validation_rules.json", FileAccess.READ)
	return JSON.parse_string(f.get_as_text())

# === DoD3：五层规则表 JSON 化——L1 Schema 执行器按表抓缺字段 ===
func test_dod3_schema_layer_enforced_from_rule_table() -> void:
	var reg := _make_registry()
	reg.load_validation_rules(_rule_table())
	_files["res://t/abilities.json"] = {"version": "1.0.0",
		"skills": [{"id": "abi_ok", "name": "拳", "type": "attack"}, {"id": "abi_bad", "type": "attack"}]}
	_files["res://t/items.json"] = {"version": "1.0.0", "items": [{"id": "itm_ok", "name": "药", "type": "pill"}]}
	var fa: Array[String] = ["res://t/abilities.json"]
	var fi: Array[String] = ["res://t/items.json"]
	reg.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	reg.register_adapter(ContentTypeAdapter.new(&"item", fi, "items", "id", "物品"))
	reg.load_packs()
	var violations := reg.validate_all()
	var codes := []
	for v in violations:
		codes.append(str(v.get_code()))
	expect(codes.has("VA1-REQ-ADAPTER"), "缺 name 的 ability 应被 L1 规则表执行器抓获（实际 %s）" % [codes])
	var bad_fields := []
	for v in violations:
		if str(v.get_code()) == "VA1-REQ-ADAPTER":
			bad_fields.append(str(v.get_field()))
	expect(bad_fields.has("ability.name"), "违规 field 应定位到 ability.name（实际 %s）" % [bad_fields])

# === DoD4：Build 期索引注入（CO-R03 运行期只查不建） ===
func test_dod4_attach_index_and_query() -> void:
	var reg := _make_registry()
	var tbl := {"nv_npc_chief": ["newbie_village"], "npc_hunter": ["newbie_village"]}
	reg.attach_index("npc_by_region", tbl)
	_files["res://t/abilities.json"] = {"version": "1.0.0", "skills": [{"id": "abi_a"}]}
	var fa: Array[String] = ["res://t/abilities.json"]
	reg.register_adapter(ContentTypeAdapter.new(&"ability", fa, "skills", "id", "技能"))
	reg.load_packs()
	var got := reg.query(&"npc_by_region", "nv_npc_chief")
	expect(got.has("newbie_village"), "Build 期注入的 npc_by_region 应可查（实际 %s）" % [got])
	expect(reg.query(&"npc_by_region", "不存在").is_empty(), "无键应回空数组（CO-R04）")

func test_dod4_unregistered_index_refused() -> void:
	var reg := _make_registry()
	reg.attach_index("hack_index", {"a": ["b"]})
	expect(reg.query(&"hack_index", "a").is_empty(),
		"IX-1 登记表外的索引应被拒（query 恒空，CO-R04）")

# === DoD5：content_version 注入链（provenance 缺席 → provider fingerprint → dev） ===
func test_dod5_content_version_provider_chain() -> void:
	SaveManager._content_version_cache = ""   # 清缓存（前置用例可能已缓存真 fingerprint）
	SaveManager.set_content_version_provider(func() -> String: return "fp_test_1234")
	var reg := _make_registry()
	reg.attach_shard_registry({})
	expect(str(SaveManager._content_version()).begins_with("fp_test"), "provider 注入后 content_version 应取 fingerprint（实际 %s）" % SaveManager._content_version())
	SaveManager.set_content_version_provider(Callable())   # 清场：还原默认链
	SaveManager._content_version_cache = ""

# === DoD6：Mod 禁代码——假 pack 含 .gd 应拒载并列证（CO-R07） ===
func test_dod6_mod_with_code_rejected() -> void:
	var mod_dir := "user://dod6_fake_mod"
	DirAccess.make_dir_recursive_absolute(mod_dir)
	var mf := FileAccess.open(mod_dir + "/pack.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify({"pack_id": "evil_pack", "type": "mod", "version": "1.0.0"}))
	mf.close()
	var gd := FileAccess.open(mod_dir + "/cheat.gd", FileAccess.WRITE)
	gd.store_string("extends Node")
	gd.close()
	var reg := _make_registry()
	_files[mod_dir + "/pack.json"] = {"pack_id": "evil_pack", "type": "mod", "version": "1.0.0"}
	var found := reg.discover(mod_dir)
	var names := []
	for m in found:
		names.append(str(m.pack_id))
	expect(not names.has("evil_pack"), "含代码的 mod 应被拒载（CO-R07，实际 %s）" % [names])
	var codes := []
	for v in reg.validate_all():
		codes.append(str(v.get_code()))
	expect(codes.has("CO-R07_MOD_CODE"), "拒载应留 CO-R07 违规证据（实际 %s）" % [codes])
	# 清场
	for f in [mod_dir + "/pack.json", mod_dir + "/cheat.gd"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(mod_dir)

func test_dod6_clean_mod_accepted() -> void:
	var mod_dir := "user://dod6_clean_mod"
	DirAccess.make_dir_recursive_absolute(mod_dir)
	var mf := FileAccess.open(mod_dir + "/pack.json", FileAccess.WRITE)
	mf.store_string(JSON.stringify({"pack_id": "clean_pack", "type": "mod", "version": "1.0.0"}))
	mf.close()
	var dj := FileAccess.open(mod_dir + "/data.json", FileAccess.WRITE)
	dj.store_string("{}")
	dj.close()
	var reg := _make_registry()
	_files[mod_dir + "/pack.json"] = {"pack_id": "clean_pack", "type": "mod", "version": "1.0.0"}
	var found := reg.discover(mod_dir)
	var names := []
	for m in found:
		names.append(str(m.pack_id))
	expect(names.has("clean_pack"), "纯数据 mod 应被发现（实际 %s）" % [names])
	# 清场
	for f in [mod_dir + "/pack.json", mod_dir + "/data.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	DirAccess.remove_absolute(mod_dir)


# === 批C 收编核验：ConfigManager facade 与 Registry store 同源（ability 样例） ===
func test_batchc_facade_reads_registry_store() -> void:
	if not expect(ConfigManager.content_registry != null, "生产装配下 Registry 应就绪"):
		return
	var ab_ids: Array = ConfigManager.content_registry.all_ids(&"ability")
	if not expect(ab_ids.size() > 0, "ability store 应非空（生产数据）"):
		return
	var probe: String = str(ab_ids[0])
	var via_facade: Dictionary = ConfigManager.get_ability(probe)
	var via_registry: Dictionary = ConfigManager.content_registry.adapter_store(&"ability").get(probe, {})
	expect(str(via_facade.get("id", "")) == probe and via_facade == via_registry,
		"facade get_ability 应与 Registry store 同源同值（%s）" % probe)
