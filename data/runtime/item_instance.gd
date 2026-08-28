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

func serialize() -> Dictionary:
	return {
		"iid": instance_id, "id": item_id, "cnt": count,
		"dur": durability, "mdur": max_durability,
		"src": acquired_source, "time": acquired_time,
	}

func deserialize(data: Dictionary) -> void:
	instance_id = data.get("iid", "")
	item_id = data.get("id", "")
	count = data.get("cnt", 1)
	durability = data.get("dur", -1.0)
	max_durability = data.get("mdur", -1.0)
	acquired_source = data.get("src", "")
	acquired_time = data.get("time", 0)
	is_new = false
