#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scan_deps.py —— Code Graph（代码层依赖图）【Phase 5 双图分离：Code Graph / Content Graph】

扫描工程内全部 .gd，按「五层架构」映射每个文件所属层，提取：
  - class_name（定义的类）
  - extends（继承：类名 或 "res://..." 路径）
  - preload / load("res://...")（资源/脚本引用）
构建 节点(文件) + 边(依赖) 的 Code Graph，输出：
  - JSON 报告（--out 指定；默认打印到 stdout）
  - Mermaid 图（--mermaid 指定输出文件）
并依据「架构铁律：依赖只允许向下」标注**向上依赖违例**（高 layer 依赖低 layer）。

五层（foundation rank 越小越基础/被依赖方）：core < data < services < autoload < scenes < resources/tests/tools
（core 为最基础层，被全员依赖；依赖铁律：只允许「上层依赖更基础的层」，禁止基础层反向依赖上层）。

【与 Content Graph 的关系】（施工图 §9 / 硬约束 #3）：
  · Code Graph = 代码层依赖（本文件，.gd 文件级）
  · Content Graph = 数据实体层依赖（tools/ref_index.py，实体级）
  · 两图分别输出、禁止混用；统一门面见 tools/dep_graph.py

用法：
  python scan_deps.py [--root D:/武侠游戏] [--out deps.json] [--mermaid deps.mmd]
