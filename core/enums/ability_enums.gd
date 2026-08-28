# core/enums/ability_enums.gd
# 武学相关枚举（内功/外功/轻功/绝技）

extends RefCounted
class_name AbilityEnums

enum AbilityType { UNKNOWN, EXTERNAL, INTERNAL, LIGHT, SPECIAL }
enum AbilityGrade { BASIC, ADVANCED, ULTIMATE, DIVINE }
enum WeaponType { NONE, SWORD, BLADE, STAFF, FIST, SPEAR, WHIP, CLIFF }
enum InternalSlot { MAIN, SUB }
