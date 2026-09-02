#!/usr/bin/env python3
# tools/change_log.py
# 累计更改日志：登记每次修改 + 可查询「某模块最近改了什么」
# 纯标准库，随仓库走，多 AI 协同共享同一份 docs/更改日志.md。
#
# 纪律（多 AI 协同铁律，详见 change-tracking skill）：
#   1. 任何文件修改/提交，必须先 `add` 登记一行；共享地基改动还须写 `变更通告_*`。
#   2. 调试任何 BUG 前，先 `query --module <嫌疑模块>` 看最近改了什么；
#      再交叉 `git log -- <文件>` 与 `tools/handoff.py dashboard` 确认是不是别人的回归。
#   3. 若 BUG 根因是某次旧改动，修复后在该行「关联」注明「回归自 <commit>」。
#
# 用法：
#   python tools/change_log.py add --commit abc1234 --module BattleScene \
#       --scope "scenes/gameplay/battle" --what "加 await 守卫防释放后崩" \
#       --impact "无回归" --ref "BUG-12"
#   python tools/change_log.py notice --title "BattleScene await 守卫" --module BattleScene \
#       --scope "scenes/gameplay/battle" --what "..." --impact "..." 
#   python tools/change_log.py query --module BattleScene
#   python tools/change_log.py query --keyword "冻结" --days 7
#   python tools/change_log.py backfill [--since 2026-08-20] [--all]

import argparse
import os
import subprocess
import sys
from datetime import date, timedelta

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LOG = os.path.join(REPO, "docs", "更改日志.md")

HEADER = """# 更改日志（累计 · 机器可查）

> **多 AI 协同铁律（change-tracking）**
> 1. 任何文件修改/提交，必须先 `python tools/change_log.py add` 登记一行；共享地基
>    （EventBus / ConfigManager / core/enums/* / screens.json / strings.csv / GameManager / GameState）
>    改动还须额外写 `docs/变更通告_YYYY-MM-DD_主题.md`。
> 2. **调试任何 BUG 前，先 `python tools/change_log.py query --module <嫌疑模块>` 看最近改了什么**；
>    再交叉 `git log -- <文件>` 与 `tools/handoff.py dashboard` 确认是不是别人的回归（避免改半天是小改动引起的）。
> 3. 若 BUG 根因是某次旧改动，修复后在「关联」列注明「回归自 <commit>」。

列：日期 | commit | 模块 | 改动范围 | 改了什么 | 影响/风险 | 关联通告/派单
"""

TABLE_HEADER = "| 日期 | commit | 模块 | 改动范围 | 改了什么 | 影响/风险 | 关联 |\n|---|---|---|---|---|---|---|"


def _ensure_log():
    if not os.path.exists(LOG):
        with open(LOG, "w", encoding="utf-8") as f:
            f.write(HEADER)
            f.write("\n")
            f.write(TABLE_HEADER)
            f.write("\n")
    else:
        # 若文件存在但没有表头（旧格式），补表头
        with open(LOG, "r", encoding="utf-8") as f:
            txt = f.read()
        if "| 日期 | commit |" not in txt:
            with open(LOG, "w", encoding="utf-8") as f:
                f.write(HEADER)
                f.write("\n")
                f.write(TABLE_HEADER)
                f.write("\n")
                f.write(txt)


def _read_rows():
    """返回 (data_rows, existing_commits)。data_rows: list of (lineno, [cells])。"""
    rows = []
    commits = set()
    with open(LOG, "r", encoding="utf-8") as f:
        for i, line in enumerate(f, 1):
            s = line.rstrip("\n")
            if not s.startswith("|"):
                continue
            if s.startswith("|---"):
                continue
            cells = [c.strip() for c in s.strip().strip("|").split("|")]
            if cells and cells[0] == "日期":
                continue
            if len(cells) < 7:
                continue
            rows.append((i, cells))
            if len(cells) > 1:
                commits.add(cells[1])
    return rows, commits


def _esc(v):
    return str(v).replace("|", "\\|").replace("\n", " ").strip()


def add_row(commit, module, scope, what, impact, ref, day=None):
    _ensure_log()
    day = day or date.today().isoformat()
    commit = commit[:7] if commit and len(commit) > 7 else (commit or "")
    row = "| {} | {} | {} | {} | {} | {} | {} |\n".format(
        _esc(day), _esc(commit), _esc(module), _esc(scope),
        _esc(what), _esc(impact), _esc(ref),
    )
    with open(LOG, "a", encoding="utf-8") as f:
        f.write(row)
    print("已登记 →", row.strip())


def cmd_add(args):
    add_row(args.commit, args.module, args.scope, args.what, args.impact, args.ref, args.date)


