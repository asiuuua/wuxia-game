# 04 Test Infrastructure / Architecture Gate 施工图 V1.4 修复版

| 项 | 值 |
|---|---|
| 状态 | **FROZEN**（2026-09-06 用户批准；可依此实施） |
| 日期 | 2026-09-05 |
| 上游 | 宪法 V1.4（ADR-0005） → `01_总体架构施工图_V1.4修复版.md`（§92/93/94/95/96/115~120/127/129）→ `02_Domain_Kernel施工图_V1.4修复版.md`（K-R 矩阵）→ `03_Contract_Schema_DataContract施工图_V1.4修复版.md`（C-R 矩阵） |
| 下游 | Phase0（REPORT 测量）→ Phase1（Kernel 契约）→ Phase2（Transaction）逐阶段点亮本图门禁 |
| 冻结物 | `TEST-INFRA v1.2.0`（见 §9） |

---

## 0. 定位

本图回答一个问题：**「如何机器化地证明架构没烂、契约没漂、行为没变」**。

建立五大件（用户指定冻结范围）：

1. **Unit Test 基础** —— 现有 73 测试资产的升级契约，不推翻；
2. **Contract Test 基础** —— `Module A → Public Contract → Module B` 三方一致性；
3. **Architecture Linter** —— 01 §92 的 7 个校验器落到一个工具；
4. **Deterministic Test Double** —— FakeClock / SeededRandom / RecordingEventBus / InMemoryRepository / FailureInjector；
5. **CI / verify_all 骨架** —— 门禁注册表 + REPORT 模式 + 工件输出。

**铁律（§104 CONTRACT BEFORE IMPLEMENTATION）**：本图只冻结契约与骨架设计。ACR-0001 施工范围未批前，**不落任何实现代码**。

---

## 1. 现状盘点（机器扫描证据，2026-09-05 实测）

### 1.1 已有资产（第 171 节：升级不丢弃）

| 资产 | 实测 | 价值 |
|---|---|---|
| 测试 Runner | `tests/unit/run_all.gd` + `run_all.tscn`，扫描 `test_*.gd` 反射执行，退出码 0/1 已 CI-ready | 保留为唯一入口，只扩不换 |
| 测试基类 | `_test_base.gd`：`TestBase extends RefCounted`，`expect()/expect_eq()`，`before_each/after_each`，失败不中断汇总暴露 | 设计正确（弃 `assert()` 的原因已注释），冻结其接口向后兼容 |
| 单元测试 | 73 个 `test_*.gd`（bond/romance/quest/shop/forge/save_migration…） | 原地保留，不批量迁移 |
| verify_all | 309 行，GATE1~9 语义齐备（编译/单测/工程规范/预设红线/双写防线/引用校验/工作室冒烟/结构兜底/JS 门禁） | 升级 V2 注册表，9 门禁语义不变 |
| git 钩子 | GATE0a(mouse_filter)/GATE0b(信号契约基线)/GATE0c(ambiguous 警告) | 保留，新增 GATE0d |
| 引用校验 | `tools/ref_index.py`（GATE6：索引+悬空+`--who`+基线） | 03 已定升级为 id_validator 宿主 |
| 确定性底座 | `core/utils/seeded_rng.gd`（SeededRNG） | 升级为实现 02 RandomProvider 契约 |
| 存档迁移测试 | `test_save_migration.gd`（4 场景）+ `SaveManager.SAVE_VERSION="1.1.0"` | 扩为 LN-GATE09 迁移链 |
| UI 烟雾 | `tests/ui/` 7 个 .tscn | 纳入 verify_all 编排（现状手动跑） |

### 1.2 缺口（本图要补）

