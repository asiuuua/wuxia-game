# core/portrait_cache_manager.gd
# 立绘 LRU 缓存管理器（工业化扩容 P2 · 纯静态工具，无 Node / 无新 Autoload）
#
# 解决：3000+ 立绘按需取用时「重复加载 / 内存溢出 / 纹理不复用」三害。
#   - 同步取用 get_portrait(path)：命中缓存 O(1) 直返；未命中同步加载并写入（保持现有 UI 同步渲染链路不变）
#   - 预热 preload_portrait(path)：对话开场先把主角/当前 NPC 立绘入缓存，避免首帧卡顿（"双立绘优化"）
#   - LRU 上限可配（默认 50，set_cap 调整），超出回收最近最少使用，内存有界
#   - 纹理复用：同一 path 只持有一份 Texture2D，所有 TextureRect 共享引用（引用计数归 Godot 资源管理）
#
# 设计对齐 icon_registry.gd：纯工具脚本 + class_name 全局调用，不注册 Autoload、不碰共享地基。

class_name PortraitCacheManager

const DEFAULT_CAP: int = 50

# path -> Texture2D（同一 path 全局唯一一份）
static var _cache: Dictionary = {}
# 访问顺序，末尾 = 最近使用（LRU 淘汰取头部）
static var _lru: Array[String] = []
# LRU 上限（运行时可 set_cap 调整）
static var _cap: int = DEFAULT_CAP


## 调整 LRU 上限（运行时配置用）。n<=0 忽略。若新上限小于当前缓存量，立即回收最久未用。
static func set_cap(n: int) -> void:
	if n <= 0:
		return
	_cap = n
	while _lru.size() > _cap:
		_evict_oldest()


## 同步取立绘（UI 主路径）。命中缓存直返；缺失则加载入缓存；path 空/不存在/加载失败返回 null（调用方按原逻辑降级）。
static func get_portrait(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	if _cache.has(path):
		_touch(path)
		return _cache[path]
	var tex := load(path) as Texture2D
	if tex == null:
		return null
	_insert(path, tex)
	return tex


## 预热：确保 path 已入缓存（缺失则同步加载）。用于对话开场预热主角/当前 NPC 立绘，避免首帧卡顿。
static func preload_portrait(path: String) -> void:
	if path == "" or not ResourceLoader.exists(path):
		return
	if _cache.has(path):
		_touch(path)
		return
	var tex := load(path) as Texture2D
	if tex != null:
		_insert(path, tex)


## 主动释放某立绘（对话结束/立绘不再需要时调用，进一步控内存）。
static func release_portrait(path: String) -> void:
	if _cache.has(path):
		_cache.erase(path)
		var idx: int = _lru.find(path)
		if idx >= 0:
			_lru.remove_at(idx)


## 清空全部缓存（大场景切换时由全局资源管理器调用）。
static func clear() -> void:
	_cache.clear()
	_lru.clear()


## 当前缓存条目数（测试/诊断用）。
static func get_cache_size() -> int:
	return _cache.size()


## 某立绘是否已在缓存（测试/诊断用）。
static func has_portrait(path: String) -> bool:
	return _cache.has(path)


static func _touch(path: String) -> void:
	var idx: int = _lru.find(path)
	if idx >= 0:
		_lru.remove_at(idx)
	_lru.append(path)


static func _insert(path: String, tex: Texture2D) -> void:
	_cache[path] = tex
	_lru.append(path)
	# LRU 回收：超出上限时释放最久未用
	while _lru.size() > _cap:
		_evict_oldest()


static func _evict_oldest() -> void:
	if _lru.is_empty():
		return
	var oldest: String = _lru[0]
	_lru.remove_at(0)
	_cache.erase(oldest)
