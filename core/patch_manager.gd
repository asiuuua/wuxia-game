# core/patch_manager.gd
# 单机补丁/热更新机制（18 图 RH 域；旧「规范 §4.7」编号已废）：扫描 patches 目录，加载 pck 覆盖主包资源，
# 做版本校验并记录已应用补丁，可选触发存档迁移。注册为 Autoload 单例 PatchManager。
# 注：autoload 脚本不写 class_name（与单例名冲突），通过全局单例名调用。

extends Node
# 批D 子批2（ADR-0007 装配收敛）：原 autoload 降级为普通 Node——由 Bootstrap（生命周期壳）
# 挂载，_ready 扫描/应用补丁语义保真（add_child 后 _ready 照常触发）。
class_name PatchManager

var _applied_patches: Array[String] = []
var _patch_dir: String = ""

func _ready() -> void:
	_patch_dir = OS.get_executable_path().get_base_dir() + "/patches/"
	_load_patch_history()
	_scan_and_apply_patches()

func _scan_and_apply_patches() -> void:
	if not DirAccess.dir_exists_absolute(_patch_dir):
		return
	var dir: DirAccess = DirAccess.open(_patch_dir)
	if dir == null:
		GameLogger.error("Patch", "Cannot open patch dir: %s" % _patch_dir)
		return
	var patches: Array[String] = []
	dir.list_dir_begin()
	var file_name: String = dir.get_next()
	while file_name != "":
		if dir.current_is_dir() and file_name.begins_with("patch_"):
			patches.append(file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	patches.sort()
	for patch_name in patches:
		if not _applied_patches.has(patch_name):
			_apply_patch(patch_name)

func _apply_patch(patch_name: String) -> bool:
	var patch_path: String = _patch_dir + patch_name + "/"
	var manifest: Dictionary = JSONUtil.load_json(patch_path + "manifest.json")
	if manifest.is_empty():
		GameLogger.error("Patch", "Invalid patch manifest: %s" % patch_name)
		return false
	var game_version: String = ProjectSettings.get_setting("application/config/version", "0.0.0")
	if not _version_check(game_version, manifest.get("min_game_version", "0.0.0")):
		GameLogger.error("Patch", "Patch %s requires game version >= %s" % [patch_name, manifest.min_game_version])
		return false
	var pck_path: String = patch_path + "patch.pck"
	if FileAccess.file_exists(pck_path):
		if not ProjectSettings.load_resource_pack(pck_path, true):
			GameLogger.error("Patch", "Failed to load patch PCK: %s" % pck_path)
			return false
	# 存档迁移登记（13 图 SV-3/P-S1 修复）：不再 has_method 死探测；格式非法必须响报。
	var migration_spec: Variant = manifest.get("save_migration", null)
	if migration_spec != null:
		if migration_spec is Dictionary:
			SaveManager.register_migration(migration_spec)
		else:
			GameLogger.error("Patch", "manifest.save_migration 须为 SV-3 条目 {from,to,step:Callable}，已拒绝: %s" % patch_name)
	_applied_patches.append(patch_name)
	_save_patch_history()
	GameLogger.info("Patch", "Applied patch: %s (version %s)" % [patch_name, manifest.get("version", "?")])
	EventBus.patch_applied.emit(patch_name, manifest.get("version", ""))
	return true

func _version_check(current: String, minimum: String) -> bool:
	var cur_parts: Array = current.split(".")
	var min_parts: Array = minimum.split(".")
	for i in min(cur_parts.size(), min_parts.size()):
		if int(cur_parts[i]) > int(min_parts[i]):
			return true
		if int(cur_parts[i]) < int(min_parts[i]):
			return false
	return true

func _load_patch_history() -> void:
	var path: String = "user://patch_history.json"
	if not FileAccess.file_exists(path):
		return
	var data: Dictionary = JSONUtil.load_json(path)
	_applied_patches.clear()
	for s in data.get("applied", []):
		_applied_patches.append(String(s))

func _save_patch_history() -> void:
	JSONUtil.save_json("user://patch_history.json", {"applied": _applied_patches})
