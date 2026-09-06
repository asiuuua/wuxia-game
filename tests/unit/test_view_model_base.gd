# tests/unit/test_view_model_base.gd
# 14 图批1 ②：ViewModel 契约骨架测试（PV-1 / 宪法 L2097 / 14图 §5.3 三禁）。
# 覆盖：RefCounted 纯数据形态、基类 rebuild 抽象面、派生类投影往返、
#       投影快照独立性（transient 语义）、投影字段零 Node 引用（三禁之二运行时抽查）。
# 三禁的静态面（直写/Node 引用/写入口前缀）由 GATE41 scan_view_model_hygiene 主责。

extends TestBase


## 试点派生类：模拟 HUD 产榜屏最小投影（值类型字段 + 派生字段计算）
class PilotVM extends ViewModelBase:
	var display_name: String = ""
	var load_ratio: float = 0.0        # 派生字段：负重百分比
	var can_afford: bool = false       # 派生字段：可否购买
	var tags: Array = []

	## 模拟从业务状态快照（Dictionary）重建投影——骨架期以快照参数代 Query，
	## Query 化后来源替换为 RM 查询，本契约形状不变。
	func rebuild_from(snapshot: Dictionary) -> bool:
		display_name = String(snapshot.get("display_name", ""))
		var cur := int(snapshot.get("load_cur", 0))
		var max_v := int(snapshot.get("load_max", 1))
		load_ratio = float(cur) / float(maxi(max_v, 1))
		can_afford = int(snapshot.get("money", 0)) >= int(snapshot.get("price", 0))
		tags = (snapshot.get("tags", []) as Array).duplicate()
		return true


func test_view_model_is_refcounted_not_node() -> void:
	var vm: Variant = ViewModelBase.new()
	expect(vm != null and is_instance_valid(vm), "ViewModelBase 可实例化")
	expect(not (vm is Node), "PV-1：ViewModel 是 RefCounted 纯数据，禁是 Node")
	expect(vm is RefCounted, "extends RefCounted 冻结形态")


func test_base_rebuild_is_abstract_false() -> void:
	var vm: ViewModelBase = ViewModelBase.new()
	expect(vm.rebuild() == false, "基类 rebuild 未实现=false（契约：必须声明投影重建入口）")


func test_pilot_rebuild_projection_roundtrip() -> void:
	var vm := PilotVM.new()
	var ok := vm.rebuild_from({
		"display_name": "李十五",
		"load_cur": 30,
		"load_max": 100,
		"money": 50,
		"price": 40,
		"tags": ["甲", "乙"],
	})
	expect(ok, "派生类 rebuild 成功")
	expect(vm.display_name == "李十五", "直投字段")
	expect(vm.load_ratio > 0.29 and vm.load_ratio < 0.31, "派生字段=负重 30%")
	expect(vm.can_afford, "派生字段=可否购买（钱够价）")


func test_projection_snapshot_is_transient() -> void:
	var vm := PilotVM.new()
	var snap := {
		"display_name": "苏婉儿", "load_cur": 10, "load_max": 100,
		"money": 5, "price": 10, "tags": ["甲"],
	}
	vm.rebuild_from(snap)
	expect(not vm.can_afford, "投影时点：钱不够")
	# 业务状态此后变化（钱涨了/改名）：已投影字段不跟随——UI 渲染只读上次 rebuild 的瞬像
	snap["money"] = 100
	snap["display_name"] = "改名后"
	expect(not vm.can_afford, "transient：业务状态后变不影响已投影字段")
	expect(vm.display_name == "苏婉儿", "transient：快照后源改动不穿透")


func test_projection_fields_hold_no_node_reference() -> void:
	var vm := PilotVM.new()
	vm.rebuild_from({"display_name": "甲", "load_cur": 1, "load_max": 2, "money": 0, "price": 0, "tags": []})
	var node_refs := 0
	for p in vm.get_property_list():
		if int(p.get("usage", 0)) & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var v: Variant = vm.get(String(p.get("name", "")))
		if v is Node:
			node_refs += 1
	expect_eq(node_refs, 0, "三禁之二：投影字段零 Node 引用（运行时抽查）")
