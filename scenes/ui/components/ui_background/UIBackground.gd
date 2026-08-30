# scenes/ui/components/ui_background/UIBackground.gd
# 界面动态背景组件（2026-08-29 抽出 MainMenu / SaveLoadScreen 的重复背景代码）
#
# 解决核心问题：背景图宽高比与视口不一致时，STRETCH_KEEP_ASPECT 等比缩放会露出空隙，
# 空隙显示项目清屏色 → 观感上就是「黑边」。本组件在图片**下层**铺一张同色系竖向渐变垫底，
# 空隙露出的是渐变色而非黑色，与图片边缘自然融合。零裁剪、零拉伸。
#
# 层次（由下至上）：
#   ① 渐变垫底（GradientTexture2D，色标取自主菜单背景图左右侧边竖向采样）
#   ② 背景图（STRETCH_KEEP_ASPECT，等比不裁切）
#   ③ 压暗层（保证菜单文字可读）
#   ④ 落叶粒子（氛围）

extends Control
class_name UIBackground

const UIPalette = preload("res://core/constants/ui_theme.gd")

## 背景图路径；留空或文件不存在则只显示渐变垫底（不报错、不崩）
@export var bg_image_path: String = "res://assets/ui/main_menu_bg.jpg"
## 压暗层不透明度（0=不压暗，1=全黑）
@export var scrim_alpha: float = 0.55
## 是否启用落叶粒子
@export var leaves_enabled: bool = true
## 可选：布局配置文件路径（JSON）。留空则使用下方默认行为（向后兼容）。
## 文件可覆盖 stretch_mode / scrim_alpha / edge_auto / leaves_enabled / edge_color。
## 由「工作室专业调教」工具的「登录界面」标签页生成（data/configs/ui/login_bg_layout.json）。
@export var layout_config_path: String = ""

# 运行时解析出的布局参数（_ready 时由 layout_config_path 覆盖）
var _stretch_mode: int = TextureRect.STRETCH_KEEP_ASPECT
var _edge_auto: bool = false
var _grad_stops: Array = GRAD_STOPS  # 默认用硬编码绿渐变；edge_auto 时改为采样图边色

