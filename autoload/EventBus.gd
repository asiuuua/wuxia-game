# autoload/EventBus.gd
# 全局事件总线：跨模块通信唯一通道（规范 §6）
# 铁律：禁止直接引用其他业务模块；谁产生谁 emit，谁关心谁 connect；参数用值类型

extends Node
# 注：autoload 脚本不能写 class_name X 与 autoload 同名，会与单例冲突报错（已删除）

# EventBus 是单例事件总线：信号是给**外部模块** emit/订阅的，本类自身不发射是
# 正常设计（保持跨模块解耦）。GDScript 静态检查会误报 "unused signal"，
# 用类级 @warning_ignore 仅抑制本文件的该类警告，不污染项目级设置。
@warning_ignore("unused_signal")

# === 背包模块 ===
@warning_ignore("unused_signal")
signal inventory_item_added(item_id: String, count: int)
@warning_ignore("unused_signal")
signal inventory_item_removed(item_id: String, count: int)
@warning_ignore("unused_signal")
signal inventory_weight_changed(current: float, max_weight: float)
@warning_ignore("unused_signal")
signal inventory_add_overflow(item_id: String, lost_count: int)   # 入包溢出：UI 据此提示"背包已满，损失X"
@warning_ignore("unused_signal")
signal item_used(item_id: String, effect: Dictionary)             # 【RETIRED·0-B.12 违例·禁新增同族】使用消耗品生效：effect = {hp, mp}（GATE21 基线冻结，改造走 ItemUsedPayload 类）

# === 战斗模块 ===
@warning_ignore("unused_signal")
signal combat_started(combat_id: String)
@warning_ignore("unused_signal")
signal combat_ended(combat_id: String, result: int)

# === 战术战棋网格（战斗窗口主权 · 共享地基纯追加） ===
# 视图层（BattleGridNode/BattleEntity）订阅；逻辑层 CombatCore 产生，谁产生谁 emit
@warning_ignore("unused_signal")
signal grid_highlight_update(highlight_dict: Dictionary)   # 【RETIRED·0-B.12 违例·禁新增同族】高亮刷新：{type:int -> Array[Vector2i]}（GATE21 基线冻结，改造走 GridHighlightPayload 类）

# === 蓝图中枢事件（严格区分 NOTIFY 通知 / CMD 指令） ===
# NOTIFY：已发生事实，发出方不等待返回（战斗模块发完即结束）
@warning_ignore("unused_signal")
signal combat_finished(combat_id: String, victory: bool, escaped: bool, unit_snapshots: Array)
@warning_ignore("unused_signal")
signal quest_failed(quest_id: String, reason: String)
# CMD：请求执行动作（任务/对话发出，战斗模块接收后开启战斗）
@warning_ignore("unused_signal")
signal cmd_start_combat(attacker_list: Array, defender_list: Array)

# === 难度系统（阶段1 骨架） ===
@warning_ignore("unused_signal")
signal cmd_set_difficulty(difficulty_id: String, is_new_game: bool)
@warning_ignore("unused_signal")
signal notify_difficulty_changed(new_difficulty_id: String)
@warning_ignore("unused_signal")
signal notify_difficulty_change_rejected(difficulty_id: String)
@warning_ignore("unused_signal")
signal notify_player_party_wiped_out()
@warning_ignore("unused_signal")
signal notify_escape_success()
@warning_ignore("unused_signal")
signal notify_escape_fail()
@warning_ignore("unused_signal")
signal notify_defeat_cg(text_id: String)

# === 武学模块 ===
@warning_ignore("unused_signal")
signal ability_learned(ability_id: String)
@warning_ignore("unused_signal")
signal ability_used(ability_id: String, caster_id: String)
@warning_ignore("unused_signal")
signal combat_skill_equipped(ability_id: String, slot: int)

# === 装备模块（Phase 2） ===
@warning_ignore("unused_signal")
signal equipment_equipped(slot: String, item_id: String)
@warning_ignore("unused_signal")
signal equipment_unequipped(slot: String, item_id: String)
@warning_ignore("unused_signal")
signal equipment_changed()

# === 炼药模块（Phase 2） ===
@warning_ignore("unused_signal")
signal alchemy_refined(recipe_id: String, output_item_id: String, count: int)
@warning_ignore("unused_signal")
signal alchemy_failed(recipe_id: String, reason: String)

