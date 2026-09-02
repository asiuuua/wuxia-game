#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
GATE0c —— 信号参数校验「ambiguous 跳过项」非阻塞提示门禁。

为什么存在：
  signal_audit.py v5 能识别「同名信号跨类多签名冲突（ambiguous）」，例如 Godot 允许
  不同类声明同名 signal confirmed 但签名不同（ConfirmDialog.confirmed() 0 参 vs
  SaveNameDialog.confirmed(save_name: String) 1 参）。对这种信号，全局信号表无法可靠
  确定 argc，v5 选择「跳过 DEFINITE 判定」以避免永久假红——代价是这些 connect 的
  参数个数**不再被校验覆盖**。若将来有人把参数写错，会因 ambiguous 被跳过而没被发现。

  本脚本把这批「当前未被参数校验覆盖的 connect」在提交时**打印成警告清单**提醒开发者，
  但【绝不拦截提交】：无论信号审计失败、还是清单非空，本脚本都 exit 0（pre-commit 据此放行）。

设计铁律（零阻断 / 零回归）：
  - 永远 exit 0。脚本自身保证；pre-commit 侧也做了「RC!=0 也不 exit 1」的防御性兜底。
  - fail-open：signal_audit.py 缺失/崩溃/输出非 JSON 时，仅打印提示并 exit 0，绝不连累提交。
  - 不改写任何工程文件，只读 signal_audit.py 的 --json 输出。

用法（被 pre-commit 调用，无需手跑）：
  python tools/gate0c_ambiguous_warn.py
退出码：0（始终）
"""
import json
import os
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # D:/武侠游戏 (tools/..)
SIG_AUDIT = os.path.join(REPO, "tools", "signal_audit.py")

# 复用与 pre-commit / signal_audit 一致的 Python 解析顺序：managed runtime 优先，否则 PATH 回退
_MANAGED = "C:/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe"


def resolve_python():
    if os.path.isfile(_MANAGED) and os.access(_MANAGED, os.X_OK):
        return _MANAGED
    for cand in ("python3", "python"):
        import shutil
        p = shutil.which(cand)
        if p:
            return p
    return None


def main():
    py = resolve_python()
    if py is None or not os.path.isfile(SIG_AUDIT):
        # fail-open：基础设施缺失，绝不拦提交
        print("[GATE0c] ⚠ Python 或 signal_audit.py 缺失，跳过 ambiguous 提示（非阻塞）。")
        return 0

    try:
        proc = subprocess.run(
            [py, SIG_AUDIT, "--json", REPO],
            capture_output=True, text=True, timeout=120,
        )
    except Exception as e:  # 超时/异常都 fail-open
        print("[GATE0c] ⚠ signal_audit.py 运行异常，跳过 ambiguous 提示（非阻塞）: %s" % e)
        return 0

    raw = (proc.stdout or "").strip()
    if not raw:
        print("[GATE0c] ⚠ signal_audit.py 无输出，跳过 ambiguous 提示（非阻塞）。")
        return 0
    try:
        data = json.loads(raw)
    except Exception:
        # 输出非 JSON（多半是 signal_audit 报错打到 stdout）：不阻断
        print("[GATE0c] ⚠ signal_audit.py 输出非 JSON，跳过 ambiguous 提示（非阻塞）。")
        return 0

    ambiguous = data.get("ambiguous") or []
    names = data.get("ambiguous_names") or []
    counts = data.get("counts") or {}

    print("=" * 82)
    print("【GATE0c · 非阻塞提示】信号参数校验 ambiguous 跳过项（仅警告，不拦截提交）")
    print("=" * 82)

    if not ambiguous:
        print("✓ 当前无 ambiguous 同名信号冲突，所有 connect 均已纳入参数个数校验覆盖。")
        print("=" * 82)
        return 0

    print("⚠ 发现 %d 处 connect 因「同名信号跨类多签名冲突」而【未被参数个数校验覆盖】："
          % len(ambiguous))
    if names:
        print("  冲突信号名: %s" % "、".join(names))
    print("  —— 这些是 Godot 允许的「同名 signal 不同签名」导致的扫描盲区；")
    print("  —— 若将来改动这些 connect 的参数，写错也不会被本审计发现，请人工核对。")
    print("-" * 82)
    for r in ambiguous:
        # r = [rel, ln, sig, handler]
        rel, ln, sig, handler = (r + ["", "", "", ""])[:4]
        handler_disp = (handler or "").strip()
        # signal_audit 对内联 Callable 匿名函数（func(...): ...）的 handler 名解析会残留函数体，
        # 这里归一显示为「内联 Callable」，避免提示里出现破碎的函数签名
        if "func(" in handler_disp or handler_disp.startswith("func "):
            handler_disp = "(内联 Callable 匿名函数)"
        elif len(handler_disp) > 60:
            handler_disp = handler_disp[:57] + "..."
        print("  %s:%s  信号 %s  ->  %s" % (rel, ln, sig, handler_disp))
    print("-" * 82)
    print("提示：统一这些同名信号的签名，或在 signal_audit 里做按类细化，即可消除盲区。")
    print("（本提示不阻断提交；详情见 tools/signal_audit.py 的 v5 说明。）")
    print("=" * 82)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
