# -*- coding: utf-8 -*-
"""build_release.py — 18 图 RH-7 构建发布流水线（P-RH5 收口）

编排既有门禁，不改生产源码（RH-7 冻结条款）：
  ① 双闸门（verify_all.py 全量，含 GATE6 引用+ID 层）
  ② provenance.json 八字段生成（RH-2：禁手写，只由本脚本产出）
  ③ Godot 导出（Win 立即可用；Android 归 Phase4 实测，RH-4）
  ④ 产物命名冻结（RH-3）：wuxiajianghu_{game_version}_{build_id}_{platform}.{exe|apk}
  ⑤ 产物 sha256 校验和输出

Release Gate（RH-4）编排现状：
  第1项 双闸门 / 第2项 GATE06 / 第5项 Provenance —— 本脚本强制。
  第3项 GATE40+ 性能基准 —— tools/run_benchmarks.py --release 强制（SBP-R09：
      全部 RELEASE PASS 才放行；FUNCTIONAL PASS 不得作为发布依据）。
  第4项 迁移 golden 对 —— 夹具在位检查 + 双闸门 GATE2 单元套件常绿强制（SV-R03）。
  （原 [PENDING] 两项已于 2026-09-06 落地，本注释为 17图 SBP / 13图 SV-3 收口留痕。）

用法：
  python tools/build_release.py                 # 全流程（门禁+provenance+导出）
  python tools/build_release.py --skip-gates    # 跳过门禁（仅调试用，禁止正式发布）
  python tools/build_release.py --provenance-only  # 只刷新 provenance.json
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_GODOT = r"C:\Users\Administrator\.workbuddy\binaries\godot\Godot_v4.7.2-stable_win64_console.exe"


def run(cmd, **kw):
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)


def read_project_version():
    text = open(os.path.join(ROOT, "project.godot"), encoding="utf-8").read()
    m = re.search(r'config/version="([^"]+)"', text)
    if not m:
        print("✗ project.godot 缺 application/config/version（18图 RH-1）"); sys.exit(1)
    return m.group(1)


def read_save_schema_version():
    text = open(os.path.join(ROOT, "autoload", "SaveManager.gd"), encoding="utf-8").read()
    m = re.search(r'const SAVE_VERSION\s*:=\s*"([^"]+)"', text)
    if not m:
        print("✗ SaveManager.gd 缺 SAVE_VERSION"); sys.exit(1)
    return m.group(1)


def content_fingerprint():
    """content_version：data/configs 全树 sha256（05 图 content_fingerprint 同源口径）。"""
    h = hashlib.sha256()
    base = os.path.join(ROOT, "data", "configs")
    paths = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames[:] = [d for d in dirnames if d != "ui"]
        for fn in filenames:
            paths.append(os.path.relpath(os.path.join(dirpath, fn), base).replace(os.sep, "/"))
    for rel in sorted(paths):
        h.update(rel.encode("utf-8"))
        h.update(open(os.path.join(base, rel), "rb").read())
    return h.hexdigest()[:16]


def git(*args):
    return run(["git"] + list(args)).stdout.strip()


def make_provenance():
    game_version = read_project_version()
    save_schema = read_save_schema_version()
    head = git("rev-parse", "HEAD")
    dirty = [l for l in git("status", "--porcelain").splitlines()
             if l.strip() and "provenance.json" not in l and not l.strip().startswith("?? build/")]
    if dirty:
        print("✗ 工作树不干净（发布必须来自干净提交，RH-4 第5项）：")
        for l in dirty[:10]:
            print("   " + l)
        sys.exit(1)
    prov = {
        "build_id": "b" + time.strftime("%Y%m%d%H%M"),
        "source_revision": head,
        "game_version": game_version,
        "constitution_version": "1.4",   # 18图 V1.4 修复版总注明文：写现行宪法版本（ADR-0005）
        "architecture_version": "1.4",   # 现行=01 图 V1.4 修复版（ADR-0006 十七图升版）
        "content_version": content_fingerprint(),
        "schema_version": save_schema,
        "save_schema_version": save_schema,
    }
    out = os.path.join(ROOT, "provenance.json")
    json.dump(prov, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("✓ provenance.json 八字段已生成：%s" % json.dumps(prov, ensure_ascii=False))
    return prov


def run_gates():
    print("── ① 双闸门（verify_all 全量）──")
    r = run([sys.executable, os.path.join(HERE, "verify_all.py")])
    tail = r.stdout.splitlines()[-1] if r.stdout else ""
    print("   " + tail)
    if r.returncode != 0:
        print("✗ 门禁未全绿，中止发布（RH-4 第6项：门禁非绿即阻断）"); sys.exit(1)


def release_gate_perf():
    """Release Gate 第3项：GATE40+ 性能基准（17图 SBP），--release 模式强制。"""
    print("── Release Gate 第3项：GATE40+ 性能基准（17图 SBP）──")
    r = run([sys.executable, os.path.join(HERE, "run_benchmarks.py"), "--release"])
    lines = r.stdout.splitlines()
    for ln in lines[1:]:
        if "PASS" in ln or "✗" in ln or "✓" in ln or "⚠" in ln:
            print("   " + ln.strip())
    if r.returncode != 0:
        print("✗ 性能基准未达 RELEASE PASS，中止发布（SBP-R09：FUNCTIONAL PASS ≠ RELEASE PASS）")
        sys.exit(1)


def release_gate_golden():
    """Release Gate 第4项：迁移 golden 对（13图 SV-3 Phase2）。
    迁移正确性由双闸门 GATE2 单元套件常绿强制（test_save_migration golden 对）；
    此处兜底检查夹具在位，防止夹具被误删后 Release Gate 名存实亡。"""
    print("── Release Gate 第4项：迁移 golden 对（13图 SV-3 Phase2）──")
    golden_dir = os.path.join(ROOT, "tests", "golden", "migrations")
    required = ["migrate_1_0_0_to_1_1_0.input.json", "migrate_1_0_0_to_1_1_0.expected.json",
                # F4 批新增：SV-2 模块级迁移链 golden 对（game_state 1.0.0→1.1.0，region_* 前缀改写）
                "module_game_state_1_0_0_to_1_1_0.input.json",
                "module_game_state_1_0_0_to_1_1_0.expected.json"]
    missing = [f for f in required if not os.path.isfile(os.path.join(golden_dir, f))]
    if missing:
        print("✗ golden 夹具缺失: %s（重跑生产器 tools/golden/gen_migration_golden.tscn 产出）" % missing)
        sys.exit(1)
    print("   ✓ golden 夹具在位（%s），迁移对由 GATE2 常绿强制（SV-R03）" % len(required))


def export_win(prov):
    godot = os.environ.get("GODOT", DEFAULT_GODOT)
    if not os.path.exists(godot):
        print("✗ 找到不到 Godot console：%s（可用环境变量 GODOT 指定）" % godot); sys.exit(2)
    # 导出模板检查（4.x：AppData/Roaming/Godot/export_templates/<ver>）
    ver = run([godot, "--version"]).stdout.strip()
    tpl = os.path.join(os.environ.get("APPDATA", ""), "Godot", "export_templates")
    if not os.path.isdir(tpl) or not os.listdir(tpl):
        print("✗ 未安装 Godot 导出模板：%s" % tpl)
        print("  → 编辑器 → 管理导出模板 → 下载并安装对应版本后重试。")
        print("  （provenance.json 已生成；模板装好后重跑本脚本即可出包）")
        sys.exit(2)
    out_dir = os.path.join(ROOT, "build")
    os.makedirs(out_dir, exist_ok=True)
    raw = os.path.join(out_dir, "wuxiajianghu.exe")
    print("── ③ Godot 导出（Windows Desktop / %s）──" % ver)
    r = run([godot, "--headless", "--path", ROOT, "--export-release", "Windows Desktop", raw])
    if r.returncode != 0 or not os.path.exists(raw):
        print("✗ 导出失败："); print(r.stdout[-1500:]); print(r.stderr[-800:]); sys.exit(2)
    final = os.path.join(out_dir, "wuxiajianghu_%s_%s_win64.exe" % (prov["game_version"], prov["build_id"]))
    os.replace(raw, final)
    prov_copy = os.path.join(out_dir, "provenance.json")
    open(prov_copy, "w", encoding="utf-8").write(json.dumps(prov, ensure_ascii=False, indent=2))
    digest = hashlib.sha256(open(final, "rb").read()).hexdigest()
    print("✓ 产物：%s" % final)
    print("✓ sha256：%s" % digest)
    print("✓ provenance.json 已随包（exe 同级 + pck 内 res:// 双份）")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--skip-gates", action="store_true")
    ap.add_argument("--provenance-only", action="store_true")
    args = ap.parse_args()
    print("══════ build_release · 18图 RH-7 发布流水线 ══════")
    if not args.skip_gates:
        run_gates()
    else:
        print("⚠ --skip-gates：仅供调试，正式发布禁止（RH-4）")
    prov = make_provenance()
    release_gate_golden()
    if args.provenance_only:
        print("（--provenance-only：性能基准 Release Gate 在完整发布流程强制执行）")
        return
    release_gate_perf()
    export_win(prov)
    print("══════ Android：Phase4 实测（RH-4），预设与说明已就位 ══════")


if __name__ == "__main__":
    main()
