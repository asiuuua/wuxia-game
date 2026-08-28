# core/enums/item_enums.gd
# 物品相关枚举

extends RefCounted
class_name ItemEnums

enum ItemType { UNKNOWN, WEAPON, ARMOR, PILL, MATERIAL, QUEST }
enum ItemRarity { COMMON, UNCOMMON, RARE, EPIC, LEGENDARY }
# 位标志（按规范 §2.3，使用 1<<n 语义，避免魔法数字）
enum ItemFlag {
	DISCARDABLE = 1,
	SELLABLE = 2,
	TRADEABLE = 4,
	KEY_ITEM = 8,
	STACKABLE = 16,
	CONSUMABLE = 32,
	EQUIPPABLE = 64,
}
# 货币类型（统一货币系统：铜钱<银两<金子）
enum Currency { COPPER, SILVER, GOLD }