| # | 缺口 | 证据 |
|---|---|---|
| Q-1 | 契约测试体系整体缺失 | 仅 `test_eventbus.gd` 一份；无 golden payload、无 registry |
| Q-2 | 架构 Linter 缺失 | 01 §92 七校验器 0/7 存在 |
| Q-3 | 确定性 Test Double 空白 | 全仓 grep `fake_/stub_/test_double` 零命中 |
| Q-4 | 测试无注入点 | 测试直接 `new` 真服务，时钟/随机隐依赖 autoload |
| Q-5 | verify_all 无注册表/REPORT/JSON 工件 | 单文件硬编码 GATES dict |
| Q-6 | **门禁编号三套并存且相撞** | 宪法 §88 定义 LN-GATE01~20（含 GATE17 Asset Contract / GATE18 Localization / GATE08 Save/Load / GATE09 Migration）；01 §127 追加 GATE21~32；verify_all 物理槽位 GATE1~9 与 LN 在 **3/4/6/8/9 五个号上语义相撞**（如物理 GATE8=结构兜底 ≠ LN-G08 Save/Load）。03 曾混用两套编号（C-R04/05 指了物理 GATE3，C-R06/07/08 指了物理 GATE6） |
| Q-7 | 事务 11 场景测试（01 §118）全缺 | 0-C 尚未落地，随 Phase2 建 |
| Q-8 | UI 烟雾与集成测试游离 | `tests/integration/` 空目录；7 个 .tscn 未进 verify_all |

**Q-6 的处理（2026-09-05 与宪法原文逐条核对后勘定）**：03 引用的 GATE17/18/08/09 **不是笔误**——它们是宪法 §88 的逻辑编号（Asset Contract / Localization / Save-Load / Migration），本图初版将其误判为「不存在的编号」并提议 GATE33~36，**该提议作废**。真正的缺陷是 03 的 C-R04/05（GATE03）与 C-R06/07/08（GATE06）引用了**物理槽位号**而非 LN 号。已随本图产出同步修正：C-R04/05 → GATE06（Content Schema）、C-R06/07/08 → GATE07（Reference Integrity），并在 03 §8 头部加入命名空间声明。统一编号政策见 §2。

---

## 2. 门禁编号总政策（Gate Registry · 冻结）

### 2.1 双命名空间政策（Q-6 的裁决）

存在三套编号：**宪法 §88**（推荐 GATE01~20）、**01 §127**（V1.2 新增 GATE21~32）、**verify_all 物理槽位**（现存 GATE1~9）。三套若不裁决，任何 Gate 引用都不可判读。冻结如下：

1. **逻辑编号（LN）是唯一规范命名空间**：`LN = 宪法 §88 GATE01~20 ∪ 01 §127 GATE21~32`，共 32 个。**所有施工图 / 契约 / ACR / ADR / 任务卡的 Gate 引用一律用 LN**。
2. **物理槽位是实现编号**：verify_all 现存 GATE1~9 与 hook GATE0a/b/c **冻结不动**（§171 升级不丢弃，工具/skill/记忆大量引用，重编号=高扰动零收益）；其中 GATE1/2 与 LN-G01/02 语义恰好一致，**3~9 与 LN 同号不同义**——因此**物理号禁止在文档中裸引**，只允许出现在代码与 verify_all 输出里。
3. **新物理槽位从 GATE40 起编**：LN 全域是 01~32，物理新槽一律 40+（GATE40、GATE41…），物理与逻辑**永不再撞**。verify_all 输出行内必须附 LN 名，如 `GATE41 [LN-G07 Reference Integrity] ✓`。
4. **一处歧义一次裁决**：本表是 LN↔物理映射的唯一权威；02/03 的 Gate 引用已按本表对齐（03 C-R04/05→GATE06、C-R06/07/08→GATE07；02 的 GATE21~28 全部本就是 LN 号，核对无误）。

### 2.2 Gate Registry（权威表：LN 01~32）

**第一段：宪法 §88 基线（LN-G01~G20）**

