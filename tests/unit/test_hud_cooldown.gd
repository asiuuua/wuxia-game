# tests/unit/test_hud_cooldown.gd
# 验证武学快捷栏真实冷却（ability_service.cd_remaining + 信号闭环）。
# 覆盖：set_cooldown 存值+emit / tick_cooldowns 递减+归零清除 / equip·unequip 清槽 cd+notify_skill_bar_changed。

extends TestBase

const SAMPLE := "sword_qingsong_001"

var _got_sid := ""
var _got_remain := -1.0
var _bar_changed := 0

func _on_cd(sid: String, remain: float) -> void:
	_got_sid = sid
	_got_remain = remain

func _on_bar(_p: Variant = null) -> void:
	_bar_changed += 1

func test_set_cooldown_stores_and_emits() -> void:
	var asvc = GameManager.ability_service
	asvc.learn(SAMPLE)
	asvc.equip_combat_skill(0, SAMPLE)
	asvc.cd_remaining.clear()
	_got_sid = ""; _got_remain = -1.0
	EventBus.notify_skill_cd_update.connect(_on_cd)
	asvc.set_cooldown(0, 3.0)
	expect(abs(asvc.cd_remaining.get(0, -1.0) - 3.0) < 0.001, "cd_remaining[0] 应=3.0")
	expect(_got_sid == SAMPLE, "应推送 skill_id=%s" % SAMPLE)
	expect(abs(_got_remain - 3.0) < 0.001, "应推送 remain=3.0")
	EventBus.notify_skill_cd_update.disconnect(_on_cd)
	asvc.reset()

func test_tick_decrements_and_clears() -> void:
	var asvc = GameManager.ability_service
	asvc.learn(SAMPLE)
	asvc.equip_combat_skill(0, SAMPLE)
	asvc.cd_remaining.clear()
	asvc.set_cooldown(0, 1.0)
	asvc.tick_cooldowns(0.4)
	expect(abs(asvc.cd_remaining.get(0, -1.0) - 0.6) < 0.001, "tick 后应剩 0.6")
	asvc.tick_cooldowns(0.6)
	expect(not asvc.cd_remaining.has(0), "归零后该槽 cd 应被清除")
	asvc.reset()

func test_equip_unequip_clear_cd_and_notify() -> void:
	var asvc = GameManager.ability_service
	asvc.learn(SAMPLE)
	asvc.equip_combat_skill(0, SAMPLE)
	asvc.cd_remaining.clear()
	asvc.set_cooldown(0, 3.0)
	_bar_changed = 0
	EventBus.notify_skill_bar_changed.connect(_on_bar)
	# 重新装备同一槽位 → 清该槽 cd 并 emit notify_skill_bar_changed
	asvc.equip_combat_skill(0, SAMPLE)
	expect(not asvc.cd_remaining.has(0), "装备变化应清除该槽 cd")
	expect(_bar_changed >= 1, "应 emit notify_skill_bar_changed")
	# 卸下 → 同样清 cd + emit
	asvc.set_cooldown(0, 2.0)
	_bar_changed = 0
	asvc.unequip_combat_skill(0)
	expect(not asvc.cd_remaining.has(0), "卸下应清除该槽 cd")
	expect(_bar_changed >= 1, "卸下应 emit notify_skill_bar_changed")
	EventBus.notify_skill_bar_changed.disconnect(_on_bar)
	asvc.reset()
