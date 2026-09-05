# -*- coding: utf-8 -*-
"""region_validator.py — 16 图 CP-R06 三同铁律校验器（物理槽 GATE06，2026-09-06 落地）

三同铁律（16 图 Freeze 清单第 5 项 / CP-3a）：「区域ID = 传送ID = 分片ID」机器化：
  ① _map_index.json regions[].region_id ↔ data/configs/regions/ 分片目录名（双向）
     · 登记无分片目录 = 空壳区域 FATAL
     · 分片目录无登记 = 私搭分片 FATAL
  ② 每个 region 的 connections（传送目标）⊆ 已登记 region_id 集合（悬空传送 FATAL）
  ③ index_file 指向的分片 index.json 存在，且其 region_id 自引用 == 所在区域 ID
     （自引用漂移 = 三同破坏 FATAL）；目录名 == region_id（分片ID 同一性）

用法: python tools/region_validator.py   （退出码 0=通过 1=违规）
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MAP_INDEX = os.path.join(ROOT, "data", "configs", "regions", "_map_index.json")
REGIONS_DIR = os.path.join(ROOT, "data", "configs", "regions")

violations = []
notes = []

# 空壳区域基线（16 图 Phase3~4 内容生产收敛，只减不增）：前瞻性登记、分片未建的区域。
# 与全项目基线范式同构——每生产一个区域分片即从名单删除一条；名单外出现新空壳 = FATAL。
BASELINE = os.path.join(HERE, "region_baseline.json")


def load_baseline():
    if os.path.exists(BASELINE):
        return set(json.load(open(BASELINE, encoding="utf-8")).get("empty_shell", []))
    return set()


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, "/")


def main():
    mi = json.load(open(MAP_INDEX, encoding="utf-8"))
    regions = mi.get("regions", [])
    reg_ids = [str(r.get("region_id", "")) for r in regions]
    reg_set = set(reg_ids)

    # 重复登记（region_id 本身必须唯一）
    dup = sorted({x for x in reg_ids if reg_ids.count(x) > 1})
    for x in dup:
        violations.append(("CP-R06", "_map_index.json", "region_id 重复登记: %s" % x))

    # ① 注册表 ↔ 分片目录 双向一致（空壳区域按基线豁免：前瞻登记分片未建，生产后删条收敛）
    shell_ok = load_baseline()
    dirs = {d for d in os.listdir(REGIONS_DIR)
            if os.path.isdir(os.path.join(REGIONS_DIR, d)) and not d.startswith("_")}
    for x in sorted(reg_set - dirs):
        if x in shell_ok:
            notes.append("空壳区域（基线豁免，待 Phase3~4 生产）: %s" % x)
        else:
            violations.append(("CP-R06", "_map_index.json", "空壳区域（登记无分片目录，基线外零容忍）: %s" % x))
    for x in sorted(dirs - reg_set):
        violations.append(("CP-R06", "regions/%s" % x, "私搭分片（目录无登记，三同破坏）" ))

    # ②③ 逐区域：传送悬空（全员生效）+ index_file 归属 + 分片自引用（分片存在的区域才查）
    for r in regions:
        rid = str(r.get("region_id", ""))
        if not rid:
            violations.append(("CP-R06", "_map_index.json", "region 缺 region_id 字段"))
            continue
        for dst in r.get("connections", []):
            if dst not in reg_set:
                violations.append(("CP-R06", "_map_index.json",
                                   "悬空传送: %s → %s（目标未登记）" % (rid, dst)))
        if rid in shell_ok and rid not in dirs:
            continue   # 空壳区域：无分片可查，index_file/自引用检查随分片生产启用
        idx_file = str(r.get("index_file", ""))
        if not idx_file or not os.path.exists(os.path.join(ROOT, idx_file.replace("res://", ""))):
            violations.append(("CP-R06", rid, "index_file 缺失或不存在: %s" % idx_file))
            continue
        idx = json.load(open(os.path.join(ROOT, idx_file.replace("res://", "")), encoding="utf-8"))
        if str(idx.get("region_id", "")) != rid:
            violations.append(("CP-R06", idx_file,
                               "分片自引用漂移: index.region_id=%r ≠ 注册表 %r（三同破坏）"
                               % (idx.get("region_id"), rid)))
        if os.path.basename(os.path.dirname(idx_file.replace("res://", ""))) != rid:
            violations.append(("CP-R06", idx_file,
                               "index_file 不在同名分片目录下（分片ID 同一性破坏）"))

    print("region_validator · 16图 CP-R06 三同铁律（GATE06）")
    print("  注册区域: %d | 分片目录: %d | 传送边: %d" %
          (len(reg_ids), len(dirs), sum(len(r.get("connections", [])) for r in regions)))
    for n in notes:
        print("  ℹ " + n)
    if violations:
        for rule, f, ev in violations:
            print("  ✗ [%s] %s — %s" % (rule, f, ev))
        print("════ 结论：✗ %d 项违规 ════" % len(violations))
        sys.exit(1)
    print("════ 结论：✓ 通过（注册↔分片双向一致 / 传送零悬空 / 自引用零漂移）════")
    sys.exit(0)


if __name__ == "__main__":
    main()
