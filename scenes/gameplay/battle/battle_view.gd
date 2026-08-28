# scenes/gameplay/battle/battle_view.gd
# 战斗视图层（M2）：接收 CombatEvent，按 type 分派到对应单位的 HUD（飘字/血条/真气条）
# 设计原则（架构文档 §5.1 / §6.2）：
#   - 只播动画，不判断战斗逻辑、不读 CombatState（血条直设 target_hp_after，加速/跳过不错位）
#   - 实现三个约定接口：signal anim_completed / play_event(ev) / set_instant(bool)
# 属战斗窗口主权（scenes/gameplay/battle/），UI 窗口不碰。

extends Control
class_name BattleView

signal anim_completed

var _instant: bool = false
var panels: Dictionary = {}   # character_id -> UnitHud

## 注册某单位的 HUD（BattleScene 装配时调用）
func register_unit(id: String, hud: UnitHud) -> void:
	panels[id] = hud

func set_instant(enabled: bool) -> void:
	_instant = enabled
	for hud in panels.values():
		hud.set_instant(enabled)

## 按事件类型分派演出
func play_event(ev: CombatEvent) -> void:
	match ev.type:
		CombatEvent.Type.DAMAGE:
			_play_damage(ev)
		CombatEvent.Type.HEAL:
			_play_heal(ev)
		CombatEvent.Type.QI_COST:
			_play_mp(ev, ev.actor_mp_after, "-气", Color(0.4, 0.6, 0.95))
		CombatEvent.Type.QI_GAIN:
			_play_mp(ev, ev.target_mp_after, "+气", Color(0.4, 0.8, 0.6))
		CombatEvent.Type.STATUS_APPLIED:
			_pop(ev.target_id, "状态", Color(0.6, 0.9, 0.6))
		CombatEvent.Type.STATUS_TICK:
			_pop(ev.target_id, "%d" % ev.value, Color(0.95, 0.5, 0.2))
		CombatEvent.Type.STATUS_EXPIRED:
			_pop(ev.target_id, "解除", Color(0.7, 0.7, 0.7))
		CombatEvent.Type.SHIELD_ABSORB:
			_play_shield(ev)
		CombatEvent.Type.REFLECT:
			_play_reflect(ev)
		CombatEvent.Type.REVIVE:
			_play_revive(ev)
		_:
			pass
	anim_completed.emit()

func _play_damage(ev: CombatEvent) -> void:
	var hud: UnitHud = panels.get(ev.target_id)
	if hud != null and ev.target_max_hp > 0:
		hud.set_hp(ev.target_hp_after)
	if ev.dodged:
		_pop(ev.target_id, "Miss", Color(0.8, 0.8, 0.8))
	elif ev.crit:
		_pop(ev.target_id, "-%d!" % ev.value, Color(1.0, 0.85, 0.2))
	elif ev.value > 0:
		# 护盾全吸收时 DAMAGE.value==0，跳过难看的 "-0"
		_pop(ev.target_id, "-%d" % ev.value, Color(0.95, 0.3, 0.3))

## 护盾吸收：设盾条宽度 + 青色飘字（吸收量）
func _play_shield(ev: CombatEvent) -> void:
	var hud: UnitHud = panels.get(ev.target_id)
	if hud != null:
		hud.set_shield(ev.target_shield_after)
	_pop(ev.target_id, "盾%d" % ev.value, Color(0.4, 0.95, 0.95))

## 反弹：REFLECT 不发独立 DAMAGE，须按 target_hp_after 更新攻击者血条 + 紫色飘字
func _play_reflect(ev: CombatEvent) -> void:
	var hud: UnitHud = panels.get(ev.target_id)
	if hud != null and ev.target_max_hp > 0:
		hud.set_hp(ev.target_hp_after)
	_pop(ev.target_id, "反弹%d" % ev.value, Color(0.85, 0.4, 0.95))

## 复活：设血条 + 金色闪光特效 + 金色飘字
func _play_revive(ev: CombatEvent) -> void:
	var hud: UnitHud = panels.get(ev.target_id)
	if hud != null and ev.target_max_hp > 0:
		hud.set_hp(ev.target_hp_after)
		hud.play_revive()
	_pop(ev.target_id, "复活!", Color(1.0, 0.85, 0.2))

func _play_heal(ev: CombatEvent) -> void:
	var uid: String = ev.target_id if ev.target_id != "" else ev.actor_id
	var hud: UnitHud = panels.get(uid)
	if hud != null and ev.target_max_hp > 0:
		hud.set_hp(ev.target_hp_after)
	_pop(uid, "+%d" % ev.value, Color(0.4, 0.95, 0.5))

func _play_mp(ev: CombatEvent, mp_after: int, tag: String, color: Color) -> void:
	var uid: String = ev.target_id if ev.target_id != "" else ev.actor_id
	var hud: UnitHud = panels.get(uid)
	if hud != null:
		hud.set_mp(mp_after)
	_pop(uid, tag, color)

func _pop(uid: String, txt: String, color: Color) -> void:
	var hud: UnitHud = panels.get(uid)
	if hud != null:
		hud.pop_text(txt, color)
