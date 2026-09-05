# -*- coding: utf-8 -*-
"""
run_benchmarks.py — GATE40+ 性能基准门禁壳（17 图 SBP-4/SBP-R07/R08/R09）
==========================================================================
职责只有三件：跑基准 → 比对基线 → 报 FUNCTIONAL PASS / RELEASE PASS。
预算值不写死在代码/宪法/施工图（§94A 规则 1），由实测后登记进基线文件。

首批 3 项基准（SBP-3 推荐 Boot/Save/Combat Turn）：
  boot            引擎启动墙钟（--quit 中位数，进程外测量，3 次取中位）
  save_roundtrip  存档全链路（bench_main.tscn 进程内测量）
  combat_turn     战斗回合结算（bench_main.tscn 进程内测量）

基线文件：tools/benchmarks/baselines/<benchmark_id>.json，格式冻结（SBP-R07）：
  { benchmark_id, input_scale, environment, result_distribution, allowed_variance,
    version, baseline_ms }
  文档六字段缺一 = 格式 FATAL；baseline_ms 为实测登记的预算值（毫秒）。

双 PASS 状态机（SBP-R09）：
  |measured - baseline| / baseline <= allowed_variance  → RELEASE PASS
  基准可跑、结果有效但超预算                            → FUNCTIONAL PASS（≠ RELEASE PASS）

用法：
  python tools/run_benchmarks.py               # tier 模式：FUNCTIONAL PASS 即 0（verify_all --tier performance 调用）
  python tools/run_benchmarks.py --release     # 发布模式：全部 RELEASE PASS 才 0（build_release 第3项强制）
  python tools/run_benchmarks.py --register    # 用本轮实测登记/刷新基线（显式动作，须人审 diff）
"""
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BASELINE_DIR = os.path.join(HERE, "benchmarks", "baselines")
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/.workbuddy/binaries/godot/Godot_v4.7.2-stable_win64_console.exe"
)
BOOT_RUNS = 3

# SBP-R07 格式冻结字段（§216 六字段）+ 实测预算值
REQUIRED_FIELDS = ["benchmark_id", "input_scale", "environment",
                   "result_distribution", "allowed_variance", "version"]


def _env():
    env = dict(os.environ)
    profile = os.path.expanduser("~")
    env.setdefault("USERPROFILE", profile)
    env.setdefault("APPDATA", os.path.join(profile, "AppData", "Roaming"))
    return env


def _run_bench_scene():
    """跑基准场景，收集 BENCH_RESULT 行。"""
    cmd = [GODOT, "--headless", "--path", ROOT, "res://tools/benchmarks/bench_main.tscn"]
    p = subprocess.run(cmd, capture_output=True, text=True, errors="replace",
                       cwd=ROOT, env=_env(), timeout=300)
    results = {}
    for ln in (p.stdout or "").splitlines():
        if ln.startswith("BENCH_RESULT "):
            try:
                d = json.loads(ln[len("BENCH_RESULT "):])
                results[d.get("benchmark_id", "?")] = d
            except json.JSONDecodeError:
                print("   ✗ BENCH_RESULT 行解析失败: %s" % ln[:120])
    return results, p.returncode