| LN | 逻辑名（宪法 §88 原文） | 实现载体 | 状态 | 说明 |
|---|---|---|---|---|
| GATE01 | Compile | 物理 GATE1（headless 零硬错误） | ACTIVE | 同号同义 |
| GATE02 | Unit | 物理 GATE2（run_all 零 ✗ 零 M） | ACTIVE | 同号同义 |
| GATE03 | Integration | tests/integration/ + run_all --tier=integration | PLANNED（Phase2） | 物理槽位 GATE40 |
| GATE04 | Architecture Dependency | arch_lint --rules dependency | PLANNED（Phase1） | 物理槽位 GATE41 |
| GATE05 | Module Boundary | arch_lint --rules module_scope | PLANNED（Phase1） | 物理 GATE40；存量物理 GATE5 双写防线 / GATE8 结构兜底属其内容面 |
| GATE06 | Content Schema | 物理GATE3 升级（JSON 可解析/class_name）+ pack_manifest/-schema_version validators | PARTIAL（Phase1 补全） | C-R01~05/14/15/18 |
| GATE07 | Reference Integrity | 物理 GATE6（ref_index.py 升级：悬空/重复/退役复用/环） | PARTIAL（Phase1 补全） | C-R06~08 |
| GATE08 | Save/Load | save_header_test（SaveHeader 5 字段） | PLANNED（Phase2） | C-R16；物理 GATE8=结构兜底，**无关** |
| GATE09 | Migration | migration_test（迁移链 + 旧档 fixture） | PLANNED（Phase2） | C-R17；物理 GATE9=JS 门禁，**无关** |
| GATE10 | Event Contract | contract_test 事件面 | PLANNED（Phase1） | V1.2 实现并入 GATE24 验证器的事件面 |
| GATE11 | API Contract | contract_test 命令/查询/Repository 面 | PLANNED（Phase1） | 同上，并入 GATE24 |
| GATE12 | Forbidden Dependency | arch_lint --rules api | PLANNED（Phase1） | 与 LN-G22 同源（V1.2 精化） |
| GATE13 | God Object | arch_lint --rules god_object（fan-in/方法数/职责数） | PLANNED（Phase2） | 首个目标=GameManager（17 Service 引用） |
| GATE14 | Direct DB Access | arch_lint --rules api（FileAccess/DirAccess 面） | PLANNED（Phase1） | 同 LN-G22 扫描器 |
| GATE15 | Domain Godot Access | arch_lint --rules api（Node/get_tree 面） | PLANNED（Phase1） | 同上；**V1.4 修复版**：RULE 001 放软后，Domain 经白名单 Adapter/Boundary 触达 Godot 属合法协作（判据=宪法 0-E.3/GATE15 Adapter 放行，白名单升表随 ACR），扫描器只拦白名单外裸引 |
| GATE16 | Studio Smoke | 物理 GATE7（studio_smoke.py） | ACTIVE | 同义映射（号不同） |
| GATE17 | Asset Contract | asset_ref_validator（Definition 禁资源路径） | PLANNED（Phase4） | C-R13 |
| GATE18 | Localization | localization_validator（禁硬编码中文） | PLANNED（Phase4） | C-R12 |
| GATE19 | Performance | performance_test（宪法 §4158 行要求：注明环境/规模/口径） | PLANNED（Phase4+） | 01 §121 先 Profiler 后优化 |
| GATE20 | Full Regression | verify_all --tier release 本身 | ACTIVE（=全量编排） | 修复缺陷沉淀回归用例（T-R13） |

**第二段：01 §127 追加（LN-G21~G32）**