"""
import os, re, sys, json, argparse

# 五层架构（foundation rank：数值越小越「基础/底层/被依赖方」，数值越大越「上层/视图」）
# 依赖铁律：允许「上层依赖更基础的层」(from 依赖 to 时 to 的 rank <= from 的 rank)；
# 违例 = 基础层(低 rank) 反向依赖 上层(高 rank)，例如 core 依赖 scenes、services 依赖 scenes。
LAYERS = ["core", "data", "services", "autoload", "scenes", "resources", "tests", "tools"]
LAYER_RANK = {l: i for i, l in enumerate(LAYERS)}
RANK_OTHER = 99  # 其它目录（既非五层也非 tools）

SKIP_DIRS = {".godot", "addons", "node_modules", ".import", "__pycache__", "dist"}

CLASSNAME_RE = re.compile(r'^\s*class_name\s+([A-Za-z_]\w*)', re.M)
# extends 类名 / extends "res://..." 路径
EXTENDS_NAME_RE = re.compile(r'^\s*extends\s+([A-Za-z_]\w*)', re.M)
EXTENDS_PATH_RE = re.compile(r'extends\s+["\'](res://[^"\']+)["\']')
# preload/load("res://...") 或 ("res://...")（含 const X = preload(...)）
RES_REF_RE = re.compile(r'(?:preload|load)\(\s*["\'](res://[^"\']+)["\']')


def layer_of(path, root):
    rel = os.path.relpath(path, root)
    top = rel.split(os.sep)[0]
    if top in LAYER_RANK:
        return top
    return "other"


def short_res(path):
    return "res://" + path.replace("\\", "/")


def scan(root):
    root = os.path.abspath(root)
    # 1) 收集全部 .gd
    gd_files = []
    for dp, dns, fns in os.walk(root):
        dns[:] = [d for d in dns if d not in SKIP_DIRS]
        for fn in fns:
            if fn.endswith(".gd"):
                gd_files.append(os.path.join(dp, fn))

    # 2) 解析 class_name + 建立 res:// -> 文件 映射
    class_to_file = {}
    nodes = {}
    for f in gd_files:
        try:
            text = open(f, encoding="utf-8", errors="ignore").read()
        except Exception:
            text = ""
        cn = CLASSNAME_RE.search(text)
        cn_name = cn.group(1) if cn else None
        if cn_name:
            class_to_file[cn_name] = f
        nodes[f] = {
            "path": short_res(os.path.relpath(f, root)),
            "layer": layer_of(f, root),
            "class_name": cn_name,
            "extends": None,
        }

    res_to_file = {n["path"]: f for f, n in nodes.items()}

    # 3) 解析依赖边
    edges = []  # {from, to, kind, resolved}
    for f, n in nodes.items():
        text = open(f, encoding="utf-8", errors="ignore").read()
        # extends
        ep = EXTENDS_PATH_RE.search(text)
        if ep:
            tgt = ep.group(1).replace("\\", "/")
            n["extends"] = tgt
            edges.append({"from": f, "to": tgt, "kind": "extends", "resolved": tgt in res_to_file})
        else:
            en = EXTENDS_NAME_RE.search(text)
            if en:
                base = en.group(1)
                n["extends"] = base
                if base in class_to_file:
                    edges.append({"from": f, "to": short_res(os.path.relpath(class_to_file[base], root)),
                                  "kind": "extends", "resolved": True})
        # preload / load
        for m in RES_REF_RE.finditer(text):
            tgt = m.group(1).replace("\\", "/")
            edges.append({"from": f, "to": tgt, "kind": "preload/load", "resolved": tgt in res_to_file})

    # 4) 标注向上依赖违例（高 layer 依赖低 layer）
    violations = []
    for e in edges:
        tgt = e["to"]
        if not (isinstance(tgt, str) and tgt.startswith("res://")):
            continue
        if tgt not in res_to_file:
            continue  # 未解析到的引用（缺文件/拼写）单独可查，但不算层违例
        fl = nodes[e["from"]]["layer"]
        tl = nodes[res_to_file[tgt]]["layer"]
        rf = LAYER_RANK.get(fl, RANK_OTHER)
        rt = LAYER_RANK.get(tl, RANK_OTHER)
        if rt > rf:  # 基础层(低 rank) 反向依赖 上层(高 rank) = 违反架构铁律
            violations.append({
                "from": nodes[e["from"]]["path"], "from_layer": fl,
                "to": tgt, "to_layer": tl, "kind": e["kind"],
            })

    # 5) 汇总
    layer_counts = {}
    for n in nodes.values():
        layer_counts[n["layer"]] = layer_counts.get(n["layer"], 0) + 1
    unresolved = [e["to"] for e in edges if not e["resolved"] and e["to"].startswith("res://")]

    report = {
        "root": root,
        "summary": {
            "gd_files": len(gd_files),
            "layers": layer_counts,
            "edges": len(edges),
            "resolved_edges": sum(1 for e in edges if e["resolved"]),
            "unresolved_refs": len(unresolved),
            "upward_violations": len(violations),
        },
        "violations": violations,
        "unresolved_refs": sorted(set(unresolved)),
        "nodes": [n for n in nodes.values()],
        "edges": [{"from": nodes[e["from"]]["path"], "to": e["to"], "kind": e["kind"], "resolved": e["resolved"]} for e in edges],
    }

    return report


def main():
    ap = argparse.ArgumentParser()
    default_root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    ap.add_argument("--root", default=default_root)
    ap.add_argument("--out", help="JSON 报告输出路径（默认打印到 stdout）")
    ap.add_argument("--mermaid", help="Mermaid 图输出路径（可选）")
    args = ap.parse_args()
    report = scan(args.root)
    out_json = json.dumps(report, ensure_ascii=False, indent=2)
    if args.out:
        open(args.out, "w", encoding="utf-8").write(out_json)
        print("JSON 报告已写入:", args.out)
    else:
        print(out_json)
    s = report["summary"]
    print("\n==== 依赖图摘要 ====")
    print("扫描 .gd 文件数:", s["gd_files"])
    print("各层文件数:", json.dumps(s["layers"], ensure_ascii=False))
    print("依赖边总数:", s["edges"], "（已解析", s["resolved_edges"], "/ 未解析", s["unresolved_refs"], "）")
    print("⚠ 向上依赖违例（违反架构铁律）:", s["upward_violations"])
    for v in report["violations"]:
        print("   ", v["from_layer"], "→", v["to_layer"], "|", v["from"], "==", v["kind"], "==>", v["to"])
    if args.mermaid:
        mm = ["graph TD"]
        for l in LAYERS + ["other"]:
            items = [n for n in report["nodes"] if n["layer"] == l]
            if items:
                mm.append("  subgraph %s" % l)
                for n in items:
                    mm.append("    N%s[\"%s\"]" % (abs(hash(n["path"])) % 100000, n["path"].split("/")[-1]))
                mm.append("  end")
        for e in report["edges"]:
            if e["resolved"]:
                mm.append("    N%s --> N%s" % (abs(hash(e["from"])) % 100000, abs(hash(e["to"])) % 100000))
        open(args.mermaid, "w", encoding="utf-8").write("\n".join(mm))
        print("\nMermaid 图已写入:", args.mermaid)


# ---- Code Graph：impact / reverse（基于 scan 结果，Phase 5 双图分离）----
def _build_code_index(report):
    """从 scan 报告构建 path->node 和前向/反向边索引。"""
    nodes = {n["path"]: n for n in report["nodes"]}
    forward = {}   # path -> [to_path]
    backward = {}  # path -> [from_path]
    for e in report["edges"]:
        if not e["resolved"]:
            continue
        f, t = e["from"], e["to"]
        forward.setdefault(f, []).append(t)
        backward.setdefault(t, []).append(f)
    return nodes, forward, backward


def impact_of_file(file_path, root=None):
    """Code Graph 影响分析（可传递）：改 file_path 会影响哪些文件（即谁依赖它）。
    file_path 支持绝对路径、相对路径或 res:// 路径。返回 [path...]（去重排序）。
    业务语义封装，等价于 reverse_deps_of_file（传递反向）。"""
    return reverse_deps_of_file(file_path, root=root)


def reverse_deps_of_file(file_path, root=None):
    """Code Graph 反向依赖（可传递）：谁引用了 file_path（含间接引用）。
    返回 [path...]（res:// 格式，去重排序）。"""
    if root is None:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    report = scan(root)
    nodes, _fwd, backward = _build_code_index(report)
    start = _normalize_path(file_path, root)
    visited = set()
    result = set()

    def _walk(p):
        if p in visited:
            return
        visited.add(p)
        for f in backward.get(p, []):
            result.add(f)
            _walk(f)

    if start in nodes:
        _walk(start)
    return sorted(result)


def _normalize_path(file_path, root):
    """把各种路径格式统一成 res:// 开头的标准形式。"""
    if file_path.startswith("res://"):
        return file_path
    if os.path.isabs(file_path):
        rel = os.path.relpath(file_path, root)
    else:
        rel = file_path
    return "res://" + rel.replace("\\", "/")


if __name__ == "__main__":
    main()
