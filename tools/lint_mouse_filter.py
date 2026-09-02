#!/usr/bin/env python3
# tools/lint_mouse_filter.py
# 静默拦截 BUG 静态扫描器（GATE0）
#
# 背景（用户血的教训，已立铁律）：
#   Godot 的 mouse_filter：STOP=0（默认）/ PASS=1 / IGNORE=2。
#   本意让装饰子节点"点击穿透"，却错写成 0（STOP=拦截）——于是盖在按钮中心的
#   Label/TextureRect 把按钮本体的 mouse_entered/button_up 全吞了：
#     现象 = 自动悬停在按钮上、鼠标移不开、点了不触发回调；纯事件捕获、全程零报错。
#   这种 BUG 不报红、GATE1 抓不到，只能靠"无头鼠标拾取模拟器"复核才暴露。
#
# 本工具把"规则"变成"自动检测"：扫描所有 .tscn，找出
#   【clickable 按钮节点下的 可见 装饰子节点 且 mouse_filter 仍为 STOP(0 或默认)】
# 这类节点会在运行时静默吞掉按钮点击。
#
# 两层严格度：
#   --tier default（提交门禁用，零误报）：仅报 显式 mouse_filter = 0 的装饰子节点
#                            （= 有人写 0 想穿透，典型手误；DialogOverlay 里
#                              visible=false 的节点自动排除）
#   --tier strict（定期审计用）：报 任何 mouse_filter != 2(IGNORE) 且 != 1(PASS)
#                            的可见装饰子节点（含默认 STOP，挖潜在隐患）
#
# 退出码：发现高危（default 层）返回 1，否则 0。strict 层发现返回 2（仅警告，不阻断）。
import os
import sys
import argparse

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCENES_DIR = os.path.join(REPO, "scenes")

# 视为"可点击"的节点类型（按钮类）
CLICKABLE_TYPES = ("Button", "BaseButton", "TextureButton", "TouchScreenButton",
                   "LinkButton", "OptionButton", "CheckBox", "ColorPickerButton")
# 视为"装饰/文本"的节点类型（这些本应 IGNORE）
DECOR_TYPES = ("Label", "TextureRect", "ColorRect", "NinePatchRect",
               "RichTextLabel", "Panel", "Control", "MarginContainer",
               "VBoxContainer", "HBoxContainer", "CenterContainer")


def _parse(path):
    """返回节点列表：每个含 full_path, type, line, mouse_filter, visible"""
    nodes = []
    cur = None  # 当前节点 dict
    with open(path, encoding="utf-8") as f:
        for i, raw in enumerate(f, 1):
            line = raw.rstrip("\n")
            s = line.strip()
            if s.startswith("[node"):
                # 解析 name / parent / type
                name = typ = parent = None
                for kv in s[5:].rstrip("]").split():
                    if kv.startswith("name="):
                        name = kv[len("name="):].strip('"')
                    elif kv.startswith("parent="):
                        parent = kv[len("parent="):].strip('"')
                    elif kv.startswith("type="):
                        typ = kv[len("type="):].strip('"')
                if name is None:
                    continue
                full = name if (parent in (None, ".")) else (parent + "/" + name)
                cur = {"full": full, "parent": parent if parent not in (None, ".") else "",
                       "type": typ or "", "line": i, "name": name,
                       "mouse_filter": None, "visible": True}
                nodes.append(cur)
            elif cur is not None:
                if s.startswith("mouse_filter"):
                    # mouse_filter = 0/1/2
                    try:
                        cur["mouse_filter"] = int(s.split("=")[1].strip())
                    except Exception:
                        pass
                elif s.startswith("visible"):
                    val = s.split("=")[1].strip() if "=" in s else "true"
                    cur["visible"] = (val.lower() == "true")
    return nodes


def _is_clickable(typ):
    return any(t in typ for t in CLICKABLE_TYPES)


def _is_decor(typ):
    return any(t in typ for t in DECOR_TYPES)


