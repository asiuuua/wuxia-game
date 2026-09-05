# 13 Save / Persistence / Migration 施工图 V1.2

| 项 | 内容 |
|---|---|
| 状态 | **FROZEN CANDIDATE**（用户批准后升 FROZEN；批准前不写实现代码，01 §104） |
| 上游 | 宪法 V1.2（**§31 Save架构** / **§32 Save Migration原则** / §30 反循环引用·巨大存档 / L6084 施工图必答「存档怎么挂」/ L6414 存档损坏事故不可取消审计回滚 / L2034-2065 State Owner 表 / §23A ADR-0005 Save与RuntimeState分离）→ 01（**§70 Save Architecture** / **§71 Save Migration** / §72 Event Log / §78 Definition·Runtime·Save·Capability 边界）→ 02（Transaction·Journal）→ 03（**§7 S-1~S-6 序列化契约**）→ 04（golden / 双替）→ 05（**VE-1/VE-2 content_fingerprint 进 SaveHeader** / CO-R09 / C-4 已裁）→ 06（SaveDTO 三切片·恢复顺序）→ 07（SR-1~3 / W-R12 GATE29 回放）→ 09（EA-1/2 装备实例入档 / ID-2 分配器水位）→ 12（QD-1 Branch 存档升级 / QD-6 死命令防线） |
| 范围 | 冻结 7 件：SaveHeader 五字段 / SaveDTO 模块自版本 / 迁移链显式注册表 / 注册与加载契约 / 原子写冻结升级 / user:// 持久化域划分 / 读档分相 |
| 编号命名空间 | 本图冻结契约与开放问题用 **SV-**；实锤缺陷 **P-S1~P-S12**；Enforcement **SV-R01~R12**。**撞号声明**：06 图 Save 小节局部编号 SV-1~SV-4 自本图起由本图接管，映射：06 SV-1 三切片→本图 SV-2、06 SV-2 迁移内聚→本图 SV-3、06 SV-3 恢复顺序→本图 SV-4/SV-7、06 SV-4 可回放→本图开放 SV-1（07 SR-2 承接）。07 图局部 SR-1~3 不受影响。 |

---

## 1. 定位

存档是**状态的切片，不是状态的容器**。本图把「存了能读回来、写坏了能救回来、换了版本能迁移」三条底线钉成契约。好消息：**原子写五步 + .bak 抢救 + 版本迁移骨架 + 全域 roundtrip 测试**已经是全项目工程化质量最高的地基之一（安卓写入中断事故教育出来的真资产）；坏消息是：**补丁迁移接线是死的、key 撞车静默覆盖数据、未知版本反而放行、加载顺序靠注释**——四颗雷都在「玩家最不可承受的存档路径」上。本图把好资产收编升级，把四颗雷逐个拆除。

---

## 2. 现状盘点（全部机器扫描所得，2026-09-05）

### 2.1 已有资产（§171 收编升级，不丢弃）

| # | 资产 | 证据 | 处置 |
|---|---|---|---|
| 1 | **原子写五步**：.tmp → 回读校验 → .bak 备份 → rename 替换 → 失败自动恢复 | SaveManager.gd L288-322 | 冻结（SV-5）+ 回读升级 checksum |
| 2 | **版本迁移骨架**：save_version 独立于游戏版本 / 未来版本拒读 / 无版本遗留档兼容 | SaveManager.gd L224-261 + test_save_migration 6 用例 | 冻结（SV-3）+ 补齐四缺口 |
| 3 | **inventory 双格式兼容**：{idx,data} 新格式保真槽位 + 旧裸格式回退 + idx 越界兜底塞空位 + 负重按当前配置重算 + count 索引重建 | inventory_service.gd L651-696 | 冻结为兼容范式标杆 |
| 4 | **GameState last_region_id 非法回退**：读档校验区域注册表，非法回退 newbie_village | game_state.gd L138-141 + test L37-42 | 冻结为「外键回退」范式 |
| 5 | **ISaveable 注册制统一序列化**：11 域入档 + 3 域显式声明不入档（shop/forge/alchemy 注释自认纯配置无状态） | GameManager.gd L260-273 | 冻结（SV-4）+ 强类型化 |
| 6 | **save() duplicate 快照纪律**：bond/sect 注释自记「快照被 reset 清空」事故教训 | bond_service L259 / sect_service L17 | 冻结为 save() 编写规范 |
| 7 | **roundtrip 测试网**：test_save_roundtrip 7 用例（占槽 6+auto_1 前后快照还原，不碰真实存档）+ 各域散布 roundtrip 13 处 | tests/unit/ | 冻结并参数化扩全（SV-R08） |

