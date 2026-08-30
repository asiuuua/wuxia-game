# scenes/gameplay/battle/tactical_test_riverside.gd
# 战棋测试场景根：把「真实战斗逻辑」(TacticalBattleScene) 作为子场景复用，再挂一层装饰
# (TacticalTestDecorator) 提供水面/竹子遮挡/房屋遮挡/雾气。战斗逻辑零改动、零复制。
# 用途：作为你那张参考图的"战棋测试场景"落地——进入即看到带遮挡纵深与水面雾气的竹林水畔战场。
# 触发：godot --path . res://scenes/gameplay/battle/tactical_test_riverside.tscn
#       （headless 下跑 0.8s 自动退出，便于门禁冒烟；编辑器下常驻可手动操作）

extends Node2D

const BATTLE_ID := "tactical_test_riverside"

func _enter_tree() -> void:
	# 必须在子场景 TacticalBattleScene._ready 之前写入，否则它读不到 pending_battle_id
	if GameManager != null:
		# 允许外部（GameManager.start_test_swarm 等）指定不同战斗配置复用本装饰壳；否则用默认 BATTLE_ID
		if GameManager.debug_override_battle_id != "":
			GameManager.pending_battle_id = GameManager.debug_override_battle_id
		else:
			GameManager.pending_battle_id = BATTLE_ID

func _ready() -> void:
	var tbs := get_node_or_null("TacticalBattleScene")
	var bf: Node2D = null
	if tbs != null:
		bf = tbs.get_node_or_null("Battlefield")
	var deco = get_node_or_null("TacticalTestDecorator")
	if bf != null and deco != null and deco.has_method("attach"):
		deco.attach(bf, self)
	# 注：本场景主要在编辑器里打开查看。Godot 4 在「headless 直接加载场景文件」模式下主循环不推进时间，
	# 定时器 timeout 不会触发，故不在此做自退；headless 验证请读启动日志确认零报错即可。
