# ADR_INDEX —— 架构决策记录统一登记表

- 建立：2026-09-06（用户整批复核「按各图 §7 推荐追认」落地件；11 图跨图登记条目的执行）
- 规则（用户追认）：**新 ADR 编号自 0005 起顺延**；宪法 §23A 预占题保持专名引用、**不占号**（见 §3）；每条 ADR 状态 ∈ {PROPOSED / APPROVED / SUPERSEDED}；本表是编号唯一真源，正文锚定各图原文。

---

## 1. 已裁决 ADR

| # | 标题 | 裁决（原文锚点） | 状态 |
|---|---|---|---|
| ADR-0002 | **内容 ID 格式** | **基线形态 C**：现有小写下划线 ID（`npc_su_waner`）合法，零迁移、不动存档红线（03 图 §11）。**扩展二级形态（06 图 AC-1 推荐 B）**：区域前缀变体 `nv_npc_chief` / `mt_dialog_priest` 经「区域缩写白名单 + 域段固定」正则合法化（`^[a-z]{2,4}_(npc\|dlg\|...)_ [a-z0-9_]+$` 族），敌人裸名补 `enemy_` 前缀；**裸名区域升 `region_*` 前缀（16 图 CP-2）**。nv/mt 存量迁移随 Phase3~4 实施时执行，须配套存档迁移链 + Impact Analysis（01 §71；实施前按 APPROVAL 惯例报备影响面） | APPROVED（2026-09-06 用户整批追认） |
| ADR-0003 | **目录迁移时机**：`data/configs/**` → `content/definitions/**` | 延后至 **Phase 5**（先用契约约束，待 Registry 就绪一次性搬迁，避免二次返工）（03 图 §11） | APPROVED（2026-09-06） |
| ADR-0004 | **Schema 表达形式** | 保留 **GDScript `.gd` 强类型类**（编译器即校验器），另生成机器可读 Schema 摘要供工具消费（03 图 §11） | APPROVED（2026-09-06） |

> ADR-0001（采纳 V1.2 宪法与目标架构迁移）以 ACR-0001 文档承载（`ACR-0001_采纳V1.2宪法与目标架构迁移.md`，APPROVED 2026-09-06），不另占 ADR 号。

## 2. 各图开放问题整批追认（2026-09-06）

02 O-1~4 / 03 ADR-0002~0004 / 04 T-1~4 / 05 C-1~4 / 06 AC-1~4 / 07 WT-1~4 / 08 RF-1~4 / 09 IE-1~4 / 10 EC-1~4 / 11 AB-1~4 / 12 QD-1~4 / 13 SV-1~4 / 14 PV-1~4 / 15 ST-1~4 / 16 CP-1~4 / 17 SBP-1~4 / 18 RH-1~4 —— **全部按各图推荐/倾向执行**，批注已回写各图开放问题章节；原表保留供审计。其中 17 图 SBP-3/4 已按推荐实施（GATE40+）；18 图 RH-1/2/3 已执行，RH-4 按「Phase4 最小可玩闭环」推荐。

## 3. 宪法 §23A 预占题（不占号，实施期专名立项）

Repository 选型 / Combat 使用 CombatantSnapshot / Marriage·Children 结构 / Save·RuntimeState 边界 —— 实施到对应 Phase 时以专名另立 ADR（编号届时顺延），不在本表预占。

## 4. 设计决议备忘（未占 ADR 号的落定项）

- **patch manifest 与迁移 Callable 的域边界（13/18 图张力）**：manifest 为数据面，只载 `from/to` 元数据；Callable 迁移步骤居代码注册表（`SaveManager._migrations`），补丁安装时按注册表链走并对账 `save_version`。Phase1 已冻结 manifest `save_migration` 旧字符串格式拒收改 ERROR 响报（更改日志 2026-09-06）。
- **forge_iron_sword（10 图 P-E7）处置**：`forge` 前缀违 03 白名单正则 + `material_iron_001` 悬空（materials.json 无定义，配方恒 `can_forge=false`，测试已锚定该行为）。按 10 图 EC-R07 既定路线 **Phase4 随 GATE07 基线统一迁移 `recipe_` 域**；迁移时同步：①清存量引用后再登记 `_retired_ids.json`（CP-R02 无基线豁免，存量未清即登记 = GATE6 即时红）；②随 Recipe schema 统一决定补铁料定义或改配方产出。基线冻结制下现状维持，不提前改内容。
- **GATE2 flaky 防抖（04 图 D-07）**：首跑红自动复跑一次，FLAKY-RECOVERED 判绿留痕（6a45c99 已落地）。

## 5. 关联

- 各图开放问题原文：`02~18_*施工图_V1.2.md` 对应章节
- 宪法 §23A / APPROVAL_2026-09-06 / ACR-0001
