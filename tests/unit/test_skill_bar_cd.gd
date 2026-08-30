# tests/unit/test_skill_bar_cd.gd
# 端到端验证 HUD 技能栏「读秒」UI 表现（服务层+信号已由 test_hud_cooldown 覆盖，本测试验 UI 层）。
# 直接调 _ready() 构建+订阅（与项目现有 UI 测试惯例一致），驱动冷却后断言槽内 _cd Label 显隐与文本。

extends TestBase

const SAMPLE := "sword_qingsong_001"
# B 路线（2026-08-30）：技能栏结构与槽位在 SkillBarPanel.tscn，测试必须实例化场景
const SkillBarPanelScene = preload("res://scenes/ui/overlays/hud/SkillBarPanel.tscn")

var _panel: SkillBarPanel

func _make_panel() -> SkillBarPanel:
	var asvc = GameManager.ability_service
	asvc.learn(SAMPLE)
	asvc.equip_combat_skill(0, SAMPLE)
	asvc.cd_remaining.clear()
	var p: SkillBarPanel = SkillBarPanelScene.instantiate()
	p._ready()            # 触发 _collect_slots + 订阅 EventBus + _refresh_full
	return p

func _teardown() -> void:
	if is_instance_valid(_panel):
		_panel._exit_tree()   # 手动断开，避免悬挂连接
		_panel.free()
		_panel = null

# 1) 进入冷却：读秒 Label 可见且显示 3.0
func test_cd_label_shows_on_cooldown() -> void:
	_panel = _make_panel()
	GameManager.ability_service.set_cooldown(0, 3.0)
	var slot0 = _panel._slots[0]
	expect(slot0.get_ability_id() == SAMPLE, "槽0 应显示已装备技能")
	expect(slot0._cd.visible == true, "冷却中读秒 Label 应可见")
	expect(slot0._cd.text == "3.0", "读秒应显示 3.0（实际 %s）" % slot0._cd.text)
	_teardown()

# 2) 每帧递减：文本更新；归零：Label 隐藏
func test_cd_label_ticks_and_clears() -> void:
	_panel = _make_panel()
	GameManager.ability_service.set_cooldown(0, 3.0)
	GameManager.ability_service.tick_cooldowns(1.0)
	expect(_panel._slots[0]._cd.text == "2.0", "tick 后读秒应 2.0（实际 %s）" % _panel._slots[0]._cd.text)
	GameManager.ability_service.tick_cooldowns(2.0)
	expect(_panel._slots[0]._cd.visible == false, "归零后读秒 Label 应隐藏")
	_teardown()

# 3) 重新装备同一槽位：清除冷却 → 读秒隐藏（验证 notify_skill_bar_changed 联动）
func test_equip_clears_cd_label() -> void:
	_panel = _make_panel()
	GameManager.ability_service.set_cooldown(0, 5.0)
	expect(_panel._slots[0]._cd.visible == true, "冷却中读秒应可见")
	GameManager.ability_service.equip_combat_skill(0, SAMPLE)
	expect(_panel._slots[0]._cd.visible == false, "重新装备后读秒应隐藏")
	_teardown()
