# application/content/content_registry.gd
# Content Pipeline 核心（05 图 CT-1~CT-3 / LD-1~LD-4 / VE-1 / IX-1~IX-4 / CONTENT-RUNTIME v1.2.0）
# 九职责 ↔ API 一一映射（01 §45 原文，不多不少）：
#   Load=load_packs · Cache=内建 ShardCache · Index=query · Version=content_fingerprint
#   Dependency=resolve_order · DLC/Mod=discover · Validation=validate_all · Unload=unload
# 归属：Application 层 RefCounted 服务（非 Autoload 非 Kernel）；Phase3 前临时驻 ConfigManager
# autoload 位（05 图 C-1 已追认：装配层持有为 Phase3 目标，过渡态宿主=ConfigManager）。
# 复用 kernel 契约：OperationResult（结果面）/ ValidationViolation（VA-1 违规类型）。

class_name ContentRegistry
extends RefCounted

# IX-1：12 张必需索引（01 §46 全列，零删减；运行期只查不建，CO-R03）
const REQUIRED_INDEXES: Array[String] = [
	"quest_by_npc", "quest_by_faction", "quest_by_region", "quest_by_chapter", "quest_by_tag",
	"dialogue_by_npc", "dialogue_by_quest",
	"item_by_category", "item_by_tag",
	"npc_by_region", "npc_by_faction",
	"ability_by_actor",
]

var _loader: Callable                 # LD-1 过渡态：JSON 解析注入（生产=ConfigManager._load_json；测试=假 loader）
var _error_cb: Callable               # 容错回调注入（生产=ConfigManager._record_error；保真错误文案与容错层）
var _ready_cb: Callable               # LD-2 ⑤ ContentReadyEvent 发射器注入（生产=EventBus.content_ready）
var _packs: Dictionary = {}           # pack_id -> ContentPackManifest
var _adapters: Dictionary = {}        # kind -> ContentTypeAdapter
var _adapter_order: Array[StringName] = []   # 注册顺序（version「最后者胜」语义依赖此序）
var _shard_registry: Dictionary = {}  # dialog_id -> 分片登记（_index.json 原样收编，attach 引用共享）
var _indexes: Dictionary = {}         # index_name -> {IndexKey -> Array[String]}（IX-3 结构冻结）
var _cache: ShardCache                # CA-1 二级缓存（内建；Phase3 收回私有）
var _source_versions: Dictionary = {} # kind -> 最后抓到的 JSON version（与现 _config_version 语义对齐）
var _violations: Array[ValidationViolation] = []   # VA-3：rule_id+file+id+证据
var _validation_rules: Dictionary = {}   # VA-4（批2 DoD3）：五层规则表（构建期/运行期双端同一份 JSON）
var _schemas: Dictionary = {}            # Phase 3 Schema 真源（ConfigManager 注入；同一份 content_schemas.json，防两套规则漂移）
var _loaded: bool = false
var _fingerprint: String = ""
var _fingerprint_list: Array[String] = []          # C-4 已追认：列表+哈希双存（哈希可比对，列表可读可迁移）

func _init(p_loader: Callable = Callable(), p_error_cb: Callable = Callable()) -> void:
	_loader = p_loader
	_error_cb = p_error_cb
	_cache = ShardCache.new()

# === 注册（load 前）===

## 注册一类内容的 TypeAdapter（CT-4：一次迁一类；load 后禁注册=运行期内容不可变 CA-4）
func register_adapter(adapter: ContentTypeAdapter) -> bool:
	if _loaded:
		push_error("[Content] 运行期内容不可变（CA-4），load_packs 后禁注册新 adapter")
		return false
	if adapter == null or adapter.content_kind.is_empty():
		push_error("[Content] adapter 无效（kind 空）")
		return false
	if _adapters.has(adapter.content_kind):
		push_error("[Content] adapter kind 重复注册: %s" % adapter.content_kind)
		return false
	if adapter.files.is_empty() or (adapter.array_key.is_empty() and not adapter.loose and adapter.expand_key.is_empty()):
		push_error("[Content] adapter %s 缺 array_key/files（loose/expand 模式豁免 array_key）" % adapter.content_kind)
		return false
	_adapters[adapter.content_kind] = adapter
	_adapter_order.append(adapter.content_kind)
	return true

