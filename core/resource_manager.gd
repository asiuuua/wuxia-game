# core/resource_manager.gd
# 全局资源管理器（工业化扩容 P6 · 纯静态工具，无新 Autoload）
#
# 统一收口"重资源"（CG 视频/图片/语音/大纹理）的获取与回收，解决工业化体量下的三类痼疾：
#   1) 重复加载：同一 path 全局只持有一份（引用计数，多消费者共享）。
#   2) 内存无界：分级回收（L1 常驻 / L2 温存 TTL / L3 冷回收）+ 硬上限，内存有界。
#   3) 阻塞加载：acquire_async 走后台线程（StreamingMediaLoader），完成回调不卡帧。
#
# 设计：对齐 PortraitCacheManager / CombatEntityPool，纯工具 + class_name 全局调用。
#   异步完成由 SceneTree.process_frame 信号驱动（_ensure_pump 连接一次），不注册 Autoload。
#   大场景切换时调用 reclaim_all() 集中回收（含立绘缓存、战斗实体池的统一释放口）。

class_name ResourceManager

# ---- 回收分级参数（运行时可配）----
const DEFAULT_CAP: int = 256          # 资源条目硬上限（含已引用）；超限回收最久未用
const DEFAULT_WARM_TTL_MS: int = 5000 # L2 温存时限；超过且引用计数为 0 进入 L3 冷回收
const SWEEP_INTERVAL_MS: int = 1000   # 闲置回收扫描限频

# 条目：{res: Variant, refcount: int, last_used: int}
static var _entries: Dictionary = {}
static var _pending: Dictionary = {}   # path -> {cb: Callable}（异步在途）
static var _cap: int = DEFAULT_CAP
static var _warm_ttl: int = DEFAULT_WARM_TTL_MS
static var _sweep_last: int = 0
static var _pump_connected: bool = false


## 调整硬上限 / 温存时限（运行时配置用）。n<=0 忽略；上限下调立即触发回收。
static func set_cap(n: int) -> void:
	if n <= 0:
		return
	_cap = n
	reclaim_idle()


static func set_warm_ttl(ms: int) -> void:
	if ms <= 0:
		return
	_warm_ttl = ms


## 同步获取（引用计数 +1）。命中已加载直接返回；否则同步加载并缓存。
## 失败返回 null（调用方降级）。
static func acquire_sync(path: String, type_hint: String = "") -> Variant:
	if path == "":
		return null
	if _entries.has(path) and _entries[path].res != null:
		_touch(path)
		return _entries[path].res
	var res: Variant = StreamingMediaLoader.load_blocking(path, type_hint)
	if res == null:
		return null
	_store(path, res, 1)
	return res


## 异步获取（引用计数 +1，后台线程加载，完成后回调 cb(res)）。
## 已加载则立即回调（同帧）；否则入在途表，由 process_frame 泵驱动完成后回调。
## cb 可空（仅缓存，后续 get 取用）。
static func acquire_async(path: String, type_hint: String = "", cb: Callable = Callable()) -> void:
	if path == "":
		return
	# 乐观引用：先占位（refcount+1），加载完成再填 res
	if _entries.has(path):
		_entries[path].refcount += 1
		_touch(path)
	else:
		_entries[path] = {"res": null, "refcount": 1, "last_used": Time.get_ticks_msec()}
	if _entries[path].res != null:
		# 已就绪：立即回调
		var res: Variant = _entries[path].res
		if cb.is_valid():
			cb.call(res)
		return
	_pending[path] = {"cb": cb}
	StreamingMediaLoader.request(path, type_hint)
	_ensure_pump()


## 释放一次引用（引用计数 -1）。归零后进入温存计时，超时/超限回收。
static func release(path: String) -> void:
	_dec_ref(path)


## 取当前资源（已加载返回，否则 null，不触发加载）。
static func get_resource(path: String) -> Variant:
	if _entries.has(path):
		return _entries[path].res
	return null


static func has(path: String) -> bool:
	return _entries.has(path) and _entries[path].res != null


static func get_refcount(path: String) -> int:
	if _entries.has(path):
		return _entries[path].refcount
	return 0


