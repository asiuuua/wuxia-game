@tool
@warning_ignore("shadowed_global_identifier")
extends PopupBase

const UIPalette = preload("res://core/constants/ui_theme.gd")
const ItemSlot = preload("res://scenes/ui/components/item_slot/ItemSlot.gd")
const ItemSlotScene = preload("res://scenes/ui/components/item_slot/ItemSlot.tscn")
const Tooltip = preload("res://scenes/ui/components/tooltip/Tooltip.gd")

var _weight_label: Label
var _grids: Dictionary = {}
var _slot_by_iid: Dictionary = {}
var _tooltip: Tooltip
var _context_menu: PopupMenu = null
var _current_iid: String = ""

# B 路线：静态结构（dim/面板/标题/三栏滚动网格）已迁入 InventoryScreen.tscn，
# 美术可在编辑器直接编辑布局与外观；本脚本只负责数据填充、状态与交互。
# 节点引用经 $ 路径取自 .tscn（结构契约），避免硬编码 new() 重建布局。
func _ready() -> void:
	if Engine.is_editor_hint():
		return
	focus_mode = Control.FOCUS_NONE
	popup_id = "Inventory"
	# 压暗底（颜色取自 UIPalette，避免 .tscn 里写死）
	$Dim.color = UIPalette.DIM
	$Dim.mouse_filter = Control.MOUSE_FILTER_STOP
	# 玻璃面板皮肤（结构在 .tscn，皮肤暂沿用统一玻璃样式；后续迁 UISkin 纹理/九宫格层）
	UICenterUtils.apply_glass_style($Center/Panel)
	# 标题/重量/按钮文本与配色（文本需 tr()，留代码；结构在 .tscn 由美术编辑）
	var title: Label = $Center/Panel/Margin/VBox/Header/Title
	title.text = tr("ui_inventory_title")
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", UIPalette.GOLD)
	_weight_label = $Center/Panel/Margin/VBox/Header/Weight
	_weight_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_weight_label.add_theme_color_override("font_color", UIPalette.TEXT_SECONDARY)
	var sort_btn: Button = $Center/Panel/Margin/VBox/Header/SortBtn
	sort_btn.text = tr("ui_inventory_tidy")
	sort_btn.focus_mode = Control.FOCUS_NONE
	sort_btn.pressed.connect(_on_sort)
	var close: Button = $Center/Panel/Margin/VBox/Header/CloseBtn
	close.text = tr("ui_inventory_close")
	close.focus_mode = Control.FOCUS_NONE
	close.pressed.connect(request_close)
	_grids["main"] = $Center/Panel/Margin/VBox/MainScroll/MainGrid
	_grids["material"] = $Center/Panel/Margin/VBox/MaterialScroll/MaterialGrid
	_grids["quest"] = $Center/Panel/Margin/VBox/QuestScroll/QuestGrid
	($Center/Panel/Margin/VBox/MainLabel).text = _bag_title("main")
	($Center/Panel/Margin/VBox/MaterialLabel).text = _bag_title("material")
	($Center/Panel/Margin/VBox/QuestLabel).text = _bag_title("quest")
	_tooltip = Tooltip.new()
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# 抬升层级并置顶，避免贴边物品浮窗被面板/裁剪容器遮挡或裁切
	_tooltip.z_index = 100
	add_child(_tooltip)
	_tooltip.move_to_front()
	_refresh()
	EventBus.inventory_item_added.connect(_on_inv_changed)
	EventBus.inventory_item_removed.connect(_on_inv_changed)

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
			slot = ItemSlotScene.instantiate()
			_connect_slot(slot)
			grid.add_child(slot)
		if slot == null:
			continue
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
			# P0 修复：丢弃必须经 drop_item，受 DISCARDABLE/LOCKED 保护，绝不直接 remove_instance 绕过招牌锁定保护
			var tgt: ItemInstance = inv.get_instance_by_id(iid)
			if tgt != null:
				var res: Dictionary = inv.drop_item(iid, tgt.count)
				if not res.get("ok", false):
					# 锁定/不可丢弃：保留物品，仅记录（不静默绕过保护）；提示层由 UI 窗口补全
					GameLogger.info("Inventory", "丢弃被拒(保护生效): %s reason=%s" % [iid, res.get("reason", "")])
			_refresh()
		3:
			# 拆分前判空：物品可能在并发移除后已不存在，get_instance_by_id 返回 null → .count 崩溃
			var tgt: ItemInstance = inv.get_instance_by_id(iid)
			if tgt != null:
				var cnt: int = int(tgt.count) / 2
				if cnt > 0:
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
	# P2-9：服务层按类型不变式可能拒绝跨栏拖拽（返回 false）。这里不再静默 no-op，
	# 落点非法时记录（预览"暗示允许"但落点非法的体验问题归 UI 窗口 ItemSlot._can_drop_data 处理）
	var ok: bool = GameManager.inventory_service.move_instance(src_iid, tgt_bag, _index_in_bag(tgt_bag, target_iid))
	if not ok:
		GameLogger.info("Inventory", "拖拽被拒(服务层类型不变式): %s -> %s" % [src_iid, tgt_bag])
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

func _exit_tree() -> void:
	if EventBus.inventory_item_added.is_connected(_on_inv_changed):
		EventBus.inventory_item_added.disconnect(_on_inv_changed)
	if EventBus.inventory_item_removed.is_connected(_on_inv_changed):
		EventBus.inventory_item_removed.disconnect(_on_inv_changed)

# === 编辑器预览（UIPreview 调用）：填标题/重量 + 各栏铺空槽，展示布局（不依赖存档） ===
func _editor_preview() -> void:
	if not Engine.is_editor_hint():
		return
	var title: Label = get_node_or_null("Center/Panel/Margin/VBox/Header/Title")
	if title != null:
		title.text = tr("ui_inventory_title")
		title.add_theme_font_size_override("font_size", 22)
		title.add_theme_color_override("font_color", UIPalette.GOLD)
	var weight: Label = get_node_or_null("Center/Panel/Margin/VBox/Header/Weight")
	if weight != null:
		weight.text = tr("ui_inventory_weight") % [12, 100]
	var sort_btn: Button = get_node_or_null("Center/Panel/Margin/VBox/Header/SortBtn")
	if sort_btn != null:
		sort_btn.text = tr("ui_inventory_tidy")
	var close: Button = get_node_or_null("Center/Panel/Margin/VBox/Header/CloseBtn")
	if close != null:
		close.text = tr("ui_inventory_close")
	var grids: Array = [
		get_node_or_null("Center/Panel/Margin/VBox/MainScroll/MainGrid"),
		get_node_or_null("Center/Panel/Margin/VBox/MaterialScroll/MaterialGrid"),
		get_node_or_null("Center/Panel/Margin/VBox/QuestScroll/QuestGrid")
	]
	for g in grids:
		if g == null:
			continue
		for i in 6:
			var slot: Control = ItemSlotScene.instantiate()
			g.add_child(slot)
			slot.owner = null
			if slot.has_method("set_empty"):
				slot.set_empty()
