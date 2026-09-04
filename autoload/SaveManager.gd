# autoload/SaveManager.gd
# 存档管理器：注册可存档对象，统一序列化/反序列化，支持版本号与备份
# 原则：每个模块独立序列化，不交叉引用；存档版本号独立于游戏版本号

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

const SAVE_VERSION := "1.1.0"   # 1.1.0(2026-09-04)：新增 last_region_id（读档恢复所在区域）

# 版本迁移链（第二阶段·代码审查报告整改）：老版本存档按序迁移到当前版本。
# 迁移步骤签名：func(data: Dictionary) -> Dictionary（原地补字段/改结构，返回处理后的 data）。
# 新增不兼容变更时：SAVE_VERSION 升版 + 在此追加一步迁移，绝不破坏老档。
var _migrations: Array = [
	# {"from": "1.0.0", "step": Callable}
]
const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 6   # 手动存档槽位上限（存档选择界面按槽位渲染）
const TMP_SUFFIX := ".tmp"   # 原子写临时文件后缀
const BAK_SUFFIX := ".bak"   # 覆盖前的上一份存档备份后缀

var _saveables: Array = []   # 实现了 get_save_key()/save()/load() 的对象

func register_saveable(saveable: Variant) -> void:
	if not _saveables.has(saveable):
		_saveables.append(saveable)

## 已注册的可存档对象数量（Bootstrap 启动序列查询）
func get_saveable_count() -> int:
	return _saveables.size()

## 是否存在任意存档（主菜单"继续江湖路"可用性判断，M2 新增）
func has_any_save() -> bool:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return false
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return false
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.begins_with("save_") and fname.ends_with(".json"):
			dir.list_dir_end()
			return true
		fname = dir.get_next()
	dir.list_dir_end()
	return false

## 最新存档槽位（编号最大者）；无存档返回 -1（M2 新增）
func get_latest_save_slot() -> int:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return -1
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return -1
	var latest: int = -1
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.begins_with("save_") and fname.ends_with(".json"):
			var slot_str: String = fname.trim_prefix("save_").trim_suffix(".json")
			var slot: int = int(slot_str)
			if slot > latest:
				latest = slot
		fname = dir.get_next()
	dir.list_dir_end()
	return latest

## 手动存档列表：返回固定 MAX_SLOTS 个槽位摘要（含空槽位）；索引 0 存 slot 1
## 摘要 dict 字段：slot / exists / is_auto / player_name / level / faction / playtime / save_time / scene / thumbnail_path
func list_saves() -> Array:
	var result: Array = []
	for slot in range(1, MAX_SLOTS + 1):
		var path := SAVE_DIR + "save_%d.json" % slot
		if FileAccess.file_exists(path):
			result.append(_read_summary(slot, path, false))
		else:
			result.append({
				"slot": slot, "exists": false, "is_auto": false,
				"player_name": "", "level": 0, "faction": "",
				"playtime": "", "save_time": "", "scene": "", "thumbnail_path": "",
			})
	return result

## 自动存档列表：最近 3 个（auto_N.json）；只读，不可手动删除（M3 自动存档系统尚未接入，通常返回空）
func list_auto_saves() -> Array:
	var result: Array = []
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		return result
	var dir: DirAccess = DirAccess.open(SAVE_DIR)
	if dir == null:
		return result
	dir.list_dir_begin()
	var fname: String = dir.get_next()
	while fname != "":
		if fname.begins_with("auto_") and fname.ends_with(".json"):
			var slot_str: String = fname.trim_prefix("auto_").trim_suffix(".json")
			var slot: int = int(slot_str)
			result.append(_read_summary(slot, SAVE_DIR + fname, true))
		fname = dir.get_next()
	dir.list_dir_end()
	result.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["slot"] > b["slot"])
	if result.size() > 3:
		result = result.slice(0, 3)
	return result

## 删除手动存档；成功返回 true（M3 新增）
func delete_save(slot: int) -> bool:
	var path := SAVE_DIR + "save_%d.json" % slot
	if not FileAccess.file_exists(path):
		GameLogger.warn("SaveManager", "待删除存档不存在: %s" % path)
		return false
	if DirAccess.remove_absolute(path) != OK:
		GameLogger.error("SaveManager", "删除存档失败: %s" % path)
		return false
	EventBus.game_saved.emit(slot)   # 复用信号通知存档集合变化（M5 可细分）
	return true

