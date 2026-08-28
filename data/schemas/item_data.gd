# data/schemas/item_data.gd
# 物品静态数据 Resource：可在编辑器中直接创建 .tres
# 与 data/configs/items/*.json 字段对应；运行时由 ConfigManager 读取 JSON，编辑器内用本 Resource

extends Resource
class_name ItemData

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var type: int = 0            # ItemEnums.ItemType
@export var rarity: int = 0         # ItemEnums.ItemRarity
@export var icon_path: String = ""
@export var max_stack: int = 1
@export var weight: float = 0.0
@export var price: int = 0
@export var flags: int = 0          # ItemEnums.ItemFlag 位标志

func has_flag(flag: int) -> bool:
	return (flags & flag) != 0

func is_key_item() -> bool:
	return has_flag(ItemEnums.ItemFlag.KEY_ITEM)
