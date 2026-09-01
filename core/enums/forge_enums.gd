# core/enums/forge_enums.gd
# 锻造系统枚举（Phase 2 系统填充 · 契约层）
# 与 alchemy_enums 类似，但产出任意装备/道具而非仅丹药

extends RefCounted
class_name ForgeEnums

## 锻造结果（业务层据此决定 emit 哪个 notify）
enum ForgeResult {
	SUCCESS,                 # 锻造成功
	FAIL_MISSING_MATERIAL,  # 材料不足
	FAIL_LEVEL_TOO_LOW,     # 锻造等级/角色等级不足
	FAIL_UNKNOWN_RECIPE,    # 配方不存在
	FAIL_BAG_FULL,          # 背包已满装不下产出（2026-08-29 背包评审新增，追加于末尾保持兼容）
	FAIL_INVALID_COUNT,     # 锻造数量非法（<=0）
}

## 锻造产物类型（对应装备槽位大类）
enum ForgeType {
	WEAPON,     # 兵器
	ARMOR,      # 护甲
	ACCESSORY,  # 配饰
}
