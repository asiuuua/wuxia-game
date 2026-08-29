# scenes/ui/icon_registry.gd
# 图标解析引擎（UI 窗口主权 · 美术接入预留接口）
#
# 设计目标：让美术（美工）后期只丢图标文件、不碰代码就能替换/新增所有图标。
# 任何需要图标的地方都只调用 IconRegistry.get_icon(<id>)，绝不在代码里写死
# load("res://...png")。资源路径全部集中在 resources/icons/ 下，由本文件按 id 解析。
#
# 用法（三步，美术零代码）：
#   1) 美术把图标丢进 resources/icons/<分类>/<名字>.<png|webp|svg|jpg|avif>
#      例如 resources/icons/skills/fire_sword.png
#   2) 在数据配置里用字符串引用它："icon": "skills/fire_sword"（不含扩展名）
#   3) 代码里：texture = UIManager.get_icon("skills/fire_sword")  或
#               texture = preload("res://scenes/ui/icon_registry.gd").get_icon("skills/fire_sword")
#
# 找不到图标时返回统一的占位图（品红色棋盘），既不崩溃也能一眼看出"缺图标"。
#
# 注意：本文件是纯工具脚本（无 class_name、无 Node），通过 preload 调用，
#       其它窗口可"使用"但不可"修改"（图标解析属 UI 窗口主权）。

# 图标根目录（美术只动这里）
const ICON_ROOT := "res://resources/icons"
# 支持的图标扩展名（按优先级尝试）
const EXT_ORDER := ["png", "webp", "svg", "jpg", "avif"]

# 解析缓存：id -> Texture2D（命中占位也缓存，避免每帧重复探测磁盘）
static var _cache: Dictionary = {}
# 占位图缓存（单例，全工程共用一个"缺图标"提示）
static var _placeholder_cache: Texture2D = null

## 按 id 取图标纹理。id 形如 "skills/fire_sword"（不含扩展名，可带子目录）。
## 找不到返回占位图，绝不返回 null（防止运行期 .texture = null 崩溃）。
static func get_icon(icon_id: String) -> Texture2D:
	if icon_id == null or icon_id.strip_edges() == "":
		return _placeholder()
	if _cache.has(icon_id):
		return _cache[icon_id]
	var tex := _load_first_match(icon_id)
	if tex != null:
		_cache[icon_id] = tex
	else:
		_cache[icon_id] = _placeholder()
	return _cache[icon_id]

## 是否存在某个图标文件（供 UI 判断是否要画图标框）
static func has_icon(icon_id: String) -> bool:
	if icon_id == null or icon_id.strip_edges() == "":
		return false
	if _cache.has(icon_id):
		return _cache[icon_id] != _placeholder()
	return _load_first_match(icon_id) != null

# 按 EXT_ORDER 依次探测 res://resources/icons/<id>.<ext>
static func _load_first_match(icon_id: String) -> Texture2D:
	var safe_id := icon_id.strip_edges()
	for ext in EXT_ORDER:
		var path := "%s/%s.%s" % [ICON_ROOT, safe_id, ext]
		if ResourceLoader.exists(path):
			var tex := load(path) as Texture2D
			if tex != null:
				return tex
	return null

## 统一的"缺图标"占位图（品红色棋盘，Godot 原生 PlaceholderTexture2D）
static func _placeholder() -> Texture2D:
	if _placeholder_cache == null:
		var ph := PlaceholderTexture2D.new()
		ph.size = Vector2(64, 64)
		_placeholder_cache = ph
	return _placeholder_cache
