@tool
# scenes/ui/screens/npc/NpcPanelScreen.gd
# NPC 面板（独立屏幕 · 预留接口）：展示某 NPC 的
#   半身立绘（配偶可左右滑动查看已解锁的特殊立绘并勾选）/ 数值 / 武学 / 攻击属性 /
#   送礼偏好 / 与主角好感 / 切磋入口 / 个人背包（占位查看）。
# 数据来源：ConfigManager.get_npc + npc_stats.json（预留数值）+ bond_service（好感）+
#   romance_service（婘眷值 / 立绘选择 / 同游·家庭出游）。
# 铁律：UI 只读业务服务公开方法，不持有 Node；刷新监听 EventBus.bond_relationship_changed。
# B 路线：静态壳在 NpcPanelScreen.tscn，脚本只填动态内容 + 立绘滑动逻辑。

extends PopupBase
class_name NpcPanelScreen

const UIPalette = preload("res://core/constants/ui_theme.gd")
const UIFeedback = preload("res://scenes/ui/components/ui_feedback/UIFeedback.gd")
const PortraitCache = preload("res://core/portrait_cache_manager.gd")

const NPC_STATS_PATH := "res://data/configs/npcs/npc_stats.json"

@onready var _portrait: TextureRect = $Panel/Margin/VLayout/Header/Portrait
@onready var _name_label: Label = $Panel/Margin/VLayout/Header/PortraitNav/NameLabel
@onready var _qq_info: Label = $Panel/Margin/VLayout/Header/PortraitNav/QQInfo
@onready var _portrait_label: Label = $Panel/Margin/VLayout/Header/PortraitNav/SwipeRow/PortraitLabel
@onready var _prev_btn: Button = $Panel/Margin/VLayout/Header/PortraitNav/SwipeRow/PrevBtn
@onready var _next_btn: Button = $Panel/Margin/VLayout/Header/PortraitNav/SwipeRow/NextBtn
@onready var _content: VBoxContainer = $Panel/Margin/VLayout/BodyAnchor/Content
@onready var _close: Button = $Panel/Margin/VLayout/Close

var _npc_id: String = ""
var _portrait_index: int = 0  # 当前滑动到的立绘索引
var _ready_done: bool = false
var _pending_open: Variant = null  # _on_open 在 _ready 之前被调用时暂存

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	focus_mode = Control.FOCUS_NONE
	UIManager.apply_safe_area(self)
	popup_id = "NpcPanel"
	_close.text = "关闭"
	_close.focus_mode = Control.FOCUS_NONE
	_close.pressed.connect(request_close)
	UIFeedback.attach(_close)
	_prev_btn.pressed.connect(_on_prev)
	_next_btn.pressed.connect(_on_next)
	if not EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.connect(_on_relationship_changed)
	_ready_done = true
	if _pending_open != null:
		_open(_pending_open)
		_pending_open = null

## UIManager.open_screen 在 add_child 之前就会调用 _on_open，此时 @onready 节点未就绪；
## 采用与 CelebrationOverlay / DialogOverlay 相同的模式：先暂存，等 _ready 后再真正刷新。
func _on_open(data: Variant) -> void:
	if _ready_done:
		_open(data)
	else:
		_pending_open = data

func _open(data: Variant) -> void:
	if data is Dictionary and data.has("npc_id"):
		_npc_id = String(data["npc_id"])
	_refresh()

func _on_prev() -> void:
	if _portrait_index > 0:
		_portrait_index -= 1
		_apply_current_portrait()

func _on_next() -> void:
	var list: Array = _portrait_list()
	if _portrait_index < list.size() - 1:
		_portrait_index += 1
		_apply_current_portrait()

func _portrait_list() -> Array:
	if GameManager.romance_service != null and _npc_id != "":
		return GameManager.romance_service.get_portrait_list(_npc_id)
	if _npc_id != "":
		var npc: Dictionary = ConfigManager.get_npc(_npc_id)
		if not npc.is_empty():
			var p: String = npc.get("half_body_portrait", npc.get("portrait", ""))
			if p != "":
				return [p]
	return []

