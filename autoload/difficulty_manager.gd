# autoload/difficulty_manager.gd
# 难度管理器（蓝图难度系统设计）：独立模块，不侵入任务/剧情/对话业务逻辑。
# 依赖：静态配置表(ConfigManager) + GameState全局状态 + EventBus事件总线。
# 对外只输出系数与配置参数；任务系统、对话系统、存档修复器完全不感知难度内部细节。
# 铁律：禁止任务/剧情逻辑按 difficulty_id 写 if 判断；一律调用本类对外 API。

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错。

const FALLBACK_ID := "NORMAL"

var _current: Dictionary = {}   # 当前难度配置副本（缓存）

func _ready() -> void:
	# 订阅指令事件：UI / 新游戏流程发出切换请求
	EventBus.cmd_set_difficulty.connect(_on_cmd_set_difficulty)
	# 读档后 GameState 难度可能变化，刷新缓存（避免用旧难度系数）
	EventBus.game_loaded.connect(_on_game_loaded)
	_refresh_current()

# ===================== 当前难度推导 =====================
func _current_id_from_state() -> String:
	var d: int = GameState.get_difficulty()
	var keys: Array = CombatEnums.Difficulty.keys()
	if d >= 0 and d < keys.size():
		return keys[d]
	return FALLBACK_ID

func _refresh_current() -> void:
	_current = ConfigManager.get_difficulty(_current_id_from_state())

func _on_game_loaded(_slot: int) -> void:
	_refresh_current()

# ===================== 指令：设置难度 =====================
func _on_cmd_set_difficulty(difficulty_id: String, is_new_game: bool) -> void:
	var entry: Dictionary = ConfigManager.get_difficulty(difficulty_id)
	if entry.is_empty():
		GameLogger.error("DifficultyManager", "难度配置不存在: %s" % difficulty_id)
		return
	# 游戏内切换受 can_change_in_game 约束；新游戏阶段放开全部难度
	if not is_new_game and not bool(entry.get("can_change_in_game", true)):
		EventBus.notify_difficulty_change_rejected.emit(difficulty_id)
		return
	var enum_int: int = CombatEnums.Difficulty.get(difficulty_id, -1)
	if enum_int < 0:
		GameLogger.error("DifficultyManager", "难度枚举不存在: %s" % difficulty_id)
		return
	GameState.set_difficulty(enum_int)
	_current = entry
	EventBus.notify_difficulty_changed.emit(difficulty_id)

# ===================== 对外 API（战斗模块唯一入口，零 if 判断难度） =====================
func get_current_difficulty_id() -> String:
	return _current_id_from_state()

## 玩家输出伤害倍率
func get_player_damage_scale() -> float:
	return float(_current.get("player_damage_mult", 1.0))

## 敌人伤害倍率
func get_enemy_damage_scale() -> float:
	return float(_current.get("enemy_damage_mult", 1.0))

## 敌人血量倍率
func get_enemy_hp_scale() -> float:
	return float(_current.get("enemy_hp_mult", 1.0))

## 敌人防御/抗性倍率
func get_enemy_armor_scale() -> float:
	return float(_current.get("enemy_armor_mult", 1.0))

## 逃跑成功率修正值（正数提升，负数降低；HELL 通过 allow_escape=false 直接禁止）
func get_escape_bonus() -> float:
	return float(_current.get("escape_modifier", 0.0))

## 是否允许逃跑（HELL 关闭）
func get_allow_escape() -> bool:
	return bool(_current.get("allow_escape", true))

## 是否允许非致命击倒（NIGHTMARE/HELL 关闭）
func get_allow_non_lethal() -> bool:
	return bool(_current.get("allow_non_lethal", true))

## 当前难度对应的敌方 AI 行为配置 ID（战斗据此加载不同 AI 模板）
func get_enemy_ai_profile_id() -> String:
	return String(_current.get("ai_behavior_profile", "default"))

# ===================== 团灭死亡行为（消费端执行器在阶段2 接入，本步只给配置与 API） =====================
## 团灭基础动作（RESPAWN_CHECKPOINT / LOAD_LATEST_SAVE / DELETE_SAVE 等）
func get_player_defeat_behaviour() -> int:
	var s: String = String(_current.get("defeat_behaviour", "LOAD_LATEST_SAVE"))
	return CombatEnums.DefeatBehaviour.get(s, CombatEnums.DefeatBehaviour.LOAD_LATEST_SAVE)

## 团灭丢失银两数（0 表示不扣）
func get_defeat_lose_money() -> int:
	return int(_current.get("defeat_lose_money", 0))

## 团灭是否丢失少量非稀有道具
func get_defeat_lose_items() -> bool:
	return bool(_current.get("defeat_lose_items", false))

## 没钱支付时是否转为负债
func get_defeat_debt_if_broke() -> bool:
	return bool(_current.get("defeat_debt_if_broke", false))

## 团灭触发隐藏 CG / 对话的 text_id（空串表示无）
func get_defeat_cg_text_id() -> String:
	return String(_current.get("defeat_cg_text_id", ""))

## 团灭丢失的非稀有物数量（0 表示不丢）
func get_defeat_lose_item_count() -> int:
	return int(_current.get("defeat_lose_item_count", 0))

## 团灭 CG 是否仅在「没钱支付」分支触发（true 时只在 broke 时播 CG）
func get_defeat_cg_when_broke_only() -> bool:
	return bool(_current.get("defeat_cg_when_broke_only", false))

## 某难度是否游戏内锁定（供 UI 决定是否灰显）
func is_difficulty_locked(difficulty_id: String) -> bool:
	var e: Dictionary = ConfigManager.get_difficulty(difficulty_id)
	return not bool(e.get("can_change_in_game", true))
