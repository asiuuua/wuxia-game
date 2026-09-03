# autoload/ConfigManager.gd
# 配置表管理器：启动时加载所有 JSON 配置，提供按 ID 查询能力
# 设计：逻辑与数据分离，所有数值写在 data/configs，绝不硬编码进代码

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

# 配置表路径集中管理（禁止散落硬编码路径）
const ABILITY_FILES: Array[String] = [
	"res://data/configs/abilities/skills.json",
]
const ITEM_FILES: Array[String] = [
	"res://data/configs/items/weapons.json",
	"res://data/configs/items/pills.json",
	"res://data/configs/items/equipment.json",
	"res://data/configs/items/materials.json",
]
const ENEMY_FILES: Array[String] = [
	"res://data/configs/npcs/enemies.json",
]
const BATTLE_FILES: Array[String] = [
	"res://data/configs/scenes/battles.json",
]
const QUEST_FILES: Array[String] = [
	"res://data/configs/quests/quests.json",
]
const NPC_FILES: Array[String] = [
	"res://data/configs/npcs/town_npcs.json",
]
# 对话分片（P1 工业化扩容）：单文件拆分为 per-dialog 分片 + 全局索引
# 启动只加载 KB 级索引；get_dialog 按需懒加载分片、闲置自动卸载（pin 保护进行中对话）
const DIALOG_INDEX_FILE: String = "res://data/configs/npcs/dialogs/_index.json"
const DIALOG_CACHE_MAX: int = 256
const DIALOG_IDLE_TTL_MS: int = 2000

# 对话事件映射（事件键 -> 效果数组；trigger_events 引用）
const DIALOG_EVENT_FILES: Array[String] = [
	"res://data/configs/dialogs/dialogue_events.json",
]

const PLAYER_FILES: Array[String] = [
	"res://data/configs/player.json",
]

# 难度配置表（阶段1 骨架：5 档完整参数，全部配置驱动，零硬编码）
const DIFFICULTY_FILES: Array[String] = [
	"res://data/configs/difficulty/difficulty_table.json",
]

# 炼药配方配置（Phase 2 炼药系统）
const RECIPE_FILES: Array[String] = [
	"res://data/configs/alchemy/recipes.json",
]

# 锻造配方配置（Phase 2 系统填充 · 契约层）
const FORGE_FILES: Array[String] = [
	"res://data/configs/forge/recipes.json",
]

# 商店配置（Phase 2 系统填充 · 契约层）
const SHOP_FILES: Array[String] = [
	"res://data/configs/shop/shops.json",
]

# 门派配置（Phase 2 系统填充 · 契约层）
const SECT_FILES: Array[String] = [
	"res://data/configs/sect/sects.json",
]

# 结缘系统 NPC 关系配置（模块18 · M1；字段前向兼容 M2+ 婚礼/结义/师徒）
const RELATION_FILES: Array[String] = [
	"res://data/configs/bond/relations.json",
]

# 世界环境配置（阶段A 基础设施：时间/天气/季节调参）
const WORLD_FILES: Array[String] = [
	"res://data/configs/world/world_config.json",
]

# UI 动效令牌（2026-08-29 配置层：时长/缓动/缩放幅度，改手感只改表）
const UI_ANIM_FILES: Array[String] = [
	"res://data/configs/ui/ui_anim.json",
]

# UI 音效映射（2026-08-29 配置层：事件名 -> 路径 + 音量；文件缺失静默跳过）
const UI_SFX_FILES: Array[String] = [
	"res://data/configs/ui/ui_sfx.json",
]
const MENU_FILES: Array[String] = ["res://data/configs/ui/menu_config.json"]

# 战斗数值换算表（阶段A：五维根属性→面板属性派生；整表 Dictionary，非 id 键控）
const COMBAT_ATTR_FILE := "res://data/configs/combat/attribute_table.json"

# 区域配置仓库（区域化剧情骨架）：总索引 + 区域目录。区域对白登记进 _dialog_index 走懒加载
const REGION_MAP_INDEX := "res://data/configs/regions/_map_index.json"
const REGION_DIR := "res://data/configs/regions/"

