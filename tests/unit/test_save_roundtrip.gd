# tests/unit/test_save_roundtrip.gd
# 存档往返与安全测试：守住「存了能读回来」以及「写坏了能救回来」两条底线
# 安全约定：测试会占用槽位 6 与 auto_1，执行前后做快照与还原，不破坏玩家真实存档

extends TestBase

const TEST_SLOT := 6
const SAVE_DIR := "user://saves/"

# === 玩家状态往返 ===
func test_player_state_roundtrip() -> void:
	var ps: PlayerState = GameManager.player_state
	ps.init_default("存档测试侠", 1)
	ps.level = 7
	ps.silver = 1234
	ps.hp = 66
	var data: Dictionary = ps.save()
	ps.init_default("还原前", 1)
	ps.load(data)
	expect_eq(ps.level, 7, "等级应还原")
	expect_eq(ps.silver, 1234, "银两应还原")
	expect_eq(ps.hp, 66, "气血应还原")
	expect(ps.player_name == "存档测试侠", "名字应还原，实际 %s" % ps.player_name)

# === 背包往返 ===
func test_inventory_roundtrip() -> void:
	var inv = GameManager.inventory_service
	inv.reset()
	var ok: bool = inv.add_item("pill_heal_xiaohuan_001", 5, "test")
	expect(ok, "添加物品应成功")
	var before: int = inv.get_item_count("pill_heal_xiaohuan_001")
	var data: Dictionary = inv.save()
	inv.reset()
	inv.load(data)
	expect_eq(inv.get_item_count("pill_heal_xiaohuan_001"), before, "背包物品数应还原")

# === 手动存档往返（走真实文件路径） ===
func test_save_manager_roundtrip() -> void:
	var path := SAVE_DIR + "save_%d.json" % TEST_SLOT
	var snap: Array = _snap(path)
	GameManager.player_state.level = 5
	expect(SaveManager.save_to_slot(TEST_SLOT, "测试存档"), "存档应成功")
	GameManager.player_state.level = 99
	expect(SaveManager.load_from_slot(TEST_SLOT), "读档应成功")
	expect_eq(GameManager.player_state.level, 5, "等级应从存档还原为 5")
	_restore(path, snap)

# === 自动存档往返：此前 quick_save 能存不能读，此用例专门守住它 ===
func test_auto_save_roundtrip() -> void:
	var path := SAVE_DIR + "auto_1.json"
	var snap: Array = _snap(path)
	GameManager.player_state.level = 3
	expect(SaveManager.quick_save(), "快速存档应成功")
	GameManager.player_state.level = 88
	expect(SaveManager.load_auto_save(1), "自动存档应能读回")
	expect_eq(GameManager.player_state.level, 3, "等级应从自动存档还原为 3")
	_restore(path, snap)

# === 原子写：第二次写入应留下 .bak，且不留 .tmp 残渣 ===
func test_atomic_write_leaves_backup() -> void:
	var path := SAVE_DIR + "save_%d.json" % TEST_SLOT
	var snap: Array = _snap(path)
	SaveManager.save_to_slot(TEST_SLOT, "第一次")
	GameManager.player_state.level = 11
	SaveManager.save_to_slot(TEST_SLOT, "第二次")
	expect(FileAccess.file_exists(path + ".bak"), "覆盖写入应生成 .bak 备份")
	expect(not FileAccess.file_exists(path + ".tmp"), "正常写入后不应残留 .tmp")
	_restore(path, snap)
	_remove(path + ".bak")

# === 损坏回退：主档被写坏时应自动从 .bak 抢救 ===
func test_corrupted_save_falls_back_to_bak() -> void:
	var path := SAVE_DIR + "save_%d.json" % TEST_SLOT
	var snap: Array = _snap(path)
	GameManager.player_state.level = 21
	SaveManager.save_to_slot(TEST_SLOT, "好的")
	GameManager.player_state.level = 22
	SaveManager.save_to_slot(TEST_SLOT, "更好的")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f != null:
		f.store_string("{ 这不是合法 JSON")
		f.close()
	expect(SaveManager.load_from_slot(TEST_SLOT), "主档损坏后应能从备份恢复")
	expect_eq(GameManager.player_state.level, 21, "应还原为备份中的等级 21")
	_restore(path, snap)
	_remove(path + ".bak")

# === 工具 ===
func _snap(path: String) -> Array:
	var existed := FileAccess.file_exists(path)
	var text := ""
	if existed:
		var f := FileAccess.open(path, FileAccess.READ)
		if f != null:
			text = f.get_as_text()
			f.close()
	return [existed, text]

func _restore(path: String, snap: Array) -> void:
	var existed: bool = bool(snap[0])
	var text: String = String(snap[1])
	if existed:
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(text)
			f.close()
	elif FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)

func _remove(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
