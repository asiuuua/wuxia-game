#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dep_graph.py —— Dependency Graph 统一门面（Phase 5，施工图 §9 硬约束 #3）

双图分离，禁止混用：
  · Content Graph（数据实体层）：ref_index.py 核心，实体级 impact / 反向 / 环检测
  · Code Graph（代码层）：scan_deps.py 核心，文件级 impact / 反向

命名空间化 API：
  content_impact(kind, eid) / content_reverse(kind, eid) / content_cycles() / content_build()
  code_scan() / code_impact(path) / code_reverse(path)

用法：
  python tools/dep_graph.py --content-impact npc npc_001
  python tools/dep_graph.py --content-reverse dialog dlg_001
  python tools/dep_graph.py --content-cycles
  python tools/dep_graph.py --code-impact autoload/ConfigManager.gd
  python tools/dep_graph.py --code-reverse autoload/ConfigManager.gd
  python tools/dep_graph.py --json --content-impact npc npc_001
"""
import os
import sys
import json
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# ---- Content Graph（数据实体层）----
import ref_index


def content_impact(kind, eid, root=None):
    """Content Graph 影响分析：改 kind/eid 会影响哪些实体（可传递反向）。
    返回 {kind: [ids...]}。"""
    return ref_index.impact(kind, eid, root=root)


def content_reverse(kind, eid, root=None, transitive=True):
    """Content Graph 反向依赖。transitive=True 传递，False 仅一阶。
    返回 {kind: [ids...]}。"""
    if transitive:
        return ref_index.transitive_reverse(kind, eid, root=root)
    # 一阶：用 reverse_dependencies 但按 from_id 的 kind 分组
    who = ref_index.reverse_dependencies(eid, root=root)
    defs, _refs = ref_index.build(root=root)
    result = {}
    for k, f, _fp in who:
        if k == kind:
            fk = ref_index._kind_of_id(f, defs)
            if fk:
                result.setdefault(fk, set()).add(f)
    return {k: sorted(v) for k, v in result.items()}


def content_cycles(root=None):
    """Content Graph 环检测。返回 [[(kind, id), ...], ...]。"""
    return ref_index.find_cycles(root=root)


def content_build(root=None):
    """Content Graph 构建（透传 ref_index.build）。返回 (defs, refs)。"""
    return ref_index.build(root=root)


# ---- Code Graph（代码层）----
sys.path.insert(0, os.path.join(HERE, "desktop_studio"))
import scan_deps  # noqa: E402


def code_scan(root=None):
    """Code Graph 全量扫描（透传 scan_deps.scan）。返回报告 dict。"""
    return scan_deps.scan(root or ROOT)


def code_impact(file_path, root=None):
    """Code Graph 影响分析（正向可传递）：改 file_path 会影响哪些文件。
    返回 [path...]（res:// 格式，去重排序）。"""
    return scan_deps.impact_of_file(file_path, root=root or ROOT)


def code_reverse(file_path, root=None):
    """Code Graph 反向依赖（可传递）：谁引用了 file_path。
    返回 [path...]（res:// 格式，去重排序）。"""
    return scan_deps.reverse_deps_of_file(file_path, root=root or ROOT)


# ---- CLI ----
def main():
    ap = argparse.ArgumentParser(description="Dependency Graph 统一门面（Content / Code 双图分离）")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--content-impact", nargs=2, metavar=("KIND", "ID"),
                    help="Content Graph 影响分析：改 KIND/ID 会影响什么")
    ap.add_argument("--content-reverse", nargs=2, metavar=("KIND", "ID"),
                    help="Content Graph 反向依赖：谁引用了 KIND/ID")
    ap.add_argument("--content-cycles", action="store_true",
                    help="Content Graph 环检测")
    ap.add_argument("--code-impact", metavar="PATH",
                    help="Code Graph 影响分析：改 PATH 文件会影响什么")
    ap.add_argument("--code-reverse", metavar="PATH",
                    help="Code Graph 反向依赖：谁引用了 PATH")
    ap.add_argument("--json", action="store_true", help="输出 JSON 格式")
    args = ap.parse_args()

    result = None
    label = ""
    if args.content_impact:
        kind, eid = args.content_impact
        result = content_impact(kind, eid, root=args.root)
        label = "Content Impact: %s/%s" % (kind, eid)
    elif args.content_reverse:
        kind, eid = args.content_reverse
        result = content_reverse(kind, eid, root=args.root)
        label = "Content Reverse: %s/%s" % (kind, eid)
    elif args.content_cycles:
        result = content_cycles(root=args.root)
        label = "Content Cycles: %d 个环" % len(result)
    elif args.code_impact:
        result = code_impact(args.code_impact, root=args.root)
        label = "Code Impact: %s（影响 %d 个文件）" % (args.code_impact, len(result))
    elif args.code_reverse:
        result = code_reverse(args.code_reverse, root=args.root)
        label = "Code Reverse: %s（被 %d 个文件引用）" % (args.code_reverse, len(result))
    else:
        ap.print_help()
        return 0

    if args.json:
        # cycle 是 tuple 列表，转 list 方便 JSON
        if result and isinstance(result, list) and result and isinstance(result[0], list):
            json_result = [[list(x) for x in c] for c in result]
        else:
            json_result = result
        print(json.dumps(json_result, ensure_ascii=False, indent=2))
    else:
        print("═══ %s ═══" % label)
        if isinstance(result, dict):
            for k, v in sorted(result.items()):
                print("  %s: %s" % (k, v))
        elif isinstance(result, list):
            if result and isinstance(result[0], list):
                for i, c in enumerate(result[:10]):
                    print("  环 %d: %s" % (i + 1, " → ".join("%s/%s" % x for x in c)))
                if len(result) > 10:
                    print("  ... 共 %d 个" % len(result))
            else:
                for item in result:
                    print("  " + item)
    return 0


if __name__ == "__main__":
    sys.exit(main())
