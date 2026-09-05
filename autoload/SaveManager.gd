# autoload/SaveManager.gd
# 存档管理器：注册可存档对象，统一序列化/反序列化，支持版本号与备份
# 原则：每个模块独立序列化，不交叉引用；存档版本号独立于游戏版本号

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

const SAVE_VERSION := "1.2.0"   # 1.2.0(2026-09-06)：SV-2 二段式 Body——每模块键包 {schema_version, data}，模块版本独立演进
const BASE_SAVE_VERSION := "1.0.0"   # 无版本号遗留档的推定起点（SV-3 注册表推导基点）

# 模块级 schema 版本起点（13 图 SV-2）：Body 每键 = {"schema_version": ..., "data": {...}}。
# 模块字段变更 = 该模块升版 + register_module_migration 登记步骤 + golden 对，不再牵动全局 SAVE_VERSION。
const MODULE_SCHEMA_VERSION := "1.0.0"

# 模块当前版本覆盖表（SV-2）：未来某模块升版时在此登记 key→新 SemVer；
# 写端据此打戳、读端据此判「未来/低位版本」。空 = 全部模块处于起点版。
var _module_versions: Dictionary = {}

# 存档 Body 键登记制（SV-2「新模块入档必须先在本表登记 DataContract，禁私自扩键」）：
# 白名单来自 docs/contract/save_body_registry.json（tools/golden/gen_save_body_registry 场景 dump 真实注册清单产出，人审入库）。
# register_saveable 时校验：白名单非空且 key 未登记 → 拒绝注册（FATAL 留痕）。载入失败 → 空表跳过校验（ERROR 留痕，结构问题由 GATE/CI 兜底）。
var _registry_whitelist: Dictionary = {}

# 模块级迁移链注册表（SV-2）：{ "key": str, "from": SemVer, "to": SemVer, "step": Callable }。
# 与全局 SAVE_VERSION 链分层：顶层结构变更走 register_migration（动 SAVE_VERSION）；
# 单模块字段变更走 register_module_migration（只动该键 schema_version）。
var _module_migrations: Array = []

# 全局存档版本迁移链显式注册表（13 图 SV-3 / 宪法 §32）：老版本存档按序迁移到当前版本。
# 步骤签名：{ "from": SemVer, "to": SemVer, "step": Callable }，step 为 func(data)->Dictionary。
# 已知版本链由注册表自动推导（禁手写 known 数组，P-S6 收口）；未知版本一律拒读（P-S3）。
var _migrations: Array = []

var _content_version_cache: String = ""   # content_version 进程内缓存（P-S5，见 _content_version）

func _ready() -> void:
	_seed_builtin_migrations()
	_load_body_registry()

## 1.1.0 → 1.2.0：SV-2 二段式 Body——把全部裸键包成 {"schema_version": "1.0.0", "data": 值}。
## 存档文件顶层只有 meta + 模块键，模块值恒为 save() 产出的 Dictionary（ISaveable 接口约束）；
## 仅包装「值为 Dictionary 且无 schema_version」的键，防御手工改档的异常形态。
func _migrate_1_1_0_to_1_2_0(data: Dictionary) -> Dictionary:
	for k in data:
		if k == "meta":
			continue
		var v: Variant = data[k]
		if v is Dictionary and not (v as Dictionary).has("schema_version"):
			data[k] = {"schema_version": MODULE_SCHEMA_VERSION, "data": v}
	return data

## 内置历史迁移登记（13 图 DoD 3：每步必登记，禁止零登记豁免）。
## 外部补丁迁移经 PatchManager → register_migration 接线（P-S1 修复）。
func _seed_builtin_migrations() -> void:
	register_migration({
		"from": "1.0.0",
		"to": "1.1.0",
		"step": Callable(self, "_migrate_1_0_0_to_1_1_0"),
	})
	register_migration({
		"from": "1.1.0",
		"to": "1.2.0",
		"step": Callable(self, "_migrate_1_1_0_to_1_2_0"),
	})

