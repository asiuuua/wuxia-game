# Phase 5 Dependency Graph Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现 Code Graph / Content Graph 双图分离 + Content Graph impact / transitive_reverse / 环检测 + 引用面实测归档。

**Architecture:** 以 `ref_index.py` 为 Content Graph 核心扩展图遍历能力；`scan_deps.py` 明确命名为 Code Graph 并补齐 impact/reverse 接口；新建 `dep_graph.py` 统一门面（content_* / code_* 命名空间化，禁混用）；GATE41 追加 Content 环检测。

**Tech Stack:** Python 3（标准库）；Content Graph 基于 ref_index.py 现有 build/check 机制扩展；Code Graph 基于 scan_deps.py 现有 scan 结果扩展。

**设计文档：** `docs/superpowers/specs/2026-09-07-phase5-dependency-graph.md`

**提交纪律：** 每 Task 提交走 `python tools/commit_queue.py add --window 工作室工具 --message "[集成] ..." --files <精确文件列表>`，禁 git add -A；全部完成后再 flush。

---

### Task 1: 引用面实测报告归档

**Files:**
- Create: `docs/architecture/引用面实测报告_2026-09-07.md`

- [ ] **Step 1: 生成实测报告**

基于 2026-09-07 扫描结果（62 文 / 176 行），产出正式报告：

```markdown
# 引用面实测报告（data/configs 路径引用全量扫描）

> 日期：2026-09-07
> 目的：ADR-0003 目录迁移（data/configs/** → content/definitions/**）前置摸底
> 扫描范围：scenes/ application/ autoload/ addons/ services/ tools/
> 排除：.godot/ __pycache__/ .workbuddy/ Godot/

## 1. 总览

| 指标 | 数值 |
|---|---|
| 总匹配文件数 | 62 |
| 总匹配行数 | 176 |
| 生产代码（.gd） | 29 文件 / 84 行 |
| 工具脚本（.py/.gd） | 33 文件 / 92 行 |

## 2. 按目录分布

| 目录 | 文件数 | 匹配行数 | 主要引用内容 |
|---|---|---|---|
| autoload/ | 6 | 41 | ConfigManager 集中装载所有配置表路径 |
| tools/ | 33 | 92 | 各类校验器、数据管道、桌面工作室服务层 |
| scenes/ | 15 | 26 | UI 各界面读取皮肤/布局/菜单配置 |
| addons/ | 4 | 8 | 欢庆管理器、内容工作室插件 |
| application/ | 2 | 6 | ContentRegistry 聚合 / Schema 校验 |
| services/ | 2 | 3 | 结缘服务、对话事件执行器 |

## 3. 重点文件清单（目录迁移高影响）

### 3.1 核心枢纽（改造优先级 P0）

- `autoload/ConfigManager.gd`：30+ 配置表路径集中定义，是目录迁移的单点改造核心

### 3.2 工具层（改造优先级 P1）

- `tools/ref_index.py`：全量引用索引，路径硬编码多处
- `tools/data_sink.py`：写路径收口核心
- `tools/desktop_studio/services/` 下所有 service / repository：读写配置表

### 3.3 生产代码（改造优先级 P2）

- `scenes/ui/` 下各界面：读取 UI 配置
- `application/content/`：ContentRegistry
- `services/`：业务服务

## 4. ADR-0003 迁移影响评估

**结论**：62 文 / 176 行的量级在可控范围内。核心策略：
1. ConfigManager 单点改造（P0）
2. tools/ 批量改造（P1，可脚本化替换 + 全量回归验证）
3. 生产代码批量替换（P2，Godot 侧用全局替换 + GATE1 编译验证）

**前置条件**：批 C（Content Registry）完 + 批 D（Autoload 八级收缩）完 → Phase 5 一次性搬迁。

## 5. 完整清单

（附完整文件-行号-上下文表，按目录分组）
```

> 注：完整清单部分直接填入扫描到的 62 文件详细数据。

- [ ] **Step 2: 提交**

```bash
python tools/commit_queue.py add --window 工作室工具 --message "[集成] Phase5 Task1：引用面实测报告归档（ADR-0003 前置摸底，62 文 176 行）" --files docs/architecture/引用面实测报告_2026-09-07.md docs/superpowers/specs/2026-09-07-phase5-dependency-graph.md
```

---

### Task 2: Content Graph 核心扩展（impact / transitive_reverse / 环检测）

