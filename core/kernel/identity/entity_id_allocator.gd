# core/kernel/identity/entity_id_allocator.gd
# Kernel 契约（02 图 identity 域扩展 · 06 图批1 ①）：EntityId 分配器。
# 冻结依据（09 图 §6 ID-1/ID-2/ID-3 + 06 图 §7「EntityId 分配器随 Phase1 Kernel」）：
#   ID-1 单一分配器：全项目所有实例/实体序列的发号必须经此类——iid 成为分配器的一个 domain 序列。
#   ID-2 水位策略：分配器水位本身不入档（可从数据推导）；load 后 bootstrap = max(现存 serial)+1，
#        persisted_hint 只作上界安全垫（覆盖已被消费/装备走、不在「现存」面内的 serial，堵回滚档撞号 P-3）。
#   ID-3 禁再发明：任何模块禁自建 size()+1 / 时间戳 / UUID 序列（07 TX-4 禁令域内重申）。
# 铁律（宪法第 26 节 / 02 图 §2）：ID 永不复用、不表达业务状态、不依赖显示名称、不随语言变化。
# 水位只前进不后退：任何 bootstrap 都取 max，绝不把水位拨回去。

class_name EntityIdAllocator
extends RefCounted

const SERIAL_PAD := 6   # EntityId serial 形态：000001（02 图 §2）

var _watermarks: Dictionary = {}   # domain(StringName) -> 下一个待发序号(int)；分配器自身零持久化状态


## 发一个纯数字序号（iid 形态：<prefix>#<serial> 的 serial 段）
func next_int(domain: StringName) -> int:
	var cur := int(_watermarks.get(domain, 1))
	_watermarks[domain] = cur + 1
	return cur


## 发一个零填充 serial（"000001" 形态，配 EntityId.of 使用）
func next_serial(domain: StringName) -> String:
	return "%0*d" % [SERIAL_PAD, next_int(domain)]


## 发一个完整 EntityId（kernel 身份锚）
func next_entity_id(domain: StringName) -> EntityId:
	return EntityId.of(domain, next_serial(domain))


## 存档恢复（ID-2）：watermark = max(现存 serial + 1 ..., persisted_hint, 旧水位)
## existing_serials：从「现存」数据面推导出的已用序号（untyped Array[int] 逐元素取）
## persisted_hint：旧存档显式记录的「下一个待发号」（若有；只上界保护，不回拨）
func bootstrap(domain: StringName, existing_serials: Array, persisted_hint: int = 0) -> void:
	var hi := watermark(domain)
	for s in existing_serials:
		hi = maxi(hi, int(s) + 1)
	if persisted_hint > 0:
		hi = maxi(hi, persisted_hint)
	_watermarks[domain] = hi


## 只读观察：domain 当前水位（下一个待发号）
func watermark(domain: StringName) -> int:
	return int(_watermarks.get(domain, 1))


## 单域复位（测试/重开档用；生产路径只经 reset_all 或 bootstrap）
func reset_domain(domain: StringName) -> void:
	_watermarks.erase(domain)


## 全域复位
func reset_all() -> void:
	_watermarks.clear()
