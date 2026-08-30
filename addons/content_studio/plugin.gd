@tool
extends EditorPlugin

# 内容工作室：把 NPC 数据表、剧情对话表、欢庆模块三个编辑器集合到一个左侧坞。
# 依赖：addons/celebration_manager（仅复用其 dock 脚本，不再单独启用，避免重复坞）。

var _dock: TabContainer = null
var _npc: Control = null
var _story: Control = null
var _celeb: Control = null

func _enter_tree() -> void:
	_dock = TabContainer.new()

	_npc = load("res://addons/content_studio/npc_panel.gd").new()
	_npc.name = "NPC数据表"
	_dock.add_child(_npc)

	_story = load("res://addons/content_studio/story_panel.gd").new()
	_story.name = "剧情对话表"
	_dock.add_child(_story)

	var celeb_script: Script = load("res://addons/celebration_manager/celebration_manager_dock.gd")
	if celeb_script != null:
		_celeb = celeb_script.new()
		_celeb.name = "欢庆模块"
		_dock.add_child(_celeb)
	else:
		var warn := Label.new()
		warn.name = "欢庆模块"
		warn.text = "未找到 celebration_manager 插件（请保留 addons/celebration_manager 目录）"
		_dock.add_child(warn)

	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_UL, _dock)

func _exit_tree() -> void:
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null
