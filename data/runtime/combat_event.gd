# data/runtime/combat_event.gd
# 结构化战斗事件：逻辑层算完后吐出的一串有序事件，供演出层逐个播放
# 设计原则（对标逸剑 / 大厂 CRPG）：
#   - 战斗内高频有序流走「函数返回值 Array[CombatEvent]」，不走 EventBus（避免污染订阅/失序）
#   - 只有 combat_started / combat_ended / combat_finished 这类跨模块通知才发 EventBus
#   - 每个事件自包含：谁发起、谁承受、数值、是否暴击/闪避、挂了什么状态——演出层无需回查逻辑

extends RefCounted
class_name CombatEvent

enum Type {
	TURN_START,      # 某单位开始行动（ATB 轮到它，顺序条高亮）
	ACTION_BASIC,    # 普攻
	ACTION_SKILL,    # 施展招式
	QI_COST,         # 真气消耗（招式付出）
	QI_GAIN,         # 真气回复（调息 / 心法）
	COOLDOWN_SET,    # 招式进入冷却
	DAMAGE,          # 造成伤害（含闪避/暴击标记）
	HEAL,            # 治疗
	STATUS_APPLIED,  # 施加状态
	STATUS_TICK,     # 状态每回合生效（DoT / HoT）
	STATUS_EXPIRED,  # 状态消失
	OUTCOME,         # 战斗结束（VICTORY / DEFEAT / FLEE）
}

var type: int = Type.DAMAGE
var actor_id: String = ""        # 发起者（如 "player" / "bandit_001"）
var target_id: String = ""       # 承受者
var value: int = 0               # 数值（伤害 / 治疗 / 真气 / DoT）
var crit: bool = false
var dodged: bool = false
var status_id: String = ""       # 状态 id（STATUS_* 事件用）
var stacks: int = 0              # 状态层数
var skill_id: String = ""        # 招式 id（ACTION_SKILL 用）

# ── M2 演出层直设值（只增不改共享契约）──
# 视图层据此"直接设"血条/真气，无需回查 CombatState，避免加速/跳过/断线错位。
var target_hp_after: int = 0     # 承受者行动后气血（DAMAGE/HEAL/STATUS_TICK）
var target_max_hp: int = 0       # 承受者气血上限
var actor_mp_after: int = 0      # 发起者行动后真气（QI_COST）
var target_mp_after: int = 0     # 承受者行动后真气（QI_GAIN / 调息回真气）

func _to_string() -> String:
	return "CombatEvent(%d %s→%s v=%d%s%s)" % [
		type, actor_id, target_id, value,
		" 暴击" if crit else "", " 闪避" if dodged else ""]
