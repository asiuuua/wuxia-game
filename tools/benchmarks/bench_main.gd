# tools/benchmarks/bench_main.gd
# GATE40+ 性能基准宿主（17 图 SBP-4/SBP-6，2026-09-06 P1 批次落地）。
# 形态：Godot 场景模式跑（autoload 全在；--script 模式无 autoload，故用 tscn 宿主）。
# 首批 3 项中的 2 项在此进程内测量（SBP-3 推荐 Boot/Save/Combat Turn）：
#   - save_roundtrip：存档组装+原子写+回读+checksum 双验全链路
#   - combat_turn   ：战斗回合结算（player_attack_events + enemy_phase_events）
# 第 3 项 boot（引擎启动墙钟）由 tools/run_benchmarks.py 在进程外测量。
# 输出协议：每项基准一行 `BENCH_RESULT {json}`，由 run_benchmarks.py 收集比对基线。
# 铁律：基准永不删除（SBP-R08）；基准不 finalize 战斗（零奖励副作用，不污染存档）。
extends Node

const SAVE_ITER := 30
const COMBAT_ACTIONS := 100
const BENCH_BATTLE_ID := "battle_bandit_001"   # 固定规模基准战斗（bandit_001+bandit_002，非战棋）
const COMBAT_SEED := 20260905   # 固定 seed：SeededRNG 注入，降低随机波动

func _ready() -> void:
	# 看门狗：任何中途脚本错误都不允许门禁空转挂死（240s 强制退出码 2）
	var watchdog := Timer.new()
	watchdog.wait_time = 240.0
	watchdog.one_shot = true
	watchdog.timeout.connect(func(): print("BENCH_RESULT " + JSON.stringify({"benchmark_id": "watchdog", "error": "超时强退"})); get_tree().quit(2))
	add_child(watchdog)
	watchdog.start()
	var results: Array = []
	var failed := false
	var r_save := bench_save_roundtrip()
	results.append(r_save)
	failed = failed or r_save.has("error")
	var r_combat := bench_combat_turn()
	results.append(r_combat)
	failed = failed or r_combat.has("error")
	for r in results:
		print("BENCH_RESULT " + JSON.stringify(r))
	get_tree().quit(1 if failed else 0)

## 存档全链路基准：组装（12 键 SaveHeader+正文）→ 原子写（tmp 回读 checksum 双验 + .bak）
## → 回读 → checksum 复算。写 user://bench_tmp/ 独立沙箱，不碰真实槽位，跑完即删。
func bench_save_roundtrip() -> Dictionary:
	var dir := "user://bench_tmp/"
	var path := dir + "bench.json"
	DirAccess.make_dir_recursive_absolute(dir)
	var samples: Array[float] = []
	var keys := SaveManager.get_saveable_count()
	for i in SAVE_ITER:
		var t0 := Time.get_ticks_usec()
		var d := SaveManager._build_save_data()
		if not SaveManager._write_json(path, d, -1):
			return {"benchmark_id": "save_roundtrip", "error": "原子写失败 iter=%d" % i}
		var loaded: Dictionary = SaveManager._load_json(path)
		if loaded.is_empty() or not SaveManager._checksum_ok(loaded):
			return {"benchmark_id": "save_roundtrip", "error": "回读/checksum 失败 iter=%d" % i}
		samples.append((Time.get_ticks_usec() - t0) / 1000.0)
	_cleanup_dir(dir)
	return {
		"benchmark_id": "save_roundtrip",
		"median_ms": _median(samples),
		"input_scale": "keys=%d iter=%d" % [keys, SAVE_ITER],
		"result_distribution": "median",
		"samples": samples.size(),
	}

## 战斗回合基准：固定 seed + 固定战斗 + 固定动作数。
## 每动作 = 玩家普攻事件流 + 敌方阶段事件流（纯逻辑结算，无演出无 finalize）。
func bench_combat_turn() -> Dictionary:
	var samples: Array[float] = []
	var actions := 0
	var restarts := 0
	_start_seeded()
	while actions < COMBAT_ACTIONS:
		if GameManager.combat_service.is_over():
			if restarts > 32:
				return {"benchmark_id": "combat_turn", "error": "战斗过早结束重启超限"}
			_start_seeded()
			restarts += 1
			continue
		var t0 := Time.get_ticks_usec()
		if not GameManager.combat_service.is_over():
			GameManager.combat_service.player_attack_events()
		if not GameManager.combat_service.is_over():
			GameManager.combat_service.enemy_phase_events()
		samples.append((Time.get_ticks_usec() - t0) / 1000.0)
		actions += 1
	return {
		"benchmark_id": "combat_turn",
		"median_ms": _median(samples),
		"input_scale": "battle=%s actions=%d" % [BENCH_BATTLE_ID, COMBAT_ACTIONS],
		"result_distribution": "median",
		"samples": samples.size(),
	}

func _start_seeded() -> void:
	GameManager.combat_service.start_combat(BENCH_BATTLE_ID)
	# 固定 seed 覆盖 start_combat 的时间派生 seed（内核 configure 第二参）
	GameManager.combat_service.get_core().configure(GameManager.combat_service.get_state(), COMBAT_SEED)

func _median(samples: Array[float]) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	var n := sorted.size()
	return sorted[n / 2] if n % 2 == 1 else (sorted[n / 2 - 1] + sorted[n / 2]) / 2.0

func _cleanup_dir(dir: String) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir():
			DirAccess.remove_absolute(dir + fname)
		fname = d.get_next()
	d.list_dir_end()
	DirAccess.remove_absolute(dir)