## 收编对话分片登记表（IX-4：_index.json shards → DialogueByNPC 雏形；引用共享零拷贝）
func attach_shard_registry(shards: Dictionary) -> void:
	if _loaded:
		push_error("[Content] 运行期内容不可变（CA-4），load 后禁改分片登记表")
		return
	_shard_registry = shards

## 注入 ContentReadyEvent 发射器（LD-2 ⑤；Callable 注入保持本类不依赖 EventBus）
func set_ready_callback(cb: Callable) -> void:
	_ready_cb = cb

# === 冻结 API 面（CT-3）===

## CO-R03（批2 DoD4）：注入 Build 期索引产物（tools/build_content_indexes.py 产出）
## 运行期只查不建；注入后 _ensure_indexes 对该索引只保底不覆盖（Build 产物优先）。
func attach_index(index_name: String, tbl: Dictionary) -> void:
	if _loaded:
		push_error("[Content] 运行期内容不可变（CA-4），load 后禁改索引")
		return
	if not REQUIRED_INDEXES.has(index_name):
		push_warning("[Content] 未登记索引: %s（IX-1 之外禁建）" % index_name)
		return
	_indexes[index_name] = tbl

## VA-4（批2 DoD3）：注入五层规则表（双端同一份 JSON——构建期 tools/validate_content_rules.py 同读）
## 结构见 data/configs/content_validation_rules.json；注入后 load_packs 的校验按表执行。
func load_validation_rules(rules: Dictionary) -> void:
	if _loaded:
		push_error("[Content] 运行期内容不可变（CA-4），load 后禁改规则表")
		return
	if not rules.has("layers"):
		push_error("[Content] 规则表缺 layers（VA-4 结构）")
		return
	_validation_rules = rules

## Phase 3 Schema 真源注入（03 图 §6.3 / 双端同源：构建期 tools/schema_validator.py 同读同一份
## data/configs/content_schemas.json，由 ConfigManager 装载后注入，防两套规则漂移）。
## 本类在 VA-2 L1 校验时按文件匹配 schema 做字段级检查（VA1-SCHEMA，ERROR 语义=登记不拒载）。
func load_schemas(schemas: Dictionary) -> void:
	if _loaded:
		push_error("[Content] 运行期内容不可变（CA-4），load 后禁改 Schema 表")
		return
	_schemas = schemas

## VA-3 severity 映射（rule_id → severity）：FATAL 才进拒载路径，ERROR/WARN 登记可见不拒载
func _severity_of(rule_id: String) -> String:
	for l in _validation_rules.get("layers", []):
		for r in l.get("rules", []):
			if str(r.get("rule_id", "")) == rule_id:
				return str(r.get("severity", "ERROR"))
	return "ERROR"

## 规则表查询：layer 序号 → rules 数组（未注入返回空=校验退化为内建最小集）
func _rules_for_layer(layer: int) -> Array:
	if _validation_rules.is_empty():
		return []
	for l in _validation_rules.get("layers", []):
		if int(l.get("layer", -1)) == layer:
			return l.get("rules", [])
	return []

