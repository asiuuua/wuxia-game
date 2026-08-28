# core/enums/sect_enums.gd
# 门派系统枚举（Phase 2 系统填充 · 契约层）

extends RefCounted
class_name SectEnums

## 加入门派结果
enum JoinResult {
	SUCCESS,                  # 加入成功
	FAIL_ALREADY_IN_SECT,     # 已在某门派中
	FAIL_REPUTATION_TOO_LOW,  # 声望不足
	FAIL_UNKNOWN_SECT,        # 门派不存在
}

## 门派阶位（由低到高，对应 sects.json 中 ranks[].rank 字符串）
enum Rank {
	OUTSIDER,  # 外门弟子
	INNER,     # 内门弟子
	CORE,      # 核心弟子
	ELDER,     # 长老
	LEADER,    # 掌门 / 宗主
}
