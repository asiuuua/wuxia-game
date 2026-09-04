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
	GameState.set_last_region("misty_town")
	var d := GameState.save()
	expect(str(d.get("last_region_id", "")) == "misty_town", "save() 应包含 last_region_id")
	# 模拟读档：load 后恢复
	GameState.load({"last_region_id": "misty_town"})
	expect(GameState.get_last_region() == "misty_town", "load() 应恢复 last_region_id")

func test_game_state_invalid_region_falls_back() -> void:
	# 1.1.0 迁移兜底：last_region_id 指向不存在区域（如手工改档）→ 回退起始区域
	GameState.load({"last_region_id": "__no_such_region__"})
	expect(GameState.get_last_region() == "newbie_village", "非法区域应回退 newbie_village")
	GameState.load({})
	expect(GameState.get_last_region() == "newbie_village", "缺字段应回退 newbie_village")
