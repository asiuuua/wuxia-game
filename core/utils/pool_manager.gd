# core/utils/pool_manager.gd
# 对象池管理器（规范 §4.5.2）：按名称登记多个池，统一获取/释放/统计。
# 注册为 Autoload 单例 PoolManager，供战斗等高频场景调用。
# 注：autoload 脚本不写 class_name（与单例名冲突），通过全局单例名调用。

extends Node

var _pools: Dictionary = {}  # pool_name -> ObjectPool

func register_pool(pool_name: String, scene: PackedScene, parent: Node, initial: int = 10, max_size: int = 50) -> void:
	if _pools.has(pool_name):
		GameLogger.warn("Pool", "Pool already registered: %s" % pool_name)
		return
	var pool := ObjectPool.new(scene, parent, initial, max_size)
	_pools[pool_name] = pool
	GameLogger.info("Pool", "Registered pool: %s (initial=%d, max=%d)" % [pool_name, initial, max_size])

func acquire(pool_name: String) -> Node:
	if not _pools.has(pool_name):
		GameLogger.error("Pool", "Pool not found: %s" % pool_name)
		return null
	return _pools[pool_name].acquire()

func release(pool_name: String, obj: Node) -> void:
	if _pools.has(pool_name):
		_pools[pool_name].release(obj)

func release_all(pool_name: String) -> void:
	if _pools.has(pool_name):
		_pools[pool_name].release_all()

func clear_all() -> void:
	for pool_name in _pools:
		_pools[pool_name].clear()
	_pools.clear()

func get_stats() -> Dictionary:
	var stats: Dictionary = {}
	for pool_name in _pools:
		var pool: ObjectPool = _pools[pool_name]
		stats[pool_name] = {"active": pool.get_active_count(), "pooled": pool.get_pool_count()}
	return stats
