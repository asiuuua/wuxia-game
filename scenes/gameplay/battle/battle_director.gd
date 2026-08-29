# scenes/gameplay/battle/battle_director.gd
# 战斗演出编排层（M2）：从 combat_service 取事件流 → 逐个分派给 BattleView → await 完成 → 下一个
# 设计原则（对标架构文档 §5）：
#   - 不持有任何战斗逻辑：只负责"播放节奏"，伤害怎么算它不知道
#   - 时长一律引用 ui_anim.json 的令牌（带兜底，避免 UI 窗口尚未补 battle 块时崩）
#   - 每个事件等待用「定时器」作权威节奏，View 的 anim_completed 仅作完整性信号——
#     这样即使 View 漏发信号也不会卡死（新手最容易踩的坑）
#   - 加速 = 所有时长 ÷ speed_scale；跳过 = speed_scale 拉满 + View.set_instant(true)
# 属战斗窗口主权（scenes/gameplay/battle/），UI 窗口不碰。

extends Node
class_name CombatDirector

signal all_finished

var _view: BattleView = null
var _speed_scale: float = 1.0
var _instant: bool = false

# 兜底时长（秒）：ui_anim.json 缺失 battle 块时使用。
# 含 M3-3 补齐的战斗全量令牌意图值，确保 UI 窗口补 battle 块前手感也正确。
const _FALLBACK := {
	"instant": 0.0,
	"fast": 0.08,
	"normal": 0.12,
	"gentle": 0.18,
	"slow": 0.25,
	"damage_pop": 0.12,
	"hit_shake": 0.12,
	"turn_gap": 0.1,
	"death_fade": 0.4,
	"shield_absorb": 0.12,
	"reflect": 0.14,
	"revive": 0.35,
}
var _anim: Dictionary = {}

func _ready() -> void:
	_load_anim()

## 绑定视图（BattleScene 装配时调用）
func bind_view(v: BattleView) -> void:
	_view = v

## 加速倍率：1× / 2× / 4×
func set_speed_scale(s: float) -> void:
	_speed_scale = max(0.0001, s)

## 跳过模式：拉满速度 + 通知 View 直接跳终态
func set_instant(enabled: bool) -> void:
	_instant = enabled
	if _view != null:
		_view.set_instant(enabled)
	if enabled:
		_speed_scale = 999.0

## 顺序播放整段事件流；全部播完 emit all_finished
func play_events(events: Array[CombatEvent]) -> void:
	for ev in events:
		await _play_one(ev)
	all_finished.emit()

func _play_one(ev: CombatEvent) -> void:
	if _view != null:
		_view.play_event(ev)
	var dur: float = _duration(ev)
	if _instant:
		dur = 0.0
	else:
		dur = dur / _speed_scale
	await _wait(dur)

func _wait(dur: float) -> void:
	if dur <= 0.0:
		return
	await get_tree().create_timer(dur).timeout

# ───────────────────────── 时长令牌 ─────────────────────────

## 按事件类型映射到 ui_anim 令牌名
func _token_for(ev: CombatEvent) -> String:
	match ev.type:
		CombatEvent.Type.DAMAGE:
			return "damage_pop" if not ev.dodged else "hit_shake"
		CombatEvent.Type.HEAL:
			return "gentle"
		CombatEvent.Type.QI_COST, CombatEvent.Type.QI_GAIN:
			return "fast"
		CombatEvent.Type.STATUS_APPLIED, CombatEvent.Type.STATUS_TICK, CombatEvent.Type.STATUS_EXPIRED:
			return "fast"
		CombatEvent.Type.ACTION_BASIC, CombatEvent.Type.ACTION_SKILL, CombatEvent.Type.TURN_START:
			return "turn_gap"
		CombatEvent.Type.COOLDOWN_SET:
			return "instant"
		CombatEvent.Type.SHIELD_ABSORB:
			return "shield_absorb"
		CombatEvent.Type.REFLECT:
			return "reflect"
		CombatEvent.Type.REVIVE:
			return "revive"
		CombatEvent.Type.OUTCOME:
			return "death_fade"
		_:
			return "fast"

## 解析令牌 → 秒；优先 ui_anim.battle.<token>，其次 ui_anim.durations.<token>，最后兜底
func _duration(ev: CombatEvent) -> float:
	var token: String = _token_for(ev)
	if _anim.is_empty():
		_load_anim()
	if not _anim.is_empty():
		var battle: Dictionary = _anim.get("battle", {})
		if battle.has(token):
			return float(battle[token])
		var d: Dictionary = _anim.get("durations", {})
		if d.has(token):
			return float(d[token])
	return _FALLBACK.get(token, 0.12)

func _load_anim() -> void:
	# 工业化扩容 P7：经 ConfigManager 集中取用 UI 动效整表，杜绝硬编码数据路径
	_anim = ConfigManager.get_ui_anim_table()
