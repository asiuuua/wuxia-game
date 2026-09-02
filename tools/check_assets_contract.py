#!/usr/bin/env python3
# tools/check_assets_contract.py
# GATE0 扩展：资源文件存在性 + 数据契约(JSON)合法性 静态扫描。
#
# 背景（用户踩过的"静默失败"真实坑，零报错但功能坏）：
#   - 8 个 UI 音效文件根本没放进工程 → AudioManager.play_ui_sfx 在
#     ResourceLoader.exists 失败时空静默跳过 → 所有 UI 音效一直无声、零报错。
#   - preset_12x12.jpg 实为 PNG 被错命名 → Godot 无法导入、静默不报错。
#   - 这类"资源/数据缺失"属于最高发最阴的静默 BUG 一类：代码跑了、加载失败被吞、
#     引擎不报错、玩家踩了才知道。
#
# 与已有工具的分工（不重复造轮子）：
#   - lint_mouse_filter.py      → 只查 .tscn 的 mouse_filter 静默吞点击。
#   - signal_audit.py           → 只查"信号/处理器参数个数对齐"（必崩类）。
#   - audit_onready_paths.py    → 只查 scenes/ui 的 $Path/get_node 在 .tscn 能否解析（null 类）。
#   本工具补它们的盲区：① .tscn 的 ext_resource path= 与 .gd 的 load/preload("res://")
#   指向的【资源文件是否真实存在】；② data/configs 下 JSON 是否合法（防脏数据契约）。
#
# 设计铁律（呼应"机器约束不能反向卡开发"）：
#   - 默认只【报告】缺失/坏 JSON，exit 0（不拦），因为资源引用误报面比 mouse_filter 大
#     （少量动态/可选引用），直接拦会误拦正常提交。
#   - --strict 才在发现问题时 exit 1（供 CI / 人工决议 / 未来接 pre-commit 严格门禁用）。
#   - 失败开放：扫描器自身异常（编码/权限）打印告警并 exit 0，绝不冒充"发现高危"拦提交。
#   - 支持 --files（只查指定文件，供未来接 pre-commit）与白名单 allow（确有意的缺失豁免）。
import os
import re
import sys
import json
import argparse
import glob

def _to_win(p: str) -> str:
    # Git Bash 等环境会把 /d/xxx 形式路径传给 Windows Python，后者不认盘符前缀；
    # 归一化为 Windows 风格（D:/xxx），否则 os.path.isfile/glob/os.walk 全部失效。
    if len(p) > 2 and p[0] == "/" and p[2] == "/":
        return p[1].upper() + ":/" + p[3:]
    return p


ROOT = os.path.normpath(os.path.dirname(os.path.dirname(os.path.abspath(_to_win(__file__)))))
SKIP_DIRS = {".godot", ".git"}

# .tscn 里 [ext_resource ... path="res://..."] 等所有带 res:// 的 path 属性
RES_PATH_RE = re.compile(r'path="(res://[^"]+)"')
# .gd 里 load("res://...") / preload("res://...") 字面量（动态拼接 "res://"+x 抓不到，天然跳过=保守）
RES_LOAD_RE = re.compile(r'(?:load|preload)\(\s*"res://([^"]+)"\s*\)')


def _to_rel(res: str) -> str:
    # RES_PATH_RE 抓到的 group 含 "res://" 前缀；RES_LOAD_RE 抓到的不含。
    # 统一去掉前缀（若存在），避免对 load/preload 引用多截 8 字符导致误报缺失。
    if res.startswith("res://"):
        return res[len("res://"):]
    return res


def _strip_comments(src: str, ext: str) -> str:
    # 去掉 GDScript(.gd)的 # 注释 与 tscn 的 ; 注释，避免误把注释里的
    # "res://..." 字面量当成真实资源引用（造成假阳性噪音）。
    # 失败开放：仅做行级裁剪，最坏情况漏掉一个真引用（不误报），可接受。
    cmt = "#" if ext == ".gd" else ";"
    out = []
    for line in src.splitlines():
        idx = line.find(cmt)
        out.append(line if idx < 0 else line[:idx])
    return "\n".join(out)


