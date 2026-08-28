# data/schemas/ability_data.gd
# 武学（内功/外功/轻功）静态数据 Resource
# 与 data/configs/abilities/skills.json 字段对应

extends Resource
class_name AbilityData

@export var id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var mp_cost: int = 0
@export var power: int = 0
@export var type: int = 0            # CombatEnums.AbilityType
@export var target: int = 0         # CombatEnums.TargetType
@export var tags: PackedStringArray = []
@export var learned_by_default: bool = false
