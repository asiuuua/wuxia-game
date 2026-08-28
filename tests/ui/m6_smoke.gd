# tests/ui/m6_smoke.gd
# M6 运行时冒烟：验证 C（quest_phase 真源）+ D（cmd_start_combat 自动接线）
extends Node

var _phase_seen: int = -1

func _ready() -> void:
	# 提前捕获 SceneTree 引用：下方 emit cmd_start_combat 会触发 start_battle → change_scene_to_file
	# （Godot 4.x 为同步切场景），会把本节点(M6Test)释放；释放后 get_tree() 变 null，故须先存引用。
	var tree := get_tree()
	await tree.process_frame
	print("[M6] boot ok, autoloads loaded")

	# ===== C: quest_phase（GameState 为唯一真源，quest_service 门面转发） =====
	var p0: int = GameState.get_quest_phase()
	EventBus.quest_phase_changed.connect(_on_phase)
	GameState.advance_quest_phase()
	GameState.set_quest_phase(5)
	var svc: int = GameManager.quest_service.get_phase()
	var phase_snap: int = _phase_seen  # 快照：下方还原 set_quest_phase(1) 会把 _phase_seen 改成 1，须先存
	print("[M6] quest_phase start=%d phase_seen=%d final=%d svc_facade=%d" % [p0, phase_snap, GameState.get_quest_phase(), svc])
	GameState.set_quest_phase(1)  # 还原，避免污染（本测试不写存档）

	# ===== D: cmd_start_combat 接线（emit → GameManager 解析 NPC→battle_id → start_battle） =====
	EventBus.cmd_start_combat.emit(["player"], ["npc_bandit"])
	var b1: String = GameManager.pending_battle_id
	EventBus.cmd_start_combat.emit(["player"], ["npc_hunter"])
	var b2: String = GameManager.pending_battle_id
	EventBus.cmd_start_combat.emit(["player"], ["npc_sect_elder"])
	var b3: String = GameManager.pending_battle_id
	EventBus.cmd_start_combat.emit(["player"], ["no_such_npc"])  # 不存在的 defender：应告警且不崩溃
	var b4: String = GameManager.pending_battle_id
	print("[M6] cmd battle_id bandit=%s hunter=%s elder=%s badcase=%s" % [b1, b2, b3, b4])

	var ok: bool = (b1 == "battle_bandit_001" and b2 == "battle_wolf_001" \
		and b3 == "battle_sect_trials" and b4 == "battle_sect_trials" \
		and p0 == 1 and phase_snap == 5 and svc == 5)
	print("[M6] ok=%s" % ok)
	if ok:
		print("[M6] ALL_M6_OK")
	tree.quit()

func _on_phase(v: int) -> void:
	_phase_seen = v