## 载入 Body 键登记表（SV-2 登记制机器化）：docs/contract/save_body_registry.json
## 由 tools/golden/gen_save_body_registry 场景 dump 真实注册清单产出（人审入库）。
## 载入失败 → 空表 + ERROR 留痕，校验跳过（结构问题由 GATE/CI 兜底，不在运行时把玩家锁死）。
func _load_body_registry() -> void:
	_registry_whitelist.clear()
	if not FileAccess.file_exists("res://docs/contract/save_body_registry.json"):
		GameLogger.error("SaveManager", "存档 Body 登记表缺失（res://docs/contract/save_body_registry.json），扩键校验跳过")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://docs/contract/save_body_registry.json"))
	if not (parsed is Dictionary):
		GameLogger.error("SaveManager", "存档 Body 登记表解析失败，扩键校验跳过")
		return
	var modules: Variant = (parsed as Dictionary).get("modules", {})
	if not (modules is Dictionary):
		GameLogger.error("SaveManager", "存档 Body 登记表缺 modules 段，扩键校验跳过")
		return
	for k in modules:
		_registry_whitelist[str(k)] = true
	GameLogger.info("SaveManager", "存档 Body 登记表已载入：%d 键（SV-2 禁私自扩键）" % _registry_whitelist.size())

## 模块级迁移登记口（SV-2）：{ "key", "from", "to", "step:Callable" }。
## 未来某模块字段变更升 schema_version 时，在此登记一步（配 golden 对）。
func register_module_migration(entry: Dictionary) -> bool:
	var key: String = str(entry.get("key", ""))
	var from_v: String = str(entry.get("from", ""))
	var to_v: String = str(entry.get("to", ""))
	var step: Variant = entry.get("step", null)
	if key == "" or from_v == "" or to_v == "" or not (step is Callable):
		GameLogger.error("SaveManager", "register_module_migration 拒绝非法条目（需 key/from/to/step:Callable）: %s" % [entry])
		return false
	for m in _module_migrations:
		if str(m.get("key", "")) == key and str(m.get("from", "")) == from_v:
			GameLogger.warn("SaveManager", "模块迁移步骤重复登记，跳过: %s %s -> %s" % [key, from_v, to_v])
			return true
	_module_migrations.append({"key": key, "from": from_v, "to": to_v, "step": step})
	GameLogger.info("SaveManager", "已登记模块迁移步骤: %s %s -> %s" % [key, from_v, to_v])
	return true

## 模块当前 schema 版本：覆盖表登记值优先，缺省 = MODULE_SCHEMA_VERSION 起点版
func _module_current_version(key: String) -> String:
	return str(_module_versions.get(key, MODULE_SCHEMA_VERSION))

