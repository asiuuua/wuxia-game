#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
signal_audit.py v5 — GDScript 信号连接 vs 处理器参数个数一致性扫描。

为什么需要它：Godot 4.x 中，信号发射 N 个参数时，连接的处理器方法必须能"接住"
这 N 个参数——否则运行时抛 "Method expected K argument(s), but called with N"。
本项目已在 InventoryScreen._on_inv_changed 真实踩过（1 参接 2 参 → 必崩）。

v4 修正 v3 的括号截断 bug：当 connect 实参内含 `.bind(i)` 时，旧正则 `[^)]*`
在 `.bind(i)` 的 `)` 处就截断，导致 `.bind` 闭合括号丢失、bind 计数归零、误报。
现改为：定位到 `connect(` 后用**括号配对**读到匹配的 `)`，再解析实参。

v5 修正（2026-09-02，AI-架构）：同名信号跨类多签名冲突误报。
Godot 允许不同类声明同名 `signal confirmed` 但参数不同（如 SaveNameDialog 的
`confirmed(save_name: String)` 1 参 vs ConfirmDialog/MenuItem 的 `confirmed()` 0 参）。
v4 把信号按全局名字建表（后者覆盖前者），`confirmed` 被记成最后声明的 1 参，
于是对 ConfirmDialog/MenuItem 的 0 参 `confirmed` 连接误判 "1+bind 参 > 处理器 N 参" → 假 DEFINITE。
v5 在扫描后检测同名信号的**多签名集合**：若某信号名存在 >1 种 argc，则标 `ambiguous`，
对该信号的所有 connect 跳过 DEFINITE 判定（仅放松、不引入新误报；代价是可能漏报该信号的真实
参数不匹配，但总比永久假红、无法接入门禁要好）。

另修正：
- 处理器签名优先在本文件内解析（消除同名虚方法跨文件碰撞，如 BaseScreen._refresh 覆盖 Hud._refresh）。
- .bind(X) 绑参：处理器实际收到 (绑定参..., 信号参...)。
- 默认参数：最小可接收=首个默认参之前的个数，最大=声明总数（变参 ... 无上限）。

判定（处理器将收到实参 R = signal_argc + bind_count）：
    R > handler_max  -> DEFINITE（实参过多，必崩）
    R < handler_min  -> DEFINITE（实参过少，必崩）
    否则              -> OK
    handler 含 "..."  -> OK

内置 Godot 信号（pressed/mouse_entered...）不在本工程 signal 定义中，跳过不查。