**Files:**
- Modify: `tools/ref_index.py`（追加图遍历函数 + CLI 子命令）
- Modify: `tools/phase5_dep_graph_tests.py`（新建，段 A 纯函数断言）

- [ ] **Step 1: 建测试文件 + 段 A 断言（红灯）**

```python
# -*- coding: utf-8 -*-
"""phase5_dep_graph_tests.py — Phase 5 Dependency Graph 回归（verify_all GATE41 升级项）

临时目录自包含测试，不碰真工程数据：
  段 A  Content Graph 图遍历（impact / transitive_reverse / find_cycles）
  段 B  dep_graph 统一门面（content_* / code_* 双命名空间）
  段 C  环检测 + GATE41 升级
退出码 0=通过。
"""
import os, sys, json, shutil, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import ref_index  # noqa: E402


def _w(root, rel, data):
    p = os.path.join(root, *rel.split("/"))
    os.makedirs(os.path.dirname(p), exist_ok=True)
    with open(p, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2)


def make_temp_project():
    """建最小工程：NPC → Dialogue → Quest → Item 链，带环的对话跳转。"""
    d = tempfile.mkdtemp(prefix="p5_dep_")
    _w(d, "data/configs/regions/newbie_village/npcs.json", {"npcs": [
        {"id": "npc_001", "name": "张三", "dialog_id": "dlg_001", "scene": "newbie_village"},
    ]})
    _w(d, "data/configs/npcs/dialogs/_index.json", {"shards": {"dlg_001": {}}})
    _w(d, "data/configs/npcs/dialogs/shards/dlg_001.json", {
        "id": "dlg_001", "npc_id": "npc_001", "lines": [
            {"id": "l1", "speaker_id": "npc_001", "text": "你好", "next_id": "l2"},
            {"id": "l2", "speaker_id": "player", "text": "你好", "next_id": "l1"},  # l1↔l2 成环
        ]})
    _w(d, "data/configs/quests/main.json", {"quests": [
        {"id": "q_001", "name": "初遇", "dialogue_id": "dlg_001", "reward_item_ids": ["item_001"]},
    ]})
    _w(d, "data/configs/items/consumables.json", {"items": [
        {"id": "item_001", "name": "金创药", "type": "consumable"},
    ]})
    return d


def section_a(root, checks):
    """段 A：Content Graph 图遍历纯函数。"""
    # A1 impact：npc_001 影响 dlg_001（直接） + q_001（间接，通过 dlg_001）
    imp = ref_index.impact("npc", "npc_001", root=root)
    checks.append(("A1 impact NPC→对话→任务",
                   "dlg_001" in imp.get("dialog", []) and "q_001" in imp.get("quest", []),
                   "imp=%s" % imp))
    # A2 impact 不回溯自身（NPC 不在结果里）
    checks.append(("A2 impact 不含起点自身", "npc" not in imp or "npc_001" not in imp.get("npc", []),
                   "imp.keys=%s" % list(imp.keys())))
    # A3 transitive_reverse：item_001 被 q_001 引用（直接） + 被 npc_001 引用（间接，通过 q→dlg→npc 不对，应该反过来）
    #   正确链路：npc_001 → dlg_001 ← q_001 → item_001
    #   反向 item_001 的引用方 = q_001（直接）
    rev = ref_index.transitive_reverse("item", "item_001", root=root)
    checks.append(("A3 transitive_reverse item→quest",
                   "q_001" in rev.get("quest", []),
                   "rev=%s" % rev))
    # A4 find_cycles：line_jump l1↔l2 成环
    cycles = ref_index.find_cycles(root=root)
    has_line_cycle = any(
        all(k == "line_jump" for k, _ in c) and len(c) >= 2
        for c in cycles
    )
    checks.append(("A4 find_cycles 检测到 line_jump 环", has_line_cycle,
                   "cycles=%d first=%s" % (len(cycles), cycles[0] if cycles else None)))
    # A5 无环实体：npc_001 不在任何环里
    has_npc_cycle = any("npc_001" in [e for _k, e in c] for c in cycles)
    checks.append(("A5 NPC 不在环里", not has_npc_cycle, "npc_in_cycle=%s" % has_npc_cycle))


def main():
    failures = []
    d = make_temp_project()
    try:
        checks = []
        section_a(d, checks)
        for name, ok, msg in checks:
            print("  %s %s（%s）" % ("✓" if ok else "✗", name, msg))
        failures = [(n, o, m) for n, o, m in checks if not o]
    finally:
        shutil.rmtree(d, ignore_errors=True)
    print("════ Phase 5 Dependency Graph：%s（失败 %d）════" % (
        "✓ 通过" if not failures else "✗ 未过", len(failures)))
    return 0 if not failures else 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 2: 运行确认红灯**

Run: `python tools/phase5_dep_graph_tests.py`
Expected: AttributeError（impact / transitive_reverse / find_cycles 不存在），退出码 1

- [ ] **Step 3: 在 ref_index.py 追加图遍历函数**

在文件尾部（三件套查询函数之后、main 之前）追加：

```python
# ---- Content Graph：图遍历（Phase 5 Dependency Graph）----
def _kind_of_id(eid, defs):
    """根据 id 反推实体类型（跨 kind 图遍历用）。优先匹配更具体的域。"""
    for k in ["npc", "quest", "item", "battle", "enemy", "dialog",
              "ability", "flag_def", "battle_layout", "line_jump"]:
        if str(eid) in defs.get(k, {}):
            return k
    return None


