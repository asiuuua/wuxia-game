# -*- coding: utf-8 -*-
"""arch_validators.py — 04 图 GATE41 架构校验器组（01 §92 七校验器补位，2026-09-06 落地）

01 §92 七校验器物理化进度（本文件落地后 6/7，changed_file_scope 属多 AI 阶段暂缓）：
  ① forbidden_api_validator  = arch_linter GATE22（fc2debd 已建）✓
  ② freeze_manifest_validator = arch_linter GATE32（fc2debd 已建）✓
  ③ naming(ID 正则)          = id_validator GATE06（已有）✓
  ④ dependency_validator     = 本文件 GATE41 ✓（层方向单向 + 环检测 + 生产禁引 tests）
  ⑤ module_scope_validator   = 本文件 GATE41 ✓（Test Double 只准住 tests/doubles/）
  ⑥ naming_validator(test_*) = 本文件 GATE41 ✓（T-R02：tests/unit 套件必须 test_ 前缀）
  ⑦ changed_file_scope       = GATE23（多 AI 阶段，依赖 Write Lease 元数据，暂缓——不越界）
  state_owner_validator（GATE25）= 本文件双模式（B1 收口 2026-09-06）：
      ① scan_owner_writer_baseline —— 写入口基线禁新增（tools/arch_linter_baseline.json gate25_owner_writers）
      ② report_state_owners —— 写入口密度 REPORT 观察保留（T-4 多写者阈值继续观察）
  cross_module_write_validator（RULE 004/007，B2 上线 2026-09-06）= scan_cross_module_writes：
      对 Owner 对象的跨模块属性直写扫描——Owner 自文件写豁免，跨模块直写基线禁新增
      （tools/arch_linter_baseline.json gate41_cross_module_writes）
  14 图批1 三锚（2026-09-06）：
      scan_ui_flow_whitelist   —— PV-R03 UI/场景层 GameManager 流程直连白名单禁新增
                                  （gate41_ui_flow_whitelist，Phase3 Command 化只减不增）
      scan_services_no_stage   —— QD-R10（12图）机器化/PV-3 消费面核查：services 禁 Node 演出（零容忍）
      scan_view_model_hygiene  —— PV-1 三禁（14图§5.3）：extends ViewModelBase 文件
                                  禁直写/禁 Node 引用/禁写入口前缀

层方向铁律（宪法 §85 / 工作记忆）：autoload → core → data → services → scenes → tests，单向。
用法: python tools/arch_validators.py   （退出码 0=通过 1=违规）
"""
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
BASELINE_PATH = os.path.join(HERE, "arch_linter_baseline.json")


