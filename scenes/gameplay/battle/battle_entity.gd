# scenes/gameplay/battle/battle_entity.gd
# 战术战棋单位实体（战斗窗口主权）：Node2D 占位精灵 + 头顶悬浮血条/真气条 + 选中环
# 职责：
#   - place_at / move_to：按网格坐标落位（立即）或 Tween 插值移动（GRID_MOVE 事件驱动）
#   - set_hp / set_mp：据事件直设血条（加速/跳过不错位，与 M2 BattleView 约定一致）
#   - pop_text：伤害/治疗/状态飘字
# ⚠️ 不持有战斗逻辑；只做表现。网格坐标换算委托 BattleGridNode.cell_center。
# 工业化（P4·第5层）：视觉子节点只在首次 _build 创建一次，setup 可重复调用（对象池复用）；
#              reset() 清零血条/真气/选中/飘字，杜绝回收复用残留。

extends Node2D
class_name BattleEntity

var unit_id: String = ""
var is_player: bool = false
var _max_hp: int = 100
var _hp: int = 100
var _max_mp: int = 50
var _mp: int = 50
var _grid_pos: Vector2i = Vector2i.ZERO
var _grid_node: Node = null

var _built: bool = false
var _body: ColorRect
var _name_lbl: Label
var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _mp_bg: ColorRect
var _mp_fill: ColorRect
var _sel_ring: ColorRect
var _pop_layer: Node2D
var _pop_pool: Array[Label] = []   # 飘字复用池（P2-7：避免高频 new/free）
var _move_tween: Tween = null

const SPRITE_W: float = 40.0
const SPRITE_H: float = 52.0
const BAR_W: float = 44.0

## 装配（可重复调用，对象池复用安全）：首次构建视觉子节点，之后仅重置清零。
func setup(uid: String, player: bool, name_text: String, max_hp: int, max_mp: int, grid_node: Node) -> void:
	unit_id = uid
	is_player = player
	_max_hp = max_hp
	_max_mp = max_mp
	_hp = max_hp
	_mp = max_mp
	_grid_node = grid_node
	if not _built:
		_build()
	_reset_visual(name_text)

## 回收复用前的重置：清零血条/真气/选中/飘字，重设名称与阵营配色（对象池 release→acquire 间调用）
func reset(name_text: String = "") -> void:
	if not _built:
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
		_move_tween = null
	_reset_visual(name_text)

func _reset_visual(name_text: String) -> void:
	if name_text != "" and _name_lbl != null:
		_name_lbl.text = name_text
	if _body != null:
		_body.color = Color(0.3, 0.5, 0.95) if is_player else Color(0.85, 0.35, 0.35)
	set_selected(false)
	_clear_pops()
	_refresh_bars()

func _clear_pops() -> void:
	if _pop_layer == null:
		return
	# 回收飘字池（reset/复用前清空，杜绝残留飘字与已释放引用）
	for l in _pop_pool:
		if is_instance_valid(l):
			l.free()
	_pop_pool.clear()

