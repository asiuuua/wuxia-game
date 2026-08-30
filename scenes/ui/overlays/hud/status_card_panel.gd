@tool
# scenes/ui/overlays/hud/status_card_panel.gd
# HUD 左上角状态卡（v2 四面板之一）：头像框 + 姓名/等级/银两 + 气血条 + 内力条 + 六维属性条。
# 纯展示层，订阅 EventBus 的 player_* 信号刷新，不修改业务数据。
# 配色全部走 UIPalette，禁止裸 Color 字面量。
#
# B 路线（2026-08-30）：整个静态结构（磨砂面板 / 头像框 / 三组文字 / 8 条数值条实例）
# 已迁入 StatusCardPanel.tscn，美术可在编辑器直接改布局、尺寸、配色与整体缩放。
# 本脚本只保留：① 引用场景节点 ② 给数值条填动态参数（标签/颜色/长度）③ EventBus 订阅与刷新。
# 原 _build() / _build_avatar() 约 95 行代码搭 UI 全部删除。

extends HudDraggablePanel
class_name StatusCardPanel

const UIPalette = preload("res://core/constants/ui_theme.gd")
# 双 const 引用模式：StatusBar 仅做类型标注（数值条实例已在 .tscn 内，不再 instantiate）
const StatusBar = preload("res://scenes/ui/components/status_bar/StatusBar.gd")

# 六维属性（key 对应 PlayerState 成员名，name 为面板显示用单字，node 为 .tscn 中对应节点名）
const _ATTRS := [
	{"key": "strength", "name": "力", "node": "BarStrength"},
	{"key": "constitution", "name": "骨", "node": "BarConstitution"},
	{"key": "agility", "name": "敏", "node": "BarAgility"},
	{"key": "wisdom", "name": "悟", "node": "BarWisdom"},
	{"key": "luck", "name": "福", "node": "BarLuck"},
	{"key": "focus", "name": "定", "node": "BarFocus"},
]

@onready var _name_label: Label = $Panel/Margin/V/Top/Info/NameLabel
@onready var _lv_label: Label = $Panel/Margin/V/Top/Info/LvLabel
@onready var _money_label: Label = $Panel/Margin/V/Top/Info/MoneyLabel
@onready var _avatar_char: Label = $Panel/Margin/V/Top/Avatar/AvatarChar
@onready var _avatar_tex: TextureRect = $Panel/Margin/V/Top/Avatar/AvatarTex
@onready var _hp_bar: StatusBar = $Panel/Margin/V/HPBar
@onready var _mp_bar: StatusBar = $Panel/Margin/V/MPBar

var _attr_bars: Dictionary = {}

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_setup_bars()
	# 拖拽初始化（状态卡默认左上角 12,12；可拖拽、落点持久化）
	_init_drag("status_card", Vector2(12.0, 12.0))
	if is_instance_valid(EventBus):
		EventBus.player_hp_changed.connect(_refresh)
		EventBus.player_mp_changed.connect(_refresh)
		EventBus.player_level_up.connect(_refresh)
		EventBus.player_exp_changed.connect(_refresh)
		EventBus.player_stats_changed.connect(_refresh)
		EventBus.player_money_changed.connect(_refresh)
	_refresh()

# === 数值条动态参数（结构与位置在 .tscn，颜色/标签/长度仍按数据填） ===
func _setup_bars() -> void:
	_hp_bar.setup("气血", UIPalette.HP_FILL, 300.0)
	_mp_bar.setup("内力", UIPalette.MP_FILL, 300.0)
	for a in _ATTRS:
		var b := get_node(NodePath("Panel/Margin/V/AttrGrid/" + String(a["node"]))) as StatusBar
		if b == null:
			continue
		b.setup(a["name"], UIPalette.ATTR_FILL, 150.0, 14.0, false)
		_attr_bars[a["key"]] = b

