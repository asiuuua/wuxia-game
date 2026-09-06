# autoload/defeat_handler.gd
# 团灭死亡执行器（阶段2 消费端核心）：读难度配置复合列，按步执行死亡惩罚。
# 铁律：本类零「if difficulty==」判断；一切行为由 DifficultyManager 配置 API 驱动。
# 基础动作 → 扣钱 → 掉物(记抵押物) → 没钱则负债 → 播对应 CG。

extends Node
# 批D 子批3（ADR-0007 装配收敛）：原 autoload 降级为普通 Node——由 Bootstrap（生命周期壳）
# 挂载，_ready 订阅团灭通知语义保真（add_child 后 _ready 照常触发）。
class_name DefeatHandler

func _ready() -> void:
	# 订阅团灭通知（combat_service.finalize 在 DEFEAT 时发出）
	EventBus.notify_player_party_wiped_out.connect(_on_party_wiped_out)

# ===================== 入口：按基础动作分派 =====================
func _on_party_wiped_out() -> void:
	var behaviour: int = DifficultyManager.get_player_defeat_behaviour()
	match behaviour:
		CombatEnums.DefeatBehaviour.RESPAWN_CHECKPOINT:
			_do_respawn()
		CombatEnums.DefeatBehaviour.LOAD_LATEST_SAVE:
			_do_load_and_penalize()
		CombatEnums.DefeatBehaviour.DELETE_SAVE:
			_do_delete_and_title()
		CombatEnums.DefeatBehaviour.TRIGGER_QUEST_FAIL:
			_do_trigger_quest_fail()
		_:
			# 兜底：回安全点
			GameLogger.warn("DefeatHandler", "未识别的团灭行为，退化为安全点复活")
			_do_respawn()

# === 基础动作：回安全点（EASY） ===
func _do_respawn() -> void:
	var ps: PlayerState = GameManager.player_state
	ps.hp = ps.max_hp
	ps.mp = ps.max_mp
	EventBus.player_hp_changed.emit(ps.hp, ps.max_hp)
	EventBus.player_mp_changed.emit(ps.mp, ps.max_mp)
	GameManager.return_to_safe_point()

# === 基础动作：读档 + 施加惩罚（NORMAL/HARD/NIGHTMARE） ===
func _do_load_and_penalize() -> void:
	var slot: int = GameManager.current_slot
	if slot < 0:
		slot = SaveManager.get_latest_save_slot()
	if slot < 0:
		# 无存档可回：退化为安全点复活（避免卡死）
		GameLogger.warn("DefeatHandler", "无可用存档，退化为安全点复活")
		_do_respawn()
		return
	if not SaveManager.load_from_slot(slot):
		_do_respawn()
		return
	# 读档成功：在已恢复状态上施加惩罚
	_apply_penalties()
	# 把惩罚后的状态写回存档，使死亡代价永久化
	if GameManager.current_slot >= 0:
		SaveManager.save_to_slot(GameManager.current_slot)
	GameManager.return_to_safe_point()

# === 基础动作：删档 + 回主菜单（HELL） ===
func _do_delete_and_title() -> void:
	var slot: int = GameManager.current_slot
	if slot >= 0:
		SaveManager.delete_save(slot)
	GameManager.return_to_title()

func _do_trigger_quest_fail() -> void:
	# 当前无具体任务失败惩罚，退化为安全点
	GameLogger.warn("DefeatHandler", "TRIGGER_QUEST_FAIL 未配置具体任务，退化为安全点")
	_do_respawn()

# ===================== 惩罚复合列：扣钱 → 掉物(抵押物) → 负债 → 播CG =====================
func _apply_penalties() -> void:
	var money_loss: int = DifficultyManager.get_defeat_lose_money()
	var broke: bool = false
	if money_loss > 0:
		broke = _lose_money(money_loss)
	if DifficultyManager.get_defeat_lose_items():
		var count: int = DifficultyManager.get_defeat_lose_item_count()
		var lost: Array = GameManager.inventory_service.lose_some_non_rare_items(count)
		for item_id in lost:
			GameState.add_collateral(item_id)   # 记录抵押物，供李村小张赎回线读取
	# 播 CG：仅在「没钱」分支触发（配置 gated）
	var cg_id: String = DifficultyManager.get_defeat_cg_text_id()
	if cg_id != "" and (not DifficultyManager.get_defeat_cg_when_broke_only() or broke):
		EventBus.notify_defeat_cg.emit(cg_id)

# 扣钱：够则扣，不够则扣光；若允许负债则记负债；返回 true 表示「无钱支付」(broke)
func _lose_money(amount: int) -> bool:
	var ps: PlayerState = GameManager.player_state
	if ps.silver >= amount:
		ps.spend_money(amount)
		return false
	# 钱不够：先扣光现有银两
	var remaining: int = amount - ps.silver
	ps.silver = 0
	EventBus.player_money_changed.emit(ps.silver, ps.copper, ps.gold)
	if DifficultyManager.get_defeat_debt_if_broke():
		ps.add_debt(remaining)
		return true
	return true
