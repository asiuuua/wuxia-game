# core/kernel/identity/entity_id.gd
# Kernel 契约（02 图 §2）：稳定身份。
# 冻结名：KERNEL-CONTRACT v1.2.0（02 图 §13 Freeze 清单）。
# 铁律：ID 永不复用、不表达业务状态、不依赖显示名称、不随语言变化（宪法第 26 节）。
#       Value Object：创建后不可变，无公共 setter（K-R09/K-R10）。

class_name EntityId
extends RefCounted

const SEPARATOR := "_"

var _domain: StringName   # NPC / QUEST / ITEM / ABILITY / DIALOGUE / FACTION / LOCATION / EVENT / STORY
var _serial: String       # 000001

func _init(domain: StringName, serial: String) -> void:
	_domain = domain
	_serial = serial

static func of(domain: StringName, serial: String) -> EntityId:
	return EntityId.new(domain, serial)

## 解析 "NPC_000001"。失败返回 null（调用方必须处理 null，不得假设永远成功）
static func parse(raw: String) -> EntityId:
	if raw == "":
		return null
	var parts := raw.split(SEPARATOR, false)
	if parts.size() != 2:
		return null
	return EntityId.new(StringName(parts[0]), parts[1])

func get_domain() -> StringName:
	return _domain

func get_serial() -> String:
	return _serial

func equals(other: EntityId) -> bool:
	if other == null:
		return false
	return _domain == other.get_domain() and _serial == other.get_serial()

func _to_string() -> String:
	return String(_domain) + SEPARATOR + _serial
