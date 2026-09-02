#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把审计发现（findings.json）归类进 docs/backlog.json 对应模块。

用法:
  python tools/audit_to_backlog.py --file findings.json
  python tools/audit_to_backlog.py --file findings.json --dry-run   # 仅预览，不落盘
  python tools/audit_to_backlog.py --file -                         # 从 stdin 读 JSON

findings.json 结构:
{
  "findings": [
    {
      "module": "ui",                 # 目标模块 id 或 name（匹配不到则落 audit 模块）
      "title": "确认框缩放动画仍是占位",
      "type": "占位",                  # 隐性BUG | 未实现 | 待办 | 占位 | 优化建议
      "status": "open",               # open | blocked | done | resolved
      "source": "scenes/ui/.../ConfirmDialog.gd:6",
      "detail": "……",
      "suggestion": "……",
      "plain": { "what":"…", "why":"…", "progress":"…", "missing":"…", "plan":"…", "bugs":"…" }  # 可选
    }
  ]
}

行为:
  - 按 module 匹配 backlog.json 的 modules[].id（大小写不敏感）或 name；
  - 匹配不到 → 落入 id="audit" 的「审计/质量」模块（若该模块不存在则自动创建）；
  - 追加 item（title/type/status/placeholder/source/detail/suggestion/plain）；
  - 同一模块内若已存在相同 title，跳过（防止重复归类）；
  - 更新顶层 updated 日期；
  - 写回 docs/backlog.json（indent=2, ensure_ascii=False）；
  - 写回后默认自动跑 tools/gen_backlog.py 重生成 docs/待办清单.md 与看板（--no-regen 可关）。

主权边界：本脚本只改 docs/backlog.json（工作室待办清单平台数据），不碰任何游戏逻辑代码。
"""
import os
import sys
import json
import argparse
import datetime
import subprocess

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BACKLOG = os.path.join(ROOT, "docs", "backlog.json")
GEN = os.path.join(ROOT, "tools", "gen_backlog.py")

ALLOWED_TYPES = {"隐性BUG", "未实现", "待办", "占位", "优化建议"}
ALLOWED_STATUS = {"open", "blocked", "done", "resolved"}


def _norm(s: str) -> str:
    return (s or "").strip().lower()


def _match_module(data: dict, key: str):
    """按 id 或 name（大小写不敏感）匹配模块；返回 (module_dict, matched_by)。"""
    k = _norm(key)
    for m in data["modules"]:
        if _norm(m.get("id", "")) == k or _norm(m.get("name", "")) == k:
            return m, "id/name"
    return None, None


def _ensure_audit_module(data: dict) -> dict:
    """确保存在 id='audit' 的模块，返回该模块 dict。"""
    for m in data["modules"]:
        if _norm(m.get("id", "")) == "audit":
            return m
    mod = {
        "id": "audit",
        "name": "审计/质量",
        "desc": "跨窗口质量审计发现的待办（由审计窗口派发，多落在各模块）。",
        "items": [],
    }
    data["modules"].append(mod)
    return mod


def _build_item(f: dict) -> dict:
    t = f.get("type", "待办")
    if t not in ALLOWED_TYPES:
        sys.stderr.write("  ⚠ 未知 type=%r，已归为「待办」\n" % t)
        t = "待办"
    st = f.get("status", "open")
    if st not in ALLOWED_STATUS:
        sys.stderr.write("  ⚠ 未知 status=%r，已归为「open」\n" % st)
        st = "open"
    item = {
        "title": f.get("title", "(未命名审计项)"),
        "type": t,
        "status": st,
        "placeholder": f.get("placeholder", t == "占位"),
        "source": f.get("source", "审计核查"),
        "detail": f.get("detail", ""),
        "suggestion": f.get("suggestion", "——"),
    }
    if f.get("plain"):
        item["plain"] = f["plain"]
    return item


def run(file_arg: str, dry_run: bool, no_regen: bool) -> int:
    # ---- 读 findings ----
    if file_arg == "-":
        raw = sys.stdin.read()
    else:
        if not os.path.exists(file_arg):
            sys.stderr.write("✗ 找不到 findings 文件: %s\n" % file_arg)
            return 2
        with open(file_arg, "r", encoding="utf-8") as fh:
            raw = fh.read()
    try:
        payload = json.loads(raw)
    except Exception as e:
        sys.stderr.write("✗ findings JSON 解析失败: %s\n" % e)
        return 2
    findings = payload.get("findings")
    if not isinstance(findings, list) or not findings:
        sys.stderr.write("✗ findings 为空或非数组\n")
        return 2

    # ---- 读 backlog ----
    if not os.path.exists(BACKLOG):
        sys.stderr.write("✗ 找不到 %s\n" % BACKLOG)
        return 2
    with open(BACKLOG, "r", encoding="utf-8") as fh:
        data = json.load(fh)

    # ---- 归类 ----
    added = []          # (module_name, title)
    skipped = []        # (module_name, title)
    for f in findings:
        mod_key = f.get("module", "audit")
        mod, how = _match_module(data, mod_key)
        if mod is None:
            mod = _ensure_audit_module(data)
            how = "audit(兜底)"
        existing = {_norm(it.get("title", "")) for it in mod.get("items", [])}
        title = f.get("title", "(未命名审计项)")
        if _norm(title) in existing:
            skipped.append((mod.get("name", mod.get("id")), title))
            sys.stderr.write("  ⊘ 跳过重复: [%s] %s\n" % (mod.get("name", mod.get("id")), title))
            continue
        item = _build_item(f)
        mod.setdefault("items", []).append(item)
        added.append((mod.get("name", mod.get("id")), title))
        print("  + 归类到 [%s] (%s): %s  | type=%s status=%s" % (
            mod.get("name", mod.get("id")), how, title, item["type"], item["status"]))

    if dry_run:
        print("\n[DRY-RUN] 不会落盘。本应将写入 %d 项、跳过 %d 项重复。" % (len(added), len(skipped)))
        return 0

    # ---- 写回 ----
    data["updated"] = datetime.date.today().isoformat()
    with open(BACKLOG, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
    print("\n✓ 已写入 %s（新增 %d 项，跳过 %d 项重复）" % (BACKLOG, len(added), len(skipped)))

    # ---- 重生成文档 ----
    if not no_regen and os.path.exists(GEN):
        print("→ 重生成 docs/待办清单.md 与看板 …")
        try:
            subprocess.run([sys.executable, GEN], check=True,
                           stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            print("✓ gen_backlog 完成")
        except Exception as e:
            sys.stderr.write("  ⚠ gen_backlog 失败（不影响 backlog.json 写入）: %s\n" % e)
    return 0


def main():
    ap = argparse.ArgumentParser(description="把审计发现归类进 docs/backlog.json")
    ap.add_argument("--file", required=True, help="findings.json 路径，或 - 表示从 stdin 读")
    ap.add_argument("--dry-run", action="store_true", help="仅预览，不写回 backlog.json")
    ap.add_argument("--no-regen", action="store_true", help="写回后不重跑 gen_backlog.py")
    args = ap.parse_args()
    sys.exit(run(args.file, args.dry_run, args.no_regen))


if __name__ == "__main__":
    main()
