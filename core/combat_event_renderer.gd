# core/combat_event_renderer.gd
# 共享战斗事件渲染器（P0-2）：把 CombatEvent 统一映射到"可渲染单位"的表现接口。
# 旧 BattleView（驱动 UnitHud）与战术 TacticalBattleScene（驱动 BattleEntity）都委托本类，
# 新增事件类型只改此处，消除两套并行实现的分歧风险。
# 可渲染单位约定接口：set_hp(int) / set_mp(int) / set_shield(int，可选) /
#                      pop_text(String,Color) / play_revive()(可选 REVIVE 闪光)。
# 缺少的方法用 has_method 兜底跳过（BattleEntity 无护盾条/复活闪光即只飘字+设血）。
# 属战斗窗口主权（经 core 共享，不新增 autoload，符合项目铁律）。

class_name CombatEventRenderer
extends RefCounted

# 基准演出时长（秒），与 battle_director.gd _FALLBACK 对齐（无 ui_anim 表时的兜底）
const _FALLBACK := {
	"damage_pop": 0.12,
	"hit_shake": 0.12,
	"gentle": 0.1,
	"fast": 0.05,
	"status": 0.05,
	"shield_absorb": 0.08,
	"reflect": 0.08,
	"revive": 0.1,
}

## 渲染单个战斗事件。lookup: Callable 接收 character_id 返回单位对象（UnitHud / BattleEntity），找不到返回 null 即跳过
## instant=true 时跳过飘字（跳过模式用；旧战斗 UnitHud 自带 _instant 走默认 false 即可）
static func render(ev: CombatEvent, lookup: Callable, instant: bool = false) -> void:
	match ev.type:
		CombatEvent.Type.DAMAGE:
			var o = lookup.call(ev.target_id)
			if o != null and ev.target_max_hp > 0:
				o.set_hp(ev.target_hp_after)
			if ev.dodged:
				_pop(lookup, ev.target_id, "Miss", Color(0.8, 0.8, 0.8), instant)
			elif ev.crit:
				_pop(lookup, ev.target_id, "-%d!" % ev.value, Color(1.0, 0.85, 0.2), instant)
			elif ev.value > 0:
				_pop(lookup, ev.target_id, "-%d" % ev.value, Color(0.95, 0.3, 0.3), instant)
		CombatEvent.Type.HEAL:
			var uid: String = ev.target_id if ev.target_id != "" else ev.actor_id
			var o = lookup.call(uid)
			if o != null and ev.target_max_hp > 0:
				o.set_hp(ev.target_hp_after)
			_pop(lookup, uid, "+%d" % ev.value, Color(0.4, 0.95, 0.5), instant)
		CombatEvent.Type.QI_COST:
			_render_mp(lookup, ev.actor_id, ev.actor_mp_after, "-气", Color(0.4, 0.6, 0.95), instant)
		CombatEvent.Type.QI_GAIN:
			_render_mp(lookup, ev.target_id if ev.target_id != "" else ev.actor_id, ev.target_mp_after, "+气", Color(0.4, 0.8, 0.6), instant)
		CombatEvent.Type.STATUS_APPLIED:
			_pop(lookup, ev.target_id, "状态", Color(0.6, 0.9, 0.6), instant)
		CombatEvent.Type.STATUS_TICK:
			var o = lookup.call(ev.target_id)
			if o != null and ev.target_max_hp > 0:
				o.set_hp(ev.target_hp_after)
			_pop(lookup, ev.target_id, "%d" % ev.value, Color(0.95, 0.5, 0.2), instant)
		CombatEvent.Type.STATUS_EXPIRED:
			_pop(lookup, ev.target_id, "解除", Color(0.7, 0.7, 0.7), instant)
		CombatEvent.Type.SHIELD_ABSORB:
			var o = lookup.call(ev.target_id)
			if o != null and o.has_method("set_shield"):
				o.set_shield(ev.target_shield_after)
			_pop(lookup, ev.target_id, "盾%d" % ev.value, Color(0.4, 0.95, 0.95), instant)
		CombatEvent.Type.REFLECT:
			var o = lookup.call(ev.target_id)
			if o != null and ev.target_max_hp > 0:
				o.set_hp(ev.target_hp_after)
			_pop(lookup, ev.target_id, "反弹%d" % ev.value, Color(0.85, 0.4, 0.95), instant)
		CombatEvent.Type.REVIVE:
			var o = lookup.call(ev.target_id)
			if o != null and ev.target_max_hp > 0:
				o.set_hp(ev.target_hp_after)
			if o != null and o.has_method("play_revive"):
				o.play_revive()
			_pop(lookup, ev.target_id, "复活!", Color(1.0, 0.85, 0.2), instant)
		_:
			pass

static func _render_mp(lookup: Callable, uid: String, mp: int, tag: String, color: Color, instant: bool = false) -> void:
	var o = lookup.call(uid)
	if o != null:
		o.set_mp(mp)
	_pop(lookup, uid, tag, color, instant)

static func _pop(lookup: Callable, uid: String, txt: String, color: Color, instant: bool = false) -> void:
	if instant:
		return
	var o = lookup.call(uid)
	if o != null and o.has_method("pop_text"):
		o.pop_text(txt, color)

## 基准演出时长（秒），与旧战斗 CombatDirector 的 _FALLBACK 对齐
static func duration(ev: CombatEvent) -> float:
	match ev.type:
		CombatEvent.Type.DAMAGE:
			return _FALLBACK["damage_pop"] if not ev.dodged else _FALLBACK["hit_shake"]
		CombatEvent.Type.HEAL:
			return _FALLBACK["gentle"]
		CombatEvent.Type.QI_COST, CombatEvent.Type.QI_GAIN:
			return _FALLBACK["fast"]
		CombatEvent.Type.STATUS_APPLIED, CombatEvent.Type.STATUS_TICK, CombatEvent.Type.STATUS_EXPIRED:
			return _FALLBACK["status"]
		CombatEvent.Type.SHIELD_ABSORB:
			return _FALLBACK["shield_absorb"]
		CombatEvent.Type.REFLECT:
			return _FALLBACK["reflect"]
		CombatEvent.Type.REVIVE:
			return _FALLBACK["revive"]
		_:
			return _FALLBACK["fast"]
