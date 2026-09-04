@tool
# scenes/ui/components/rank_select_dialog/RankSelectDialog.gd
# 后宅名分选择弹窗（NPC 详情页 / 姻缘面板共用）：
#   弹出大房~七房 / 小妾一~七 / 通房丫鬟 15 档选择，调用 romance_service.set_spouse_rank(npc_id, rank)。
# 铁律：UI 只读业务服务公开方法，不持有 Node；名分仅称谓/排序，无属性加成。
# B 路线：静态壳在 RankSelectDialog.tscn，脚本只填动态内容。

extends PopupBase
class_name RankSelectDialog

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

@onready var _title: Label = $Panel/Margin/VLayout/Title
@onready var _grid: GridContainer = $Panel/Margin/VLayout/BodyAnchor/Grid
@onready var _close: Button = $Panel/Margin/VLayout/Close

var _npc_id: String = ""
var _ready_done: bool = false
var _pending_open: Variant = null

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	focus_mode = Control.FOCUS_NONE
	UIManager.apply_safe_area(self)
	popup_id = "RankSelectDialog"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_close.text = "取消"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(request_close)
	UIFeedback.attach(_close)
	_ready_done = true
	if _pending_open != null:
		_open(_pending_open)
		_pending_open = null
	enable_responsive($Panel, Vector2(560, 520))

## UIManager.open_screen 在 add_child 之前就会调用 _on_open，此时 @onready 节点未就绪；
## 采用与 NpcPanelScreen 相同的模式：先暂存，等 _ready 后再真正刷新。
func _on_open(data: Variant) -> void:
	if _ready_done:
		_open(data)
	else:
		_pending_open = data

func _open(data: Variant) -> void:
	if data is Dictionary and data.has("npc_id"):
		_npc_id = String(data["npc_id"])
	_refresh()

func _refresh() -> void:
	if _grid == null:
		return
	for c in _grid.get_children():
		c.queue_free()
	var rs = GameManager.romance_service
	var npc: Dictionary = ConfigManager.get_relation(_npc_id)
	var name: String = String(npc.get("name", _npc_id))
	_title.text = "设置名分 · %s" % name
	var cur: int = BondEnums.SpouseRank.CHAMBERMAID
	if rs != null and rs.is_spouse(_npc_id):
		cur = rs.get_spouse_rank(_npc_id)
	for rank in range(BondEnums.SpouseRank.CHAMBERMAID + 1):
		_grid.add_child(_build_rank_button(rank, cur))

func _build_rank_button(rank: int, current: int) -> Button:
	var b := Button.new()
	b.text = BondEnums.spouse_rank_name(rank)
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(150, 42)
	if rank == current:
		b.text = "%s（当前）" % b.text
		b.add_theme_color_override("font_color", UIPalette.GOLD)
	b.pressed.connect(_on_pick.bind(rank))
	UIFeedback.attach(b)
	return b

func _on_pick(rank: int) -> void:
	var rs = GameManager.romance_service
	if rs == null:
		request_close()
		return
	if rs.set_spouse_rank(_npc_id, rank):
		EventBus.notification_show.emit("已将 %s 的名分设为「%s」" % [_npc_name(_npc_id), BondEnums.spouse_rank_name(rank)])
	else:
		EventBus.notification_show.emit("设置名分失败：该角色并非配偶")
	request_close()

func _npc_name(npc_id: String) -> String:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return npc_id
	return String(npc.get("name", npc_id))

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后渲染示例名分网格（规避 GameManager）
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_title = get_node_or_null("Panel/Margin/VLayout/Title")
	_grid = get_node_or_null("Panel/Margin/VLayout/BodyAnchor/Grid")
	_close = get_node_or_null("Panel/Margin/VLayout/Close")
	if _title == null or _grid == null or _close == null:
		return
	_title.text = "设置名分 · 示例NPC"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 22)
	_close.text = "取消"
	for rank in range(BondEnums.SpouseRank.CHAMBERMAID + 1):
		var b := Button.new()
		b.text = BondEnums.spouse_rank_name(rank)
		b.custom_minimum_size = Vector2(150, 42)
		_grid.add_child(b)
