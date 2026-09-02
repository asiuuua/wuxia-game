# tests/unit/test_item_flags.gd
# ItemFlags 工具类单元测试（继承 TestBase，被 run_all.tscn 收录）
# BUG-27 护盾：class_name ItemFlags 原仅被测试引用、运行时未接线，本测试验证其位运算正确性，
# 使其从「死代码」变为「有单元测试覆盖的可选工具类」。

extends TestBase

func test_item_flags_single_bits() -> void:
	expect(ItemFlags.is_discardable(1), "DISCARDABLE=1 应识别")
	expect(ItemFlags.is_sellable(2), "SELLABLE=2 应识别")
	expect(ItemFlags.is_tradeable(4), "TRADEABLE=4 应识别")
	expect(ItemFlags.is_key_item(8), "KEY_ITEM=8 应识别")
	expect(ItemFlags.is_stackable(16), "STACKABLE=16 应识别")
	expect(ItemFlags.is_consumable(32), "CONSUMABLE=32 应识别")
	expect(ItemFlags.is_equippable(64), "EQUIPPABLE=64 应识别")

func test_item_flags_combined() -> void:
	var f: int = ItemFlags.SELLABLE | ItemFlags.STACKABLE  # 2 | 16 = 18
	expect(ItemFlags.is_sellable(f), "组合含 SELLABLE")
	expect(ItemFlags.is_stackable(f), "组合含 STACKABLE")
	expect(not ItemFlags.is_discardable(f), "组合不含 DISCARDABLE")
	expect(not ItemFlags.is_equippable(f), "组合不含 EQUIPPABLE")

func test_item_flags_zero_and_overlap() -> void:
	expect(not ItemFlags.is_sellable(0), "0 标志无任何位")
	var g: int = ItemFlags.SELLABLE | ItemFlags.TRADEABLE | ItemFlags.EQUIPPABLE  # 2|4|64=70
	expect_eq(int(ItemFlags.is_sellable(g)), 1, "多组合 SELLABLE 真")
	expect_eq(int(ItemFlags.is_tradeable(g)), 1, "多组合 TRADEABLE 真")
	expect_eq(int(ItemFlags.is_equippable(g)), 1, "多组合 EQUIPPABLE 真")