## VA-2 第一层（Schema 形状）执行器：按规则表 required_fields/required_fields_by_kind 校验
func _validate_schema_layer(kind: StringName, entries: Array, files: Array[String]) -> Array[ValidationViolation]:
	var out: Array[ValidationViolation] = []
	for rule in _rules_for_layer(1):
		var rid := String(rule.get("rule_code", ""))
		var sev := String(rule.get("severity", "ERROR"))
		if rid == "VA1-REQ-ID":
			for e in entries:
				if not (e is Dictionary):
					continue   # 批C 后段：expand/loose 模式 store 值可为数组/整文档，非条目跳过
				var id := str(e.get("id", ""))
				if id.is_empty():
					out.append(ValidationViolation.new(StringName(rid), &"id",
						"条目缺 id（VA-2 L1）"))
		elif rid == "VA1-REQ-ADAPTER":
			var by_kind: Dictionary = rule.get("required_fields_by_kind", {})
			var req: Array = by_kind.get(String(kind), [])
			for e in entries:
				for f in req:
					var fv: Variant = e.get(String(f), null)
					if fv == null or str(fv).strip_edges() == "":
						out.append(ValidationViolation.new(
							StringName(rid), StringName(String(kind) + "." + String(f)),
							"条目 %s 必填字段缺失: %s（VA-2 L1）" % [e.get("id", ""), f]))
	# Phase 3 Schema 字段级（VA1-SCHEMA，ERROR 语义=登记不拒载）：adapter 文件命中
	# content_schemas.json 时按同一份真源做形状校验（双端同源；ability/item 当前无命中=no-op）
	for f in files:
		var rel := String(f).replace("res://data/configs/", "").replace("\\", "/")
		var schema := SchemaFieldChecker.schema_for(_schemas, rel)
		if schema.is_empty():
			continue
		for e in entries:
			if not (e is Dictionary):
				continue
			for v in SchemaFieldChecker.check_entry(schema, e):
				out.append(ValidationViolation.new(&"VA1-SCHEMA", &"schema", v))
	return out

## Load：启动期唯一入口，内部走 LD-2 五段顺序
func load_packs() -> OperationResult:
	if _loaded:
		return OperationResult.fail(&"CONTENT_ALREADY_LOADED", "运行期内容不可变（CA-4），load_packs 只许执行一次")
	var run_violations: Array[ValidationViolation] = []
	# —— ① base pack：虚拟 base pack（PK-2：物理迁移延 Phase5，逻辑上聚合现有 data/configs/）
	var base_manifest := ContentPackManifest.new(&"base", ContentPackManifest.TYPE_BASE)
	base_manifest.source_dir = "res://data/configs/"
	base_manifest.state = ContentPackManifest.STATE_LOADING
	for kind in _adapter_order:
		_load_adapter(_adapters[kind])
	# VA-2 L1（批2 DoD3）：规则表注入后按表执行 Schema 形状校验（双端同一份 JSON）
	# VA-3 分流：FATAL→拒载路径（run_violations）；ERROR/WARN→登记可见不拒载
	for kind in _adapter_order:
		var adapter: ContentTypeAdapter = _adapters[kind]
		for v in _validate_schema_layer(kind, adapter.store.values(), adapter.files):
			if _severity_of(str(v.get_code())) == "FATAL":
				run_violations.append(v)
			else:
				_violations.append(v)
	var last_ver: String = ""
	for kind in _adapter_order:
		var v: String = str(_source_versions.get(kind, ""))
		if not v.is_empty():
			last_ver = v
	base_manifest.semver = last_ver if not last_ver.is_empty() else "0.0.0"
	# CO-R06 fail-fast：启动期 FATAL 违规 → 整体加载失败并列违规清单，禁静默 fallback（LD-3）
	# 本批 adapter 加载走容错层（ERROR 语义），无 FATAL 场景；分支骨架供五层校验批（VA-1）接入
	if not run_violations.is_empty():
		base_manifest.state = ContentPackManifest.STATE_FAILED
		_violations.append_array(run_violations)
		return OperationResult.fail(&"CONTENT_LOAD_FAILED",
			"启动期内容校验存在 FATAL 违规，拒绝装载（LD-3 fail-fast）",
			{"violation_count": run_violations.size()})
	_packs[&"base"] = base_manifest
	# —— ② 依赖拓扑序（单 base 平凡；多 pack 拓扑+环=CONTENT_LOAD_FAILED 随 Phase5 实装）
	# —— ③ Index Build（Build 期生成，运行期只查不建 CO-R03）
	_ensure_indexes()
	# —— ④ Binding 校验（骨架：分片 file 指针；引用/悬空/退役复用随五层校验批）
	_validate_bindings()
	# —— ⑤ 发 ContentReadyEvent（COMMITTED 语义）
	base_manifest.state = ContentPackManifest.STATE_LOADED
	_loaded = true
	_compute_fingerprint()
	if not _ready_cb.is_null():
		_ready_cb.call(_fingerprint)
	return OperationResult.ok()

