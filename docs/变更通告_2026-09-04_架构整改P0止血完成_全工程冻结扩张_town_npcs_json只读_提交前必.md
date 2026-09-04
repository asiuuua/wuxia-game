# 变更通告 2026-09-04 · 架构整改P0止血完成：全工程冻结扩张、town_npcs.json只读、提交前必须过verify_all

> 模块：全工程　改动范围：data/configs/npcs/town_npcs.json(只读留档) / tools/verify_all.py(新增一键验证) / regions/ 区域表(唯一NPC真源)　commit：（待提交后补）

## 变更项
P0止血四件套已落地并提交(2f7fb3b)：①NPC数据唯一真源=regions/<区域>/npcs.json，town_npcs.json 已清空只读留档(.bak备份在)，任何窗口/工具不得再写它(GATE5机器拦截)；②新增一键验证 python tools/verify_all.py(五门禁：headless零错/单测全绿/工程规范/预设红线/双写防线)，改代码或数据后必须全绿才可提交；③工程基线已建立(基线8提交)，此前工作树158项变更已全部分类入库

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