# === 任务模块 ===
@warning_ignore("unused_signal")
signal quest_accepted(quest_id: String)
@warning_ignore("unused_signal")
signal quest_objective_updated(quest_id: String, objective_id: String, progress: int)
@warning_ignore("unused_signal")
signal quest_objective_completed(quest_id: String, objective_id: String)
@warning_ignore("unused_signal")
signal quest_completed(quest_id: String)
@warning_ignore("unused_signal")
signal quest_turned_in(quest_id: String)
@warning_ignore("unused_signal")
signal quest_phase_changed(phase: int)

# === 玩家模块 ===
@warning_ignore("unused_signal")
signal player_level_up(new_level: int)
@warning_ignore("unused_signal")
signal player_exp_changed(current: int, max_exp: int)
@warning_ignore("unused_signal")
signal player_hp_changed(current: int, max_hp: int)
@warning_ignore("unused_signal")
signal player_mp_changed(current: int, max_mp: int)
@warning_ignore("unused_signal")
signal player_stats_changed()
@warning_ignore("unused_signal")
signal player_died()
@warning_ignore("unused_signal")
signal player_money_changed(silver: int, copper: int, gold: int)

# === 对话模块 ===
@warning_ignore("unused_signal")
signal dialogue_started(dialogue_id: String, npc_id: String)
@warning_ignore("unused_signal")
signal dialogue_ended(dialogue_id: String)
@warning_ignore("unused_signal")
signal dialogue_event_triggered(event_key: String)

# === 表现层指令通道（12 图 QD-R10/P-Q10 收口 2026-09-06）===
# services 层禁 Node 演出：PresentationEffect 只经此通道产指令，
# 相机/场景演出由装配层（GameManager）订阅执行。
@warning_ignore("unused_signal")
signal screen_shake_requested(intensity: float, duration: float)

# === 游戏流程 ===
@warning_ignore("unused_signal")
signal game_started()
@warning_ignore("unused_signal")
signal game_saved(slot: int)
@warning_ignore("unused_signal")
signal game_loaded(slot: int)
@warning_ignore("unused_signal")
signal scene_changed(scene_name: String)

# === 启动流程（Bootstrap，规范 §4.1） ===
@warning_ignore("unused_signal")
signal bootstrap_started(total_steps: int)
@warning_ignore("unused_signal")
signal bootstrap_step_started(step_name: String, index: int)
@warning_ignore("unused_signal")
signal bootstrap_step_completed(step_name: String, index: int)
@warning_ignore("unused_signal")
signal bootstrap_completed()

# === 错误处理（规范 §4.2） ===
@warning_ignore("unused_signal")
signal game_error(level: int, module: String, message: String)
@warning_ignore("unused_signal")
signal notification_show(text: String)

# === 补丁/热更新（规范 §4.7） ===
@warning_ignore("unused_signal")
signal patch_applied(patch_id: String, version: String)


# === UI ===
@warning_ignore("unused_signal")
signal ui_action_requested(action_id: String)                  # 菜单/按钮动作请求：UI 只 emit，UIManager 据此路由（数据驱动，零硬编码跳转）
@warning_ignore("unused_signal")
signal popup_close_requested(popup: Control)                   # 弹窗关闭请求：PopupBase.request_close 发出，UIManager 统一收口（隐藏缓存/销毁），弹窗自身不销毁自己

# === 图标解析（架构治理 · 依赖反转：UI 层经 EventBus 注入解析器到 UIManager） ===
# 背景：IconRegistry 位于 scenes/ui 层（UI 窗口主权），基础层 autoload/ui_manager.gd 不得静态
# 依赖它（否则构成"基础层反向依赖上层"的唯一真实架构违例）。故改为：UI 层在运行时把
# IconRegistry.get_icon / has_icon 两个 Callable 经本信号注入 UIManager，UIManager 仅持槽位。
# 谁产生谁 emit（组合根 Bootstrap._ready 在 UIManager 就绪后 emit），UIManager 接收，零静态耦合。
@warning_ignore("unused_signal")
signal icon_provider_registered(get_fn: Callable, has_fn: Callable)   # UI 层注入图标解析器（get_icon / has_icon）

