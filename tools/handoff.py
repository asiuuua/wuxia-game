#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
跨窗口协作隐患传递板 —— 多 AI 并行开发的「派单 / 认领 / 交接」协调器。

两阶段交接协议：
  1. 派单(issue)：某窗口发现需要其它窗口修的隐患/任务，写入 handoff_out_<派单方>.jsonl，
     指定 to=执行窗口、files/desc/verify/followup。
  2. 认领(claim)：执行窗口隔段时间扫描，认领 to==自己的 open 任务，写入 handoff_status_<执行方>.jsonl。
  3. 执行方自验(done)：执行窗口修完，按 verify 字段自行核验，标记 done。
  4. 派单方后续(followup)：派单方看到 done，执行自己的后续依赖（followup），收尾。
  5. 关闭(close)：双方确认后 close。

状态由「事件重放」推导（open/claimed/done/followup/closed），全程 append-only：
  - 派单方只写自己的 handoff_out_<窗口>.jsonl；
  - 执行方/派单方只写自己的 handoff_status_<窗口>.jsonl；
  无跨窗口文件锁竞争。

用法：
  python tools/handoff.py issue --from 战斗窗口 --to 背包窗口 --title "修复X" --desc "..." \
      --files a.gd --verify "单测通过" --followup "无"
  python tools/handoff.py scan --window 背包窗口
  python tools/handoff.py claim --by 背包窗口 --id <id>
  python tools/handoff.py done --by 背包窗口 --id <id> --note "已修复并自验"
  python tools/handoff.py followup --by 战斗窗口 --id <id> --note "后续已做"
  python tools/handoff.py close --by 背包窗口 --id <id>
  python tools/handoff.py dashboard
