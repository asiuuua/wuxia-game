# tests/unit/test_hud_panels.gd
# v2 HUD 四面板拆分自验：验证 Hud 挂载 4 个面板且各面板独立构建不崩。
# 测试环境未入树，add_child 不会自动触发子节点 _ready，故手动调用以覆盖构建/订阅逻辑。

extends TestBase

const Hud = preload("res://scenes/ui/overlays/hud/Hud.gd")
const StatusCardPanel = preload("res://scenes/ui/overlays/hud/status_card_panel.gd")
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
	var p1 := StatusCardPanel.new(); p1._ready(); p1.free()
	var p2 := TopRightMenuPanel.new(); p2._ready(); p2.free()
	var p3 := QuestTrackPanel.new(); p3._ready(); p3.free()
	var p4 := SkillBarPanel.new(); p4._ready(); p4.free()
	expect(true, "四面板独立 _ready 未崩溃")

func test_skill_bar_has_six_slots() -> void:
	var p := SkillBarPanel.new()
	p._ready()
	p._refresh_full()
	expect(p.get_child_count() > 0, "技能栏应至少含一个布局容器")
	expect(p.get_child(0).get_child_count() == 6, "技能栏应有 6 个槽位，实际 %d" % p.get_child(0).get_child_count())
	p.free()

func test_status_card_is_visual_scaled_to_two_thirds() -> void:
	# 用户截图三轮反馈：状态卡「缩小三分之一」→ 保留 2/3（≈0.667），实际渲染 227×212，
	# 远低于屏幕左上 1/4（960×540）。修改此值需同步改 docs/HUD常驻系统落地方案v2_2026-08-29.md 的尺寸表。
	var p := StatusCardPanel.new()
	p._ready()
	expect(is_equal_approx(p.scale.x, 0.667), "状态卡 scale.x 应为 0.667（缩小 1/3），实际 %f" % p.scale.x)
	expect(is_equal_approx(p.scale.y, 0.667), "状态卡 scale.y 应为 0.667（缩小 1/3），实际 %f" % p.scale.y)
	expect(p.pivot_offset == Vector2.ZERO, "状态卡 pivot_offset 应锚左上 Vector2.ZERO")
	p.free()

func test_quest_track_default_position() -> void:
	# 无存档时应落到默认（状态卡正下方 2 指头距离）；拖动后写盘，重挂载沿用（用户需求：屏幕固定）
	var p := QuestTrackPanel.new()
	p._ready()
	p._write_json({})      # 清掉任何残留存档，确保走默认
	p._load_position()
	expect(p.global_position == QuestTrackPanel.DEFAULT_POS,
		"无存档时默认位置应为状态卡下方 2 指头（%s），实际 %s" % [str(QuestTrackPanel.DEFAULT_POS), str(p.global_position)])
	p.free()

func test_quest_track_default_below_status_card() -> void:
	# 用户 2026-08-29 明确要求：初始位置在「状态卡 2 指头距离」处（正下方、左缘对齐）
	var dp := QuestTrackPanel.DEFAULT_POS
	# x 与状态卡左缘 (12) 对齐
	expect(is_equal_approx(dp.x, 12.0), "任务栏 x 应与状态卡左缘对齐 (12)，实际 %f" % dp.x)
	# y = 状态卡顶(12) + 渲染高(318*0.667≈212) + 2 指头(32) ≈ 256
	var expected_y: float = 12.0 + 318.0 * 0.667 + 2.0 * 16.0
	expect(is_equal_approx(dp.y, expected_y), "任务栏 y 应为状态卡下方 2 指头（≈%f），实际 %f" % [expected_y, dp.y])
	QuestTrackPanel.new().free()

func test_quest_track_clamps_to_screen() -> void:
	# 用户需求：可随意拖动，但不可脱离屏幕
	var p := QuestTrackPanel.new()
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
	var p := QuestTrackPanel.new()
	p._ready()
	p._write_json({})
	p._load_position()
	p.global_position = Vector2(123, 456)
	p._save_position()
	var d := p._read_json()
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
	var p := QuestTrackPanel.new()
	p._ready()
	expect(p._scroll is ScrollContainer, "任务追踪应含 ScrollContainer 滚动列表")
	if p._scroll is ScrollContainer:
		expect(p._scroll.horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "横向滚动应禁用")
		expect(p._scroll.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_AUTO, "纵向滚动应自动")
	expect(p._entries != null, "_entries 列表容器应存在且为滚动内容")
	p.free()

func test_quest_track_scroll_caps_height() -> void:
	# 内容超高时列表区应被封顶到 MAX_VISIBLE，触发滚动而非无限撑高
	var p := QuestTrackPanel.new()
	p._ready()
	p._entries.custom_minimum_size = Vector2(0, 9999)   # 模拟超长内容
	p._apply_scroll_height()
	expect(p._scroll.size.y <= 361.0, "列表区高度应被封顶到 MAX_VISIBLE(360)，实际 %f" % p._scroll.size.y)
	expect(p._scroll.size.y >= 59.0, "列表区高度不应低于最小 60，实际 %f" % p._scroll.size.y)
	p.free()

func test_quest_track_frosted_glass() -> void:
	# 用户需求：毛玻璃效果（半透 + 圆角 + 阴影）
	var p := QuestTrackPanel.new()
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
	var p := QuestTrackPanel.new()
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
