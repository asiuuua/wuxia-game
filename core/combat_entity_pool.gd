# core/combat_entity_pool.gd
# 战斗实体对象池（工业化扩容 P4 · 第5层）：跨战斗复用 BattleEntity / UnitHud，
# 消除每场/每次移动 new/free 抖动与内存泄漏；空闲表有界回收，内存恒定可控。
#
# 设计：
#   - 空闲表（free list）保存已脱离场景树的实例；acquire 优先取空闲实例，否则 new。
#   - release 将实例脱离父节点、reset 清零后入空闲表；超出容量上限则 queue_free 真正回收（防内存膨胀）。
#   - 纯静态工具 + class_name 全局调用，不注册 Autoload、不碰共享地基（对齐 PortraitCacheManager 模式）。
#     静态空闲表在引擎会话内常驻 → 自然跨战斗/跨场景复用；上限裁剪保证内存有界。

class_name CombatEntityPool

const MAX_ENTITIES: int = 64
const MAX_HUDS: int = 64

# 空闲实例（已脱离场景树，等待复用）
static var _free_entities: Array[BattleEntity] = []
static var _free_huds: Array[UnitHud] = []

## 取一个 BattleEntity（已 setup 配置好）：空闲表空则新建，否则复用并清零重置。
static func acquire_entity(uid: String, player: bool, name_text: String, max_hp: int, max_mp: int, grid_node: Node) -> BattleEntity:
	var ent: BattleEntity
	if _free_entities.is_empty():
		ent = BattleEntity.new()
	else:
		ent = _free_entities.pop_back()
	ent.setup(uid, player, name_text, max_hp, max_mp, grid_node)
	return ent

## 取一个 UnitHud（已 setup 配置好）：空闲表空则新建，否则复用并清零重置。
static func acquire_hud(name_text: String, max_hp: int, max_mp: int) -> UnitHud:
	var hud: UnitHud
	if _free_huds.is_empty():
		hud = UnitHud.new()
	else:
		hud = _free_huds.pop_back()
	hud.setup(name_text, max_hp, max_mp)
	return hud

## 归还一个 BattleEntity：脱离父节点 → reset 清零 → 入空闲表；超额则真正释放。
static func release_entity(ent: BattleEntity) -> void:
	if ent == null:
		return
	if ent.get_parent() != null:
		ent.get_parent().remove_child(ent)
	ent.reset("")
	_free_entities.append(ent)
	_trim_entities()

## 归还一个 UnitHud：脱离父节点 → reset 清零 → 入空闲表；超额则真正释放。
static func release_hud(hud: UnitHud) -> void:
	if hud == null:
		return
	if hud.get_parent() != null:
		hud.get_parent().remove_child(hud)
	hud.reset()
	_free_huds.append(hud)
	_trim_huds()

## 主动清空空闲表（切场景/退出时调用，防残留累计）
static func clear() -> void:
	for e in _free_entities:
		e.queue_free()
	_free_entities.clear()
	for h in _free_huds:
		h.queue_free()
	_free_huds.clear()

static func get_free_entity_count() -> int:
	return _free_entities.size()

static func get_free_hud_count() -> int:
	return _free_huds.size()

static func _trim_entities() -> void:
	while _free_entities.size() > MAX_ENTITIES:
		var e: BattleEntity = _free_entities.pop_back()
		e.queue_free()

static func _trim_huds() -> void:
	while _free_huds.size() > MAX_HUDS:
		var h: UnitHud = _free_huds.pop_back()
		h.queue_free()
