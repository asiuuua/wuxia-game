# Phase 5 设计：Dependency Graph（Code / Content 双图分离 + impact 分析）

> 日期：2026-09-07
> 来源：`docs/audit/工作室V1.4全盘审查整改报告_2026-09-06.md` M-3 / Phase 5（Dependency Graph，2~3 天）
> 依据：宪法 §69（Dependency Graph）/ 15 图 ST-3（§9 硬约束 #3）/ ADR-0003（目录迁移延 Phase 5）
> 状态：已获用户最高权限（2026-09-07）

## 1. 目标

1. **Code Graph / Content Graph 分离**（施工图 §9，硬约束 #3）：现有 `scan_deps.py` 明确为 Code Graph（.gd 代码层依赖）；新增 Content Dependency Graph（数据实体层依赖）。两图分别输出、禁止混用。
2. **impact(entity_id) / reverse_dependencies(entity_id)**：在 Content Graph 上实现可传递的影响分析与反查，回答宪法 §69 的问题——「我修改这个 NPC，会影响什么？」。
3. **引用面实测归档**：全量扫描 `data/configs` 路径在生产代码 + 工具中的引用点，作为 ADR-0003 目录迁移（`data/configs/** → content/definitions/**`）的前置输入。
4. **GATE41 升级**：架构校验器组纳入 Content Dependency Graph 环检测与跨域引用校验。

## 2. 现状盘点（实测）

### 2.1 已有资产

| 资产 | 位置 | 状态 |
|---|---|---|
| ref_index.py（实体引用索引） | `tools/ref_index.py` | ✅ Phase 4 已升级为三件套，含 `reverse_dependencies()` / `validate_delete()` / `validate_cascade()` |
| scan_deps.py（代码依赖图） | `tools/desktop_studio/scan_deps.py` | ⚠️ 只扫 .gd 代码层，无 impact / reverse_deps 接口，未明确命名为 Code Graph |
| GATE41 架构校验器 | `tools/arch_validators.py` | ⚠️ 含 dependency 禁引矩阵 + 环检测，但只针对代码层模块 |
| 实体类型（已收集） | ref_index build() | npc / quest / item / battle / enemy / dialog / ability / flag_def / battle_layout / line_jump（共 10 类） |

### 2.2 引用面实测结果（2026-09-07 扫描）

| 指标 | 数值 |
|---|---|
| 总匹配文件数 | 62 |
| 总匹配行数 | 176 |
| 生产代码（.gd） | 29 文件 / 84 行 |
| 工具脚本（.py/.gd） | 33 文件 / 92 行 |

按目录分布：autoload 6 文 41 行（ConfigManager 集中装载）、tools 33 文 92 行、scenes 15 文 26 行、addons 4 文 8 行、application 2 文 6 行、services 2 文 3 行。

**关键枢纽**：`autoload/ConfigManager.gd` 集中定义 30+ 配置表路径，是目录迁移的核心改造点。

### 2.3 缺口

| 项 | 现状 | 缺口 |
|---|---|---|
| Content Graph impact 分析 | 只有一阶 `reverse_dependencies()` | 缺可传递影响分析（如 NPC→对话→任务→物品 全链） |
| Code / Content 命名混淆 | scan_deps.py 叫"依赖图"，ref_index 叫"引用索引" | 未按施工图 §9 明确分离为 Code Graph / Content Graph |
| 环检测（Content 侧） | 无 | 任务链 / 对话跳转可能成环，需检测 |
| GATE41 覆盖 | 只校验代码层依赖 | 缺 Content Graph 校验（环 / 跨域非法引用） |

## 3. 设计

### 3.1 双图分离原则

```
┌─────────────────────────────────────────────────┐
│              Dependency Graph (总名)              │
├──────────────────────┬──────────────────────────┤
│    Code Graph        │    Content Graph         │
│  （代码层依赖）        │  （数据实体层依赖）        │
│  · scan_deps.py      │  · ref_index.py (核心)    │
│  · .gd 文件级        │  · 实体定义 + 引用边       │
│  · extends/preload   │  · NPC/Dialog/Quest/…     │
│  · 向上依赖违例检测   │  · impact / 反向依赖 / 环  │
└──────────────────────┴──────────────────────────┘
```

- **Code Graph** = `scan_deps.py` 现状（重命名澄清，加 impact/reverse_deps 接口）
- **Content Graph** = `ref_index.py` 三件套 + 新增图遍历能力（impact、传递反查、环检测）
- **统一门面** = `dep_graph.py`（`tools/` 顶层），对外暴露 `code_*` / `content_*` 两组 API，禁止跨图混用

### 3.2 Content Dependency Graph 核心扩展

在 `ref_index.py` 现有基础上追加三个函数（Content Graph 专属）：