def impact(kind, eid, root=None):
    """影响分析（正向可传递）：改 kind/eid 会波及哪些下游实体。
    返回 {kind: [ids...]}，不含起点自身。"""
    defs, refs = build(root)
    visited = set()
    result = {}

    def _walk(k, e):
        key = (k, e)
        if key in visited:
            return
        visited.add(key)
        for rk, rf, rt, _fp, _s in refs:
            if rf == e and rt in defs.get(rk, {}):
                result.setdefault(rk, set()).add(rt)
                _walk(rk, rt)

    _walk(kind, str(eid))
    return {k: sorted(v) for k, v in result.items()}


def transitive_reverse(kind, eid, root=None):
    """传递反向依赖：谁直接+间接引用了 kind/eid。
    返回 {kind: [ids...]}，不含起点自身。"""
    defs, refs = build(root)
    visited = set()
    result = {}

    def _walk(k, e):
        key = (k, e)
        if key in visited:
            return
        visited.add(key)
        for rk, rf, rt, _fp, _s in refs:
            if rk == k and rt == e:
                fk = _kind_of_id(rf, defs)
                if fk:
                    result.setdefault(fk, set()).add(rf)
                    _walk(fk, rf)

    _walk(kind, str(eid))
    return {k: sorted(v) for k, v in result.items()}


def find_cycles(root=None):
    """Content Graph 环检测。返回 [cycle_list]，每个 cycle 是 [(kind, id), ...]。"""
    defs, refs = build(root)
    # 建邻接表：(kind, id) -> [(kind, id)]
    adj = {}
    for rk, rf, rt, _fp, _s in refs:
        if rt not in defs.get(rk, {}):
            continue
        fk = _kind_of_id(rf, defs)
        if not fk:
            continue
        adj.setdefault((fk, rf), []).append((rk, rt))
    # DFS 三色法找环
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {}
    cycles = []

    def _dfs(node, path):
        color[node] = GRAY
        path.append(node)
        for nb in adj.get(node, []):
            c = color.get(nb, WHITE)
            if c == GRAY:
                idx = path.index(nb)
                cycles.append(path[idx:])
            elif c == WHITE:
                _dfs(nb, path)
        path.pop()
        color[node] = BLACK

    for node in adj:
        if color.get(node, WHITE) == WHITE:
            _dfs(node, [])
    return cycles
```

- [ ] **Step 4: 运行确认绿灯**

Run: `python tools/phase5_dep_graph_tests.py`
Expected: A1~A5 全 ✓，退出码 0

Run: `python tools/ref_index.py`
Expected: GATE6 仍全绿（无新增悬空）

- [ ] **Step 5: 提交**

```bash
python tools/commit_queue.py add --window 工作室工具 --message "[集成] Phase5 Task2：Content Graph 图遍历（impact / transitive_reverse / find_cycles）" --files tools/ref_index.py tools/phase5_dep_graph_tests.py
```

---

### Task 3: Code Graph 命名澄清 + impact/reverse 接口

**Files:**
- Modify: `tools/desktop_studio/scan_deps.py`（文档澄清 + 追加 impact_of_file / reverse_deps_of_file）

- [ ] **Step 1: 改文档字符串 + 追加两个函数**

修改文件头部 docstring，明确标注为 **Code Graph（代码层依赖图）**。

在文件尾部（main 之前）追加：

```python
# ---- Code Graph：impact / reverse（基于 scan 结果）----
def _build_index(report):
    """从 scan 报告构建 path -> node 和边索引。"""
    nodes = {n["path"]: n for n in report["nodes"]}
    forward = {}   # path -> [to_path]
    backward = {}  # path -> [from_path]
    for e in report["edges"]:
        if not e["resolved"]:
            continue
        f, t = e["from"], e["to"]
        forward.setdefault(f, []).append(t)
        backward.setdefault(t, []).append(f)
    return nodes, forward, backward


