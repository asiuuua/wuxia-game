# core/ui_skin.gd
# 通用 UI 皮肤装载器（UI 窗口主权）。
# 设计原则（与「UI 放权方案」一致）：小白只改 data/configs/ui/skin/theme.json 这份数据；
# 游戏侧只做「装载 + 应用」，读不到文件或解析失败都回退 DEFAULTS，永不崩溃。
# 不提供任何写逻辑——写由工作室后端 /api/ui_skin 负责，游戏侧对平台零依赖。
extends RefCounted
class_name UISkin

const THEME_PATH := "res://data/configs/ui/skin/theme.json"

# 默认配色（与现有美术一致；缺文件 / 解析失败时回退，视觉不变）。
# 键名即工作室「主题配色」面板的字段；值为 Godot Color(R,G,B,A)，0~1 浮点。
const DEFAULTS := {
	"panel_bg": Color(0.071, 0.078, 0.11, 0.62),
	"panel_border": Color(1, 1, 1, 0.2),
	"title_color": Color(0.831, 0.686, 0.216, 1),
	"content_color": Color(0.941, 0.902, 0.82, 1),
	"accent": Color(0.55, 0.78, 0.45, 1),
}

## 读取主题配色，返回 {key: Color}。缺文件或非法 JSON 回退 DEFAULTS。
static func load_theme() -> Dictionary:
	if not FileAccess.file_exists(THEME_PATH):
		return DEFAULTS.duplicate()
	var f := FileAccess.open(THEME_PATH, FileAccess.READ)
	if f == null:
		return DEFAULTS.duplicate()
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return DEFAULTS.duplicate()
	var raw: Dictionary = j.data
	var out := DEFAULTS.duplicate()
	for k in DEFAULTS.keys():
		if raw.has(k) and raw[k] is Array and (raw[k] as Array).size() >= 3:
			var a: Array = raw[k]
			var r := float(a[0]); var g := float(a[1]); var b := float(a[2])
			var al := float(a[3]) if (raw[k] as Array).size() > 3 else 1.0
			out[k] = Color(r, g, b, al)
	return out

## 用主题配色构造一个磨砂玻璃面板 StyleBoxFlat（与 ConfirmDialog.tscn 的 1_glass 同形）。
## 这样工作室改 panel_bg / panel_border 时即时反映到弹窗主体，无需动 .tscn。
static func panel_stylebox(theme: Dictionary) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = theme.get("panel_bg", DEFAULTS["panel_bg"])
	sb.border_color = theme.get("panel_border", DEFAULTS["panel_border"])
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.content_margin_left = 1
	sb.content_margin_right = 1
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	return sb
