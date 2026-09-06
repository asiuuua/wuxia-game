# -*- coding: utf-8 -*-
"""registry_audit.py — ST-6 校验器注册表三方对账（15 图批1，D5 2026-09-06）

对账三方：
  ① tools/contract_registry.json（ST-6 声明式注册表）
  ② tools/verify_all.py 的 GATES 字典键（物理槽真源）
  ③ docs/PROJECT_STATUS.md 物理槽状态表（治理真源）
任一不一致 = 对账失败（防纸面门禁/幽灵槽）。
REPORT 模式：当前仅提示不拦（新工具，观察一个迭代后升硬门禁）。
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
REGISTRY = os.path.join(HERE, "contract_registry.json")
VERIFY_ALL = os.path.join(HERE, "verify_all.py")
PROJECT_STATUS = os.path.join(ROOT, "docs", "PROJECT_STATUS.md")


def registry_slots() -> set:
    with open(REGISTRY, encoding="utf-8") as f:
        d = json.load(f)
    # tier=performance 的槽走 --tier 分支（不在默认 GATES 字典），对账排除
    return {int(v["slot"]) for v in d.get("validators", []) if v.get("tier") != "performance"}


def verify_all_slots() -> set:
    with open(VERIFY_ALL, encoding="utf-8") as f:
        src = f.read()
    m = re.search(r"GATES\s*=\s*\{(.*?)\}", src, re.S)
    if not m:
        return set()
    return {int(k) for k in re.findall(r"(\d+)\s*:", m.group(1))}


def project_status_slots() -> set:
    if not os.path.exists(PROJECT_STATUS):
        return set()
    with open(PROJECT_STATUS, encoding="utf-8") as f:
        src = f.read()
    slots = set()
    m = re.search(r"## 物理槽.*?(?=\n## )", src, re.S)
    seg = m.group(0) if m else src
    for k in re.findall(r"^\|\s*GATE(\d+)\s", seg, re.M):
        slots.add(int(k))
    return slots


def perf_tier_slots() -> set:
    """tier=performance 槽（--tier 分支专属，不在默认 GATES）：对账时合法豁免。"""
    with open(REGISTRY, encoding="utf-8") as f:
        d = json.load(f)
    return {int(v["slot"]) for v in d.get("validators", []) if v.get("tier") == "performance"}


def main() -> int:
    reg = registry_slots()
    va = verify_all_slots()
    ps = project_status_slots()
    perf = perf_tier_slots()
    problems = []
    for name, missing in (
        ("注册表有而 verify_all 无槽", reg - va),
        ("verify_all 有槽而注册表未登记", va - reg),
        ("PROJECT_STATUS 缺物理槽行", va - ps),
        ("PROJECT_STATUS 有行而 verify_all 无槽（幽灵状态）", (ps - va) - perf),
    ):
        if missing:
            problems.append("%s: %s" % (name, sorted(missing)))

    print("registry_audit · ST-6 三方对账（注册表 / verify_all / PROJECT_STATUS）")
    print("  槽：注册表 %d ｜ verify_all %d ｜ PROJECT_STATUS %d" % (len(reg), len(va), len(ps)))
    if problems:
        for p in problems:
            print("  ✗ " + p)
        print("════ 结论：✗ 对账失败 %d 类 ════" % len(problems))
        return 1
    print("════ 结论：✓ 三方一致（ST-6 注册表对账通过）════")
    return 0


if __name__ == "__main__":
    sys.exit(main())
