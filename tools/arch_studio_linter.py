# -*- coding: utf-8 -*-
"""arch_studio_linter.py — 内容工作室 Python 服务层架构静态检查（Phase 2 Repository 层）

依据: docs/architecture/01_总体架构施工图_V1.4修复版.md §26/§27/§28（Repository Boundary）
分层铁律:
  业务域 service（services/*_service.py）→ 域 Repository（services/repositories/）
    → persistence 适配层（services/persistence.py）→ data_sink（DataSink 六步收口）
本检查机器化两条红线（新增即拦，无基线豁免）:
  R1 业务层零直调: 业务域 service 不得 import 或直接调用 save_json / save_text
     （落盘必须经对应域 Repository；唯一例外 persistence.py 自身定义处）
  R2 Repository 边界: repositories/ 只能依赖 persistence / _common / project_service
     （不得反向依赖业务 service，防数据访问层与业务层环化）
退出码: 0=全绿；1=违规。
用法: python tools/arch_studio_linter.py
"""
import ast
import os
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
SERVICES = os.path.join(ROOT, "tools", "desktop_studio", "services")

# 业务层排除清单：自身定义写口的文件与包
ALLOWED_WRITE_DEF = {"persistence.py"}
# repositories/ 允许依赖的 services 子模块（完整路径；其余 services.* 一律越界）
ALLOWED_REPO_DEP = {"services.persistence", "services._common", "services.project_service"}
ALLOWED_REPO_TOP = {"persistence", "_common", "project_service"}

FORBIDDEN_NAMES = ("save_json", "save_text")


def _py_files(base):
    out = []
    for dirpath, _dirs, files in os.walk(base):
        for fn in sorted(files):
            if fn.endswith(".py"):
                out.append(os.path.join(dirpath, fn))
    return sorted(out)


def _rel(p):
    return os.path.relpath(p, ROOT).replace("\\", "/")


class _Visitor(ast.NodeVisitor):
    def __init__(self):
        self.hits = []

    def visit_ImportFrom(self, node):
        # 从 _common 批量 import save_json/save_text 即违规（业务层不得持有写口）
        if node.module == "services._common":
            for a in node.names:
                if a.name in FORBIDDEN_NAMES:
                    self.hits.append("import %s → 违规直取写口" % a.name)
        self.generic_visit(node)

    def visit_Call(self, node):
        f = node.func
        if isinstance(f, ast.Name) and f.id in FORBIDDEN_NAMES:
            self.hits.append("直调 %s(...) → 违规绕过 Repository" % f.id)
        self.generic_visit(node)


def scan_service_files():
    """R1：业务域 service 零 save_json/save_text 直调（含 import 与调用两层）。"""
    hits = []
    for p in _py_files(SERVICES):
        rel = _rel(p)
        top = os.path.basename(p)
        if top in ALLOWED_WRITE_DEF or top == "__init__.py":
            continue
        if os.path.sep + "repositories" + os.path.sep in p.replace("/", os.path.sep):
            continue  # repositories/ 是数据访问层，本检查 R2 单独覆盖
        try:
            tree = ast.parse(open(p, "r", encoding="utf-8").read(), filename=p)
        except SyntaxError as e:
            hits.append("%s: 语法错误 %s" % (rel, e))
            continue
        v = _Visitor()
        v.visit(tree)
        for h in v.hits:
            hits.append("%s: %s" % (rel, h))
    return hits


def scan_repo_deps():
    """R2：repositories/ 不得反向依赖业务 service（仅允许 persistence/_common/project_service）。"""
    hits = []
    repo_dir = os.path.join(SERVICES, "repositories")
    if not os.path.isdir(repo_dir):
        return hits
    for p in _py_files(repo_dir):
        rel = _rel(p)
        try:
            tree = ast.parse(open(p, "r", encoding="utf-8").read(), filename=p)
        except SyntaxError as e:
            hits.append("%s: 语法错误 %s" % (rel, e))
            continue
        for node in ast.walk(tree):
            if isinstance(node, ast.Import):
                for a in node.names:
                    n = a.name
                    if n.startswith("services") and n not in ALLOWED_REPO_DEP:
                        hits.append("%s: 反向依赖业务层 %s" % (rel, n))
            elif isinstance(node, ast.ImportFrom):
                mod = node.module or ""
                if mod == "services":
                    # from services import persistence 形式：仅放行白名单顶层名
                    for a in node.names:
                        if a.name not in ALLOWED_REPO_TOP:
                            hits.append("%s: 反向依赖业务层 %s.%s" % (rel, mod, a.name))
                elif mod.startswith("services") and mod not in ALLOWED_REPO_DEP:
                    hits.append("%s: 反向依赖业务层 %s" % (rel, mod))
    return hits


def run():
    r1 = scan_service_files()
    r2 = scan_repo_deps()
    print("=" * 70)
    print("Studio Python 服务层架构检查（R1 业务零直调 / R2 Repository 边界）")
    print("=" * 70)
    ok = True
    if r1:
        ok = False
        print("  R1 ✗ 业务层直调写口（%d 处）:" % len(r1))
        for h in r1[:20]:
            print("    " + h)
    else:
        print("  R1 ✓ 业务层零 save_json/save_text 直调")
    if r2:
        ok = False
        print("  R2 ✗ Repository 越界（%d 处）:" % len(r2))
        for h in r2[:20]:
            print("    " + h)
    else:
        print("  R2 ✓ Repository 仅依赖 persistence/_common/project_service")
    print("=" * 70)
    return ok


if __name__ == "__main__":
    sys.exit(0 if run() else 1)
