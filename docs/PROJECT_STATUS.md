# PROJECT_STATUS —— Gate 点亮状态单一真源

- 建立：2026-09-06（B 批：04 图状态迁移纪律「同步本表 + PROJECT_STATUS + verify_all」的 PROJECT_STATUS 载体此前缺失，补建）
- 定义源：04 图 V1.4 修复版 §2 Gate Registry（状态语义：ACTIVE=已实现且进必过清单 / PARTIAL=有载体待补全 / PLANNED=未点亮，点亮前禁止进必过清单）
- 同步纪律：任何 Gate 状态迁移必须三同步（04 图本表 + 本文件 + verify_all 口径）

## 物理槽（verify_all 默认 tier）

| 槽 | 状态 | 说明 |
|---|---|---|
| GATE1 quit_check | ACTIVE | 含自愈缓存重建 |
| GATE2 unit tests | ACTIVE | 73 套件（tests/unit + tests/integration）零 ✗ 零 M，flaky 防抖 D-07 |
| GATE3 内容红线 | ACTIVE | JSON 铁律/硬编码路径扫描（基线模式） |
| GATE4 战斗预设红线 | ACTIVE | |
| GATE5 双写防线 | ACTIVE | |
| GATE6 五检 | ACTIVE | ref_index/id_validator/schema_guard/pack_manifest/region 三同 |
| GATE7 Studio Smoke | ACTIVE | 编辑闭环冒烟 |
| GATE8 结构完整性 | ACTIVE | |
| GATE9 JS 语法 | ACTIVE | |
| GATE17 Asset Contract | ACTIVE | check_assets_contract.py --strict（05 图批1 挂槽） |
| GATE21 Type Policy | ACTIVE | 0-B.12 禁裸信号载荷，存量退役禁新增 |
| GATE22 Forbidden API | ACTIVE | core 禁 IO/JSON/随机；存量 3 条基线 |
| GATE32 Foundation Freeze | ACTIVE | EventBus 86 信号基线 + save_body_registry 登记制 |
| GATE41 架构校验器组 | ACTIVE | dependency 禁引矩阵+环 / module_scope / test_naming / state_owner（B 批收口，见下） |
| GATE42 Context Pack | ACTIVE | GATE30（LN）物理槽：0-G.5 六字段+0-G.6 STALE 红线+01§127 对账（C2②） |
| GATE40 性能基准 | ACTIVE | --tier performance（17 图 SBP-6） |

## 逻辑槽（LN，宪法 §88 ∪ 01 §127）——关键状态

| LN | 状态 | 说明 |
|---|---|---|
| GATE25 State Ownership | ACTIVE（B1 收口） | state_owner 基线禁新增（tools/arch_linter_baseline.json gate25_owner_writers）+ REPORT 观察保留；T-4 多写者阈值继续观察 |
| GATE26 Transaction Atomicity | ACTIVE（B3 点亮） | 载体=test_transaction_runtime 13 项+test_shop_trade_tx 10 项，经 GATE2 必过 |
| GATE27 Rollback Recovery | ACTIVE（B3 点亮） | 同 GATE26 载体 |
| GATE28 Command Ordering | ACTIVE（B4 点亮） | test_command_ordering（K-R16：排序只依赖 sequence）经 GATE2 必过 |
| GATE03 Integration | ACTIVE（A1 实体化） | tests/integration 3 用例入 GATE2 扫描 |
| GATE23 Changed File Scope | PLANNED | 多 AI 阶段，依赖 Write Lease 元数据 |
| GATE24 Contract Drift | PARTIAL | pre-commit 0b 信号审计 + GATE32 基线镜像承载；独立 contract_drift_validator 待建 |
| GATE30 Context Integrity & Freshness | ACTIVE（C2② 物理化） | context_pack_validator 进 GATE42，STALE 即红；STALE 期间禁 Foundation 修改（0-G.6） |
| GATE11 API Contract | PARTIAL | eventbus_signal_registry.json 初版 + GATE32 镜像；Owner 抽审待做 |

## 未点亮清单（防纸面门禁）

GATE08/09（语义复用 GATE2 存档套件）/ GATE13 God Object（state_owner 前身观察）/ GATE18 Localization / GATE19（=GATE40 已覆盖）——状态细节以 04 图 §2 表为准。

## C 组基础设施（2026-09-06）

- **Write Lease**：tools/write_lease.py（宪法 0-G.8 载体）——FROZEN_SCOPE（core/kernel/、core/execution/、EventBus.gd、arch_linter_baseline.json）无租约禁止动；claim/check/release/list；4h 过期。多窗口施工前必须 claim（B 批撞车实录的根治件）。
- **GATE22 §93 完整矩阵**：kernel 面绝对禁令（零基线）+core 面基线 64 条禁新增；0-E.3 Adapter 豁免（adapter/ 或 *_adapter.gd）。
- **ADR-0007**：APPROVED（2026-09-06 用户批准）。**批A 已落地**：application/application_root.gd（Create/Inject 段+装配完整性自检）+ GameManager.USE_APPLICATION_ROOT 开关（默认 false 旧路径）+ _adopt_from 引用转发（调用方/测试零改动）+ 4 用例；双开关各 77 套件全绿等价验证。批B（shop/quest/inventory 迁移+Register 段移交）随下一批次。
