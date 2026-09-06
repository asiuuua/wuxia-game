# application/content/shard_cache.gd
# Content Pipeline · Cache 冻结项（05 图 CA-1~CA-4 / CONTENT-RUNTIME v1.2.0）
# 契约冻结（CA-2）：max_entries=256 · ttl_ms=2000 · pin/unpin 引用计数（>0 禁逐出，CO-R11）
# 逐出回调由 Owner 注册；缓存键 = 内容 ID（CA-3，禁显示名/路径/中文串）。
# 现对话分片 LRU（ConfigManager _dialog_cache 族）的通用化收编，行为保真。

class_name ShardCache
extends RefCounted

const DEFAULT_MAX_ENTRIES: int = 256   # CA-2 冻结参数
const DEFAULT_TTL_MS: int = 2000       # CA-2 冻结参数
const SWEEP_DEBOUNCE_MS: int = 250     # 清扫防抖（沿用现对话分片语义）

var max_entries: int
var ttl_ms: int

var _clock: Callable                    # 时间源：默认引擎毫秒；测试注入假时钟
var _entries: Dictionary = {}           # id -> payload（CA-3 键=内容 ID）
var _pinned: Dictionary = {}            # id -> 引用计数（CO-R11：>0 禁逐出）
var _last_access: Dictionary = {}       # id -> 最后访问毫秒
var _last_sweep: int = 0
var _evict_callback: Callable           # CA-2 逐出回调（Owner 注册）：func(id: String)

func _init(p_max_entries: int = DEFAULT_MAX_ENTRIES, p_ttl_ms: int = DEFAULT_TTL_MS, p_clock: Callable = Callable()) -> void:
	max_entries = maxi(p_max_entries, 1)
	ttl_ms = maxi(p_ttl_ms, 0)
	_clock = p_clock

func _now() -> int:
	if _clock.is_null():
		return Time.get_ticks_msec()
	return int(_clock.call())

## CA-2：逐出回调由 Owner 注册（逐出时回调 func(id)）
func set_evict_callback(cb: Callable) -> void:
	_evict_callback = cb

func has(id: String) -> bool:
	return _entries.has(id)

func size() -> int:
	return _entries.size()

## 命中返回 payload 并刷新访问时间；未命中返回 null
## （命名 fetch：避开 Object.get(property) 原生方法签名冲突）
func fetch(id: String) -> Variant:
	if not _entries.has(id):
		return null
	_last_access[id] = _now()
	return _entries[id]

## 放入（键=内容 ID，永不复用；dev reload 整包重载路径允许覆盖，CA-4）
func put(id: String, payload: Variant) -> void:
	_entries[id] = payload
	_last_access[id] = _now()

## 主动擦除：pin 中（引用计数 >0）拒绝并返回 false（与现 unload_dialog 语义一致）
func erase(id: String) -> bool:
	if int(_pinned.get(id, 0)) > 0:
		return false
	return _drop(id)

## 钉住：进行中的对话/交易禁逐出（引用计数）
func pin(id: String) -> void:
	_pinned[id] = int(_pinned.get(id, 0)) + 1

## 解钉
func unpin(id: String) -> void:
	var n: int = int(_pinned.get(id, 0)) - 1
	if n <= 0:
		_pinned.erase(id)
	else:
		_pinned[id] = n

func pin_count(id: String) -> int:
	return int(_pinned.get(id, 0))

## 闲置回收：超 TTL 或超上限的未 pin 分片逐出（返回被逐出的 id 列表）
## 带防抖：距上次清扫不足 SWEEP_DEBOUNCE_MS 时直接跳过（force=true 强制）
func sweep(force: bool = false) -> Array[String]:
	var now: int = _now()
	if not force and now - _last_sweep < SWEEP_DEBOUNCE_MS:
		return []
	_last_sweep = now
	var evicted: Array[String] = []
	# 1) TTL 过期
	for id in _entries.keys():
		if int(_pinned.get(id, 0)) > 0:
			continue
		var last: int = int(_last_access.get(id, 0))
		if now - last > ttl_ms:
			evicted.append(id)
	# 2) 超上限补逐（LRU）：补足到 max_entries 为止，pin 永不逐出（CO-R11）
	#    用计数补逐而非循环内查 size——删除统一发生在末尾，循环内 size 不缩水
	var overflow: int = _entries.size() - max_entries - evicted.size()
	if overflow > 0:
		var sorted: Array = Array(_entries.keys())
		sorted.sort_custom(func(a: String, b: String) -> bool:
			return int(_last_access.get(a, 0)) < int(_last_access.get(b, 0)))
		for id in sorted:
			if overflow <= 0:
				break
			if int(_pinned.get(id, 0)) > 0:
				continue
			if evicted.has(id):
				continue
			evicted.append(id)
			overflow -= 1
	for id in evicted:
		_drop(id)
	return evicted

# 内部：真实移除 + 触发 Owner 逐出回调
func _drop(id: String) -> bool:
	if not _entries.erase(id):
		return false
	_last_access.erase(id)
	if not _evict_callback.is_null():
		_evict_callback.call(id)
	return true