func _exit_tree() -> void:
	# 本面板挂在 autoload 的 HUD 层，切场景/游戏退出时 EventBus 可能已先于本节点释放，
	# 故 disconnect 前必须 is_instance_valid 判空。
	if not is_instance_valid(EventBus):
		return
	if EventBus.player_hp_changed.is_connected(_refresh):
		EventBus.player_hp_changed.disconnect(_refresh)
	if EventBus.player_mp_changed.is_connected(_refresh):
		EventBus.player_mp_changed.disconnect(_refresh)
	if EventBus.player_level_up.is_connected(_refresh):
		EventBus.player_level_up.disconnect(_refresh)
	if EventBus.player_exp_changed.is_connected(_refresh):
		EventBus.player_exp_changed.disconnect(_refresh)
	if EventBus.player_stats_changed.is_connected(_refresh):
		EventBus.player_stats_changed.disconnect(_refresh)
	if EventBus.player_money_changed.is_connected(_refresh):
		EventBus.player_money_changed.disconnect(_refresh)

func _refresh(_a: Variant = null, _b: Variant = null, _c: Variant = null) -> void:
	if not is_instance_valid(GameManager) or GameManager.player_state == null:
		return
	var ps: PlayerState = GameManager.player_state
	if _name_label != null:
		_name_label.text = ps.player_name
	if _lv_label != null:
		_lv_label.text = "等级 %d" % ps.level
	if _money_label != null:
		_money_label.text = "银两 %d" % ps.silver
	if _avatar_char != null:
		_avatar_char.text = ps.player_name.left(1)
	if _avatar_tex != null:
		# 双通道：有玩家头像（resources/icons/npc/player.png）显图，否则首字兜底
		if UIManager.has_icon("npc/player"):
			_avatar_tex.texture = UIManager.get_icon("npc/player")
			_avatar_tex.visible = true
			_avatar_char.visible = false
		else:
			_avatar_tex.visible = false
			_avatar_char.visible = true
	_hp_bar.set_value(ps.hp, ps.max_hp)
	_mp_bar.set_value(ps.mp, ps.max_mp)
	for a in _ATTRS:
		var b: StatusBar = _attr_bars.get(a["key"], null)
		if b != null:
			# PlayerState 是 Object，Object.get 仅 1 参（无默认值）；
			# 用 `or 0` 兜底缺省属性，避免解析期 “Too many arguments for get()”。
			var raw: Variant = ps.get(a["key"])
			b.set_level(int(raw) if raw != null else 0, 100)

# === 编辑器预览（UIPreview 调用）：手动赋值 @onready 后 _setup_bars + 注入模拟数值，展示填满状态卡 ===
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_name_label = get_node_or_null("Panel/Margin/V/Top/Info/NameLabel")
	_lv_label = get_node_or_null("Panel/Margin/V/Top/Info/LvLabel")
	_money_label = get_node_or_null("Panel/Margin/V/Top/Info/MoneyLabel")
	_avatar_char = get_node_or_null("Panel/Margin/V/Top/Avatar/AvatarChar")
	_avatar_tex = get_node_or_null("Panel/Margin/V/Top/Avatar/AvatarTex")
	_hp_bar = get_node_or_null("Panel/Margin/V/HPBar") as StatusBar
	_mp_bar = get_node_or_null("Panel/Margin/V/MPBar") as StatusBar
	if _name_label == null or _hp_bar == null:
		return
	_setup_bars()
	_name_label.text = "侠客无名"
	_lv_label.text = "等级 12"
	_money_label.text = "银两 9999"
	if _avatar_char != null:
		_avatar_char.text = "侠"
	if _avatar_tex != null:
		_avatar_tex.visible = false
	if _avatar_char != null:
		_avatar_char.visible = true
	_hp_bar.set_value(220, 300)
	_mp_bar.set_value(150, 300)
	for a in _ATTRS:
		var b: StatusBar = get_node_or_null("Panel/Margin/V/AttrGrid/" + String(a["node"])) as StatusBar
		if b != null:
			b.set_level(70, 100)
