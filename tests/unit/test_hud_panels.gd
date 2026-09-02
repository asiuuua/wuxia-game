# tests/unit/test_hud_panels.gd
# v2 HUD 四面板拆分自验：验证 Hud 挂载 4 个面板且各面板独立构建不崩。
# 测试环境未入树，add_child 不会自动触发子节点 _ready，故手动调用以覆盖构建/订阅逻辑。

extends TestBase

# 强制优先加载基类，确保 class_name HudDraggablePanel 在子类解析前注册
# （测试运行器按 preload 顺序解析，HudDraggablePanel 若不先入则子类 extends 报「找不到基类」）
const HudDraggablePanel = preload("res://scenes/ui/overlays/hud/hud_draggable_panel.gd")
const Hud = preload("res://scenes/ui/overlays/hud/Hud.gd")
const StatusCardPanel = preload("res://scenes/ui/overlays/hud/status_card_panel.gd")
# B 路线（2026-08-30）：状态卡静态结构已迁入 StatusCardPanel.tscn，
# 用脚本 new() 出来的实例没有子节点（缩放/数值条全在场景里），故测试一律改为实例化场景。
const StatusCardPanelScene = preload("res://scenes/ui/overlays/hud/StatusCardPanel.tscn")
const QuestTrackPanelScene = preload("res://scenes/ui/overlays/hud/QuestTrackPanel.tscn")
const TopRightMenuPanelScene = preload("res://scenes/ui/overlays/hud/TopRightMenuPanel.tscn")
const SkillBarPanelScene = preload("res://scenes/ui/overlays/hud/SkillBarPanel.tscn")
const TopRightMenuPanel = preload("res://scenes/ui/overlays/hud/top_right_menu_panel.gd")
const QuestTrackPanel = preload("res://scenes/ui/overlays/hud/quest_track_panel.gd")
const SkillBarPanel = preload("res://scenes/ui/overlays/hud/skill_bar_panel.gd")

func test_hud_mounts_four_panels() -> void:
	var hud := Hud.new()
	hud._ready()
	expect(hud.get_child_count() == 4, "Hud 应挂载 4 个面板，实际 %d" % hud.get_child_count())
	# 测试环境未入树，手动触发各子面板 _ready 以验证构建/订阅
	for c in hud.get_children():
		c._ready()
	expect(hud.get_child(0) is StatusCardPanel, "面板0 应为 StatusCardPanel")
	expect(hud.get_child(1) is TopRightMenuPanel, "面板1 应为 TopRightMenuPanel")
	expect(hud.get_child(2) is QuestTrackPanel, "面板2 应为 QuestTrackPanel")
	expect(hud.get_child(3) is SkillBarPanel, "面板3 应为 SkillBarPanel")
	hud.free()

func test_panels_build_without_crash() -> void:
	# 各面板独立实例化 + _ready，验证订阅/构建不崩（服务可能为 null，应有 null 守卫）
	var p1 := StatusCardPanelScene.instantiate(); p1._ready(); p1.free()
	var p2 := TopRightMenuPanelScene.instantiate(); p2._ready(); p2.free()
	var p3 := QuestTrackPanelScene.instantiate(); p3._ready(); p3.free()
	var p4 := SkillBarPanelScene.instantiate(); p4._ready(); p4.free()
	expect(true, "四面板独立 _ready 未崩溃")

func test_skill_bar_has_six_slots() -> void:
	var p := SkillBarPanelScene.instantiate()
	p._ready()
	p._refresh_full()
	expect(p.get_child_count() > 0, "技能栏应至少含一个布局容器")
	expect(p.get_child(0).get_child_count() == 6, "技能栏应有 6 个槽位，实际 %d" % p.get_child(0).get_child_count())
	p.free()