### 2.2 实锤缺陷（P-S1~P-S12，全部扫描所得）

- **P-S1【P0·死接线】** `patch_manager.gd` L52 `SaveManager.has_method("register_migration")` 探测一个**根本不存在的方法**（SaveManager 只有 register_saveable 与私有 _migrations）→ 补丁 manifest 的 `save_migration` 字段配置了也**永远不生效**，补丁声明的存档迁移静默丢失。与 12 图 P-Q1（has_method 死命令）完全同族；QD-6 防线直接覆盖本例。
- **P-S2【P0·数据丢失窗口】** key 撞车**静默覆盖**：`save_to_slot`/`quick_save` 里 `save_data[key] = saveable.save()`（L162/L171）无 key 唯一性检测；`register_saveable` 只查对象重复不查 key。两个 saveable 同 key → 后写覆盖前写，**前一域数据静默丢失**——资产损失 P0 族（09 图同款事故语义）。
- **P-S3【迁移策略自相矛盾】** `_migrate_if_needed`：未来版本拒读 ✓；已知老版本走链 ✓；**未知版本「按当前版本尽力解析」并把 save_version 改写为当前版** ✗（L240-242）——与 L204 自订原则「拒绝读档（防止新版数据被旧逻辑损坏）」正好相反：**识别不了的版本反而放行还盖当前版戳**，后续写入将永久污染该档。
- **P-S4【隐式加载顺序契约】** equipment_service.load L139 注释自认「玩家状态先于本服务加载完成，此处直接重算加成」+ `GameManager.player_state` 直连——加载正确性**依赖 `_register_saveables` 的注册顺序**（L261 player 第一、L265 equipment 第五），零机器守卫；未来按字母序重构注册表 = 加成算错且无任何报错。
- **P-S5【SaveHeader 缺三字段】** meta 实际只有 `{save_version, timestamp, custom_name?}`（L335-342）——宪法 §31 / 01 §70 要求的五字段**缺 game_version、content_version、checksum** 三个；checksum 缺失 = .tmp 回读校验只验「可解析」不验「完整/未被篡改」；content_version 缺失 = 05 图 VE-2「读档重算指纹比对」无法落地。
- **P-S6【迁移链空壳】** `_migrations: Array = []` 占位（L13-15）；known 版本表手写数组（L236-237）；1.0.0→1.1.0 实际零迁移步骤，靠 GameState.load 默认值兜底（L243 注释自认）——「迁移」实质 = 版本号盖章 + 各模块默认值，**无一条 Input/Expected golden 测试对**（宪法 §32 要求每次 Migration 必须测试）。
- **P-S7【死配置 + 无轮转】** settings_manager `game.autosave=true / autosave_interval=300` 配置存在但自动存档**未接入**（SaveManager L84 注释自认「M3 自动存档系统尚未接入」）；`quick_save` 永远覆盖 auto_1.json（L163），`list_auto_saves` 的「最近 3 个」逻辑永远只有 1 个可用——restock 死字段同族。
- **P-S8【幽灵字段】** `_read_summary` L135 读 `ps.get("thumbnail_path")`，但 `player_state.save()`（L242-252）**从不写该字段** → 存档卡片缩略图路径恒空。UI 依赖一条不存在的数据（读不存在的键=幽灵字段，contract_registry 时代必须清零）。
- **P-S9【validator 名不符实】** `save_validator.gd` 名叫校验器，**不校验任何存档结构/schema**；只含一条硬编码业务修复规则（must_alive 矛盾→`fail_quest(quest_id, "FAIL_DEAD_NPC")` 字符串字面量，12 P-Q12 同族）+ `GameManager.quest_service` 直连（08 同族）。职责错位：「读档后修复器」却顶着「存档校验器」的名字。
- **P-S10【持久化 IO 三风格】** SaveManager/settings_manager/quest_track_panel/hud_draggable_panel **手写 FileAccess + `JSON.parse_string`**（解析失败静默返回 {}，连告警都没有）vs PatchManager/ConfigManager 走 JSONUtil 封装（有 push_error 但 load 仍静默 {}、save 无原子写）——持久化 IO 无唯一入口，S-3「显式检查」执行度不一。
- **P-S11【鸭子注册无守卫】** `register_saveable(saveable: Variant)` 不验证 get_save_key/save/load 三方法存在（L21 注释自认约定）——漏实现的 saveable 要到**玩家点存档那一刻**才崩，且崩在不可恢复路径。
- **P-S12【缺 key 静默跳过】** `_load_from_path` L206-209：`if data.has(key): load(...)` 否则无声跳过——新模块读老档拿零数据无任何告警，也无「期望模块清单」校验；与 P-S6 盖章式迁移叠加 = 日志显示「存档已迁移成功」但数据实际残缺。

