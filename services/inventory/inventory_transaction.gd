# services/inventory/inventory_transaction.gd
# 批量事务（PRD §4.3 进阶）：收集多步背包操作，commit 时统一应用到 InventoryService。
# 各段独立原子，复用既有已验证事务方法，不重复实现扣料逻辑：
#   - remove：走 try_consume（按 item_id 聚合并校验、尊重锁定、任一不足整体不扣）
#   - add：走 add_items（聚合预检、全部装得下才逐个添加，要么全进要么不加）
#   - consume：走 consume_instance（按实例 ID 逐个消耗，如战斗中按 iid 吃药）
# 用法：
#   var tx := InventoryTransaction.new()
#   tx.add("gold_coin", 50); tx.remove("mat_iron", 3)
#   if tx.commit(InventoryService): print("ok") else: print("事务失败")

extends RefCounted
class_name InventoryTransaction

var _ops: Array = []          # [{ "op": "add"|"remove"|"consume", ... }]
var _source: String = ""

func set_source(source: String) -> void:
	_source = source

## 入队：添加 count 个 item_id（source 可选，缺省用事务级 source）
func add(item_id: String, count: int, source: String = "") -> void:
	_ops.append({ "op": "add", "item_id": item_id, "count": count, "source": source })

## 入队：移除 count 个 item_id（被动扣料，尊重锁定）
func remove(item_id: String, count: int) -> void:
	_ops.append({ "op": "remove", "item_id": item_id, "count": count })

## 入队：按实例 ID 消耗 count 个（如战斗中按 iid 吃药）
func consume(iid: String, count: int = 1) -> void:
	_ops.append({ "op": "consume", "iid": iid, "count": count })

func is_empty() -> bool:
	return _ops.is_empty()

## 提交：顺序 apply remove -> add -> consume，各段独立事务原子。
## 任一段失败立即返回 false（前段已应用的不回滚；调用方应据返回值决定后续流程，失败即中止）
func commit(svc: InventoryService) -> bool:
	# 1) 移除（批量扣料，尊重锁定，任一不足整体不扣）
	var remove_list: Array = []
	for op in _ops:
		if op["op"] == "remove":
			remove_list.append({ "item_id": op["item_id"], "count": int(op["count"]) })
	if not remove_list.is_empty() and not svc.try_consume(remove_list):
		return false
	# 2) 添加（批量事务，要么全进要么不加）
	var add_list: Array = []
	for op in _ops:
		if op["op"] == "add":
			add_list.append({ "item_id": op["item_id"], "count": int(op["count"]), "source": op.get("source", _source) })
	if not add_list.is_empty() and not svc.add_items(add_list, _source):
		return false
	# 3) 按实例消耗
	for op in _ops:
		if op["op"] == "consume":
			for i in range(int(op["count"])):
				if not svc.consume_instance(op["iid"]):
					return false
	return true
