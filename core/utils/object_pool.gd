# core/utils/object_pool.gd
# 通用对象池（规范 §4.5.1）：复用高频创建/销毁的节点，降低 GC 与实例化开销。
# 适用：伤害飘字、战斗特效、投射物、掉落物等（见 docs/开发规范.md 对象池清单）。

class_name ObjectPool
extends RefCounted

var _scene: PackedScene
var _pool: Array[Node] = []
var _active: Array[Node] = []
var _max_size: int = 50
var _initial_size: int = 10
var _parent: Node = null
var _auto_expand: bool = true

func _init(scene: PackedScene, parent: Node, initial_size: int = 10, max_size: int = 50) -> void:
	_scene = scene
	_parent = parent
	_initial_size = initial_size
	_max_size = max_size
	_prewarm()

func _prewarm() -> void:
	for i in _initial_size:
		var obj: Node = _scene.instantiate()
		obj.visible = false
		_parent.add_child(obj)
		_pool.append(obj)

func acquire() -> Node:
	var obj: Node = null
	if _pool.size() > 0:
		obj = _pool.pop_back()
	elif _auto_expand and _active.size() < _max_size:
		obj = _scene.instantiate()
		_parent.add_child(obj)
	else:
		if _active.size() > 0:
			obj = _active.pop_front()
			_reset_object(obj)
	if obj != null:
		obj.visible = true
		_active.append(obj)
	return obj

func release(obj: Node) -> void:
	if obj == null:
		return
	_active.erase(obj)
	_reset_object(obj)
	obj.visible = false
	if _pool.size() < _max_size:
		_pool.append(obj)
	else:
		obj.queue_free()

func release_all() -> void:
	for obj in _active.duplicate():
		release(obj)

func _reset_object(obj: Node) -> void:
	if obj.has_method("reset"):
		obj.reset()
	obj.position = Vector2.ZERO
	obj.scale = Vector2.ONE
	obj.rotation = 0.0
	obj.modulate = Color.WHITE

func clear() -> void:
	release_all()
	for obj in _pool:
		obj.queue_free()
	_pool.clear()

func get_active_count() -> int:
	return _active.size()

func get_pool_count() -> int:
	return _pool.size()
