# -*- coding: utf-8 -*-
"""
verify_all.py — 一键验证入口（架构整改 P0-c 落地）
================================================
把「证明没踩坏游戏」的全部门禁串成一条命令，任何窗口/任何人改动代码或数据后必须全绿：

  GATE1  headless --quit 零 SCRIPT/PARSE/COMPILE 错误
  GATE2  tests/unit/run_all.tscn 单元套件（零 ✗ 且 失败 M=0）
  GATE3  validate_project.gd 工程规范（JSON 全可解析 / 禁 .tres / 无硬编码数据路径 / class_name 规范）
  GATE4  战斗预设红线：data/configs/battles/grids/preset_*.json 存在性校验
         （绝不动 preset_* 铁律的机器兜底；历史上若整目录被删，这里会拦）
  GATE5  双写防线：town_npcs.json 已只读留档，tools/、addons/、scenes/、services/ 下的
         .gd/.py 代码不得再出现对它的写入意图（读写留档注释除外）

用法（Windows，任意终端）：
  python tools/verify_all.py            # 跑全部门禁
  python tools/verify_all.py --gate 1   # 只跑某一门（1/2/3/4）

退出码：0 = 全绿；1 = 有门禁未过（提交/合并前必须为 0）。

⚠ 关键经验（2026-09-04 排障实锤）：
  Godot 4.7.2 在「进程拿不到 USERPROFILE/APPDATA」的环境里，user:// 会被解析成
  相对路径 ./Godot/app_userdata/<项目名>，导致所有 user:// 读写（HUD 面板位置存档、
  SaveManager 等）静默失败 → 单测假红（如 test_quest_track_persists_position）。
  本脚本启动 Godot 前会自动补齐这两个环境变量，根治此类环境假红。
"""
import os
import sys
import glob
import json
import subprocess

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
GODOT = os.environ.get("GODOT") or os.path.expanduser(
    "~/.workbuddy/binaries/godot/Godot_v4.7.2-stable_win64_console.exe"
)

# Godot 输出必须接管道消费者（tee/grep），直接重定向文件会丢内容（gate_check.sh 已踩坑）
def _run(args, allowlist=None):
    """跑一个命令，返回 (输出文本, 退出码)。"""
    p = subprocess.run(args, capture_output=True, text=True, errors="replace", cwd=ROOT)
    return (p.stdout + p.stderr), p.returncode


def _godot_env():
    """补齐 Godot 解析 user:// 所需的用户目录环境变量（缺了 user:// 变相对路径假红）。"""
    env = dict(os.environ)
    profile = r"C:\Users\Administrator"
    env.setdefault("USERPROFILE", profile)
    env.setdefault("APPDATA", os.path.join(profile, "AppData", "Roaming"))
    return env


def _godot(args):
    cmd = [GODOT] + args
    p = subprocess.run(
        cmd, capture_output=True, text=True, errors="replace", cwd=ROOT, env=_godot_env()
    )
    return (p.stdout or "") + (p.stderr or ""), p.returncode


def gate1_quit_check():
    """GATE1：--quit 健康检查，零硬错误。"""
    out, _ = _godot(["--headless", "--path", ROOT, "--quit"])
    bad = [ln for ln in out.splitlines()
           if ("SCRIPT ERROR" in ln or "Parse Error" in ln or "Compile Error" in ln
               or "Could not parse" in ln)]
    for ln in bad[:10]:
        print("   " + ln.strip())
    ok = not bad
    print("  GATE1 %s（--quit %s）" % ("✓ 通过" if ok else "✗ 存在硬错误",
                                     "零错误" if ok else "错误 %d 行" % len(bad)))
    return ok


def gate2_unit_tests():
    """GATE2：run_all 单元套件，判绿=✗计数为 0 且 失败 M=0。"""
    out, _ = _godot(["--headless", "--path", ROOT, "res://tests/unit/run_all.tscn"])
    lines = out.splitlines()
    fails = [ln.strip() for ln in lines if "✗" in ln]
    total = None
    for ln in lines:
        if "套件：通过" in ln:
            total = ln.strip()
    for ln in fails[:10]:
        print("   " + ln)
    ok = (not fails) and (total is not None) and ("失败 0" in total)
    print("  GATE2 %s（%s；✗=%d）" % ("✓ 通过" if ok else "✗ 未过",
                                     total or "未见汇总行(框架未跑起来)", len(fails)))
    return ok


def gate3_project_validate():
    """GATE3：工程规范批量校验（JSON 可解析 / 禁 .tres / 硬路径 / class_name）。
    基线模式：tools/verify_baseline.json 里的已知存量违规只警告不拦（修一处删一条），
    新增违规（不在基线内）一律拦截。"""
    out, _ = _godot(["--headless", "--path", ROOT, "--script", "res://tools/validate_project.gd"])
    lines = out.splitlines()
    bad = [ln.strip() for ln in lines if "✗" in ln]
    known = set()
    base_fp = os.path.join(HERE, "verify_baseline.json")
    if os.path.exists(base_fp):
        try:
            with open(base_fp, encoding="utf-8") as f:
                known = set(json.load(f).get("gate3_known", []))
        except Exception as e:
            print("   ⚠ 基线文件读取失败（按无基线处理）: %s" % e)
    fresh, stale = [], []
    for ln in bad:
        core = ln.lstrip("✗* ").strip()  # 校验器行自带 ✗ 前缀，剥掉再匹配基线
        if not core.startswith("res://"):
            continue  # 汇总行（如「发现 N 处违规」）不算违规条目
        if any(core.startswith(k) for k in known):
            stale.append(core)
        else:
            fresh.append(core)
    for ln in fresh[:10]:
        print("   ✗ " + ln)
    for ln in stale[:10]:
        print("   ⚠ 基线存量(不拦): " + ln)
    ok = not fresh
    print("  GATE3 %s（新增违规 %d；基线存量 %d）" % ("✓ 通过" if ok else "✗ 未过", len(fresh), len(stale)))
    return ok