## 从存档文件抽取摘要（槽位号 + 是否自动 + 角色/时长/时间等；缺失字段回退占位）
func _read_summary(slot: int, path: String, is_auto: bool) -> Dictionary:
	var data: Dictionary = _load_json(path)
	var meta: Dictionary = data.get("meta", {})
	var ps: Dictionary = data.get("player", {})
	var unix_time: int = int(meta.get("timestamp", 0))
	return {
		"slot": slot,
		"exists": true,
		"is_auto": is_auto,
		# 自定义存档名优先（ESC 菜单「保存游戏」走 SaveLoadScreen 命名），否则回退角色名
		"player_name": meta.get("custom_name", "") if meta.get("custom_name", "") != "" else ps.get("player_name", "侠客"),
		"level": int(ps.get("level", 1)),
		"faction": ps.get("faction", "无门无派"),
		"playtime": _format_playtime(int(ps.get("playtime", 0))),
		"save_time": _format_time(unix_time),
		"scene": ps.get("scene", "江湖某处"),
		"thumbnail_path": ps.get("thumbnail_path", ""),
	}

## 时间戳 → "YYYY-MM-DD HH:MM"（0 回退 "—"）
func _format_time(unix: int) -> String:
	if unix <= 0:
		return "—"
	return Time.get_datetime_string_from_unix_time(unix, true).left(16)

## 秒数 → "HH:MM:SS"
func _format_playtime(seconds: int) -> String:
	if seconds <= 0:
		return "—"
	var h: int = seconds / 3600
	var m: int = (seconds % 3600) / 60
	var s: int = seconds % 60
	return "%02d:%02d:%02d" % [h, m, s]

## 一键快速存档（存到 auto_1.json，与 list_auto_saves 兼容）；成功返回 true
## 用于游戏内 ESC 菜单「保存游戏」，避免弹复杂选槽界面
func quick_save() -> bool:
	if _saveables.is_empty():
		GameLogger.warn("SaveManager", "无已注册存档对象，快速存档跳过")
		return false
	var save_data: Dictionary = {"meta": _build_meta()}
	for saveable in _saveables:
		var key: String = saveable.get_save_key()
		save_data[key] = saveable.save()
	var path := SAVE_DIR + "auto_1.json"
	return _write_json(path, save_data, -1)

## 手动存档到指定槽位；custom_name 非空时写入 meta，供卡片显示自定义存档名
func save_to_slot(slot: int, custom_name: String = "") -> bool:
	var save_data: Dictionary = {"meta": _build_meta(custom_name)}
	for saveable in _saveables:
		var key: String = saveable.get_save_key()
		save_data[key] = saveable.save()
	var path := SAVE_DIR + "save_%d.json" % slot
	var ok: bool = _write_json(path, save_data, slot)
	if ok:
		GameLogger.info("SaveManager", "已保存到槽位 %d（名称：%s）" % [slot, custom_name if custom_name != "" else "默认"])
	return ok

## 手动读档（save_N.json）
func load_from_slot(slot: int) -> bool:
	return _load_from_path(SAVE_DIR + "save_%d.json" % slot, slot)

## 自动读档（auto_N.json）：quick_save 的对称操作。此前缺失导致自动存档「能存不能读」
## slot 传 -1 表示非手动槽位（GameManager 据此不记录 current_slot）
func load_auto_save(slot: int) -> bool:
	return _load_from_path(SAVE_DIR + "auto_%d.json" % slot, -1)

## 统一读档流程：存在性 → 解析 → 损坏回退 .bak → 版本校验 → 分发各模块
func _load_from_path(path: String, slot: int) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[Save] 存档不存在: %s" % path)
		return false
	var data: Dictionary = _load_json(path)
	if data.is_empty():
		GameLogger.error("SaveManager", "存档解析失败（可能已损坏），尝试回退备份: %s" % path)
		if not _restore_from_backup(path):
			GameLogger.error("SaveManager", "备份不可用，读档中止: %s" % path)
			return false
		data = _load_json(path)
		if data.is_empty():
			GameLogger.error("SaveManager", "回退后仍无法解析，读档中止: %s" % path)
			return false
	_check_version(data)
	if not _migrate_if_needed(data):
		GameLogger.error("SaveManager", "存档版本高于当前 %s，拒绝读档（防止新版数据被旧逻辑损坏）: %s" % [SAVE_VERSION, path])
		return false
	for saveable in _saveables:
		var key: String = saveable.get_save_key()
		if data.has(key):
			saveable.load(data[key])
	EventBus.game_loaded.emit(slot)
	return true