| LN | 逻辑名（01 §127 原文） | 实现载体 | 点亮 Phase | 级别 |
|---|---|---|---|---|
| GATE21 | GDScript Type Policy | arch_lint --rules type | Phase1 | E3 |
| GATE22 | Forbidden API | arch_lint --rules api | **ACTIVE**（C2① 升版 2026-09-06） | E3/E4 | 01 §93 完整矩阵（scan_kernel93：kernel 面绝对禁令+core 面基线 64 条禁新增）+ 0-E.3 Adapter 白名单豁免（adapter/ 或 *_adapter.gd 逐项登记） |
| GATE23 | Changed File Scope | changed_file_scope_validator | 多 AI 阶段 | E4 |
| GATE24 | Contract Drift | contract_drift_validator + 契约测试（吸收 LN-G10/11） | Phase1 | E2/E3 |
| GATE25 | State Ownership | state_owner_validator | **ACTIVE**（2026-09-06 B1 收口） | E3 | 载体=arch_validators 双模式：写入口基线禁新增（gate25_owner_writers，18 文件 43 入口）+ 跨模块直写扫描（gate41_cross_module_writes 基线 1 条）；REPORT 观察保留（T-4 多写者阈值继续） |
| GATE26 | Transaction Atomicity | transaction_test（11 场景） | **ACTIVE**（2026-09-06 B3 点亮） | E2 | 载体=tests/unit/test_transaction_runtime.gd 13 项 + test_shop_trade_tx.gd 10 项（01 §118 十一路+嵌套拒绝+Journal 审计+0-C.19 Golden 不变式），进 GATE2 run_all 必过清单（73 套件）；点亮方式=经 GATE2 承载（verify_all 无独立物理槽，GATE2 全绿即本 Gate 绿） |
| GATE27 | Rollback Recovery | transaction_test | **ACTIVE**（2026-09-06 B3 点亮） | E2 | 同 GATE26 载体；逆序恢复/RECOVERY_REQUIRED 五元组/COMMITTED 终态拒绝已覆盖（2026-09-06 架构窗） |
| GATE28 | Command Ordering | command_ordering_test | Phase2 | E2 |
| GATE29 | Vertical Slice | vs_replay 套件 | Phase2 | E2 |
| GATE30 | Context Integrity & Freshness（原 Context Freshness，V1.4 扩义改名） | context_pack_validator | **ACTIVE**（C2② 物理化 2026-09-06，物理槽 GATE42） | E3 | 宪法 0-G.5 六字段+0-G.6 Freeze 一致性（STALE 红）+01 §127 GATE21~32 硬性验收对账，进 verify_all 十五槽 |
| GATE31 | Permission Evidence | write_lease_validator | 多 AI 阶段 | E4 |
| GATE32 | Foundation Freeze Consistency | freeze_manifest_validator | Phase1 | E3 |

**第三段：存量物理槽位（不在 LN 域，禁文档裸引）**

| 物理 | 职责 | LN 映射 |
|---|---|---|
| GATE0a/b/c | mouse_filter / 信号基线 / ambiguous 警告 | 工具链守卫（LN 无对应，保留） |
| GATE0d | arch_lint 暂存快扫（观察期非阻断） | LN-G04/12/15 的增量执行点 |
| 物理 GATE4 | 战斗预设红线 | LN-G06 内容面 |
| 物理 GATE5 | town_npcs.json 双写防线 | LN-G05 内容面 |
| 物理 GATE8 | 工程结构兜底 | LN-G05 内容面 |
| 物理 GATE9 | JS 语法门禁 | 工具链守卫（LN 无对应，保留） |
| GATE40+ | 未来新槽位（GATE03/04/05/08/09/13 等的落点） | 见第一段状态列 |

**状态规则**：ACTIVE=已实现且进必过清单；PARTIAL=有载体待补全（补全项进对应 Phase）；PLANNED=未点亮，**点亮前禁止进必过清单**（防「纸面门禁」）；状态迁移必须同步本表 + PROJECT_STATUS + verify_all（01 §127 条款）。

> **V1.4 修复版**：随 01 图 §127 直修，GATE21~32 由「01 §127 追加」升格为**硬性验收 Gate**（与 GATE01~20 同级入档，同表同纪律；arch_linter 组承载=物理槽 GATE41，禁裸引物理号纪律不变）。GATE30 同步扩义为 Context Integrity & Freshness（见上表），物理化时点随 ACR 裁决；未点亮者仍受上段「纸面门禁」防线约束。

---

## 3. Unit Test 基础（冻结项 1/5）

### 3.1 不动摇的部分

- `run_all.tscn` 双闸门入口；`TestBase` 反射执行 `test_*`；失败不中断、汇总暴露；退出码 0/1。
- 73 个存量测试**原地保留**。目录重排属 Phase4 逐模块顺带动作，禁止一次性大 move。

### 3.2 升级契约 U-1~U-7