# 渐变色标：取自主菜单背景图左右各 60px 的竖向 5 段平均色（2026-08-29 采样）
# 图片换成别的风格时，重采样后改这里即可，不必动逻辑
const GRAD_STOPS: Array = [
	[0.00, 194, 195, 181],
	[0.25, 193, 193, 170],
	[0.50, 186, 190, 170],
	[0.75, 178, 179, 163],
	[1.00, 173, 178, 165],
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_load_layout_config()
	_build_gradient_base()
	_build_image()
	_build_scrim()
	if leaves_enabled:
		add_child(_build_leaves())

## 读取 layout_config_path 指向的 JSON，覆盖运行时布局参数。
## 解析失败 / 文件缺失则静默保持默认（向后兼容旧调用方）。
func _load_layout_config() -> void:
	if layout_config_path == "" or not ResourceLoader.exists(layout_config_path):
		return
	var cfg: Dictionary = _load_json(layout_config_path)
	if cfg == null:
		return
	var sm: String = cfg.get("stretch_mode", "")
	if sm != "":
		_stretch_mode = _stretch_from_string(sm)
	if cfg.has("scrim_alpha"):
		var sa = cfg["scrim_alpha"]
		if typeof(sa) == TYPE_FLOAT or typeof(sa) == TYPE_INT:
			scrim_alpha = float(sa)
	if cfg.has("edge_auto"):
		_edge_auto = bool(cfg["edge_auto"])
	if cfg.has("leaves_enabled"):
		leaves_enabled = bool(cfg["leaves_enabled"])
	# edge_color 仅在 edge_auto=false 时作为垫底色
	if cfg.has("edge_color") and not _edge_auto:
		var ec = cfg["edge_color"]
		if typeof(ec) == TYPE_ARRAY and ec.size() >= 3:
			_grad_stops = [[0.0, ec[0], ec[1], ec[2]], [1.0, ec[0], ec[1], ec[2]]]
	# 自动取图边色：采样背景图顶/底边缘色，生成竖向渐变垫底（替换写死绿渐变）
	if _edge_auto and bg_image_path != "" and ResourceLoader.exists(bg_image_path):
		_grad_stops = _sample_edge_stops(bg_image_path)

## 字符串 -> TextureRect.StretchMode 枚举（"cover" 等价于 keep_aspect_covered）
static func _stretch_from_string(s: String) -> int:
	match s:
		"keep":
			return TextureRect.STRETCH_KEEP
		"keep_centered":
			return TextureRect.STRETCH_KEEP_CENTERED
		"keep_aspect":
			return TextureRect.STRETCH_KEEP_ASPECT
		"keep_aspect_centered":
			return TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		"keep_aspect_covered", "cover":
			return TextureRect.STRETCH_KEEP_ASPECT_COVERED
		"scale", "stretch":
			return TextureRect.STRETCH_SCALE
		"tile":
			return TextureRect.STRETCH_TILE
		_:
			return TextureRect.STRETCH_KEEP_ASPECT

## 极简 JSON 读取（仅本组件用，避免引入额外依赖）
func _load_json(p: String) -> Dictionary:
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var res = JSON.parse_string(txt)
	if res is Dictionary:
		return res
	return {}

## 采样背景图顶/底边缘色，生成竖向渐变（顶→底），用于垫底填缝，与图片边缘同色系
func _sample_edge_stops(p: String) -> Array:
	var tex := load(p) as Texture2D
	if tex == null:
		return GRAD_STOPS
	var img := tex.get_image()
	if img == null:
		return GRAD_STOPS
	var w: int = img.get_width()
	var h: int = img.get_height()
	var band: int = maxi(1, h / 24)
	var top: Color = _avg_rect(img, 0, band, w)
	var bot: Color = _avg_rect(img, h - band, band, w)
	return [
		[0.0, top.r * 255.0, top.g * 255.0, top.b * 255.0],
		[1.0, bot.r * 255.0, bot.g * 255.0, bot.b * 255.0],
	]

## 对图片某横向条带做稀疏平均色（用于边缘采样）
func _avg_rect(img: Image, y0: int, bh: int, w: int) -> Color:
	var r := 0.0
	var g := 0.0
	var b := 0.0
	var n := 0.0
	var step_x: int = maxi(1, w / 32)
	for y in range(y0, y0 + bh):
		for x in range(0, w, step_x):
			var c: Color = img.get_pixel(x, y)
			r += c.r
			g += c.g
			b += c.b
			n += 1.0
	if n <= 0.0:
		return Color(0.6, 0.6, 0.6)
	return Color(r / n, g / n, b / n)

## ① 渐变垫底：图片留出的空隙由它填补，颜色与图片边缘同源
func _build_gradient_base() -> void:
	var grad := Gradient.new()
	# 清空 Gradient 自带的默认黑白两点，避免混入
	grad.offsets = PackedFloat32Array()
	grad.colors = PackedColorArray()
	for stop in _grad_stops:
		grad.add_point(float(stop[0]), Color8(int(stop[1]), int(stop[2]), int(stop[3])))

	var tex := GradientTexture2D.new()
	tex.gradient = grad
	# 默认 fill_from(0,0)->fill_to(1,0) 是横向；这里改成竖向，匹配图片上浅下深的结构
	tex.fill_from = Vector2(0.0, 0.0)
	tex.fill_to = Vector2(0.0, 1.0)
	tex.width = 4      # 渐变为纯竖向，横向只需几个像素，拉伸无损失
	tex.height = 256

	var rect := TextureRect.new()
	rect.texture = tex
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.stretch_mode = TextureRect.STRETCH_SCALE   # 渐变可安全拉伸
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)

## ② 背景图：stretch_mode 由 layout_config_path 配置驱动（默认 keep_aspect_covered=铺满裁切，零黑边）
func _build_image() -> void:
	if bg_image_path == "" or not ResourceLoader.exists(bg_image_path):
		return
	var img_rect := TextureRect.new()
	img_rect.texture = load(bg_image_path) as Texture2D
	img_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	img_rect.stretch_mode = _stretch_mode
	img_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	img_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(img_rect)

## ③ 压暗层：垫底渐变与图片一起压暗，保证两者明度一致、看不出接缝
func _build_scrim() -> void:
	if scrim_alpha <= 0.0:
		return
	var scrim := ColorRect.new()
	scrim.color = Color(UIPalette.BG_DARK.r, UIPalette.BG_DARK.g, UIPalette.BG_DARK.b, scrim_alpha)
	scrim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scrim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(scrim)

## ④ 落叶粒子（图片背景与程序化背景共用）
func _build_leaves() -> CPUParticles2D:
	var vw: float = maxf(get_viewport_rect().size.x, 1280.0)
	var leaves := CPUParticles2D.new()
	leaves.emitting = true
	leaves.amount = 24
	leaves.lifetime = 9.0
	leaves.gravity = Vector2(0, 26)
	leaves.initial_velocity_min = 18.0
	leaves.initial_velocity_max = 55.0
	leaves.direction = Vector2(0.15, 1.0)
	leaves.spread = 18.0
	leaves.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	leaves.emission_rect_extents = Vector2(vw / 2.0, 24.0)
	leaves.position = Vector2(vw / 2.0, -24.0)
	leaves.scale = Vector2(1.6, 1.6)
	leaves.texture = _make_leaf_texture()
	# 注意：CPUParticles2D 是 Node2D 不是 Control，没有 mouse_filter 属性，不能设
	return leaves

func _make_leaf_texture() -> Texture2D:
	var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	img.fill(UIPalette.GOLD)
	return ImageTexture.create_from_image(img)
