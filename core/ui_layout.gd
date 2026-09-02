# core/ui_layout.gd
# HUD 四面板默认位置装载器（UI 放权 Phase 1：推广 layout.json 模式到 HUD）。
# 工作室「UI 模块 → HUD 布局」写入 data/configs/ui/hud_layout.json（参考分辨率 1920x1080 绝对坐标）。
# 游戏侧只读取 + 按当前视口等比缩放 + 缺省回退：文件缺失 / 解析失败 / 字段非法 → 返回 fallback（各面板既有硬编码默认），零破坏。
# 玩家在游戏内拖拽后落点存 user://ui/hud_positions.json（个人偏好），优先于本默认值；本文件只决定「首开 / 恢复默认」时的位置。

extends RefCounted
class_name UILayout

const HUD_LAYOUT_PATH := "res://data/configs/ui/hud_layout.json"
const REF_W := 1920.0
const REF_H := 1080.0

## 读取某面板在「参考分辨率」下的默认绝对坐标，并按当前视口等比缩放后返回。
## key: 面板键（status_card / quest_track / top_right_menu / skill_bar）
## fallback: 现有硬编码默认（JSON 不可用时原样返回，保证行为不变）
## vp: 当前主视口尺寸（用于等比缩放）
static func hud_default_pos(panel_key: String, fallback: Vector2, vp: Vector2) -> Vector2:
	var data: Dictionary = _load_hud()
	if data == null or not data.has("panels"):
		return fallback
	var panels: Dictionary = data["panels"]
	if not panels.has(panel_key):
		return fallback
	var spec: Variant = panels[panel_key]
	if not (spec is Dictionary):
		return fallback
	var sx = spec.get("x", null)
	var sy = spec.get("y", null)
	if not (sx is float or sx is int) or not (sy is float or sy is int):
		return fallback
	var rx: float = float(sx)
	var ry: float = float(sy)
	# 按当前视口相对参考分辨率等比缩放：保证任意分辨率下布局比例一致（右上角仍右上角）
	var scale_x: float = vp.x / REF_W
	var scale_y: float = vp.y / REF_H
	if not is_finite(scale_x) or scale_x <= 0.0:
		scale_x = 1.0
	if not is_finite(scale_y) or scale_y <= 0.0:
		scale_y = 1.0
	return Vector2(rx * scale_x, ry * scale_y)

static func _load_hud() -> Dictionary:
	if not FileAccess.file_exists(HUD_LAYOUT_PATH):
		return {}
	var f := FileAccess.open(HUD_LAYOUT_PATH, FileAccess.READ)
	if f == null:
		return {}
	var txt := f.get_as_text()
	f.close()
	var j := JSON.new()
	if j.parse(txt) != OK:
		return {}
	if j.data is Dictionary:
		return j.data
	return {}
