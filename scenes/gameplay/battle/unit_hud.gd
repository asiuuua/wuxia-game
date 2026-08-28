# scenes/gameplay/battle/unit_hud.gd
# 单个战斗单位的 HUD（M2 演出层用）：名字 + 血条 + 真气条 + 状态行 + 飘字
# 纯视图，不读战斗逻辑；max_hp/max_mp 由 BattleScene 装配时 setup 注入。
# 属战斗窗口主权。

extends Control
class_name UnitHud

var _name: Label
var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _shield_fill: ColorRect
var _mp_bg: ColorRect
var _mp_fill: ColorRect
var _status: HBoxContainer
var _instant: bool = false
var _max_hp: int = 100
var _max_mp: int = 100

const BAR_W: float = 200.0

func _ready() -> void:
	custom_minimum_size = Vector2(220, 64)
	_name = Label.new()
	add_child(_name)
	_hp_bg = ColorRect.new(); _hp_bg.color = Color(0.25, 0.1, 0.1)
	_hp_bg.size = Vector2(BAR_W, 10); _hp_bg.position = Vector2(0, 22); add_child(_hp_bg)
	_hp_fill = ColorRect.new(); _hp_fill.color = Color(0.9, 0.2, 0.2)
	_hp_fill.size = Vector2(BAR_W, 10); _hp_fill.position = Vector2(0, 22); add_child(_hp_fill)
	# 护盾条：血条上方一条青色细条，宽度按 shield/max_hp；初始宽 0（无盾隐藏）
	_shield_fill = ColorRect.new(); _shield_fill.color = Color(0.4, 0.95, 0.95)
	_shield_fill.size = Vector2(0, 4); _shield_fill.position = Vector2(0, 18); add_child(_shield_fill)
	_mp_bg = ColorRect.new(); _mp_bg.color = Color(0.1, 0.15, 0.3)
	_mp_bg.size = Vector2(BAR_W, 6); _mp_bg.position = Vector2(0, 34); add_child(_mp_bg)
	_mp_fill = ColorRect.new(); _mp_fill.color = Color(0.3, 0.5, 0.95)
	_mp_fill.size = Vector2(BAR_W, 6); _mp_fill.position = Vector2(0, 34); add_child(_mp_fill)
	_status = HBoxContainer.new(); _status.position = Vector2(0, 44); add_child(_status)

## 装配：名字 + 上下限（据此算血条比例）
func setup(name_text: String, max_hp: int, max_mp: int) -> void:
	_name.text = name_text
	_max_hp = max_hp; _max_mp = max_mp
	set_hp(max_hp); set_mp(max_mp)

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
	flash.size = Vector2(220, 64)
	flash.position = Vector2(0, 0)
	add_child(flash)
	var t := create_tween()
	t.tween_property(flash, "modulate:a", 0.0, 0.35)
	t.tween_callback(flash.queue_free)

func _tween_bar(bar: ColorRect, target_w: float) -> void:
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

## 飘字：在 HUD 本地坐标 (90,14) 上飘并淡出
func pop_text(txt: String, color: Color) -> void:
	var l := Label.new()
	l.text = txt
	l.modulate = color
	l.position = Vector2(90, 14)
	add_child(l)
	if _instant:
		l.queue_free()
		return
	var t := create_tween()
	t.tween_property(l, "position:y", -22.0, 0.5)
	t.parallel().tween_property(l, "modulate:a", 0.0, 0.5)
	t.tween_callback(l.queue_free)