| # | 冻结内容 |
|---|---|
| U-1 | **目标目录分层**（只约束新增）：`tests/unit/kernel/`（Kernel 契约域）· `tests/contract/` · `tests/integration/` · `tests/arch/`（linter 的 GDScript 侧自检）· `tests/doubles/`（见 §6）· `tests/ui/`（存续） |
| U-2 | **TestBase 扩展**（只增不改旧签名）：`expect_float(actual, expected, eps, msg)` · `expect_str(actual, expected, msg)` · `skip(reason)`（计入 skipped，不计失败）· `set_seed(seed)`（注入确定性随机） |
| U-3 | **Fixture**：`before_each/after_each` 存续；新增 `before_all/after_all`；**禁测试间共享可变成员**（每用例重新 `new`） |
| U-4 | **命名法**：`test_<被测行为>_<条件>_<预期>`，如 `test_rollback_middle_mutation_restores_state` |
| U-5 | **单测禁区**：禁 `load` 场景、禁访问磁盘真实存档路径、禁 `await` 真实计时（用 FakeClock）、禁全局随机（用 set_seed） |
| U-6 | **套件元数据**：每个 `test_*.gd` 头部注释登记 `# @module: <模块>  @layer: unit|contract|integration  @owner: <owner>`，runner 汇总输出分层统计与 blast radius 报告 |
| U-7 | **分层运行**：run_all 支持 `--tier=unit|contract|integration|all`（`OS.get_cmdline_user_args`），verify_all 按层调用 |
| U-8 | **回归沉淀（宪法 §87）**：每个已修复的 P0/P1 缺陷必须沉淀为 `test_regression_<BUG号>` 永久用例进 Regression Suite；**测试修复后禁止删除**（宪法 §4017 行「测试不能删除」）；「代码失败→改测试→PASS」除非需求正式改变 + 测试确已过时 + ADR 明确允许，否则一律禁止（宪法 §90） |

---

## 4. Contract Test 基础（冻结项 2/5）

目标（01 §117）：公共契约变更未经批准 → 测试红 → 禁止合并。

| # | 冻结内容 |
|---|---|
| C-1 | **Contract Registry**：`docs/contracts/contract_registry.json`（机器可读），登记六类契约——signals / commands / queries / **repositories** / errors / schemas（宪法 §84 要求四类公共契约全部有 Contract Test）；每条含 `owner、签名、版本、冻结状态`。**初版由工具从 `EventBus.gd` 现有 84 信号一次性生成**（生成器入 tools/，禁止手抄漂移） |
| C-2 | **事件 golden payload**：每条公共事件一份快照（字段名/类型/必填性）。结构未批变更 → 契约测试红 |
| C-3 | **跨模块契约测试**落 `tests/contract/`，命名 `contract_<producer>_to_<consumer>.gd` |
| C-4 | **漂移双通道**：测试通道（E2，跑 golden 快照）+ 静态通道（E3，contract_drift_validator 扫 `class_name`/方法签名/信号参数 vs registry）——即 GATE24 的两个面 |
| C-5 | **Save Schema 契约**：现 `test_save_roundtrip.gd` 升级为对 SaveHeader 五字段（03 §5：save_version/game_version/content_version/timestamp/checksum）断言；迁移链归 LN-GATE09 |
| C-6 | `test_eventbus.gd` 不删，**改造为 registry 驱动**（从硬编码断言改为读 registry 生成用例） |

---

## 5. Architecture Linter（冻结项 3/5）

### 5.1 工具形态

`tools/arch_lint.py` —— 单入口多规则，与现有 `lint_mouse_filter.py`/`audit_signal_contract.py` 同栈（Python）。

```
用法：python tools/arch_lint.py --rules type,api --files <...> \
      --baseline tools/arch_baseline.json --report-json build/arch_report.json
退出码：0 过 / 1 拦 / 2 配置错
```

- 支持全仓与暂存文件两种模式（暂存模式供 GATE0d 快扫）。
- 输出：stdout 人类可读 + `--report-json`（供 verify_all 汇总与 PROJECT STATUS）。

### 5.2 七校验器 → 规则面（01 §92 全覆盖）

