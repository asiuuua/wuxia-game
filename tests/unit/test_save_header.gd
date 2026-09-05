# tests/unit/test_save_header.gd
# SaveHeader 五字段契约测试（13 图 SV-1 / SV-R01）：五字段齐备 + checksum 写读可复算 + 篡改必拒。
# 安全约定：只占用 save_99.json（UI 槽位 1~6 之外），用完即删，不碰玩家真实存档。

extends TestBase
class_name TestSaveHeader

const PROBE_SLOT := 99

func after_each() -> void:
	var path := SaveManager.SAVE_DIR + "save_%d.json" % PROBE_SLOT
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	# SV-4 拓扑用例隔离过注册表 → 统一在此恢复真实注册状态（防用例间污染）
	if _saveables_touched:
		SaveManager._saveables = _saved_saveables
		_saveables_touched = false
	# SV-2 登记制用例隔离过白名单 → 统一在此恢复（防用例间污染）
	if _registry_touched:
		SaveManager._registry_whitelist = _saved_whitelist
		SaveManager._module_versions = _saved_module_versions
		_registry_touched = false

var _saved_saveables: Array = []
var _saveables_touched := false
var _saved_whitelist: Dictionary = {}
var _saved_module_versions: Dictionary = {}
var _registry_touched := false

## 隔离 SaveManager 注册表（拓扑/缺 key/SV-2 用例专用）：备份→清空，after_each 统一恢复。
## 白名单/模块版本表一并隔离：fake 键不受生产登记表拦截，注入版本表不泄漏到其他用例。
func _isolate_saveables() -> void:
	_saved_saveables = SaveManager._saveables.duplicate()
	_saveables_touched = true
	SaveManager._saveables.clear()
	if not _registry_touched:
		_saved_whitelist = SaveManager._registry_whitelist.duplicate()
		_saved_module_versions = SaveManager._module_versions.duplicate()
		_registry_touched = true
	SaveManager._registry_whitelist = {}
	SaveManager._module_versions = {}

# === SV-4/P-S2（P0 漏修补课）：注册期 key 撞车必须拒绝 ===
func test_register_duplicate_key_refused() -> void:
	var count_before := SaveManager.get_saveable_count()
	SaveManager.register_saveable(_DupKey.new())
	expect(SaveManager.get_saveable_count() == count_before, "撞 key（game_state 已占用）的注册应被拒绝")

class _DupKey extends ISaveable:
	func get_save_key() -> String:
		return "game_state"   # 与 GameState 的注册 key 撞车

# === SV-4/P-S4：加载顺序 = get_load_after() 依赖拓扑排序，禁隐式注册顺序 ===
func test_topo_order_respects_dependencies() -> void:
	_isolate_saveables()
	var log: Array = []
	var deps_b: Array[String] = ["fake_a"]
	var deps_c: Array[String] = ["fake_b"]
	# 故意按 C→B→A 反序注册：证明顺序来自拓扑排序而非注册先后
	SaveManager.register_saveable(_FakeSave.new("fake_c", deps_c, log))
	SaveManager.register_saveable(_FakeSave.new("fake_b", deps_b, log))
	SaveManager.register_saveable(_FakeSave.new("fake_a", [], log))
	var order: Array = SaveManager._topo_load_order()
	if not expect(order.size() == 3, "拓扑序应含全部 3 个模块，实际 %s" % [order]):
		return
	expect(order[0] == "fake_a", "无依赖模块应最先（实际序 %s）" % [order])
	expect(order.find("fake_a") < order.find("fake_b") and order.find("fake_b") < order.find("fake_c"),
		"依赖声明方（get_load_after）必须后于被依赖方加载（实际序 %s）" % [order])

