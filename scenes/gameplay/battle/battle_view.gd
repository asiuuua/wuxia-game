# scenes/gameplay/battle/battle_view.gd
# 战斗视图层（M2）：接收 CombatEvent，按 type 分派到对应单位的 HUD（飘字/血条/真气条）
# 设计原则（架构文档 §5.1 / §6.2）：
#   - 只播动画，不判断战斗逻辑、不读 CombatState（血条直设 target_hp_after，加速/跳过不错位）
#   - 实现三个约定接口：signal anim_completed / play_event(ev) / set_instant(bool)
# 属战斗窗口主权（scenes/gameplay/battle/），UI 窗口不碰。

extends Control
class_name BattleView

# P0-2：显式 preload 渲染器（不依赖编辑器全局类缓存，headless 验证可确定性解析）
const CombatEventRenderer = preload("res://core/combat_event_renderer.gd")

signal anim_completed

var _instant: bool = false
var panels: Dictionary = {}   # character_id -> UnitHud
# P0-2：统一渲染查找闭包（character_id -> UnitHud），供 CombatEventRenderer 委托
var _lookup: Callable = func(id): return panels.get(id)

## 注册某单位的 HUD（BattleScene 装配时调用）
func register_unit(id: String, hud: UnitHud) -> void:
	panels[id] = hud

func set_instant(enabled: bool) -> void:
	_instant = enabled
	for hud in panels.values():
		hud.set_instant(enabled)

## 按事件类型分派演出（P0-2：统一委托 CombatEventRenderer，新增事件类型只改渲染器一处）
func play_event(ev: CombatEvent) -> void:
	CombatEventRenderer.render(ev, _lookup)
	anim_completed.emit()

# P0-2：以下 _play_damage / _play_heal / _play_mp / _play_shield / _play_reflect /
# _play_revive / _pop 私有渲染逻辑已迁移至 CombatEventRenderer（统一共享），
# BattleView 现仅作薄委托层，与战术场景共用一套渲染，消除重复实现。