| 校验器（01 §92 原名） | 规则面 | 对应 Gate |
|---|---|---|
| `dependency_validator` | 层方向矩阵：Kernel 依赖 0 层；Domain→Presentation/Execution BLOCK；**Presentation→Domain 直接状态修改 BLOCK**（01 §119）；跨模块内部符号引用 BLOCK（含宪法 §83 的 NPC→Marriage 实现等跨模块实现泄漏）；环检测 | GATE04/22 |
| `forbidden_api_validator` | 模块×API 矩阵（01 §93）：Kernel 禁 `Node/SceneTree/get_tree/get_node/FileAccess/DirAccess/JSON/ResourceLoader/ProjectSettings/randf/randi/RandomNumberGenerator/Time.*/OS.get_datetime`；Domain 分阶段禁（Phase5 起 JSON 全禁） | GATE22 |
| `module_scope_validator` | Test Double 只准住 `tests/doubles/`；生产代码禁 import `tests/`；模块私有目录禁外引 | GATE21 |
| `changed_file_scope_validator` | git diff vs 任务卡 allowed_files（依赖 Write Lease 元数据，多 AI 阶段启用） | GATE23 |
| `contract_drift_validator` | registry vs 代码（§4 C-4） | GATE24 |
| `state_owner_validator` | 公共 setter 扫描 + 写入口基线禁新增（B1）；多写者启发式阈值待 §11 T-4（REPORT 保留） | GATE25 |
| `naming_validator` | Event 过去时（K-R12）；ID 正则（03 §3 冻结正则）；错误判断禁比 message 字符串（K-R11） | GATE21/24 |

### 5.3 基线模式（沿用 audit_signal_baseline 成熟范式）

- `tools/arch_baseline.json`：只拦**新增**违规，存量进基线；
- 更新基线必须随 ADR（T-R12，机器检查 diff）；
- REPORT 模式（`--report`）：只记录不拦截，产出 Phase0 测量基线（ACR-0001 要求）。

### 5.4 执行点

| 点 | 门禁 | 模式 |
|---|---|---|
| pre-commit | GATE0d | 暂存文件快扫，观察期非阻断 → 稳定后转阻断 |
| verify_all full | GATE21/22/24/25 | 全仓扫描 |

---

## 6. Deterministic Test Double（冻结项 4/5）

### 6.1 三原则

1. Test Double 一律 `RefCounted`、一律住 `tests/doubles/`、生产代码零引用；
2. 禁 mock 框架、禁反射魔法——每个 double 手写、见名知意；
3. 注入走构造函数；禁止测试改生产单例状态。

### 6.2 六件套（名单与契约冻结）

| Double | 替代对象（02 契约） | 用途 |
|---|---|---|
| `FakeClock` | `GameClock @abstract` | 手动 `advance_ticks()/advance_days()`；覆盖 weather_time / schedule / 休息推进天数 |
| `SeededRandomProvider` | `RandomProvider @abstract` | 包装 `SeededRNG`（同步升级其为实现 02 契约的生产类），固定 seed 断言随机序列 |
| `RecordingEventBus` | EventBus（测试替身，非替换全局） | 记录 PENDING→COMMITTED 事件序列，供命令序/事务断言 |
| `InMemory<Xxx>Repository` | 各模块 Repository 契约 | 按 02 契约**逐模块手写**（禁泛型），仅测试目录 |
| `FakePersistence` | SaveResult 注入点 | 模拟第 N 次 save 失败 → 覆盖 01 §118 的 Save Failure / Post-Commit Failure |
| `FailureInjector` | MutationRecord.undo | 让第 k 条 undo 抛错 → 覆盖 Rollback Failure → `RECOVERY_REQUIRED`（K-R15） |

### 6.3 确定性回放（01 §120）

- 载体 = **MutationJournal + command sequence 快照**；`Record → Replay → Compare` 结果必须一致；
- `replay_runner.gd` 随 Phase2 事务落地同步提供；
- 必须支持回放的关键系统（01 原文）：Combat / AI / Random Event / Loot / World Simulation。

---

## 7. CI / verify_all 骨架（冻结项 5/5）

### 7.1 verify_all V2（9 门禁语义不变，壳升级）

| # | 冻结内容 |
|---|---|
| V-1 | **Gate 注册表化**：GATES dict → 结构化注册表 `{id, name, fn, tier, blocking, phase}`；CLI 支持 `--tier quick|full|release` · `--only GATE2,GATE6` · `--skip` · `--report-json build/verify_report.json` |
| V-2 | **REPORT 模式**（ACR-0001 Phase0）：`--report` 全门禁只记录不拦截，产出现状违规基线数字，作为绞杀者迁移的测量起点 |
| V-3 | **工件**：`build/verify_report.json` + 各 gate 日志落 `build/`（gitignore），供 PROJECT STATUS 与多 AI 传递板引用 |
| V-4 | **双闸门口径不变**：GATE1 零 SCRIPT/PARSE/COMPILE 硬错误；GATE2 零 ✗ 且失败 M=0 |
| V-5 | **接入顺序 = §2.2 点亮列**：PLANNED 门禁未点亮前不出现在必过清单 |