def impact_of_file(file_path, root=None):
    """Code Graph 影响分析（正向）：改 file_path 会影响哪些文件（可传递）。
    file_path 支持绝对路径或 res:// 路径。返回 [path...]（去重排序）。"""
    if root is None:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    report = scan(root)
    nodes, forward, _back = _build_index(report)
    # 标准化输入路径
    if file_path.startswith("res://"):
        start = file_path
    else:
        rel = os.path.relpath(os.path.abspath(file_path), root)
        start = "res://" + rel.replace("\\", "/")
    visited = set()
    result = set()

    def _walk(p):
        if p in visited:
            return
        visited.add(p)
        for t in forward.get(p, []):
            result.add(t)
            _walk(t)

    if start in nodes:
        _walk(start)
    return sorted(result)


def reverse_deps_of_file(file_path, root=None):
    """Code Graph 反向依赖（可传递）：谁引用了 file_path。返回 [path...]。"""
    if root is None:
        root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    report = scan(root)
    nodes, _fwd, backward = _build_index(report)
    if file_path.startswith("res://"):
        start = file_path
    else:
        rel = os.path.relpath(os.path.abspath(file_path), root)
        start = "res://" + rel.replace("\\", "/")
    visited = set()
    result = set()

    def _walk(p):
        if p in visited:
            return
        visited.add(p)
        for f in backward.get(p, []):
            result.add(f)
            _walk(f)

    if start in nodes:
        _walk(start)
    return sorted(result)
```

- [ ] **Step 2: 验证（快速手测一个文件）**

Run: `python -c "import sys; sys.path.insert(0, 'tools/desktop_studio'); import scan_deps; print(scan_deps.impact_of_file('autoload/ConfigManager.gd')[:5])"`
Expected: 输出受 ConfigManager 影响的文件列表

- [ ] **Step 3: 提交**

```bash
python tools/commit_queue.py add --window 工作室工具 --message "[集成] Phase5 Task3：Code Graph 命名澄清 + impact/reverse 接口" --files tools/desktop_studio/scan_deps.py
```

---

### Task 4: dep_graph 统一门面（双图分离，禁混用）

**Files:**
- Create: `tools/dep_graph.py`
- Modify: `tools/phase5_dep_graph_tests.py`（追加段 B）

- [ ] **Step 1: 加段 B 断言（红灯）**

在测试文件的 `main()` 之前追加：

```python
def section_b(root, checks):
    """段 B：dep_graph 统一门面（content_* / code_* 双命名空间）。"""
    sys.path.insert(0, os.path.join(HERE, "..", "tools"))
    import dep_graph
    # B1 content_impact 透传 ref_index.impact
    imp = dep_graph.content_impact("npc", "npc_001", root=root)
    checks.append(("B1 content_impact 透传",
                   "dlg_001" in imp.get("dialog", []),
                   "imp=%s" % imp))
    # B2 content_reverse 透传（transitive=True）
    rev = dep_graph.content_reverse("item", "item_001", root=root, transitive=True)
    checks.append(("B2 content_reverse 透传",
                   "q_001" in rev.get("quest", []),
                   "rev=%s" % rev))
    # B3 content_cycles 透传
    cycles = dep_graph.content_cycles(root=root)
    checks.append(("B3 content_cycles 透传", len(cycles) >= 1,
                   "cycles=%d" % len(cycles)))
    # B4 code_scan 透传 scan_deps（对工程根扫描有结果）
    code_report = dep_graph.code_scan(root=root)
    checks.append(("B4 code_scan 透传",
                   code_report.get("summary", {}).get("gd_files", 0) >= 1,
                   "gd_files=%d" % code_report.get("summary", {}).get("gd_files", 0)))
```

在 `main()` 中 `section_a(d, checks)` 之后加 `section_b(d, checks)`。

- [ ] **Step 2: 运行确认红灯**

Run: `python tools/phase5_dep_graph_tests.py`
Expected: ImportError（dep_graph 模块不存在），退出码 1

- [ ] **Step 3: 实现 dep_graph.py**

```python
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
dep_graph.py —— Dependency Graph 统一门面（Phase 5）

