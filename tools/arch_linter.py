# tools/arch_linter.py
# GATE21/GATE22/GATE32 架构 Linter（01 图 §91 Enforcement E3 STATIC CHECK / §93 Forbidden API / §127 Gate 基线）
# 依据: docs/architecture/01_总体架构施工图_V1.2.md §91~§96/§127; 宪法 RULE 001/§78/§79
#
# 三项机器可判定检查（其余 GATE23~31 需 Contract Registry / Transaction Runtime 等
# 未建基建，维持 E0/E1 文档级，随对应 Phase 落地再物理化——AI 不自决扩大解释）：
#   GATE21 GDScript Type Policy —— 0-B.12 禁 Dictionary/Array 裸信号载荷；存量 2 条登记 RETIRED，新增即拦
#   GATE22 Forbidden API        —— 按模块限制（§93）：core 业务层禁 IO/JSON/随机/系统时间（授权边界白名单豁免）；
#                                  services/autoload 禁系统时间业务直读与全局随机（基线模式，新增即拦）
#   GATE32 Foundation Freeze    —— EventBus 信号声明集合冻结：增/删/改签名与基线不符即拦
#                                  （与 pre-commit 钩子 0b 互为镜像，防绕过钩子直跑 verify_all 漏检）
#
# 基线: tools/arch_linter_baseline.json（首次 --fix-baseline 生成，人工审核后冻结；
#       修一处删一条，只减不增）。退出码: 0=全绿 1=新增违规。
import json
import os
import re
import sys