### 7.2 hook 编排

- pre-commit：GATE0a/b/c + **GATE0d**（arch_lint 暂存快扫，观察期非阻断）；
- pre-push：`verify_all --tier full`（push 前全量，本地即 CI）。

### 7.3 门禁必过清单（release tier）

`存量物理 GATE1~9 全绿` + `已点亮 LN 门禁（GATE01~32 中状态=ACTIVE/PARTIAL 已补全者）全绿` + `GATE0a/b/d 零拦截`。判绿口径**只加不减**（T-R11）；「我已经检查过了」不等于 PASS（宪法 §89），一切以 verify_all 退出码为准。

### 7.4 托管形态

本地 CI 优先（单机 + 多 AI 并行场景，verify_all 退出码已 CI-ready）。GitHub Actions yml 为**可选项**（§11 T-3），非冻结物。

---

## 8. Enforcement 矩阵 T-R01~T-R13

| 规则 | 内容 | 严重度 | E 级 | 扫描器/测试 | Gate |
|---|---|---|---|---|---|
| T-R01 | 单测必须继承 TestBase，禁自造 runner | ERROR | E3 | arch_lint --rules test_shape（**已物理化**——2026-09-06 升表口批：arch_validators `scan_test_shape` 上线（GATE41 槽承载，原登记 GATE21 属 LN 命名空间），扫描 tests/ 递归全部 test_*.gd 必须 `extends TestBase`；84 套件全量合规零基线 ACTIVE，命中即红；生成器/运行器天然不在扫描面） | GATE41 |
| T-R02 | `test_*` 命名法（U-4） | ERROR | E3 | naming_validator（**已物理化**——2026-09-06 B 批复查更正 A3 误判：arch_validators `scan_test_naming` 即本规则载体，GATE41 槽执行；A3 首查 grep 模式未命中致误报未物理化） | GATE41 |
| T-R03 | 单测禁真实磁盘/真实时钟/全局随机（宪法 §82） | FATAL | E3 | forbidden_api_validator | GATE22 |
| T-R04 | Test Double 只准住 `tests/doubles/` | FATAL | E3 | module_scope_validator | GATE21 |
| T-R05 | 生产代码禁引用 `tests/` | FATAL | E3/E4 | dependency_validator | GATE22 |
| T-R06 | 公共 Command/Query/Event/Repository 变更必过契约测试（宪法 §84） | FATAL | E2 | contract_test | GATE24 |
| T-R07 | registry 与代码漂移 = BLOCK（宪法 §94 同义） | FATAL | E3 | contract_drift_validator | GATE24 |
| T-R08 | 事务 11 场景（01 §118）缺一即红（Phase2 起） | FATAL | E2 | transaction_test | GATE26/27 |
| T-R09 | 回放结果不一致 = BLOCK | FATAL | E2 | replay_test | GATE29 |
| T-R10 | 新门禁必须登记 Gate Registry + PROJECT STATUS + verify_all（01 §127 条款） | ERROR | E3 | freeze_manifest_validator | GATE32 |
| T-R11 | verify_all 判绿口径只许加严，禁放宽 | FATAL | E4 | diff 门禁脚本 + 评审 | GATE01 |
| T-R12 | 基线文件（arch_baseline 等）变更必须随 ADR | FATAL | E4 | pre-commit diff 检查 | GATE0b 同款 |
| T-R13 | P0/P1 修复必须沉淀 `test_regression_<BUG号>`，测试禁止删除（宪法 §87/§90） | FATAL | E2/E3 | regression 缺口扫描 + 评审 | GATE02/GATE20 |

**E0（纯文档约束）计数 = 0** —— 每条规则都有扫描器或测试兜底，无「纸面规则」。Gate 列一律 LN 编号（§2.1 政策）。

---

## 9. Freeze 清单（`TEST-INFRA v1.2.0`）

冻结即意味：任何变更必须走 ADR。