# === SV-4/P-S4：依赖环 = 注册错误，拓扑排序必须失败（返回空） ===
func test_topo_cycle_refused() -> void:
	_isolate_saveables()
	var deps_x: Array[String] = ["fake_y"]
	var deps_y: Array[String] = ["fake_x"]
	SaveManager.register_saveable(_FakeSave.new("fake_x", deps_x, []))
	SaveManager.register_saveable(_FakeSave.new("fake_y", deps_y, []))
	expect(SaveManager._topo_load_order().is_empty(), "依赖环必须导致拓扑排序失败（返回空数组，读端拒读）")

# === SV-4/P-S4：拓扑序读档 —— 依赖方后加载（load 调用顺序断言） ===
func test_load_calls_follow_topo_order() -> void:
	_isolate_saveables()
	var log: Array = []
	var deps_b: Array[String] = ["fake_a"]
	SaveManager.register_saveable(_FakeSave.new("fake_b", deps_b, log))   # 反序注册
	SaveManager.register_saveable(_FakeSave.new("fake_a", [], log))
	var body := {"fake_a": {"v": "a"}, "fake_b": {"v": "b"}}
	_write_probe_save(body)
	expect(SaveManager.load_from_slot(PROBE_SLOT), "双模块档读档应成功")
	expect(log == ["fake_a", "fake_b"], "load 调用顺序应为拓扑序 [fake_a, fake_b]（依赖方后加载），实际 %s" % [log])

# === SV-4/P-S12：已注册但档内缺 key（老档新模块）→ 跳过该模块，读档不失败 ===
func test_missing_key_module_skipped() -> void:
	_isolate_saveables()
	var log: Array = []
	var deps_b: Array[String] = ["fake_a"]
	SaveManager.register_saveable(_FakeSave.new("fake_a", [], log))
	SaveManager.register_saveable(_FakeSave.new("fake_b", deps_b, log))
	# 档内只有 fake_a（模拟 1.0 老档没有后来新增的 fake_b 模块）
	var body := {"fake_a": {"v": "a"}}
	_write_probe_save(body)
	expect(SaveManager.load_from_slot(PROBE_SLOT), "缺 key（老档新模块）应按默认值兜底，读档成功")
	expect(log == ["fake_a"], "缺 key 模块 fake_b 应被跳过，仅 fake_a 被加载，实际 %s" % [log])

## 构造带合法 checksum 的探针档（meta 五字段齐备），供拓扑读档用例使用
func _write_probe_save(body: Dictionary) -> void:
	var meta := {
		"save_version": SaveManager.SAVE_VERSION,
		"game_version": "",
		"content_version": "dev",
		"timestamp": 0,
		"checksum": SaveManager._body_checksum(body),
	}
	var save_data := {"meta": meta}
	for k in body:
		save_data[k] = body[k]
	var path := SaveManager.SAVE_DIR + "save_%d.json" % PROBE_SLOT
	expect(SaveManager._write_json(path, save_data, PROBE_SLOT), "探针档写入应成功")

## 拓扑/缺 key 用例的内存假存档模块（SV-4 强类型：必须 extends ISaveable）
class _FakeSave extends ISaveable:
	var key: String = ""
	var deps: Array[String] = []
	var load_log: Array = []   # 共享引用：由用例注入，load() 时记录调用顺序
	var last_payload: Dictionary = {}   # SV-2 用例：记录最近一次 load 收到的解包后载荷
	func _init(k: String, d: Array[String] = [], log_ref: Array = []) -> void:
		key = k
		deps = d
		load_log = log_ref
	func get_save_key() -> String:
		return key
	func get_load_after() -> Array[String]:
		return deps
	func save() -> Dictionary:
		return {"v": key}
	func load(data: Dictionary) -> void:
		load_log.append(key)
		last_payload = data