func test_status_card_is_visual_scaled_to_two_thirds() -> void:
	# 设计变更（2026-08-31）：取消 0.667 缩放，改用真实尺寸便于拖拽定位（见 quest_track_panel.gd 注释）。
	# 故状态卡 scale 保持 1.0（不缩放），此处断言与现行实现一致。
	var p := StatusCardPanelScene.instantiate()
	p._ready()
	expect(is_equal_approx(p.scale.x, 1.0), "状态卡 scale.x 应为 1.0（2026-08-31 起取消缩放），实际 %f" % p.scale.x)
	expect(is_equal_approx(p.scale.y, 1.0), "状态卡 scale.y 应为 1.0（2026-08-31 起取消缩放），实际 %f" % p.scale.y)
	expect(p.pivot_offset == Vector2.ZERO, "状态卡 pivot_offset 应锚左上 Vector2.ZERO")
	p.free()

func test_quest_track_default_position() -> void:
	# 无存档时应落到默认（状态卡正下方 2 指头距离）；拖动后写盘，重挂载沿用（用户需求：屏幕固定）
	var p := QuestTrackPanelScene.instantiate()
	p._ready()
	p._write_json({})      # 清掉任何残留存档，确保走默认
	p._load_position()
	expect(p.global_position == QuestTrackPanel.DEFAULT_POS,
		"无存档时默认位置应为状态卡下方 2 指头（%s），实际 %s" % [str(QuestTrackPanel.DEFAULT_POS), str(p.global_position)])
	p.free()

func test_quest_track_default_below_status_card() -> void:
	# 用户 2026-08-29 明确要求：初始位置在「状态卡 2 指头距离」处（正下方、左缘对齐）。
	# 注：2026-08-31 起状态卡取消 0.667 缩放（STATUS_CARD_SCALE=1.0，见 quest_track_panel.gd），
	# 故渲染高 = STATUS_CARD_H(318) * 1.0；公式与现行实现保持一致。
	var dp := QuestTrackPanel.DEFAULT_POS
	# x 与状态卡左缘 (12) 对齐
	expect(is_equal_approx(dp.x, 12.0), "任务栏 x 应与状态卡左缘对齐 (12)，实际 %f" % dp.x)
	# y = 状态卡顶(12) + 渲染高(318*1.0=318) + 2 指头(32) = 362
	var expected_y: float = 12.0 + 318.0 * 1.0 + 2.0 * 16.0
	expect(is_equal_approx(dp.y, expected_y), "任务栏 y 应为状态卡下方 2 指头（≈%f），实际 %f" % [expected_y, dp.y])
	QuestTrackPanelScene.instantiate().free()

func test_quest_track_clamps_to_screen() -> void:
	# 用户需求：可随意拖动，但不可脱离屏幕
	var p := QuestTrackPanelScene.instantiate()
	p._ready()
	p.global_position = Vector2(99999, 99999)
	p._clamp_to_screen()
	expect(p.global_position.x <= 1920 - p.size.x + 1.0, "应夹在屏幕右边界内，实际 x=%f" % p.global_position.x)
	expect(p.global_position.y <= 1080 - p.size.y + 1.0, "应夹在屏幕下边界内，实际 y=%f" % p.global_position.y)
	expect(p.global_position.x >= -1.0, "不应脱离屏幕左")
	expect(p.global_position.y >= -1.0, "不应脱离屏幕上")
	p.free()

func test_quest_track_persists_position() -> void:
	# 拖动落点应持久化，重载后还原
	var p := QuestTrackPanelScene.instantiate()
	p._ready()
	p._write_json({})
	p._load_position()
	p.global_position = Vector2(123, 456)
	p._save_position()
	var d: Dictionary = p._read_json()
	expect(d.has("quest_track"), "存档应包含 quest_track 键")
	var kv: Dictionary = d["quest_track"]
	expect(is_equal_approx(float(kv.get("x")), 123.0), "存档 x 应为 123")
	expect(is_equal_approx(float(kv.get("y")), 456.0), "存档 y 应为 456")
	p._load_position()
	expect(is_equal_approx(p.global_position.x, 123.0), "重载后 x 应还原 123")
	expect(is_equal_approx(p.global_position.y, 456.0), "重载后 y 应还原 456")
	p.free()

