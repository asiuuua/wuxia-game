# scenes/gameplay/battle/unit_hud.gd
# 单个战斗单位的 HUD（M2 演出层用）：名字 + 血条 + 真气条 + 护盾条 + 状态行 + 飘字
# 纯视图，不读战斗逻辑；max_hp/max_mp 由 BattleScene 装配时 setup 注入。
# 属战斗窗口主权。
# 工业化（P4·第5层）：视觉子节点惰性构建一次（_ensure_built），setup/reset 可重复调用，
#              对象池复用前 reset() 清零状态行/护盾/飘字，杜绝回收复用残留。

extends Control
class_name UnitHud

var _name: Label
var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _shield_fill: ColorRect
var _mp_bg: ColorRect
var _mp_fill: ColorRect
var _status: HBoxContainer
var _portrait: TextureRect = null
var _pop_layer: Node2D = null
var _pop_pool: Array[Label] = []   # 飘字复用池（P2-7：避免高频 new/free）
var _instant: bool = false
var _max_hp: int = 100
var _max_mp: int = 100
var _built: bool = false

const BAR_W: float = 200.0
const PORTRAIT_W: float = 56.0   # 头像宽；布局整体右移，原元素 x 偏移 PORTRAIT_W

func _ready() -> void:
	_ensure_built()

## 惰性构建全部视觉子节点（首次 setup/set_portrait 前确保存在；对象池复用不再重建）
func _ensure_built() -> void:
	if _built:
		return
	_built = true
	custom_minimum_size = Vector2(220 + PORTRAIT_W, 64)
	_name = Label.new()
	add_child(_name)
	_name.position = Vector2(PORTRAIT_W, 0)
	_hp_bg = ColorRect.new(); _hp_bg.color = Color(0.25, 0.1, 0.1)
	_hp_bg.size = Vector2(BAR_W, 10); _hp_bg.position = Vector2(PORTRAIT_W, 22); add_child(_hp_bg)
	_hp_fill = ColorRect.new(); _hp_fill.color = Color(0.9, 0.2, 0.2)
	_hp_fill.size = Vector2(BAR_W, 10); _hp_fill.position = Vector2(PORTRAIT_W, 22); add_child(_hp_fill)
	# 护盾条：血条上方一条青色细条，宽度按 shield/max_hp；初始宽 0（无盾隐藏）
	_shield_fill = ColorRect.new(); _shield_fill.color = Color(0.4, 0.95, 0.95)
	_shield_fill.size = Vector2(0, 4); _shield_fill.position = Vector2(PORTRAIT_W, 18); add_child(_shield_fill)
	_mp_bg = ColorRect.new(); _mp_bg.color = Color(0.1, 0.15, 0.3)
	_mp_bg.size = Vector2(BAR_W, 6); _mp_bg.position = Vector2(PORTRAIT_W, 34); add_child(_mp_bg)
	_mp_fill = ColorRect.new(); _mp_fill.color = Color(0.3, 0.5, 0.95)
	_mp_fill.size = Vector2(BAR_W, 6); _mp_fill.position = Vector2(PORTRAIT_W, 34); add_child(_mp_fill)
	_status = HBoxContainer.new(); _status.position = Vector2(PORTRAIT_W, 44); add_child(_status)
	_pop_layer = Node2D.new(); add_child(_pop_layer)
	_ensure_portrait()

## 装配：名字 + 上下限（据此算血条比例）；可重复调用（对象池复用安全）
func setup(name_text: String, max_hp: int, max_mp: int) -> void:
	_ensure_built()
	_name.text = name_text
	_max_hp = max_hp; _max_mp = max_mp
	set_hp(max_hp); set_mp(max_mp)

## 回收复用前的重置：清零状态行 / 护盾 / 飘字（对象池 release→acquire 间调用）
func reset() -> void:
	if not _built:
		return
	_instant = false
	for c in _status.get_children():
		c.free()
	set_shield(0)
	_clear_pops()

func _clear_pops() -> void:
	if _pop_layer == null:
		return
	for l in _pop_pool:
		if is_instance_valid(l):
			l.free()
	_pop_pool.clear()

## 头像：按图标 id 取图（缺图显占位图，不崩）；由 BattleScene 装配时调用
## 惰性自建 _portrait，即便 _ready 尚未执行也可挂图（健壮性更强）
func set_portrait(icon_id: String) -> void:
	_ensure_built()
	_ensure_portrait()
	_portrait.texture = UIManager.get_icon(icon_id)

## 自建头像槽（_ready 与 set_portrait 共用，避免重复逻辑）
func _ensure_portrait() -> void:
	if _portrait != null:
		return
	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.size = Vector2(PORTRAIT_W, PORTRAIT_W)
	_portrait.position = Vector2(0, 4)
	add_child(_portrait)

func set_hp(hp: int) -> void:
	var ratio: float = clampf(float(hp) / float(_max_hp), 0.0, 1.0)
	_tween_bar(_hp_fill, BAR_W * ratio)

func set_mp(mp: int) -> void:
	var ratio: float = clampf(float(mp) / float(_max_mp), 0.0, 1.0)
	_tween_bar(_mp_fill, BAR_W * ratio)

## 护盾条：按 shield / max_hp 比例（盾以气血单位计，故相对 max_hp 显示）
func set_shield(shield: int) -> void:
	var ratio: float = clampf(float(shield) / max(1.0, float(_max_hp)), 0.0, 1.0)
	_tween_bar(_shield_fill, BAR_W * ratio)

## 复活特效：金色闪光覆盖 HUD 后淡出（服从 _instant）
func play_revive() -> void:
	if _instant:
		return
	var flash := ColorRect.new()
	flash.color = Color(1.0, 0.85, 0.2, 0.55)
	flash.size = Vector2(220 + PORTRAIT_W, 64)
	flash.position = Vector2(0, 0)
	add_child(flash)
	var t := create_tween()
	t.tween_property(flash, "modulate:a", 0.0, 0.35)
	t.tween_callback(flash.queue_free)

func _tween_bar(bar: ColorRect, target_w: float) -> void:
	if not is_inside_tree():
		# 装配阶段可能先 setup 再 add_child，此时 tween 需要节点已在树中；直接落位即可
		bar.size.x = target_w
		return
	if _instant:
		bar.size.x = target_w
		return
	var t := create_tween()
	t.tween_property(bar, "size:x", target_w, 0.18)

## 状态行：entries 为 [ [status_id, stacks], ... ]
func set_status(entries: Array) -> void:
	for c in _status.get_children():
		c.queue_free()
	for e in entries:
		var lbl := Label.new()
		lbl.text = "%s%d" % [String(e[0]), int(e[1])]
		lbl.add_theme_color_override("font_color", Color(0.8, 0.9, 0.6))
		_status.add_child(lbl)

func set_instant(enabled: bool) -> void:
	_instant = enabled

## 飘字：在 HUD 本地坐标 (90,14) 上飘并淡出；跳过模式 (_instant) 不飘字
func pop_text(txt: String, color: Color) -> void:
	_ensure_built()
	if _instant:
		return
	var l := _acquire_pop()
	l.text = txt
	l.modulate = color
	l.visible = true
	l.position = Vector2(90 + PORTRAIT_W, 14)
	var t := create_tween()
	t.tween_property(l, "position:y", -22.0, 0.5)
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