func test_meta_has_five_fields() -> void:
	var d := SaveManager._build_save_data("命名测试")
	var meta: Dictionary = d["meta"]
	for field in ["save_version", "game_version", "content_version", "timestamp", "checksum"]:
		expect(meta.has(field) and str(meta[field]) != "", "meta 应含非空字段 %s" % field)
	expect(str(meta["save_version"]) == SaveManager.SAVE_VERSION, "save_version 应为当前版本")
	expect(str(meta["game_version"]) == str(ProjectSettings.get_setting("application/config/version", "")),
		"game_version 应取自 ProjectSettings（只记录不阻断）")
	expect(meta.has("custom_name") and str(meta["custom_name"]) == "命名测试", "custom_name 扩展字段应保留")

func test_checksum_detects_tamper() -> void:
	var d := SaveManager._build_save_data()
	expect(SaveManager._checksum_ok(d), "未篡改存档应通过 checksum")
	for k in d:
		if k != "meta":
			(d[k] as Dictionary)["__tampered__"] = 1
			break
	expect(not SaveManager._checksum_ok(d), "正文被篡改后 checksum 应不通过")

func test_write_read_checksum_roundtrip() -> void:
	var d := SaveManager._build_save_data()
	var path := SaveManager.SAVE_DIR + "save_%d.json" % PROBE_SLOT
	expect(SaveManager._write_json(path, d, PROBE_SLOT), "原子写应成功")
	var loaded: Dictionary = SaveManager._load_json(path)
	expect(not loaded.is_empty() and SaveManager._checksum_ok(loaded), "写盘回读应通过 checksum 双验")

func test_tampered_save_refused() -> void:
	var d := SaveManager._build_save_data()
	var path := SaveManager.SAVE_DIR + "save_%d.json" % PROBE_SLOT
	expect(SaveManager._write_json(path, d, PROBE_SLOT), "原子写应成功")
	# 篡改正文且保持合法 JSON（注入新顶层键）：checksum 必不一致
	var parsed_v: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not expect(parsed_v is Dictionary, "探针档应可解析"):
		return
	var parsed: Dictionary = parsed_v
	parsed["__injected_tamper__"] = 1
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(parsed))
	f.close()
	# SV-1：checksum 不一致 → .bak 抢救链；探针槽无 .bak → 拒读（禁静默尽力解析）
	expect(not SaveManager.load_from_slot(PROBE_SLOT), "checksum 不一致且无 .bak → 应拒读")

# === SV-2 二段式 Body：写端每模块键包 {schema_version, data} ===
func test_body_two_phase_wrap() -> void:
	var d := SaveManager._build_save_data()
	var module_keys := 0
	for k in d:
		if k == "meta":
			continue
		module_keys += 1
		var wrapped_v: Variant = d[k]
		if not expect(wrapped_v is Dictionary, "模块键 %s 应为包装 Dictionary" % k):
			continue
		var wrapped: Dictionary = wrapped_v
		expect(str(wrapped.get("schema_version", "")) == SaveManager.MODULE_SCHEMA_VERSION,
			"模块键 %s 应带当前模块版本 %s（实际 %s）" % [k, SaveManager.MODULE_SCHEMA_VERSION, str(wrapped.get("schema_version", ""))])
		expect(wrapped.get("data", null) is Dictionary, "模块键 %s 的 data 应为 Dictionary" % k)
	expect(module_keys >= 12, "真实装配下 Body 应含 12 个模块键（实际 %d）" % module_keys)

# === SV-2 读端：legacy 裸载荷兜底兼容（1.2.0 前老档漏网形态） ===
func test_legacy_module_payload_compat() -> void:
	expect(SaveManager._resolve_module_payload("any_key", {"v": 1}) is Dictionary
		and (SaveManager._resolve_module_payload("any_key", {"v": 1}) as Dictionary).get("v", 0) == 1,
		"legacy 裸载荷应原样透传（1.0.0 渐进兼容）")

