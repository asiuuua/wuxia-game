@tool
# scenes/ui/screens/npc_gallery/NpcGalleryScreen.gd
# 人物图鉴（NPC 列表）：列出全部 NPC，每行头像 + 名字 + 关系标签 + 好感 + 「查看详情」。
# 数据来源：ConfigManager.get_all_npc_ids() + bond_service（好感）+ romance/sworn/master（关系标签）。
# 铁律：UI 只读业务服务公开方法，不持有 Node；刷新监听 EventBus.bond_relationship_changed。
# B 路线：静态壳在 NpcGalleryScreen.tscn，脚本只填动态内容。

extends PopupBase
class_name NpcGalleryScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

@onready var _title: Label = $Panel/Margin/VLayout/Title
@onready var _content: VBoxContainer = $Panel/Margin/VLayout/BodyAnchor/Content
@onready var _close: Button = $Panel/Margin/VLayout/Close

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	focus_mode = Control.FOCUS_NONE
	UIManager.apply_safe_area(self)
	popup_id = "NpcGalleryScreen"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_close.text = "关闭"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(request_close)
	UIFeedback.attach(_close)
	if not EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.connect(_on_relationship_changed)
	_refresh()
	enable_responsive($Panel, Vector2(760, 620))

func _refresh() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	var ids: Array = ConfigManager.get_all_npc_ids()
	if ids.is_empty():
		var l := Label.new()
		l.text = "（暂无 NPC 资料）"
		l.add_theme_color_override("font_color", UIPalette.DISABLED)
		_content.add_child(l)
		return
	for npc_id in ids:
		_content.add_child(_build_row(String(npc_id)))

func _build_row(npc_id: String) -> Control:
	var npc: Dictionary = ConfigManager.get_npc(npc_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	# NPC 头像：美术按关系 id 丢 resources/icons/npc/<npc_id>.png 即可替换，缺图回退阵营色块
	var icon := TextureRect.new()
	icon.texture = UIManager.get_icon("npc/" + npc_id)
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var name_l := Label.new()
	name_l.custom_minimum_size = Vector2(150, 0)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text = "%s  [%s]" % [String(npc.get("name", npc_id)), _relation_tag(npc_id)]
	row.add_child(name_l)
	var aff_l := Label.new()
	aff_l.custom_minimum_size = Vector2(90, 0)
	aff_l.text = "好感%d" % _affection(npc_id)
	row.add_child(aff_l)
	var detail := Button.new()
	detail.text = "查看详情"
	detail.focus_mode = Control.FOCUS_NONE
	detail.pressed.connect(_on_view_details.bind(npc_id))
	UIFeedback.attach(detail)
	row.add_child(detail)
	return row

func _affection(npc_id: String) -> int:
	if GameManager.bond_service == null:
		return 0
	return GameManager.bond_service.get_affection(npc_id)

func _relation_tag(npc_id: String) -> String:
	var rs = GameManager.romance_service
	if rs != null and rs.is_spouse(npc_id):
		return "配偶·%s" % rs.get_spouse_rank_name(npc_id)
	if GameManager.sworn_service != null and GameManager.sworn_service.is_sworn(npc_id):
		return "结义"
	if GameManager.master_service != null and GameManager.master_service.is_master(npc_id):
		return "师徒"
	if rs != null and rs.can_propose(npc_id):
		return "可结缘"
	return "相识"

func _on_view_details(npc_id: String) -> void:
	UIManager.open_screen("NpcPanel", UIManager.Layer.POPUP, {"npc_id": npc_id})

func _on_relationship_changed() -> void:
	_refresh()

func _exit_tree() -> void:
	if EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.disconnect(_on_relationship_changed)

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后渲染示例列表（规避 GameManager）
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_title = get_node_or_null("Panel/Margin/VLayout/Title")
	_content = get_node_or_null("Panel/Margin/VLayout/BodyAnchor/Content")
	_close = get_node_or_null("Panel/Margin/VLayout/Close")
	if _title == null or _content == null or _close == null:
		return
	_title.text = "人物图鉴"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 24)
	_close.text = "关闭"
	for c in _content.get_children():
		c.queue_free()
	for i in range(4):
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.custom_minimum_size = Vector2(36, 36)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(icon)
		var name_l := Label.new()
		name_l.custom_minimum_size = Vector2(150, 0)
		name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_l.text = "示例NPC %d  [相识]" % (i + 1)
		row.add_child(name_l)
		var aff_l := Label.new()
		aff_l.custom_minimum_size = Vector2(90, 0)
		aff_l.text = "好感%d" % (20 + i * 20)
		row.add_child(aff_l)
		var detail := Button.new()
		detail.text = "查看详情"
		row.add_child(detail)
		_content.add_child(row)
