# application/actor/npc_definition.gd
# 06 图批1 ④（NP-1 四态之一 / NP-4）：NPCDefinition —— 数据驱动静态态。
# 来源：ContentRegistry RegionPack（05 图收编）；本批=契约骨架，区域分片 npcs.json 的
#   完整化与 NPCByRegion 索引点亮归 05 批2~3（06 图 DoD#4）。
# NP-4：display 走键化（LN-G18 / VA5 *_text_id 后缀）；dialog_id/quest_id/battle_id 归
#   Binding（01 §47）；spawn 点保留在 Definition（生成数据，非 Runtime 态）。

class_name NPCDefinition
extends RefCounted

var id: String = ""              # NPC/敌人 ID（过 03 §3.3 形态，A-R08/GATE07）
var display_text_id: String = "" # 显示名键（strings.csv；空=回退裸名，Phase2 键化补齐）
var scene: String = ""           # 区域分片生成过滤字段（§1.1 既有语义）
var spawn_x: float = 0.0
var spawn_y: float = 0.0
var dialog_id: String = ""       # Binding 三件（01 §47；空=无绑定）
var quest_id: String = ""
var battle_id: String = ""


## 从区域分片条目（regions/<rid>/npcs.json 既有键）构建；宽容缺键，id 必填
static func from_dict(d: Dictionary) -> NPCDefinition:
	var def := NPCDefinition.new()
	def.id = str(d.get("id", ""))
	def.display_text_id = str(d.get("display_text_id", d.get("name_text_id", "")))
	def.scene = str(d.get("scene", ""))
	def.spawn_x = float(d.get("pos_x", d.get("x", 0.0)))
	def.spawn_y = float(d.get("pos_y", d.get("y", 0.0)))
	def.dialog_id = str(d.get("dialog_id", ""))
	def.quest_id = str(d.get("quest_id", ""))
	def.battle_id = str(d.get("battle_id", ""))
	return def


func to_dict() -> Dictionary:
	return {
		"id": id,
		"display_text_id": display_text_id,
		"scene": scene,
		"pos_x": spawn_x,
		"pos_y": spawn_y,
		"dialog_id": dialog_id,
		"quest_id": quest_id,
		"battle_id": battle_id,
	}


func spawn_position() -> Vector2:
	return Vector2(spawn_x, spawn_y)