func _build() -> void:
	_built = true
	# 身体占位（玩家蓝、敌人红）
	_body = ColorRect.new()
	_body.size = Vector2(SPRITE_W, SPRITE_H)
	_body.position = Vector2(-SPRITE_W * 0.5, -SPRITE_H)
	_body.color = Color(0.3, 0.5, 0.95) if is_player else Color(0.85, 0.35, 0.35)
	add_child(_body)
	# 选中高亮环（默认透明）
	_sel_ring = ColorRect.new()
	_sel_ring.size = Vector2(SPRITE_W + 10, SPRITE_H + 10)
	_sel_ring.position = Vector2(-(SPRITE_W + 10) * 0.5, -SPRITE_H - 5)
	_sel_ring.color = Color(1.0, 0.85, 0.2, 0.0)
	add_child(_sel_ring)
	# 名字
	_name_lbl = Label.new()
	_name_lbl.text = ""
	_name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_lbl.position = Vector2(-30.0, -SPRITE_H - 22.0)
	_name_lbl.add_theme_color_override("font_color", Color(0.95, 0.95, 0.95))
	_name_lbl.add_theme_font_size_override("font_size", 13)
	add_child(_name_lbl)
	# 血条 / 真气条（悬浮于头顶）
	_hp_bg = ColorRect.new(); _hp_bg.color = Color(0.2, 0.1, 0.1)
	_hp_bg.size = Vector2(BAR_W, 6); _hp_bg.position = Vector2(-BAR_W * 0.5, -SPRITE_H - 14.0); add_child(_hp_bg)
	_hp_fill = ColorRect.new(); _hp_fill.color = Color(0.9, 0.25, 0.25)
	_hp_fill.size = Vector2(BAR_W, 6); _hp_fill.position = _hp_bg.position; add_child(_hp_fill)
	_mp_bg = ColorRect.new(); _mp_bg.color = Color(0.1, 0.15, 0.3)
	_mp_bg.size = Vector2(BAR_W, 4); _mp_bg.position = Vector2(-BAR_W * 0.5, -SPRITE_H - 7.0); add_child(_mp_bg)
	_mp_fill = ColorRect.new(); _mp_fill.color = Color(0.35, 0.55, 0.95)
	_mp_fill.size = Vector2(BAR_W, 4); _mp_fill.position = _mp_bg.position; add_child(_mp_fill)
	_pop_layer = Node2D.new(); add_child(_pop_layer)

func _refresh_bars() -> void:
	_hp_fill.size.x = BAR_W * clampf(float(_hp) / float(_max_hp), 0.0, 1.0)
	_mp_fill.size.x = BAR_W * clampf(float(_mp) / float(_max_mp), 0.0, 1.0)

## 立即落位（初始化用）
func place_at(grid_pos: Vector2i) -> void:
	_grid_pos = grid_pos
	if _grid_node != null:
		var gn := _grid_node as BattleGridNode
		position = gn.cell_center(grid_pos) + Vector2(0, -10.0)

## 动画移动（GRID_MOVE 事件驱动）；instant=true 时直接落位（跳过模式用）
func move_to(grid_pos: Vector2i, instant: bool = false) -> void:
	_grid_pos = grid_pos
	if _grid_node == null:
		return
	var gn := _grid_node as BattleGridNode
	var target := gn.cell_center(grid_pos) + Vector2(0, -10.0)
	if instant:
		position = target
		return
	if _move_tween != null and _move_tween.is_valid():
		_move_tween.kill()
	_move_tween = create_tween()
	_move_tween.tween_property(self, "position", target, 0.25)

func set_hp(hp: int) -> void:
	_hp = hp
	_refresh_bars()

func set_mp(mp: int) -> void:
	_mp = mp
	_refresh_bars()

func set_selected(sel: bool) -> void:
	_sel_ring.color = Color(1.0, 0.85, 0.2, 0.5 if sel else 0.0)

func pop_text(txt: String, color: Color) -> void:
	var l := _acquire_pop()
	l.text = txt
	l.modulate = color
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.visible = true
	l.position = Vector2(-14.0, -SPRITE_H - 32.0)
	var t := create_tween()
	t.tween_property(l, "position:y", -SPRITE_H - 64.0, 0.5)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): _release_pop(l))

## 飘字复用：从池中取一个空闲 Label，无则新建并登记（P2-7 池化，避免高频 new/free）
func _acquire_pop() -> Label:
	for l in _pop_pool:
		if is_instance_valid(l) and not l.visible:
			return l
	var l := Label.new()
	_pop_layer.add_child(l)
	_pop_pool.append(l)
	return l

## 飘字动画结束归还池（仅隐藏，等待下次复用）；节点已释放则忽略
func _release_pop(l: Label) -> void:
	if not is_instance_valid(l):
		return
	l.visible = false