用法：python tools/signal_audit.py [project_root]
退出码：0=无非 DEFINITE 隐患；2=有 DEFINITE（可接入 CI/门禁）。
"""
import os
import re
import sys

ROOT = sys.argv[1] if len(sys.argv) > 1 else os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SKIP_DIRS = {".godot", ".git"}

SIG_RE = re.compile(r'^\s*signal\s+(\w+)\s*\((.*?)\)\s*(?:#.*)?$', re.M)
FUNC_RE = re.compile(r'^\s*(?:static\s+)?func\s+(\w+)\s*\((.*?)\)\s*(?:->.*)?$', re.M)
CONNECT_OPEN = re.compile(r'\.connect\s*\(')


def parse_args(argstr: str):
    s = argstr.strip()
    if s == "" or s == " ":
        return 0, 0, False
    if "..." in s:
        return 0, 0, True
    parts = [p.strip() for p in s.split(",") if p.strip() != ""]
    total = len(parts)
    min_req = total
    for i, p in enumerate(parts):
        if "=" in p:
            min_req = i
            break
    return total, min_req, False


def extract_handler(inner: str):
    """从 connect 实参串中提取处理器名与 .bind 绑定参个数。"""
    inner = inner.strip()
    if inner == "":
        return "", 0
    bind_count = 0
    mbind = re.search(r'\.bind\s*\(\s*([^)]*)\)', inner)
    if mbind:
        bargs = mbind.group(1).strip()
        bind_count = 0 if bargs == "" else len([x for x in bargs.split(",") if x.strip() != ""])
        inner = inner[:mbind.start()]
    m = re.search(r'Callable\s*\(\s*[^,]+,\s*&?["\']([^"\']+)["\']', inner)
    if m:
        return m.group(1), bind_count
    inner = re.sub(r'\.bind\s*\(.*$', '', inner)
    first = inner.split(",")[0].strip()
    if "." in first:
        first = first.rsplit(".", 1)[1]
    return first.strip(), bind_count


def read_balanced(src: str, start: int):
    """从 start（'(' 之后第一个字符）起，按括号配对读到匹配 ')'，返回 (内部串, 结束下标)。"""
    depth = 1
    i = start
    n = len(src)
    while i < n:
        c = src[i]
        if c == '(':
            depth += 1
        elif c == ')':
            depth -= 1
            if depth == 0:
                return src[start:i], i + 1
        i += 1
    return src[start:], n


def resolve_handler(funcs_by_file, funcs_global, rel, handler):
    f = funcs_by_file.get(rel, {}).get(handler)
    if f is not None:
        return f, "in-file"
    g = funcs_global.get(handler)
    if g is not None:
        return g, "global"
    return None, "unknown"


def main():
    signals_set = {}        # name -> set(argc)：收集同名信号的所有签名
    funcs_by_file = {}
    funcs_global = {}
    connects = []

    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in SKIP_DIRS]
        for fn in filenames:
            if not fn.endswith(".gd"):
                continue
            path = os.path.join(dirpath, fn)
            try:
                with open(path, encoding="utf-8") as f:
                    src = f.read()
            except Exception:
                continue
            rel = os.path.relpath(path, ROOT)
            if rel not in funcs_by_file:
                funcs_by_file[rel] = {}
            for m in SIG_RE.finditer(src):
                name = m.group(1)
                argc = parse_args(m.group(2))[0]
                signals_set.setdefault(name, set()).add(argc)
            for m in FUNC_RE.finditer(src):
                sig = parse_args(m.group(2))
                funcs_by_file[rel][m.group(1)] = sig
                funcs_global[m.group(1)] = sig
            # 连接点：定位 .connect( 后用括号配对读实参
            for m in CONNECT_OPEN.finditer(src):
                inner, _ = read_balanced(src, m.end())
                inner = inner.strip()
                pre = src[:m.start()]
                if inner.startswith('"') or inner.startswith("'"):
                    # CONN_B: obj.connect("sig", handler)
                    mq = re.match(r'["\']([^"\']+)["\']\s*,\s*(.*)$', inner)
                    if not mq:
                        continue
                    sig = mq.group(1)
                    handler_inner = mq.group(2)
                else:
                    # CONN_A: TARGET.signal.connect(handler)
                    # 信号名 = 紧贴 .connect 之前的那个标识符（取 pre 最后一个 '.' 之后）。
                    # 不能用 re.search 最左匹配——pre 含整段前文，会误逮文件里更早的 connect 信号。
                    sig = pre.rsplit('.', 1)[-1].strip()
                    if sig == "" or not sig[0].isalpha():
                        continue
                    handler_inner = inner
                h, bc = extract_handler(handler_inner)
                if h:
                    connects.append((rel, src[:m.start()].count("\n") + 1, sig, h, bc))

    # 同名信号跨类多签名冲突 -> ambiguous：全局表无法可靠确定 argc，跳过 DEFINITE 判定（只放松）
    ambiguous = {name for name, argcs in signals_set.items() if len(argcs) > 1}
    # 单签名信号：保留其唯一 argc 用于判定；ambiguous 信号不进入此表
    signals = {name: next(iter(argcs)) for name, argcs in signals_set.items() if len(argcs) == 1}

    definite, unknown, ambiguous_hits = [], [], []
    for (rel, ln, sig, handler, bind_count) in connects:
        if sig not in signals:
            if sig in ambiguous:
                ambiguous_hits.append((rel, ln, sig, handler))
            continue
        sargc = signals[sig]
        hsig, scope = resolve_handler(funcs_by_file, funcs_global, rel, handler)
        if hsig is None:
            unknown.append((rel, ln, sig, sargc, handler, "未找到函数定义（多为内联 Callable，运行时兜底）"))
            continue
        htotal, hmin, hvar = hsig
        if hvar:
            continue
        received = sargc + bind_count
        if received > htotal:
            definite.append((rel, ln, sig, sargc, handler, htotal, bind_count, "实参过多", scope))
        elif received < hmin:
            definite.append((rel, ln, sig, sargc, handler, htotal, bind_count, "实参过少", scope))

    print("=" * 82)
    print("GDScript 信号/处理器参数对齐扫描 v5（括号配对 + 本文件解析 + ambiguous 跳过）")
    print(f"项目根: {ROOT}")
    print(f"自定义信号: {len(signals_set)}（其中 ambiguous 同名多签名: {len(ambiguous)}）  函数: {len(funcs_global)}  连接点: {len(connects)}")
    print("=" * 82)

    print(f"\n[DEFINITE] 实参个数超出处理器可接范围（运行时必崩）: {len(definite)}")
    for r in definite:
        extra = f" (+{r[6]} bind)" if r[6] else ""
        print(f"  {r[0]}:{r[1]}  信号 {r[2]}({r[3]}参){extra} -> {r[4]}(最多接 {r[5]}参)  [{r[7]}/{r[8]}]")

    print(f"\n[UNKNOWN] 处理器函数未在工程内找到（多为内联 Callable，跳过）: {len(unknown)}")
    for r in unknown[:40]:
        print(f"  {r[0]}:{r[1]}  信号 {r[2]}({r[3]}参) -> {r[4]}  ({r[5]})")

    print(f"\n[AMBIGUOUS] 同名信号跨类多签名冲突，跳过参数对齐判定（不误报）: {len(ambiguous_hits)}")
    for r in ambiguous_hits[:40]:
        print(f"  {r[0]}:{r[1]}  信号 {r[2]} -> {r[3]}  (同名信号声明签名不一致，无法定位真实 argc)")

    print("\n" + "=" * 82)
    if definite:
        print(f"结论: 发现 {len(definite)} 个 DEFINITE 级隐患，必须修复！")
        sys.exit(2)
    print("结论: 未发现 DEFINITE 级信号/处理器参数不匹配。")
    sys.exit(0)


if __name__ == "__main__":
    main()