func _apply_current_portrait() -> void:
	var list: Array = _portrait_list()
	if list.is_empty():
		_portrait.texture = null
		_portrait_label.text = "立绘 0/0"
		_prev_btn.disabled = true
		_next_btn.disabled = true
		return
	_portrait_index = clampi(_portrait_index, 0, list.size() - 1)
	var path: String = String(list[_portrait_index])
	var tex: Texture2D = PortraitCache.get_portrait(path)
	_portrait.texture = tex
	_portrait_label.text = "立绘 %d/%d%s" % [_portrait_index + 1, list.size(), "（已勾选）" if _is_selected() else ""]
	_prev_btn.disabled = (_portrait_index <= 0)
	_next_btn.disabled = (_portrait_index >= list.size() - 1)

func _is_selected() -> bool:
	if GameManager.romance_service == null:
		return false
	return GameManager.romance_service.get_selected_portrait_index(_npc_id) == _portrait_index

func _refresh() -> void:
	if _npc_id == "":
		return
	var npc: Dictionary = ConfigManager.get_npc(_npc_id)
	var name: String = String(npc.get("name", _npc_id))
	_name_label.text = name
	# 立绘：默认显示「已勾选」的那张
	if GameManager.romance_service != null and GameManager.romance_service.is_spouse(_npc_id):
		_portrait_index = GameManager.romance_service.get_selected_portrait_index(_npc_id)
	else:
		_portrait_index = 0
	_apply_current_portrait()
	_refresh_qq()
	_build_sections(npc)

func _refresh_qq() -> void:
	if GameManager.romance_service != null and GameManager.romance_service.is_spouse(_npc_id):
		var qq: Dictionary = GameManager.romance_service.get_quanquan(_npc_id)
		var lv: int = int(qq.get("level", 0))
		var xp_in: int = int(qq.get("xp_in_level", 0))
		var xp_need: int = int(qq.get("xp_per_level", 200))
		var up: int = int(qq.get("unlocked_portraits", 0))
		var to_next: int = int(qq.get("xp_to_next_portrait", 0))
		var hint: String = "（满级，2 张特殊立绘已全部解锁）" if to_next <= 0 and up >= 2 else "（再 %d 经验解锁下一张特殊立绘）" % to_next
		_qq_info.text = "婘眷值 Lv.%d  %d/%d  已解锁特殊立绘 %d/2 张%s" % [lv, xp_in, xp_need, up, hint]
	else:
		_qq_info.text = "（未结缘：婚后方可培养婘眷值）"

func _build_sections(npc: Dictionary) -> void:
	for c in _content.get_children():
		c.queue_free()
	var stats: Dictionary = _load_stats(_npc_id)
	_section("一、基础数值")
	if stats.is_empty():
		_note("（暂无详细资料，后续填充）")
	else:
		_kv("等级", str(stats.get("level", "-")))
		_kv("气血", str(stats.get("hp", "-")))
		_kv("攻击", str(stats.get("attack", "-")))
		_kv("防御", str(stats.get("defense", "-")))
	_section("二、武学")
	var arts: Array = stats.get("martial_arts", [])
	if arts.is_empty():
		_note("（暂无）")
	else:
		_note("、".join(arts))
	_section("三、可赠予偏好")
	var gifts: Array = stats.get("gift_prefs", [])
	_note("、".join(gifts) if not gifts.is_empty() else "（暂无）")
	_section("四、与主角好感")
	var aff: int = 0
	if GameManager.bond_service != null:
		aff = GameManager.bond_service.get_affection(_npc_id)
	_kv("好感度", "%d / 100" % aff)
	_section("五、互动")
	var btns: Array = []
	if GameManager.romance_service != null and GameManager.romance_service.is_spouse(_npc_id):
		btns.append(_btn("同游旅行 (+5 婘眷值)", true, _on_travel))
		if not GameManager.romance_service.get_children_of(_npc_id).is_empty():
			btns.append(_btn("一家人出游 (+15 婘眷值)", true, _on_family_outing))
		btns.append(_btn("勾选当前立绘", true, _on_select_portrait))
	else:
		btns.append(_btn("切磋", bool(stats.get("can_spar", false)), _on_spar))
	btns.append(_btn("送礼", true, _on_gift))
	btns.append(_btn("查看其背包", true, _on_view_backpack))
	for b in btns:
		_content.add_child(b)
	_section("六、个人背包")
	_note(String(stats.get("backpack_note", "（NPC 个人背包：后续可由任务/赠予把物品给主角查看）")))