## 解析单模块键载荷（SV-2 读端）：
## - 二段式 {"schema_version", "data"}：版本==当前 → 取 data；版本更高 → null（未来模块拒读）；
##   版本更低 → 沿模块迁移链升到当前，断链 = null（未知模块版本拒读，P-S3 同精神）。
## - legacy 裸键（1.2.0 前老档，理论上已被全局迁移包装；此处兜底）→ 原样透传 + 一次性通报。
## - 非 Dictionary / 包装缺 data / data 非 Dictionary → null（调用方拒读整档）。
## 返回 null = 无法安全解析（调用方中止读档，禁静默尽力解析）。
func _resolve_module_payload(key: String, raw: Variant) -> Variant:
	if not (raw is Dictionary):
		GameLogger.error("SaveManager", "模块键 %s 载荷非 Dictionary，拒绝读档（SV-2）" % key)
		return null
	var dict: Dictionary = raw
	if dict.has("schema_version"):
		var mv: String = str(dict.get("schema_version", ""))
		var payload: Variant = dict.get("data", null)
		if not (payload is Dictionary):
			GameLogger.error("SaveManager", "模块键 %s 二段式载荷缺 data Dictionary，拒绝读档（SV-2）" % key)
			return null
		var cur: String = _module_current_version(key)
		if mv == cur:
			return payload
		if _version_gt(mv, cur):
			GameLogger.error("SaveManager", "模块 %s schema_version %s 高于当前 %s，拒绝读档（防新档被旧逻辑写坏，SV-2）" % [key, mv, cur])
			return null
		# 低位版本：沿模块迁移链升级（注册表链走，断链即拒）
		var guard := 0
		while mv != cur:
			var step: Dictionary = {}
			for m in _module_migrations:
				if str(m.get("key", "")) == key and str(m.get("from", "")) == mv:
					step = m
					break
			if step.is_empty() or not (step.get("step") is Callable):
				GameLogger.error("SaveManager", "模块 %s schema_version %s 无迁移步骤（当前 %s），拒绝读档（SV-2/P-S3 同精神）" % [key, mv, cur])
				return null
			var carried: Dictionary = {"data": payload}
			var out: Variant = (step["step"] as Callable).call(carried)
			if not (out is Dictionary) or not (out as Dictionary).get("data", null) is Dictionary:
				GameLogger.error("SaveManager", "模块 %s 迁移步骤 %s->%s 产出非法，拒绝读档" % [key, mv, str(step.get("to", ""))])
				return null
			payload = (out as Dictionary)["data"]
			mv = str(step.get("to", ""))
			guard += 1
			if guard > 32:
				GameLogger.error("SaveManager", "模块 %s 迁移链异常（超 32 步未抵达 %s），拒绝读档" % [key, cur])
				return null
		return payload
	# legacy 裸键兜底：1.2.0 前老档未经全局迁移包装的漏网形态（正常不应到达此处）
	GameLogger.warn("SaveManager", "模块键 %s 为 legacy 裸载荷（无 schema_version 包装），按 1.0.0 兼容读取（SV-2 渐进口径）" % key)
	return dict


## 公开迁移登记口（13 图 SV-3 显式注册表 / P-S1 死接线修复，Phase1 落地）：

## 1.0.0 → 1.1.0：新增 last_region_id（读档恢复所在区域）。
## 老档 game_state 缺该字段时补起始区域默认值（与 GameState.load 兜底同口径）；
## game_state 键整体缺失的老档不动（缺 key 分级归 SV-4 期望清单核对，Phase2）。
func _migrate_1_0_0_to_1_1_0(data: Dictionary) -> Dictionary:
	var gs: Variant = data.get("game_state", null)
	if gs is Dictionary:
		var g: Dictionary = gs
		if not g.has("last_region_id"):
			g["last_region_id"] = "newbie_village"
	return data


## 公开迁移登记口（13 图 SV-3 显式注册表 / P-S1 死接线修复，Phase1 落地）：
## 外部（如 PatchManager）按 { "from": SemVer, "to": SemVer, "step": Callable } 登记。
## step 签名：func(data: Dictionary) -> Dictionary；非法条目拒绝并 ERROR（禁静默）。
func register_migration(entry: Dictionary) -> bool:
	var from_v: String = str(entry.get("from", ""))
	var to_v: String = str(entry.get("to", ""))
	var step: Variant = entry.get("step", null)
	if from_v == "" or to_v == "" or not (step is Callable):
		GameLogger.error("SaveManager", "register_migration 拒绝非法条目（需 from/to/step:Callable）: %s" % [entry])
		return false
	for m in _migrations:
		if str(m.get("from", "")) == from_v and str(m.get("to", "")) == to_v:
			GameLogger.warn("SaveManager", "迁移步骤重复登记，跳过: %s -> %s" % [from_v, to_v])
			return true
	_migrations.append({"from": from_v, "to": to_v, "step": step})
	_migrations.sort_custom(func(a, b): return str(a.get("from", "")) < str(b.get("from", "")))
	GameLogger.info("SaveManager", "已登记存档迁移步骤: %s -> %s" % [from_v, to_v])
	return true