## Index：查索引，只回 ID 数组（IX-3 结构冻结；禁回对象/Dictionary，CO-R04）
func query(index_name: StringName, key: String) -> Array[String]:
	var out: Array[String] = []
	if not REQUIRED_INDEXES.has(String(index_name)):
		push_warning("[Content] 未登记索引: %s（IX-1 十二张之外禁建）" % index_name)
		return out
	var tbl: Dictionary = _indexes.get(String(index_name), {})
	out.assign(tbl.get(key, []))
	return out

## Version：聚合指纹（VE-1：已载 pack 按 id 排序后 (pack_id, semver) 序列 SHA-256 前 16 位）
func content_fingerprint() -> String:
	return _fingerprint

## Version：指纹列表原文（C-4 双存：可读可复算）
func content_fingerprint_list() -> Array[String]:
	return _fingerprint_list.duplicate()

## Dependency：pack 拓扑序（环=CONTENT_LOAD_FAILED；单 base 阶段为平凡序）
func resolve_order() -> Array[StringName]:
	var order: Array[StringName] = []
	var ids: Array = _packs.keys()
	ids.sort()
	for pid in ids:
		order.append(pid)
	return order

## DLC / Mod：目录发现（DM-4 顺序；DM-5 YAGNI：发现器 Phase5+ 实装，本批为结构骨架）
func discover(dir: String) -> Array[ContentPackManifest]:
	var found: Array[ContentPackManifest] = []
	var d := DirAccess.open(dir)
	if d == null:
		return found
	d.list_dir_begin()
	var fname := d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname == "pack.json":
			var data: Dictionary = {}
			if not _loader.is_null():
				var got: Variant = _loader.call(dir.path_join(fname))
				if got is Dictionary:
					data = got
			var m := ContentPackManifest.new(
				StringName(str(data.get("pack_id", fname.get_basename()))),
				str(data.get("type", ContentPackManifest.TYPE_MOD)))
			m.semver = str(data.get("version", "0.0.0"))
			m.priority = int(data.get("priority", 0))
			m.source_dir = dir
			# DM-3/CO-R07（批2 DoD6）：Mod 禁代码——pack 目录出现 .gd/.tscn/.tres = 拒载（FAIL 并列证据）
			var unsafe := _scan_mod_safety(dir)
			if not unsafe.is_empty():
				m.state = ContentPackManifest.STATE_FAILED
				for u in unsafe:
					_violations.append(ValidationViolation.new(&"CO-R07_MOD_CODE",
						StringName(str(m.pack_id)), u))
				push_error("[Content] pack %s 含可执行资源，拒载（CO-R07）: %s 项"
					% [str(m.pack_id), unsafe.size()])
			else:
				found.append(m)
		fname = d.get_next()
	d.list_dir_end()
	return found

