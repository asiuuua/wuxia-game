# tools/golden/gen_save_body_registry.gd
# 存档 Body 登记表生产器（13 图 SV-2：「新模块入档必须先在本表登记 DataContract，禁私自扩键」）。
# 职责：在真实装配环境下（autoload 全启 + start_new_game 初始态）dump 全部已注册模块的
#       save() 顶层字段清单，产出 docs/contract/save_body_registry.json 供人审入库；
#       SaveManager._load_body_registry 启动时载入该表做「禁私自扩键」机器校验。
# 用法：godot --headless --path <项目根> res://tools/golden/gen_save_body_registry.tscn
# 约定：新增/变更存档模块时重跑本场景重产登记表（diff 入审）；fields 为 dump 时点结构，
#       条件字段以 Owner 模块代码为准（登记表锁「键集」由 SaveManager 机器校验，fields 供人审锚点）。
extends Node

const OUT_PATH := "res://docs/contract/save_body_registry.json"

func _ready() -> void:
	# 保险：gen 场景作为主场景跑时 autoload 已注册（GameManager._ready 链）；为 0 则手动补注册
	if SaveManager.get_saveable_count() == 0:
		GameManager._register_saveables()
	# 装配初始游戏态（各服务 reset + 玩家默认值），让 dump 覆盖完整结构
	GameManager.start_new_game()
	var full: Dictionary = SaveManager._build_save_data()
	var modules: Dictionary = {}
	for key in full:
		if key == "meta":
			continue
		var wrapped: Variant = full[key]
		if not (wrapped is Dictionary) or not (wrapped as Dictionary).has("schema_version"):
			push_error("[registry] 模块键 %s 非 SV-2 二段式（缺 schema_version 包装），无法登记" % key)
			get_tree().quit(1)
			return
		var data_v: Variant = (wrapped as Dictionary).get("data", null)
		if not (data_v is Dictionary):
			push_error("[registry] 模块键 %s 的 data 非 Dictionary，无法登记" % key)
			get_tree().quit(1)
			return
		var fields: Array = []
		for f in data_v:
			fields.append(str(f))
		fields.sort()
		modules[key] = {
			"owner": _owner_of(key),
			"schema_version": str((wrapped as Dictionary)["schema_version"]),
			"fields": fields,
		}
	var out := {
		"_doc": "存档 Body 键登记表（13 图 SV-2 DataContract）。SaveManager._load_body_registry 启动载入：register_saveable 时键不在 modules 即拒注册（禁私自扩键）。生产器=tools/golden/gen_save_body_registry.tscn（dump 真实注册清单，start_new_game 初始态）；fields 为 dump 时点顶层字段，条件字段以 Owner 模块代码为准；新增/变更模块须重跑重产并 diff 入审。",
		"schema_version": SaveManager.MODULE_SCHEMA_VERSION,
		"modules": modules,
	}
	DirAccess.make_dir_recursive_absolute(OUT_PATH.get_base_dir())
	var f := FileAccess.open(OUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[registry] 无法写入 %s" % OUT_PATH)
		get_tree().quit(1)
		return
	f.store_string(JSON.stringify(out, "\t"))
	f.close()
	print("[registry] 已产出存档 Body 登记表：%d 键 -> %s（入库前请人审）" % [modules.size(), OUT_PATH])
	get_tree().quit(0)

## 模块键 -> Owner 归属（12 键冻结清单，与 01 §70 十二键映射一致）
func _owner_of(key: String) -> String:
	var map := {
		"player": "PlayerState(data/runtime)",
		"world_time": "WorldTimeState(data/runtime, weather_time_service 注册)",
		"game_state": "GameState(autoload, save_bridge)",
		"quest": "QuestService(services/quest)",
		"inventory": "InventoryService(services/inventory)",
		"equipment": "EquipmentService(services/equipment)",
		"ability": "AbilityService(services/ability)",
		"sect": "SectService(services/sect)",
		"bond": "BondService(services/bond)",
		"romance": "RomanceService(services/bond)",
		"sworn": "SwornService(services/bond)",
		"master": "MasterService(services/bond)",
	}
	return str(map.get(key, "UNKNOWN(须人审)"))
