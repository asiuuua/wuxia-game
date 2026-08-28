# data/runtime/status_effect.gd
# 状态效果（Buff/Debuff/DOT/HOT/Control）—— 对标逸剑的状态引擎
# 字段语义（逸剑实测）：
#   - stacks / max_stacks：层数（多数上限 9），叠加增广幅度
#   - remaining：剩余回合，每回合自动 -1（即「每回合消退 1 层」的时长维度）
#   - stat / mode / value：属性修正（攻击/防御/暴击/闪避/集气速率…），幅度 = value * stacks
#   - dot_per_turn：每回合气血变化（负=伤害，正=治疗），按层数生效
#   - clear_on_rest：调息时清除
# 复杂逻辑（聚合 / tick / 合并）由 CombatCore 统一处理，本类只承载数据 + 工具方法

extends RefCounted
class_name StatusEffect

const MODE_FLAT := 0     # 数值加成（加减固定值）
const MODE_PCT := 1      # 百分比加成（相对基础值）

var effect_id: String = ""
var name_key: String = ""
var type: int = CombatEnums.EffectType.BUFF
var stat: String = ""              # 修正的属性名（"attack"/"defense"/"crit"/"dodge"/"speed"…）
var mode: int = MODE_FLAT
var value: float = 0.0             # 单层幅度
var stacks: int = 1
var max_stacks: int = 9
var remaining: int = 2             # 剩余回合
var dot_per_turn: int = 0          # 每回合气血变化（已含层数外的单层值，Core 乘 stacks）
var clear_on_rest: bool = false

func is_expired() -> bool:
	return remaining <= 0

## 字符串 → 模式常量（配置表用 "flat" / "pct"）
static func mode_from_str(s: String) -> int:
	return MODE_PCT if s == "pct" else MODE_FLAT