func _load_stats(npc_id: String) -> Dictionary:
	if not FileAccess.file_exists(NPC_STATS_PATH):
		return {}
	var f := FileAccess.open(NPC_STATS_PATH, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return parsed.get(npc_id, {})
	return {}

func _section(title: String) -> void:
	var h := Label.new()
	h.text = title
	h.add_theme_font_size_override("font_size", 18)
	h.add_theme_color_override("font_color", UIPalette.GOLD)
	_content.add_child(h)

func _note(text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UIPalette.DISABLED)
	_content.add_child(l)

func _kv(k: String, v: String) -> void:
	var row := HBoxContainer.new()
	var kl := Label.new()
	kl.custom_minimum_size = Vector2(120, 0)
	kl.text = k
	var vl := Label.new()
	vl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vl.text = v
	row.add_child(kl)
	row.add_child(vl)
	_content.add_child(row)

func _btn(text: String, enabled: bool, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.focus_mode = Control.FOCUS_NONE
	if enabled:
		b.pressed.connect(cb)
	UIFeedback.attach(b)
	return b

func _on_travel() -> void:
	var r: Dictionary = GameManager.romance_service.travel_together(_npc_id)
	EventBus.notification_show.emit("同游归来，婘眷值 +5" if r.get("ok", false) else "未能同游")
	_refresh()

func _on_family_outing() -> void:
	var r: Dictionary = GameManager.romance_service.family_outing(_npc_id)
	EventBus.notification_show.emit("阖家出游，婘眷值 +15" if r.get("ok", false) else "未能出游")
	_refresh()

func _on_select_portrait() -> void:
	if GameManager.romance_service != null:
		GameManager.romance_service.select_portrait(_npc_id, _portrait_index)
	EventBus.notification_show.emit("已切换为该 NPC 立绘形象（对话框/NPC 面板生效）")
	_apply_current_portrait()

func _on_spar() -> void:
	EventBus.notification_show.emit("（切磋接口预留：后续接入战斗）")

func _on_gift() -> void:
	EventBus.notification_show.emit("（送礼接口预留：后续接入背包赠予）")

func _on_view_backpack() -> void:
	EventBus.notification_show.emit("（查看 NPC 背包接口预留）")

func _on_relationship_changed() -> void:
	if is_instance_valid(self):
		_refresh()

func _exit_tree() -> void:
	if EventBus.bond_relationship_changed.is_connected(_on_relationship_changed):
		EventBus.bond_relationship_changed.disconnect(_on_relationship_changed)

## 编辑器预览（UIPreview 调用）：手动赋值 @onready 后填示例 NPC 面板（规避 GameManager）
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_name_label = $Panel/Margin/VLayout/Header/PortraitNav/NameLabel
	_qq_info = $Panel/Margin/VLayout/Header/PortraitNav/QQInfo
	_portrait_label = $Panel/Margin/VLayout/Header/PortraitNav/SwipeRow/PortraitLabel
	_prev_btn = $Panel/Margin/VLayout/Header/PortraitNav/SwipeRow/PrevBtn
	_next_btn = $Panel/Margin/VLayout/Header/PortraitNav/SwipeRow/NextBtn
	_content = $Panel/Margin/VLayout/BodyAnchor/Content
	_close = $Panel/Margin/VLayout/Close
	if _name_label == null or _content == null:
		return
	_npc_id = ""
	_name_label.text = "示例 NPC（预览）"
	_qq_info.text = "（未结缘：婚后方可培养婘眷值）"
	_portrait_label.text = "立绘 0/0"
	_prev_btn.disabled = true
	_next_btn.disabled = true
	_close.text = "关闭"
	for c in _content.get_children():
		c.queue_free()
	_section("一、基础数值")
	_kv("等级", "30")
	_kv("气血", "2500")
	_kv("攻击", "320")
	_kv("防御", "210")
	_section("二、武学")
	_note("天山六阳掌、凌波微步")
	_section("三、可赠予偏好")
	_note("茶具、古琴")
	_section("四、与主角好感")
	_kv("好感度", "68 / 100")
	_section("五、互动")
	_content.add_child(_btn("切磋", false, _on_spar))
	_content.add_child(_btn("送礼", true, _on_gift))
	_content.add_child(_btn("查看其背包", true, _on_view_backpack))
	_section("六、个人背包")
	_note(String(_load_stats("").get("backpack_note", "（NPC 个人背包：后续可由任务/赠予把物品给主角查看）")))