### 2.3 user:// 持久化面全景（七面三风格）

| 面 | 路径 | 写入口 | 风格 |
|---|---|---|---|
| 游戏存档 | user://saves/*.json | SaveManager | 手写 FileAccess+parse_string（静默 {}）|
| 玩家设置 | user://settings.json | SettingsManager | 手写（同上）|
| HUD 偏好 | user://ui/hud_positions.json | quest_track_panel + hud_draggable_panel 两处各自读写 | 手写（同上）|
| 补丁历史 | user://patch_history.json | PatchManager | JSONUtil |
| 运行日志 | user://logs/game.log | GameLogger | 自有 |
| 配置错误日志 | user://config_errors.log | ConfigManager | 自有 |
| 工具校验日志 | user://project_validation.log | validate_project.gd（工具）| 自有 |

---

## 3. 冻结契约（7 件）

### SV-1 SaveHeader 五字段（宪法 §31 / 01 §70 全词落位）

- meta 冻结为五字段 + 可选扩展：`save_version` / `game_version`（ProjectSettings version）/ `content_version`（**05 VE-1 指纹**：已载 pack 排序序列 SHA-256 前 16 位 + 列表双存，读档重算比对）/ `timestamp` / `checksum`；`custom_name` 保留为 meta 扩展字段。
- **checksum = 正文（meta 之外全量）SHA-256**，写时计算、读时验证；校验失败 → 走 .bak 抢救链（SV-5），**禁静默尽力解析**。
- game_version 只记录不阻断（跨版本读档由 save_version 迁移链负责）；content_version 不匹配 → 按 05 C-4 规则警告 + 内容缺失清单，不拒读（内容缺失可降级，存档损坏不可降级——两类失败分开）。

### SV-2 SaveDTO 模块自版本（S-6 / 01 §70 / 06 SV-1 接管）

- 每模块 `save()` 返回升级为二段式 `{ "schema_version": "1.0.0", "data": {...} }`；**模块 schema_version 独立演进**，字段变更 = 模块升版 + 对应迁移步骤 + golden 对，不再牵动全局 SAVE_VERSION。
- 01 §70 十分区对现状映射冻结：player / world_time / game_state（global_flags·unit_runtime·quest_phase·difficulty·last_safe_point·last_region_id·xiaozhang_collateral）/ quest / inventory / equipment / ability / bond / romance（spouses·children·celebration_quotas）/ sworn / master 共 12 键为当前 Body 全集；**新模块入档必须先在本表登记 DataContract**（03 §契约登记），禁私自扩键。
- Runtime Object 不得直接当 Save DTO：现状「字段直拍」视为手写 DTO 合法过渡态，但必须补 schema_version 与字段清单登记；06 三切片（Player/NPC/Party）落位时按 Owner 各自 export/import，GameState 不代写（06 SV-1 原文）。

### SV-3 迁移链显式注册表（宪法 §32 / 01 §71 全词落位）

