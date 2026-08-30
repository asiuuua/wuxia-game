# services/object_pool.gd
# 全局对象池（按 key 分桶复用节点实例），服务「数十至数百特效 / 投射物」极致帧率需求。
# 安全原则（规避 fresh 版 ObjectPool 的两类已知 bug）：
#   - 绝不偷活跃节点：池空且达 max 时返回 null 由调用方决定，不抢占在用对象 → 无视觉串台
#   - 不持有父节点引用：节点由调用方 add_child 到合适父节点；release 时主动 remove_child 后入空闲桶
#   - 悬空守卫：所有操作前 is_instance_valid 检查，场景销毁后残留引用不引发错误
# 用法：
#   var n = ObjectPool.acquire("hit_spark", func(): return preload("res://...").instantiate())
#   parent.add_child(n); ... 使用 n ...
#   ObjectPool.release("hit_spark", n)
# 生命周期：切场景边界（GameManager.start_battle / return_to_town 调 ResourceManager.reclaim_all）内统一 clear()，避免跨场景泄漏。
# 注意：本脚本作为 autoload 注册（name=ObjectPool，见 project.godot），故无需声明 class_name —— 同名 autoload 单例已提供全局
#       ObjectPool 实例引用；若再写 class_name ObjectPool 会与 autoload 单例名冲突（"hides an autoload singleton"）导致加载失败。
extends Node

const DEFAULT_MAX := 256

var _pools: Dictionary = {}

func _ensure(key: String) -> Dictionary:
	if not _pools.has(key):
		_pools[key] = {"free": [], "active": [], "max": DEFAULT_MAX}
	return _pools[key]

## 取一个可用节点：优先复用空闲桶；否则在 max 内新建；达上限返回 null（绝不偷活跃节点）
func acquire(key: String, factory: Callable) -> Node:
	var pool := _ensure(key)
	if not pool.free.is_empty():
		var n: Node = pool.free.pop_back()
		if is_instance_valid(n):
			pool.active.append(n)
			return n
		# 残留失效引用，继续走新建分支
	if pool.active.size() < pool.max:
		var n: Node = factory.call() as Node
		if n != null:
			pool.active.append(n)
		return n
	return null

## 归还节点：从活跃桶移除，从父节点摘下，入空闲桶待复用
func release(key: String, node: Node) -> void:
	var pool := _ensure(key)
	var idx: int = pool.active.find(node)
	if idx >= 0:
		pool.active.remove_at(idx)
	if is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		pool.free.append(node)

## 设置某 key 的最大实例数（默认 256）
func set_max(key: String, max_count: int) -> void:
	_ensure(key).max = max_count

## 回收：释放某 key（或全部 key）的所有节点，切场景 / 退场时调用，避免跨场景泄漏
func clear(key: String = "") -> void:
	if key == "":
		for k in _pools.keys():
			_free_pool(_pools[k])
		_pools.clear()
	elif _pools.has(key):
		_free_pool(_pools[key])
		_pools.erase(key)

func _free_pool(pool: Dictionary) -> void:
	for n in pool.free + pool.active:
		if is_instance_valid(n):
			n.queue_free()
	pool.free.clear()
	pool.active.clear()

## 诊断：当前活跃 / 空闲计数（调试用）
func stats(key: String) -> Dictionary:
	if not _pools.has(key):
		return {"active": 0, "free": 0, "max": 0}
	var p: Dictionary = _pools[key]
	return {"active": p.active.size(), "free": p.free.size(), "max": p.max}