var _abilities: Dictionary = {}
var _items: Dictionary = {}
var _enemies: Dictionary = {}
var _battles: Dictionary = {}
var _quests: Dictionary = {}
var _npcs: Dictionary = {}
var _dialog_index: Dictionary = {}
var _dialog_cache: Dictionary = {}      # dialog_id -> 已加载分片（懒加载）
var _dialog_pinned: Dictionary = {}     # dialog_id -> pin 计数（>0 时禁止卸载）
var _dialog_last_access: Dictionary = {}
var _dialog_last_sweep: int = 0
var _dialog_events: Dictionary = {}   # 对话事件：事件键 -> 效果数组
var _difficulties: Dictionary = {}
var _recipes: Dictionary = {}
var _forge: Dictionary = {}
var _shops: Dictionary = {}
var _sects: Dictionary = {}
var _relations: Dictionary = {}   # 结缘系统 NPC 关系数据（模块18 · M1）
var _world_config: Dictionary = {}
var _ui_anim: Dictionary = {}   # UI 动效令牌（整体 Dictionary，非 id 键控）
var _ui_sfx: Dictionary = {}    # UI 音效映射（整体 Dictionary，非 id 键控）
var _status_effects: Dictionary = {}   # 状态效果配置（战斗核心懒加载用；纯追加，零硬编码取用口）
var _combat_attr: Dictionary = {}   # 战斗数值换算表（阶段A；整表 Dictionary，非 id 键控）
var _config_version: String = ""
var _is_loaded: bool = false
var _config_errors: Array[String] = []  # 配置容错层：累积加载/引用校验发现的问题

func _ready() -> void:
	_config_errors.clear()
	_load_abilities()
	_load_items()
	_load_enemies()
	_load_battles()
	_load_quests()
	_load_npcs()
	_load_dialogs()
	_load_dialog_events()
	_load_player()
	_load_difficulties()
	_load_recipes()
	_load_forge()
	_load_shops()
	_load_sects()
	_load_relations()
	_load_world()
	_load_ui_anim()
	_load_ui_sfx()
	_load_menus()
	_load_combat_attr()
	_load_regions()
	_validate_references()
	_flush_config_errors()
	_is_loaded = true

## 配置是否加载完成（Bootstrap 启动序列查询）
func is_loaded() -> bool:
	return _is_loaded

# === 各系统配置加载（含条目级容错守卫）===
# 守卫规则：每条必须是对象且含非空 id；否则记录并跳过，绝不崩溃

func _load_abilities() -> void:
	for path in ABILITY_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("skills", []):
			if not _is_valid_entry(entry, path, "skills"):
				continue
			var id: String = str(entry["id"])
			if _abilities.has(id):
				_record_error("技能 %s 重复定义，后者覆盖" % id)
			_abilities[id] = entry

func _load_items() -> void:
	for path in ITEM_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("items", []):
			if not _is_valid_entry(entry, path, "items"):
				continue
			var id: String = str(entry["id"])
			if _items.has(id):
				_record_error("物品 %s 重复定义，后者覆盖" % id)
			_items[id] = entry

func _load_enemies() -> void:
	for path in ENEMY_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("enemies", []):
			if not _is_valid_entry(entry, path, "enemies"):
				continue
			var id: String = str(entry["id"])
			if _enemies.has(id):
				_record_error("敌人 %s 重复定义，后者覆盖" % id)
			_enemies[id] = entry

func _load_battles() -> void:
	for path in BATTLE_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("battles", []):
			if not _is_valid_entry(entry, path, "battles"):
				continue
			var id: String = str(entry["id"])
			if _battles.has(id):
				_record_error("战斗 %s 重复定义，后者覆盖" % id)
			_battles[id] = entry

func _load_quests() -> void:
	for path in QUEST_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("quests", []):
			if not _is_valid_entry(entry, path, "quests"):
				continue
			var id: String = str(entry["id"])
			if _quests.has(id):
				_record_error("任务 %s 重复定义，后者覆盖" % id)
			_quests[id] = entry

func _load_npcs() -> void:
	for path in NPC_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("npcs", []):
			if not _is_valid_entry(entry, path, "npcs"):
				continue
			var id: String = str(entry["id"])
			if _npcs.has(id):
				_record_error("NPC %s 重复定义，后者覆盖" % id)
			_npcs[id] = entry

# 启动只加载全局索引（KB 级常驻）；分片内容按需懒加载
func _load_dialogs() -> void:
	var data: Dictionary = _load_json(DIALOG_INDEX_FILE)
	if data.is_empty():
		_record_error("对话索引缺失或解析失败: %s" % DIALOG_INDEX_FILE)
		return
	_config_version = data.get("version", _config_version)
	for did in data.get("shards", {}).keys():
		var entry: Dictionary = data["shards"][did]
		if not (entry is Dictionary) or not entry.has("file"):
			_record_error("对话索引 %s 条目缺 file 字段，已跳过" % did)
			continue
		if _dialog_index.has(did):
			_record_error("对话 %s 索引重复定义，后者覆盖" % did)
		_dialog_index[did] = entry

