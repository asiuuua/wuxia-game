# tests/unit/test_bond_service.gd
# 结缘系统 M1 单元测试：好感度等级边界 / 送礼反应 / 次数衰减 / 好感度事件 / 存档往返
# 运行：Godot_4.7.2_console --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn
# 框架：继承 TestBase，test_* 方法；断言用 expect / expect_eq(int,int,msg)

extends TestBase

# 用例隔离：每个 test 前重置结缘与背包，避免相互污染
func before_each() -> void:
	GameManager.bond_service.reset()
	GameManager.inventory_service.reset()

## 结缘服务应已装配进 GameManager
func test_service_wired() -> void:
	expect(GameManager.bond_service != null, "bond_service 应已装配")
	expect(ConfigManager.has_relation("npc_su_waner"), "样例 NPC 苏婉儿应已加载")

## 好感度等级归段与 100 上限夹紧
func test_affection_level_boundaries() -> void:
	var bs = GameManager.bond_service
	bs.add_affection("npc_su_waner", 19, "test")
	expect_eq(bs.get_affection_level("npc_su_waner"), BondEnums.AffectionLevel.STRANGER, "19 应为陌生")
	bs.add_affection("npc_su_waner", 1, "test")
	expect_eq(bs.get_affection_level("npc_su_waner"), BondEnums.AffectionLevel.ACQUAINTANCE, "20 应为相识")
	bs.add_affection("npc_su_waner", 20, "test")
	expect_eq(bs.get_affection_level("npc_su_waner"), BondEnums.AffectionLevel.FRIENDLY, "40 应为友善")
	bs.add_affection("npc_su_waner", 20, "test")
	expect_eq(bs.get_affection_level("npc_su_waner"), BondEnums.AffectionLevel.CLOSE, "60 应为亲密")
	bs.add_affection("npc_su_waner", 20, "test")
	expect_eq(bs.get_affection_level("npc_su_waner"), BondEnums.AffectionLevel.LOVED, "80 应为挚爱")
	bs.add_affection("npc_su_waner", 20, "test")
	expect_eq(bs.get_affection_level("npc_su_waner"), BondEnums.AffectionLevel.DEVOTED, "100 应为倾心")
	bs.add_affection("npc_su_waner", 50, "test")
	expect_eq(bs.get_affection("npc_su_waner"), 100, "好感度应夹紧在 100")

## 送礼反应分类（喜爱/喜欢/讨厌/平淡）
func test_gift_reaction_categories() -> void:
	var bs = GameManager.bond_service
	expect_eq(bs.get_gift_reaction("npc_su_waner", "pill_heal_dahuang_001"), BondEnums.GiftReaction.LOVED, "大还丹应为喜爱")
	expect_eq(bs.get_gift_reaction("npc_su_waner", "pill_heal_xiaohuan_001"), BondEnums.GiftReaction.LIKED, "小还丹应为喜欢")
	expect_eq(bs.get_gift_reaction("npc_su_waner", "material_ore_001"), BondEnums.GiftReaction.DISLIKED, "精铁矿石应为讨厌")
	expect_eq(bs.get_gift_reaction("npc_su_waner", "pill_mp_huixue_001"), BondEnums.GiftReaction.NEUTRAL, "回血丹应为平淡")

## 喜爱礼物：+20 好感并消耗 1 个物品
func test_give_gift_loved() -> void:
	var bs = GameManager.bond_service
	var inv = GameManager.inventory_service
	expect(inv.add_item("pill_heal_dahuang_001", 1, "test"), "添加喜爱物应成功")
	var iid: String = _first_iid("pill_heal_dahuang_001")
	expect(iid != "", "应能取到实例 iid")
	var before: int = bs.get_affection("npc_su_waner")
	var res: Dictionary = bs.give_gift("npc_su_waner", iid)
	expect(res.get("ok", false), "送礼应成功")
	expect_eq(int(res.get("reaction", -1)), BondEnums.GiftReaction.LOVED, "反应应为喜爱")
	expect_eq(int(res.get("affection_gain", 0)), 20, "喜爱应 +20 好感")
	expect_eq(bs.get_affection("npc_su_waner"), before + 20, "好感度应增加 20")
	expect_eq(inv.get_item_count("pill_heal_dahuang_001"), 0, "背包中应少 1")

