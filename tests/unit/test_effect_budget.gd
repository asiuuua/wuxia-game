# tests/unit/test_effect_budget.gd
# 7.3.5 特效预算：飘字按「单位」独立池 + 超限入队稍后播放（梦幻式），避免无限新建 Label / 直接丢弃数字。
# 逻辑层无需场景树即可验证。
extends TestBase

func test_floating_text_pool_capped() -> void:
	var e := BattleEntity.new()
	e.setup("u", true, "U", 100, 50, null)
	# 连续取 MAX_POPS*2 个标签并全部标记为占用，池应封顶 MAX_POPS（绝不限量新建）
	for i in range(e.MAX_POPS * 2):
		var l = e._acquire_pop()
		expect(l != null, "acquire 应始终返回有效标签（第 %d 次）" % i)
		l.visible = true
	expect(e._pop_pool.size() == e.MAX_POPS, "飘字池应受 MAX_POPS 上限约束，实际:%d" % e._pop_pool.size())
	# 收回一个空闲后再取，应复用而非新建（池大小不变）
	var before: int = e._pop_pool.size()
	var recycled = e._acquire_pop()
	expect(recycled != null, "回收路径应返回有效标签")
	expect(e._pop_pool.size() == before, "回收路径不应增大池（%d -> %d）" % [before, e._pop_pool.size()])
	e.free()

func test_queue_when_full_no_discard() -> void:
	var e := BattleEntity.new()
	e.setup("u", true, "U", 100, 50, null)
	# 填满池且全部处于播放中（无空闲 Label）
	for i in range(e.MAX_POPS):
		var l = e._acquire_pop()
		l.visible = true
		e._pop_active.append(l)
	# 继续 pop_text：超限时不应新建更多 Label，而是进入待播队列（绝不丢弃数字）
	for i in range(5):
		e.pop_text("-%d" % i, Color.RED)
	expect(e._pop_pool.size() == e.MAX_POPS, "超限后池大小不应超过 MAX_POPS，实际:%d" % e._pop_pool.size())
	expect(e._pop_pending.size() == 5, "超限的 5 条飘字应进入待播队列，实际:%d" % e._pop_pending.size())
	# 模拟一条飘字播放结束 -> 应出队播放一条，数字不丢
	e._release_pop(e._pop_active[0])
	expect(e._pop_pending.size() == 4, "释放一条后队列应减少 1，实际:%d" % e._pop_pending.size())
	expect(e._pop_active.size() == e.MAX_POPS, "释放即出队补充后活跃数仍应为 MAX_POPS，实际:%d" % e._pop_active.size())
	e.free()
