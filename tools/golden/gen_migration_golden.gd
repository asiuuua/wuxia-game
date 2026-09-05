# tools/golden/gen_migration_golden.gd
# 迁移 golden 生产器（13 图 SV-3 / SV-R03 / 宪法 §32：每次 Migration 必须测试 Input、Expected Output）。
# 职责：构造 1.0.0 与 1.1.0 形状的代表性存档 Input，跑真实迁移链得到 Expected，双双落盘 JSON 夹具；
#       夹具入库后人审冻结，test_save_migration.gd 逐轮用「Input 跑迁移 == Expected」守门。
# 用法：godot --headless --path <项目根> res://tools/golden/gen_migration_golden.tscn
# 约定：SAVE_VERSION 升版时，在本文件追加对应构造段并重跑本场景，产出新一对夹具；
#       对名动态跟随当前 SAVE_VERSION（migrate_<from>_to_<SAVE_VERSION>），旧夹具永不删除
#       （SBP-R08 同款精神：基准与夹具都是常绿资产，历史对保留供审计）。
extends Node

const OUT_DIR := "res://tests/golden/migrations/"

func _ready() -> void:
	var failed := false
	# 1.0.0 遗留档：走完整链（1.0.0→1.1.0→1.2.0 ... 直到当前 SAVE_VERSION）
	var input_100 := _build_1_0_0_input()
	var expected_100: Dictionary = input_100.duplicate(true)
	if not SaveManager._migrate_if_needed(expected_100):
		push_error("[golden] 1.0.0 input 迁移失败，无法产出 expected 夹具")
		failed = true
	else:
		_write(OUT_DIR + "migrate_1_0_0_to_%s.input.json" % SaveManager.SAVE_VERSION, input_100)
		_write(OUT_DIR + "migrate_1_0_0_to_%s.expected.json" % SaveManager.SAVE_VERSION, expected_100)
	# 1.1.0 档：走 1.1.0→当前 链（SV-2 批次新增：覆盖「补 last_region_id 之后的中间版本」）
	var input_110 := _build_1_1_0_input()
	var expected_110: Dictionary = input_110.duplicate(true)
	if not SaveManager._migrate_if_needed(expected_110):
		push_error("[golden] 1.1.0 input 迁移失败，无法产出 expected 夹具")
		failed = true
	else:
		_write(OUT_DIR + "migrate_1_1_0_to_%s.input.json" % SaveManager.SAVE_VERSION, input_110)
		_write(OUT_DIR + "migrate_1_1_0_to_%s.expected.json" % SaveManager.SAVE_VERSION, expected_110)
	if failed:
		get_tree().quit(1)
		return
	print("[golden] 已产出迁移 golden 对：migrate_1_0_0_to_%s 与 migrate_1_1_0_to_%s（入库前请人审）" % [SaveManager.SAVE_VERSION, SaveManager.SAVE_VERSION])
	get_tree().quit(0)

## 构造 1.0.0 形状代表性存档：meta 无 checksum/game_version/content_version（当时还没有），
## game_state 缺 last_region_id（1.1.0 才引入）。字段形状对照 game_state.gd save() 真源裁剪。
func _build_1_0_0_input() -> Dictionary:
	return {
		"meta": {
			"save_version": "1.0.0",
			"timestamp": 1750000000,
			"custom_name": "golden样本",
		},
		"player": {
			"player_name": "golden侠",
			"level": 3,
			"silver": 250,
			"hp": 88,
			"mp": 30,
		},
		"world_time": {
			"day": 4,
			"hour": 15,
			"minute": 30,
		},
		"game_state": {
			"global_flags": {"nv_wolf_defeated": true},
			"unit_runtime": {},
			"difficulty": 1,
			"last_safe_point": {"marker": "town", "text_id": "safe_town"},
			"xiaozhang_collateral": [],
			"quest_phase": 1,
		},
	}

## 构造 1.1.0 形状代表性存档：= 1.0.0 形状 + game_state.last_region_id（1.1.0 引入）。
## SV-2 批次（1.2.0）前的最终裸键形态：模块值直接是 data dict，无 {schema_version, data} 包装。
func _build_1_1_0_input() -> Dictionary:
	var d := _build_1_0_0_input()
	(d["meta"] as Dictionary)["save_version"] = "1.1.0"
	(d["meta"] as Dictionary)["game_version"] = "0.5.0"
	(d["game_state"] as Dictionary)["last_region_id"] = "newbie_village"
	return d

func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[golden] 无法写入 %s" % path)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
