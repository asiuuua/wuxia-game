# tests/unit/test_save_migration.gd
# 第二阶段整改单测（2026-09-04）：存档版本迁移器 + 读档恢复区域。
# 覆盖：老版本迁移链 / 无版本遗留档 / 更新版本拒读 / last_region_id 持久化与非法回退。

extends TestBase
class_name TestSaveMigration

func test_current_version_passes_through() -> void:
	var data := {"meta": {"save_version": SaveManager.SAVE_VERSION}, "game_state": {}}
	expect(SaveManager._migrate_if_needed(data), "当前版本存档应直接通过")
	expect(str(data["meta"]["save_version"]) == SaveManager.SAVE_VERSION, "版本号不应被改动")

func test_legacy_no_version_migrates() -> void:
	# 无版本号 = 1.0.0 遗留档：迁移通过并补写当前版本号
	var data := {"meta": {}, "game_state": {"global_flags": {}}}
	expect(SaveManager._migrate_if_needed(data), "无版本号遗留档应迁移成功")
	expect(str(data["meta"]["save_version"]) == SaveManager.SAVE_VERSION, "迁移后应补写当前版本号")

func test_older_known_version_migrates() -> void:
	var data := {"meta": {"save_version": "1.0.0"}}
	expect(SaveManager._migrate_if_needed(data), "已知老版本 1.0.0 应迁移成功")
	expect(str(data["meta"]["save_version"]) == SaveManager.SAVE_VERSION, "迁移后应为当前版本")

func test_future_version_rejected() -> void:
	# 更新版本的档：拒绝读档（防旧逻辑写坏新数据），绝不静默解析
	var data := {"meta": {"save_version": "9.9.9"}}
	expect(not SaveManager._migrate_if_needed(data), "未来版本存档应被拒绝")

func test_game_state_last_region_roundtrip() -> void:
	GameState.set_last_region("region_misty_town")
	var d := GameState.save()
	expect(str(d.get("last_region_id", "")) == "region_misty_town", "save() 应包含 last_region_id")
	# 模拟读档：load 后恢复
	GameState.load({"last_region_id": "region_misty_town"})
	expect(GameState.get_last_region() == "region_misty_town", "load() 应恢复 last_region_id")

func test_game_state_invalid_region_falls_back() -> void:
	# 1.1.0 迁移兜底：last_region_id 指向不存在区域（如手工改档）→ 回退起始区域
	# （F4/CP-2 起注册表已无裸名，回退目标=region_newbie_village）
	GameState.load({"last_region_id": "__no_such_region__"})
	expect(GameState.get_last_region() == "region_newbie_village", "非法区域应回退 region_newbie_village")
	GameState.load({})
	expect(GameState.get_last_region() == "region_newbie_village", "缺字段应回退 region_newbie_village")

# === SV-2 模块迁移链（F4/CP-2 2026-09-06）：game_state 1.0.0→1.1.0 裸名区域升 region_* ===
## SV-R03 同律：模块迁移步骤必带 Input/Expected golden 对（人审冻结）。
## input=存档文件中 game_state 键的二段式包装原样；expected=_resolve_module_payload 解析后的载荷。
func test_module_game_state_migration_golden_pair() -> void:
	var input_v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/golden/migrations/module_game_state_1_0_0_to_1_1_0.input.json"))
	var expected_v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/golden/migrations/module_game_state_1_0_0_to_1_1_0.expected.json"))
	if not expect(input_v is Dictionary and expected_v is Dictionary, "模块 golden 夹具应存在且可解析"):
		return
	var resolved: Variant = SaveManager._resolve_module_payload("game_state", input_v)
	if not expect(resolved is Dictionary, "模块 1.0.0 载荷应沿模块链迁移成功"):
		return
	# JSON.stringify 默认键排序，两侧字符串比较与键序无关
	expect(JSON.stringify(resolved) == JSON.stringify(expected_v), "模块迁移结果应与 golden expected 完全一致")

func test_module_migration_rewrites_misty_town() -> void:
	var wrapper := {"schema_version": "1.0.0", "data": {"last_region_id": "misty_town", "global_flags": {}}}
	var resolved: Variant = SaveManager._resolve_module_payload("game_state", wrapper)
	expect(resolved is Dictionary and str((resolved as Dictionary).get("last_region_id", "")) == "region_misty_town",
		"裸名 misty_town 应被模块迁移改写为 region_misty_town")