def _load_allowlist():
    """读取 tools/lint_mouse_filter.allow：每行一个相对/绝对路径或文件名，
    # 开头为注释。命中则对该文件豁免（用于确有意的 mouse_filter=STOP 场景，
    避免被迫 --no-verify 整体绕过守卫）。"""
    p = os.path.join(REPO, "tools", "lint_mouse_filter.allow")
    out = set()
    if not os.path.isfile(p):
        return out
    with open(p, encoding="utf-8") as f:
        for line in f:
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            out.add(os.path.normpath(s))
    return out


def _suppressed(fp, allow):
    if not allow:
        return False
    rel = os.path.normpath(os.path.relpath(fp, REPO))
    base = os.path.basename(fp)
    return rel in allow or base in allow


def scan_file(path, tier):
    nodes = _parse(path)
    by_path = {n["full"]: n for n in nodes}
    findings = []
    for n in nodes:
        if not _is_clickable(n["type"]):
            continue
        # BFS 后代
        prefix = n["full"] + "/"
        for c in nodes:
            if not c["full"].startswith(prefix):
                continue
            # 跳过嵌套的可点击节点自身（那是另一交互元素）
            if _is_clickable(c["type"]):
                continue
            if not c["visible"]:
                continue
            if not _is_decor(c["type"]):
                continue
            mf = c["mouse_filter"]
            if tier == "default":
                # 仅显式 0（STOP）才算手误高危
                if mf == 0:
                    findings.append((path, c["line"], n["full"], c["full"], c["type"]))
            else:  # strict：任何非 IGNORE(2) 且非 PASS(1) 的可见装饰子节点
                if mf != 2 and mf != 1:
                    findings.append((path, c["line"], n["full"], c["full"], c["type"]))
    return findings


def main():
    ap = argparse.ArgumentParser(description="静默拦截 mouse_filter 静态扫描")
    ap.add_argument("--tier", choices=["default", "strict"], default="default")
    ap.add_argument("--root", default=SCENES_DIR)
    ap.add_argument("--files", nargs="*", default=None,
                    help="只扫描指定文件（pre-commit 钩子用：仅查本次暂存的 .tscn）")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    findings = []
    if a.files is not None:
        # 仅扫描显式传入的文件（路径需存在；已删除的文件跳过）
        for fp in a.files:
            if fp.endswith(".tscn") and os.path.isfile(fp):
                findings += scan_file(fp, a.tier)
    else:
        for dp, _, files in os.walk(a.root):
            for fn in files:
                if fn.endswith(".tscn"):
                    findings += scan_file(os.path.join(dp, fn), a.tier)

    # 白名单豁免（确有意的 STOP，避免被迫 --no-verify）
    allow = _load_allowlist()
    suppressed = [x for x in findings if _suppressed(x[0], allow)]
    findings = [x for x in findings if not _suppressed(x[0], allow)]

    if not a.quiet:
        if suppressed:
            print("ℹ 白名单豁免 %d 处（见 tools/lint_mouse_filter.allow）：" % len(suppressed))
            for fp, ln, btn, child, ct in suppressed:
                print("  (豁免) %s:%d  %s/%s" % (os.path.relpath(fp, REPO), ln, btn, child))
        if findings:
            print("⚠ 发现 %d 处『按钮下可见装饰子节点仍为 STOP(会静默吞点击)』：" % len(findings))
            for fp, ln, btn, child, ct in findings:
                rel = os.path.relpath(fp, REPO)
                print("  %s:%d  按钮[%s] 的子节点[%s](%s) mouse_filter=STOP" % (rel, ln, btn, child, ct))
        else:
            print("✓ 未发现 mouse_filter=STOP 的按钮装饰子节点（静默拦截风险：无）")
    return 1 if (findings and a.tier == "default") else (2 if (findings and a.tier == "strict") else 0)


if __name__ == "__main__":
    sys.exit(main())
