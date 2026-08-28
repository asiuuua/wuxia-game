# autoload/game_state.gd
# 全局状态中枢（蓝图 1-2）：集中持有所有「运行时动态数据」，是存档序列化的唯一来源。
# 铁律：外部模块只允许调用本类的公开 API，禁止直接读写内部字典。
# 设计：仅持全局状态，不含任何业务逻辑；业务层只通过 EventBus 通知它更新（见 _ready 订阅）。

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错。

# 单位世界态枚举（与 CombatEnums 解耦，避免中枢层反向依赖战斗层）
enum UnitStatus { ALIVE, DOWNED, DEAD }

# === 运行时状态存储（私有，外部一律走 API） ===
var _global_flags: Dictionary = {}          # 世界开关 / 剧情变量：key(String) -> value(Variant)
var _unit_runtime: Dictionary = {}          # 单位世界态：unit_id -> {status, faction, affinity}
var _difficulty: int = CombatEnums.Difficulty.NORMAL   # 当前全局难度
var _last_safe_point: Dictionary = {"marker": "town", "text_id": "safe_town"}   # 最近安全点（复活点），默认城镇
var _xiaozhang_collateral: Array = []   # 小张抵押物：HARD 团灭丢失的非稀有物 item_id 清单（随存档持久化）
var _quest_phase: int = 1               # 任务阶段（章节进度）：存档唯一真源，外部一律走 API

func _ready() -> void:
	# 订阅战斗结束通知：用单位快照更新 NPC 世界态。
	# 这是「业务层发通知 → 中枢层响应」的合规模式，中枢不反向调用战斗模块。
	EventBus.combat_finished.connect(_on_combat_finished)

# ===================== 全局 flag =====================
func set_global_flag(key: String, value: Variant) -> void:
	_global_flags[key] = value

func get_global_flag(key: String, default_value: Variant = null) -> Variant:
	return _global_flags.get(key, default_value)

func has_global_flag(key: String) -> bool:
	return _global_flags.has(key)

# ===================== 单位世界态 =====================
## 设定某单位存活/倒地/死亡状态（status 取 UnitStatus 枚举值）
func set_unit_status(unit_id: String, status: int) -> void:
	_ensure_unit(unit_id)
	_unit_runtime[unit_id]["status"] = status

## 读取某单位状态，未记录过则默认 ALIVE（避免「未初始化=死亡」的误判）
func get_unit_status(unit_id: String) -> int:
	if not _unit_runtime.has(unit_id):
		return UnitStatus.ALIVE
	return _unit_runtime[unit_id].get("status", UnitStatus.ALIVE)

func is_unit_alive(unit_id: String) -> bool:
	return get_unit_status(unit_id) != UnitStatus.DEAD

func set_unit_faction(unit_id: String, faction: int) -> void:
	_ensure_unit(unit_id)
	_unit_runtime[unit_id]["faction"] = faction

func get_unit_faction(unit_id: String) -> int:
	if not _unit_runtime.has(unit_id):
		return 0
	return _unit_runtime[unit_id].get("faction", 0)

func set_unit_affinity(unit_id: String, affinity: float) -> void:
	_ensure_unit(unit_id)
	_unit_runtime[unit_id]["affinity"] = affinity

func get_unit_affinity(unit_id: String) -> float:
	if not _unit_runtime.has(unit_id):
		return 0.0
	return _unit_runtime[unit_id].get("affinity", 0.0)

# ===================== 难度 =====================
func set_difficulty(value: int) -> void:
	_difficulty = value

func get_difficulty() -> int:
	return _difficulty

# ===================== 任务阶段（章节进度，唯一真源） =====================
func get_quest_phase() -> int:
	return _quest_phase

func set_quest_phase(value: int) -> void:
	if _quest_phase == value:
		return
	_quest_phase = value
	EventBus.quest_phase_changed.emit(_quest_phase)

func advance_quest_phase() -> int:
	set_quest_phase(_quest_phase + 1)
	return _quest_phase

# ===================== 安全点（复活点） =====================
## 记录最近离开的安全点（城镇/客栈等），团灭复活使用
func set_last_safe_point(marker: String, text_id: String) -> void:
	_last_safe_point = {"marker": marker, "text_id": text_id}

func get_last_safe_point() -> Dictionary:
	return _last_safe_point.duplicate()

# ===================== 小张抵押物（HARD 团灭钩子） =====================
## 记录一件被当作抵押物的物品（去重），供后续李村小张赎回线读取
func add_collateral(item_id: String) -> void:
	if not _xiaozhang_collateral.has(item_id):
		_xiaozhang_collateral.append(item_id)

func get_collateral() -> Array:
	return _xiaozhang_collateral.duplicate()

# ===================== 战斗快照接入 =====================
## 战斗结束事件回调：把参战 NPC 的生死写入世界态。
## 快照元素约定：{ "unit_id": String, "is_player": bool, "status": int }
func _on_combat_finished(_combat_id: String, _victory: bool, _escaped: bool, unit_snapshots: Array) -> void:
	apply_combat_snapshot(unit_snapshots)

## 供外部（如剧情指令）直接应用一份快照
func apply_combat_snapshot(unit_snapshots: Array) -> void:
	for snap in unit_snapshots:
		if snap.get("is_player", false):
			continue   # 玩家状态由 PlayerState 管理，不在此处
		var uid: String = snap.get("unit_id", "")
		if uid == "":
			continue
		set_unit_status(uid, int(snap.get("status", UnitStatus.ALIVE)))

# ===================== 存档接口（SaveManager 调用） =====================
func get_save_key() -> String:
	return "game_state"

func save() -> Dictionary:
	return {
		"global_flags": _global_flags.duplicate(),
		"unit_runtime": _unit_runtime.duplicate(true),
		"difficulty": _difficulty,
		"last_safe_point": _last_safe_point.duplicate(),
		"xiaozhang_collateral": _xiaozhang_collateral.duplicate(),
		"quest_phase": _quest_phase,
	}

func load(data: Dictionary) -> void:
	_global_flags = data.get("global_flags", {}).duplicate()
	_unit_runtime = data.get("unit_runtime", {}).duplicate(true)
	_difficulty = int(data.get("difficulty", CombatEnums.Difficulty.NORMAL))
	_last_safe_point = data.get("last_safe_point", {"marker": "town", "text_id": "safe_town"})
	_xiaozhang_collateral = data.get("xiaozhang_collateral", [])
	_quest_phase = int(data.get("quest_phase", 1))

## 新游戏：清空全部运行时状态
func reset() -> void:
	_global_flags.clear()
	_unit_runtime.clear()
	# 难度保留：新游戏前由难度选择界面经 cmd_set_difficulty 写入，reset 不应清空
	_last_safe_point = {"marker": "town", "text_id": "safe_town"}
	_xiaozhang_collateral = []
	_quest_phase = 1

# ===================== 内部辅助 =====================
func _ensure_unit(unit_id: String) -> void:
	if not _unit_runtime.has(unit_id):
		_unit_runtime[unit_id] = {
			"status": UnitStatus.ALIVE,
			"faction": 0,
			"affinity": 0.0,
		}
