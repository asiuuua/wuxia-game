# core/streaming_media_loader.gd
# 流式媒体加载器（工业化扩容 P5 · 纯静态工具，无 Node / 无新 Autoload）
#
# 解决：CG 视频 / 图片 / 语音等"重资源"用 load() 同步加载会卡主线程（百万字大项目里
#       单段 CG 视频可能数十 MB，同步 load 直接掉帧甚至卡死开场）。
#   - request(path)：非阻塞发起后台线程加载（立即返回，不卡帧）。
#   - get_status(path)：轮询加载状态（INVALID / IN_PROGRESS / FAILED / LOADED）。
#   - take(path)：加载完成后取资源（仅 LOADED 时返回非 null）。
#   - load_blocking(path)：便捷同步取用（内部仍走 threaded 接口，供测试/简单调用）。
#   - cancel(path)：放弃一次未完成的请求（置为已加载态由调用方忽略即可；本接口仅清内部簿记）。
#
# 设计：对齐 PortraitCacheManager / CombatEntityPool，纯工具脚本 + class_name 全局调用，
#       不注册 Autoload、不碰共享地基。真正的"每帧轮询"由消费者（CelebrationOverlay /
#       AudioManager 的 _process，或 ResourceManager 的 process_frame 泵）完成。

class_name StreamingMediaLoader

const STATUS_INVALID := ResourceLoader.THREAD_LOAD_INVALID_RESOURCE
const STATUS_IN_PROGRESS := ResourceLoader.THREAD_LOAD_IN_PROGRESS
const STATUS_FAILED := ResourceLoader.THREAD_LOAD_FAILED
const STATUS_LOADED := ResourceLoader.THREAD_LOAD_LOADED

# 内部簿记：记录我们主动发起过请求的路径（避免对从未请求过的路径误报）
static var _requested: Dictionary = {}   # path -> true


## 非阻塞发起后台加载。path 空 / 已加载 / 已在进行中则忽略。
## type_hint 一般留空让 Godot 自动推断；个别类型（如明确 AudioStream）可传 "".
static func request(path: String, type_hint: String = "", use_sub_threads: bool = true) -> void:
	if path == "":
		return
	if _requested.has(path):
		return
	# 直接调 ResourceLoader 后台线程加载；立即返回不阻塞。
	ResourceLoader.load_threaded_request(path, type_hint, use_sub_threads)
	_requested[path] = true


## 当前加载状态（返回上面四个 STATUS_* 常量之一）。
static func get_status(path: String) -> int:
	return ResourceLoader.load_threaded_get_status(path)


## 是否已完成加载（可直接 take）。
static func is_ready(path: String) -> bool:
	return ResourceLoader.load_threaded_get_status(path) == STATUS_LOADED


## 是否加载失败（调用方应降级处理）。
static func is_failed(path: String) -> bool:
	return ResourceLoader.load_threaded_get_status(path) == STATUS_FAILED


## 取已加载资源。仅当 is_ready 为真时返回非 null；否则返回 null（调用方不应在就绪前取）。
static func take(path: String) -> Variant:
	if ResourceLoader.load_threaded_get_status(path) == STATUS_LOADED:
		return ResourceLoader.load_threaded_get(path)
	return null


## 便捷同步取用：内部发起 threaded 请求并阻塞等待完成（仍走 threaded 接口，语义清晰）。
## 适用于测试或确定要同步拿资源的小场景；重资源请走 request + 轮询。
static func load_blocking(path: String, type_hint: String = "") -> Variant:
	if path == "":
		return null
	ResourceLoader.load_threaded_request(path, type_hint, true)
	return ResourceLoader.load_threaded_get(path)


## 放弃一次请求（仅清内部簿记；已加载的资源由 Godot 资源系统自行管理）。
static func cancel(path: String) -> void:
	_requested.erase(path)


## 诊断：当前已知已发起请求的路径数。
static func requested_count() -> int:
	return _requested.size()
