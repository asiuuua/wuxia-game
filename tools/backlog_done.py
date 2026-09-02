#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
把某个待办项标记为「已完成执行」，并记录解决方信息，然后重新生成看板。

用法（AI 解决某任务后调用）：
  python tools/backlog_done.py --module ui --title "主菜单悬停音效" --by "AI-UI" --commit 63263e2 --note "替换为木质按钮音"
  python tools/backlog_done.py --list                 # 列出所有模块与条目，便于定位 --title
  python tools/backlog_done.py --module ui --title "..." --by "AI-UI"   # 不传 --commit/--note 则留空

匹配规则：
  --module 为模块 id（见 backlog.json 的 modules[].id）；
  --title 为条目标题的子串（同模块内唯一匹配），精确优先、模糊次之。
匹配成功后写入：status=done, resolvedBy, resolvedAt(完整时间戳 YYYY-MM-DD HH:MM:SS), commit, resolution(=note)。
--commit 缺省时自动取当前 git HEAD 短哈希（并提示应补真实修复提交），保证「已完成执行」始终带可追溯的日志定位。
随后自动重跑 gen_backlog.py 重新生成 docs/待办清单.md 与 docs/backlog_dashboard.html。
纯标准库。
"""
import os
import sys
import json
import subprocess
import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
JSON_PATH = os.path.join(ROOT, "docs", "backlog.json")
GEN = os.path.join(ROOT, "tools", "gen_backlog.py")


def load():
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def find_item(data, module_id, title_sub):
    mod = next((m for m in data["modules"] if m["id"] == module_id), None)
    if not mod:
        return None, None, "模块不存在：%s（可用：%s）" % (module_id, ", ".join(m["id"] for m in data["modules"]))
    items = mod["items"]
    # 精确
    exact = [it for it in items if it["title"] == title_sub]
    if len(exact) == 1:
        return mod, exact[0], None
    # 子串（唯一）
    sub = [it for it in items if title_sub in it["title"]]
    if len(sub) == 1:
        return mod, sub[0], None
    if len(sub) > 1:
        return None, None, "标题子串「%s」命中多条：%s" % (title_sub, " / ".join(it["title"] for it in sub))
    return None, None, "模块 %s 内未找到含「%s」的条目" % (module_id, title_sub)


def list_items(data):
    for m in data["modules"]:
        print("[%s] %s" % (m["id"], m["name"]))
        for it in m["items"]:
            flag = "✅" if it.get("status") == "done" else ("⛔" if it.get("status") == "blocked" else "·")
            print("    %s (%s/%s) %s" % (flag, it["type"], it.get("status", "open"), it["title"]))


def main():
    args = sys.argv[1:]
    if not args or "--list" in args:
        list_items(load())
        return
    module_id = None
    title_sub = None
    by = "（未署名）"
    commit = ""
    note = ""
    i = 0
    while i < len(args):
        a = args[i]
        if a == "--module":
            module_id = args[i + 1]; i += 2; continue
        if a == "--title":
            title_sub = args[i + 1]; i += 2; continue
        if a == "--by":
            by = args[i + 1]; i += 2; continue
        if a == "--commit":
            commit = args[i + 1]; i += 2; continue
        if a == "--note":
            note = args[i + 1]; i += 2; continue
        i += 1
    if not module_id or not title_sub:
        print("用法：--module <id> --title <子串> [--by 窗口] [--commit 哈希] [--note 说明]  | 或 --list")
        sys.exit(2)

    data = load()
    mod, it, err = find_item(data, module_id, title_sub)
    if err:
        print("ERROR: " + err)
        sys.exit(1)
    if it.get("status") == "done":
        print("提示：该条目已是 done（resolvedBy=%s commit=%s），将更新解决信息。" % (it.get("resolvedBy"), it.get("commit")))

    it["status"] = "done"
    it["resolvedBy"] = by
    it["resolvedAt"] = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    if not commit:
        # 未指定则尽量取当前 HEAD，但仍提醒补真实修复提交
        try:
            commit = subprocess.check_output(
                ["git", "rev-parse", "--short", "HEAD"], cwd=ROOT, stderr=subprocess.DEVNULL
            ).decode().strip()
            print("⚠ 未指定 --commit，已默认取当前 HEAD（%s）。若该修复尚未独立提交，请补 --commit <真实修复哈希> 以利追溯。" % commit)
        except Exception:
            commit = ""
    if commit:
        it["commit"] = commit
    if note:
        it["resolution"] = note

    with open(JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print("已标记完成：[%s] %s  → resolvedBy=%s 时间=%s commit=%s"
          % (mod["id"], it["title"], by, it["resolvedAt"], commit))
    if commit:
        print("   追溯改动：git show %s" % commit)
        print("   一键复原：git revert %s   （出问题回退用）" % commit)
        print("   变更日志：docs/更改日志.md 中搜 %s" % commit)

    # 重新生成看板
    rc = subprocess.call([sys.executable, GEN])
    sys.exit(rc)


if __name__ == "__main__":
    main()
