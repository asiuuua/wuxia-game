# Phase 4 设计：Reference 三件套 + 删除保护

> 日期：2026-09-07
> 来源：`docs/audit/工作室V1.4全盘审查整改报告_2026-09-06.md` Phase 4（Reference 三件套）
> 状态：已获用户批准（2026-09-07，四节设计全部认可）

## 1. 目标

1. ReferenceResolver（解析）/ ReferenceInspector（检查）/ ReferenceValidator（校验）三件套显式化，与 `tools/ref_index.py` 合并演进（不新建独立模块）。
2. 删除保护：DELETE 被引用实体 = BLOCKED，除非显式 Cascade Change（级联声明）。
3. 验收：负向测试「NPC.dialogue_id = UNKNOWN → Reference FAIL → Commit BLOCK」通过。

## 2. 现状盘点（实测）

| 项 | 现状 |
|---|---|
| 悬空引用拦截 | ✅ DataSink ⑤ 增量反查已拦截「写入引入新悬空引用」（前置侦察已验证：`dialog_id=UNKNOWN` 写入被回滚拦截） |
| 三件套 | ⚠️ 职责隐含在 ref_index.py：`build()`=解析、`check()`=校验、`--who`=反查，未显式命名 |
| 删除保护 | ❌ `npc_delete` / `dlg_delete` / `dlg_line_delete` / `battle_layout_delete` 均无「谁引用了我」检查 |
| 引用边缺口 | ❌ 对话分片 → NPC（顶层 `npc_id` / 行内 `speaker_id`）未收集；战斗 → 战棋布局（`scenes/battles.json` 的 `layout` 字段）未收集 |

## 3. 设计

### 3.1 三件套结构（ref_index.py 内重组）

- **ReferenceResolver** = 现有 `build()` 升级：扫描 data/configs → 产出 `(defs 定义索引, refs 引用边)`。
- **ReferenceInspector** = 查询侧：
  - `reverse_dependencies(target)` → 谁引用了 target（Phase 5 Dependency Graph 前奏）
  - `resolve(kind, id)` → 定义是否存在、所在文件
  - `references_of(from_id)` → 我引用了谁
- **ReferenceValidator** = 校验侧：
  - `validate_dangling(defs, refs)` → 悬空检测（= 现有 `check()`）
  - `validate_delete(kind, id)` → 删除保护（无引用放行；有引用返回 BLOCK + 引用方列表）
  - `validate_cascade(kind, id, cascade)` → 级联验证

CLI 契约冻结：`python tools/ref_index.py`（全量校验报告）与 `--who` 输出格式不变，verify_all GATE6 零改动。

### 3.2 补齐两条引用边

1. 对话分片 → NPC：`data/configs/npcs/dialogs/shards/*.json` 与 `regions/*/dialogs/*.json` 的顶层 `npc_id` + 行内 `speaker_id` 收集为 `speaker → npc` 边。
2. 战斗 → 战棋布局：`data/configs/scenes/battles.json`（及 battles 定义形态）的 `layout` 字段收集为 `battle → battle_layout` 边（battle_layout 定义侧 = `data/configs/battles/grids/<id>.json`）。

**引用边软硬分级（实现决策，2026-09-07）：**

| 边 | 软/硬 | 依据 |
|---|---|---|
| `dialog.npc_id → npc` | **软**（悬空告警不拦） | VA4-BINDING 契约语义=「登记放行、只校验不拒载」（data_sink ②）；GATE7 冒烟实测：先删 NPC 进回收站、后建对话引用该 id（延迟绑定）是既有合法工作流，硬边会拦截编辑中间态。删除保护仍生效（reverse_dependencies 含软边） |
| `line.speaker_id → npc` | **软** | 内容字段；`player` 排除；删 NPC 级联清 npc_id 后 speaker 悬空不被 ⑤ 反拦（避免死锁） |
| `npc.dialog_id → dialog` 等 | **硬** | VA3-DANGLING 数据完整性，悬空即拦（负向验收 E 段依赖） |
| `battle.layout → battle_layout` | **硬** | 战斗定义契约字段，悬空即拦 |
| `line_jump`（next_id / options.jump_id） | **硬** | 对话图内部结构，⑤ 兜底（C6 场景） |

