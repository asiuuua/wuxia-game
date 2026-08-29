# tools/gen_contract.gd
# 契约总表生成器：扫描 EventBus 信号 + 各服务/状态类公开方法，自动生成 docs/契约总表.md
# 运行：Godot console --headless --path "D:/武侠游戏" --script res://tools/gen_contract.gd
# 铁律：代码是唯一真源，本脚本输出即契约文档（禁止手改）；改了接口必须重跑本脚本
# 设计：纯 FileAccess 文本解析，不加载 autoload（规避 --script 模式的假阳性）

extends SceneTree

const OUTPUT_PATH := "res://docs/契约总表.md"

# 纳入契约的文件清单（键=res:// 相对路径，值=对外职责说明）
# 新模块开工后在此登记一行即可
const CONTRACT_FILES := {
	"autoload/EventBus.gd": "全局事件总线（唯一跨模块消息通道；notify_*=事实通知，cmd_*=指令）",
	"autoload/GameManager.gd": "装配中枢：Service 容器 + 场景切换/存读档入口",
	"autoload/SaveManager.gd": "多槽存档管理（ISaveable 注册制）",
	"autoload/ConfigManager.gd": "全部 JSON 配置查询 + 容错校验",
	"autoload/difficulty_manager.gd": "难度管理器（团灭死亡行为/惩罚系数/丢物规则配置入口；零难度 if）",
	"autoload/ui_manager.gd": "UI 屏幕栈（screens.json 名->脚本）",
	"data/runtime/player_state.gd": "玩家运行时状态（气血/属性/金钱/存档）",
	"services/inventory/inventory_service.gd": "背包服务（三栏/堆叠/负重/事务API/用药）",
	"services/equipment/equipment_service.gd": "装备服务（装配/卸下/加成重算）",
	"services/shop/shop_service.gd": "商店服务（买卖/预检）",
	"services/forge/forge_service.gd": "锻造服务（配方/材料事务）",
	"services/alchemy/alchemy_service.gd": "炼药服务（配方/材料事务）",
	"services/combat/combat_service.gd": "战斗服务（回合制/结算/奖励回写/战斗内用药）",
	"services/quest/quest_service.gd": "任务服务（接取/推进/发奖）",
	"services/ability/ability_service.gd": "武学服务（学习/装备/施展）",
	"services/sect/sect_service.gd": "门派服务（声望/阶位）",
	"services/bond/bond_service.gd": "结缘服务（好感度/送礼/好感度事件；M1）",
	"services/bond/romance_service.gd": "姻缘服务（姻缘/婚姻分支：无限配偶/求婚/结婚/关系网/子嗣预留；M2）",
	"services/bond/sworn_service.gd": "结义服务（结义分支：无限结义兄弟/好感阈值/结义能力；M4）",
	"services/bond/master_service.gd": "师徒服务（师徒分支：双向拜师收徒/阶位/可授武学；M4）",
	"services/bond/relationship_service.gd": "关系网服务（聚合好感/配偶/子嗣/结义/师徒为统一关系图；M3，无状态门面）",
}

