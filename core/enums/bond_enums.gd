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

## 后宅名分（用户 2026-09-03 拍板：大房~七房为妻，依次小妾一~七，其后通房丫鬟；不设配偶数量上限、不加成）。
## 名分仅作称谓与排序用，可自定义重排（见 RomanceService 的 set_spouse_rank）。
enum SpouseRank {
	PRIMARY,      # 大房（首位嫡妻）
	SECOND,       # 二房
	THIRD,        # 三房
	FOURTH,       # 四房
	FIFTH,        # 五房
	SIXTH,        # 六房
	SEVENTH,      # 七房
	CONCUBINE_1,  # 小妾一
	CONCUBINE_2,  # 小妾二
	CONCUBINE_3,  # 小妾三
	CONCUBINE_4,  # 小妾四
	CONCUBINE_5,  # 小妾五
	CONCUBINE_6,  # 小妾六
	CONCUBINE_7,  # 小妾七
	CHAMBERMAID,  # 通房丫鬟（其后无限挂靠）
}

## 子嗣成长阶段（出生 → 成年，按 advance_days 累积天数推进）
enum ChildStage {
	INFANT,    # 婴儿（0~30天）
	TODDLER,   # 幼童（30~180天）
	CHILD,     # 孩童（180~720天）
	TEEN,      # 少年（720~1800天）
	ADULT,     # 成年（1800天+）
}

## 后宅名分中文名（顺序与 SpouseRank 一一对应）
const SPOUSE_RANK_NAMES := [
	"大房", "二房", "三房", "四房", "五房", "六房", "七房",
	"小妾一", "小妾二", "小妾三", "小妾四", "小妾五", "小妾六", "小妾七",
	"通房丫鬟",
]

## 子嗣阶段中文名
const CHILD_STAGE_NAMES := ["婴儿", "幼童", "孩童", "少年", "成年"]

## 按结婚次序取默认名分：第1位大房，2~7为二房~七房，8~14为小妾一~七，其后通房丫鬟。
static func default_rank_for_order(order: int) -> int:
	if order < 0:
		return SpouseRank.CHAMBERMAID
	if order < SpouseRank.CHAMBERMAID:
		return order
	return SpouseRank.CHAMBERMAID

## 取后宅名分中文名（越界回退"通房丫鬟"）
static func spouse_rank_name(rank: int) -> String:
	if rank < 0 or rank >= SPOUSE_RANK_NAMES.size():
		return SPOUSE_RANK_NAMES[SpouseRank.CHAMBERMAID]
	return SPOUSE_RANK_NAMES[rank]

## 取子嗣阶段中文名（越界回退空串）
static func child_stage_name(stage: int) -> String:
	if stage < 0 or stage >= CHILD_STAGE_NAMES.size():
		return ""
	return CHILD_STAGE_NAMES[stage]

## 血缘亲疏（relations.json 亲属关系用）：
## NONE=无亲属关系（可求娶）；SWORN=结义（非血亲，单身/鳏寡可求娶）；MASTER=师徒（非血亲，单身/鳏寡可求娶）。
## BLOOD 及更亲近（父母/子女/兄弟姐妹）为血亲，一律禁婚。
enum KinType {
	NONE,      # 无亲属关系，可登记求娶对象
	SWORN,     # 结义（义兄/义弟/义姐/义妹）
	MASTER,    # 师徒
	PARENT,    # 生身父母（血亲，禁婚）
	CHILD,     # 亲生子女（血亲，禁婚）
	SIBLING,   # 同胞兄弟姐妹（血亲，禁婚）
}

## 是否为不可求娶的血亲（亲缘更近于结义/师徒缘份）
static func is_blood_kin(k: int) -> bool:
	return k == KinType.PARENT or k == KinType.CHILD or k == KinType.SIBLING
