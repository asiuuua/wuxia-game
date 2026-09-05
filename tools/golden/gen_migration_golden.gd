# tools/golden/gen_migration_golden.gd
# 迁移 golden 生产器（13 图 SV-3 / SV-R03 / 宪法 §32：每次 Migration 必须测试 Input、Expected Output）。
# 职责：构造 1.0.0 形状的代表性存档 Input，跑真实迁移链得到 Expected，双双落盘 JSON 夹具；
#       夹具入库后人审冻结，test_save_migration.gd 逐轮用「Input 跑迁移 == Expected」守门。
# 用法：godot --headless --path <项目根> res://tools/golden/gen_migration_golden.tscn
# 约定：新增迁移步骤（SAVE_VERSION 升版）时，在本文件追加对应构造段并重跑本场景，
#       产出新一对夹具；旧夹具永不删除（SBP-R08 同款精神：基准与夹具都是常绿资产）。
extends Node

const OUT_DIR := "res://tests/golden/migrations/"

func _ready() -> void:
	var input := _build_1_0_0_input()
	var expected: Dictionary = input.duplicate(true)
	var ok: bool = SaveManager._migrate_if_needed(expected)
	if not ok:
		push_error("[golden] 迁移失败，无法产出 expected 夹具")
		get_tree().quit(1)
		return
	DirAccess.make_dir_recursive_absolute(OUT_DIR)
	_write(OUT_DIR + "migrate_1_0_0_to_1_1_0.input.json", input)
	_write(OUT_DIR + "migrate_1_0_0_to_1_1_0.expected.json", expected)
	print("[golden] 已产出迁移 golden 对：migrate_1_0_0_to_1_1_0.{input,expected}.json（入库前请人审）")
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

func _write(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("[golden] 无法写入 %s" % path)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(data, "\t"))
	f.close()
