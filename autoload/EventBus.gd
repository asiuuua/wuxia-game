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
signal item_used(item_id: String, effect: Dictionary)             # 使用消耗品生效：effect = {hp, mp}

# === 战斗模块 ===
@warning_ignore("unused_signal")
signal combat_started(combat_id: String)
@warning_ignore("unused_signal")
signal combat_ended(combat_id: String, result: int)
@warning_ignore("unused_signal")
signal combat_character_died(character_id: String)

# === 蓝图中枢事件（严格区分 NOTIFY 通知 / CMD 指令） ===
# NOTIFY：已发生事实，发出方不等待返回（战斗模块发完即结束）
@warning_ignore("unused_signal")
signal combat_finished(combat_id: String, victory: bool, escaped: bool, unit_snapshots: Array)
@warning_ignore("unused_signal")
signal quest_failed(quest_id: String, reason: String)
@warning_ignore("unused_signal")
signal unit_downed(unit_id: String, is_non_lethal: bool)
# CMD：请求执行动作（任务/对话发出，战斗模块接收后开启战斗）
@warning_ignore("unused_signal")
signal cmd_start_combat(attacker_list: Array, defender_list: Array)
@warning_ignore("unused_signal")
signal cmd_set_unit_faction(unit_id: String, faction_id: int)
@warning_ignore("unused_signal")
signal cmd_apply_story_buff(unit_id: String, buff_id: String)

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
signal quest_ready_to_turn_in(quest_id: String)
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

# === 配置（规范 §4.4） ===
@warning_ignore("unused_signal")
signal config_loaded(success: bool)
@warning_ignore("unused_signal")
signal config_validation_failed(errors: Array)

# === UI ===
@warning_ignore("unused_signal")
signal ui_screen_opened(screen_name: String)
@warning_ignore("unused_signal")
signal ui_screen_closed(screen_name: String)

# === 世界环境（阶段A 基础设施） ===
@warning_ignore("unused_signal")
signal world_day_advanced(day: int)
@warning_ignore("unused_signal")
signal world_weather_changed(weather: int)
@warning_ignore("unused_signal")
signal world_time_changed(day: int, time_of_day: float, season: int, weather: int)

# === 锻造系统（Phase 2 系统填充 · 契约层） ===
@warning_ignore("unused_signal")
signal cmd_forge(recipe_id: String, count: int)
@warning_ignore("unused_signal")
signal notify_forge_completed(recipe_id: String, output_item_id: String, count: int)
@warning_ignore("unused_signal")
signal notify_forge_failed(recipe_id: String, reason: String)

# === 商店系统（Phase 2 系统填充 · 契约层） ===
@warning_ignore("unused_signal")
signal cmd_buy(shop_id: String, item_id: String, count: int)
@warning_ignore("unused_signal")
signal cmd_sell(shop_id: String, item_id: String, count: int)
@warning_ignore("unused_signal")
signal notify_trade_completed(shop_id: String, item_id: String, count: int, is_buy: bool)
@warning_ignore("unused_signal")
signal notify_trade_failed(shop_id: String, item_id: String, reason: String)

# === 门派系统（Phase 2 系统填充 · 契约层） ===
@warning_ignore("unused_signal")
signal cmd_join_sect(sect_id: String)
@warning_ignore("unused_signal")
signal cmd_contribute_sect(sect_id: String, amount: int)
@warning_ignore("unused_signal")
signal notify_sect_joined(sect_id: String)
@warning_ignore("unused_signal")
signal notify_sect_reputation_changed(sect_id: String, new_reputation: int)
@warning_ignore("unused_signal")
signal notify_sect_rank_up(sect_id: String, new_rank: int)
@warning_ignore("unused_signal")
signal notify_sect_join_failed(sect_id: String, reason: String)
