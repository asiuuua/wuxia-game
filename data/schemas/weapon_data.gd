# data/schemas/weapon_data.gd
# 兵器静态数据 Resource（装备类物品的扩展属性）

extends Resource
class_name WeaponData

@export var attack: int = 0
@export var durability: int = 100
@export var max_durability: int = 100
@export var speed: float = 1.0
@export var equip_slot: String = "main_hand"
@export var compatible_abilities: PackedStringArray = []
