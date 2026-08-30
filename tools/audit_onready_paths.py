#!/usr/bin/env python3
# 审计：scenes/ui 下所有 .gd 的 @onready $Path / get_node("...") 是否能在对应 .tscn 解析到。
# 仅报告「解析不到」的项（即潜在 null 崩溃），不做语义判断。
import os, re, sys

ROOT = "D:/武侠游戏"
UI = os.path.join(ROOT, "scenes", "ui")

def parse_tscn_nodes(tscn_path):
    # 解析 [node name="X" type="Y" parent="Z"]，name/parent 可能顺序不定、type 夹在中间
    nodes = []  # (name, parent)
    with open(tscn_path, encoding="utf-8") as f:
        for line in f:
            if not line.strip().startswith("[node"):
                continue
            nm = re.search(r'name="([^"]+)"', line)
            if not nm:
                continue
            name = nm.group(1)
            pm = re.search(r'parent="([^"]+)"', line)
            parent = pm.group(1) if pm else "."
            nodes.append((name, parent))
    # 建路径树：.tscn 的 parent 是「根相对路径」（根名省略），如 "Panel"、"Panel/Margin"
    # key 与 value 都用「根相对完整路径」，这样孙节点（如 Panel/Margin/VBox）也能被父引用命中
    rel = {}  # 根相对完整路径 -> 根相对完整路径（key==value）
    rel["."] = "."
    root_name = None
    changed = True
    while changed:
        changed = False
        for name, parent in nodes:
            if parent == ".":
                if name not in rel:
                    rel[name] = name
                    changed = True
                if root_name is None:
                    root_name = name
            else:
                if parent in rel:
                    nr = rel[parent] + "/" + name
                    if nr not in rel:
                        rel[nr] = nr
                        changed = True
    # 转成完整路径（拼上根名）
    full = set()
    if root_name:
        for v in rel.values():
            if v == ".":
                full.add(root_name)
            else:
                full.add(root_name + "/" + v)
    return full

def resolve(path_set, rel):
    # $Path 相对根节点（.gd 拥有者的根节点路径即为 .tscn 根节点名）
    # rel 形如 "Panel/Margin/VBox/TitleLabel" 或 "TitleLabel"
    parts = rel.split("/")
    # 根节点名我们不知道，但路径集合里既有 "RootName" 又有 "RootName/Child"
    # 用「去掉首段后是否在集合」判断：尝试每个已知根前缀
    for full in path_set:
        fps = full.split("/")
        if len(fps) <= len(parts):
            continue
        if fps[-len(parts):] == parts:
            return True
    # 也允许 rel 本身就是某完整路径（单段）
    if rel in path_set:
        return True
    # 单段匹配：集合里有 ".../TitleLabel"
    for full in path_set:
        if full.split("/")[-1] == parts[-1] and len(parts) == 1:
            # 单段且集合里存在同名叶节点 —— 但这不保证路径对，仅当 rel 唯一同名时
            pass
    return False

PROBLEMS = []

for dirpath, _, files in os.walk(UI):
    for fn in files:
        if not fn.endswith(".gd"):
            continue
        gdp = os.path.join(dirpath, fn)
        with open(gdp, encoding="utf-8") as f:
            src = f.read()
        # 找 @onready var _x: T = $Path
        for m in re.finditer(r'@onready\s+var\s+\w+\s*(?::\s*\w+)?\s*=\s*\$([A-Za-z0-9_/]+)', src):
            rel = m.group(1)
            tscn = gdp[:-3] + ".tscn"
            if not os.path.exists(tscn):
                continue
            pset = parse_tscn_nodes(tscn)
            if not resolve(pset, rel):
                PROBLEMS.append((gdp, "$" + rel, "tscn=" + tscn))
        # get_node("...") 也查
        for m in re.finditer(r'get_node\(\s*"([^"]+)"\s*\)', src):
            rel = m.group(1)
            if rel.startswith("$"):
                rel = rel[1:]
            if "/" not in rel and not rel.startswith("."):
                continue
            tscn = gdp[:-3] + ".tscn"
            if not os.path.exists(tscn):
                continue
            pset = parse_tscn_nodes(tscn)
            if not resolve(pset, rel):
                PROBLEMS.append((gdp, 'get_node("' + rel + '")', "tscn=" + tscn))

if PROBLEMS:
    print("=== 发现 @onready/$Path 解析不到的隐患 ===")
    for g, p, t in PROBLEMS:
        print(f"{g}\n   路径: {p}\n   {t}\n")
    sys.exit(1)
else:
    print("AUDIT_CLEAN: 所有 @onready $Path 均能在对应 .tscn 解析到")