func _load_dialog_events() -> void:
	for path in DIALOG_EVENT_FILES:
		var data: Dictionary = _load_json(path)
		var events: Dictionary = data.get("events", {})
		for key in events.keys():
			var lst: Array = events[key]
			if not (lst is Array):
				_record_error("对话事件 %s 效果须为数组" % key)
				continue
			if _dialog_events.has(key):
				_record_error("对话事件 %s 重复定义，后者覆盖" % key)
			_dialog_events[key] = lst

func _load_difficulties() -> void:
	for path in DIFFICULTY_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("difficulties", []):
			if not _is_valid_entry(entry, path, "difficulties", "difficulty_id"):
				continue
			var id: String = str(entry["difficulty_id"])
			if _difficulties.has(id):
				_record_error("难度 %s 重复定义，后者覆盖" % id)
			_difficulties[id] = entry

func _load_recipes() -> void:
	for path in RECIPE_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("recipes", []):
			if not _is_valid_entry(entry, path, "recipes"):
				continue
			var id: String = str(entry["id"])
			if _recipes.has(id):
				_record_error("配方 %s 重复定义，后者覆盖" % id)
			_recipes[id] = entry

func _load_forge() -> void:
	for path in FORGE_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("recipes", []):
			if not _is_valid_entry(entry, path, "forge_recipes"):
				continue
			var id: String = str(entry["id"])
			if _forge.has(id):
				_record_error("锻造配方 %s 重复定义，后者覆盖" % id)
			_forge[id] = entry

func _load_shops() -> void:
	for path in SHOP_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("shops", []):
			if not _is_valid_entry(entry, path, "shops"):
				continue
			var id: String = str(entry["id"])
			if _shops.has(id):
				_record_error("商店 %s 重复定义，后者覆盖" % id)
			_shops[id] = entry

func _load_sects() -> void:
	for path in SECT_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("sects", []):
			if not _is_valid_entry(entry, path, "sects"):
				continue
			var id: String = str(entry["id"])
			if _sects.has(id):
				_record_error("门派 %s 重复定义，后者覆盖" % id)
			_sects[id] = entry

# === 结缘系统 NPC 关系配置（模块18 · M1） ===
func _load_relations() -> void:
	for path in RELATION_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		for entry in data.get("relations", []):
			if not _is_valid_entry(entry, path, "relations"):
				continue
			var id: String = str(entry["id"])
			if _relations.has(id):
				_record_error("关系 NPC %s 重复定义，后者覆盖" % id)
			_relations[id] = entry

func _load_world() -> void:
	for path in WORLD_FILES:
		var data: Dictionary = _load_json(path)
		_config_version = data.get("version", _config_version)
		if data.size() > 0:
			_world_config = data

# === UI 动效 / 音效配置（2026-08-29 配置层落地）===
# 二者都是「整表 Dictionary」而非 id 键控，直接整存；读取一律走带兜底的 get_*，
# 配置缺失或写错都不影响运行（退回默认值，不崩）。

func _load_ui_anim() -> void:
	for path in UI_ANIM_FILES:
		var data: Dictionary = _load_json(path)
		if data.size() > 0:
			_config_version = data.get("version", _config_version)
			_ui_anim = data

func _load_ui_sfx() -> void:
	for path in UI_SFX_FILES:
		var data: Dictionary = _load_json(path)
		if data.size() > 0:
			_config_version = data.get("version", _config_version)
			_ui_sfx = data

## 取时长令牌（秒）
func get_anim_duration(token: String, fallback: float = 0.12) -> float:
	return float(_ui_anim.get("durations", {}).get(token, fallback))

## 取缓动曲线类型（Godot Tween.TransitionType）
func get_anim_trans(token: String, fallback: int = Tween.TRANS_QUAD) -> int:
	match String(_ui_anim.get("easings", {}).get(token, {}).get("trans", "")):
		"LINEAR": return Tween.TRANS_LINEAR
		"SINE": return Tween.TRANS_SINE
		"QUAD": return Tween.TRANS_QUAD
		"CUBIC": return Tween.TRANS_CUBIC
		"QUART": return Tween.TRANS_QUART
		"QUINT": return Tween.TRANS_QUINT
		"EXPO": return Tween.TRANS_EXPO
		"BACK": return Tween.TRANS_BACK
		"ELASTIC": return Tween.TRANS_ELASTIC
		"BOUNCE": return Tween.TRANS_BOUNCE
		"CIRC": return Tween.TRANS_CIRC
		_: return fallback

