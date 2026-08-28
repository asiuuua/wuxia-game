# core/constants/item_constants.gd
# 物品系统常量

extends RefCounted
class_name ItemConstants

const DEFAULT_MAX_SLOTS := 30
const BASE_MAX_WEIGHT := 50.0
# 负重系数：每点力量额外可携带的重量（数值进常量，便于策划调参）
# 真负重公式：max_weight = BASE_MAX_WEIGHT + strength * STRENGTH_WEIGHT_COEFF
const STRENGTH_WEIGHT_COEFF := 2.5