"""
import argparse
import json
import os
import re
import uuid
from datetime import datetime, timezone, timedelta

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # D:/武侠游戏 (tools/..)
BOARD = os.path.join(REPO, ".workbuddy", "handovers")
OUT = "handoff_out_{}.jsonl"        # 派单方写：任务创建
STATUS = "handoff_status_{}.jsonl"  # 执行方/派单方写：claim/done/followup/close 事件
TZ8 = timezone(timedelta(hours=8))

ILLEGAL = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def ws(name: str) -> str:
    return ILLEGAL.sub("_", name).strip() or "unknown"


def now() -> str:
    return datetime.now(TZ8).isoformat(timespec="seconds")


def ensure() -> None:
    os.makedirs(BOARD, exist_ok=True)


def read_lines(path):
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return [l.strip() for l in f if l.strip()]


def append(rec, filename):
    path = os.path.join(BOARD, filename)
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


def all_issues():
    out = []
    for f in os.listdir(BOARD):
        if f.startswith("handoff_out_") and f.endswith(".jsonl"):
            for l in read_lines(os.path.join(BOARD, f)):
                try:
                    out.append(json.loads(l))
                except Exception:
                    pass
    return out


def all_events():
    evs = []
    for f in os.listdir(BOARD):
        if f.startswith("handoff_status_") and f.endswith(".jsonl"):
            for l in read_lines(os.path.join(BOARD, f)):
                try:
                    evs.append(json.loads(l))
                except Exception:
                    pass
    return evs


def state_of(task_id, evs):
    st = "open"
    claim_by = done_by = followup_by = close_by = None
    note_done = note_followup = None
    for e in evs:
        if e.get("id") != task_id:
            continue
        a = e.get("action")
        if a == "claim":
            st, claim_by = "claimed", e.get("by")
        elif a == "done":
            st, done_by, note_done = "done", e.get("by"), e.get("note")
        elif a == "followup":
            st, followup_by, note_followup = "followup", e.get("by"), e.get("note")
        elif a == "close":
            st, close_by = "closed", e.get("by")
    return dict(state=st, claim_by=claim_by, done_by=done_by,
                followup_by=followup_by, close_by=close_by,
                note_done=note_done, note_followup=note_followup)


def cmd_issue(args):
    ensure()
    rec = {
        "id": uuid.uuid4().hex[:12],
        "ts": now(),
        "from": args.frm,
        "to": args.to,
        "title": args.title,
        "desc": args.desc,
        "files": list(args.files),
        "verify": args.verify,
        "followup": args.followup,
    }
    append(rec, OUT.format(ws(args.frm)))
    print(f"[handoff] 已派单 {rec['id']} {args.frm} -> {args.to}: {args.title}")
    return 0


def _event(action, args, note_field="note"):
    ensure()
    rec = {"id": args.id, "ts": now(), "by": args.by, "action": action,
           "note": getattr(args, note_field) or ""}
    append(rec, STATUS.format(ws(args.by)))
    print(f"[handoff] {args.by} {action} {args.id}")
    return 0


def cmd_claim(args):
    return _event("claim", args)


def cmd_done(args):
    return _event("done", args)


def cmd_followup(args):
    return _event("followup", args)


def cmd_close(args):
    return _event("close", args)


def cmd_scan(args):
    issues = all_issues()
    evs = all_events()
    hits = []
    for it in issues:
        if it.get("to") != args.window:
            continue
        if state_of(it["id"], evs)["state"] in ("open", "claimed"):
            hits.append(it)
    if not hits:
        print(f"[scan] {args.window}: 无待认领/进行中任务")
        return 0
    for it in hits:
        s = state_of(it["id"], evs)
        print(f"  {it['id']} [{s['state']}] from={it['from']} 标题={it['title']}")
        print(f"      文件={it['files']}")
        print(f"      核验={it['verify']}")
        print(f"      后续={it['followup']}")
    return 0


def cmd_dashboard(args):
    issues = all_issues()
    evs = all_events()
    if not issues:
        print("[dashboard] 暂无协作任务")
        return 0
    for it in sorted(issues, key=lambda x: x["ts"]):
        s = state_of(it["id"], evs)
        print(f"{it['id']} [{s['state']}] {it['from']} -> {it['to']}: {it['title']}")
        if s["claim_by"]:
            print(f"      认领={s['claim_by']}")
        if s["note_done"]:
            print(f"      done备注={s['note_done']}")
        if s["note_followup"]:
            print(f"      followup备注={s['note_followup']}")
    return 0


def build_parser():
    p = argparse.ArgumentParser(description="跨窗口协作隐患传递板")
    sub = p.add_subparsers(dest="cmd", required=True)

    i = sub.add_parser("issue", help="派单（发现需他窗做的事）")
    i.add_argument("--from", dest="frm", required=True, help="派单方窗口名")
    i.add_argument("--to", required=True, help="执行方窗口名")
    i.add_argument("--title", required=True, help="任务标题")
    i.add_argument("--desc", default="", help="详细描述")
    i.add_argument("--files", nargs="+", default=[], help="涉及文件（相对仓库根）")
    i.add_argument("--verify", default="", help="执行方自验标准")
    i.add_argument("--followup", default="", help="派单方后续依赖动作")
    i.set_defaults(func=cmd_issue)

    for name, act, help in [
        ("claim", "claim", "认领（执行方）"),
        ("done", "done", "执行方自验完成"),
        ("followup", "followup", "派单方做后续依赖"),
        ("close", "close", "关闭"),
    ]:
        sp = sub.add_parser(name, help=help)
        sp.add_argument("--by", required=True, help="操作方窗口名")
        sp.add_argument("--id", required=True, help="任务 id")
        sp.add_argument("--note", default="", help="备注")
        sp.set_defaults(func=(lambda a, _act=act: _event(_act, a)))

    sc = sub.add_parser("scan", help="查看派给本窗口的待办")
    sc.add_argument("--window", required=True, help="窗口名")
    sc.set_defaults(func=cmd_scan)

    sub.add_parser("dashboard", help="全局任务状态").set_defaults(func=cmd_dashboard)
    return p


if __name__ == "__main__":
    args = build_parser().parse_args()
    raise SystemExit(args.func(args))