## CO-R07 安全扫描：递归检查 pack 目录内可执行资源（GDScript 无沙箱的硬约束，DM-3）
func _scan_mod_safety(dir: String) -> Array[String]:
	var bad: Array[String] = []
	var stack: Array[String] = [dir]
	while not stack.is_empty():
		var cur: String = stack.pop_back()
		var dd := DirAccess.open(cur)
		if dd == null:
			continue
		dd.list_dir_begin()
		var fname := dd.get_next()
		while fname != "":
			var full := cur.path_join(fname)
			if dd.current_is_dir():
				stack.append(full)
			elif fname.ends_with(".gd") or fname.ends_with(".tscn") or fname.ends_with(".tres"):
				bad.append(full)
			fname = dd.get_next()
		dd.list_dir_end()
	return bad

## Validation：返回违规清单（VA-1 运行期通道；五层校验器批接入）
func validate_all() -> Array[ValidationViolation]:
	return _violations.duplicate()

## Unload：仅整 pack 粒度且零引用（CO-R12）；base 永驻
func unload(pack_id: StringName) -> OperationResult:
	if not _packs.has(pack_id):
		return OperationResult.fail(&"CONTENT_PACK_NOT_FOUND", "未知 pack: %s" % pack_id)
	if pack_id == &"base":
		return OperationResult.fail(&"CONTENT_UNLOAD_FORBIDDEN", "base pack 永驻，禁卸载（PK-2/CO-R12）")
	var m: ContentPackManifest = _packs[pack_id]
	if m.state != ContentPackManifest.STATE_LOADED:
		return OperationResult.fail(&"CONTENT_UNLOAD_BAD_STATE",
			"pack %s 状态 %s 不可卸载" % [pack_id, m.state])
	m.state = ContentPackManifest.STATE_UNLOADED
	_compute_fingerprint()
	return OperationResult.ok()

# === 内容读取（Registry 侧）===

func has_entry(kind: StringName, id: String) -> bool:
	var adapter: ContentTypeAdapter = _adapters.get(kind)
	return adapter != null and adapter.store.has(id)

func all_ids(kind: StringName) -> Array[String]:
	var out: Array[String] = []
	var adapter: ContentTypeAdapter = _adapters.get(kind)
	if adapter != null:
		out.assign(adapter.store.keys())
	return out

## 该类内容抓到的 JSON version（最后者胜，与现 _config_version 语义对齐）
func source_version(kind: StringName) -> String:
	return str(_source_versions.get(kind, ""))

# === 过渡态暴露（Phase3 装配收敛 / Phase4 类型化时收回私有）===

## adapter store 引用（facade attach 模式：ConfigManager 成员指向真身，61 调用方零改动）
func adapter_store(kind: StringName) -> Dictionary:
	var adapter: ContentTypeAdapter = _adapters.get(kind)
	if adapter == null:
		push_error("[Content] 未知内容种类: %s" % kind)
		return {}
	return adapter.store

## 分片登记表引用（ConfigManager._dialog_index 同一 Dictionary，零拷贝）
func shard_registry() -> Dictionary:
	return _shard_registry

## 内建 ShardCache（CA-1 二级缓存；现对话分片懒加载宿主）
func shard_cache() -> ShardCache:
	return _cache

# === 内部：装载 / 索引 / 校验 / 指纹 ===

