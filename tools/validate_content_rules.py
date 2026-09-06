#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""validate_content_rules.py — 构建期规则表校验（05 图 VA-4 双端同一份，C/D1 DoD3）

与运行期（application/content/content_registry.gd load_validation_rules）读同一份
data/configs/content_validation_rules.json——本脚本校验规则表自身合法性（层序冻结/字段完整/
severity 枚举），保证双端消费的结构前提。构建期接入点：verify_all / GATE3 群可后续挂载。
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RULES = os.path.join(ROOT, "data", "configs", "content_validation_rules.json")

REQUIRED_FIELDS = {"rule_code", "severity", "applies", "desc"}
VALID_SEVERITY = {"FATAL", "ERROR", "WARN"}
FROZEN_LAYER_ORDER = [1, 2, 3, 4, 5]   # VA-2 顺序冻结


def main() -> int:
    try:
        with open(RULES, encoding="utf-8") as f:
            rules = json.load(f)
    except (OSError, ValueError) as e:
        print("✗ 规则表不可读/非法 JSON: %s" % e)
        return 1

    problems = []
    layers = rules.get("layers", [])
    if not layers:
        problems.append("缺 layers")
    order = [int(l.get("layer", -1)) for l in layers]
    if order != FROZEN_LAYER_ORDER:
        problems.append("层序违背 VA-2 冻结: %s（应为 %s）" % (order, FROZEN_LAYER_ORDER))

    total_rules = 0
    for l in layers:
        if not l.get("name"):
            problems.append("layer %s 缺 name" % l.get("layer"))
        for r in l.get("rules", []):
            total_rules += 1
            missing = REQUIRED_FIELDS - set(r.keys())
            if missing:
                problems.append("rule %s 缺字段: %s" % (r.get("rule_code", "?"), sorted(missing)))
            if r.get("severity") not in VALID_SEVERITY:
                problems.append("rule %s severity 非法: %s（VA-3 枚举）"
                                % (r.get("rule_code", "?"), r.get("severity")))

    print("content_validation_rules · 构建期规则表校验（VA-4 双端同一份）")
    print("  层 %d / 规则 %d 条" % (len(layers), total_rules))
    if problems:
        for p in problems:
            print("  ✗ " + p)
        print("════ 结论：✗ %d 项 ════" % len(problems))
        return 1
    print("════ 结论：✓ 规则表合法（层序冻结 / 字段完整 / severity 合规）════")
    return 0


if __name__ == "__main__":
    sys.exit(main())
