# scenes/ui/screens/bond_romance/BondRomanceScreen.gd
# 姻缘面板（关系总览 + 求婚/结义/拜师/收徒/欢庆/婚礼 入口）
# 铁律：UI 只展示与输入，数据来自 GameManager 各业务服务公开方法；
#       数据源与关系中枢 relationship_service 对齐——结义走 sworn_service、师徒走 master_service，
#       好感走 bond_service、姻缘走 romance_service，避免与关系图对不上。
#       刷新监听 EventBus.bond_relationship_changed（0 参，必须 0 参处理器避免运行期崩溃）。

extends PopupBase
class_name BondRomanceScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")

var _content: VBoxContainer = null
var _scroll: ScrollContainer = null

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	UIManager.apply_safe_area(self)
	popup_id = "BondRomance"
	_build()
	_refresh()
	if not EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.connect(_on_relationship_changed)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := make_glass_panel(Vector2(760, 620))
	add_child(panel)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var v := VBoxContainer.new()
	margin.add_child(v)
	var title := Label.new()
	title.text = "姻缘 · 情缘录"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	v.add_child(title)
	_scroll = ScrollContainer.new()
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_child(_scroll)
	_content = VBoxContainer.new()
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_content)
	var close := Button.new()
	close.text = "关闭"
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(request_close)
	UIFeedback.attach(close)
	v.add_child(close)

func _refresh() -> void:
	if _content == null:
		return
	for c in _content.get_children():
		c.queue_free()
	_add_spouse_section()
	_add_child_section()
	_add_sworn_section()
	_add_master_section()
	_add_candidate_section()

func _section(title: String) -> void:
	var h := Label.new()
	h.text = title
	h.add_theme_font_size_override("font_size", 18)
	h.add_theme_color_override("font_color", UIPalette.GOLD)
	_content.add_child(h)

func _add_note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UIPalette.DISABLED)
	_content.add_child(l)

func _npc_name(npc_id: String) -> String:
	var npc: Dictionary = ConfigManager.get_relation(npc_id)
	if npc.is_empty():
		return npc_id
	return String(npc.get("name", npc_id))

