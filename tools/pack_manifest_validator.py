# -*- coding: utf-8 -*-
"""pack_manifest_validator.py — 03 图 Content Pack 契约校验器（物理槽 GATE06，2026-09-06 基座上线）

覆盖 Enforcement（03 图 §8 §6.2 Manifest 契约）：
  C-R14  Pack manifest 必填字段完整（FATAL）：
         id / version(三段 SemVer) / minimum_game_version(三段) / dependencies(数组) / content(对象)。
  C-R15  Pack 依赖可解析、无循环（FATAL）：dependencies 图 DFS 找环；依赖缺失即拒绝。

扫描面（ADR-0003 目录迁移延 Phase5，content/ 目录未建前先扫过渡位）：
  · data/configs/**/manifest.json（过渡位）
  · content/manifests/**/*.json（目标位，Phase5 启用）
当前无 manifest 实例 → 通报「C-R14/C-R15 基座在位、零实例」判绿（基座先行，Phase5 目录
迁移后首个 manifest 落地即自动纳管——AI 不自决扩大解释，本工具只执行施工图既定规则）。
用法: python tools/pack_manifest_validator.py   （退出码 0=通过 1=违规）
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

SEMVER3 = re.compile(r"^\d+\.\d+\.\d+$")
REQUIRED = ["id", "version", "minimum_game_version", "dependencies", "content"]


def find_manifests():
    out = []
    transitional = os.path.join(ROOT, "data", "configs")
    for dirpath, _dirs, files in os.walk(transitional):
        if "manifest.json" in files:
            out.append(os.path.relpath(os.path.join(dirpath, "manifest.json"), ROOT).replace(os.sep, "/"))
    target = os.path.join(ROOT, "content", "manifests")
    if os.path.isdir(target):
        for dirpath, _dirs, files in os.walk(target):
            for fn in files:
                if fn.endswith(".json"):
                    out.append(os.path.relpath(os.path.join(dirpath, fn), ROOT).replace(os.sep, "/"))
    return sorted(set(out))


def main():
    manifests = find_manifests()
    violations = []
    edges = {}   # pack_id -> [dep_id,...]（C-R15 环检测）

    for rel in manifests:
        try:
            m = json.load(open(os.path.join(ROOT, rel), encoding="utf-8"))
        except Exception as e:
            violations.append(("C-R14", rel, "JSON 解析失败: %s" % e))
            continue
        for k in REQUIRED:
            if k not in m:
                violations.append(("C-R14", rel, "必填字段缺失: %s（03图§6.2 Manifest 契约）" % k))
        if not SEMVER3.match(str(m.get("version", ""))):
            violations.append(("C-R14", rel, "version=%r 非三段 SemVer" % m.get("version")))
        if not SEMVER3.match(str(m.get("minimum_game_version", ""))):
            violations.append(("C-R14", rel, "minimum_game_version=%r 非三段 SemVer" % m.get("minimum_game_version")))
        deps = m.get("dependencies")
        if not isinstance(deps, list):
            violations.append(("C-R14", rel, "dependencies 必须为数组"))
        elif isinstance(m.get("id"), str):
            edges[m["id"]] = deps
        # 依赖可解析（C-R15 前半）：本扫描面内须能找到依赖包（相对 data/configs 过渡位）
        if isinstance(deps, list):
            known = set(edges) | {os.path.splitext(os.path.basename(rel))[0] for rel in manifests}
            for d in deps:
                if d not in known:
                    violations.append(("C-R15", rel, "依赖包不可解析: %s" % d))

    # C-R15 环检测（DFS 三色标记）
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {k: WHITE for k in edges}

    def dfs(u, path):
        color[u] = GRAY
        for v in edges.get(u, []):
            if v not in edges:
                continue
            if color.get(v) == GRAY:
                violations.append(("C-R15", u, "依赖环: %s → %s" % (" → ".join(path + [u]), v)))
            elif color.get(v) == WHITE:
                dfs(v, path + [u])
        color[u] = BLACK

    for k in list(edges):
        if color.get(k) == WHITE:
            dfs(k, [])

    print("pack_manifest_validator · 03图 C-R14/C-R15（GATE06）")
    if not manifests:
        print("  manifest 实例: 0（ADR-0003 目录迁移延 Phase5）—— C-R14/C-R15 基座在位，Phase5 首个 manifest 落地即自动纳管")
    else:
        print("  manifest 实例: %d" % len(manifests))
        for rel in manifests:
            print("    - " + rel)
    if violations:
        for rule, f, ev in violations:
            print("  ✗ [%s] %s — %s" % (rule, f, ev))
        print("════ 结论：✗ %d 项违规 ════" % len(violations))
        sys.exit(1)
    print("════ 结论：✓ 通过（必填字段 / 三段版本 / 依赖可解析无环）════")
    sys.exit(0)


if __name__ == "__main__":
    main()
