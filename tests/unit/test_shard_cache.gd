# tests/unit/test_shard_cache.gd
# ShardCache 单测（05 图 CA-1~CA-4 / CONTENT-RUNTIME v1.2.0）：
# TTL 逐出 · pin 引用计数禁逐出（CO-R11）· 超限 LRU · 逐出回调 · 防抖 · erase 拒绝。
# 假时钟注入：零真实时间依赖，零真实磁盘。

extends TestBase
class_name TestShardCache

var _now_ms: int = 0

func _fake_clock() -> int:
	return _now_ms

func _make_cache(max_entries: int = 256, ttl_ms: int = 2000) -> ShardCache:
	_now_ms = 0
	return ShardCache.new(max_entries, ttl_ms, Callable(self, "_fake_clock"))

# === 基础存取（CA-3：键=内容 ID）===

func test_put_get_has_erase() -> void:
	var c := _make_cache()
	c.put("d_a", {"x": 1})
	expect(c.has("d_a"), "put 后 has 为真")
	expect_eq(c.size(), 1, "size 应为 1")
	var got: Variant = c.fetch("d_a")
	expect(got is Dictionary and int(got.get("x", 0)) == 1, "get 应返回原 payload")
	c.erase("d_a")
	expect(not c.has("d_a"), "erase 后 has 为假")
	expect(c.fetch("__none__") == null, "未命中 get 应返回 null")

# === TTL 逐出（CA-2）===

func test_ttl_eviction() -> void:
	var c := _make_cache(4, 100)
	c.put("d_a", 1)
	_now_ms = 50
	c.sweep(true)
	expect(c.has("d_a"), "TTL 内不逐出")
	_now_ms = 101
	var evicted: Array[String] = c.sweep(true)
	expect(not c.has("d_a"), "超 TTL 未 pin 分片应逐出")
	expect(evicted.has("d_a"), "sweep 应返回逐出列表")

# === pin 引用计数（CO-R11：pin 中禁逐出）===

func test_pin_prevents_eviction() -> void:
	var c := _make_cache(4, 100)
	c.put("d_a", 1)
	c.put("d_b", 2)
	c.pin("d_a")
	c.pin("d_a")   # 引用计数 2
	_now_ms = 101
	c.sweep(true)
	expect(c.has("d_a"), "pin 中禁逐出（CO-R11）")
	expect(not c.has("d_b"), "未 pin 分片正常逐出")
	c.unpin("d_a")
	_now_ms = 202
	c.sweep(true)
	expect(c.has("d_a"), "计数 2 解钉 1 次仍 pin")
	c.unpin("d_a")
	_now_ms = 303
	c.sweep(true)
	expect(not c.has("d_a"), "计数归零后可逐出")

func test_erase_rejected_when_pinned() -> void:
	var c := _make_cache()
	c.put("d_a", 1)
	c.pin("d_a")
	expect(not c.erase("d_a"), "pin 中 erase 应拒绝（与原 unload_dialog 语义一致）")
	c.unpin("d_a")
	expect(c.erase("d_a"), "解钉后 erase 应成功")

# === 超限 LRU 逐出 ===

func test_capacity_lru_eviction() -> void:
	var c := _make_cache(2, 100000)
	c.put("d_a", 1)      # t=0 最旧
	_now_ms = 10
	c.put("d_b", 2)
	_now_ms = 20
	c.put("d_c", 3)      # 超限
	c.sweep(true)
	expect(not c.has("d_a"), "超限应逐出最久未访问者")
	expect(c.has("d_b") and c.has("d_c"), "较新者保留")

func test_capacity_lru_skips_pinned() -> void:
	var c := _make_cache(2, 100000)
	c.put("d_a", 1)      # 最旧但 pin 中
	c.put("d_b", 2)
	c.pin("d_a")
	_now_ms = 10
	c.put("d_c", 3)
	c.sweep(true)
	expect(c.has("d_a"), "pin 中即使最旧也不逐出")
	expect(not c.has("d_b"), "未 pin 的次旧被逐出")
	expect(c.has("d_c"), "最新保留")

# === 逐出回调（CA-2：Owner 注册）===

func test_evict_callback_fires() -> void:
	var c := _make_cache(1, 100000)
	var seen: Array = []
	c.set_evict_callback(func(id: String) -> void: seen.append(id))
	c.put("d_a", 1)
	_now_ms = 10
	c.put("d_b", 2)
	c.sweep(true)
	expect(seen.has("d_a"), "逐出应触发 Owner 回调")
	c.erase("d_b")
	expect(seen.has("d_b"), "主动擦除同样触发回调")

# === 清扫防抖（沿用现对话分片 250ms 语义）===

func test_sweep_debounce() -> void:
	var c := _make_cache(4, 10)
	c.put("d_a", 1)
	_now_ms = 50
	c.sweep()
	_now_ms = 60   # TTL 已过但距上次清扫 10ms < 250ms 防抖窗口
	c.sweep()
	expect(c.has("d_a"), "防抖窗口内 sweep 应跳过")
	_now_ms = 301
	c.sweep()
	expect(not c.has("d_a"), "防抖窗口过后正常清扫")