| 冻结物 | 内容 |
|---|---|
| 双命名空间政策 | §2.1（LN=宪法 §88 ∪ 01 §127；物理槽位冻结 1~9 + GATE40+ 新槽；文档禁裸引物理号） |
| Gate Registry | §2.2 全表（LN01~32 / 载体 / 状态 / Phase / 级别 / 映射） |
| TestBase API 面 | 现有 `expect/expect_eq/run/before_each/after_each` + 新增 `expect_float/expect_str/skip/set_seed/before_all/after_all` 签名 |
| 目录契约 | U-1 六目录（新增约束） |
| arch_lint 规则面 | §5.2 七校验器规则面 + CLI 形态（§5.1） |
| Test Double 名单 | §6.2 六件套及其替代的 02 契约 |
| verify_all V2 CLI 面 | §7.1 V-1~V-5 |
| T-R01~T-R13 | §8 全矩阵 |
| 编号对齐 | 03 表 C-R04/05→GATE06、C-R06/07/08→GATE07（LN 化修正），02 核对无需改 |

---

## 10. 完成定义（DoD，7 条）

1. `run_all --tier=unit|contract|integration|all` 四层跑通，双闸门口径不变；
2. `arch_lint.py` REPORT 模式全量跑通并产出 `arch_baseline.json`（Phase0 测量起点）；
3. `contract_registry.json` 由生成器从 `EventBus.gd` 产出（84 信号零遗漏，六类契约齐全）；
4. Test Double 六件套骨架落 `tests/doubles/`，生产代码零引用（T-R05 扫描通过）；
5. `verify_all` V2 注册表化，`--report-json` 工件可产出；
6. LN↔物理映射零冲突：02/03/04 三图 Gate 引用互查全部落在 LN 域（§2.1），无 GATE33~36 之类的域外编号；
7. **全部为骨架与契约，未动任何生产源码。**

---

## 11. 开放问题（必须 ADR 裁决，AI 不得自决）

> **【已追认 2026-09-06】** 用户整批复核：**T-1 双命名空间政策获追认**——LN（宪法 §88 ∪ 01 §127）为唯一文档编号、物理槽位冻结 1~9 + GATE40+ 新槽；T-2~T-4 按倾向执行。本表保留原文供审计。

| # | 问题 | 倾向 |
|---|---|---|
| T-1 | **双命名空间政策追认**：LN（宪法 §88 ∪ 01 §127）为唯一文档编号、物理槽位冻结 1~9 + GATE40+ 新槽 | 按本图执行（这是宪法 §88 + 01 §127 + §171 唯一自洽的读法；物理重编号=高扰动零收益，另起 GATE33~36=与宪法 §88 重复建设） |
| T-2 | EventBus 84 信号导入 registry 的初版权威来源：工具生成后是否需人工逐条复审 | 工具生成 + Owner AI 抽审（全手审 84 条易漂移） |
| T-3 | GitHub Actions 引入时机 | 暂缓；本地 verify_all --tier full 已覆盖，纯可选项 |
| T-4 | state_owner_validator「多写者」启发式阈值（误报治理） | 先 REPORT 模式观察两周真实噪音率再定 |

---

## 12. 04 的一句话总纲

**门禁不是文档里的一句话，而是一台机器：编号冻结、规则可扫、双替可控、判绿口径只加不减。**

---

## 关联文档

- `PROJECT_CONSTITUTION_V1.4.md`（§92 校验器 / §93 Forbidden API / §115~120 测试架构 / §127 Gate 基线 / §171 升级不丢弃；V1.2→V1.4 条款号零漂移，正文「宪法 §N」引用全部有效）
- `01_总体架构施工图_V1.4修复版.md`（§92/93/94/95/96/115~120/127/129；§127 GATE21~32 硬性验收直修）
- `02_Domain_Kernel施工图_V1.4修复版.md`（K-R01~R18 · GameClock/RandomProvider/Repository/MutationRecord 契约）
- `03_Contract_Schema_DataContract施工图_V1.4修复版.md`（C-R01~C-R18 · SaveHeader · ID 正则）
- `ACR-0001_采纳V1.2宪法与目标架构迁移.md`（Phase0 REPORT 测量要求）
