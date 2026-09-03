# services/quest/flag_store.gd
# 状态存储(FlagStore)：对标大厂"全局 Facts / Globals"。集中读写 布尔/任意键值/好感/任务进度。
# 设计：运行时默认托管在 GameState._global_flags（存档唯一真源，随存档持久化）；
#       测试/离线场景用 FlagStore.new(false) 拿内存独立存储，便于隔离断言。不持有 Node。
class_name FlagStore
extends RefCounted

const FAVID_PREFIX := "favor:"
const PROGRESS_PREFIX := "progress:"

var _use_game_state: bool = true
var _mem: Dictionary = {}

func _init(use_global: bool = true) -> void:
	_use_game_state = use_global
	if not use_global:
		_mem = {}

# ---------- 通用布尔 / 任意键值 ----------
func get_flag(key: String, default_value: Variant = null) -> Variant:
	if _use_game_state:
		return GameState.get_global_flag(key, default_value)
	return _mem.get(key, default_value)

func set_flag(key: String, value: Variant) -> void:
	if _use_game_state:
		GameState.set_global_flag(key, value)
	else:
		_mem[key] = value

func has_flag(key: String) -> bool:
	if _use_game_state:
		return GameState.has_global_flag(key)
	return _mem.has(key)

# ---------- 好感（对某 NPC 的数值关系，落到 global_flags 命名空间） ----------
func get_favor(npc_id: String) -> float:
	return float(get_flag(FAVID_PREFIX + npc_id, 0.0))

func add_favor(npc_id: String, delta: float) -> void:
	set_flag(FAVID_PREFIX + npc_id, get_favor(npc_id) + delta)

# ---------- 任务进度 ----------
func get_progress(quest_id: String) -> int:
	return int(get_flag(PROGRESS_PREFIX + quest_id, 0))

func set_progress(quest_id: String, value: int) -> void:
	set_flag(PROGRESS_PREFIX + quest_id, value)