## 取缓动进出方向（Godot Tween.EaseType）
func get_anim_ease(token: String, fallback: int = Tween.EASE_OUT) -> int:
	match String(_ui_anim.get("easings", {}).get(token, {}).get("ease", "")):
		"IN": return Tween.EASE_IN
		"OUT": return Tween.EASE_OUT
		"IN_OUT": return Tween.EASE_IN_OUT
		"OUT_IN": return Tween.EASE_OUT_IN
		_: return fallback

## 取整组动效预设（hover / press / focus / screen / toast）
func get_anim_preset(preset: String) -> Dictionary:
	return _ui_anim.get(preset, {})

## 取预设里的数值项，如 get_anim_value("hover", "scale")
func get_anim_value(preset: String, key: String, fallback: float = 1.0) -> float:
	return float(get_anim_preset(preset).get(key, fallback))

## 取预设里的时长（自动从 durations 令牌解析成秒）
func get_anim_preset_duration(preset: String, fallback: float = 0.12) -> float:
	var token: String = String(get_anim_preset(preset).get("duration", ""))
	if token == "":
		return fallback
	return get_anim_duration(token, fallback)

## 取音效事件配置；事件不存在返回空 Dictionary（调用方据此静默跳过）
func get_ui_sfx(event: String) -> Dictionary:
	return _ui_sfx.get("events", {}).get(event, {})

## 音效总线名
func get_ui_sfx_bus() -> String:
	return String(_ui_sfx.get("bus", "SFX"))

## 音效播放器池大小：避免鼠标快速划过多个按钮时后一个音切断前一个
func get_ui_sfx_pool_size() -> int:
	return int(_ui_sfx.get("pool_size", 4))

# === 状态效果配置（战斗核心懒加载取用口 · 纯追加）===
# 不暴露硬编码路径：由本方法内部按集中常量懒加载，调用方只传 id。
const STATUS_EFFECTS_FILE := "res://data/configs/abilities/status_effects.json"
var _status_effects_loaded: bool = false

func get_status_effect(id: String) -> Dictionary:
	if not _status_effects_loaded:
		_load_status_effects()
	if not _status_effects.has(id):
		return {}
	return _status_effects[id]

## 状态效果整表（战斗核心本地缓存一次性填充用）
func get_status_effect_table() -> Dictionary:
	if not _status_effects_loaded:
		_load_status_effects()
	return _status_effects

func _load_status_effects() -> void:
	var data: Dictionary = _load_json(STATUS_EFFECTS_FILE)
	for s in data.get("status_effects", []):
		if s is Dictionary and s.has("id"):
			_status_effects[str(s["id"])] = s
	_status_effects_loaded = true

## UI 动效整表（战斗演出等需要直接读 battle 令牌时长时取用，避免重复打开文件）
func get_ui_anim_table() -> Dictionary:
	return _ui_anim

# === 配置容错层（阶段落地：异常容错）===
# 目标：填错 ID / 配置写错 → 记录 + 跳过 + 继续运行，绝不崩溃

# 单条配置是否合法：必须是对象且含非空 id 字段
func _is_valid_entry(entry: Variant, path: String, category: String, id_field: String = "id") -> bool:
	if not (entry is Dictionary):
		_record_error("%s | %s 条目不是对象，已跳过" % [path.get_file(), category])
		return false
	var d: Dictionary = entry as Dictionary
	var id: String = str(d.get(id_field, "")).strip_edges()
	if id.is_empty():
		_record_error("%s | %s 条目缺少字段 '%s'，已跳过" % [path.get_file(), category, id_field])
		return false
	return true

# 记录一条配置问题（同时进日志缓冲 + 引擎错误输出）
func _record_error(msg: String) -> void:
	_config_errors.append(msg)
	push_error("[Config] " + msg)