## 版本校验：仅记日志（真正迁移决策在 _migrate_if_needed）
func _check_version(data: Dictionary) -> void:
	var meta: Dictionary = data.get("meta", {})
	var v: String = meta.get("save_version", "")
	if v == SAVE_VERSION:
		return
	if v == "":
		GameLogger.warn("SaveManager", "存档缺少版本号，按 1.0.0 遗留档处理")
		return
	GameLogger.warn("SaveManager", "存档版本 %s 与当前 %s 不一致" % [v, SAVE_VERSION])

## 版本迁移（第二阶段·代码审查报告整改）：老档按迁移链逐步升级；更新版本拒绝读档。
## 返回 false = 无法安全读档（调用方中止）。
func _migrate_if_needed(data: Dictionary) -> bool:
	if not data.has("meta") or not (data["meta"] is Dictionary):
		data["meta"] = {}
	var meta: Dictionary = data["meta"]
	var v: String = str(meta.get("save_version", ""))
	if v == SAVE_VERSION:
		return true
	if v != "" and _version_gt(v, SAVE_VERSION):
		return false   # 未来版本的档：拒绝，防旧逻辑写坏新数据
	# 无版本号 = 1.0.0 遗留档；或已知老版本 → 依次走迁移链
	var known: Array[String] = ["1.0.0"]
	known.append(SAVE_VERSION)
	var from_idx := 0 if v == "" else known.find(v)
	if from_idx < 0:
		GameLogger.warn("SaveManager", "未知存档版本 %s，按当前版本尽力解析" % v)
		meta["save_version"] = SAVE_VERSION
		return true
	# 1.0.0 → 1.1.0 无破坏性结构变化（last_region_id 由 GameState.load 默认值兜底）；
	# 未来步骤在此追加：for step in _migrations: data = step.step.call(data)
	for m in _migrations:
		if m.get("from", "") == v and m.get("step") is Callable:
			data = m["step"].call(data)
	meta["save_version"] = SAVE_VERSION
	GameLogger.info("SaveManager", "存档已迁移：%s → %s" % [v if v != "" else "1.0.0(遗留)", SAVE_VERSION])
	return true

## 简易语义化版本比较：a > b
func _version_gt(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in range(3):
		var ai := int(pa[i]) if i < pa.size() else 0
		var bi := int(pb[i]) if i < pb.size() else 0
		if ai != bi:
			return ai > bi
	return false

## 从 .bak 恢复主档；成功返回 true
func _restore_from_backup(path: String) -> bool:
	var bak := path + BAK_SUFFIX
	if not FileAccess.file_exists(bak):
		return false
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(bak, path) != OK:
		# rename 失败则退回复制，保证主档至少能恢复
		if DirAccess.copy_absolute(bak, path) != OK:
			return false
	GameLogger.warn("SaveManager", "已从备份恢复: %s" % bak)
	return true

func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed != null:
		return parsed
	return {}

## 原子写：写 .tmp → 回读校验 → 备份旧档 → 替换主档
## 目的：写入中途崩溃（安卓上很常见）时，主档与 .bak 至少有一个是完好的
func _write_json(path: String, data: Dictionary, slot: int) -> bool:
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	var text := JSON.stringify(data)
	var tmp := path + TMP_SUFFIX
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		push_error("[Save] 无法写入临时文件: %s" % tmp)
		return false
	f.store_string(text)
	f.close()
	if not _verify_file(tmp):
		push_error("[Save] 临时文件校验失败，放弃本次写入: %s" % tmp)
		DirAccess.remove_absolute(tmp)
		return false
	if FileAccess.file_exists(path):
		_backup(path)
		DirAccess.remove_absolute(path)
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_error("[Save] 替换主档失败，尝试从备份恢复: %s" % path)
		DirAccess.remove_absolute(tmp)
		_restore_from_backup(path)
		return false
	EventBus.game_saved.emit(slot)
	return true

## 备份当前主档到 .bak（覆盖式，只保留最近一份）
func _backup(path: String) -> void:
	var bak := path + BAK_SUFFIX
	if FileAccess.file_exists(bak):
		DirAccess.remove_absolute(bak)
	if DirAccess.copy_absolute(path, bak) != OK:
		push_warning("[Save] 备份失败（不阻断写入）: %s" % path)

## 回读校验：确认刚写的文件能被完整解析，避免把半截数据当成存档
func _verify_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var text := f.get_as_text()
	f.close()
	if text.is_empty():
		return false
	return JSON.parse_string(text) != null

func _build_meta(custom_name: String = "") -> Dictionary:
	var meta := {
		"save_version": SAVE_VERSION,
		"timestamp": Time.get_unix_time_from_system(),
	}
	if custom_name != "":
		meta["custom_name"] = custom_name
	return meta
