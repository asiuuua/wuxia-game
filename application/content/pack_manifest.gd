# application/content/pack_manifest.gd
# Content Pipeline · Package 冻结项（05 图 PK-1 / DM-1 / CONTENT-RUNTIME v1.2.0）
# Pack 生命周期五态（PK-1 冻结）：状态迁移只发生在 Loader 五段与 Unload。
# manifest 字段（DM-1 冻结）：一律 DLC = Mod = Pack，无特权代码路径；区别仅在 type/priority/overrides。

class_name ContentPackManifest
extends RefCounted

# PK-1：生命周期五态（冻结）
const STATE_DISCOVERED := "discovered"
const STATE_LOADING := "loading"
const STATE_LOADED := "loaded"
const STATE_FAILED := "failed"
const STATE_UNLOADED := "unloaded"

# DM-1：pack 类型（冻结；base/expansion/mod 同一机制）
const TYPE_BASE := "base"
const TYPE_EXPANSION := "expansion"
const TYPE_MOD := "mod"

var pack_id: StringName
var type: String = TYPE_BASE
var semver: String = "0.0.0"
var priority: int = 0                       # DM-4：同优先级按升序、后载者仅 override 声明项内生效
var depends: Array[String] = []             # 依赖 pack 声明（拓扑序输入）
var overrides: Array[String] = []           # DM-2：显式覆盖声明（未声明的覆盖 = 违规拒载）
var state: String = STATE_DISCOVERED
var source_dir: String = ""                 # 发现来源目录（res:// 或 user://）

func _init(p_pack_id: StringName, p_type: String = TYPE_BASE) -> void:
	pack_id = p_pack_id
	type = p_type

func is_loaded_state() -> bool:
	return state == STATE_LOADED