# 跨表引用校验：悬空引用记录警告，被引用方缺失的条目在运行时由各自 get_x 返回 {} 兜底
func _validate_references() -> void:
	# 任务 → 战斗（目标）/ 物品（奖励）
	for qid in _quests.keys():
		var q: Dictionary = _quests[qid]
		for obj in q.get("objectives", []):
			var b_id: String = str(obj.get("target_battle", "")).strip_edges()
			if not b_id.is_empty() and not has_battle(b_id):
				_record_error("任务 %s 引用了不存在的战斗 %s，该任务目标将无法触发" % [qid, b_id])
		for it in q.get("rewards", {}).get("items", []):
			var i_id: String = str(it.get("item_id", "")).strip_edges()
			if not i_id.is_empty() and not has_item(i_id):
				_record_error("任务 %s 奖励引用了不存在的物品 %s" % [qid, i_id])
	# 战斗 → 敌人
	for bid in _battles.keys():
		var b: Dictionary = _battles[bid]
		for e_id in b.get("enemy_ids", []):
			var e: String = str(e_id).strip_edges()
			if not e.is_empty() and not has_enemy(e):
				_record_error("战斗 %s 引用了不存在的敌人 %s，该敌人将被跳过" % [bid, e])
	# NPC → 任务 / 战斗 / 对话
	for nid in _npcs.keys():
		var n: Dictionary = _npcs[nid]
		var q_id: String = str(n.get("quest_id", "")).strip_edges()
		if not q_id.is_empty() and not has_quest(q_id):
			_record_error("NPC %s 引用了不存在的任务 %s" % [nid, q_id])
		var b_id: String = str(n.get("battle_id", "")).strip_edges()
		if not b_id.is_empty() and not has_battle(b_id):
			_record_error("NPC %s 引用了不存在的战斗 %s" % [nid, b_id])
		var d_id: String = str(n.get("dialog_id", "")).strip_edges()
		if not d_id.is_empty() and not has_dialog(d_id):
			_record_error("NPC %s 引用了不存在的对话 %s" % [nid, d_id])
	# 对话 → 任务（若对话带接取任务）；遍历索引逐个懒加载校验
	for did in _dialog_index.keys():
		var d: Dictionary = get_dialog(did)
		if d.is_empty():
			continue
		var q_id: String = str(d.get("quest_id", "")).strip_edges()
		if not q_id.is_empty() and not has_quest(q_id):
			_record_error("对话 %s 引用了不存在的任务 %s" % [did, q_id])

# 将累积的配置问题写入可读日志（供小白排查），并打印到控制台
func _flush_config_errors() -> void:
	if _config_errors.is_empty():
		return
	var log_path := "user://config_errors.log"
	var f: FileAccess = FileAccess.open(log_path, FileAccess.WRITE)
	if f != null:
		f.store_line("【武侠江湖 配置校验报告】生成时间: " + Time.get_datetime_string_from_system())
		f.store_line("共发现 %d 处配置问题，游戏已跳过这些条目继续运行：" % _config_errors.size())
		f.store_line("=".repeat(40))
		for e in _config_errors:
			f.store_line("- " + e)
		f.close()
	GameLogger.warn("Config", "配置校验发现 %d 处问题，详见: %s" % [_config_errors.size(), ProjectSettings.globalize_path(log_path)])
	for e in _config_errors:
		GameLogger.warn("Config", "[配置问题] " + e)

# === 技能 ===
func get_ability(id: String) -> Dictionary:
	if not _abilities.has(id):
		push_error("[Config] 技能不存在: %s" % id)
		return {}
	return _abilities[id]

func has_ability(id: String) -> bool:
	return _abilities.has(id)

func get_all_ability_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_abilities.keys())
	return out

# === 物品 ===
func get_item(id: String) -> Dictionary:
	if not _items.has(id):
		push_error("[Config] 物品不存在: %s" % id)
		return {}
	return _items[id]

func has_item(id: String) -> bool:
	return _items.has(id)

# === 敌人 ===
func get_enemy(id: String) -> Dictionary:
	if not _enemies.has(id):
		push_error("[Config] 敌人不存在: %s" % id)
		return {}
	return _enemies[id]

func has_enemy(id: String) -> bool:
	return _enemies.has(id)

# === 战斗配置 ===
func get_battle(id: String) -> Dictionary:
	if not _battles.has(id):
		push_error("[Config] 战斗配置不存在: %s" % id)
		return {}
	return _battles[id]

func has_battle(id: String) -> bool:
	return _battles.has(id)

# === 战棋布局资源（资源驱动：底图/战斗共享同一份网格几何）===
## 底图配置：返回 { "tactical_layout": "<layout_id>" }；底图不存在返回空字典
func get_map_layout(map_id: String) -> Dictionary:
	if map_id == "":
		return {}
	return _load_json("res://data/configs/maps/%s.json" % map_id)

## 战棋布局资源：返回 { "width", "height", "obstacles", "deployment"? }；不存在返回空字典
func get_battle_layout(layout_id: String) -> Dictionary:
	if layout_id == "":
		return {}
	return _load_json("res://data/configs/battles/grids/%s.json" % layout_id)

# === 世界区域（填表模式：data/configs/world/regions.json）===
# 共享地基增量（只增不改）：新增 get_region / get_all_region_ids / get_region_connections。
var _regions: Dictionary = {}
var _regions_loaded: bool = false

func _ensure_regions() -> void:
	if _regions_loaded:
		return
	_regions = _load_json("res://data/configs/world/regions.json")
	# 剔除 _ 开头的元数据键（如 _doc），仅保留真实区域
	for k in _regions.keys():
		if k.begins_with("_"):
			_regions.erase(k)
	_regions_loaded = true