const SAVE_DIR := "user://saves/"
const MAX_SLOTS := 6   # 手动存档槽位上限（存档选择界面按槽位渲染）
const TMP_SUFFIX := ".tmp"   # 原子写临时文件后缀
const BAK_SUFFIX := ".bak"   # 覆盖前的上一份存档备份后缀

var _saveables: Array = []   # 实现 ISaveable 的对象（SV-4/P-S11 鸭子探测退役：强类型签名收口）

## 注册可存档对象。SV-4/P-S2（P0 漏修补课 2026-09-06）：注册期 key 撞车即拒绝并报错，
## 不给玩家留「后注册者覆盖先注册者存档数据」的静默丢失窗口。
## SV-4/P-S11：签名强类型收 ISaveable（鸭子探测退役），无 get_save_key/save/load 的对象编译期即拒。
func register_saveable(saveable: ISaveable) -> void:
	if _saveables.has(saveable):
		return
	var key: String = saveable.get_save_key()
	# SV-2 登记制：白名单已载入且 key 未登记 → 拒绝注册（禁私自扩键；新模块先登记 save_body_registry.json）
	if not _registry_whitelist.is_empty() and not _registry_whitelist.has(key):
		GameLogger.error("SaveManager", "存档 key %s 未在 Body 登记表（docs/contract/save_body_registry.json）登记，拒绝注册（SV-2 禁私自扩键）" % key)
		push_error("[Save] 未登记存档 key: %s" % key)
		return
	for existing in _saveables:
		if existing.get_save_key() == key:
			GameLogger.error("SaveManager", "存档 key 撞车，拒绝注册（SV-4/P-S2 注册期 FATAL）: key=%s 新对象=%s 与已有=%s 冲突" % [key, saveable, existing])
			push_error("[Save] 存档 key 撞车: %s" % key)
			return
	_saveables.append(saveable)


## 读档加载顺序（13图 SV-4/P-S4）：按 get_load_after() 依赖拓扑排序（Kahn），
## 禁隐式注册顺序依赖；存在依赖环 = 注册错误，返回空数组（调用方拒读）。
func _topo_load_order() -> Array:
	var by_key := {}
	for s in _saveables:
		by_key[s.get_save_key()] = s
	var indeg := {}
	var dependents := {}   # dep_key -> [依赖它的 key 列表]
	for key in by_key:
		var deps: Array[String] = by_key[key].get_load_after()
		indeg[key] = deps.size()
		for d in deps:
			if not dependents.has(d):
				dependents[d] = []
			dependents[d].append(key)
	var queue: Array = []
	for key in indeg:
		if int(indeg[key]) == 0:
			queue.append(key)
	var order: Array = []
	while not queue.is_empty():
		var k: String = queue.pop_front()
		order.append(k)
		for nxt in dependents.get(k, []):
			indeg[nxt] = int(indeg[nxt]) - 1
			if int(indeg[nxt]) == 0:
				queue.append(nxt)
	if order.size() != by_key.size():
		GameLogger.error("SaveManager", "存档模块加载依赖存在环，拓扑排序失败（SV-4/P-S4 FATAL）")
		return []
	return order

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
	# SV-2：player 键已二段式包装（{"schema_version", "data"}）——摘要读取走轻量解包
	# （摘要只读不迁移；老档裸键形态原样可用，两种形态都兼容）
	var ps_raw: Variant = data.get("player", {})
	if ps_raw is Dictionary and (ps_raw as Dictionary).has("schema_version") and (ps_raw as Dictionary).get("data", null) is Dictionary:
		ps_raw = (ps_raw as Dictionary)["data"]
	var ps: Dictionary = ps_raw if ps_raw is Dictionary else {}
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
	var save_data: Dictionary = _build_save_data()
	var path := SAVE_DIR + "auto_1.json"
	return _write_json(path, save_data, -1)

## 手动存档到指定槽位；custom_name 非空时写入 meta，供卡片显示自定义存档名
func save_to_slot(slot: int, custom_name: String = "") -> bool:
	var save_data: Dictionary = _build_save_data(custom_name)
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

