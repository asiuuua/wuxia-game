# core/enums/shop_enums.gd
# 商店系统枚举（Phase 2 系统填充 · 契约层）

extends RefCounted
class_name ShopEnums

## 交易方向
enum TradeType {
	BUY,   # 玩家向商店购买
	SELL,  # 玩家向商店出售
}

## 交易结果（业务层据此决定 emit 哪个 notify）
enum TradeResult {
	SUCCESS,            # 交易成功
	FAIL_NO_MONEY,     # 银两不足
	FAIL_NO_STOCK,     # 商店库存不足
	FAIL_NO_ITEM,      # 背包无此物可卖
	FAIL_INVALID,      # 参数非法（数量为0/物品不存在）
	FAIL_BAG_FULL,     # 背包已满（买入预检失败；2026-08-29 背包评审新增，追加于末尾保持兼容）
}