ROOT = os.path.normpath(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
BASELINE_PATH = os.path.join(ROOT, "tools", "arch_linter_baseline.json")

# §93 授权边界白名单（IO/JSON/计时基建工具层，非业务逻辑）
CORE_WHITELIST = {
    "core/utils/json_util.gd",       # JSON 统一封装（授权 IO 边界）
    "core/utils/game_logger.gd",     # 日志读取（授权 IO 边界）
    "core/patch_manager.gd",         # 资源补丁加载（授权 IO 基建）
    "core/resource_manager.gd",      # 资源 LRU（Time.get_ticks_msec 引擎计时，非业务时间）
    "core/ui_layout.gd",             # HUD 布局持久化（授权 IO 边界）
    "core/ui_skin.gd",               # 主题皮肤加载（授权 IO 边界）
    "core/ui_vfx.gd",                # 特效配置加载（授权 IO 边界）
}
# core/utils 其余文件按 utils 工具层豁免（seeded_rng 用 RandomNumberGenerator 是其本职）
CORE_UTILS_PREFIX = "core/utils/"

RE_SIGNAL_DICT = re.compile(r"^signal\s+\w+\s*\([^)]*:\s*(Dictionary|Array)\b", re.M)
RE_CORE_FORBIDDEN = re.compile(
    r"\bFileAccess\b|\bDirAccess\b|\bJSON\s*\.|\bTime\.get_|\brandf\(|\brandi\(|\bRandomNumberGenerator\b")
RE_SYS_TIME = re.compile(r"\bTime\.get_unix_time_from_system\b|\bTime\.get_datetime_string_from_system\b")
RE_GLOBAL_RAND = re.compile(r"(?<![.\w])randf\s*\(|(?<![.\w])randi\s*\(|(?<![.\w])randi_range\s*\(|(?<![.\w])randf_range\s*\(")


def _gd_files():
    out = []
    for top in ("core", "autoload", "services", "scenes"):
        d = os.path.join(ROOT, top)
        for dirpath, _dirs, files in os.walk(d):
            for fn in files:
                if fn.endswith(".gd"):
                    out.append(os.path.relpath(os.path.join(dirpath, fn), ROOT).replace("\\", "/"))
    return sorted(out)


def _read(rel):
    with open(os.path.join(ROOT, rel), "r", encoding="utf-8", errors="replace") as f:
        return f.read()


def scan_signals_dict():
    """GATE21: 全域 Dictionary/Array 裸信号载荷 → [{file, line, decl}]（decl=去注释签名，注释改动不触发误报）"""
    hits = []
    for rel in _gd_files():
        for i, ln in enumerate(_read(rel).splitlines(), 1):
            if RE_SIGNAL_DICT.match(ln.strip()):
                sig = re.sub(r"#.*$", "", ln.strip()).rstrip()
                hits.append({"file": rel, "line": i, "decl": sig})
    return hits


def _code_part(ln: str) -> str:
    """剥离行内注释（与 GATE21/GATE32 同口径）：注释里提到禁 API 名不触发误报。
    回归实录 2026-09-06：02 图 Kernel 施工文件（game_clock/random_provider）的
    铁律注释行含 Time.get_*/randf( 等字样被整行匹配误伤。"""
    return re.sub(r"#.*$", "", ln).rstrip()


def scan_forbidden_api():
    """GATE22: 三段——core 业务层禁 API / services+autoload 禁系统时间 / services 禁全局随机
    （匹配与指纹均用去注释代码：真实代码违例照拦，注释提及不禁）"""
    hits = []
    for rel in _gd_files():
        body = _read(rel)
        # core/：白名单与 utils 工具层豁免，其余禁 IO/JSON/随机/时间
        if rel.startswith("core/"):
            if rel in CORE_WHITELIST or rel.startswith(CORE_UTILS_PREFIX):
                continue
            for i, ln in enumerate(body.splitlines(), 1):
                code = _code_part(ln)
                if RE_CORE_FORBIDDEN.search(code):
                    hits.append({"gate": "GATE22-core", "file": rel, "line": i, "code": code[:110]})
        # services/+autoload/：禁系统时间直读（§79）
        if rel.startswith("services/") or rel.startswith("autoload/"):
            for i, ln in enumerate(body.splitlines(), 1):
                code = _code_part(ln)
                if RE_SYS_TIME.search(code):
                    hits.append({"gate": "GATE22-time", "file": rel, "line": i, "code": code[:110]})
            # 时间域禁全局随机（07图 W-R01：weather_time_service 必经 RandomProvider/决定论）
            if rel == "autoload/weather_time_service.gd":
                for i, ln in enumerate(body.splitlines(), 1):
                    code = _code_part(ln)
                    if RE_GLOBAL_RAND.search(code):
                        hits.append({"gate": "GATE22-wrand", "file": rel, "line": i, "code": code[:110]})
        # services/：禁全局随机（§78，SeededRNG 实例方法调用不命中）
        if rel.startswith("services/"):
            for i, ln in enumerate(body.splitlines(), 1):
                code = _code_part(ln)
                if RE_GLOBAL_RAND.search(code):
                    hits.append({"gate": "GATE22-rand", "file": rel, "line": i, "code": code[:110]})
    return hits


def scan_eventbus_freeze():
    """GATE32: EventBus 信号声明指纹 → {signal名: 去注释签名}（注释改动不触发误报，只冻结真签名）"""
    decls = {}
    src = _read("autoload/EventBus.gd")
    for ln in src.splitlines():
        s = ln.strip()
        if s.startswith("signal "):
            sig = re.sub(r"#.*$", "", s).strip()
            name = sig.split("(")[0].split()[1]
            decls[name] = " ".join(sig.split())
    return decls


def _load_baseline():
    if os.path.exists(BASELINE_PATH):
        with open(BASELINE_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    return None


def _save_baseline(data):
    with open(BASELINE_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=1, sort_keys=True)
    print("  [arch_linter] 基线已写入 %s（请人工审核后冻结）" % os.path.relpath(BASELINE_PATH, ROOT))


def _key(hit):
    return "%s|%s|%s" % (hit.get("gate", "GATE21"), hit["file"], hit["line"])


def run(fix_baseline=False):
    """执行三项检查。返回 (ok, report_lines)。fix_baseline=True 时重建基线并判绿。"""
    report = []
    sig_hits = scan_signals_dict()
    api_hits = scan_forbidden_api()
    freeze_now = scan_eventbus_freeze()

    base = _load_baseline()
    if base is None or fix_baseline:
        base = {
            "_notes": {
                "gate21": "存量 Dictionary/Array 裸信号载荷（0-B.12）登记退役——禁新增同族，存量接线随 UI 主权改造收编",
                "gate22-time-合法豁免": "SaveManager 存档 timestamp / ConfigManager 报告生成时间为真实世界元数据，非业务时间语义",
                "gate22-time-待整改": "bond_service t / sworn_service sworn_day / inventory acquired_time 为业务字段读系统时间，应改游戏日（随 bond 域批次整改）",
                "gate22-time-引擎引导": "combat_core seed_val 兜底种子为未指定 seed 时的引擎引导用途",
                "gate22-rand-表现层": "dialogue 镜头抖动为纯表现效果，不参与游戏逻辑确定性",
            },
            "gate21_signals_dict_retired": sig_hits,       # 存量登记（退役禁新增）
            "gate22_forbidden_api": api_hits,              # 存量登记（分类见 _notes）
            "gate32_eventbus_signals": freeze_now,         # 信号声明指纹冻结
        }
        _save_baseline(base)
        report.append("  基线首次生成：%d 条 GATE21 / %d 条 GATE22 / %d 个 GATE32 信号" %
                      (len(sig_hits), len(api_hits), len(freeze_now)))
        return True, report

    ok = True
    # GATE21：基线外新增 Dictionary 信号即拦
    b21 = {"%s|%d|%s" % (h["file"], h["line"], h["decl"]) for h in base.get("gate21_signals_dict_retired", [])}
    new21 = [h for h in sig_hits if "%s|%d|%s" % (h["file"], h["line"], h["decl"]) not in b21]
    # 行号漂移容忍：按 (file, decl) 二次匹配
    if new21:
        b21_fd = {(h["file"], h["decl"]) for h in base.get("gate21_signals_dict_retired", [])}
        new21 = [h for h in new21 if (h["file"], h["decl"]) not in b21_fd]
    if new21:
        ok = False
        report.append("  GATE21 ✗ 新增 Dictionary/Array 裸信号载荷（0-B.12）%d 处:" % len(new21))
        for h in new21[:10]:
            report.append("    %s:%d  %s" % (h["file"], h["line"], h["decl"][:100]))
    else:
        report.append("  GATE21 ✓ 类型政策（存量 %d 条已登记退役/禁新增）" % len(sig_hits))

    # GATE22：基线外新增违例即拦
    b22 = {"%s|%s|%s" % (h["gate"], h["file"], h["code"]) for h in base.get("gate22_forbidden_api", [])}
    new22 = [h for h in api_hits if "%s|%s|%s" % (h["gate"], h["file"], h["code"]) not in b22]
    if new22:
        ok = False
        report.append("  GATE22 ✗ 新增 Forbidden API 违例 %d 处:" % len(new22))
        for h in new22[:10]:
            report.append("    [%s] %s:%d  %s" % (h["gate"], h["file"], h["line"], h["code"]))
    else:
        report.append("  GATE22 ✓ Forbidden API（存量 %d 条已登记基线）" % len(api_hits))

    # GATE32：信号集合增/删/改签名即拦
    b32 = base.get("gate32_eventbus_signals", {})
    added = {k: v for k, v in freeze_now.items() if k not in b32}
    removed = {k: v for k, v in b32.items() if k not in freeze_now}
    changed = {k: (b32[k], freeze_now[k]) for k in freeze_now if k in b32 and b32[k] != freeze_now[k]}
    if added or removed or changed:
        ok = False
        report.append("  GATE32 ✗ EventBus 地基冻结破坏: 新增 %d / 删除 %d / 改签名 %d" % (len(added), len(removed), len(changed)))
        for k, v in list(added.items())[:5]:
            report.append("    + %s  %s" % (k, v))
        for k in list(removed.keys())[:5]:
            report.append("    - %s" % k)
        for k, (ov, nv) in list(changed.items())[:5]:
            report.append("    ~ %s  %s → %s" % (k, ov, nv))
    else:
        report.append("  GATE32 ✓ 地基冻结（EventBus %d 信号与基线一致）" % len(freeze_now))

    return ok, report


if __name__ == "__main__":
    fix = "--fix-baseline" in sys.argv
    ok, lines = run(fix_baseline=fix)
    print("=" * 70)
    print("架构 Linter（GATE21/22/32）| 项目根:", ROOT)
    print("=" * 70)
    for ln in lines:
        print(ln)
    print("=" * 70)
    sys.exit(0 if ok else 1)