func test_quest_track_has_scroll_list() -> void:
	# 用户需求：内部滑动列表，多任务滚动查看
	var p := QuestTrackPanelScene.instantiate()
	p._ready()
	expect(p._scroll is ScrollContainer, "任务追踪应含 ScrollContainer 滚动列表")
	if p._scroll is ScrollContainer:
		expect(p._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "横向滚动应禁用")
		expect(p._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "纵向滚动应自动")
	expect(p._entries != null, "_entries 列表容器应存在且为滚动内容")
	p.free()

func test_quest_track_scroll_caps_height() -> void:
	# 内容超高时列表区应被封顶到 MAX_VISIBLE，触发滚动而非无限撑高
	var p := QuestTrackPanelScene.instantiate()
	p._ready()
	p._entries.custom_minimum_size = Vector2(0, 9999)   # 模拟超长内容
	p._apply_scroll_height()
	expect(p._scroll.size.y <= 361.0, "列表区高度应被封顶到 MAX_VISIBLE(360)，实际 %f" % p._scroll.size.y)
	expect(p._scroll.size.y >= 59.0, "列表区高度不应低于最小 60，实际 %f" % p._scroll.size.y)
	p.free()

func test_quest_track_frosted_glass() -> void:
	# 用户需求：毛玻璃效果（半透 + 圆角 + 阴影）
	var p := QuestTrackPanelScene.instantiate()
	p._ready()
	expect(p.mouse_filter == Control.MOUSE_FILTER_STOP, "根应 STOP 以捕获拖拽")
	expect(p.mouse_default_cursor_shape == Control.CURSOR_MOVE, "应显示可移动光标提示")
	var pnl: Control = p.get_child(0)
	expect(pnl is Panel, "子节点0 应为玻璃 Panel")
	if pnl is Panel:
		var sb: StyleBox = pnl.get_theme_stylebox("panel")
		expect(sb is StyleBoxFlat, "panel 样式应为 StyleBoxFlat")
		if sb is StyleBoxFlat:
			expect(sb.shadow_size > 0, "毛玻璃应有阴影，实际 shadow_size=%d" % sb.shadow_size)
			expect(sb.bg_color.a < 1.0, "毛玻璃背景应半透，实际 alpha=%f" % sb.bg_color.a)
	p.free()

## 集成自验：HUD 三信号之 notify_quest_track_changed 消费端接线
## 注入一个追踪中任务（不依赖具体配置）→ QuestTrackPanel 首次 _refresh 应渲染该任务条目；
## 再 emit notify_quest_track_changed，面板应重建并移除该任务标题。
## 覆盖：EventBus 信号 → QuestTrackPanel._refresh → 条目增删 这条跨模块链路。
func test_quest_track_refreshes_on_signal() -> void:
	var qs = GameManager.quest_service
	if qs == null:
		expect(false, "GameManager.quest_service 未初始化")
		return
	# 注入一个追踪中的假任务（绕过配置依赖，专注验证 HUD 信号接线）
	var st := QuestState.new()
	st.quest_id = "hud_track_test"
	st.status = QuestEnums.QuestStatus.ACTIVE
	st.tracked = true
	qs.active_quests["hud_track_test"] = st
	qs.tracked_ids.append("hud_track_test")
	var p := QuestTrackPanelScene.instantiate()
	p._ready()   # 构建 + 首次 _refresh → 渲染 1 条追踪任务
	var found_title := false
	for c in p._entries.get_children():
		if c is Label and c.text.contains("hud_track_test"):
			found_title = true
	expect(found_title, "接取追踪任务后，HUD 应渲染该任务标题")
	# 移除追踪并广播 notify_quest_track_changed → 面板应重建并移除该标题
	qs.active_quests.erase("hud_track_test")
	qs.tracked_ids.erase("hud_track_test")
	EventBus.notify_quest_track_changed.emit()
	var found_title2 := false
	for c in p._entries.get_children():
		if c is Label and c.text.contains("hud_track_test"):
			found_title2 = true
	expect(not found_title2, "移除追踪并 emit 后，HUD 不应再显示该任务标题")
	# 清理：先断开订阅再释放，避免已释放节点仍挂在 EventBus 上
	if EventBus.notify_quest_track_changed.is_connected(p._refresh):
		EventBus.notify_quest_track_changed.disconnect(p._refresh)
	p.free()
	qs.reset()