## 取单个区域配置：{"name","scene_path","type","connections"}；不存在返回空字典
func get_region(id: String) -> Dictionary:
	_ensure_regions()
	return _regions.get(id, {})

## 全部区域 id 列表
func get_all_region_ids() -> Array[String]:
	_ensure_regions()
	var out: Array[String] = []
	out.assign(_regions.keys())
	return out

## 某区域可直达的区域 id 列表；无配置返回空数组
func get_region_connections(id: String) -> Array[String]:
	var r: Dictionary = get_region(id)
	var c: Array = r.get("connections", [])
	var out: Array[String] = []
	out.assign(c)
	return out

# === 区域配置仓库（region 剧情骨架 · 纯增量）===
# 把 regions/ 下各区域的 npc/quest/item/battle/enemy 合并进全局查询表；
# 区域对白登记进 _dialog_index，复用已有"分片懒加载 + 闲置卸载 + pin"机制。
var _region_index: Dictionary = {}   # region_id -> index.json 元信息
var _region_loaded: bool = false

func _load_regions() -> void:
	if _region_loaded:
		return
	_region_loaded = true
	var map: Dictionary = _load_json(REGION_MAP_INDEX)
	for r in map.get("regions", []):
		if not (r is Dictionary) or not r.has("region_id"):
			_record_error("区域总索引存在非法条目，已跳过")
			continue
		var rid: String = str(r["region_id"])
		var idx: Dictionary = _load_json(_region_path(rid, "index.json"))
		if idx.is_empty():
			_record_error("区域 %s 缺失 index.json 点名册，跳过该区域" % rid)
			continue
		if _region_index.has(rid):
			_record_error("区域 %s 重复定义，后者覆盖" % rid)
		_region_index[rid] = idx
		_merge_region_kind(rid, "npcs", _npcs, "NPC")
		_merge_region_kind(rid, "quests", _quests, "任务")
		_merge_region_kind(rid, "items", _items, "物品")
		_merge_region_kind(rid, "battles", _battles, "战斗")
		_merge_region_kind(rid, "enemies", _enemies, "敌人")
		_register_region_dialogs(rid, idx)

## 区域文件绝对路径：res://data/configs/regions/<rid>/<fname>
func _region_path(rid: String, fname: String) -> String:
	return "%s%s/%s" % [REGION_DIR, rid, fname]

## 把某个区域的某类实体并入全局查询表（重复则以区域为准覆盖）
func _merge_region_kind(rid: String, kind: String, target: Dictionary, label: String) -> void:
	var path := _region_path(rid, kind + ".json")
	var data: Dictionary = _load_json(path)
	for entry in data.get(kind, []):
		if not _is_valid_entry(entry, path, "region_" + kind):
			continue
		var eid: String = str(entry["id"])
		if target.has(eid):
			_record_error("区域 %s 的%s %s 与全局重复，后者覆盖" % [rid, label, eid])
		target[eid] = entry

## 把区域对白登记进懒加载索引（不加载内容，get_dialog 时才现取）
func _register_region_dialogs(rid: String, idx: Dictionary) -> void:
	for did in idx.get("dialogs", []):
		var key: String = str(did)
		if _dialog_index.has(key):
			_record_error("区域 %s 对话 %s 索引重复，后者覆盖" % [rid, key])
		_dialog_index[key] = {"file": _region_path(rid, "dialogs/%s.json" % key)}

## 取区域元信息（display_name / prefix / plotline / 各实体清单）；不存在返回空字典
func get_region_meta(rid: String) -> Dictionary:
	return _region_index.get(rid, {})

## 取全部区域元信息（region_id -> index 内容）
func get_all_region_meta() -> Dictionary:
	return _region_index

## 取区域剧情一句话（plotline），用于地图/剧情指引展示
func get_region_plotline(rid: String) -> String:
	return String(get_region_meta(rid).get("plotline", ""))

## 取区域内特定实体清单（如 get_region_entity_list("newbie_village","npcs")）
func get_region_entity_list(rid: String, kind: String) -> Array[String]:
	var idx: Dictionary = get_region_meta(rid)
	var arr: Array = idx.get(kind, [])
	var out: Array[String] = []
	out.assign(arr)
	return out

# === 任务 ===
func get_quest(id: String) -> Dictionary:
	if not _quests.has(id):
		push_error("[Config] 任务不存在: %s" % id)
		return {}
	return _quests[id]

func has_quest(id: String) -> bool:
	return _quests.has(id)

# === NPC ===
func get_npc(id: String) -> Dictionary:
	if not _npcs.has(id):
		push_error("[Config] NPC 不存在: %s" % id)
		return {}
	return _npcs[id]

