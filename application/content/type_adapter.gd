# application/content/type_adapter.gd
# Content Pipeline · Registry 迁移机制（05 图 CT-4 / CONTENT-RUNTIME v1.2.0）
# 每类内容一个 TypeAdapter（id 字段名/文件列表/索引需求），ConfigManager 17 个 _load_*
# 逐类改写为 adapter 数据（绞杀者：一次迁一类、GATE2 全绿再迁下一类）。
# 本类是纯数据 + 真身 store；加载算法归 ContentRegistry（LD-1 解析边界另批落位）。

class_name ContentTypeAdapter
extends RefCounted

var content_kind: StringName          # 内容种类：&"ability" / &"item" / ...
var files: Array[String] = []         # 该类内容全部 JSON 文件（res:// 路径）
var array_key: String = ""            # JSON 中条目数组键（如 "skills"/"items"）
var id_field: String = "id"           # 条目 id 字段名
var display_label: String = ""        # 错误文案用的中文名（保真原 _record_error 文案）
var definition_class: String = ""     # 03 Definition 类名占位（Phase4 类型化时启用）
var schema_check: Callable = Callable()  # 可选 Schema 校验挂点（批C：签名 func(path: String, entry: Dictionary) -> void；entries 模式按条目调用，loose 模式按整文档调用）
var loose: bool = false               # 批C 后段泛化：整表模式——单文件整体 Dictionary（非 id 键控），store=最后加载文档（「最后者胜」逐文件覆盖保真）
var expand_key: String = ""           # 批C 后段泛化：字典展开模式——data[expand_key] 为 {键:值} 映射，键值对直接拷入 store（如 dialog_events 的 events 节）
var store: Dictionary = {}            # id -> entry 真身（Registry 持有，运行期内容不可变 CA-4）

func _init(p_kind: StringName, p_files: Array[String], p_array_key: String,
		p_id_field: String = "id", p_label: String = "", p_definition_class: String = "") -> void:
	content_kind = p_kind
	files = p_files.duplicate()
	array_key = p_array_key
	id_field = p_id_field
	display_label = p_label
	definition_class = p_definition_class