def _load_allow() -> set:
    p = os.path.join(ROOT, "tools", "check_assets_contract.allow")
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


def scan_resources(files=None) -> list:
    """返回缺失资源列表 [(引用文件rel, res路径)]。files=None 扫全工程。"""
    missing = []
    allow = _load_allow()
    targets = []
    if files is not None:
        for fp in files:
            fp = _to_win(fp)
            if (fp.endswith(".tscn") or fp.endswith(".gd")) and os.path.isfile(fp):
                targets.append(fp)
    else:
        for dp, dns, fns in os.walk(ROOT):
            dns[:] = [d for d in dns if d not in SKIP_DIRS]
            for fn in fns:
                if fn.endswith(".tscn") or fn.endswith(".gd"):
                    targets.append(os.path.join(dp, fn))
    for p in targets:
        p = _to_win(p)
        rel = os.path.relpath(p, ROOT)
        if os.path.normpath(rel) in allow:
            continue
        ext = os.path.splitext(p)[1].lower()
        try:
            with open(p, encoding="utf-8") as f:
                src = f.read()
        except Exception:
            continue
        src = _strip_comments(src, ext)
        for m in RES_PATH_RE.finditer(src):
            rp = _to_rel(m.group(1))
            if os.path.normpath(rp) in allow:
                continue
            if not os.path.isfile(os.path.join(ROOT, rp)):
                missing.append((rel, m.group(1)))
        for m in RES_LOAD_RE.finditer(src):
            rp = _to_rel(m.group(1))
            if os.path.normpath(rp) in allow:
                continue
            if not os.path.isfile(os.path.join(ROOT, rp)):
                missing.append((rel, m.group(1)))
    # 去重
    seen = set()
    uniq = []
    for rel, res in missing:
        k = (rel, res)
        if k in seen:
            continue
        seen.add(k)
        uniq.append((rel, res))
    return uniq


def scan_json() -> list:
    """返回坏 JSON 列表 [(rel, 错误)]。"""
    bad = []
    for path in glob.glob(os.path.join(ROOT, "data", "configs", "**", "*.json"), recursive=True):
        rel = os.path.relpath(path, ROOT)
        try:
            with open(path, encoding="utf-8") as f:
                json.load(f)
        except Exception as e:
            bad.append((rel, str(e)))
    return bad


def main():
    ap = argparse.ArgumentParser(description="资源/数据契约静态扫描（GATE0 扩展）")
    ap.add_argument("--files", nargs="*", default=None,
                    help="只扫描指定文件（未来接 pre-commit 用）")
    ap.add_argument("--strict", action="store_true",
                    help="发现缺失/坏 JSON 时 exit 1（默认仅报告 exit 0）")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()

    try:
        missing = scan_resources(a.files)
        bad = scan_json()
    except Exception as e:
        sys.stderr.write("[check_assets_contract] ⚠ 扫描器自身异常，已放行未阻断：%s\n" % e)
        sys.exit(0)

    if not a.quiet:
        if missing:
            print("⚠ 发现 %d 处『res:// 资源引用指向不存在的文件』（静默加载失败高发区）：" % len(missing))
            for rel, res in missing:
                print("  %s  →  %s" % (rel, res))
        else:
            print("✓ 所有 res:// 资源引用均指向存在的文件")
        if bad:
            print("⚠ 发现 %d 个非法 JSON（数据契约损坏）：" % len(bad))
            for rel, err in bad:
                print("  %s  →  %s" % (rel, err))
        else:
            print("✓ data/configs 下所有 JSON 合法")
    rc = 1 if (a.strict and (missing or bad)) else 0
    return rc


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception as e:
        sys.stderr.write("[check_assets_contract] ⚠ 扫描器自身异常，已放行未阻断：%s\n" % e)
        sys.exit(0)