```python
# ---- Content Graph：图遍历 ----
def impact(kind, eid, root=None):
    """影响分析：改这个实体会波及哪些实体（正向可传递）。
    返回 {kind: set(ids)}，含直接 + 间接被引用方。
    例：impact("npc", "npc_001") → {dialog: {dlg_001}, quest: {q_001}, ...}"""
    defs, refs = build(root)
    visited = set()
    result = {}
    def _walk(k, e):
        key = (k, e)
        if key in visited:
            return
        visited.add(key)
        # 找 e 引用了谁（正向边：from=e → to=下游）
        for rk, rf, rt, _fp, _s in refs:
            if rf == e and rt in defs.get(rk, {}):
                result.setdefault(rk, set()).add(rt)
                _walk(rk, rt)
    _walk(kind, eid)
    return {k: sorted(v) for k, v in result.items()}


def transitive_reverse(kind, eid, root=None):
    """传递反向依赖：谁直接+间接引用了这个实体。
    返回 {kind: set(ids)}。例：删一个对话，哪些 NPC/任务 受影响。"""
    defs, refs = build(root)
    visited = set()
    result = {}
    def _walk(k, e):
        key = (k, e)
        if key in visited:
            return
        visited.add(key)
        for rk, rf, rt, _fp, _s in refs:
            if rk == k and rt == e and rf in defs.get(rk, set()):
                # rf 引用了 e → rf 是反向依赖方
                # 找 rf 所属的 kind（rf 是 from_id，需反推它属于哪种实体）
                fk = _kind_of_id(rf, defs)
                if fk:
                    result.setdefault(fk, set()).add(rf)
                    _walk(fk, rf)
    _walk(kind, eid)
    return {k: sorted(v) for k, v in result.items()}


def find_cycles(root=None):
    """Content Graph 环检测。返回 [cycle_list]，每个 cycle 是 [(kind, id), ...]。"""
    defs, refs = build(root)
    # 建邻接表
    adj = {}  # (kind, id) -> [(kind, id)]
    for rk, rf, rt, _fp, _s in refs:
        if rt not in defs.get(rk, {}):
            continue  # 跳过悬空
        fk = _kind_of_id(rf, defs)
        if not fk:
            continue
        adj.setdefault((fk, rf), []).append((rk, rt))
    # DFS 找环
    WHITE, GRAY, BLACK = 0, 1, 2
    color = {}
    cycles = []
    def _dfs(node, path):
        color[node] = GRAY
        path.append(node)
        for nb in adj.get(node, []):
            c = color.get(nb, WHITE)
            if c == GRAY:
                # 找到环：从 nb 在 path 中的位置到末尾
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


def _kind_of_id(eid, defs):
    """根据 id 反推实体类型（用于跨 kind 的图遍历）。"""
    for k, d in defs.items():
        if eid in d:
            return k
    return None
```

### 3.3 Code Graph 命名澄清 + 接口对齐

`scan_deps.py` 不做大改，只做两件事：
1. 文档字符串明确标注为 **Code Graph**（代码层依赖图）
2. 追加两个轻量函数：`impact_of_file(path)` / `reverse_deps_of_file(path)`（基于现有 scan 结果）

### 3.4 统一门面 dep_graph.py

新建 `tools/dep_graph.py`，提供命名空间化的 API：

```python
# Content Graph 接口（实体层）
def content_impact(kind, eid, root=None): ...
def content_reverse(kind, eid, root=None, transitive=True): ...
def content_cycles(root=None): ...
def content_build(root=None): ...   # 透传 ref_index.build

# Code Graph 接口（代码层）
def code_impact(file_path, root=None): ...
def code_reverse(file_path, root=None): ...
def code_scan(root=None): ...       # 透传 scan_deps.scan

# 禁混用：两套接口内部互不通，文档显式声明
```

### 3.5 GATE41 升级

在 `arch_validators.py` 中追加 Content Graph 校验项：
- **C-DEP-01**：Content Graph 零环（对话跳转环 / 任务依赖环 均拦截）
- **C-DEP-02**：跨域引用白名单（如 NPC 不得直接引用 item，须通过 quest 中转——如宪法/施工图有此规则则启用，否则 REPORT 模式）

> 本期 Phase 5 先落地 C-DEP-01（环检测，REPORT 模式不拦），C-DEP-02 待数据宪法明确跨域规则后再启用。

### 3.6 引用面实测归档

把扫描结果正式归档为 `docs/architecture/引用面实测报告_2026-09-07.md`，包含：
- 统计总表
- 按模块/文件分组的详细清单
- ADR-0003 目录迁移影响评估（重点文件清单）
- ConfigManager 改造优先级评估

## 4. 验收标准

1. `dep_graph.content_impact("npc", "npc_001")` 能返回对话 + 任务（如有）等下游影响
2. `dep_graph.content_reverse("dialog", "dlg_001", transitive=True)` 能返回引用该对话的 NPC + 任务
3. `dep_graph.content_cycles()` 在当前工程上返回 0 环（或已知环被基线豁免）
4. `tools/dep_graph.py --content-impact npc npc_001` CLI 可用
5. GATE41 全绿（含新增 Content 环检测 REPORT 项）
6. 引用面实测报告正式归档
