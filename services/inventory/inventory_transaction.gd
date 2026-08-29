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

## 提交：先预校验（不改状态），再 apply add -> remove -> consume。
## 顺序保障原子性（P1-2 修复）：先 add（占空间/产出），再 remove（扣料）。若产出装不下已被预校验拦截，
## 万一 add 成功而 remove 失败，回滚刚加入的产物，杜绝"扣了料、产物没进"的静默丢料。
## 任一段失败立即返回 false，且已应用的前段会被回滚，确保整体要么全成、要么全不成。
func commit(svc: InventoryService) -> bool:
	var remove_list: Array = []
	var add_list: Array = []
	var consume_list: Array = []
	for op in _ops:
		match op["op"]:
			"remove":
				remove_list.append({ "item_id": op["item_id"], "count": int(op["count"]) })
			"add":
				add_list.append({ "item_id": op["item_id"], "count": int(op["count"]), "source": op.get("source", _source) })
			"consume":
				consume_list.append({ "iid": op["iid"], "count": int(op["count"]) })
	# 预校验（不改动状态）：remove 用非锁定可用量；add 用 can_add；consume 用实例存在性
	for r in remove_list:
		if svc.get_unlocked_count(r["item_id"]) < int(r["count"]):
			GameLogger.warn("InventoryTx", "预校验失败(remove 不足): %s" % r["item_id"])
			return false
	for a in add_list:
		if not svc.can_add(a["item_id"], int(a["count"])):
			GameLogger.warn("InventoryTx", "预校验失败(add 装不下): %s" % a["item_id"])
			return false
	for c in consume_list:
		if svc.get_instance_by_id(c["iid"]) == null:
			GameLogger.warn("InventoryTx", "预校验失败(consume 实例不存在): %s" % c["iid"])
			return false
	# 1) 添加（批量事务，要么全进要么不加）
	if not add_list.is_empty() and not svc.add_items(add_list, _source):
		GameLogger.warn("InventoryTx", "add 段失败")
		return false
	# 2) 移除（批量扣料，尊重锁定，任一不足整体不扣）
	if not remove_list.is_empty() and not svc.try_consume(remove_list):
		# 回滚已加入的产物（按 item_id 反向扣，刚加入物未锁定必可移除）
		for a in add_list:
			svc.remove_item_by_id(a["item_id"], int(a["count"]))
		GameLogger.warn("InventoryTx", "remove 段失败，已回滚 add")
		return false
	# 3) 按实例消耗
	for c in consume_list:
		for i in range(int(c["count"])):
			if not svc.consume_instance(c["iid"]):
				GameLogger.warn("InventoryTx", "consume 段失败(实例耗尽): %s" % c["iid"])
				return false
	return true
