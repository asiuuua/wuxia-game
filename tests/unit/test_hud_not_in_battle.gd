# tests/unit/test_hud_not_in_battle.gd
# 设计拍版回归（2026-09-02）：HUD 为城镇常驻 UI，战斗中绝不出现——
# 战斗使用独立的战斗 UI（BattleScene / TacticalBattleScene 自带），与 HUD 互斥。
# 任何开战入口（GameManager.start_battle）都必须先卸载 HUD，确保战斗中无 HUD 残留。
extends TestBase

## 开战即卸载 HUD：模拟"已在城镇挂载 HUD"后调用 start_battle，
## 断言 HUD 被立即卸载（_hud == null），战斗中不会出现 HUD 面板。
## 注：start_battle 内的 _deferred_change_scene 是 await process_frame 的延迟切场景，
## 单元测试同步跑完即 get_tree().quit()，该延迟切场景不会真正执行，故本测试安全、无副作用。
func test_start_battle_unmounts_hud() -> void:
	var ctrl := Control.new()
	UIManager.mount_hud(ctrl)
	expect(UIManager._hud == ctrl, "前置：城镇已挂载常驻 HUD")

	# 真实战斗配置（battles.json 存在），验证开战策略确实卸载 HUD
	GameManager.start_battle("battle_bandit_001")
	expect(UIManager._hud == null, "开战后 HUD 必须被卸载（战斗中不可出现 HUD 面板）")

	# 清理（重复 unmount 安全）
	UIManager.unmount_hud()

## 重复开战不产生残留双 HUD：第二次开战时 HUD 已是 null，仍应保持 null（无视觉重叠）。
func test_repeated_start_battle_keeps_hud_unmounted() -> void:
	var a := Control.new()
	UIManager.mount_hud(a)
	GameManager.start_battle("battle_bandit_001")
	expect(UIManager._hud == null, "首次开战应卸载 HUD")

	var b := Control.new()
	UIManager.mount_hud(b)
	GameManager.start_battle("battle_bandit_001")
	expect(UIManager._hud == null, "再次开战（二次挂载后）仍必须卸载 HUD，杜绝残留")

	UIManager.unmount_hud()
