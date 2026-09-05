# core/kernel/repository/repository.gd
# Kernel 契约（02 图 §8）：仓储契约基类（01 §28）。
# Kernel 只定义「仓储是什么」；具体仓储按实体建，不建 IRepository<T>（01 §10）。
# 具体仓储（NpcRepository 等）属于各模块自己的 contracts/，不属于 Kernel。
# 实现位于 infrastructure/repositories/。Domain 只依赖契约。
# 铁律：禁止 Domain → JSON / Domain → SQLite（01 §28）；存储实现替换时 Domain 0 修改。

@abstract
class_name Repository
extends RefCounted

@abstract func get_repository_id() -> StringName
