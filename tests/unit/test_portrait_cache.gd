# tests/unit/test_portrait_cache.gd
# P2 立绘 LRU 缓存单测：验证 命中复用 / 缺失降级 / LRU 上限回收 / 预热 / 释放清空
# 不依赖 UI 节点，纯测 core/portrait_cache_manager.gd 的静态缓存逻辑。

extends TestBase
class_name TestPortraitCache

const T1 := "res://assets/characters/player.png"
const T2 := "res://assets/characters/village_chief.png"
const T3 := "res://assets/characters/village_chief_face.png"

func before_each() -> void:
	PortraitCacheManager.clear()
	PortraitCacheManager.set_cap(50)

func after_each() -> void:
	PortraitCacheManager.clear()
	PortraitCacheManager.set_cap(50)

func test_missing_returns_null() -> void:
	expect(PortraitCacheManager.get_portrait("") == null, "空路径应返回 null")
	expect(PortraitCacheManager.get_portrait("res://no_such_portrait_xyz.png") == null, "不存在路径应返回 null")

func test_load_caches_and_reuses() -> void:
	var a := PortraitCacheManager.get_portrait(T1)
	expect(a != null, "应成功加载真实立绘 %s" % T1)
	expect(PortraitCacheManager.has_portrait(T1), "加载后应进入缓存")
	expect_eq(PortraitCacheManager.get_cache_size(), 1, "缓存应只有 1 条")
	var b := PortraitCacheManager.get_portrait(T1)
	expect(a == b, "二次取用应返回同一 Texture2D 实例（复用，零重复加载）")

func test_lru_eviction() -> void:
	PortraitCacheManager.set_cap(2)
	var a := PortraitCacheManager.get_portrait(T1)
	var b := PortraitCacheManager.get_portrait(T2)
	expect(a != null and b != null, "前两张应加载成功")
	expect_eq(PortraitCacheManager.get_cache_size(), 2, "容量内应有 2 条")
	# 访问 T1 使其成为最近使用，再加载 T3 触发回收最久未用者（T2）
	PortraitCacheManager.get_portrait(T1)
	var c := PortraitCacheManager.get_portrait(T3)
	expect(c != null, "第三张应加载成功")
	expect_eq(PortraitCacheManager.get_cache_size(), 2, "超出上限应回收，保持 2 条")
	expect(not PortraitCacheManager.has_portrait(T2), "最久未用的 T2 应被 LRU 回收")
	expect(PortraitCacheManager.has_portrait(T1), "最近使用的 T1 应保留")
	expect(PortraitCacheManager.has_portrait(T3), "新加载的 T3 应保留")

func test_preload_warms_cache() -> void:
	expect(not PortraitCacheManager.has_portrait(T1), "预热前应不在缓存")
	PortraitCacheManager.preload_portrait(T1)
	expect(PortraitCacheManager.has_portrait(T1), "预热后应入缓存")
	var a := PortraitCacheManager.get_portrait(T1)
	var b := PortraitCacheManager.get_portrait(T1)
	expect(a == b, "预热后取用应复用同一实例")

func test_release_and_clear() -> void:
	PortraitCacheManager.get_portrait(T1)
	expect(PortraitCacheManager.has_portrait(T1), "加载后应在缓存")
	PortraitCacheManager.release_portrait(T1)
	expect(not PortraitCacheManager.has_portrait(T1), "release 后应从缓存移除")
	PortraitCacheManager.get_portrait(T1)
	PortraitCacheManager.get_portrait(T2)
	PortraitCacheManager.clear()
	expect_eq(PortraitCacheManager.get_cache_size(), 0, "clear 后缓存应为空")
