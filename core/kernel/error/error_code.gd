# core/kernel/error/error_code.gd
# Kernel 契约（02 图 §3.1）：机器可识别错误码常量表。
# 铁律（01 §83）：禁止依赖中文错误字符串作为业务判断依据。
#       业务分支只能比较 ErrorCode 常量，永远不得比较 message（K-R11）。
# 新增错误码必须：① 登记进 Contract Registry ② 升 CONTRACT 版本 ③ 补 Contract Test。

class_name ErrorCode
extends RefCounted

const NONE: StringName                        = &"ERR_NONE"
const ITEM_NOT_FOUND: StringName              = &"ERR_ITEM_NOT_FOUND"
const INSUFFICIENT_FUNDS: StringName          = &"ERR_INSUFFICIENT_FUNDS"
const INSUFFICIENT_CAPACITY: StringName       = &"ERR_INSUFFICIENT_CAPACITY"
const INVALID_TARGET: StringName              = &"ERR_INVALID_TARGET"
const QUEST_NOT_AVAILABLE: StringName         = &"ERR_QUEST_NOT_AVAILABLE"
const REQUIREMENT_NOT_MET: StringName         = &"ERR_REQUIREMENT_NOT_MET"
const INVALID_STATE: StringName               = &"ERR_INVALID_STATE"
const MODULE_DEPENDENCY: StringName           = &"ERR_MODULE_DEPENDENCY"
const PRECHECK_FAILED: StringName             = &"ERR_PRECHECK_FAILED"
const INVARIANT_VIOLATION: StringName         = &"ERR_INVARIANT_VIOLATION"
const TRANSACTION_ROLLBACK_FAILED: StringName = &"ERR_TRANSACTION_ROLLBACK_FAILED"
const RECOVERY_REQUIRED: StringName           = &"ERR_TRANSACTION_RECOVERY_REQUIRED"
const CONTENT_REFERENCE_MISSING: StringName   = &"ERR_CONTENT_REFERENCE_MISSING"
const REPOSITORY_UNAVAILABLE: StringName      = &"ERR_REPOSITORY_UNAVAILABLE"
