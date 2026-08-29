@tool
extends EditorPlugin

# 欢庆内容管理插件入口。
# 在编辑器左上方坞里挂一个面板（CelebrationManagerDock），让非技术的作者也能：
#   - 从可结缘 NPC 下拉里选人（或一键绑定新 NPC id）
#   - 一键导入 CG 视频/图片、背景音乐、台词文本
#   - 直接编辑台词、媒体类型
#   - 保存即写回 res://data/configs/bond/celebrations.json（按 npc_id 分键，自动回退 default）
# 注意：本脚本与 dock 脚本均无 class_name，且为编辑器专用（extends EditorPlugin / 仅编辑器加载），
# 不会进入游戏运行时，也不影响双闸门（--quit / run_all）。

var _dock: Control = null

func _enter_tree() -> void:
	var dock_script: Script = load("res://addons/celebration_manager/celebration_manager_dock.gd")
	_dock = dock_script.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UL, _dock)

func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
