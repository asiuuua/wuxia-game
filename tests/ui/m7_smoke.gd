# tests/ui/m7_smoke.gd
# M7 运行时冒烟：实例化 TownScene，验证 A（角色呼吸 _apply_breath 运行时无报错）
extends Node

func _ready() -> void:
	await get_tree().process_frame
	var ts = load(PathConstants.SCENE_TOWN).instantiate()
	add_child(ts)
	await get_tree().create_timer(1.0).timeout
	print("[M7] TownScene instantiated children=%d (breath tween applied if no SCRIPT ERROR above)" % ts.get_child_count())
	ts.queue_free()
	get_tree().quit()