> 修正记录：初版计划将 `dialog.npc_id` 定为硬边，实现期被 GATE7 冒烟实测推翻——`audit_service.self_test` 的编辑闭环「删除 NPC → 回收站 → dlg_new(npc_id=已删 NPC)」触发 ⑤ 拦截。改软边后：删除保护、级联验证、负向验收均不受影响，GATE7 恢复全绿。

### 3.3 删除保护接入（4 个删除函数）

| 函数 | 实体 | 反向引用来源 |
|---|---|---|
| `npc_delete` | NPC | 对话分片 npc_id / speaker_id（补边后生效） |
| `dlg_delete` | 对话 | NPC.dialog_id |
| `dlg_line_delete` | 台词行 | 同对话内 next_id / options.jump_id |
| `battle_layout_delete` | 战棋布局 | 战斗定义 layout 字段（补边后生效） |

被引用 → 返回 BLOCKED，消息列出全部引用方（例：「删除被阻止：npc_001 被 2 处引用 [对话 dlg_demo 的 speaker_id]…」）。

边界：`cel_delete`（欢庆内容）为独立存储域，不在保护范围；quest 无删除函数，不涉及。

### 3.4 Cascade 显式级联验证（不依赖 Phase 7 Transaction）

删除函数新增可选参数 `cascade`（引用方 id 列表），语义 = 显式声明「我已确认清理这些引用」：

- 不传 cascade 且被引用 → BLOCKED。
- 传 cascade → 三项校验全过才放行：
  1. cascade 覆盖**所有**反向引用（漏报任一处 → 仍 BLOCK）；
  2. cascade 中引用**确实存在**（防瞎写）；
  3. 级联清理 = 被删实体侧移除/置空引用方字段（引用方实体本身不删）。

示例：删除对话 `dlg_demo`，cascade=`["npc_001"]` → 校验 `npc_001.dialog_id` 确实引用它 → 将 `npc_001.dialog_id` 置空后再删 → 成功；若另有引用方 `npc_002` 未声明 → BLOCK。

### 3.5 验收测试与 GATE 接入

新增自包含测试 `tools/phase4_reference_tests.py`（临时目录，不碰真数据），挂 verify_all 新槽位 **GATE11**：

1. 负向：`NPC.dialog_id=UNKNOWN` 写入 → Reference FAIL → 写入 BLOCK（含回滚验证）——报告验收项。
2. 删除保护：删被引用 NPC/对话/布局 → BLOCKED；删无引用实体 → 成功。
3. 级联：cascade 完整覆盖 → 成功且引用方字段同步置空；漏报 → BLOCK。
4. 边补全：speaker_id、layout 两条新边各自命中一次。

## 4. 涉及文件

| 文件 | 动作 |
|---|---|
| `tools/ref_index.py` | 重组三件套 + 补两条引用边 + 新增 reverse_dependencies / validate_delete / validate_cascade |
| `tools/desktop_studio/services/npc_service.py` | `npc_delete` 接入删除保护 + cascade |
| `tools/desktop_studio/services/dialogue_service.py` | `dlg_delete` / `dlg_line_delete` 接入删除保护 + cascade |
| `tools/desktop_studio/services/asset_service.py` | `battle_layout_delete` 接入删除保护 + cascade |
| `tools/phase4_reference_tests.py` | 新增验收测试 |
| `tools/verify_all.py` | 注册 GATE11 |

## 5. 明确不做（边界）

- 不新建独立 reference.py 模块（报告要求「与 ref_index.py 合并演进」）。
- 不做多文件事务原子性（Phase 7 Transaction 范畴；级联为两文件顺序写，中途失败由既有 DataSink 备份兜底并如实报错）。
- 不改 route 文件、不改 preset_*.json、不动他人既有 UI。
- 不做删除影响预览前端接入（Phase 5 Dependency Graph 范畴）。
