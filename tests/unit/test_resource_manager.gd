# tests/unit/test_resource_manager.gd
# P6 全局资源管理器单测：验证 引用计数 / 同步缓存复用 / 分级回收(全量) / 异步完成回调 /
# 集中回收清理立绘缓存。纯测 core/resource_manager.gd 静态逻辑（异步用 pump 手动驱动）。
# 不依赖 UI 节点；异步加载借助 OS 后台线程 + 手动 pump 完成。

extends TestBase
class_name TestResourceManager

const T1 := "res://assets/characters/player.png"
const T2 := "res://assets/characters/village_chief.png"

var _cb_fired := false
var _cb_res: Variant = null


func before_each() -> void:
	ResourceManager.reset()
	# 工业化 P6 重构：reclaim_all 改为钩子驱动；测试中显式登记立绘 LRU 清空钩子（不依赖 GameManager 启动顺序）
	ResourceManager.register_reclaim_hook(PortraitCacheManager.clear)
	_cb_fired = false
	_cb_res = null

func after_each() -> void:
	ResourceManager.reset()
	PortraitCacheManager.clear()


func test_acquire_sync_refcounts_and_reuses() -> void:
	var a: Variant = ResourceManager.acquire_sync(T1)
	expect(a != null, "同步获取应返回非 null（%s）" % T1)
	expect_eq(ResourceManager.get_refcount(T1), 1, "首次获取引用计数应为 1")
	var b: Variant = ResourceManager.acquire_sync(T1)
	expect(a == b, "二次同步获取应返回同一实例（引用计数缓存）")
	expect_eq(ResourceManager.get_refcount(T1), 2, "再次获取引用计数应为 2")
	ResourceManager.release(T1)
	ResourceManager.release(T1)
	expect_eq(ResourceManager.get_refcount(T1), 0, "释放两次后引用计数应为 0（进入温存）")


func test_reclaim_all_releases_warm_entries() -> void:
	ResourceManager.acquire_sync(T1)
	ResourceManager.release(T1)   # 引用归零，进入温存
	ResourceManager.reclaim_all()
	expect(ResourceManager.get_resource(T1) == null, "reclaim_all 应释放引用为 0 的条目")
	expect(not ResourceManager.has(T1), "reclaim_all 后 has(T1) 应为 false")


func test_reclaim_all_clears_portrait_cache() -> void:
	# 立绘经 PortraitCacheManager 缓存一条
	PortraitCacheManager.get_portrait(T2)
	expect(PortraitCacheManager.has_portrait(T2), "前置：立绘应已入缓存")
	ResourceManager.reclaim_all()
	expect(not PortraitCacheManager.has_portrait(T2), "reclaim_all 应集中清理立绘 LRU 缓存")


func test_acquire_async_completes_and_caches() -> void:
	ResourceManager.acquire_async(T1, "", Callable(self, "_on_res"))
	# 手动驱动 pump（模拟 process_frame），限时等待后台线程加载完成
	var guard := 0
	while not _cb_fired and guard < 200:
		ResourceManager.pump()
		OS.delay_msec(5)
		guard += 1
	expect(_cb_fired, "异步加载完成后回调应触发")
	expect(_cb_res != null, "回调应带回非 null 资源")
	expect(ResourceManager.has(T1), "加载完成资源应进入管理器（可后续 get_resource 取用）")
	expect_eq(ResourceManager.get_refcount(T1), 1, "异步获取引用计数应为 1")
	ResourceManager.release(T1)


func _on_res(res: Variant) -> void:
	_cb_fired = true
	_cb_res = res


func test_evict_frees_immediately() -> void:
	ResourceManager.acquire_sync(T1)
	ResourceManager.release(T1)   # 引用归零，进入温存（未到 TTL 不回收）
	ResourceManager.evict(T1)     # 即时释放
	expect(ResourceManager.get_resource(T1) == null, "evict 应即时释放引用为 0 的条目（不等 TTL）")
	expect(not ResourceManager.has(T1), "evict 后 has(T1) 应为 false")
