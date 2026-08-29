# data/schemas/item_data.gd
# 物品静态数据 Resource：可在编辑器中直接创建 .tres
# 与 data/configs/items/*.json 字段对应；运行时由 ConfigManager 读取 JSON，编辑器内用本 Resource

extends Resource
class_name ItemData

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var type: String = ""       # 与运行时/JSON 字符串契约一致（"weapon"/"pill"/"material"/...）；编辑器模板不再用 int 枚举，避免双真源漂移（P2-6 修复）
@export var rarity: String = ""     # 与运行时/JSON 字符串契约一致（"common"/"uncommon"/...）
@export var icon_path: String = ""
@export var max_stack: int = 1
@export var weight: float = 0.0
@export var price: int = 0
@export var flags: int = 0          # ItemEnums.ItemFlag 位标志（位掩码，与字符串 type/rarity 解耦）

func has_flag(flag: int) -> bool:
	return (flags & flag) != 0

func is_key_item() -> bool:
	return has_flag(ItemEnums.ItemFlag.KEY_ITEM)
