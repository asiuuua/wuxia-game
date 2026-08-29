# scenes/ui/overlays/hud/Hud.gd
# 抬头显示根容器（v2 HUD 四面板拆分）：仅负责实例化并挂载四个面板，
# 自身不持有任何 EventBus 订阅与业务刷新逻辑——各面板自管订阅 + _exit_tree 断信号。
# 配色 / 布局全部下沉到各面板脚本，禁止在此散落 UI 构造。

extends Control
class_name Hud

const StatusCardPanel = preload("res://scenes/ui/overlays/hud/status_card_panel.gd")
const TopRightMenuPanel = preload("res://scenes/ui/overlays/hud/top_right_menu_panel.gd")
const QuestTrackPanel = preload("res://scenes/ui/overlays/hud/quest_track_panel.gd")
const SkillBarPanel = preload("res://scenes/ui/overlays/hud/skill_bar_panel.gd")

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	# 四面板：状态卡 / 右上菜单 / 任务追踪 / 快捷技能栏
	add_child(StatusCardPanel.new())
	add_child(TopRightMenuPanel.new())
	add_child(QuestTrackPanel.new())
	add_child(SkillBarPanel.new())
