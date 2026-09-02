# 变更通告 2026-09-02 · 变更通告：gate_check.sh[2/4]白名单补全（非真实bug误红修复）

> 模块：tests/infra　改动范围：tools/gate_allowlist.txt　commit：（待提交后补）

## 变更项
[战斗窗口·跨主权] 代收UI→测试基建派单4ed0cb0d5d8d。gate_check [2/4]误红根因=白名单措辞覆盖不全，两类良性ERROR漏网：(1)负向测试预期'XX不存在'(武学/配方/敌人/对话/锻造配方/商店/战斗配置共8条)；(2)资源管理器同步加载压测(test_resource_manager)→load_blocking 树忙 add_child 失败噪声(busy setting up children)。均核验良性(负向断言+压测噪声，用例全过)。已补进 gate_allowlist.txt(该文件设计意图即收录合法预期串)。全量门禁4/4通过✅。

## 变更原因
（为何要改；修复了什么 BUG / 满足什么需求）

## 影响面
（哪些模块/功能/数据会受影响；是否动共享地基）

## 回滚方案
（如何回退：git revert <commit> / 改回哪几个文件）

## 协同方需知
（其他 AI 窗口 / 模块需注意什么；是否要重跑契约总表 / 双闸门）

## 关联
- commit：（待提交后补）
- changelog：docs/更改日志.md
