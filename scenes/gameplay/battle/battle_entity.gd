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
var _anim_body: AnimatedSprite2D = null   # 主角动态立绘（is_player 且有帧序列时启用，否则为 null）
var _anim_base_scale_x: float = 1.0       # 主角动态立绘基准缩放 X（set_facing 翻转向保留缩放用）
var _name_lbl: Label
var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _mp_bg: ColorRect
var _mp_fill: ColorRect
var _sel_ring: ColorRect
var _pop_layer: Node2D
var _pop_pool: Array[Label] = []    # 飘字复用池（P2-7：避免高频 new/free）
var _pop_active: Array[Label] = []  # 当前播放中的飘字顺序（7.3.5 特效预算：用于回收最旧）
var _pop_pending: Array[Dictionary] = []  # 7.3.5 优化：超限时不丢弃，排队稍后播放（梦幻式）
var _move_tween: Tween = null

# 7.3.5 特效预算：单实体飘字并发上限与排队兜底。
# 上限是「每个单位」独立计算：20 个敌人 = 20 个独立池，不会互相抢上限。
# 超过上限时先入队，等正在播放的飘字结束再出队，避免直接截断/丢弃数字。
const MAX_POPS: int = 48
const MAX_QUEUE: int = 32

const SPRITE_W: float = 40.0
const SPRITE_H: float = 52.0
const BAR_W: float = 44.0
# 主角动态立绘首帧（用于在无 SpriteFrames 帧上下文时取尺寸做缩放；matte 序列固定 720×1280）
const MATTE_FIRST_FRAME := "res://assets/characters/matte/matte_00001.png"

## 装配（可重复调用，对象池复用安全）：首次构建视觉子节点，之后仅重置清零。
## frames_path：主角动态立绘的 SpriteFrames 资源路径；为空则主角仍用色块占位（与敌人一致）。
func setup(uid: String, player: bool, name_text: String, max_hp: int, max_mp: int, grid_node: Node, frames_path: String = "res://assets/characters/matte_clean/matte_clean_idle.tres") -> void:
	unit_id = uid
	is_player = player
	_max_hp = max_hp
	_max_mp = max_mp
	_hp = max_hp
	_mp = max_mp
	_grid_node = grid_node
	if not _built:
		_build(frames_path)
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
	if _body != null and _body is ColorRect:
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
			_finish_pop(l)
			l.free()
	_pop_pool.clear()
	_pop_active.clear()
	_pop_pending.clear()

func _build(frames_path: String = "") -> void:
	_built = true
	# 主角动态立绘：用 SpriteFrames 帧序列做 AnimatedSprite2D（脚下锚定，与色块占位同尺寸盒）
	# 注意：无论走动画还是色块，_sel_ring/_name_lbl/血条都必须在末尾统一构建（不可提前 return）。
	if is_player and frames_path != "" and ResourceLoader.exists(frames_path):
		var frames: SpriteFrames = load(frames_path) as SpriteFrames
		if frames != null and frames.has_animation("idle"):
			var anim := AnimatedSprite2D.new()
			anim.sprite_frames = frames
			anim.play("idle")
			# 尺寸取首帧 PNG（直接 load，避免 headless 下 get_frame_texture 惰性返回 null）
			var tex0: Texture2D = load(MATTE_FIRST_FRAME) as Texture2D
			if tex0 == null:
				tex0 = frames.get_frame_texture("idle", 0)
			if tex0 != null:
				var fh: float = float(tex0.get_height())
				var s: float = SPRITE_H / fh
				anim.scale = Vector2(s, s)
				# 居中绘制；把脚底对齐到色块占位底部（-SPRITE_H），与 ColorRect 站位一致
				anim.position = Vector2(0.0, -SPRITE_H - (fh * s) * 0.5)
				anim.centered = true
				add_child(anim)
				_anim_body = anim
				# 占位色块保留作几何参照，主角用贴图覆盖故隐藏
				_body = ColorRect.new()
				_body.size = Vector2(SPRITE_W, SPRITE_H)
				_body.position = Vector2(-SPRITE_W * 0.5, -SPRITE_H)
				_body.color = Color(0.3, 0.5, 0.95)
				_body.visible = false
				add_child(_body)
			else:
				# 帧纹理不可用降级：可见色块占位
				_body = ColorRect.new()
				_body.size = Vector2(SPRITE_W, SPRITE_H)
				_body.position = Vector2(-SPRITE_W * 0.5, -SPRITE_H)
				_body.color = Color(0.3, 0.5, 0.95)
				add_child(_body)
		else:
			# frames 无效降级：可见色块占位
			_body = ColorRect.new()
			_body.size = Vector2(SPRITE_W, SPRITE_H)
			_body.position = Vector2(-SPRITE_W * 0.5, -SPRITE_H)
			_body.color = Color(0.3, 0.5, 0.95)
			add_child(_body)
	else:
		# 敌人 / 无帧序列：色块占位（玩家蓝、敌人红）
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
	# 记录主角动态立绘的基准缩放，供 set_facing 翻转时保留（避免 scale.x 被设成 ±1 丢失缩放）
	if _anim_body != null:
		_anim_base_scale_x = _anim_body.scale.x
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
		position = gn.cell_center(grid_pos)
	set_facing(CombatCharacter.FACING.DOWN)   # 出生默认面朝下（占位；接入贴图后按枚举切帧）

