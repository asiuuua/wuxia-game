#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
write_lease.py — 多 AI 并行写租约（宪法 0-G.8 AI 并行禁区，C1 基础设施 2026-09-06）

宪法依据：0-G.8「以下 Scope 不允许无锁并行：Kernel / Public Command / Public Query /
Public Event / Transaction Contract」——本工具是这条禁令的物理载体（Write Lease）。
与 handoff.py 同范式：append-only 事件流（lease_<窗口>.jsonl），事件重放推导活跃租约，
无跨窗口文件锁竞争。

Scope 分级（0-G.8）：
  FROZEN_SCOPE（无租约禁止动）：core/kernel/、Public Command/Query/Event 面、
                               Transaction Contract、EventBus.gd、arch_linter_baseline.json
  NORMAL_SCOPE（建议持租约，不强制）：其余生产目录

用法:
  python tools/write_lease.py claim --window 架构窗 --paths "core/kernel/,autoload/SaveManager.gd"
  python tools/write_lease.py check --paths "core/kernel/transaction/"     # 冲突检查（exit 1=有活跃冲突租约）
  python tools/write_lease.py release --window 架构窗
  python tools/write_lease.py list
租期默认 4 小时（LEASE_HOURS），过期自动失效（事件重放时按时间戳推导）。
"""
import argparse
import json
import os
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LEASE_DIR = os.path.join(ROOT, ".workbuddy", "leases")
LEASE_HOURS = 4.0

FROZEN_SCOPE_PREFIX = (
    "core/kernel/", "core/execution/", "core/effect_registry.gd",
    "autoload/EventBus.gd", "tools/arch_linter_baseline.json",
)


def _lease_file(window: str) -> str:
    return os.path.join(LEASE_DIR, "lease_%s.jsonl" % window)


def _append(window: str, event: dict) -> None:
    os.makedirs(LEASE_DIR, exist_ok=True)
    event["ts"] = time.time()
    with open(_lease_file(window), "a", encoding="utf-8") as f:
        f.write(json.dumps(event, ensure_ascii=False) + "\n")


def active_leases(now: float = None) -> list:
    """事件重放：返回未过期且未 release 的租约 [{window, paths, claimed_ts}]。"""
    if now is None:
        now = time.time()
    out = []
    if not os.path.isdir(LEASE_DIR):
        return out
    for fn in os.listdir(LEASE_DIR):
        if not (fn.startswith("lease_") and fn.endswith(".jsonl")):
            continue
        window = fn[len("lease_"):-len(".jsonl")]
        events = []
        try:
            with open(os.path.join(LEASE_DIR, fn), encoding="utf-8") as f:
                for ln in f:
                    ln = ln.strip()
                    if ln:
                        events.append(json.loads(ln))
        except (OSError, ValueError):
            continue
        held = None
        for ev in events:
            if ev.get("op") == "claim":
                held = {"window": window, "paths": list(ev.get("paths", [])),
                        "claimed_ts": ev.get("ts", 0)}
            elif ev.get("op") == "release":
                held = None
        if held is not None:
            age_hours = (now - held["claimed_ts"]) / 3600.0
            if age_hours > LEASE_HOURS:
                print("  ℹ 租约过期（%.1fh > %.0fh）自动失效: %s" % (age_hours, LEASE_HOURS, held["window"]))
                continue
            out.append(held)
    return out


def paths_conflict(paths_a: list, paths_b: list) -> list:
    """目录前缀 / 文件精确 / 双向包含 冲突判定。返回冲突对列表。"""
    conflicts = []
    for a in paths_a:
        a_n = a.strip().strip("/").replace("\\", "/")
        for b in paths_b:
            b_n = b.strip().strip("/").replace("\\", "/")
            if a_n == b_n or a_n.startswith(b_n + "/") or b_n.startswith(a_n + "/"):
                conflicts.append("%s ↔ %s" % (a_n, b_n))
    return conflicts


def main() -> int:
    ap = argparse.ArgumentParser(description="多 AI 并行写租约（宪法 0-G.8）")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p_claim = sub.add_parser("claim")
    p_claim.add_argument("--window", required=True)
    p_claim.add_argument("--paths", required=True, help="逗号分隔目录/文件（res 相对路径）")

    p_check = sub.add_parser("check")
    p_check.add_argument("--paths", required=True)
    p_check.add_argument("--window", default="")

    p_release = sub.add_parser("release")
    p_release.add_argument("--window", required=True)

    sub.add_parser("list")
    args = ap.parse_args()

    if args.cmd == "claim":
        paths = [p.strip() for p in args.paths.split(",") if p.strip()]
        others = [h for h in active_leases() if h["window"] != args.window]
        for h in others:
            conf = paths_conflict(paths, h["paths"])
            if conf:
                print("✗ 租约冲突：%s 持有 [%s] 与请求 [%s] 重叠："
                      % (h["window"], ", ".join(h["paths"]), ", ".join(conf)))
                return 1
        _append(args.window, {"op": "claim", "paths": paths})
        print("✓ %s 已持租约: %s（%.0fh 后过期）" % (args.window, ", ".join(paths), LEASE_HOURS))
        return 0

    if args.cmd == "check":
        paths = [p.strip() for p in args.paths.split(",") if p.strip()]
        frozen_touched = [p for p in paths if any(p.replace("\\", "/").startswith(fs) for fs in FROZEN_SCOPE_PREFIX)]
        if frozen_touched:
            print("ℹ FROZEN_SCOPE 触及（0-G.8 无锁并行禁区，必须持租约）: %s" % ", ".join(frozen_touched))
        conflicts_all = []
        for h in active_leases():
            if args.window and h["window"] == args.window:
                continue   # 自己的租约不算冲突
            conf = paths_conflict(paths, h["paths"])
            if conf:
                conflicts_all.append("%s: %s" % (h["window"], ", ".join(conf)))
        if conflicts_all:
            print("✗ 活跃租约冲突：%s" % "; ".join(conflicts_all))
            return 1
        print("✓ 无租约冲突（活跃租约 %d 份）" % len(active_leases()))
        return 0

    if args.cmd == "release":
        _append(args.window, {"op": "release"})
        print("✓ %s 租约已释放" % args.window)
        return 0

    if args.cmd == "list":
        leases = active_leases()
        print("活跃租约 %d 份（租期 %.0fh）:" % (len(leases), LEASE_HOURS))
        for h in leases:
            age = (time.time() - h["claimed_ts"]) / 3600.0
            print("  %s（%.1fh 前）: %s" % (h["window"], age, ", ".join(h["paths"])))
        return 0

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
