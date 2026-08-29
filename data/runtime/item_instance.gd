# data/runtime/item_instance.gd
# 物品运行时实例：存档数据载体（规范 §2.3）

extends RefCounted
class_name ItemInstance

var instance_id: String = ""
var item_id: String = ""
var count: int = 1
var durability: float = -1.0       # -1 表示无耐久
var max_durability: float = -1.0
var acquired_source: String = ""   # 来源："drop:bandit_001" / "quest:q_001"
var acquired_time: int = 0
var is_new: bool = true
var locked: bool = false           # 玩家手动锁定：防止被动移除（售卖/分解/丢弃/团灭丢失/批量扣料）；主动吃药/装备不受影响

# 实例存档 schema 版本：未来物品结构迁移时按此钩子识别旧档（ver 缺省=0 即旧档）
const SCHEMA_VERSION := 1

func serialize() -> Dictionary:
	return {
		"ver": SCHEMA_VERSION,
		"iid": instance_id, "id": item_id, "cnt": count,
		"dur": durability, "mdur": max_durability,
		"src": acquired_source, "time": acquired_time,
		"lock": locked,
	}

func deserialize(data: Dictionary) -> void:
	instance_id = data.get("iid", "")
	item_id = data.get("id", "")
	count = data.get("cnt", 1)
	durability = data.get("dur", -1.0)
	max_durability = data.get("mdur", -1.0)
	acquired_source = data.get("src", "")
	acquired_time = data.get("time", 0)
	locked = data.get("lock", false)   # 旧档无 lock 字段默认 false，向后兼容
	is_new = false