func has_npc(id: String) -> bool:
	return _npcs.has(id)

func get_all_npc_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_npcs.keys())
	return out

# === 对话（分片懒加载 + 闲置自动卸载 + pin 保护） ===
func get_dialog(id: String) -> Dictionary:
	# 1) 命中缓存直接返回
	if _dialog_cache.has(id):
		_dialog_last_access[id] = Time.get_ticks_msec()
		return _dialog_cache[id]
	# 2) 索引中没有该 id
	if not _dialog_index.has(id):
		push_error("[Config] 对话不存在: %s" % id)
		return {}
	# 3) 按索引懒加载分片
	var file: String = _dialog_index[id].get("file", "")
	var entry: Dictionary = _load_json(file)
	if entry.is_empty():
		_record_error("对话分片加载失败: %s (%s)" % [id, file])
		return {}
	_dialog_cache[id] = entry
	_dialog_last_access[id] = Time.get_ticks_msec()
	_sweep_idle_dialogs()
	return entry

func has_dialog(id: String) -> bool:
	return _dialog_index.has(id)

## 钉住：进行中的对话禁止被闲置回收（引用计数）
func pin_dialog(id: String) -> void:
	_dialog_pinned[id] = int(_dialog_pinned.get(id, 0)) + 1

## 解钉
func unpin_dialog(id: String) -> void:
	var n: int = int(_dialog_pinned.get(id, 0)) - 1
	if n <= 0:
		_dialog_pinned.erase(id)
	else:
		_dialog_pinned[id] = n

## 主动卸载（pin 中则跳过）
func unload_dialog(id: String) -> void:
	if int(_dialog_pinned.get(id, 0)) > 0:
		return
	_dialog_cache.erase(id)
	_dialog_last_access.erase(id)

## 闲置回收：超过 TTL 或超出缓存上限的未 pin 分片自动释放
func _sweep_idle_dialogs() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _dialog_last_sweep < 250:
		return
	_dialog_last_sweep = now
	var expired: Array[String] = []
	for did in _dialog_cache.keys():
		if int(_dialog_pinned.get(did, 0)) > 0:
			continue
		var last: int = int(_dialog_last_access.get(did, 0))
		if now - last > DIALOG_IDLE_TTL_MS:
			expired.append(did)
	if _dialog_cache.size() > DIALOG_CACHE_MAX:
		var sorted: Array = Array(_dialog_cache.keys())
		sorted.sort_custom(func(a: String, b: String) -> bool: return int(_dialog_last_access.get(a, 0)) < int(_dialog_last_access.get(b, 0)))
		for did in sorted:
			if int(_dialog_pinned.get(did, 0)) > 0:
				continue
			if _dialog_cache.size() <= DIALOG_CACHE_MAX:
				break
			expired.append(did)
	for did in expired:
		if int(_dialog_pinned.get(did, 0)) > 0:
			continue
		_dialog_cache.erase(did)
		_dialog_last_access.erase(did)

## 取全部对话 id（基于索引，不触达分片）
func get_all_dialog_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_dialog_index.keys())
	return out

## 取某对话绑定的 NPC id（P1 分片索引的 npc_id 字段；用于多 NPC 剧情隔离与归属校验）。
## 未绑定（如 dlg_tutorial 这类通用剧情）返回空串。
func get_dialog_npc_id(dialog_id: String) -> String:
	if _dialog_index.has(dialog_id):
		return String(_dialog_index[dialog_id].get("npc_id", ""))
	return ""

## 取某事件键对应的效果数组；未配置返回空数组
func get_dialogue_event(key: String) -> Array:
	return _dialog_events.get(key, [])

# === 玩家角色（双立绘左立绘来源；数据驱动，不硬编码）===
var _player: Dictionary = {}

func _load_player() -> void:
	for path in PLAYER_FILES:
		var data: Dictionary = _load_json(path)
		if data.is_empty():
			continue
		_player = data

func get_player() -> Dictionary:
	return _player

# === 难度配置（阶段1 骨架） ===
func get_difficulty(id: String) -> Dictionary:
	if not _difficulties.has(id):
		push_error("[Config] 难度配置不存在: %s" % id)
		return {}
	return _difficulties[id]

func has_difficulty(id: String) -> bool:
	return _difficulties.has(id)

func get_all_difficulty_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_difficulties.keys())
	return out

# === 炼药配方 ===
func get_recipe(id: String) -> Dictionary:
	if not _recipes.has(id):
		push_error("[Config] 配方不存在: %s" % id)
		return {}
	return _recipes[id]

func has_recipe(id: String) -> bool:
	return _recipes.has(id)

