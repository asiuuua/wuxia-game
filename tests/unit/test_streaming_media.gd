# tests/unit/test_streaming_media.gd
# P5 流式媒体加载器单测：验证 异步请求/状态/取用、同步便捷取用、空/缺失路径安全降级。
# 不依赖 UI 节点，纯测 core/streaming_media_loader.gd 的静态逻辑。

extends TestBase
class_name TestStreamingMedia

const T1 := "res://assets/characters/player.png"
const T2 := "res://assets/characters/village_chief.png"


func test_load_blocking_returns_resource() -> void:
	var res: Variant = StreamingMediaLoader.load_blocking(T1)
	expect(res != null, "同步便捷取用应返回非 null 资源（%s）" % T1)


func test_empty_path_safe() -> void:
	expect(StreamingMediaLoader.take("") == null, "空路径 take 应返回 null")
	expect(not StreamingMediaLoader.is_ready(""), "空路径 is_ready 应为 false")
	StreamingMediaLoader.request("")   # 不应崩溃
	expect(StreamingMediaLoader.requested_count() >= 0, "request(\"\") 不应使内部簿记异常")


func test_async_request_then_take() -> void:
	StreamingMediaLoader.request(T2)
	var guard := 0
	while not StreamingMediaLoader.is_ready(T2) and not StreamingMediaLoader.is_failed(T2):
		OS.delay_msec(5)
		guard += 1
		if guard > 200:
			break
	expect(StreamingMediaLoader.is_ready(T2), "异步请求后应在限时内进入 LOADED 状态")
	var res: Variant = StreamingMediaLoader.take(T2)
	expect(res != null, "is_ready 后 take 应返回非 null 资源")


func test_status_is_valid_enum() -> void:
	StreamingMediaLoader.request(T1)
	var st: int = StreamingMediaLoader.get_status(T1)
	# 四个合法状态之一
	var ok := (st == StreamingMediaLoader.STATUS_INVALID
		or st == StreamingMediaLoader.STATUS_IN_PROGRESS
		or st == StreamingMediaLoader.STATUS_FAILED
		or st == StreamingMediaLoader.STATUS_LOADED)
	expect(ok, "get_status 应返回合法枚举值（实际 %d）" % st)
