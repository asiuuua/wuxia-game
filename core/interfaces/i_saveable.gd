# core/interfaces/i_saveable.gd
# 存档接口（抽象基类）：实现本接口的对象可被 SaveManager 统一存档
# 注：GDScript 4.x 无 implements 关键字，以继承抽象基类方式实现接口契约

extends RefCounted
class_name ISaveable

func get_save_key() -> String:
	push_error("ISaveable.get_save_key() 未实现")
	return "default"

## 读档依赖声明（13图 SV-4/P-S4）：本模块 load() 前必须先完成加载的模块 key 清单。
## 无依赖者省缺（默认空数组）；禁隐式注册顺序依赖；加载顺序 = 依赖拓扑排序。
func get_load_after() -> Array[String]:
	return []

func save() -> Dictionary:
	push_error("ISaveable.save() 未实现")
	return {}

func load(_data: Dictionary) -> void:
	push_error("ISaveable.load() 未实现")