- `_migrations` 升级为显式注册表：步骤签名 `{ "from": SemVer, "to": SemVer, "step": Callable(data) -> Dictionary }`；**公开 `register_migration()` 方法**（P-S1 修复：patch_manager 接线立即生效）。
- 已知版本链由注册表**自动推导**（禁手写 known 数组）；迁移在**内存副本**上按序执行，全部通过才落盘写回（失败保原档，双读兼容期）。
- **未知版本一律拒读**（P-S3 退役宽容策略）：识别不了 = 不是我们的档，宁可拒读保数据，不可盖戳写坏。
- **每步迁移强制 Input/Expected golden 测试对**（宪法 §32 原文：每次 Migration 必须测试 Input、Expected Output）；真实历史迁移 1.0.0→1.1.0（last_region_id）补正式注册步骤或登记「默认值兜底豁免」并说明理由——禁止继续零登记。
- 任何 Save Schema 修改触发：Impact Analysis → Migration → Compatibility Test → Gate（01 §71 原文；机器化见 SV-R03）。

### SV-4 注册与加载契约（P-S2 / P-S4 / P-S11 / P-S12 收口）

- `register_saveable` 强类型收 `ISaveable`（鸭子探测退役，P-S11）；**注册期 key 唯一性 FATAL**（P-S2 收口：撞车在启动瞬间报错，不给玩家留丢数据窗口）。
- **加载依赖显式声明**：ISaveable 增 `get_load_after() -> Array[String]`（如 equipment → ["player"]），加载顺序 = 依赖拓扑排序；**禁隐式注册顺序依赖**（P-S4 收口）；无依赖者省缺。
- 读档缺 key 分级：data 缺某已注册模块的 key → WARNING（老档新模块，默认值兜底属预期）+ 期望清单由注册表自动生成核对；**禁静默**（P-S12 收口）。
- load() 内禁新增 `GameManager.` 直连（equipment 现有一处登记迁移债，随 06 读模型整改同批清）。

### SV-5 原子写冻结 + 升级（好资产收编）

- 五步原子写（.tmp → 回读 → .bak → rename → 失败恢复）**原样冻结**，安卓写入中断的救命设计，测试已守（test_atomic_write / test_corrupted_falls_back）。
- 回读校验升级：可解析 + **checksum 一致**双验（SV-1）。
- quick_save 轮转 auto_1~3（与 list_auto_saves「最近 3 个」契约对齐，P-S7 前半收口）；自动存档触发（autosave_interval）随 M3 实装，配置死字段转活。

### SV-6 user:// 持久化域划分（S-1 边界在存档侧的落点）

- 五域冻结：`saves/`（**唯一写入口 SaveManager**，其他模块禁直写）、`settings.json`（SettingsManager）、`ui/`（表现层偏好）、`logs/`、`patch_history.json`（PatchManager）。
- **新持久化文件必须先在本表登记**（架构级变更走 STOP/ACR，宪法 §74 同款精神）；禁任何代码私自 `FileAccess.open("user://新文件")`（机器化见 SV-R10）。
- 持久化 IO 统一走 JSONUtil（S-3 显式解析检查）；JSONUtil.load_json 静默 {} 语义保留但**必须 push_error 已有**；save_json 升级原子写（复用 SaveManager 五步抽出的公共 helper）；SaveManager 手写段迁 JSONUtil（P-S10 收口，随 Phase5 基础设施抽离与 S-2 清零同批）。

### SV-7 读档分相（12 QD-5 / 07 TimeConsumer 同款四相）

- load 固定四相，顺序冻结：**① 版本迁移**（内存副本，SV-3）→ **② 逐模块 load**（拓扑序，SV-4）→ **③ 派生重算**（recalculate_stats / _rebuild_count_index / _recompute 一类派生值只在第三相算，禁止混入第二相）→ **④ 校验修复**（save_validator 归位为「读档后修复器」，修复 reason 走 ErrorCode 禁字符串字面量；真正的 schema 校验在①②相由契约测试与 checksum 承担）。
- `game_loaded` 信号在四相**全部完成后**发出（现状已基本如此，冻结为契约）；业务侧禁在②相期间消费读档数据。

### SV-8 Enforcement 矩阵（SV-R01~R12，当前 E0=0）

