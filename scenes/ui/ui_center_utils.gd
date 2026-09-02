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

## 计算面板在给定视口下的「应占尺寸」：大视口下保持 desired（视觉不变），
## 小视口下缩到视口内（留 margin 边距，防溢出/错位）；下限 240 避免极端小窗压成不可读。
## 抽成纯函数便于单元测试，fit_panel_to_viewport 直接复用。
static func clamp_panel_size(desired: Vector2, vp_size: Vector2, margin_x := 0.06, margin_y := 0.06) -> Vector2:
	var w := mini(desired.x, maxf(vp_size.x * (1.0 - margin_x), 240.0))
	var h := mini(desired.y, maxf(vp_size.y * (1.0 - margin_y), 240.0))
	return Vector2(w, h)

## 响应式锚点核心：把面板按视口裁剪并居中（参考 SettingsScreen._fit_panel 范式统一收口）。
## - 自由面板（非容器子节点）：设 size + custom_minimum_size 后按锚 0.5 + 对称 offset 居中；
## - 容器子节点（CenterContainer 等）：仅靠 custom_minimum_size 让容器居中（容器会忽略手动 size/anchor）。
## 大视口下 size = desired（与原布局一致，零视觉变化）；小视口下自动内缩，杜绝出界/错位。
static func fit_panel_to_viewport(p: Control, desired: Vector2, margin_x := 0.06, margin_y := 0.06) -> void:
	if p == null:
		return
	var vp := p.get_viewport()
	if vp == null:
		return  # headless 单测无真实视口，跳过响应式接线（测试窗口派单 9526b65a3386）
	var sz := clamp_panel_size(desired, vp.get_visible_rect().size, margin_x, margin_y)
	p.custom_minimum_size = sz
	p.size = sz
	if p.get_parent() is Container:
		return
	center_panel(p)

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