# === SV-2 读端：未来模块版本拒读 + 缺 data 拒读 + 非 Dictionary 拒读 ===
func test_bad_module_payloads_refused() -> void:
	expect(SaveManager._resolve_module_payload("any_key", {"schema_version": "9.9.9", "data": {}}) == null,
		"模块 schema_version 高于当前应拒读（防新档被旧逻辑写坏）")
	expect(SaveManager._resolve_module_payload("any_key", {"schema_version": "1.0.0"}) == null,
		"二段式载荷缺 data 应拒读")
	expect(SaveManager._resolve_module_payload("any_key", "not_a_dict") == null,
		"载荷非 Dictionary 应拒读")

# === SV-2 模块迁移链：模块升版后，低位版本沿 register_module_migration 注册表升级，断链拒读 ===
func test_module_migration_chain() -> void:
	_isolate_saveables()
	SaveManager._module_versions["fake_m"] = "1.1.0"   # 模拟模块 fake_m 已升版至 1.1.0
	var step := func(carried: Dictionary) -> Dictionary:
		var d: Dictionary = carried["data"]
		d["migrated"] = true
		return {"data": d}
	var ok: bool = SaveManager.register_module_migration({
		"key": "fake_m", "from": "1.0.0", "to": "1.1.0", "step": step,
	})
	expect(ok, "合法模块迁移条目应登记成功")
	var out_v: Variant = SaveManager._resolve_module_payload("fake_m", {"schema_version": "1.0.0", "data": {"v": 1}})
	expect(out_v is Dictionary and (out_v as Dictionary).get("migrated", false) == true and int((out_v as Dictionary).get("v", 0)) == 1,
		"1.0.0 模块载荷应沿链升到 1.1.0 且数据保留（实际 %s）" % [out_v])
	expect(SaveManager._resolve_module_payload("fake_m", {"schema_version": "1.0.5", "data": {}}) == null,
		"断链版本（无 1.0.5 迁移步骤）应拒读")

# === SV-2 端到端：1.1.0 老档（裸键+无 checksum）走「checksum放行→迁移包装→分发解包」全链读回 ===
func test_legacy_1_1_0_save_end_to_end() -> void:
	_isolate_saveables()
	var log: Array = []
	var mod_a := _FakeSave.new("legacy_a", [], log)
	SaveManager.register_saveable(mod_a)
	SaveManager._registry_whitelist["legacy_a"] = true
	# 1.1.0 形态：裸键载荷、meta 无 checksum（当时还没有）、版本号 1.1.0
	var save_data := {
		"meta": {"save_version": "1.1.0", "timestamp": 1750000000},
		"legacy_a": {"hp": 88, "bag": ["nv_item_hairpin"]},
	}
	var path := SaveManager.SAVE_DIR + "save_%d.json" % PROBE_SLOT
	expect(SaveManager._write_json(path, save_data, PROBE_SLOT), "1.1.0 老档探针写入应成功")
	expect(SaveManager.load_from_slot(PROBE_SLOT), "1.1.0 老档应经迁移链成功读回")
	expect(mod_a.last_payload.get("hp", 0) == 88 and (mod_a.last_payload.get("bag", []) as Array).size() == 1,
		"解包后载荷应原样抵达模块（数据零丢失，实际 %s）" % [mod_a.last_payload])

# === SV-2 登记制：白名单在而键未登记 → 拒注册（禁私自扩键） ===
func test_unregistered_key_refused() -> void:
	_isolate_saveables()
	SaveManager._registry_whitelist = {"known_a": true}
	SaveManager.register_saveable(_FakeSave.new("known_a", [], []))
	expect(SaveManager.get_saveable_count() == 1, "已登记 key 应注册成功")
	SaveManager.register_saveable(_FakeSave.new("known_a", [], []))
	expect(SaveManager.get_saveable_count() == 1, "同 key 二次注册应被撞车检查拦下")
	SaveManager.register_saveable(_FakeSave.new("unknown_z", [], []))
	expect(SaveManager.get_saveable_count() == 1, "未登记 key 应被拒绝注册（SV-2 禁私自扩键）")