def _measure_boot():
    """boot 基准：--quit 墙钟，3 次取中位（毫秒）。"""
    times = []
    for _ in range(BOOT_RUNS):
        t0 = time.perf_counter()
        subprocess.run([GODOT, "--headless", "--path", ROOT, "--quit"],
                       capture_output=True, cwd=ROOT, env=_env(), timeout=300)
        times.append((time.perf_counter() - t0) * 1000.0)
    times.sort()
    return times[BOOT_RUNS // 2]


def load_baselines():
    baselines = {}
    if not os.path.isdir(BASELINE_DIR):
        return baselines
    for fn in sorted(os.listdir(BASELINE_DIR)):
        if not fn.endswith(".json"):
            continue
        path = os.path.join(BASELINE_DIR, fn)
        try:
            with open(path, encoding="utf-8") as f:
                d = json.load(f)
        except Exception as e:
            print("   ✗ 基线文件读取失败 %s: %s" % (fn, e))
            continue
        missing = [k for k in REQUIRED_FIELDS if not str(d.get(k, "")).strip()]
        if missing or not isinstance(d.get("baseline_ms"), (int, float)) or d["baseline_ms"] <= 0:
            print("   ✗ 基线格式 FATAL（SBP-R07）: %s 缺 %s%s"
                  % (fn, "/".join(missing), "" if missing else "/baseline_ms 有效值"))
            continue
        baselines[d["benchmark_id"]] = d
    return baselines


def compare(bid, measured, base):
    variance = abs(measured - base["baseline_ms"]) / base["baseline_ms"]
    release = variance <= float(base["allowed_variance"])
    return release, variance


def main():
    args = sys.argv[1:]
    release_mode = "--release" in args
    register_mode = "--register" in args
    print("══════ GATE40 · Benchmark 性能基准（17图 SBP，可选 tier） ══════")

    print("── 跑基准（save_roundtrip / combat_turn 进程内；boot 墙钟 ×%d）──" % BOOT_RUNS)
    results, code = _run_bench_scene()
    boot_ms = _measure_boot()
    results["boot"] = {
        "benchmark_id": "boot",
        "median_ms": round(boot_ms, 1),
        "input_scale": "warm --quit median-of-%d" % BOOT_RUNS,
        "result_distribution": "median",
    }
    if code != 0:
        print("✗ 基准场景退出码 %d（有基准执行失败），门禁即红" % code)
        return 1

    measured_all = all(isinstance(r.get("median_ms"), (int, float)) and r["median_ms"] > 0
                       for r in results.values())
    if not measured_all:
        for bid, r in results.items():
            if not isinstance(r.get("median_ms"), (int, float)):
                print("   ✗ %s 缺有效 median_ms: %s" % (bid, json.dumps(r, ensure_ascii=False)[:160]))
        return 1

    # --register：用本轮实测登记/刷新基线（显式动作）
    if register_mode:
        os.makedirs(BASELINE_DIR, exist_ok=True)
        for bid, r in results.items():
            base = {
                "benchmark_id": bid,
                "input_scale": r.get("input_scale", ""),
                "environment": "win64-local-dev",
                "result_distribution": r.get("result_distribution", "median"),
                "allowed_variance": 0.5,
                "version": "0.5.0",
                "baseline_ms": round(float(r["median_ms"]), 2),
            }
            out = os.path.join(BASELINE_DIR, "%s.json" % bid)
            with open(out, "w", encoding="utf-8") as f:
                json.dump(base, f, ensure_ascii=False, indent=2)
            print("   ✓ 已登记 %s → baseline_ms=%s（±%s）"
                  % (out, base["baseline_ms"], base["allowed_variance"]))
        print("══ 结论：基线已登记，请人审 diff 后随提交入库 ══")
        return 0

    baselines = load_baselines()
    all_functional = True
    all_release = True
    for bid in sorted(results):
        m = results[bid]
        base = baselines.get(bid)
        if base is None:
            print("   ✗ %s: 无基线文件（SBP-R07）→ 请先 `--register` 实测登记并人审" % bid)
            all_functional = False
            continue
        if str(m.get("input_scale", "")) != str(base.get("input_scale", "")):
            print("   ⚠ %s: input_scale 变化（%s → 基线 %s），结果可能与预算不可比"
                  % (bid, m.get("input_scale"), base.get("input_scale")))
        release, variance = compare(bid, float(m["median_ms"]), base)
        all_functional = all_functional and True   # 能跑到这里 = FUNCTIONAL
        all_release = all_release and release
        tag = "RELEASE PASS ✓" if release else "FUNCTIONAL PASS（超 Release Budget，SBP-R09）"
        print("   %s: %.1fms vs 基线 %.1fms（±%s，偏差 %.1f%%）→ %s"
              % (bid, float(m["median_ms"]), base["baseline_ms"],
                 base["allowed_variance"], variance * 100, tag))
    print("══ 结论：%s ══"
          % ("RELEASE PASS ✓ 全部在预算内" if all_release
             else ("FUNCTIONAL PASS ⚠ 功能正确但超预算，禁止作为 RELEASE 依据" if all_functional
                   else "FAIL ✗ 有基准无法执行或无基线")))
    if release_mode:
        return 0 if all_release else 1
    return 0 if all_functional else 1


if __name__ == "__main__":
    sys.exit(main())
