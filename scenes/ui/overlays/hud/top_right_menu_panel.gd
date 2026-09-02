@tool
# scenes/ui/overlays/hud/top_right_menu_panel.gd
# HUD 右上角功能入口（v2 四面板之一）：「姻缘」按钮（可求婚时红点）+「菜单」按钮（打开分类主菜单）。
# 纯展示/入口层，红点轮询 GameManager.romance_service.get_marriageable_npc_ids()；
# 订阅 bond_relationship_changed 刷新。配色走 UIPalette，交互走 UIFeedback。
#
# B 路线（2026-08-30）：两个按钮与红点的静态结构/锚点/文案已迁入 TopRightMenuPanel.tscn，
# 脚本只保留连线（pressed → open_screen）与交互反馈挂载，原 _build() 代码删净。

extends HudDraggablePanel
class_name TopRightMenuPanel

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

@onready var _bond_badge: Label = $HBox/BondBtn/RomanceBadge

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_hook_buttons()
	# 拖拽初始化：默认右上角；优先取 hud_layout.json（工作室可改），否则回退视口相对默认
	var vp := _screen_size()
	_init_drag("top_right_menu", UILayout.hud_default_pos("top_right_menu", Vector2(maxf(12.0, vp.x - 220.0), 12.0), vp))
	if is_instance_valid(EventBus):
		EventBus.bond_relationship_changed.connect(_refresh_badge)
	_refresh_badge()

# 连线 + 交互反馈（按钮本体在 .tscn，行为仍由脚本挂载）
func _hook_buttons() -> void:
	var bond_btn: Button = $HBox/BondBtn
	bond_btn.pressed.connect(UIManager.open_screen.bind("BondRomance"))
	UIFeedback.attach(bond_btn)
	var menu_btn: Button = $HBox/MenuBtn
	menu_btn.pressed.connect(UIManager.open_screen.bind("GameMenu"))
	UIFeedback.attach(menu_btn)

func _exit_tree() -> void:
	if not is_instance_valid(EventBus):
		return
	if EventBus.bond_relationship_changed.is_connected(_refresh_badge):
		EventBus.bond_relationship_changed.disconnect(_refresh_badge)

# 姻缘红点：存在可求婚 NPC 时点亮右上角姻缘按钮
func _refresh_badge(_p: Variant = null) -> void:
	if _bond_badge == null:
		return
	if not is_instance_valid(GameManager) or GameManager.romance_service == null:
		_bond_badge.visible = false
		return
	var ids: Array = GameManager.romance_service.get_marriageable_npc_ids()
	_bond_badge.visible = not ids.is_empty()

# === 编辑器预览（UIPreview 调用）：手动赋值 @onready 后连线按钮（红点依赖运行态，预览中隐藏） ===
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_bond_badge = get_node_or_null("BondBtn/RomanceBadge")
	_hook_buttons()
