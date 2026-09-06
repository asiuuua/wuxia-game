#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
提交队列协同 helper —— 多 AI 并行开发的 git 提交协调器。

协议：
  - 其他窗口（战斗/UI/结缘/…）完成任务并自行验证后，调用 `add` 把
    「待提交文件列表 + 提交信息 + 窗口名」写入自己的 pending_<窗口>.jsonl。
  - PM/背包窗口调用 `flush` 读取所有 pending_*.jsonl，对每条已就绪记录
    精确 `git add` 所列文件、`commit`，再把该行移入 done_<窗口>.jsonl。
  - 全程 append-only，PM 只重写自己拥有的 done_*.jsonl，绝不改写他人文件。

用法：
  python tools/commit_queue.py add --window 战斗窗口 --message "[战斗窗口] M3-4 ..." --files a.gd b.json
  python tools/commit_queue.py flush [--dry-run]
  python tools/commit_queue.py list
  python tools/commit_queue.py pending

注意：flush 只 add 队列列出的文件，绝不 git add -A；不跑 Godot 重验证
（避免与其他窗口抢 .godot 缓存），各窗口自行保证验证。
"""
import argparse
import json
import os
import re
import subprocess
import uuid
from datetime import datetime, timezone, timedelta

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # D:/武侠游戏 (tools/..)
QUEUE_DIR = os.path.join(REPO, ".workbuddy", "commits")
PENDING = "pending_{}.jsonl"
DONE = "done_{}.jsonl"
TZ8 = timezone(timedelta(hours=8))
PUSH_LOCK = os.path.join(QUEUE_DIR, "_push_lock")  # 并发上传互斥锁（不进版本库，见 .gitignore）
PUSH_LOCK_TTL = timedelta(minutes=30)  # 锁超过 30 分钟视为失效，防卡死

# 文件名非法字符（Windows）：保留 < > : " / \ | ? * 及控制符
ILLEGAL = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def win_safe(name: str) -> str:
    return ILLEGAL.sub("_", name).strip() or "unknown"


def now_iso() -> str:
    return datetime.now(TZ8).isoformat(timespec="seconds")


def ensure_dir() -> None:
    os.makedirs(QUEUE_DIR, exist_ok=True)


def git(*args):
    return subprocess.run(
        ["git", "-c", "core.quotepath=false", *args],
        cwd=REPO, capture_output=True, text=True,
    )


def git_state_clean() -> bool:
    """MERGE / REBASE / CHERRY-PICK 进行中则拒绝提交，避免污染。"""
    g = os.path.join(REPO, ".git")
    for marker in ("MERGE_HEAD", "CHERRY_PICK_HEAD"):
        if os.path.exists(os.path.join(g, marker)):
            return False
    if os.path.isdir(os.path.join(g, "rebase-merge")) or os.path.isdir(os.path.join(g, "rebase-apply")):
        return False
    return True


# ---------------------------------------------------------------------------
# 并发上传互斥（硬性条件 2026-09-02：检测到他人上传则本次跳过，等下次）
# 用每次 flush 运行的唯一 session id 标识锁持有者，避免两个 PM flush 互判"自己人"漏拦。
# ---------------------------------------------------------------------------
def _read_push_lock():
    if not os.path.exists(PUSH_LOCK):
        return None
    try:
        with open(PUSH_LOCK, encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"session": "unknown", "window": "unknown", "ts": "1970-01-01T00:00:00+08:00"}


def other_pusher_active(my_session: str):
    """若检测到其他窗口/Agent 正在向仓库上传(push/commit)，返回其信息；否则 None。"""
    data = _read_push_lock()
    if not data:
        return None
    try:
        ts = datetime.fromisoformat(data.get("ts", "1970-01-01T00:00:00+08:00"))
        if datetime.now(TZ8) - ts > PUSH_LOCK_TTL:
            return None  # 过期锁视为失效，避免卡死正常提交
    except Exception:
        return None
    if data.get("session") == my_session:
        return None  # 自己持有的锁不算
    return data


def acquire_push_lock(my_session: str, window: str):
    os.makedirs(QUEUE_DIR, exist_ok=True)
    with open(PUSH_LOCK, "w", encoding="utf-8") as f:
        json.dump({"session": my_session, "window": window, "ts": now_iso()}, f, ensure_ascii=False)


def release_push_lock(my_session: str):
    try:
        if os.path.exists(PUSH_LOCK):
            # 只删自己的锁，避免误删并发新锁
            try:
                cur = json.load(open(PUSH_LOCK, encoding="utf-8"))
            except Exception:
                cur = {}
            if cur.get("session") == my_session:
                os.remove(PUSH_LOCK)
    except Exception:
        pass


def remote_ahead(branch: str = "master") -> bool:
    """git fetch 后，若 origin/<branch> 领先本地，说明有人已先推送 -> True。
    拉取失败或无法判断时返回 False（不误杀，正常放行）。"""
    fr = git("fetch", "origin", branch, "--quiet")
    if fr.returncode != 0:
        return False
    local = git("rev-parse", branch)
    remote = git("rev-parse", "origin/" + branch)
    if local.returncode != 0 or remote.returncode != 0:
        return False
    if local.stdout.strip() == remote.stdout.strip():
        return False
    mb = git("merge-base", "--is-ancestor", branch, "origin/" + branch)
    return mb.returncode == 0


def git_changed_files():
    """返回当前工作树中相对仓库根、有改动（M/A/D/?? 等）的**文件**路径集合。

    注意：porcelain 对未跟踪目录只输出目录级路径（`?? dir/`），若只收集该行，
    队列中逐文件的条目会永远匹配不上而被误判 no-op（a89928a 五域 repositories
    文件被静默漏提交的根因）。因此对未跟踪目录用 `git ls-files --others` 展开为
    其中逐文件路径（自动遵循 .gitignore）。"""
    r = git("status", "--porcelain")
    out = set()
    for line in r.stdout.splitlines():
        if len(line) < 3:
            continue
        p = line[3:].strip()
        out.add(p)
        if line.startswith("??") and p.endswith("/"):
            sub = git("ls-files", "--others", "--exclude-standard", "--", p)
            for f in sub.stdout.splitlines():
                f = f.strip()
                if f:
                    out.add(f)
    return out


def load_lines(path):
    if not os.path.exists(path):
        return []
    res = []
    with open(path, encoding="utf-8") as f:
        for ln in f:
            ln = ln.strip()
            if ln:
                res.append(ln)
    return res


def done_ids(window):
    ids = set()
    for ln in load_lines(os.path.join(QUEUE_DIR, DONE.format(win_safe(window)))):
        try:
            ids.add(json.loads(ln)["id"])
        except Exception:
            pass
    return ids


def mark_done(window, rec, status):
    rec = dict(rec)
    rec["committed_ts"] = now_iso()
    rec["status"] = status
    path = os.path.join(QUEUE_DIR, DONE.format(win_safe(window)))
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")


# ---------------------------------------------------------------------------
# 子命令
# ---------------------------------------------------------------------------
def cmd_add(args):
    ensure_dir()
    if not args.files:
        print("[queue] 错误：--files 不能为空")
        return 1
    rec = {
        "id": uuid.uuid4().hex[:12],
        "ts": now_iso(),
        "window": args.window,
        "branch": args.branch or "master",
        "message": args.message,
        "files": list(args.files),
        "verified": args.verified,
    }
    path = os.path.join(QUEUE_DIR, PENDING.format(win_safe(args.window)))
    with open(path, "a", encoding="utf-8") as f:
        f.write(json.dumps(rec, ensure_ascii=False) + "\n")
    print(f"[queue] 已入队 {rec['id']} -> {path}")
    print(f"        窗口={args.window} 文件数={len(rec['files'])} 已验证={args.verified}")
    return 0


def cmd_flush(args):
    ensure_dir()
    dry = args.dry_run
    my_session = uuid.uuid4().hex[:12]
    if not git_state_clean():
        print("[flush] 跳过：git 处于 MERGE/REBASE/CHERRY-PICK 状态，不安全")
        return 2
    # === 并发上传互斥（硬性条件 2026-09-02）===
    if not dry:
        blocker = other_pusher_active(my_session)
        if blocker is not None:
            print(f"[flush] 跳过：检测到其他窗口正在向仓库上传 "
                  f"({blocker.get('window')} @ {blocker.get('ts')})，本次不提交，改到下次 flush。")
            return 4
        if remote_ahead("master"):
            print(f"[flush] 跳过：远端 origin/master 领先本地（有人已先推送），"
                  f"请先 pull/rebase，本次不提交，改到下次。")
            return 5
        acquire_push_lock(my_session, "PM")
    try:
        changed = git_changed_files()
        pending_files = sorted(
            f for f in os.listdir(QUEUE_DIR)
            if f.startswith("pending_") and f.endswith(".jsonl")
        )
        committed = skipped = errors = 0
        for pf in pending_files:
            window = pf[len("pending_"):-len(".jsonl")]
            did = done_ids(window)
            for ln in load_lines(os.path.join(QUEUE_DIR, pf)):
                try:
                    rec = json.loads(ln)
                except Exception:
                    continue
                rid = rec.get("id")
                if rid in did:
                    continue
                files = rec.get("files", [])
                real = [f for f in files if f in changed]
                if dry:
                    tag = "将提交" if real else "无改动(将跳过)"
                    print(f"[dry-run] {rid} 窗口={window} {tag} ({len(real)}/{len(files)} 文件)")
                    for f in real:
                        print(f"      {f}")
                    committed += 1 if real else 0
                    continue
                if not real:
                    print(f"[skip] {rid} 窗口={window}: 所列文件均无改动，标记 no-op")
                    mark_done(window, rec, "no-op")
                    skipped += 1
                    continue
                ar = subprocess.run(
                    ["git", "-c", "core.quotepath=false", "add", *real],
                    cwd=REPO, capture_output=True, text=True,
                )
                if ar.returncode != 0:
                    print(f"[ERROR] {rid} git add 失败: {ar.stderr.strip()}")
                    errors += 1
                    continue
                cr = git("commit", "-m", rec["message"])
                if cr.returncode != 0:
                    print(f"[ERROR] {rid} commit 失败: {cr.stderr.strip()}")
                    errors += 1
                    continue
                first = cr.stdout.strip().splitlines()[0] if cr.stdout.strip() else ""
                mark_done(window, rec, "committed")
                committed += 1
                print(f"[commit] {rid} 窗口={window} -> {first}")
        if dry:
            print(f"=== dry-run 完成: 将提交 {committed} 条 ===")
        else:
            print(f"=== flush 完成: 提交 {committed}, 跳过(无改动) {skipped}, 错误 {errors} ===")
    finally:
        if not dry:
            release_push_lock(my_session)
    return 0 if errors == 0 else 3


def cmd_list(args):
    ensure_dir()
    files = sorted(
        f for f in os.listdir(QUEUE_DIR)
        if f.startswith("pending_") and f.endswith(".jsonl")
    )
    if not files:
        print("[list] 队列为空")
        return 0
    for pf in files:
        window = pf[len("pending_"):-len(".jsonl")]
        did = done_ids(window)
        pending = [
            json.loads(l) for l in load_lines(os.path.join(QUEUE_DIR, pf))
            if json.loads(l).get("id") not in did
        ]
        print(f"{window}: 待提交 {len(pending)} 条")
        for rec in pending:
            print(f"   {rec['id']} | {len(rec['files'])}文件 | {rec['message'][:50]}")
    return 0


def cmd_pending(args):
    ensure_dir()
    files = sorted(
        f for f in os.listdir(QUEUE_DIR)
        if f.startswith("pending_") and f.endswith(".jsonl")
    )
    for pf in files:
        window = pf[len("pending_"):-len(".jsonl")]
        did = done_ids(window)
        for ln in load_lines(os.path.join(QUEUE_DIR, pf)):
            rec = json.loads(ln)
            if rec.get("id") in did:
                continue
            print(json.dumps(rec, ensure_ascii=False, indent=2))
            print("---")
    return 0


def build_parser():
    p = argparse.ArgumentParser(description="多 AI 提交队列协同器")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("add", help="入队（其他窗口调用）")
    a.add_argument("--window", required=True, help="窗口名，如 战斗窗口")
    a.add_argument("--message", required=True, help="git 提交信息")
    a.add_argument("--files", required=True, nargs="+", help="待提交文件列表（相对仓库根）")
    a.add_argument("--branch", default="master", help="目标分支（仅记录，不切换）")
    a.add_argument("--verified", action="store_true", default=True, help="是否已自行验证（默认是）")
    a.set_defaults(func=cmd_add)

    f = sub.add_parser("flush", help="出队提交（PM 调用）")
    f.add_argument("--dry-run", action="store_true", help="只打印将提交的内容，不实际提交")
    f.set_defaults(func=cmd_flush)

    sub.add_parser("list", help="列出待提交条数").set_defaults(func=cmd_list)
    sub.add_parser("pending", help="打印待提交记录原文").set_defaults(func=cmd_pending)
    return p


if __name__ == "__main__":
    args = build_parser().parse_args()
    raise SystemExit(args.func(args))
