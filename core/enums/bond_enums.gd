# core/enums/bond_enums.gd
# 结缘系统枚举（模块18 · M1：好感度/送礼/好感度事件；婚礼/结义/师徒为 M2+ 前向兼容字段）
# 风格对齐 sect_enums.gd：extends RefCounted + class_name，绝不用 implements

extends RefCounted
class_name BondEnums

## 性别（NPC 关系数据用）
enum Gender {
	MALE,    # 男
	FEMALE,  # 女
}

## 好感度等级（由好感度数值归段，见 BondService._level_of）
enum AffectionLevel {
	STRANGER,      # 0-19   陌生
	ACQUAINTANCE,  # 20-39  相识
	FRIENDLY,      # 40-59  友善
	CLOSE,         # 60-79  亲密
	LOVED,         # 80-99  挚爱
	DEVOTED,       # 100    倾心
}

## 好感度事件类型（relations.json 的 affection_events[].event_type）
enum AffectionEventType {
	DIALOGUE,  # 触发专属对话
	QUEST,     # 触发专属任务
	SCENE,    # 触发场景/剧情
	GIFT,     # 送礼达成
}

## 配偶心情（M2+ 婚后互动用，前向兼容）
enum BondMood {
	NEUTRAL,
	HAPPY,
	SAD,
	ANGRY,
}

## 婚礼类型（M2+ 婚礼流程用，前向兼容）
enum WeddingType {
	SIMPLE,   # 简单
	NORMAL,   # 普通
	GRAND,    # 隆重
}

## 结缘阶段（M2+ 婚姻流程用，前向兼容）
enum RomanceStage {
	COURTING,   # 追求
	ENGAGED,    # 订婚
	PREPARING,  # 筹备
	WEDDING,    # 婚礼
	MARRIED,    # 已婚
}

## 关系互动动作类型（互动日志记录用）
enum BondActionType {
	GIFT,
	DIALOGUE,
	DATE,
	BATTLE,
	EVENT,
	MARRY,
	DIVORCE,
	INTERACT,  # 其它好感度变动（内部归类）
	INTIMATE,  # 寝欢（子嗣预留）
}

## 送礼反应（give_gift 返回值 reaction 字段）
enum GiftReaction {
	NEUTRAL,   # 普通
	LIKED,     # 喜欢
	LOVED,     # 喜爱
	DISLIKED,  # 讨厌
}

## 中文名（UI 直接显示，不硬编码在调用方）
const AFFECTION_LEVEL_NAMES := ["陌生", "相识", "友善", "亲密", "挚爱", "倾心"]
const GENDER_NAMES := ["男", "女"]
const GIFT_REACTION_NAMES := ["平淡", "喜欢", "喜爱", "讨厌"]
const ROMANCE_STAGE_NAMES := ["追求", "订婚", "筹备", "婚礼", "已婚"]

## 取好感度等级中文名（越界回退空串）
static func affection_level_name(level: int) -> String:
	if level < 0 or level >= AFFECTION_LEVEL_NAMES.size():
		return ""
	return AFFECTION_LEVEL_NAMES[level]

## 取性别中文名
static func gender_name(g: int) -> String:
	if g < 0 or g >= GENDER_NAMES.size():
		return ""
	return GENDER_NAMES[g]

## 取送礼反应中文名
static func gift_reaction_name(r: int) -> String:
	if r < 0 or r >= GIFT_REACTION_NAMES.size():
		return ""
	return GIFT_REACTION_NAMES[r]

## 取姻缘阶段中文名
static func romance_stage_name(stage: int) -> String:
	if stage < 0 or stage >= ROMANCE_STAGE_NAMES.size():
		return ""
	return ROMANCE_STAGE_NAMES[stage]

## 婚礼典礼阶段（M3：婚礼演出用，前向兼容）
enum WeddingStage {
	NONE,        # 未举办
	PREPARING,  # 筹备中
	CEREMONY,   # 典礼进行
	COMPLETED,  # 已完成
}

## 关系种类（M3：姻缘面板统一归类展示）
enum BondRelationKind {
	ROMANCE,    # 姻缘/配偶
	SWORN,      # 结义
	MASTER,     # 师徒
}

## 婚礼阶段中文名
const WEDDING_STAGE_NAMES := ["未举办", "筹备中", "典礼中", "已完成"]

## 取婚礼阶段中文名
static func wedding_stage_name(stage: int) -> String:
	if stage < 0 or stage >= WEDDING_STAGE_NAMES.size():
		return ""
	return WEDDING_STAGE_NAMES[stage]

## 婚礼类型中文名 -> 枚举值（relations.json 的 romance.wedding_type 字符串转 int）
static func wedding_type_from_name(name: String) -> int:
	match name:
		"SIMPLE":
			return WeddingType.SIMPLE
		"GRAND":
			return WeddingType.GRAND
		_:
			return WeddingType.NORMAL
