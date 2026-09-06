# scenes/ui/view_model_base.gd
# ViewModel 基类契约骨架（14 图 PV-1，D4 批1 落地 2026-09-06）。
# ViewModel = UI-local transient display state（宪法 L2097）：RefCounted 纯数据投影，
# 字段 = 该屏展示所需最小投影（含派生字段，如「负重百分比」「可否购买」）。
# 三禁（14 图 §5.3 Freeze）：禁反向写业务状态 / 禁持 Node 引用 / 禁业务判定读表现数据。
# 机器面：GATE41 scan_view_model_hygiene——extends ViewModelBase 文件扫描：
#   ①跨模块属性直写零命中 ②零 Node 类型引用/add_child/preload(.tscn) ③零写入口前缀方法。
# 引入节奏 = 绞杀者逐屏（14 图 §4 行12）：改哪屏带哪屏，不搞一次性重写；
# Phase4 从 HUD 四面板 + InventoryScreen 起步（P-V3 耦合最深处）。
# rebuild 唯一数据进点：UI 屏 _refresh/_on_reopen 时调用一次，把业务状态读成本屏投影，
# 渲染期只读本对象字段、零业务读（P-V3 收口方向的落点：`_ATTRS` 直拉 PlayerState 归此）。

class_name ViewModelBase
extends RefCounted


## 从业务状态重建本屏投影（唯一数据进点）。返回 true=已重建。
## 基类未实现 = false + ERROR（PV-1 契约：ViewModel 必须声明自己的投影重建入口）。
func rebuild() -> bool:
	push_error("[ViewModel] rebuild() 未实现——PV-1：ViewModel 必须声明投影重建入口")
	return false
