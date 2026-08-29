# core/item_flags.gd
# ItemFlags 辅助静态类：消除裸 (flags & 16) 位运算判断，提升可读性（清理债，PRD §4.1）
# 调用方可选使用，不强制替换既有判断。flags 取自物品配置 data.get("flags", 0)
# 例：if ItemFlags.is_discardable(item.flags): ...
#
# 注意：掩码常量在此文件自包含定义（与 core/enums/item_enums.gd 的 ItemFlag 枚举值对齐），
# 不跨脚本引用枚举，避免 Godot 4 class_name 依赖图在 autoload 编译期的注册顺序问题。

extends RefCounted
class_name ItemFlags

const DISCARDABLE := 1
const SELLABLE := 2
const TRADEABLE := 4
const KEY_ITEM := 8
const STACKABLE := 16
const CONSUMABLE := 32
const EQUIPPABLE := 64

static func is_discardable(flags: int) -> bool:
	return (flags & DISCARDABLE) != 0

static func is_sellable(flags: int) -> bool:
	return (flags & SELLABLE) != 0

static func is_tradeable(flags: int) -> bool:
	return (flags & TRADEABLE) != 0

static func is_key_item(flags: int) -> bool:
	return (flags & KEY_ITEM) != 0

static func is_stackable(flags: int) -> bool:
	return (flags & STACKABLE) != 0

static func is_consumable(flags: int) -> bool:
	return (flags & CONSUMABLE) != 0

static func is_equippable(flags: int) -> bool:
	return (flags & EQUIPPABLE) != 0