## 讨厌礼物：-5 好感并广播 bond_gift_disliked
func test_give_gift_disliked() -> void:
	var bs = GameManager.bond_service
	var inv = GameManager.inventory_service
	expect(inv.add_item("material_ore_001", 1, "test"), "添加讨厌物应成功")
	var iid: String = _first_iid("material_ore_001")
	# 用字典盒子捕获信号（GDScript lambda 捕获的图元变量赋值不回写外层，dict 引用可可靠回传）
	var caught := {"v": false}
	var cb := func(_n: String, _i: String): caught["v"] = true
	EventBus.bond_gift_disliked.connect(cb)
	var res: Dictionary = bs.give_gift("npc_su_waner", iid)
	EventBus.bond_gift_disliked.disconnect(cb)
	expect(res.get("ok", false), "送礼应成功")
	expect_eq(int(res.get("affection_gain", 0)), -5, "讨厌应 -5 好感")
	expect(caught["v"], "应广播 bond_gift_disliked")

## 送礼次数衰减：前 6 次 +3，第 7 次起减半为 +1
func test_gift_count_decay() -> void:
	var bs = GameManager.bond_service
	var inv = GameManager.inventory_service
	expect(inv.add_item("pill_mp_huixue_001", 10, "test"), "添加中性物应成功")
	var iid: String = _first_iid("pill_mp_huixue_001")
	for i in range(6):
		var r: Dictionary = bs.give_gift("npc_su_waner", iid)
		expect_eq(int(r.get("affection_gain", 0)), 3, "第%d次应为+3" % (i + 1))
	var r7: Dictionary = bs.give_gift("npc_su_waner", iid)
	expect_eq(int(r7.get("affection_gain", 0)), 1, "第7次应衰减为+1")

## 好感度事件触发（阈值 40 / 80），奖励物品与奖励好感
func test_affection_event_triggered() -> void:
	var bs = GameManager.bond_service
	var inv = GameManager.inventory_service
	bs.add_affection("npc_su_waner", 40, "test")
	expect(bs.get_unlocked_dialogues("npc_su_waner").has("ev_su_friendly_001"), "阈值40应触发友好事件")
	var before_item: int = inv.get_item_count("pill_heal_dahuang_001")
	bs.add_affection("npc_su_waner", 40, "test")  # 40 -> 80 触发挚爱事件
	expect(bs.get_unlocked_dialogues("npc_su_waner").has("ev_su_loved_001"), "阈值80应触发挚爱事件")
	expect_eq(inv.get_item_count("pill_heal_dahuang_001"), before_item + 1, "挚爱事件应发放奖励物品")
	expect_eq(bs.get_affection("npc_su_waner"), 85, "80触发奖励好感后应到85")

## 存档往返：好感度与已触发事件应还原
func test_save_roundtrip() -> void:
	var bs = GameManager.bond_service
	bs.add_affection("npc_su_waner", 40, "test")  # 触发友好事件
	var data: Dictionary = bs.save()
	bs.reset()
	bs.load(data)
	expect_eq(bs.get_affection("npc_su_waner"), 40, "好感度应还原")
	expect(bs.get_unlocked_dialogues("npc_su_waner").has("ev_su_friendly_001"), "已触发事件应还原")

## 未知 NPC / 失败不应消耗物品
func test_give_gift_unknown_npc() -> void:
	var bs = GameManager.bond_service
	var inv = GameManager.inventory_service
	expect(inv.add_item("pill_heal_xiaohuan_001", 1, "test"), "添加物品应成功")
	var iid: String = _first_iid("pill_heal_xiaohuan_001")
	var res: Dictionary = bs.give_gift("npc_not_exist", iid)
	expect(not res.get("ok", true), "未知NPC送礼应失败")
	expect_eq(inv.get_item_count("pill_heal_xiaohuan_001"), 1, "失败不应消耗物品")

## 工具：扫描三栏取某 item_id 的首个实例 iid（测试可窥背包内部）
func _first_iid(item_id: String) -> String:
	var inv = GameManager.inventory_service
	for bag in [inv.main_slots, inv.material_slots, inv.quest_slots]:
		for inst in bag:
			if inst != null and inst.item_id == item_id:
				return inst.instance_id
	return ""