func get_all_recipe_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_recipes.keys())
	return out

# === 锻造配方（Phase 2 系统填充 · 契约层） ===
func get_forge_recipe(id: String) -> Dictionary:
	if not _forge.has(id):
		push_error("[Config] 锻造配方不存在: %s" % id)
		return {}
	return _forge[id]

func has_forge_recipe(id: String) -> bool:
	return _forge.has(id)

func get_all_forge_recipe_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_forge.keys())
	return out

# === 商店（Phase 2 系统填充 · 契约层） ===
func get_shop(id: String) -> Dictionary:
	if not _shops.has(id):
		push_error("[Config] 商店不存在: %s" % id)
		return {}
	return _shops[id]

func has_shop(id: String) -> bool:
	return _shops.has(id)

func get_all_shop_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_shops.keys())
	return out

# === 门派（Phase 2 系统填充 · 契约层） ===
func get_sect(id: String) -> Dictionary:
	if not _sects.has(id):
		push_error("[Config] 门派不存在: %s" % id)
		return {}
	return _sects[id]

func has_sect(id: String) -> bool:
	return _sects.has(id)

func get_all_sect_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_sects.keys())
	return out

# === 结缘系统 NPC 关系（模块18 · M1） ===
func get_relation(id: String) -> Dictionary:
	if not _relations.has(id):
		push_error("[Config] 关系 NPC 不存在: %s" % id)
		return {}
	return _relations[id]

func has_relation(id: String) -> bool:
	return _relations.has(id)

func get_all_relation_ids() -> Array[String]:
	var out: Array[String] = []
	out.assign(_relations.keys())
	return out

## 测试注入：向关系表临时登记一个 NPC（仅单元测试用）。调用方必须在 after_each 里
## 用 unregister_test_relation 移除，避免残留污染生产数据与后续计数类测试。
func register_test_relation(id: String, data: Dictionary) -> void:
	_relations[id] = data

## 撤销测试注入的关系 NPC
func unregister_test_relation(id: String) -> void:
	_relations.erase(id)

# === 世界环境（阶段A 基础设施） ===
func get_world_config() -> Dictionary:
	return _world_config

func get_config_version() -> String:
	return _config_version

# ---- 菜单配置（数据驱动菜单/按钮）：action_id → screen/badge/icon_id ----
var _menus: Dictionary = {}

func get_menu_config() -> Dictionary:
	if _menus.is_empty():
		_load_menus()
	return _menus

## 按 action_id 解析菜单项（screen/badge/icon_id/nav...）；找不到返回空 Dictionary
func get_menu_item(action_id: String) -> Dictionary:
	if _menus.is_empty():
		_load_menus()
	for cat in _menus.get("categories", []):
		for item in cat.get("items", []):
			if String(item.get("action_id", "")) == action_id:
				return item
	return {}

func _load_menus() -> void:
	var data: Dictionary = _load_json(MENU_FILES[0])
	if data.is_empty():
		return
	_menus = data

# === 战斗数值换算表（阶段A：五维根属性→面板属性派生）===
# 整表 Dictionary 直接整存；所有换算系数集中此处，代码只读取不硬编码（derive_mode=flat 时零回归）。
func _load_combat_attr() -> void:
	var data: Dictionary = _load_json(COMBAT_ATTR_FILE)
	if data.is_empty():
		push_warning("[Config] 战斗数值换算表缺失或为空: %s" % COMBAT_ATTR_FILE)
		return
	_combat_attr = data

## 取整张战斗数值换算表（空则返回 {}）
func get_combat_attr() -> Dictionary:
	return _combat_attr

## 当前派生模式：flat（扁平，原有行为）/ five_attr（五维派生）；缺省 flat
func get_derive_mode() -> String:
	return String(_combat_attr.get("derive_mode", "flat"))

## 取五维根属性→面板换算系数（attr=五维名，panel=面板名）；缺失返回 fallback
func get_five_attr_weight(attr: String, panel: String, fallback: float = 0.0) -> float:
	var weights: Dictionary = _combat_attr.get("five_attr_weights", {})
	var node: Dictionary = weights.get(attr, {})
	return float(node.get(panel, fallback))

## 防御软上限 K（reduction = 1 - K/(K+有效防御)）；缺省 60
func get_defense_softcap_k() -> float:
	return float(_combat_attr.get("defense", {}).get("soft_cap_k", 60.0))

func _load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_warning("[Config] 数据文件不存在这种情况应前置避免: %s" % path)
		return {}
	var f := FileAccess.open(path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var parsed = JSON.parse_string(text)
	if parsed == null:
		push_error("[Config] JSON 解析失败: %s" % path)
		return {}
	return parsed