func _init() -> void:
	var lines: Array[String] = []
	lines.append("# 架构契约总表（自动生成，禁止手改）")
	lines.append("")
	lines.append("> 生成时间：%s　·　生成器：`tools/gen_contract.gd`（`--headless --script res://tools/gen_contract.gd`）" % Time.get_datetime_string_from_system())
	lines.append(">")
	lines.append("> **代码是唯一真源**：改了任何信号/公开方法，必须重跑生成器同步本表。")
	lines.append("> 跨模块约定：读走服务公开方法；写完广播 EventBus 事件；禁止调用 `_` 私有成员；禁止传递节点引用。")
	lines.append("")
	var total_signals := 0
	var total_methods := 0
	for rel_path in CONTRACT_FILES:
		var parsed: Dictionary = _parse_file(rel_path)
		var sigs: Array = parsed.get("signals", [])
		var methods: Array = parsed.get("methods", [])
		if sigs.is_empty() and methods.is_empty():
			lines.append("## %s（解析为空，请检查文件路径）" % rel_path)
			lines.append("")
			continue
		lines.append("## %s" % str(CONTRACT_FILES[rel_path]))
		lines.append("- 文件：`%s`" % rel_path)
		lines.append("")
		if not sigs.is_empty():
			lines.append("### 信号（谁产生谁 emit，谁关心谁 connect）")
			lines.append("")
			lines.append("| 信号 | 参数 | 用途 |")
			lines.append("|---|---|---|")
			for s in sigs:
				var sig: Dictionary = s
				var doc: String = String(sig.get("doc", "")).replace("|", "\\|")
				lines.append("| `%s` | %s | %s |" % [sig.get("name", ""), sig.get("args", ""), doc])
			total_signals += sigs.size()
			lines.append("")
		if not methods.is_empty():
			lines.append("### 公开方法（跨模块只允许调这些；`_` 开头为私有，禁调）")
			lines.append("")
			lines.append("| 方法 | 签名 | 说明 |")
			lines.append("|---|---|---|")
			for m in methods:
				var met: Dictionary = m
				var doc2: String = String(met.get("doc", "")).replace("|", "\\|").replace("\n", " ")
				var ret: String = String(met.get("ret", "")).strip_edges()
				var sig_str := "`%s(%s)`" % [met.get("name", ""), met.get("args", "")]
				if ret != "":
					sig_str += " -> `%s`" % ret
				lines.append("| %s | | %s |" % [sig_str, doc2])
			total_methods += methods.size()
		lines.append("")
	lines.append("---")
	lines.append("统计：信号 %d 个 · 公开方法 %d 个 · 纳入契约文件 %d 个" % [total_signals, total_methods, CONTRACT_FILES.size()])
	var f: FileAccess = FileAccess.open(OUTPUT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("[gen_contract] 无法写入 %s" % OUTPUT_PATH)
		quit(1)
		return
	f.store_string("\n".join(lines))
	f.close()
	print("[gen_contract] 完成：信号 %d · 公开方法 %d -> %s" % [total_signals, total_methods, OUTPUT_PATH])
	quit(0)

## 解析单个脚本：提取 signal 定义与公开 func（含上方 ## 文档注释）
## 返回 { "signals": Array, "methods": Array }
func _parse_file(rel_path: String) -> Dictionary:
	var out := { "signals": [], "methods": [] }
	if not FileAccess.file_exists(rel_path):
		return out
	var f: FileAccess = FileAccess.open(rel_path, FileAccess.READ)
	if f == null:
		return out
	var text: String = f.get_as_text()
	f.close()
	var sig_re: RegEx = RegEx.new()
	sig_re.compile("^signal\\s+(\\w+)\\s*\\((.*)\\)")
	var func_re: RegEx = RegEx.new()
	func_re.compile("^func\\s+(\\w+)\\s*\\((.*?)\\)\\s*(?:->\\s*([^:#]+))?:")
	var section_re: RegEx = RegEx.new()
	section_re.compile("^#\\s*===\\s*(.+?)\\s*===")
	var doc_re: RegEx = RegEx.new()
	doc_re.compile("^\\s*##\\s?(.*)$")
	var doc_buf: Array[String] = []
	var section: String = ""
	for raw_line in text.split("\n"):
		var line: String = raw_line
		# 连续 ## 注释收集
		var dm: RegExMatch = doc_re.search(line)
		if dm != null:
			doc_buf.append(dm.get_string(1).strip_edges())
			continue
		# 分段标题（EventBus 的 "# === 背包模块 ==="）
		var sm: RegExMatch = section_re.search(line)
		if sm != null:
			section = sm.get_string(1).strip_edges()
			doc_buf.clear()
			continue
		var sigm: RegExMatch = sig_re.search(line)
		if sigm != null:
			var doc_text := _join_doc(doc_buf)
			if section != "" and doc_text == "":
				doc_text = section
			out["signals"].append({
				"name": sigm.get_string(1),
				"args": sigm.get_string(2).strip_edges(),
				"doc": doc_text,
			})
			doc_buf.clear()
			continue
		var fm: RegExMatch = func_re.search(line)
		if fm != null:
			var fname: String = fm.get_string(1)
			# 私有与引擎回调不进契约
			if not fname.begins_with("_"):
				out["methods"].append({
					"name": fname,
					"args": fm.get_string(2).strip_edges(),
					"ret": fm.get_string(3),
					"doc": _join_doc(doc_buf),
				})
			doc_buf.clear()
			continue
		# 普通代码行打断注释缓冲
		if line.strip_edges() != "":
			doc_buf.clear()
	return out

func _join_doc(buf: Array[String]) -> String:
	return " ".join(buf).strip_edges()
