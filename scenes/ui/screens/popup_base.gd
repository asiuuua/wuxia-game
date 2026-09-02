# scenes/ui/screens/popup_base.gd
# 弹窗基类（大厂解耦范式）：视图只负责渲染与接收点击，关闭只"请求"，不自己 queue_free。
# - popup_id：弹窗标识（可选，便于排查）
# - EventBus.popup_close_requested(popup)：关闭请求信号（由 UIManager 统一收口关闭/销毁）
# - make_glass_panel(size)：统一生成「居中磨砂玻璃面板」，派生弹窗复用，避免各写玻璃样式
# - request_close()：仅经 EventBus emit 信号，绝不 self.queue_free()
# 用法：弹窗 extends PopupBase，_ready 里建好内容后调用 make_glass_panel 得到主面板 add 进去，
#       关闭按钮 connect request_close。装备/锻造/炼药/商铺/门派/属性/背包/结缘/技艺/设置/菜单等子屏已迁移继承本类，
#       统一经事件总线关闭（视图只 emit，UIManager 收口），PopupBase 即统一弹窗基类。

extends Control
class_name PopupBase

const UICenterUtils = preload("res://scenes/ui/ui_center_utils.gd")

var popup_id: String = ""

## 是否响应 ui_cancel 自行关闭（与 BaseScreen.close_on_cancel 保持一致的范式）。
## 默认 true：按下 ESC 经 request_close() 由 UIManager 收口关闭；
## 若某屏不应自关（如由外部场景统一开关），在子类中置 false。
var close_on_cancel: bool = true

func _ready() -> void:
	pass

## 生成居中磨砂玻璃主面板（先给 size，再居中+玻璃，中心精确=父中心）
func make_glass_panel(size: Vector2) -> Panel:
	var p := Panel.new()
	p.size = size
	p.custom_minimum_size = size
	UICenterUtils.center_panel(p)
	UICenterUtils.apply_glass_style(p)
	return p

## 请求关闭：只经全局事件总线广播，由 UIManager 决定隐藏(缓存)或销毁(一次性)。弹窗自身绝不 self.queue_free()
func request_close() -> void:
	EventBus.popup_close_requested.emit(self)

# === 响应式锚点（2026-09-02 统一收口）===
# 各 PopupBase 弹窗在 _ready 末尾调用 enable_responsive($Panel, Vector2(W,H)) 即可获得：
#   ① 大视口保持原尺寸（视觉不变）② 小视口自动内缩防溢出/错位 ③ 分辨率变化时自动重排居中。
# 取代各屏手写 PRESET_CENTER / 固定 offset 的脆弱写法（见 ui_center_utils.fit_panel_to_viewport）。
var _rp_panel: Control = null
var _rp_desired: Vector2 = Vector2.ZERO
var _rp_mx: float = 0.06
var _rp_my: float = 0.06

## 启用响应式面板。desired 为面板「设计尺寸」（通常取 .tscn 里 Panel 的 size）。
## margin 为视口留白比例（默认 6%）。弹窗关闭（tree_exiting）时自动断开 size_changed，避免悬空监听。
func enable_responsive(panel: Control, desired: Vector2, margin_x := 0.06, margin_y := 0.06) -> void:
	_rp_panel = panel
	_rp_desired = desired
	_rp_mx = margin_x
	_rp_my = margin_y
	_fit_responsive()
	var vp := get_viewport()
	if vp == null:
		return  # headless 单测无真实视口，跳过接线（测试窗口派单 9526b65a3386）
	if not vp.size_changed.is_connected(_fit_responsive):
		vp.size_changed.connect(_fit_responsive)
	# tree_exiting 不论子类是否定义 _exit_tree 都会触发，故用它做清理，避免与子类 _exit_tree 冲突
	if not tree_exiting.is_connected(_cleanup_responsive):
		tree_exiting.connect(_cleanup_responsive)

func _fit_responsive() -> void:
	if _rp_panel != null and is_instance_valid(_rp_panel):
		UICenterUtils.fit_panel_to_viewport(_rp_panel, _rp_desired, _rp_mx, _rp_my)

func _cleanup_responsive() -> void:
	var vp := get_viewport()
	if vp != null and vp.size_changed.is_connected(_fit_responsive):
		vp.size_changed.disconnect(_fit_responsive)

## 统一 ESC 关闭（与 BaseScreen 行为对齐，消除各屏手写 _unhandled_input 的遗漏/分叉）：
## 按下 ui_cancel 经 request_close() 收口；close_on_cancel=false 的屏（如由外部场景统一开关者）不响应。
## 子类若另写 _unhandled_input 且不调 super，则以其自身逻辑为准，不会与这里叠加。
func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if close_on_cancel and event.is_action_pressed("ui_cancel"):
		request_close()
		get_viewport().set_input_as_handled()