## 分级回收：引用计数 == 0 且（闲置超 TTL 或总量超硬上限）的条目释放。
## 引用计数 > 0（L1 常驻）永不回收。
static func reclaim_idle() -> void:
	var now: int = Time.get_ticks_msec()
	if now - _sweep_last < SWEEP_INTERVAL_MS:
		return
	_sweep_last = now
	var expired: Array[String] = []
	for p in _entries.keys():
		var e: Dictionary = _entries[p]
		if e.refcount > 0:
			continue   # L1 常驻，跳过
		var idle: int = now - int(e.last_used)
		if idle > _warm_ttl:
			expired.append(p)
	# 硬上限：超量回收最久未用（含刚超 TTL 的与未超但最旧的）
	if _entries.size() > _cap:
		var sorted: Array = Array(_entries.keys())
		sorted.sort_custom(func(a: String, b: String) -> bool: return int(_entries[a].last_used) < int(_entries[b].last_used))
		for p in sorted:
			if _entries[p].refcount > 0:
				continue
			if _entries.size() <= _cap:
				break
			expired.append(p)
	for p in expired:
		if _entries.has(p) and _entries[p].refcount == 0:
			_entries.erase(p)


## 全量软回收：释放所有引用计数 == 0 的条目（大场景切换调用）。
## 同时集中调用已落地的其它缓存释放口（立绘 LRU / 战斗实体池），一处管全部回收。
static func reclaim_all() -> void:
	var keys: Array = Array(_entries.keys())
	for p in keys:
		if _entries[p].refcount == 0:
			_entries.erase(p)
	# 集中回收其它已落地缓存（纯追加式对接，不改动它们内部逻辑）
	PortraitCacheManager.clear()
	CombatEntityPool.clear()


## 强制全回收（含引用计数 > 0 的，仅用于彻底重启/切档等极端场景）。
static func force_reclaim_all() -> void:
	_entries.clear()
	_pending.clear()
	PortraitCacheManager.clear()
	CombatEntityPool.clear()


## 诊断：当前条目数 / 在途数 / 已加载数。
static func get_stats() -> Dictionary:
	var loaded: int = 0
	for p in _entries.keys():
		if _entries[p].res != null:
			loaded += 1
	return {"entries": _entries.size(), "loaded": loaded, "pending": _pending.size(), "cap": _cap}


# ============ 内部 ============

static func _store(path: String, res: Variant, refcount: int) -> void:
	_entries[path] = {"res": res, "refcount": refcount, "last_used": Time.get_ticks_msec()}


static func _touch(path: String) -> void:
	if _entries.has(path):
		_entries[path].refcount += 1
		_entries[path].last_used = Time.get_ticks_msec()


static func _dec_ref(path: String) -> void:
	if not _entries.has(path):
		return
	_entries[path].refcount -= 1
	if _entries[path].refcount <= 0:
		_entries[path].refcount = 0
		_entries[path].last_used = Time.get_ticks_msec()


static func _store_loaded(path: String, res: Variant) -> void:
	if _entries.has(path):
		_entries[path].res = res
		_entries[path].last_used = Time.get_ticks_msec()
	else:
		_store(path, res, 0)


## process_frame 泵：驱动异步完成回调 + 限频回收扫描。
static func _on_process_frame() -> void:
	_pump_tick(0.0)


static func _pump_tick(_delta: float) -> void:
	if not _pending.is_empty():
		var paths: Array = Array(_pending.keys())
		for path in paths:
			if not _pending.has(path):
				continue
			var st: int = StreamingMediaLoader.get_status(path)
			if st == StreamingMediaLoader.STATUS_LOADED:
				var res: Variant = StreamingMediaLoader.take(path)
				_store_loaded(path, res)
				var cb: Callable = _pending[path].cb
				_pending.erase(path)
				if cb.is_valid():
					cb.call(res)
			elif st == StreamingMediaLoader.STATUS_FAILED:
				# 加载失败：释放乐观引用，移除在途（不存储资源）
				_pending.erase(path)
				_dec_ref(path)
	reclaim_idle()


## 连接一次 process_frame（供异步泵）。无主循环环境（如纯 --script 校验）安全跳过。
static func _ensure_pump() -> void:
	if _pump_connected:
		return
	var loop = Engine.get_main_loop()
	if loop == null:
		return
	if loop is SceneTree:
		var tree: SceneTree = loop
		if not tree.process_frame.is_connected(_on_process_frame):
			tree.process_frame.connect(_on_process_frame)
	_pump_connected = true


## 测试 / 确定性驱动用：手动泵一次（等价于 process_frame 一帧）。
static func pump() -> void:
	_pump_tick(0.0)


## 复位所有状态（测试用）。
static func reset() -> void:
	_entries.clear()
	_pending.clear()
	_cap = DEFAULT_CAP
	_warm_ttl = DEFAULT_WARM_TTL_MS
	_sweep_last = 0
