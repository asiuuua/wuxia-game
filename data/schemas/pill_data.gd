# data/schemas/pill_data.gd
# 丹药静态数据 Resource（消耗类物品的扩展属性）

extends Resource
class_name PillData

@export var heal_hp: int = 0
@export var heal_mp: int = 0
@export var buff_id: String = ""
