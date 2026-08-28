@warning_ignore("shadowed_global_identifier")
extends Control

const UIPalette = preload("res://core/constants/ui_theme.gd")
const ItemSlot = preload("res://scenes/ui/components/item_slot/ItemSlot.gd")
const Tooltip = preload("res://scenes/ui/components/tooltip/Tooltip.gd")

var _weight_label: Label
var _grids: Dictionary = {}
var _slot_by_iid: Dictionary = {}
var _tooltip: Tooltip
var _context_menu: PopupMenu = null
var _current_iid: String = ""

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_build()
	_refresh()
	EventBus.inventory_item_added.connect(_on_inv_changed)
	EventBus.inventory_item_removed.connect(_on_inv_changed)

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = UIPalette.DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var panel := Panel.new()
	panel.custom_minimum_size = Vector2(720, 560)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GLASS_BORDER
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.shadow_size = 18
	sb.shadow_offset = Vector2(0, 6)
	sb.shadow_color = UIPalette.GLASS_SHADOW
	panel.add_theme_stylebox_override("panel", sb)
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
	var header := HBoxContainer.new()
	v.add_child(header)
	var title := Label.new()
	title.text = tr("ui_inventory_title")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UIPalette.GOLD)
	header.add_child(title)
	_weight_label = Label.new()
	_weight_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weight_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	header.add_child(_weight_label)
	var sort_btn := Button.new()
	sort_btn.text = tr("ui_inventory_tidy")
	sort_btn.focus_mode = Control.FOCUS_NONE
	sort_btn.pressed.connect(_on_sort)
	header.add_child(sort_btn)
	var close := Button.new()
	close.text = tr("ui_inventory_close")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(UIManager.close_screen.bind(self))
	header.add_child(close)
	for bag_name in ["main", "material", "quest"]:
		var head := Label.new()
		head.text = _bag_title(bag_name)
		head.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
		v.add_child(head)
		var scroll := ScrollContainer.new()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		v.add_child(scroll)
		var grid := GridContainer.new()
		grid.columns = 8
		grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(grid)
		_grids[bag_name] = grid
	_tooltip = Tooltip.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_tooltip)

func _refresh() -> void:
	if _weight_label == null:
		return
	var inv: InventoryService = GameManager.inventory_service
	if inv == null:
		return
	_weight_label.text = tr("ui_inventory_weight") % [inv.get_weight(), inv.get_max_weight()]
	for bag_name in _grids:
		_fill_grid(bag_name, inv)

# 脏刷新：复用已有槽位节点，仅对内容发生变化的槽调用 setup（避免每次全量 queue_free 重建）
func _fill_grid(bag_name: String, inv: InventoryService) -> void:
	var grid: GridContainer = _grids[bag_name]
	var bag: Array = _bag_array(bag_name, inv)
	var desired: Array = []  # 非空实例序列 + 末尾一个空槽（若有物品）
	for inst in bag:
		if inst != null:
			desired.append(inst)
	if desired.size() > 0:
		desired.append(null)
	for i in range(desired.size()):
		var inst = desired[i]
		var sig: String = _slot_sig(inst)
		var slot: ItemSlot
		if i < grid.get_child_count():
			slot = grid.get_child(i) as ItemSlot
		else:
			slot = ItemSlot.new()
			_connect_slot(slot)
			grid.add_child(slot)
		if slot.get_meta("sig", "") != sig:
			var old_iid: String = slot.get_iid()
			if old_iid != "":
				_slot_by_iid.erase(old_iid)
			slot.setup(inst)
			slot.set_meta("sig", sig)
			if inst != null:
				_slot_by_iid[inst.instance_id] = slot
	while grid.get_child_count() > desired.size():
		var extra: ItemSlot = grid.get_child(grid.get_child_count() - 1) as ItemSlot
		var ei: String = extra.get_iid()
		if ei != "":
			_slot_by_iid.erase(ei)
		grid.remove_child(extra)
		extra.queue_free()

# 槽位内容签名：iid + 数量 + 锁定；任一变化即触发 setup 重绘
func _slot_sig(inst) -> String:
	if inst == null:
		return "EMPTY"
	return "%s#%d#%d" % [inst.instance_id, int(inst.count), int(inst.locked)]

func _connect_slot(slot: ItemSlot) -> void:
	slot.slot_pressed.connect(_on_slot_pressed)
	slot.slot_context.connect(_on_slot_context)
	slot.slot_hover.connect(_on_slot_hover)
	slot.slot_drop.connect(_on_slot_drop)

func _on_slot_pressed(iid: String) -> void:
	if iid == "":
		return
	var inst: ItemInstance = GameManager.inventory_service.get_instance_by_id(iid)
	if inst == null:
		return
	var data: Dictionary = ConfigManager.get_item(inst.item_id)
	var flags: int = int(data.get("flags", 0))
	var is_consumable: bool = data.get("type", "") == "pill" or (flags & ItemEnums.ItemFlag.CONSUMABLE) != 0
	if is_consumable:
		GameManager.inventory_service.use_item(iid, "town")
		_refresh()
	else:
		_open_context(iid)

