# scenes/ui/overlays/hud/Hud.gd
# 抬头显示根容器（v2 HUD 四面板拆分）：仅负责实例化并挂载四个面板，
# 自身不持有任何 EventBus 订阅与业务刷新逻辑——各面板自管订阅 + _exit_tree 断信号。
# 配色 / 布局全部下沉到各面板脚本，禁止在此散落 UI 构造。

extends Control
class_name Hud

# B 路线（2026-08-30）：四面板已全部迁入 .tscn，这里统一按场景实例化。
const StatusCardPanelScene = preload("res://scenes/ui/overlays/hud/StatusCardPanel.tscn")
const QuestTrackPanelScene = preload("res://scenes/ui/overlays/hud/QuestTrackPanel.tscn")
const TopRightMenuPanelScene = preload("res://scenes/ui/overlays/hud/TopRightMenuPanel.tscn")
const SkillBarPanelScene = preload("res://scenes/ui/overlays/hud/SkillBarPanel.tscn")

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	# 四面板：状态卡 / 右上菜单 / 任务追踪 / 快捷技能栏
	add_child(StatusCardPanelScene.instantiate())
	add_child(TopRightMenuPanelScene.instantiate())
	add_child(QuestTrackPanelScene.instantiate())
	add_child(SkillBarPanelScene.instantiate())