## 统一读档流程：存在性 → 解析+checksum 双验 → 损坏回退 .bak → 版本校验 → 分发各模块
func _load_from_path(path: String, slot: int) -> bool:
	if not FileAccess.file_exists(path):
		push_warning("[Save] 存档不存在: %s" % path)
		return false
	var data: Dictionary = _load_json(path)
	var bad := ""
	if data.is_empty():
		bad = "解析失败（可能已损坏）"
	elif not _checksum_ok(data):
		bad = "checksum 不一致（内容损坏或被篡改）"   # SV-1：禁静默尽力解析
	if bad != "":
		GameLogger.error("SaveManager", "存档%s，走 .bak 抢救链: %s" % [bad, path])
		if not _restore_from_backup(path):
			GameLogger.error("SaveManager", "备份不可用，读档中止: %s" % path)
			return false
		data = _load_json(path)
		if data.is_empty() or not _checksum_ok(data):
			GameLogger.error("SaveManager", "回退后仍无法通过校验，读档中止: %s" % path)
			return false
	_check_version(data)
	if not _migrate_if_needed(data):
		GameLogger.error("SaveManager", "存档版本高于当前 %s，拒绝读档（防止新版数据被旧逻辑损坏）: %s" % [SAVE_VERSION, path])
		return false
	# 13图 SV-4 收口：①P-S4 加载顺序=依赖拓扑排序（equipment 等消费 player 的模块保证后加载）；
	# ②P-S12 已注册但档内缺 key 的模块 WARNING（老档新模块默认值兜底属预期，禁静默）。
	# 拓扑失败（依赖环）= 注册期错误，拒绝读档防状态错乱。
	var order: Array = _topo_load_order()
	if order.is_empty() and not _saveables.is_empty():
		GameLogger.error("SaveManager", "拓扑排序失败，读档中止: %s" % path)
		return false
	var missing: Array = []
	for s in _saveables:
		var rkey: String = s.get_save_key()
		if not data.has(rkey):
			missing.append(rkey)
	if not missing.is_empty():
		GameLogger.warn("SaveManager", "读档缺 key（老档新模块，按默认值兜底）: %s" % ", ".join(missing))
	var by_key := {}
	for s in _saveables:
		by_key[s.get_save_key()] = s
	for key in order:
		if data.has(key):
			# SV-2 读端：二段式解包 + 模块 schema_version 核对（未来/未知版本拒读，legacy 兜底）
			var resolved: Variant = _resolve_module_payload(key, data[key])
			if resolved == null:
				GameLogger.error("SaveManager", "模块 %s 载荷解析失败，读档中止: %s" % [key, path])
				return false
			by_key[key].load(resolved as Dictionary)
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

## 版本迁移（13 图 SV-3 注册表链走）：老档沿注册表逐步升级；未知/未来版本一律拒读（P-S3）。
## 迁移全部在内存副本上进行，全部通过才写回版本戳（失败保原档）。
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
	var origin: String = v if v != "" else "%s(遗留)" % BASE_SAVE_VERSION
	if v == "":
		v = BASE_SAVE_VERSION   # 无版本号 = 1.0.0 遗留档（推定起点）
	# 注册表链走：找到 from==当前版本 的步骤逐步推进，直到抵达 SAVE_VERSION；
	# 中途任何一步找不到注册步骤 = 未知版本 → 拒读（识别不了=不是我们的档，宁可拒读保数据）
	var guard := 0
	while v != SAVE_VERSION:
		var step: Dictionary = {}
		for m in _migrations:
			if str(m.get("from", "")) == v:
				step = m
				break
		if step.is_empty() or not (step.get("step") is Callable):
			GameLogger.error("SaveManager", "未知存档版本 %s（注册表无迁移步骤），拒绝读档：不可按当前版本尽力解析盖戳（P-S3 退役）" % v)
			return false
		data = step["step"].call(data)
		v = str(step.get("to", ""))
		guard += 1
		if guard > 32:
			GameLogger.error("SaveManager", "迁移链异常（超 32 步未抵达 %s），拒绝读档" % SAVE_VERSION)
			return false
	meta["save_version"] = SAVE_VERSION
	GameLogger.info("SaveManager", "存档已迁移：%s → %s" % [origin, SAVE_VERSION])
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

