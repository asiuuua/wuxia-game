# tests/unit/test_battle_scene_icons.gd
# 战斗场景图标接线冒烟测试（UI 窗口代为接线，派单 f11a954808c2 的 verify 项）
# 验证：① UnitHud.set_portrait 真取到图标（缺图显占位图、不崩）
#       ② BattleScene._build_action_buttons 的技能按钮图标行真实跑通（返回非 null）
# 属战斗窗口主权代码，但测试只读取断言，不改战斗源码；extends TestBase 自动被 run_all 发现。
#
# 注：TestBase extends RefCounted（非 Node），被测 UnitHud/BattleScene 不会自动跑 _ready；
# 故 set_portrait 设计为惰性自建头像槽，本测试无需场景树即可验证。

extends TestBase

const SAMPLE_ABILITY: String = "sword_qingsong_001"   # 真实武学 id（data/configs/abilities/skills.json）

## UnitHud.set_portrait 应通过 UIManager.get_icon 取到图标（占位或真实）
func test_unit_hud_enemy_portrait_wires_icon() -> void:
	var h := UnitHud.new()
	h.set_portrait("enemies/bandit_001")
	expect(h._portrait != null, "UnitHud 应已建头像槽（惰性自建）")
	expect(h._portrait.texture != null, "敌人头像应取到图标（占位或真实），不应为 null")

## 玩家头像用固定 npc/player
func test_unit_hud_player_portrait_wires_icon() -> void:
	var h := UnitHud.new()
	h.set_portrait("npc/player")
	expect(h._portrait.texture != null, "玩家头像(npc/player)应取到图标，不应为 null")

## 复刻 BattleScene._build_action_buttons 的技能图标行：b.icon = UIManager.get_icon("skills/"+id)
func test_skill_icon_api_returns_texture() -> void:
	var b := Button.new()
	b.icon = UIManager.get_icon("skills/" + SAMPLE_ABILITY)
	expect(b.icon != null, "技能按钮图标应取到（占位或真实），不应为 null")

## 真实跑通 BattleScene._build_action_buttons：装备一个武学后，至少有一个技能按钮带图标
func test_battle_scene_action_buttons_have_icons() -> void:
	GameManager.ability_service.learn(SAMPLE_ABILITY)
	GameManager.ability_service.equip_combat_skill(0, SAMPLE_ABILITY)
	var scene := BattleScene.new()
	scene._build_ui()
	scene._build_action_buttons()
	var found: bool = false
	for c in scene._actions_container.get_children():
		if c is Button and c.icon != null:
			found = true
			break
	expect(found, "BattleScene 行动按钮中至少一个技能按钮应带图标（占位或真实）")
	scene.free()