func test_module_migration_passes_prefixed_through() -> void:
	var wrapper := {"schema_version": "1.0.0", "data": {"last_region_id": "region_snow", "global_flags": {}}}
	var resolved: Variant = SaveManager._resolve_module_payload("game_state", wrapper)
	expect(resolved is Dictionary and str((resolved as Dictionary).get("last_region_id", "")) == "region_snow",
		"已带 region_ 前缀的值应原样透传不被改写")

func test_module_version_registered_for_new_saves() -> void:
	expect(SaveManager._module_current_version("game_state") == "1.1.0",
		"game_state 模块版本应已登记 1.1.0（新档戳印口径）")

# === P-S3 退役：未知版本一律拒读（13 图 SV-3，禁「按当前版本尽力解析」盖戳） ===
func test_unknown_version_rejected() -> void:
	# 0.9.9 小于当前版且非未来版：注册表无 from=0.9.9 的步骤 → 未知版本 → 拒读
	var data := {"meta": {"save_version": "0.9.9"}}
	expect(not SaveManager._migrate_if_needed(data), "未知版本 0.9.9 应被拒读")

func test_unknown_version_not_stamped() -> void:
	# 拒读时不得改写版本号——盖当前版戳会让后续写入永久污染原档
	var data := {"meta": {"save_version": "0.9.9"}}
	SaveManager._migrate_if_needed(data)
	expect(str(data["meta"]["save_version"]) == "0.9.9", "拒读后版本号应保持原样，不被盖章")

# === SV-R03：每条迁移步骤必带 Input/Expected golden 对（生产器 tools/golden/ 产出，人审冻结） ===
## 对名动态跟随当前 SAVE_VERSION（migrate_<from>_to_<SAVE_VERSION>）；历史对永不删除供审计。
## 两对覆盖：1.0.0 遗留档走完整链 / 1.1.0 中间版本走尾部链（SV-2 批次起含二段式包装迁移）。
func test_migration_golden_pair() -> void:
	_run_golden_pair("1_0_0")
	_run_golden_pair("1_1_0")

func _run_golden_pair(from_seg: String) -> void:
	var stem := "migrate_%s_to_%s" % [from_seg, SaveManager.SAVE_VERSION]
	var input_v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/golden/migrations/%s.input.json" % stem))
	var expected_v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/golden/migrations/%s.expected.json" % stem))
	if not expect(input_v is Dictionary and expected_v is Dictionary, "golden 夹具 %s 应存在且可解析" % stem):
		return
	var migrated: Dictionary = input_v
	var expected: Dictionary = expected_v
	expect(SaveManager._migrate_if_needed(migrated), "golden input（%s）应沿注册表迁移成功" % from_seg)
	# JSON.stringify 默认键排序，两侧字符串比较与键序无关
	expect(JSON.stringify(migrated) == JSON.stringify(expected), "迁移结果应与 golden expected 完全一致（%s）" % stem)

# === SV-2 二段式 Body：迁移后模块键应带 {schema_version, data} 包装（1.2.0 起格式） ===
func test_migration_wraps_module_payloads() -> void:
	var input_v: Variant = JSON.parse_string(
		FileAccess.get_file_as_string("res://tests/golden/migrations/migrate_1_1_0_to_%s.input.json" % SaveManager.SAVE_VERSION))
	if not expect(input_v is Dictionary, "1.1.0 golden input 应存在且可解析"):
		return
	var migrated: Dictionary = input_v
	expect(SaveManager._migrate_if_needed(migrated), "1.1.0 input 应迁移成功")
	var player_v: Variant = migrated.get("player", null)
	if not expect(player_v is Dictionary and (player_v as Dictionary).has("schema_version"), "迁移后 player 键应为二段式包装"):
		return
	var wrapped: Dictionary = player_v
	expect(str(wrapped["schema_version"]) == SaveManager.MODULE_SCHEMA_VERSION, "包装 schema_version 应为模块起点版")
	expect((wrapped as Dictionary).get("data", null) is Dictionary and ((wrapped["data"] as Dictionary).has("player_name")),
		"包装 data 应保留原模块字段（player_name 可回读）")
