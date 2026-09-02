# tests/unit/test_ui_mouse_filter.gd
# 静默拦截 BUG 运行时结构守卫（接入 GATE2，把"不报错但点不了"变成 ✗）
#
# 用户血的教训：装饰子节点(如 label_main)错写 mouse_filter = 0(STOP=拦截，反直觉)，
# 盖在按钮中心把按钮的 mouse_entered/button_up 全吞了 → 自动悬停、鼠标移不开、
# 点击永不触发回调；纯事件捕获、全程零报错。GATE1 抓不到，只能靠拾取模拟器复核。
#
# 本测试把规则编进门禁：加载 screens.json 全部界面，instantiate() 后遍历节点树，
# 断言【任意 BaseButton 的可见 Control 子节点(非嵌套按钮) mouse_filter 不得为 STOP(0)】。
#   - instantiate() 不跑 _ready、不依赖场景树布局，可在 TestBase(RefCounted) 同步执行；
#   - mouse_filter 默认即 STOP(0)，所以"没写行"也等于 STOP，本测试一并捕获。
#   - 只查 .tscn 声明树；代码中 _build_ui 动态加的装饰子节点若要同防，需在代码里显式设 IGNORE(2)。
#
# 与 tools/lint_mouse_filter.py(静态 GATE0)互补：静态查提交期、本测试查加载期。

extends TestBase

const SCREENS_JSON := "res://data/configs/ui/screens.json"

func _collect_screen_paths() -> Array[String]:
	var paths: Array[String] = []
	if not FileAccess.file_exists(SCREENS_JSON):
		return paths
	var txt := FileAccess.get_file_as_string(SCREENS_JSON)
	var parsed: Variant = JSON.parse_string(txt)
	if typeof(parsed) != TYPE_DICTIONARY:
		return paths
	var d: Dictionary = parsed
	for v in d.values():
		var s := str(v)
		if s.ends_with(".tscn"):
			paths.append(s)
	return paths

## 收集节点树下所有 BaseButton（含嵌套）
func _collect_buttons(n: Node, out: Array[Node]) -> void:
	if n is BaseButton:
		out.append(n)
	for c in n.get_children():
		_collect_buttons(c, out)

## 递归检查某按钮下的可见装饰子节点：mouse_filter==STOP(0) 即静默拦截风险
func _walk_check(node: Node, found: Array[String]) -> void:
	for c in node.get_children():
		if c is BaseButton:
			continue  # 嵌套按钮自身由它自己负责，不递归进其内部
		if c is Control and c.visible and c.mouse_filter == Control.MOUSE_FILTER_STOP:
			found.append("%s(%s)" % [c.name, c.get_class()])
		_walk_check(c, found)

func test_no_silent_block_decoration_under_buttons() -> void:
	var paths := _collect_screen_paths()
	expect(paths.size() > 0, "应能读到 screens.json 中的界面列表")
	var total := 0
	for p in paths:
		var packed := load(p) as PackedScene
		if packed == null:
			print("  (跳过无法加载: %s)" % p)
			continue
		var inst := packed.instantiate()
		if inst == null:
			print("  (跳过无法实例化: %s)" % p)
			continue
		var btns: Array[Node] = []
		_collect_buttons(inst, btns)
		for b in btns:
			var found: Array[String] = []
			_walk_check(b, found)
			for f in found:
				total += 1
				expect(false, "静默拦截风险[%s] 按钮[%s] 的子节点[%s] mouse_filter=STOP(0)，会吞掉点击" % [p, b.name, f])
		inst.free()
	if total == 0:
		print("  ✓ 全部界面按钮的装饰子节点均未处于 STOP(0) 静默拦截状态")
