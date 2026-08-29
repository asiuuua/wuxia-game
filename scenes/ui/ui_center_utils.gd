# scenes/ui/ui_center_utils.gd
# 界面居中工具（2026-08-29）。
#
# ⚠️ 重要坑（已在多窗口复现）：Godot 4.7.2 的
#   set_anchors_and_offsets_preset(Control.PRESET_CENTER)
# 会忽略节点「当前 size」、把四个 offset 直接清零（实测：先给 size 再 PRESET_CENTER，
# 打印出来 offset 仍为 0）。结果面板 anchor 全 0.5、offset 全 0 → 左边缘落在父中心，
# 而非真正居中（视觉上明显偏右/偏下）。
#
# 本工具改用「锚 0.5 + 对称 offset（±size/2）」手动居中，中心精确 = 父节点中心。
# 所有弹出面板（菜单/姻缘/背包/设置/读档/地图/属性/技艺/确认框…）统一调用本函数，
# 杜绝各自手写 PRESET_CENTER 再踩坑。
#
# 调用前必须先给 panel.size 赋真实尺寸（本函数读取 panel.size 计算 offset）。

class_name UICenterUtils

const UIPalette = preload("res://core/constants/ui_theme.gd")

## 把 panel 真正居中到其父节点中心。调用前需已设置 panel.size。
static func center_panel(p: Control) -> void:
	if p == null:
		return
	var s := p.size
	p.anchor_left = 0.5
	p.anchor_top = 0.5
	p.anchor_right = 0.5
	p.anchor_bottom = 0.5
	p.offset_left = -s.x * 0.5
	p.offset_top = -s.y * 0.5
	p.offset_right = s.x * 0.5
	p.offset_bottom = s.y * 0.5

## 给面板套上统一的「磨砂玻璃」样式（与 ConfirmDialog / 菜单弹窗一致）。
## 调用前 panel 应已 add 到父节点；本函数只覆盖 "panel" 主题的 StyleBox。
static func apply_glass_style(p: Control) -> void:
	if p == null:
		return
	var sb := StyleBoxFlat.new()
	sb.bg_color = UIPalette.GLASS_BG
	sb.border_width_left = 1
	sb.border_width_top = 1
	sb.border_width_right = 1
	sb.border_width_bottom = 1
	sb.border_color = UIPalette.GLASS_BORDER
	sb.corner_radius_top_left = 14
	sb.corner_radius_top_right = 14
	sb.corner_radius_bottom_left = 14
	sb.corner_radius_bottom_right = 14
	sb.shadow_size = 16
	sb.shadow_offset = Vector2(0, 6)
	sb.shadow_color = UIPalette.GLASS_SHADOW
	sb.content_margin_left = 1
	sb.content_margin_right = 1
	sb.content_margin_top = 1
	sb.content_margin_bottom = 1
	p.add_theme_stylebox_override("panel", sb)