# === 世界环境（阶段A 基础设施） ===
@warning_ignore("unused_signal")
signal world_day_advanced(day: int)
@warning_ignore("unused_signal")
signal world_weather_changed(weather: int)
@warning_ignore("unused_signal")
signal world_time_changed(day: int, time_of_day: float, season: int, weather: int)

# === 锻造系统（Phase 2 系统填充 · 契约层） ===
@warning_ignore("unused_signal")
signal notify_forge_completed(recipe_id: String, output_item_id: String, count: int)
@warning_ignore("unused_signal")
signal notify_forge_failed(recipe_id: String, reason: String)

# === 商店系统（Phase 2 系统填充 · 契约层） ===
@warning_ignore("unused_signal")
signal notify_trade_completed(shop_id: String, item_id: String, count: int, is_buy: bool)
@warning_ignore("unused_signal")
signal notify_trade_failed(shop_id: String, item_id: String, reason: String)

# === 门派系统（Phase 2 系统填充 · 契约层） ===
@warning_ignore("unused_signal")
signal notify_sect_joined(sect_id: String)
@warning_ignore("unused_signal")
signal notify_sect_reputation_changed(sect_id: String, new_reputation: int)
@warning_ignore("unused_signal")
signal notify_sect_rank_up(sect_id: String, new_rank: int)
@warning_ignore("unused_signal")
signal notify_sect_join_failed(sect_id: String, reason: String)

# === 结缘系统（模块18 · M1：好感度/送礼/好感度事件） ===
@warning_ignore("unused_signal")
signal bond_affection_changed(npc_id: String, current: int, delta: int)
@warning_ignore("unused_signal")
signal bond_affection_level_up(npc_id: String, new_level: int)
@warning_ignore("unused_signal")
signal bond_affection_event_triggered(npc_id: String, event_id: String)
@warning_ignore("unused_signal")
signal bond_gift_given(npc_id: String, item_id: String, affection_gain: int, reaction: int)
@warning_ignore("unused_signal")
signal bond_gift_disliked(npc_id: String, item_id: String)

# === 姻缘系统（模块18 · M2：姻缘/婚姻分支） ===
@warning_ignore("unused_signal")
signal bond_romance_formed(npc_id: String, stage: int)
@warning_ignore("unused_signal")
signal bond_relationship_changed()
@warning_ignore("unused_signal")
signal bond_child_born(npc_id: String, child_id: String)
# === M3：结义 / 师徒 / 婚礼演出（公开 API 配套信号，纯追加） ===
@warning_ignore("unused_signal")
signal bond_sworn_formed(npc_id: String, stage: int)
@warning_ignore("unused_signal")
signal bond_master_set(npc_id: String, role: int)
@warning_ignore("unused_signal")
signal bond_apprentice_taken(npc_id: String)
@warning_ignore("unused_signal")
signal bond_wedding_started(npc_id: String, wedding_type: int, scene_path: String)

# === 欢庆模块（结缘窗口主权 · 共享地基纯追加） ===
# 由 romance_service.begin_celebration 在配额内 emit，UI 监听后打开 CelebrationOverlay 播放 CG。
@warning_ignore("unused_signal")
signal celebration_started(npc_id: String, cg_id: String)
# 婘眷值每满 500 经验解锁一张特殊立绘时 emit（npc_id + 已解锁总数），供 UI 弹喜讯 / NPC 面板刷新。
@warning_ignore("unused_signal")
signal bond_special_portrait_unlocked(npc_id: String, total_unlocked: int)

# === HUD 常驻系统（UI 窗口主权 · 共享地基纯追加） ===
# 注意：本段为 UI 窗口补完 v2 HUD 四面板所需的跨窗通知信号。
# 任务窗在 accept/turn_in/reset 处 emit notify_quest_track_changed；
# 武学窗在装备/卸下/冷却推进处 emit notify_skill_bar_changed / notify_skill_cd_update。
# 仅声明信号，不在此处 emit（谁产生谁 emit，铁律）。
@warning_ignore("unused_signal")
signal notify_quest_track_changed()                          # 任务追踪列表变化（接取/交付/重置）
@warning_ignore("unused_signal")
signal notify_skill_bar_changed()                            # 快捷栏武学装备变化
@warning_ignore("unused_signal")
signal notify_skill_cd_update(skill_id: String, remain_time: float)  # 快捷栏武学冷却推进（秒）