## 面朝：纯逻辑枚举驱动视图表现；斜45°映射只在视图层做（P1）
## 动态立绘翻转 AnimatedSprite2D；色块占位翻转 ColorRect。
func set_facing(f: int) -> void:
	var flip: float = -1.0 if f == CombatCharacter.FACING.LEFT else 1.0
	if _anim_body != null:
		_anim_body.scale.x = flip * _anim_base_scale_x   # 保留基准缩放，仅翻转向
	elif _body != null:
		_body.scale.x = flip

## 动画移动（GRID_MOVE 事件驱动）；instant=true 时直接落位（跳过模式用）
func move_to(grid_pos: Vector2i, instant: bool = false) -> void:
	var old: Vector2i = _grid_pos
	_grid_pos = grid_pos
	if old != grid_pos:
		set_facing(CombatCharacter.calc_facing(old, grid_pos))   # 仅真实移动时按逻辑坐标差值更朝向
	if _grid_node == null:
		return
	var gn := _grid_node as BattleGridNode
	var target := gn.cell_center(grid_pos)
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
	# 7.3.5 优化：优先立即播放；当前实体所有 Label 都在忙且池满时，入队稍后播放（不丢弃）
	if _can_spawn_pop():
		_spawn_pop(txt, color)
	elif _pop_pending.size() < MAX_QUEUE:
		_pop_pending.append({"txt": txt, "color": color})
	else:
		# 队列也满：兜底丢弃最旧的一条（极端罕见，正常战斗不会触发）
		_pop_pending.pop_front()
		_pop_pending.append({"txt": txt, "color": color})

## 是否能立即播放：有空闲 Label，或池未达单实体上限
func _can_spawn_pop() -> bool:
	for l in _pop_pool:
		if is_instance_valid(l) and not l.visible:
			return true
	return _pop_pool.size() < MAX_POPS

## 实际生成一条飘字
func _spawn_pop(txt: String, color: Color) -> void:
	var l := _acquire_pop()
	# 若该标签还在播上一段动画（回收复用情形），先停掉，避免两段 tween 叠放错乱
	var old_tw = null
	if l.has_meta("pop_tween"):
		old_tw = l.get_meta("pop_tween")
	if old_tw != null and is_instance_valid(old_tw):
		old_tw.kill()
	l.text = txt
	l.modulate = color
	l.modulate.a = 1.0
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.visible = true
	l.position = Vector2(-14.0, -SPRITE_H - 32.0)
	var t := create_tween()
	t.tween_property(l, "position:y", -SPRITE_H - 64.0, 0.5)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(func(): _release_pop(l))
	l.set_meta("pop_tween", t)
	if not (l in _pop_active):
		_pop_active.append(l)

## 飘字复用（7.3.5 限额）：优先复用空闲标签；池未满则新建；达上限时交给 _pop_pending 排队
func _acquire_pop() -> Label:
	for l in _pop_pool:
		if is_instance_valid(l) and not l.visible:
			return l
	if _pop_pool.size() < MAX_POPS:
		var l := Label.new()
		_pop_layer.add_child(l)
		_pop_pool.append(l)
		return l
	# 理论上不会走到这里（pop_text 会先入队）；兜底返回池首，避免 null
	return _pop_pool[0]

## 立即结束某飘字动画并隐藏（清理路径用，不触发队列）
func _finish_pop(l: Label) -> void:
	if not is_instance_valid(l):
		return
	var tw = null
	if l.has_meta("pop_tween"):
		tw = l.get_meta("pop_tween")
	if tw != null and is_instance_valid(tw):
		tw.kill()
	l.visible = false
	l.modulate.a = 1.0
	var idx := _pop_active.find(l)
	if idx >= 0:
		_pop_active.remove_at(idx)

## 飘字动画结束归还池（仅隐藏，等待下次复用），然后触发队列中下一条
func _release_pop(l: Label) -> void:
	if not is_instance_valid(l):
		return
	l.visible = false
	var idx := _pop_active.find(l)
	if idx >= 0:
		_pop_active.remove_at(idx)
	_dequeue_next_pop()

## 队列下一条出队播放；每条等上一条播完再出，避免一帧爆开
func _dequeue_next_pop() -> void:
	if _pop_pending.is_empty():
		return
	var p: Dictionary = _pop_pending.pop_front()
	_spawn_pop(p.get("txt", ""), p.get("color", Color.WHITE))
