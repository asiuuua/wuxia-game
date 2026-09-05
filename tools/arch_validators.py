# -*- coding: utf-8 -*-
"""arch_validators.py — 04 图 GATE41 架构校验器组（01 §92 七校验器补位，2026-09-06 落地）

01 §92 七校验器物理化进度（本文件落地后 6/7，changed_file_scope 属多 AI 阶段暂缓）：
  ① forbidden_api_validator  = arch_linter GATE22（fc2debd 已建）✓
  ② freeze_manifest_validator = arch_linter GATE32（fc2debd 已建）✓
  ③ naming(ID 正则)          = id_validator GATE06（已有）✓
  ④ dependency_validator     = 本文件 GATE41 ✓（层方向单向 + 环检测 + 生产禁引 tests）
  ⑤ module_scope_validator   = 本文件 GATE41 ✓（Test Double 只准住 tests/doubles/）
  ⑥ naming_validator(test_*) = 本文件 GATE41 ✓（T-R02：tests/unit 套件必须 test_ 前缀）
  ⑦ changed_file_scope       = GATE23（多 AI 阶段，依赖 Write Lease 元数据，暂缓——不越界）
  state_owner_validator（GATE25）= 本文件 REPORT 模式通报（T-4 追认：先观察噪音率再定阈值，不拦）

层方向铁律（宪法 §85 / 工作记忆）：autoload → core → data → services → scenes → tests，单向。
用法: python tools/arch_validators.py   （退出码 0=通过 1=违规）
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

violations = []
notes = []

# 依赖禁引矩阵（宪法 §85 单向依赖的落地口径：地基纯净、表现最高）：
#   core      地基：只准依赖 core（禁 data/autoload/services/scenes/tests）
#   data      数据：只准 core/data（禁 autoload/services/scenes/tests）
#   services  业务：core/data/services（禁 scenes/tests）
#   autoload  装配：全部生产层（禁 tests）
#   scenes    表现：全部生产层（禁 tests）
#   tests     天花板：自由
DENY = {
    "core": {"data", "autoload", "services", "scenes", "tests"},
    "data": {"autoload", "services", "scenes", "tests"},
    "services": {"scenes", "tests"},
    "autoload": {"tests"},
    "scenes": {"tests"},
    "tests": set(),
}

RE_REF = re.compile(
    r"""(?:preload|load)\s*\(\s*["']res://([^"']+)["']""")   # preload/load res:// 路径


def layer_of(rel):
    top = rel.split("/", 1)[0]
    return top if top in DENY else None


def scan_dependency():
    """④ dependency_validator：preload/load 图层方向 + 环检测 + 生产禁引 tests。"""
    edges = {}   # file -> [被引文件,...]
    for dirpath, _dirs, files in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace(os.sep, "/")
        if rel_dir.split("/")[0] in (".git", ".godot", ".workbuddy", "docs", "tools", "assets",
                                     "resources", "Godot", "_ai_export") or rel_dir == ".":
            continue
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            src_layer = layer_of(rel)
            if src_layer is None:
                continue
            try:
                text = open(full, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            # 去注释（与 GATE22/32 同口径）：注释里的 res:// 路径不算引用
            code_text = re.sub(r"#[^\n]*", "", text)
            edges[rel] = []
            for m in RE_REF.finditer(code_text):
                target = m.group(1).split("::")[0].strip()
                if not target.endswith(".gd"):
                    continue
                tgt_norm = target if target.startswith("/") else target
                tgt_rel = tgt_norm.lstrip("/")
                tgt_layer = layer_of(tgt_rel)
                edges[rel].append(tgt_rel)
                if tgt_layer is None:
                    continue
                # 生产层禁引 tests（T-R05：生产代码禁引用 tests/）
                if tgt_layer == "tests" and src_layer != "tests":
                    violations.append(("T-R05", rel, "生产层 %s 引用 tests/: %s（禁）" % (src_layer, tgt_rel)))
                    continue
                # 禁引矩阵：地基纯净（core 禁引上层）、表现自由（scenes 引业务合法）
                if tgt_layer in DENY.get(src_layer, set()):
                    violations.append(
                        ("DEP", rel, "依赖禁引违例: %s → %s（%s 层禁引矩阵）"
                         % (src_layer, tgt_layer, src_layer)))
    # 环检测（DFS 三色；自环跳过——GDScript 不可能 preload 自己，自匹配=字符串/常量表误伤；
    # 环签名去重防同一环重复报告）
    color = {k: 0 for k in edges}
    seen_cycles = set()

    def dfs(u, path):
        color[u] = 1
        for v in edges.get(u, []):
            if v not in edges or v == u:
                continue
            if color.get(v) == 1:
                cyc = frozenset(path[path.index(v):] + [u]) if v in path else frozenset(path + [u])
                if cyc not in seen_cycles:
                    seen_cycles.add(cyc)
                    violations.append(("DEP-CYCLE", u, "依赖环: %s → %s" % (" → ".join(path[path.index(v):] + [u]) if v in path else " → ".join(path + [u]), v)))
            elif color.get(v) == 0:
                dfs(v, path + [u])
        color[u] = 0   # 白回溯（路径敏感环检测）

    for k in list(edges):
        dfs(k, [])


def scan_module_scope():
    """⑤ module_scope_validator：Test Double（fake_/stub_ 前缀）只准住 tests/doubles/。"""
    for dirpath, _dirs, files in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace(os.sep, "/")
        if rel_dir.split("/")[0] in (".git", ".godot", ".workbuddy", "docs", "tools", "Godot",
                                     "_ai_export") or rel_dir == ".":
            continue
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            if re.match(r"^(fake_|stub_|mock_)", fn) and not rel_dir.startswith("tests/doubles"):
                rel = os.path.join(rel_dir, fn).replace(os.sep, "/")
                violations.append(("T-R04", rel, "Test Double 只准住 tests/doubles/（04图 T-R04）"))


def scan_test_naming():
    """⑥ T-R02：tests/unit 套件必须 test_ 前缀（U-4 命名法）；运行器/基座下划线系豁免。"""
    unit = os.path.join(ROOT, "tests", "unit")
    exempt = {"run_all.gd"}   # 测试运行器（run_all.tscn 驱动脚本），非套件
    for fn in sorted(os.listdir(unit)):
        if fn.endswith(".gd") and not fn.startswith("_") and fn not in exempt:
            if not fn.startswith("test_"):
                rel = "tests/unit/" + fn
                violations.append(("T-R02", rel, "测试套件文件名必须 test_ 前缀（U-4/T-R02）"))


def report_state_owners():
    """state_owner_validator REPORT 模式（T-4 追认：观察期，不拦）：
    扫 services/autoload 公开 set_ 方法计数，>8 者通报观察。"""
    counts = {}
    for top in ("services", "autoload"):
        d = os.path.join(ROOT, top)
        for dirpath, _dirs, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".gd"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace(os.sep, "/")
                n = 0
                for ln in open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace"):
                    if re.match(r"^func\s+set_\w+\s*\(", ln.strip()) or re.match(r"^func\s+\w+", ln.strip()) and re.match(r"func\s+(set|add|remove|clear|update)_", ln):
                        n += 1
                if n:
                    counts[rel] = n
    hot = sorted(counts.items(), key=lambda x: -x[1])[:3]
    for rel, n in hot:
        notes.append("state_owner REPORT: %s 写入口 %d 个（观察期 T-4，不拦）" % (rel, n))


def main():
    scan_dependency()
    scan_module_scope()
    scan_test_naming()
    report_state_owners()

    print("arch_validators · 04图 GATE41（dependency/module_scope/test_naming + state_owner REPORT）")
    for n in notes:
        print("  ℹ " + n)
    if violations:
        for rule, f, ev in violations[:12]:
            print("  ✗ [%s] %s — %s" % (rule, f, ev))
        print("════ 结论：✗ %d 项违规 ════" % len(violations))
        sys.exit(1)
    print("════ 结论：✓ 通过（层方向单向 / 生产零引 tests / Double 隔离 / 套件命名合规）════")
    sys.exit(0)


if __name__ == "__main__":
    main()