| 规则 | 内容 | 级别 | 阶段 | 测试 | Gate(LN) |
|---|---|---|---|---|---|
| SV-R01 | SaveHeader 五字段齐备 + checksum 写读可复算 | FATAL | E2 | save_header_test | GATE08 |
| SV-R02 | 模块 DTO 带schema_version 且与 DataContract 登记表一致 | FATAL | E2 | save_dto_contract_test | GATE08 |
| SV-R03 | 每条迁移步骤必带 Input/Expected golden 对；未登记的 Schema 变更拦截 | FATAL | E2 | migration_golden_test | GATE08 |
| SV-R04 | 未知版本拒读；未来版本拒读 | FATAL | E2 | test_save_migration 扩 | GATE08 |
| SV-R05 | 注册 key 唯一；key 撞车启动即 FATAL | FATAL | E1 | register_key_test | GATE02 |
| SV-R06 | has_method 探测型静默失败禁用（扫描器，与 QD-R09 同款共用） | FATAL | E1 | arch_lint.py | GATE06 |
| SV-R07 | load 依赖拓扑显式（get_load_after）；load 路径禁新增 GameManager 直连 | FATAL | E1 | arch_lint.py | GATE06 |
| SV-R08 | 全部注册 saveable 参数化 roundtrip 覆盖（12 键全绿） | FATAL | E2 | roundtrip_matrix_test | GATE02 |
| SV-R09 | 原子写五步 + checksum 回归（.bak 抢救双路径） | FATAL | E2 | test_save_roundtrip 扩 | GATE02 |
| SV-R10 | user:// 新增持久化文件未登记 = 违例（扫描 FileAccess 常量串） | FATAL | E1 | arch_lint.py | GATE06 |
| SV-R11 | 持久化 IO 统一 JSONUtil + S-3 显式检查 | WARN→FATAL | E2 | arch_lint.py | GATE06 |
| SV-R12 | 读档缺 key 分级告警 + 期望清单自动核对 | FATAL | E2 | load_manifest_test | GATE08 |

---

## 4. 迁移映射表（绞杀者，禁一次性大改）

| 现状 | 去向 | Phase |
|---|---|---|
| meta 三缺字段（P-S5） | SV-1 五字段（读兼容缺省值渐进） | Phase1 |
| has_method("register_migration") 死接线（P-S1） | SV-3 register_migration 落地 + patch 接线直连 | Phase1（随 QD-6 防线同批） |
| 未知版本宽容盖章（P-S3） | SV-3 拒读（一版兼容期 WARN → FATAL） | Phase1 |
| key 撞车无检（P-S2） | SV-4 注册期 FATAL | Phase1 |
| _migrations 空壳 + known 手写（P-S6） | SV-3 注册表自动推导 + golden 对 | Phase2 |
| save() 直拍无模块版本（SV-2 缺口） | {schema_version, data} 包装逐模块推进 | Phase2 |
| 注册顺序隐式依赖（P-S4） | get_load_after 拓扑排序 | Phase2 |
| 缺 key 静默跳过（P-S12） | 期望清单核对 + 分级告警 | Phase2 |
| save_validator 错位（P-S9） | SV-7 第四相修复器 + reason ErrorCode | Phase2 |
| quick_save 覆盖 auto_1 + autosave 死配置（P-S7） | SV-5 轮转 + M3 自动存档实装 | Phase3 |
| thumbnail_path 幽灵字段（P-S8） | M3 自动存档实装截图，或删读取端 | Phase3 |
| 手写 IO 三风格（P-S10） | JSONUtil 统一 + 原子写 helper 抽公共 | Phase5（随 S-2 清零） |

---

## 5. Freeze 清单

| 域 | 冻结项 |
|---|---|
| Header | SV-1（五字段 / checksum / 双轨失败分级） |
| DTO | SV-2（二段式 / 12 键 Body 全集 / 新键登记制） |
| 迁移 | SV-3（注册表 / register_migration / 未知拒读 / golden 对） |
| 注册 | SV-4（强类型 / key FATAL / load_after 拓扑 / 缺 key 分级） |
| 写盘 | SV-5（五步冻结 / checksum 双验 / auto 轮转） |
| 边界 | SV-6（五域 / 新文件登记制 / JSONUtil 统一） |
| 分相 | SV-7（四相顺序 / game_loaded 时机） |

---

## 6. DoD（7 条，全绿才准进入实现收尾）