def gate4_preset_redline():
    """GATE4：战斗预设红线兜底——preset_*.json 不得整体消失（误删即拦）。"""
    grids = os.path.join(ROOT, "data", "configs", "battles", "grids")
    presets = sorted(glob.glob(os.path.join(grids, "preset_*.json")))
    problems = []
    if not presets:
        problems.append("data/configs/battles/grids/ 下已无任何 preset_*.json（疑似整目录被误删）")
    for fp in presets:
        try:
            with open(fp, encoding="utf-8") as f:
                d = json.load(f)
            if not isinstance(d, dict) or "width" not in d or "height" not in d:
                problems.append(os.path.basename(fp) + " 缺 width/height 字段")
        except Exception as e:
            problems.append(os.path.basename(fp) + " 解析失败: " + str(e))
    for ln in problems:
        print("   ✗ " + ln)
    ok = not problems
    print("  GATE4 %s（战棋预设 %d 个在位且结构合法）" % ("✓ 通过" if ok else "✗ 未过", len(presets)))
    return ok


def gate5_no_dual_write():
    """GATE5：双写防线——town_npcs.json 只读留档，任何代码不得再写它。
    规则：扫描 tools/ addons/ scenes/ services/ autoload/ 的 .gd/.py；
      .gd：非注释行出现 town_npcs 即违规（ConfigManager 的只读加载在 autoload/ 已豁免）；
      .py：非注释行同时含 town_npcs 与写意图(write/open) 即违规。"""
    import re
    scan_dirs = ["addons", "scenes", "services", "tools", "autoload"]
    # 豁免：① 本脚本自身（规则文本里含关键词）② ConfigManager 只读加载入口（P1 统一后一并下线）
    # 行级豁免：代码行尾加注释标记  # verify-allow: town_npcs  （须附理由，见 studio_core 自检夹具）
    exempt_files = {"tools/verify_all.py", "autoload/ConfigManager.gd"}
    problems = []
    for sub in scan_dirs:
        base = os.path.join(ROOT, sub)
        for cur, _dirs, files in os.walk(base):
            if ".godot" in cur or "__pycache__" in cur:
                continue
            for fn in files:
                if not fn.endswith((".gd", ".py")):
                    continue
                rel = os.path.relpath(os.path.join(cur, fn), ROOT).replace("\\", "/")
                if rel in exempt_files:
                    continue
                try:
                    with open(os.path.join(cur, fn), encoding="utf-8", errors="replace") as f:
                        for i, ln in enumerate(f, 1):
                            s = ln.strip()
                            if s.startswith("#") or "town_npcs" not in s:
                                continue
                            if "verify-allow: town_npcs" in s:
                                continue  # 显式豁免标记（须附理由）
                            if fn.endswith(".gd"):
                                problems.append("%s:%d .gd 引用 town_npcs（应走区域表）" % (rel, i))
                            elif re.search(r"write|open\s*\(", s, re.I):
                                problems.append("%s:%d .py 疑似写 town_npcs" % (rel, i))
                except OSError as e:
                    problems.append("%s 读取失败: %s" % (rel, e))
    for ln in problems[:10]:
        print("   ✗ " + ln)
    ok = not problems
    print("  GATE5 %s（town_npcs.json 双写防线：违规 %d 处）" % ("✓ 通过" if ok else "✗ 未过", len(problems)))
    return ok


GATES = {1: gate1_quit_check, 2: gate2_unit_tests, 3: gate3_project_validate,
         4: gate4_preset_redline, 5: gate5_no_dual_write}


def main():
    if not os.path.exists(GODOT):
        print("找不到 Godot console：%s（可用环境变量 GODOT 指定路径）" % GODOT)
        return 1
    pick = [int(a) for a in sys.argv[sys.argv.index("--gate") + 1:]] if "--gate" in sys.argv else sorted(GATES)
    print("══════ verify_all · 项目一键验证 ══════")
    print("  工程: %s\n  Godot: %s" % (ROOT, GODOT))
    all_ok = True
    for g in pick:
        fn = GATES.get(g)
        if fn is None:
            print("未知门禁编号: %s（可用 1-4）" % g)
            return 1
        print("── GATE%d ──" % g)
        try:
            if not fn():
                all_ok = False
        except Exception as e:
            print("  GATE%d ✗ 异常: %s" % (g, e))
            all_ok = False
    print("══════ 结论：%s ══════" % ("全绿 ✓ 可以提交/合并" if all_ok else "有门禁未过 ✗ 禁止提交"))
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