func _btn(text: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	if enabled:
		b.pressed.connect(cb)
	UIFeedback.attach(b)
	return b

func _row(npc_id: String, tag: String, aff: int, buttons: Array) -> void:
	var row := HBoxContainer.new()
	# NPC 头像：美术按关系 id 丢 resources/icons/npc/<npc_id>.png 即可替换
	var icon := TextureRect.new()
	icon.texture = UIManager.get_icon("npc/" + npc_id)
	icon.custom_minimum_size = Vector2(36, 36)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	row.add_child(icon)
	var name_l := Label.new()
	name_l.custom_minimum_size = Vector2(150, 0)
	name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_l.text = "%s  [%s]" % [_npc_name(npc_id), tag]
	row.add_child(name_l)
	var aff_l := Label.new()
	aff_l.custom_minimum_size = Vector2(90, 0)
	aff_l.text = "好感%d" % aff
	row.add_child(aff_l)
	for b in buttons:
		row.add_child(b)
	_content.add_child(row)

# === 各区块 ===
func _add_spouse_section() -> void:
	_section("一、配偶")
	var rs = GameManager.romance_service
	if rs == null:
		return
	var spouses: Array = rs.get_spouses()
	if spouses.is_empty():
		_add_note("（暂无配偶，可在「五、可发展」中求婚）")
		return
	for npc_id in spouses:
		var stage_name: String = rs.get_romance_stage_name(npc_id)
		var kids: Array = rs.get_children_of(npc_id)
		var preg: bool = rs.is_pregnant(npc_id)
		var tag: String = "配偶·%s·子嗣%d%s" % [stage_name, kids.size(), "·孕" if preg else ""]
		var btns := [
			_btn("欢庆(%d)" % rs.get_celebration_left(npc_id), true, _on_celebration.bind(npc_id)),
			_btn("举办婚礼", true, _on_wedding.bind(npc_id)),
		]
		_row(npc_id, tag, GameManager.bond_service.get_affection(npc_id), btns)

func _add_child_section() -> void:
	_section("二、子嗣")
	# 子嗣记录走关系网数据中枢（UI 视图统一入口），避免直读 romance_service 私有 children 字典；
	# get_relationship_graph()["children"] 每条为 {child_id,name,mother_id,...} 记录。
	var rel = GameManager.relationship_service
	if rel == null:
		return
	var graph: Dictionary = rel.get_relationship_graph()
	var kids: Array = graph.get("children", [])
	if kids.is_empty():
		_add_note("（尚无子嗣）")
		return
	for c in kids:
		var row := HBoxContainer.new()
		var l := Label.new()
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.text = "%s（母：%s）" % [String(c.get("name", "")), _npc_name(String(c.get("mother_id", "")))]
		row.add_child(l)
		_content.add_child(row)

func _add_sworn_section() -> void:
	_section("三、结义")
	var sw = GameManager.sworn_service
	if sw == null:
		return
	var brothers: Array = sw.get_sworn_brothers()
	for npc_id in brothers:
		_row(npc_id, "结义", GameManager.bond_service.get_affection(npc_id), [])
	if brothers.is_empty():
		_add_note("（暂未结义）")
	# 可结义候选（数据中枢同款来源：sworn_service）
	for npc_id in ConfigManager.get_all_relation_ids():
		var npc: Dictionary = ConfigManager.get_relation(npc_id)
		if npc.is_empty() or not bool(npc.get("is_swornable", false)):
			continue
		if sw.is_sworn(npc_id):
			continue
		_row(npc_id, "可结义", GameManager.bond_service.get_affection(npc_id),
			[_btn("结义", sw.can_sworn(npc_id), _on_swear.bind(npc_id))])

func _add_master_section() -> void:
	_section("四、师徒")
	var ms = GameManager.master_service
	if ms == null:
		return
	for npc_id in ms.get_masters():
		_row(npc_id, "师父·%d阶" % ms.get_grade_level(npc_id), GameManager.bond_service.get_affection(npc_id), [])
	for npc_id in ms.get_apprentices():
		_row(npc_id, "徒弟·%d阶" % ms.get_grade_level(npc_id), GameManager.bond_service.get_affection(npc_id), [])
	if ms.get_masters().is_empty() and ms.get_apprentices().is_empty():
		_add_note("（尚无师徒关系）")

func _add_candidate_section() -> void:
	_section("五、可发展")
	var bs = GameManager.bond_service
	var rs = GameManager.romance_service
	var sw = GameManager.sworn_service
	var ms = GameManager.master_service
	if bs == null or rs == null or sw == null or ms == null:
		return
	var any := false
	for npc_id in ConfigManager.get_all_relation_ids():
		var npc: Dictionary = ConfigManager.get_relation(npc_id)
		if npc.is_empty():
			continue
		var btns := []
		if bool(npc.get("is_romanceable", false)) and not rs.is_spouse(npc_id):
			btns.append(_btn("求婚", rs.can_propose(npc_id), _on_propose.bind(npc_id)))
			# 欢庆：好感满即可用（用户需求：所有可结缘 NPC 好感满后都能欢庆）
			if rs.can_celebrate(npc_id):
				btns.append(_btn("欢庆(%d)" % rs.get_celebration_left(npc_id), true, _on_celebration.bind(npc_id)))
		if bool(npc.get("is_swornable", false)) and not sw.is_sworn(npc_id):
			btns.append(_btn("结义", sw.can_sworn(npc_id), _on_swear.bind(npc_id)))
		if bool(npc.get("is_masterable", false)) and not ms.is_master(npc_id):
			btns.append(_btn("拜师", ms.can_apprentice(npc_id), _on_become_master.bind(npc_id)))
		if not ms.is_apprentice(npc_id):
			btns.append(_btn("收徒", ms.can_take_apprentice(npc_id), _on_take_apprentice.bind(npc_id)))
		if btns.is_empty():
			continue
		any = true
		_row(npc_id, "候选", bs.get_affection(npc_id), btns)
	if not any:
		_add_note("（暂无可发展对象）")

# === 操作回调 ===
func _act(result: Dictionary, ok_msg: String) -> void:
	if result.get("ok", false):
		EventBus.notification_show.emit(ok_msg)
	else:
		EventBus.notification_show.emit("未能完成：%s" % String(result.get("reason", "未知")))
	_refresh()

func _on_propose(npc_id: String) -> void:
	_act(GameManager.romance_service.propose(npc_id), "结为连理！")

func _on_celebration(npc_id: String) -> void:
	var rs = GameManager.romance_service
	if rs == null:
		return
	var r: Dictionary = rs.begin_celebration(npc_id)
	if not r.get("ok", false):
		var reason: String = String(r.get("reason", "UNKNOWN"))
		if reason == "QUOTA_EXCEEDED":
			# 超当日配额：弹出预留接口的对话框（内容读 celebrations.json 的 over_limit）
			UIManager.open_screen("CelebrationOverlay", UIManager.Layer.FULLSCREEN, {"mode": "over_limit"})
		else:
			EventBus.notification_show.emit("未能欢庆：%s" % reason)
		return
	# 配额内：打开欢庆 CG 播放界面（内容读 celebrations.json 的 default）
	UIManager.open_screen("CelebrationOverlay", UIManager.Layer.FULLSCREEN,
		{"mode": "cg", "npc_id": npc_id, "cg_id": String(r.get("cg_id", "default"))})
	if bool(r.get("conceived", false)):
		EventBus.notification_show.emit("喜讯：与 %s 珠胎暗结……" % _npc_name(npc_id))

func _on_wedding(npc_id: String) -> void:
	var r: Dictionary = GameManager.bond_service.hold_wedding(npc_id)
	if r.get("ok", false):
		# 婚礼演出由 GameManager 监听 bond_wedding_started 切到 WeddingScene；
		# 先关闭本面板，避免覆盖层残留在婚礼场景之上。
		request_close()
	else:
		EventBus.notification_show.emit("未能举办：%s" % String(r.get("reason", "未知")))
		_refresh()

func _on_swear(npc_id: String) -> void:
	_act(GameManager.sworn_service.sworn(npc_id), "义结金兰！")

func _on_become_master(npc_id: String) -> void:
	_act(GameManager.master_service.become_apprentice(npc_id), "拜师成功，习得真传！")

func _on_take_apprentice(npc_id: String) -> void:
	_act(GameManager.master_service.take_apprentice(npc_id), "收徒成功！")

func _on_relationship_changed() -> void:
	_refresh()

func _exit_tree() -> void:
	if EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.disconnect(_on_relationship_changed)