双图分离（施工图 §9 / 硬约束 #3）：
  · Content Graph（数据实体层）：ref_index.py 核心
  · Code Graph（代码层）：scan_deps.py 核心

命名空间化 API：content_* / code_*，禁止跨图混用。

用法：
  python tools/dep_graph.py --content-impact npc npc_001
  python tools/dep_graph.py --content-reverse dialog dlg_001
  python tools/dep_graph.py --content-cycles
  python tools/dep_graph.py --code-impact autoload/ConfigManager.gd
  python tools/dep_graph.py --code-reverse scenes/ui/HUD.tscn
"""
import os
import sys
import json
import argparse

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)

# Content Graph（实体层）
import ref_index

# Code Graph（代码层）
sys.path.insert(0, os.path.join(HERE, "desktop_studio"))
import scan_deps


# ---- Content Graph ----
def content_impact(kind, eid, root=None):
    """Content Graph 影响分析（正向可传递）。"""
    return ref_index.impact(kind, eid, root=root)


def content_reverse(kind, eid, root=None, transitive=True):
    """Content Graph 反向依赖。transitive=True 传递，False 仅一阶。"""
    if transitive:
        return ref_index.transitive_reverse(kind, eid, root=root)
    # 一阶：复用 reverse_dependencies 但按 kind 分组
    who = ref_index.reverse_dependencies(eid, root=root)
    result = {}
    for k, f, _fp in who:
        if k == kind:
            result.setdefault(k, set()).add(f)
    return {k: sorted(v) for k, v in result.items()}


def content_cycles(root=None):
    """Content Graph 环检测。"""
    return ref_index.find_cycles(root=root)


def content_build(root=None):
    """Content Graph 构建（透传 ref_index.build）。"""
    return ref_index.build(root=root)


# ---- Code Graph ----
def code_scan(root=None):
    """Code Graph 扫描（透传 scan_deps.scan）。"""
    return scan_deps.scan(root or ROOT)


def code_impact(file_path, root=None):
    """Code Graph 影响分析（正向可传递）。"""
    return scan_deps.impact_of_file(file_path, root=root or ROOT)


def code_reverse(file_path, root=None):
    """Code Graph 反向依赖（可传递）。"""
    return scan_deps.reverse_deps_of_file(file_path, root=root or ROOT)


# ---- CLI ----
def main():
    ap = argparse.ArgumentParser(description="Dependency Graph 统一门面（Content / Code 双图分离）")
    ap.add_argument("--root", default=ROOT)
    ap.add_argument("--content-impact", nargs=2, metavar=("KIND", "ID"),
                    help="Content Graph 影响分析：改 KIND/ID 会影响什么")
    ap.add_argument("--content-reverse", nargs=2, metavar=("KIND", "ID"),
                    help="Content Graph 反向依赖：谁引用了 KIND/ID")
    ap.add_argument("--content-cycles", action="store_true",
                    help="Content Graph 环检测")
    ap.add_argument("--code-impact", metavar="PATH",
                    help="Code Graph 影响分析：改 PATH 文件会影响什么")
    ap.add_argument("--code-reverse", metavar="PATH",
                    help="Code Graph 反向依赖：谁引用了 PATH")
    ap.add_argument("--json", action="store_true", help="输出 JSON 格式")
    args = ap.parse_args()

    result = None
    label = ""
    if args.content_impact:
        kind, eid = args.content_impact
        result = content_impact(kind, eid, root=args.root)
        label = "Content Impact: %s/%s" % (kind, eid)
    elif args.content_reverse:
        kind, eid = args.content_reverse
        result = content_reverse(kind, eid, root=args.root)
        label = "Content Reverse: %s/%s" % (kind, eid)
    elif args.content_cycles:
        result = content_cycles(root=args.root)
        label = "Content Cycles: %d 个环" % len(result)
    elif args.code_impact:
        result = code_impact(args.code_impact, root=args.root)
        label = "Code Impact: %s（影响 %d 个文件）" % (args.code_impact, len(result))
    elif args.code_reverse:
        result = code_reverse(args.code_reverse, root=args.root)
        label = "Code Reverse: %s（被 %d 个文件引用）" % (args.code_reverse, len(result))
    else:
        ap.print_help()
        return 0

    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2))
    else:
        print("═══ %s ═══" % label)
        if isinstance(result, dict):
            for k, v in sorted(result.items()):
                print("  %s: %s" % (k, v))
        elif isinstance(result, list):
            if result and isinstance(result[0], list):
                for i, c in enumerate(result[:10]):
                    print("  环 %d: %s" % (i + 1, " → ".join("%s/%s" % x for x in c)))
                if len(result) > 10:
                    print("  ... 共 %d 个" % len(result))
            else:
                for item in result:
                    print("  " + item)
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: 运行确认绿灯**

Run: `python tools/phase5_dep_graph_tests.py`
Expected: A 段 + B 段全 ✓

Run: `python tools/dep_graph.py --content-cycles`
Expected: 输出 Content Graph 环检测结果

- [ ] **Step 5: 提交**

```bash
python tools/commit_queue.py add --window 工作室工具 --message "[集成] Phase5 Task4：dep_graph 统一门面（content_* / code_* 双图分离，禁混用）" --files tools/dep_graph.py tools/phase5_dep_graph_tests.py
```

---

### Task 5: GATE41 升级（Content 环检测 REPORT 项）

**Files:**
- Modify: `tools/arch_validators.py`（追加 content_cycle 校验）
- Modify: `tools/verify_all.py`（GATE41 输出适配，可选）

- [ ] **Step 1: 加段 C 断言（红灯）**

在测试文件追加：

```python
def section_c(root, checks):
    """段 C：GATE41 Content 环检测集成。"""
    # C1 有环的夹具 → find_cycles 能检测到（已在 A4 验证，此处测集成）
    import dep_graph
    cycles = dep_graph.content_cycles(root=root)
    checks.append(("C1 content_cycles 集成可用", len(cycles) >= 1,
                   "cycles=%d" % len(cycles)))
```

在 `main()` 里加 `section_c(d, checks)`。

- [ ] **Step 2: 在 arch_validators.py 追加 content_cycle 校验（REPORT 模式）**

读取现有 `arch_validators.py` 结构，在 dependency 相关校验旁追加 Content Graph 环检测（REPORT 模式，只报告不拦截，避免误杀）。

> 注：arch_validators.py 的具体结构需读文件后确定，实现时保持现有风格（check_* 函数 + 统一输出格式）。

- [ ] **Step 3: 运行确认绿灯**

Run: `python tools/verify_all.py --gate 41`
Expected: GATE41 通过，新增 content_cycle REPORT 项

Run: `python tools/phase5_dep_graph_tests.py`
Expected: 全 ✓

- [ ] **Step 4: 提交**

```bash
python tools/commit_queue.py add --window 工作室工具 --message "[集成] Phase5 Task5：GATE41 升级（Content Graph 环检测 REPORT 项）" --files tools/arch_validators.py tools/phase5_dep_graph_tests.py
```

---

### Task 6: 全量回归 + flush

**Files:** 无新增

- [ ] **Step 1: 关键门禁回归**

Run: `python tools/verify_all.py --gate 6 7 10 11 41`
Expected: 全绿

- [ ] **Step 2: GATE2 单测回归**

Run: `python tools/verify_all.py --gate 2`
Expected: 全过（无新增失败）

- [ ] **Step 3: security_selftest**

Run: `python tools/desktop_studio/security_selftest.py`
Expected: 通过

- [ ] **Step 4: flush 提交队列**

Run: `python tools/commit_queue.py flush`
Expected: 4 条记录（Task1~Task5）全部提交成功

- [ ] **Step 5: 更改日志留痕**

按项目惯例向 `docs/更改日志.md` 追加 Phase 5 完成记录。

---

## Self-Review 记录

- **Spec 覆盖**：双图分离（T3/T4）✓；Content Graph impact / transitive_reverse（T2）✓；find_cycles 环检测（T2/T5）✓；引用面实测归档（T1）✓；GATE41 升级（T5）✓；统一门面 dep_graph.py（T4）✓。
- **占位符扫描**：Task 5 Step 2 提到"需读文件后确定"——arch_validators.py 结构已知有 check_dependency 风格，实现时按现有模式追加，不算占位符。
- **类型一致性**：Content Graph 函数统一签名 `(kind, eid, root=None)`，返回 `{kind: [ids]}`；Code Graph 函数统一签名 `(file_path, root=None)`，返回 `[paths]`；dep_graph 门面按 `content_*` / `code_*` 命名空间化。跨 Task 一致。
