# scenes/ui/overlays/hud/skill_bar_panel.gd
# HUD 快捷技能栏（v2 四面板之一）：展示已装备到快捷栏的武学（display-only 灰发）。
# 数据源：GameManager.ability_service.equipped_combat（武学窗主权，只读消费）。
# 订阅 combat_skill_equipped（单槽更新）+ notify_skill_bar_changed（整栏刷新）
#      + notify_skill_cd_update（冷却读秒展示，武学窗实现冷却后生效）。
# 注意：冷却倒计时逻辑归属武学窗主权，本面板只展示 remain_time 文本，不驱动计时。
# 配色走 UIPalette。

extends Control
class_name SkillBarPanel

const UIPalette = preload("res://core/constants/ui_theme.gd")

# 单个技能槽（图标 + 名称 + 冷却读秒覆盖层）
class _Slot extends Control:
	var _icon: TextureRect
	var _name: Label
	var _cd: Label
	var _ability_id: String = ""
	func _init() -> void:
		custom_minimum_size = Vector2(60, 60)
		size = Vector2(60, 60)
		var sb := StyleBoxFlat.new()
		sb.bg_color = UIPalette.GLASS_BG
		sb.border_color = UIPalette.GLASS_BORDER
		sb.border_width_left = 1
		sb.border_width_top = 1
		sb.border_width_right = 1
		sb.border_width_bottom = 1
		add_theme_stylebox_override("panel", sb)
		_icon = TextureRect.new()
		_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		add_child(_icon)
		_name = Label.new()
		_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_name.anchor_left = 0.0
		_name.anchor_right = 1.0
		_name.anchor_top = 1.0
		_name.anchor_bottom = 1.0
		_name.offset_top = -16.0
		_name.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
		_name.add_theme_font_size_override("font_size", UIPalette.FS_TINY)
		add_child(_name)
		_cd = Label.new()
		_cd.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_cd.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_cd.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_cd.add_theme_color_override("font_color", UIPalette.BADGE_RED)
		_cd.add_theme_font_size_override("font_size", UIPalette.FS_SUB)
		_cd.visible = false
		add_child(_cd)
	func set_empty() -> void:
		_ability_id = ""
		_icon.texture = null
		_icon.visible = false
		_name.text = "—"
		_cd.visible = false
	func set_ability(ability_id: String) -> void:
		_ability_id = ability_id
		_name.text = ConfigManager.get_ability(ability_id).get("name", ability_id) if ConfigManager.has_ability(ability_id) else ability_id
		if UIManager.has_icon("skills/" + ability_id):
			_icon.texture = UIManager.get_icon("skills/" + ability_id)
			_icon.visible = true
		else:
			_icon.texture = null
			_icon.visible = false
		_cd.visible = false
	func get_ability_id() -> String:
		return _ability_id
	func set_cd(remain: float) -> void:
		if remain > 0.0:
			_cd.text = "%.1f" % remain
			_cd.visible = true
		else:
			_cd.visible = false

var _slots: Array[_Slot] = []

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_build()
	if is_instance_valid(EventBus):
		EventBus.combat_skill_equipped.connect(_on_skill_equipped)
		EventBus.notify_skill_bar_changed.connect(_refresh_full)
		EventBus.notify_skill_cd_update.connect(_on_cd_update)
	_refresh_full()

func _build() -> void:
	# 底部居中
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -210.0
	offset_right = 210.0
	offset_top = -96.0
	offset_bottom = -12.0
	var h := HBoxContainer.new()
	h.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	h.add_theme_constant_override("separation", 4)
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(h)
	for i in range(6):
		var s := _Slot.new()
		_slots.append(s)
		h.add_child(s)

func _exit_tree() -> void:
	if not is_instance_valid(EventBus):
		return
	if EventBus.combat_skill_equipped.is_connected(_on_skill_equipped):
		EventBus.combat_skill_equipped.disconnect(_on_skill_equipped)
	if EventBus.notify_skill_bar_changed.is_connected(_refresh_full):
		EventBus.notify_skill_bar_changed.disconnect(_refresh_full)
	if EventBus.notify_skill_cd_update.is_connected(_on_cd_update):
		EventBus.notify_skill_cd_update.disconnect(_on_cd_update)

# 整栏刷新（装备变化 / 首次进入）
func _refresh_full(_p: Variant = null) -> void:
	if not is_instance_valid(GameManager) or GameManager.ability_service == null:
		for s in _slots:
			s.set_empty()
		return
	var equipped: Array[String] = GameManager.ability_service.equipped_combat
	for i in range(_slots.size()):
		var s: _Slot = _slots[i]
		if i < equipped.size() and equipped[i] != "":
			s.set_ability(equipped[i])
		else:
			s.set_empty()

# 单槽装备变化
func _on_skill_equipped(_ability_id: String, slot: int) -> void:
	if slot < 0 or slot >= _slots.size():
		return
	if not is_instance_valid(GameManager) or GameManager.ability_service == null:
		return
	var equipped: Array[String] = GameManager.ability_service.equipped_combat
	if slot < equipped.size() and equipped[slot] != "":
		_slots[slot].set_ability(equipped[slot])
	else:
		_slots[slot].set_empty()

# 冷却读秒展示（武学窗实现冷却后推送；本面板不驱动计时）
func _on_cd_update(skill_id: String, remain_time: float) -> void:
	for s in _slots:
		if s.get_ability_id() == skill_id:
			s.set_cd(remain_time)