def cmd_notice(args):
    """写一份变更通告，并在 changelog 登记一行（关联指向该通告）。"""
    day = args.date or date.today().isoformat()
    slug = "".join(c if (c.isalnum() or c in "-_") else "_" for c in args.title)
    slug = slug.strip("_")[:40]
    path = os.path.join(REPO, "docs", "变更通告_{}_{}.md".format(day, slug))
    tpl = """# 变更通告 {day} · {title}

> 模块：{module}　改动范围：{scope}　commit：{commit}

## 变更项
{what}

## 变更原因
（为何要改；修复了什么 BUG / 满足什么需求）

## 影响面
（哪些模块/功能/数据会受影响；是否动共享地基）

## 回滚方案
（如何回退：git revert <commit> / 改回哪几个文件）

## 协同方需知
（其他 AI 窗口 / 模块需注意什么；是否要重跑契约总表 / 双闸门）

## 关联
- commit：{commit}
- changelog：docs/更改日志.md
""".format(day=day, title=args.title, module=args.module, scope=args.scope,
           commit=args.commit or "（待提交后补）", what=args.what or "（见 commit）")
    with open(path, "w", encoding="utf-8") as f:
        f.write(tpl)
    ref = os.path.basename(path)
    add_row(args.commit, args.module, args.scope, args.what, args.impact, ref, day)
    print("已写变更通告 →", path)


def cmd_query(args):
    rows, _ = _read_rows()
    today = date.today()
    since = None
    if args.days:
        since = (today - timedelta(days=args.days)).isoformat()
    if args.since:
        since = args.since
    kw = args.keyword.lower() if args.keyword else None
    mod = args.module.lower() if args.module else None
    hits = 0
    for lineno, cells in rows:
        if since and cells[0] < since:
            continue
        if mod and mod not in cells[2].lower() and mod not in cells[3].lower():
            continue
        if kw:
            if not any(kw in c.lower() for c in cells):
                continue
        hits += 1
        print("L{} | {} | {} | {} | {} | {} | 关联:{}".format(
            lineno, cells[0], cells[1], cells[2], cells[3], cells[4], cells[6]))
    print("---")
    print("命中 {} 行（共 {} 行）".format(hits, len(rows)))
    if hits == 0:
        print("提示：无近期改动命中。仍建议 `git log -- <文件>` 与 `tools/handoff.py dashboard` 交叉确认。")


def cmd_backfill(args):
    """从 git log 回填历史提交到 changelog（按 commit 去重）。"""
    _ensure_log()
    _, existing = _read_rows()
    since = args.since or ""
    rng = ["log", "--pretty=format:###%n%H%n%cd%n%an%n%s", "--date=short", "--name-only"]
    if not args.all:
        rng.append("--since={}".format(since) if since else "--since=2026-01-01")
    try:
        out = subprocess.check_output(
            ["git", "-c", "core.quotepath=false", "-C", REPO] + rng,
            encoding="utf-8", stderr=subprocess.STDOUT)
    except Exception as e:  # noqa
        print("git log 失败：", e)
        return
    blocks = out.split("###")
    added = 0
    for b in blocks:
        lines = [l for l in b.split("\n") if l != ""]
        if len(lines) < 4:
            continue
        full = lines[0].strip()
        short = full[:7]
        if short in existing:
            continue
        day = lines[1].strip()
        author = lines[2].strip()
        subject = lines[3].strip()
        files = lines[4:]
        # 模块 = 改动文件的顶层目录集合；改动范围 = 各级目录（含子路径，便于按子模块 grep）
        tops = []
        dirs = []
        for fp in files:
            fp = fp.replace("\\", "/")
            top = fp.split("/")[0] if "/" in fp else fp
            d = os.path.dirname(fp)
            if top and top not in tops:
                tops.append(top)
            if d and d not in dirs:
                dirs.append(d)
        if not tops:
            tops = ["（无路径）"]
        module = "多模块" if len(tops) > 2 else "/".join(tops)
        scope = " ".join(dirs[:6])
        if len(" ".join(dirs)) > 140:
            scope = scope + " …"
        impact = "（历史回填）"
        ref = "author:{}".format(author)
        add_row(short, module, scope, subject, impact, ref, day)
        existing.add(short)
        added += 1
    print("回填完成，新增 {} 行。".format(added))


def main():
    p = argparse.ArgumentParser(description="累计更改日志（多 AI 协同）")
    sub = p.add_subparsers(dest="cmd")

    a = sub.add_parser("add", help="登记一次修改")
    a.add_argument("--commit", default="")
    a.add_argument("--module", required=True)
    a.add_argument("--scope", default="")
    a.add_argument("--what", required=True)
    a.add_argument("--impact", default="")
    a.add_argument("--ref", default="")
    a.add_argument("--date", default="")
    a.set_defaults(func=cmd_add)

    n = sub.add_parser("notice", help="写变更通告并登记一行")
    n.add_argument("--title", required=True)
    n.add_argument("--module", required=True)
    n.add_argument("--scope", default="")
    n.add_argument("--what", default="")
    n.add_argument("--impact", default="")
    n.add_argument("--commit", default="")
    n.add_argument("--date", default="")
    n.set_defaults(func=cmd_notice)

    q = sub.add_parser("query", help="查询某模块/关键词近期改动")
    q.add_argument("--module", default="")
    q.add_argument("--keyword", default="")
    q.add_argument("--since", default="")
    q.add_argument("--days", type=int, default=0)
    q.set_defaults(func=cmd_query)

    b = sub.add_parser("backfill", help="从 git log 回填历史")
    b.add_argument("--since", default="")
    b.add_argument("--all", action="store_true")
    b.set_defaults(func=cmd_backfill)

    args = p.parse_args()
    if not args.cmd:
        p.print_help()
        sys.exit(1)
    args.func(args)


if __name__ == "__main__":
    main()