1. SaveHeader 五字段 golden（含 checksum 复算）进 GATE08 常绿（SV-R01/R02）；
2. key 撞车 / 鸭子注册 / has_method 探测三类违例扫描器 0 违例（SV-R05/R06）；
3. 迁移链注册表落成：1.0.0→1.1.0 补正式步骤或登记豁免说明，golden 对可跑（SV-R03）；
4. 12 键参数化 roundtrip 矩阵全绿（SV-R08）；
5. load_after 拓扑声明 + 乱序注入测试绿（equipment 故意后于 player 加载仍正确）（SV-R07）；
6. 旧档红线复验：1.0.0 遗留档 / 损坏档 .bak 双路径可读（SV-R04/R09）；
7. P-S1~P-S12 每项在映射表有对应收编行，旧资产升级不丢弃（§171）。

---

## 7. 开放问题（需用户 / ADR 裁决，AI 不自决）

- **SV-1 Event Log / Mutation Journal 是否入档**：01 §72 明文留白「是否成为正式持久化事实源必须由独立架构决策确定」。**推荐**：Journal 摘要（command_seq 水位 / 事务计数）进 SaveHeader 供对账，全量 Event Log 不入主档、走独立回放文件（07 SR-2 的 Record→Replay→Compare 消费），主档保持瘦身（宪法 §30 反巨大存档）。
- **SV-2 .bak 单份 vs 环形 N 份**：现状单份覆盖。**推荐**：单份 + checksum 先行；环形 3 份与 M3 自动存档同批评估（自动存档本身就是多份快照，边际收益递减）。
- **SV-3 relationship_service 十型关系边是否入档**：现注释自认「纯聚合门面：不持有任何状态、不进存档」（L3）。**推荐**：维持读模型现查不入档，与 08 RF 读模型 Query 化一致；若未来关系边出现独立运行时状态，按 SV-2 登记制走。
- **SV-4 存档体量水位与压缩/分片时机**：宪法 §30 把「巨大存档」列为反模式。**推荐**：YAGNI——当前 12 键体量小，先登记尺寸水位指标（如单档 > 5MB 触发架构评审），压缩/分片延后到指标触发，不过早设计。

---

## 8. 一句话总纲

**存档是状态的切片不是状态的容器：五字段头、每模块自版本、显式迁移链、显式加载序——换版本不换江湖，写坏必有备份，迁移必有 golden。**

---

## 9. 关联文档

- `PROJECT_CONSTITUTION_V1.2.md` §30 反巨大存档 / §31 Save架构 / §32 Save Migration / L6084「存档怎么挂」/ L6414 事故审计 / §23A ADR-0005
- `01_总体架构施工图_V1.2.md` §70 Save Architecture / §71 Save Migration / §72 Event Log / §78 四态边界
- `02_Domain_Kernel施工图_V1.2.md` Transaction·Journal（SV-1 摘要对账源）
- `03_Contract_Schema_DataContract施工图_V1.2.md` §7 S-1~S-6 / SemVer / DataContract 登记
- `04_Test_Infrastructure_Architecture_Gate施工图_V1.2.md` golden / 双替 / Gate Registry
- `05_Content_Registry_Content_Pipeline施工图_V1.2.md` VE-1/VE-2 content_fingerprint / CO-R09 / C-4
- `06_Actor_Player_NPC施工图_V1.2.md` Save 三切片（本图 SV 接管映射见 §0 命名空间声明）
- `07_World_Time_Schedule施工图_V1.2.md` SR-1~3 / W-R12 GATE29 回放
- `08_Relationship_Faction施工图_V1.2.md` 读模型 Query 化（SV-3 开放问题依据）
- `09_Item_Inventory_Equipment施工图_V1.2.md` EA-1/2 装备实例入档 / ID-2 分配器水位
- `10_Economy_Shop_Crafting施工图_V1.2.md` EC-3 restock 激活后的 Shop 入档预留
- `11_Ability_Combat_CombatAI施工图_V1.2.md` AB-6 会话四元组（不入主档、进回放）
- `12_Quest_Dialogue_Story施工图_V1.2.md` QD-1 Branch 存档升级 / QD-6 死命令防线（P-S1 同族防线）
