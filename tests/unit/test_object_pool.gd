# tests/unit/test_object_pool.gd
# 全局对象池单测：验证 ① 复用空闲节点（池化生效）② 达 max 返回 null（绝不偷活跃节点）
# ③ release 主动从父节点摘下（不持有父引用，规避场景销毁悬空）④ clear 释放全部。
# 注意：计数用「数组（引用类型）」而非整型变量——GDScript 4.x lambda 对值类型按值捕获，
#       闭包内 made += 1 无法回写外层，会恒为 0；用 created.append(...) 原地改引用类型则稳定。
extends TestBase

func test_acquire_reuses_released_node() -> void:
	ObjectPool.clear()
	var created: Array = []
	var factory := func() -> Node:
		var node := Node2D.new()
		created.append(node)
		return node
	var a := ObjectPool.acquire("t_a", factory)
	var b := ObjectPool.acquire("t_a", factory)
	expect(a != null and b != null, "前两次 acquire 应拿到节点")
	expect(a != b, "前两次应新建不同节点")
	expect(created.size() == 2, "应新建 2 个（实际 %d）" % created.size())
	ObjectPool.release("t_a", a)
	var c := ObjectPool.acquire("t_a", factory)
	expect(c == a, "release 后应复用同一节点（池化生效）")
	expect(created.size() == 2, "复用不应再新建（实际 %d）" % created.size())
	ObjectPool.clear()

func test_acquire_respects_max_and_never_steals_active() -> void:
	ObjectPool.clear()
	ObjectPool.set_max("t_b", 2)
	var factory := func() -> Node: return Node2D.new()
	var a := ObjectPool.acquire("t_b", factory)
	var b := ObjectPool.acquire("t_b", factory)
	var c := ObjectPool.acquire("t_b", factory)   # 超 max
	expect(a != null and b != null, "前两个应正常拿到")
	expect(c == null, "达 max 后应返回 null（绝不偷活跃节点 → 无视觉串台）")
	expect(ObjectPool.stats("t_b").active == 2, "活跃数应为 2（实际 %d）" % ObjectPool.stats("t_b").active)
	ObjectPool.clear()

func test_release_detaches_from_parent() -> void:
	ObjectPool.clear()
	var parent := Node2D.new()
	var n := ObjectPool.acquire("t_c", func() -> Node: return Node2D.new())
	parent.add_child(n)
	expect(n.get_parent() == parent, "使用中应挂在父节点上")
	ObjectPool.release("t_c", n)
	expect(n.get_parent() == null, "release 应从父节点摘下（避免悬空引用）")
	parent.free()
	ObjectPool.clear()

func test_clear_frees_all() -> void:
	ObjectPool.clear()
	ObjectPool.set_max("t_d", 50)
	var created: Array = []
	# 先连续新建 10 个不同节点（循环内不释放，确保全部新建而非复用）
	for i in range(10):
		var n := ObjectPool.acquire("t_d", func():
			var node := Node2D.new()
			created.append(node)
			return node)
		expect(n != null, "第 %d 次 acquire 应拿到节点" % i)
	expect(created.size() == 10, "应新建 10 个不同节点（实际 %d）" % created.size())
	expect(ObjectPool.stats("t_d").active == 10, "活跃数应为 10（实际 %d）" % ObjectPool.stats("t_d").active)
	# 全部释放 → 空闲桶应恰好 10
	for n in created:
		ObjectPool.release("t_d", n)
	expect(ObjectPool.stats("t_d").free == 10, "10 个节点应全在空闲桶（实际 %d）" % ObjectPool.stats("t_d").free)
	ObjectPool.clear()
	expect(ObjectPool.stats("t_d").free == 0, "clear 后空闲桶应清空")