def _load_baseline():
    try:
        with open(BASELINE_PATH, encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return {}


def _save_baseline(data):
    with open(BASELINE_PATH, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=True)

violations = []
notes = []

# 依赖禁引矩阵（宪法 §85 单向依赖的落地口径：地基纯净、表现最高）：
#   core      地基：只准依赖 core（禁 data/autoload/services/scenes/tests）
#   data      数据：只准 core/data（禁 autoload/services/scenes/tests）
#   services  业务：core/data/services（禁 scenes/tests）
#   autoload  装配：全部生产层（禁 tests）
#   scenes    表现：全部生产层（禁 tests）
#   tests     天花板：自由
DENY = {
    "core": {"data", "autoload", "services", "scenes", "tests"},
    "data": {"autoload", "services", "scenes", "tests"},
    "services": {"scenes", "tests"},
    "autoload": {"tests"},
    "scenes": {"tests"},
    "tests": set(),
}

RE_REF = re.compile(
    r"""(?:preload|load)\s*\(\s*["']res://([^"']+)["']""")   # preload/load res:// 路径


def layer_of(rel):
    top = rel.split("/", 1)[0]
    return top if top in DENY else None


def scan_dependency():
    """④ dependency_validator：preload/load 图层方向 + 环检测 + 生产禁引 tests。"""
    edges = {}   # file -> [被引文件,...]
    for dirpath, _dirs, files in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace(os.sep, "/")
        if rel_dir.split("/")[0] in (".git", ".godot", ".workbuddy", "docs", "tools", "assets",
                                     "resources", "Godot", "_ai_export") or rel_dir == ".":
            continue
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            full = os.path.join(dirpath, fn)
            rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
            src_layer = layer_of(rel)
            if src_layer is None:
                continue
            try:
                text = open(full, encoding="utf-8", errors="replace").read()
            except OSError:
                continue
            # 去注释（与 GATE22/32 同口径）：注释里的 res:// 路径不算引用
            code_text = re.sub(r"#[^\n]*", "", text)
            edges[rel] = []
            for m in RE_REF.finditer(code_text):
                target = m.group(1).split("::")[0].strip()
                if not target.endswith(".gd"):
                    continue
                tgt_norm = target if target.startswith("/") else target
                tgt_rel = tgt_norm.lstrip("/")
                tgt_layer = layer_of(tgt_rel)
                edges[rel].append(tgt_rel)
                if tgt_layer is None:
                    continue
                # 生产层禁引 tests（T-R05：生产代码禁引用 tests/）
                if tgt_layer == "tests" and src_layer != "tests":
                    violations.append(("T-R05", rel, "生产层 %s 引用 tests/: %s（禁）" % (src_layer, tgt_rel)))
                    continue
                # 禁引矩阵：地基纯净（core 禁引上层）、表现自由（scenes 引业务合法）
                if tgt_layer in DENY.get(src_layer, set()):
                    violations.append(
                        ("DEP", rel, "依赖禁引违例: %s → %s（%s 层禁引矩阵）"
                         % (src_layer, tgt_layer, src_layer)))
    # 环检测（DFS 三色；自环跳过——GDScript 不可能 preload 自己，自匹配=字符串/常量表误伤；
    # 环签名去重防同一环重复报告）
    color = {k: 0 for k in edges}
    seen_cycles = set()

    def dfs(u, path):
        color[u] = 1
        for v in edges.get(u, []):
            if v not in edges or v == u:
                continue
            if color.get(v) == 1:
                cyc = frozenset(path[path.index(v):] + [u]) if v in path else frozenset(path + [u])
                if cyc not in seen_cycles:
                    seen_cycles.add(cyc)
                    violations.append(("DEP-CYCLE", u, "依赖环: %s → %s" % (" → ".join(path[path.index(v):] + [u]) if v in path else " → ".join(path + [u]), v)))
            elif color.get(v) == 0:
                dfs(v, path + [u])
        color[u] = 0   # 白回溯（路径敏感环检测）

    for k in list(edges):
        dfs(k, [])


def scan_module_scope():
    """⑤ module_scope_validator：Test Double（fake_/stub_ 前缀）只准住 tests/doubles/。"""
    for dirpath, _dirs, files in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace(os.sep, "/")
        if rel_dir.split("/")[0] in (".git", ".godot", ".workbuddy", "docs", "tools", "Godot",
                                     "_ai_export") or rel_dir == ".":
            continue
        for fn in files:
            if not fn.endswith(".gd"):
                continue
            if re.match(r"^(fake_|stub_|mock_)", fn) and not rel_dir.startswith("tests/doubles"):
                rel = os.path.join(rel_dir, fn).replace(os.sep, "/")
                violations.append(("T-R04", rel, "Test Double 只准住 tests/doubles/（04图 T-R04）"))


def scan_test_naming():
    """⑥ T-R02：tests/unit 套件必须 test_ 前缀（U-4 命名法）；运行器/基座下划线系豁免。"""
    unit = os.path.join(ROOT, "tests", "unit")
    exempt = {"run_all.gd"}   # 测试运行器（run_all.tscn 驱动脚本），非套件
    for fn in sorted(os.listdir(unit)):
        if fn.endswith(".gd") and not fn.startswith("_") and fn not in exempt:
            if not fn.startswith("test_"):
                rel = "tests/unit/" + fn
                violations.append(("T-R02", rel, "测试套件文件名必须 test_ 前缀（U-4/T-R02）"))


def scan_test_shape():
    """⑧ T-R01：tests/**/test_*.gd 必须继承 TestBase（禁自造 runner）。
    扫描面=tests/ 递归下全部 test_*.gd（T-R02 命名法保证套件前缀唯一，此处只查基座）；
    生成器（gen_*.gd）/运行器（run_all.gd，非 test_ 前缀）/下划线辅助天然不在扫描面。"""
    tests_dir = os.path.join(ROOT, "tests")
    for dirpath, _dirs, files in os.walk(tests_dir):
        rel_dir = os.path.relpath(dirpath, ROOT).replace(os.sep, "/")
        for fn in files:
            if not (fn.startswith("test_") and fn.endswith(".gd")):
                continue
            fp = os.path.join(dirpath, fn)
            rel = os.path.join(rel_dir, fn).replace(os.sep, "/")
            try:
                text = open(fp, encoding="utf-8").read()
            except Exception:
                continue
            if not re.search(r"^extends\s+TestBase\b", text, re.M):
                violations.append(("T-R01", rel, "单测必须继承 TestBase（04图 T-R01，禁自造 runner）"))


# --- Owner 写入口合法文件映射（Owner 自文件写豁免；跨模块直写进基线禁新增） ---
OWNER_LEGAL_PREFIX = {
    "player_state": ["data/runtime/player_state.gd", "autoload/GameManager.gd", "tests/"],
    "game_state": ["autoload/game_state.gd", "tests/"],
    "GameState": ["autoload/game_state.gd", "tests/"],
    "inventory_service": ["services/inventory/", "autoload/GameManager.gd", "tests/"],
    "quest_service": ["services/quest/", "autoload/GameManager.gd", "tests/"],
    "ability_service": ["services/ability/", "autoload/GameManager.gd", "tests/"],
    "equipment_service": ["services/equipment/", "autoload/GameManager.gd", "tests/"],
    "alchemy_service": ["services/alchemy/", "autoload/GameManager.gd", "tests/"],
    "forge_service": ["services/forge/", "autoload/GameManager.gd", "tests/"],
    "shop_service": ["services/shop/", "autoload/GameManager.gd", "tests/"],
    "sect_service": ["services/sect/", "autoload/GameManager.gd", "tests/"],
    "combat_service": ["services/combat/", "autoload/GameManager.gd", "tests/"],
    "bond_service": ["services/bond/", "autoload/GameManager.gd", "tests/"],
    "romance_service": ["services/bond/", "autoload/GameManager.gd", "tests/"],
    "sworn_service": ["services/bond/", "autoload/GameManager.gd", "tests/"],
    "master_service": ["services/bond/", "autoload/GameManager.gd", "tests/"],
    "dialogue_service": ["services/dialogue/", "autoload/GameManager.gd", "tests/"],
    "effect_registry": ["core/effect_registry.gd", "autoload/GameManager.gd", "services/", "tests/"],
    "weather_time_service": ["autoload/weather_time_service.gd", "tests/"],
    "WeatherTimeService": ["autoload/weather_time_service.gd", "tests/"],
    "settings_manager": ["autoload/settings_manager.gd", "tests/"],
    "SettingsManager": ["autoload/settings_manager.gd", "tests/"],
    "save_manager": ["autoload/SaveManager.gd", "tests/"],
    "SaveManager": ["autoload/SaveManager.gd", "tests/"],
}

RE_CROSS_WRITE = re.compile(
    r"\b(%s)\.(\w+)\s*(?:[+\-*/]?=(?!=)|\+\+|--)" % "|".join(sorted(OWNER_LEGAL_PREFIX, key=len, reverse=True)))

SCAN_SKIP_TOPS = (".git", ".godot", ".workbuddy", "docs", "tools", "assets",
                  "resources", "Godot", "_ai_export", "tests")


def _gd_files_scan():
    for dirpath, _dirs, files in os.walk(ROOT):
        rel_dir = os.path.relpath(dirpath, ROOT).replace(os.sep, "/")
        if rel_dir.split("/")[0] in SCAN_SKIP_TOPS or rel_dir == ".":
            continue
        for fn in files:
            if fn.endswith(".gd"):
                full = os.path.join(dirpath, fn)
                rel = os.path.relpath(full, ROOT).replace(os.sep, "/")
                yield rel, full


def _owner_file_legal(owner: str, rel: str) -> bool:
    for prefix in OWNER_LEGAL_PREFIX.get(owner, []):
        if rel.startswith(prefix):
            return True
    return False


def scan_cross_module_writes():
    """RULE 004/RULE 007（B2 上线）：对 Owner 对象的属性直写扫描。
    Owner 自文件写豁免；跨模块直写=基线禁新增（arch_linter_baseline.json gate41_cross_module_writes）。
    已知静态盲区（局部变量中转持有后直写）不覆盖，登记于 PROJECT_STATUS。"""
    baseline = _load_baseline()
    known = set(baseline.get("gate41_cross_module_writes", []))
    hits = []
    for rel, full in _gd_files_scan():
        code = re.sub(r"#[^\n]*", "", open(full, encoding="utf-8", errors="replace").read())
        for i, ln in enumerate(code.split("\n"), 1):
            for m in RE_CROSS_WRITE.finditer(ln):
                owner, field = m.group(1), m.group(2)
                if _owner_file_legal(owner, rel):
                    continue
                sig = "%s | %s.%s" % (rel, owner, field)
                hits.append((sig, "%s:%d  %s" % (rel, i, ln.strip()[:90])))
    new_hits = [h for h in hits if h[0] not in known]
    if new_hits:
        for sig, ctx in new_hits[:10]:
            violations.append(("R004/007", sig.split(" | ")[0],
                               "跨模块属性直写（未入基线）: %s —— %s" % (sig, ctx)))
    notes.append("cross_module_writes: 存量基线 %d 条 / 本次命中 %d 处 / 新增 %d（基线禁新增）"
                 % (len(known), len(hits), len(new_hits)))


def _collect_owner_writers():
    current = {}
    for top in ("services", "autoload"):
        d = os.path.join(ROOT, top)
        for dirpath, _dirs, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".gd"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace(os.sep, "/")
                for ln in open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace"):
                    m = re.match(r"^func\s+((?:set|add|remove|clear|update)_\w+)\s*\(", ln.strip())
                    if m:
                        current.setdefault(rel, []).append(m.group(1))
    return current


def scan_owner_writer_baseline():
    """RULE 007（B1 收口）：services/autoload 写入口（set_/add_/remove_/clear_/update_ 前缀方法）
    按文件基线化——新增写入口（新方法）即红；T-4 多写者阈值另行观察（REPORT 保留）。"""
    baseline = _load_baseline()
    known = baseline.get("gate25_owner_writers", {})
    current = _collect_owner_writers()
    new_writers = []
    for rel, methods in sorted(current.items()):
        for meth in methods:
            if meth not in known.get(rel, []):
                new_writers.append("%s | %s" % (rel, meth))
    if new_writers:
        for w in new_writers[:10]:
            violations.append(("R007", w.split(" | ")[0], "Owner 写入口新增（未入基线）: %s" % w))
    total = sum(len(v) for v in current.values())
    notes.append("state_owner baseline: %d 文件 / %d 写入口 / 新增 %d（基线禁新增）"
                 % (len(current), total, len(new_writers)))


def scan_studio_write_paths():
    """ST-R01（15 图批2 上线）：Studio 编辑器域 py 代码绕过 DataSink 直写 data/configs 扫描。
    范围 = tools/{desktop_studio,config_editor,item_editor}/**.py；写基元（open w/json.dump/
    write_text/shutil.copy 等）±3 行窗口出现 configs 路径即命中；`verify-allow:` 行内标记豁免
    （自检夹具造临时工程）。基线禁新增（arch_linter_baseline.json gate_st_r01_studio_writes）。"""
    baseline = _load_baseline()
    known = set(baseline.get("gate_st_r01_studio_writes", []))
    hits = []
    write_re = re.compile(r"json\.dump\(|\.write_text\(|\.write_bytes\(|\.write\(|\.writelines\(|"
                          r"open\([^)]*[\"']w[a-z+]*[\"']|shutil\.copy(?:2|tree)?\(|os\.replace\(")
    scopes = ["desktop_studio", "config_editor", "item_editor"]
    for top in scopes:
        d = os.path.join(ROOT, "tools", top)
        if not os.path.isdir(d):
            continue
        for dirpath, dirs, files in os.walk(d):
            dirs[:] = [x for x in dirs if x not in ("__pycache__", "build", "projects", "safety_data")]
            for fn in files:
                if not fn.endswith(".py"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace(os.sep, "/")
                lines = open(os.path.join(dirpath, fn), encoding="utf-8",
                             errors="replace").read().split("\n")
                for i, ln in enumerate(lines):
                    if "verify-allow:" in ln:
                        continue
                    if not write_re.search(ln):
                        continue
                    window = "\n".join(lines[max(0, i - 3):i + 4])
                    if "configs" not in window:
                        continue
                    sig = "%s | %s" % (rel, ln.strip()[:120])
                    hits.append((sig, "%s:%d  %s" % (rel, i + 1, ln.strip()[:90])))
    new_hits = [h for h in hits if h[0] not in known]
    if new_hits:
        for sig, ctx in new_hits[:10]:
            violations.append(("ST-R01", sig.split(" | ")[0],
                               "Studio 写路径绕过 DataSink 直写 configs（未入基线）: %s —— %s" % (sig, ctx)))
    notes.append("st_r01 studio_writes: 存量基线 %d 条 / 本次命中 %d 处 / 新增 %d（基线禁新增）"
                 % (len(known), len(hits), len(new_hits)))


# --- 14 图批1（PV 域 Enforcement，2026-09-06）：RE 集与三扫描器 ---
RE_UI_FLOW = re.compile(
    r"\bGameManager\.(goto_region|load_game|start_new_game|return_to_title|"
    r"start_battle|return_to_town|start_test_\w+)\s*\(")
RE_STAGE_API = re.compile(
    r"create_tween\(|\bTween\b|get_camera|AudioStreamPlayer|ResourceLoader|CanvasItem|"
    r"preload\([^)]*\.(?:tscn|png|ogg|wav)")
RE_VM_EXTENDS = re.compile(r"^extends\s+ViewModelBase\s*$", re.M)
RE_NODE_REF = re.compile(
    r":\s*(?:Node|Node2D|Node3D|Control|CanvasItem|CanvasLayer|Viewport)\b|"
    r"add_child\(|Node\.new\(|preload\([^)]*\.tscn")
RE_VM_WRITER = re.compile(r"^func\s+(?:set|add|remove|clear|update)_\w+\s*\(", re.M)


def scan_ui_flow_whitelist():
    """PV-R03（14 图批1 物理化）：UI/场景层 GameManager 流程直连白名单——基线禁新增，
    Phase3 Application Command 化后逐条销减（14 图 §4 行9「只减不增」）。
    范围 = scenes/**/*.gd + autoload/ui_manager.gd；粒度 =「文件 | 方法」。
    基线 = tools/arch_linter_baseline.json gate41_ui_flow_whitelist。"""
    baseline = _load_baseline()
    known = set(baseline.get("gate41_ui_flow_whitelist", []))
    hits = set()
    for rel, full in _gd_files_scan():
        if not (rel.startswith("scenes/") or rel == "autoload/ui_manager.gd"):
            continue
        code = re.sub(r"#[^\n]*", "", open(full, encoding="utf-8", errors="replace").read())
        for m in RE_UI_FLOW.finditer(code):
            hits.add("%s | %s" % (rel, m.group(1)))
    new_hits = [h for h in sorted(hits) if h not in known]
    if new_hits:
        for h in new_hits[:10]:
            violations.append(("PV-R03", h.split(" | ")[0],
                               "UI/场景层 GameManager 流程直连新增（未入白名单）: %s" % h))
    notes.append("ui_flow_whitelist: 白名单 %d 条 / 本次命中 %d 处 / 新增 %d（PV-R03 只减不增）"
                 % (len(known), len(hits), len(new_hits)))


def scan_services_no_stage():
    """QD-R10（12 图）机器化——PV-3 消费面核查锚（14 图批1）：services 层禁 Node 演出
    （Tween/相机/AudioStreamPlayer/ResourceLoader/舞台资源直载）。演出只产指令
    （EventBus.screen_shake_requested 单通道）交表现层执行；sfx 走 AudioManager
    （autoload 表现 API）豁免。零基线 ACTIVE（2026-09-06 实测零命中），命中即红。"""
    hits = []
    for rel, full in _gd_files_scan():
        if not rel.startswith("services/"):
            continue
        code = re.sub(r"#[^\n]*", "", open(full, encoding="utf-8", errors="replace").read())
        for i, ln in enumerate(code.split("\n"), 1):
            if RE_STAGE_API.search(ln):
                hits.append("%s:%d  %s" % (rel, i, ln.strip()[:90]))
    if hits:
        for h in hits[:10]:
            violations.append(("QD-R10", h.split(":")[0],
                               "services 层 Node 演出 API 直查（演出须产指令交表现层）: %s" % h))
    notes.append("services_no_stage: services 演出 API 直查 %d 处（QD-R10 零容忍）" % len(hits))


def scan_view_model_hygiene():
    """PV-1 三禁（14 图 §5.3 Freeze）机器锚（14 图批1）：extends ViewModelBase 文件扫描——
    ①禁跨模块属性直写（复用 RE_CROSS_WRITE）②禁 Node 引用/add_child/preload(.tscn)
    ③禁写入口前缀公共方法（ViewModel 输出端只被 UI 读）。
    骨架期 VM 文件 0 个（基类 scenes/ui/view_model_base.gd 不 extends 自身），扫描即 ACTIVE。"""
    vm_files = []
    for rel, full in _gd_files_scan():
        code = re.sub(r"#[^\n]*", "", open(full, encoding="utf-8", errors="replace").read())
        if not RE_VM_EXTENDS.search(code):
            continue
        vm_files.append(rel)
        for i, ln in enumerate(code.split("\n"), 1):
            if RE_CROSS_WRITE.search(ln):
                violations.append(("PV-1", rel, "ViewModel 禁写业务状态（跨模块直写）: %s:%d  %s"
                                   % (rel, i, ln.strip()[:90])))
            if RE_NODE_REF.search(ln):
                violations.append(("PV-1", rel, "ViewModel 禁持 Node 引用: %s:%d  %s"
                                   % (rel, i, ln.strip()[:90])))
            if RE_VM_WRITER.search(ln):
                violations.append(("PV-1", rel, "ViewModel 禁写入口前缀方法（输出端只被 UI 读）: %s:%d"
                                   % (rel, i)))
    notes.append("view_model_hygiene: VM 文件 %d 个（PV-1 三禁扫描 ACTIVE）" % len(vm_files))


def fix_baselines():
    """--fix：把当前快照写回基线（仅供首次生成/收编时人工确认后使用）。"""
    baseline = _load_baseline()
    current = _collect_owner_writers()
    baseline["gate25_owner_writers"] = dict(sorted(current.items()))
    writes = []
    for rel, full in _gd_files_scan():
        code = re.sub(r"#[^\n]*", "", open(full, encoding="utf-8", errors="replace").read())
        for m in RE_CROSS_WRITE.finditer(code):
            owner, field = m.group(1), m.group(2)
            if _owner_file_legal(owner, rel):
                continue
            writes.append("%s | %s.%s" % (rel, owner, field))
    baseline["gate41_cross_module_writes"] = sorted(set(writes))
    st_hits = []
    write_re = re.compile(r"json\.dump\(|\.write_text\(|\.write_bytes\(|\.write\(|\.writelines\(|"
                          r"open\([^)]*[\"']w[a-z+]*[\"']|shutil\.copy(?:2|tree)?\(|os\.replace\(")
    for top in ("desktop_studio", "config_editor", "item_editor"):
        d = os.path.join(ROOT, "tools", top)
        if not os.path.isdir(d):
            continue
        for dirpath, dirs, files in os.walk(d):
            dirs[:] = [x for x in dirs if x not in ("__pycache__", "build", "projects", "safety_data")]
            for fn in files:
                if not fn.endswith(".py"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace(os.sep, "/")
                lines = open(os.path.join(dirpath, fn), encoding="utf-8",
                             errors="replace").read().split("\n")
                for i, ln in enumerate(lines):
                    if "verify-allow:" in ln or not write_re.search(ln):
                        continue
                    if "configs" in "\n".join(lines[max(0, i - 3):i + 4]):
                        st_hits.append("%s | %s" % (rel, ln.strip()[:120]))
    baseline["gate_st_r01_studio_writes"] = sorted(set(st_hits))
    flow = set()
    for rel, full in _gd_files_scan():
        if not (rel.startswith("scenes/") or rel == "autoload/ui_manager.gd"):
            continue
        code = re.sub(r"#[^\n]*", "", open(full, encoding="utf-8", errors="replace").read())
        for m in RE_UI_FLOW.finditer(code):
            flow.add("%s | %s" % (rel, m.group(1)))
    baseline["gate41_ui_flow_whitelist"] = sorted(flow)
    _save_baseline(baseline)
    print("--fix 已写基线: gate25_owner_writers(%d 文件) / gate41_cross_module_writes(%d 条) / "
          "gate_st_r01_studio_writes(%d 条) / gate41_ui_flow_whitelist(%d 条)"
          % (len(baseline["gate25_owner_writers"]), len(baseline["gate41_cross_module_writes"]),
             len(baseline["gate_st_r01_studio_writes"]), len(baseline["gate41_ui_flow_whitelist"])))


def report_state_owners():
    """state_owner_validator REPORT 模式（T-4 追认：观察期，不拦）：
    扫 services/autoload 公开 set_ 方法计数，>8 者通报观察。"""
    counts = {}
    for top in ("services", "autoload"):
        d = os.path.join(ROOT, top)
        for dirpath, _dirs, files in os.walk(d):
            for fn in files:
                if not fn.endswith(".gd"):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace(os.sep, "/")
                n = 0
                for ln in open(os.path.join(dirpath, fn), encoding="utf-8", errors="replace"):
                    if re.match(r"^func\s+set_\w+\s*\(", ln.strip()) or re.match(r"^func\s+\w+", ln.strip()) and re.match(r"func\s+(set|add|remove|clear|update)_", ln):
                        n += 1
                if n:
                    counts[rel] = n
    hot = sorted(counts.items(), key=lambda x: -x[1])[:3]
    for rel, n in hot:
        notes.append("state_owner REPORT: %s 写入口 %d 个（观察期 T-4，不拦）" % (rel, n))


def main():
    if "--fix" in sys.argv:
        fix_baselines()
        sys.exit(0)
    scan_dependency()
    scan_module_scope()
    scan_test_naming()
    scan_test_shape()
    scan_cross_module_writes()
    scan_owner_writer_baseline()
    scan_studio_write_paths()
    scan_ui_flow_whitelist()
    scan_services_no_stage()
    scan_view_model_hygiene()
    report_state_owners()

    print("arch_validators · 04图 GATE41（dependency/module_scope/test_naming/test_shape + cross_write R004/007 + state_owner 基线+REPORT + ST-R01 studio_writes + PV-R03 ui_flow + QD-R10 services_no_stage + PV-1 vm_hygiene）")
    for n in notes:
        print("  ℹ " + n)
    if violations:
        for rule, f, ev in violations[:12]:
            print("  ✗ [%s] %s — %s" % (rule, f, ev))
        print("════ 结论：✗ %d 项违规 ════" % len(violations))
        sys.exit(1)
    print("════ 结论：✓ 通过（层方向单向 / 生产零引 tests / Double 隔离 / 套件命名与基座合规）════")
    sys.exit(0)


if __name__ == "__main__":
    main()