func _on_slot_context(iid: String) -> void:
	_open_context(iid)

func _open_context(iid: String) -> void:
	if iid == "":
		return
	var inst: ItemInstance = GameManager.inventory_service.get_instance_by_id(iid)
	if inst == null:
		return
	_current_iid = iid
	if _context_menu != null:
		_context_menu.queue_free()
		_context_menu = null
	var menu := PopupMenu.new()
	_context_menu = menu
	var data: Dictionary = ConfigManager.get_item(inst.item_id)
	var flags: int = int(data.get("flags", 0))
	var is_consumable: bool = data.get("type", "") == "pill" or (flags & ItemEnums.ItemFlag.CONSUMABLE) != 0
	var is_equippable: bool = data.get("equip_slot", "") != ""
	var is_key: bool = (flags & ItemEnums.ItemFlag.KEY_ITEM) != 0
	var can_split: bool = int(inst.count) > 1 and (flags & ItemEnums.ItemFlag.STACKABLE) != 0
	if is_consumable:
		menu.add_item(tr("ui_item_use"), 0)
	if is_equippable:
		menu.add_item(tr("ui_item_equip"), 1)
	if not is_key:
		menu.add_item(tr("ui_item_discard"), 2)
	if can_split:
		menu.add_item(tr("ui_item_split"), 3)
	menu.id_pressed.connect(_on_context_id)
	add_child(menu)
	menu.popup_centered()

func _on_context_id(id: int) -> void:
	var iid: String = _current_iid
	var inv: InventoryService = GameManager.inventory_service
	if inv == null or iid == "":
		return
	match id:
		0:
			inv.use_item(iid, "town")
		1:
			GameManager.equipment_service.equip(iid)
		2:
			inv.remove_instance(iid)
		3:
			var cnt: int = int(inv.get_instance_by_id(iid).count) / 2
			inv.split_instance(iid, cnt)
	_refresh()
	if _context_menu != null:
		_context_menu.queue_free()
		_context_menu = null

func _on_slot_hover(iid: String) -> void:
	if iid == "":
		_tooltip.hide_tip()
		return
	var inst: ItemInstance = GameManager.inventory_service.get_instance_by_id(iid)
	if inst == null:
		_tooltip.hide_tip()
		return
	_tooltip.show_for(inst.item_id, get_global_mouse_position())

func _on_slot_drop(target_iid: String, data: Dictionary) -> void:
	var src_iid: String = data.get("iid", "")
	if src_iid == "":
		return
	var src_bag: String = _bag_of_iid(src_iid)
	if src_bag == "":
		return
	var tgt_bag: String = _bag_of_iid(target_iid) if target_iid != "" else src_bag
	GameManager.inventory_service.move_instance(src_iid, tgt_bag, _index_in_bag(tgt_bag, target_iid))
	_refresh()

func _on_sort() -> void:
	var inv: InventoryService = GameManager.inventory_service
	if inv == null:
		return
	inv.sort_bag("main")
	inv.sort_bag("material")
	inv.sort_bag("quest")
	_refresh()

func _bag_title(bag_name: String) -> String:
	match bag_name:
		"main": return tr("ui_inventory_main")
		"material": return tr("ui_inventory_material")
		"quest": return tr("ui_inventory_quest")
	return bag_name

func _bag_array(bag_name: String, inv: InventoryService) -> Array:
	match bag_name:
		"main": return inv.main_slots
		"material": return inv.material_slots
		"quest": return inv.quest_slots
	return []

func _bag_of_iid(iid: String) -> String:
	var inv: InventoryService = GameManager.inventory_service
	for name in ["main", "material", "quest"]:
		for inst in _bag_array(name, inv):
			if inst != null and inst.instance_id == iid:
				return name
	return ""

func _index_in_bag(bag_name: String, iid: String) -> int:
	var inv: InventoryService = GameManager.inventory_service
	var bag: Array = _bag_array(bag_name, inv)
	if iid == "":
		return bag.size() - 1
	for i in range(bag.size()):
		var inst = bag[i]
		if inst != null and inst.instance_id == iid:
			return i
	return bag.size() - 1

func _on_inv_changed(_a: Variant = null, _b: Variant = null) -> void:
	_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		UIManager.close_screen(self)
		get_viewport().set_input_as_handled()

func _exit_tree() -> void:
	if EventBus.inventory_item_added.is_connected(_on_inv_changed):
		EventBus.inventory_item_added.disconnect(_on_inv_changed)
	if EventBus.inventory_item_removed.is_connected(_on_inv_changed):
		EventBus.inventory_item_removed.disconnect(_on_inv_changed)
