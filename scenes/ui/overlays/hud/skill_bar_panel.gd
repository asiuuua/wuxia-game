@tool
# scenes/ui/overlays/hud/skill_bar_panel.gd
# HUD 快捷技能栏（v2 四面板之一）：展示已装备到快捷栏的武学（display-only 灰发）。
# 数据源：GameManager.ability_service.equipped_combat（武学窗主权，只读消费）。
# 订阅 combat_skill_equipped（单槽更新）+ notify_skill_bar_changed（整栏刷新）
#      + notify_skill_cd_update（冷却读秒展示，武学窗实现冷却后生效）。
# 注意：冷却倒计时逻辑归属武学窗主权，本面板只展示 remain_time 文本，不驱动计时。
# 配色走 UIPalette。
#
# B 路线（2026-08-30）：面板锚点与 6 个技能槽实例已迁入 SkillBarPanel.tscn
# （SkillSlot.tscn 静态 instance，美术可直接在编辑器增删槽位），脚本只收集引用 + 刷新。

extends HudDraggablePanel
class_name SkillBarPanel

const UIPalette = preload("res://core/constants/ui_theme.gd")
# SkillSlot 仅做类型标注；槽位实例已静态声明在 SkillBarPanel.tscn 的 HBox 下
const SkillSlot = preload("res://scenes/ui/components/skill_slot/SkillSlot.gd")

@onready var _hbox: HBoxContainer = $HBox

var _slots: Array[SkillSlot] = []

func _ready() -> void:
	if Engine.is_editor_hint():
		return
	_collect_slots()
	# 拖拽初始化：默认底部居中（屏幕宽/2 - 面板宽/2，屏幕高 - 面板高 - 边距）；可拖拽、落点持久化
	var vp := _screen_size()
	var panel_w := get_combined_minimum_size().x
	var panel_h := get_combined_minimum_size().y
	var default_pos := Vector2(maxf(12.0, vp.x * 0.5 - panel_w * 0.5), maxf(12.0, vp.y - panel_h - 16.0))
	_init_drag("skill_bar", default_pos)
	if is_instance_valid(EventBus):
		EventBus.combat_skill_equipped.connect(_on_skill_equipped)
		EventBus.notify_skill_bar_changed.connect(_refresh_full)
		EventBus.notify_skill_cd_update.connect(_on_cd_update)
	_refresh_full()

# 收集 .tscn 里静态声明的槽位（顺序即 HBox 子节点顺序）
func _collect_slots() -> void:
	_slots.clear()
	for c in _hbox.get_children():
		var s: SkillSlot = c as SkillSlot
		if s != null:
			_slots.append(s)

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
		var s: SkillSlot = _slots[i]
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

# === 编辑器预览（UIPreview 调用）：收集 .tscn 静态槽位并置空，展示技能栏布局 ===
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	_hbox = get_node_or_null("HBox")
	if _hbox == null:
		return
	_collect_slots()
	for s in _slots:
		s.set_empty()