## 全生命周期自验：用真实 QuestService API（accept/turn_in/reset）+ 真实进度信号
## 核对 HUD 任务追踪实时刷新是否完整（接取→出现、进度→数字更新、交付→消失、重置→清空）。
## 直接覆盖「刷新不全」这一隐性隐患：既有 test_quest_track_refreshes_on_signal 只测了手动注入/擦除 + emit，
## 从未走真实的 accept/turn_in/reset 发射链，也未验进度数字的实时刷新。
func test_quest_track_full_lifecycle_refresh() -> void:
	var qs = GameManager.quest_service
	if qs == null:
		expect(false, "GameManager.quest_service 未初始化")
		return
	if not ConfigManager.has_quest("q_bandit_001") or not ConfigManager.has_quest("demo_quest"):
		expect(false, "测试依赖的 quest 配置（q_bandit_001 / demo_quest）缺失")
		return
	qs.reset()
	var p := QuestTrackPanelScene.instantiate()
	p._ready()   # 首次 _refresh → 空列表
	expect(_qt_shows(p, "（暂无追踪任务）"), "重置后 HUD 应显示空态文案")

	# 1) 接取 → 信号发射 → 面板实时出现该任务（验证 accept 的 emit 链路，非手动注入）
	qs.accept("q_bandit_001")
	expect(_qt_shows(p, "清剿山贼"), "accept 后 HUD 应实时显示「清剿山贼」")
	qs.accept("demo_quest")
	expect(_qt_shows(p, "失踪的玉佩"), "再 accept 后 HUD 应实时显示「失踪的玉佩」（2 条都在）")

	# 2) 目标进度推进（真实 quest_objective_updated）→ 面板数字刷新为 1/1、目标描述在列
	var st: QuestState = qs.active_quests.get("q_bandit_001", null)
	expect(st != null, "q_bandit_001 应处于 active")
	if st != null:
		st.objectives_progress["defeat"] = 1
		st.objectives_completed["defeat"] = true
		EventBus.quest_objective_updated.emit("q_bandit_001", "defeat", 1)
		expect(_qt_shows(p, "1/1"), "目标进度推进后 HUD 应刷新显示 1/1")
		expect(_qt_shows(p, "击败山贼"), "HUD 应显示目标描述「击败山贼」")

	# 3) 交付（真实 turn_in，状态置 COMPLETED）→ 信号发射 → 该任务从追踪消失，另一条仍在
	st.status = QuestEnums.QuestStatus.COMPLETED
	qs.turn_in("q_bandit_001")
	expect(not _qt_shows(p, "清剿山贼"), "turn_in 后 HUD 不应再显示「清剿山贼」")
	expect(_qt_shows(p, "失踪的玉佩"), "turn_in 后另一条任务仍应在追踪中")

	# 4) 重置 → 清空回到空态
	qs.reset()
	expect(_qt_shows(p, "（暂无追踪任务）"), "reset 后 HUD 应回到空态")

	# 清理：先断开订阅再释放，避免已释放节点仍挂在 EventBus 上
	if EventBus.notify_quest_track_changed.is_connected(p._refresh):
		EventBus.notify_quest_track_changed.disconnect(p._refresh)
	if EventBus.quest_objective_updated.is_connected(p._refresh):
		EventBus.quest_objective_updated.disconnect(p._refresh)
	p.free()
	qs.reset()

# 辅助：面板条目中是否出现含 key 文本的标签（标题 / 目标行 / 空态文案）
func _qt_shows(p: Control, key: String) -> bool:
	for c in p._entries.get_children():
		if c is Label and c.text.contains(key):
			return true
	return false