## 通用装载算法（ConfigManager _load_abilities/_load_items 模式通用化，行为保真：
## 逐文件 version「最后者胜」+ 条目校验跳过 + 重复 id 记错覆盖。
## 批C 后段三模式：loose=整表（store=最后文档，空文件跳过保真）；expand_key=字典展开；
## 默认=entries 条目循环。）
func _load_adapter(adapter: ContentTypeAdapter) -> void:
	for path in adapter.files:
		var data: Dictionary = {}
		if not _loader.is_null():
			var got: Variant = _loader.call(path)
			if got is Dictionary:
				data = got
		if adapter.loose:
			# 整表模式：空文件跳过（与原 _load_world/_load_ui_anim/_load_ui_sfx 空保护保真）
			if data.is_empty():
				continue
			if not adapter.schema_check.is_null():
				adapter.schema_check.call(path, data)
			var ver := str(data.get("version", ""))
			if not ver.is_empty():
				_source_versions[adapter.content_kind] = ver
			adapter.store.clear()
			adapter.store.merge(data, true)
			continue
		if not adapter.expand_key.is_empty():
			# 字典展开模式：data[expand_key] 的 {键:值} 对直接拷入 store（重复键记错覆盖）
			var mapping: Dictionary = data.get(adapter.expand_key, {})
			for k in mapping.keys():
				if adapter.store.has(k) and not _error_cb.is_null():
					_error_cb.call("%s %s 重复定义，后者覆盖" % [adapter.display_label, str(k)])
				adapter.store[str(k)] = mapping[k]
			continue
		var ver2 := str(data.get("version", ""))
		if not ver2.is_empty():
			_source_versions[adapter.content_kind] = ver2
		for entry in data.get(adapter.array_key, []):
			if not _is_valid_entry(entry, path, adapter.array_key, adapter.id_field):
				continue
			# 批C（05图 CT-4 绞杀者）：可选 Schema 校验挂点（ quests 等带校验类的行为保真通道）
			if not adapter.schema_check.is_null():
				adapter.schema_check.call(path, entry)
			var id := str(entry[adapter.id_field]).strip_edges()
			if adapter.store.has(id) and not _error_cb.is_null():
				_error_cb.call("%s %s 重复定义，后者覆盖" % [adapter.display_label, id])
			adapter.store[id] = entry

## 条目校验（文案与 ConfigManager 容错层逐字一致）
func _is_valid_entry(entry: Variant, path: String, category: String, id_field: String) -> bool:
	if not (entry is Dictionary):
		if not _error_cb.is_null():
			_error_cb.call("%s | %s 条目不是对象，已跳过" % [path.get_file(), category])
		return false
	var d: Dictionary = entry as Dictionary
	var id: String = str(d.get(id_field, "")).strip_edges()
	if id.is_empty():
		if not _error_cb.is_null():
			_error_cb.call("%s | %s 条目缺少字段 '%s'，已跳过" % [path.get_file(), category, id_field])
		return false
	return true

## ③ Index Build：12 张登记表全立（IX-1 零删减）+ DialogueByNPC 首建（IX-4）
func _ensure_indexes() -> void:
	for idx_name in REQUIRED_INDEXES:
		if not _indexes.has(idx_name):
			_indexes[idx_name] = {}
	var by_npc: Dictionary = _indexes["dialogue_by_npc"]
	for did in _shard_registry.keys():
		var shard: Dictionary = _shard_registry[did]
		var nid: String = str(shard.get("npc_id", "")).strip_edges()
		if nid.is_empty():
			continue
		if not by_npc.has(nid):
			var fresh: Array[String] = [did]
			by_npc[nid] = fresh
		else:
			var arr: Array = by_npc[nid]
			if not arr.has(did):
				arr.append(did)

## ④ Binding 校验骨架（VA-3：每条违规必带 rule_id + file + id + 证据）
func _validate_bindings() -> void:
	for did in _shard_registry.keys():
		var shard: Dictionary = _shard_registry[did]
		var f := str(shard.get("file", "")).strip_edges()
		if f.is_empty():
			_violations.append(ValidationViolation.new(&"CO-R02_BINDING_MISSING", &"file",
				"对话分片 %s 缺 file 指针（file 为空）" % str(did)))

## VE-1：指纹 = 已载 pack 按 id 排序后 (pack_id, semver) 序列 SHA-256 前 16 位
func _compute_fingerprint() -> void:
	var parts: Array[String] = []
	var ids: Array = _packs.keys()
	ids.sort()
	for pid in ids:
		parts.append("%s@%s" % [str(pid), _packs[pid].semver])
	var joined := ",".join(parts)
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(joined.to_utf8_buffer())
	_fingerprint = ctx.finish().hex_encode().substr(0, 16)
	_fingerprint_list = parts
