# tests/unit/test_entity_id_allocator.gd
# 06 图批1 ①：EntityId 分配器契约（09 图 ID-1 单一分配器 / ID-2 水位策略 / ID-3 禁再发明）。
# 覆盖：单调发号、domain 隔离、serial 零填充、EntityId 集成、bootstrap max 推导、
#       hint 上界安全垫、水位绝不回拨（ID 永不复用红线）。

extends TestBase


func test_next_int_monotonic_per_domain() -> void:
	var alloc := EntityIdAllocator.new()
	expect_eq(alloc.next_int(&"ITEM"), 1, "首号=1")
	expect_eq(alloc.next_int(&"ITEM"), 2, "单调自增")
	expect_eq(alloc.next_int(&"ITEM"), 3, "继续单调")
	expect_eq(alloc.next_int(&"NPC"), 1, "域隔离：NPC 首号独立=1")
	expect_eq(alloc.next_int(&"ITEM"), 4, "域隔离：ITEM 不受 NPC 影响")


func test_next_serial_zero_padded_and_entity_id() -> void:
	var alloc := EntityIdAllocator.new()
	expect(alloc.next_serial(&"NPC") == "000001", "serial 零填充 6 位")
	var eid := alloc.next_entity_id(&"QUEST")
	expect(eid != null, "next_entity_id 返回 EntityId")
	expect(str(eid) == "QUEST_000001", "EntityId 形态=域_serial（QUEST 域首号，实际 %s）" % str(eid))
	var eid2 := alloc.next_entity_id(&"QUEST")
	expect(str(eid2) == "QUEST_000002", "同域连发单调（实际 %s）" % str(eid2))
	var parsed := EntityId.parse(str(eid))
	expect(parsed != null and parsed.equals(eid), "parse 往返一致")


func test_bootstrap_derives_max_plus_one() -> void:
	var alloc := EntityIdAllocator.new()
	alloc.bootstrap(&"ITEM", [3, 7, 2], 0)
	expect_eq(alloc.next_int(&"ITEM"), 8, "ID-2：水位=max(现存)+1=8")


func test_bootstrap_hint_raises_watermark() -> void:
	var alloc := EntityIdAllocator.new()
	# 现存最高 serial=5，但旧档 next_iid=20（已消费/已装备走的号不在现存面内）
	alloc.bootstrap(&"ITEM", [1, 5], 20)
	expect_eq(alloc.next_int(&"ITEM"), 20, "hint 上界生效：下一号=20")


func test_bootstrap_never_rolls_back() -> void:
	var alloc := EntityIdAllocator.new()
	alloc.bootstrap(&"ITEM", [1, 2, 3], 0)
	expect_eq(alloc.next_int(&"ITEM"), 4, "首发=4")
	# 回滚档/旧档灌入更小的数据面：水位必须钉在原地（永不复用）
	alloc.bootstrap(&"ITEM", [1, 2], 3)
	expect_eq(alloc.next_int(&"ITEM"), 5, "水位绝不回拨：仍单调")


func test_reset_domain_and_watermark_readonly() -> void:
	var alloc := EntityIdAllocator.new()
	alloc.next_int(&"ITEM")
	alloc.next_int(&"NPC")
	expect_eq(alloc.watermark(&"ITEM"), 2, "watermark 观察=下一待发号")
	alloc.reset_domain(&"ITEM")
	expect_eq(alloc.watermark(&"ITEM"), 1, "单域复位后回 1")
	expect_eq(alloc.watermark(&"NPC"), 2, "他域不受复位影响")
	alloc.reset_all()
	expect_eq(alloc.watermark(&"NPC"), 1, "全域复位")