## 回读校验升级（SV-5）：可解析 + checksum 一致双验，避免把半截/被改数据当成存档
func _verify_file(path: String) -> bool:
	var data: Dictionary = _load_json(path)
	if data.is_empty():
		return false
	return _checksum_ok(data)

## 组装完整存档体（13 图 SV-1 SaveHeader 五字段 / P-S5 收口）：
## meta = save_version / game_version / content_version / timestamp / checksum；
## custom_name 保留为 meta 可选扩展字段。
## checksum = 正文（meta 之外全量）SHA-256，写时计算、读时验证（SV-1 冻结口径）。
func _build_save_data(custom_name: String = "") -> Dictionary:
	var body: Dictionary = {}
	for saveable in _saveables:
		var key: String = saveable.get_save_key()
		# SV-2 二段式：每模块键包 {"schema_version", "data"}，模块版本独立演进
		body[key] = {"schema_version": _module_current_version(key), "data": saveable.save()}
	var meta := {
		"save_version": SAVE_VERSION,
		"game_version": str(ProjectSettings.get_setting("application/config/version", "")),
		"content_version": _content_version(),
		"timestamp": Time.get_unix_time_from_system(),
		"checksum": _body_checksum(body),
	}
	if custom_name != "":
		meta["custom_name"] = custom_name
	var save_data: Dictionary = {"meta": meta}
	for k in body:
		save_data[k] = body[k]
	return save_data

## content_version 来源（P-S5 落地口径）：发行环境读 res://provenance.json（RH-2 产物，
## content_fingerprint 与 data/configs 全树同源）；开发环境回退 "dev"。
## 05 图 VE-1 运行时指纹机（已载 pack 排序序列）落地后由此处替换。
func _content_version() -> String:
	if _content_version_cache != "":
		return _content_version_cache
	if FileAccess.file_exists("res://provenance.json"):
		var prov: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://provenance.json"))
		if prov is Dictionary:
			var p: Dictionary = prov
			var cv: String = str(p.get("content_version", ""))
			if cv != "":
				_content_version_cache = cv
				return cv
	_content_version_cache = "dev"
	return _content_version_cache

## 正文校验和（SV-1）：对「JSON 归一化后的正文」取 SHA-256。
## 归一化 = 先 stringify 再 parse 回来：把 Vector2 等运行时类型转成其 JSON 形态，
## 与读端（解析后的纯 JSON 数据）的序列化口径逐字节对齐（回归实录 2026-09-06：
## 直拍内存 dict 曾因 Variant 序列化往返不等导致 _verify_file 拒掉刚写的 tmp）。
func _body_checksum(body: Dictionary) -> String:
	var pure: Variant = JSON.parse_string(JSON.stringify(body))
	var norm: Dictionary = pure if pure is Dictionary else {}
	return JSON.stringify(norm).sha256_text()

## checksum 读端验证（SV-1）：正文重算 SHA-256 与 meta.checksum 比对。
## 老档 meta 无 checksum（1.1.0 前存量）→ 读兼容放行（缺省值渐进，映射表 SV-1 行）。
## 重算统一走 _body_checksum 归一化器：对已解析数据幂等，对内存原始 dict 同样口径一致。
func _checksum_ok(data: Dictionary) -> bool:
	var meta_v: Variant = data.get("meta", {})
	var meta: Dictionary = meta_v if meta_v is Dictionary else {}
	var stored: String = str(meta.get("checksum", ""))
	if stored == "":
		return true
	var body: Dictionary = {}
	for k in data:
		if k != "meta":
			body[k] = data[k]
	return _body_checksum(body) == stored
