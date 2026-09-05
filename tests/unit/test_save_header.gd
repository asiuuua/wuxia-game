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

# === SV-4/P-S2（P0 漏修补课）：注册期 key 撞车必须拒绝 ===
func test_register_duplicate_key_refused() -> void:
	var count_before := SaveManager.get_saveable_count()
	SaveManager.register_saveable(_DupKey.new())
	expect(SaveManager.get_saveable_count() == count_before, "撞 key（game_state 已占用）的注册应被拒绝")

class _DupKey:
	func get_save_key() -> String:
		return "game_state"   # 与 GameState 的注册 key 撞车
	func save() -> Dictionary:
		return {}
	func load(_d: Dictionary) -> void:
		pass

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
