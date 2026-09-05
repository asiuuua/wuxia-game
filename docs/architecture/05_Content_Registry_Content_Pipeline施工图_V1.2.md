# 05 Content Registry / Content Pipeline 施工图 V1.2

| 项 | 值 |
|---|---|
| 状态 | **FROZEN**（2026-09-06 用户批准；可依此实施） |
| 日期 | 2026-09-05 |
| 上游 | 宪法 V1.2 → 01 §44~47（Content ID / Registry / Index / Binding）·§98（Content Schema 属 Shared Foundation）·§104（CONTRACT BEFORE IMPLEMENTATION）→ 03 §6（Content Pack Contract 已冻结布局与 manifest，本图不重复冻结）→ 04（Gate Registry / arch_lint / LN 编号） |
| 范围 | 用户指定冻结 8 件：Registry / Loader / Cache / Index / Validation / Package / Version / **DLC / Mod 基础** |
| 冻结物 | `CONTENT-RUNTIME v1.2.0`（见 §12） |

---

## 0. 定位

03 冻结了内容的「形」（数据长什么样、Pack 布局、ID 规则）；本图冻结内容的「机」（运行时如何装、存、查、验、卸、扩展）。核心问题一句话：**把 `ConfigManager` 这个兼职 Registry 的 Autoload God-Service，演进为职责单一的 ContentRegistry 机器，且 73 个存量测试一条不破。**

**铁律**：施工范围未批前只产文档不动代码（§104）。

---

## 1. 现状盘点（机器扫描证据，2026-09-05 实测）

### 1.1 已有资产（第 171 节：升级不丢弃）

| 资产 | 实测 | 处置 |
|---|---|---|
| ConfigManager | Autoload Node；路径常量集中管理（17 组 `*_FILES`）；17 个 `_load_*` 函数；按类型 Dictionary 存取；`_record_error` 收集加载错误；**对话分片懒加载已带 LRU 雏形**（`_dialog_cache` + `_dialog_pinned` pin 计数 + `DIALOG_CACHE_MAX=256` + `TTL 2000ms`） | 逐类型迁入 Registry，壳保留为 facade（§2 CT-4） |
| 对话分片体系 | `_index.json`（v1.0）登记 **13 个 shards**（file/npc_id/chapter） | 收编为 Registry 内建索引 |
| 区域分片体系 | `_map_index.json`（**v2.0.0**，10 regions，`region_id`+`scene_path`+`connections`+`index_file`）；`newbie_village/` 已是**迷你 Pack**（index.json + npcs 13/quests 3/items 2/battles 1/enemies 2/dialogs 2 共 7 文件） | 收编为 RegionPack 形态 |
| 本地化 | `localization/strings.csv` → zh_CN/zh_TW/en 三个 `.translation` | 接 LN-G18 本地化键校验 |
| 强类型 Definition | `data/schemas/` 4 类（ability/item/pill/weapon） | Registry 返回类型对象的地基 |
| 构建期校验 | GATE3（JSON 可解析/class_name）+ GATE6 ref_index（9 类实体悬空检测+基线）+ GATE8 结构兜底 | 升级为 §6 五层校验的构建期通道 |

### 1.2 缺口（本图要补）

| # | 缺口 | 证据 |
|---|---|---|
| P-1 | **Registry 单体化**：ConfigManager = Autoload Node 兼职「加载+缓存+索引+查询+动效令牌+UI 音效+状态效果」七职；无 Version 聚合、无 Dependency、无 Unload（除对话）、无 DLC/Mod 概念 | 17 个 `_load_*`；01 §45 九职责仅覆盖 2.5 个 |
| P-2 | **ID 引用不合规**：`_map_index.json` 的 connections 混用 `region_sect_gate`（合规 13 域正则）与 `misty_town`（裸名，违 03 C-R01） | 实扫 regions[0] |
| P-3 | **Definition 存资源路径**：`_map_index` 条目带 `scene_path: res://...`，违 03「资产只存 Asset ID」 | 实扫 regions[0] |
| P-4 | **无版本链**：各表 version 五种格式并存（03 P-1）；无 pack 级 content_version，SaveHeader 未含内容指纹 | 03 §5 |
| P-5 | **业务层散布 load**：services/scenes/core 共 **82 处** `load("res://...")` | grep 实扫 |
| P-6 | **本地化键未贯穿**：区域 `display_name: "起始城镇"` 硬编码中文 | 实扫 |
| P-7 | **绑定字段空置**：对话分片 `npc_id: ""` 全空 | 实扫 shards |
| P-8 | **无运行时校验管线**：GATE3/6 是构建期；运行时加载仅 `_record_error` 后继续（非 fail-fast） | ConfigManager L233-237 |

---

## 2. Registry（冻结项 1/8）

### CT-1 定位与归属

- `ContentRegistry` 是 **Application 层 RefCounted 服务**，不是 Autoload、不是 Kernel（内容属业务数据，Kernel 无内容概念；Content **Schema** 才是 Shared Foundation，01 §98）。
- 职责 = 01 §45 九词原文：**Load、Cache、Index、Version、Dependency、DLC、Mod、Validation、Unload**。九职责 ↔ API 一一映射（§2 CT-3），**不多不少**。
- 现阶段由装配层持有；Phase3（装配收敛）前临时驻 ConfigManager 现有 autoload 位（过渡态，见 CT-4 与 §14 C-1）。

### CT-2 目录契约（目标形态，随 Phase 落位）

```
application/content/          # ContentRegistry / Pack / ShardCache（RefCounted）
infrastructure/content/       # JSON 解析、文件发现、目录扫描（S-1 边界唯一持有人）
application/content/indexes/  # 12 张 ContentIndex（Build 期生成）
```

### CT-3 API 面（冻结签名，9 职责映射）

| 01 §45 职责 | 冻结 API（签名级） |
|---|---|
| Load | `load_packs() -> OperationResult`（启动期唯一入口；内部走 §3 五段顺序） |
| Cache | 内建 `ShardCache`（§4）；对外不暴露缓存对象 |
| Index | `query(index_name: StringName, key: String) -> Array[String]`（只回 **ID 数组**，禁回对象/Dictionary） |
| Version | `content_fingerprint() -> String`（§8 聚合指纹，进 SaveHeader） |
| Dependency | `resolve_order() -> Array[StringName]`（pack 拓扑序，环=FAIL） |
| DLC / Mod | `discover(dir: String) -> Array[PackManifest]`（§9，base/expansion/mod 同一机制） |
| Validation | `validate_all() -> Array[ValidationViolation]`（复用 02 的 ValidationResult 家族） |
| Unload | `unload(pack_id: StringName) -> OperationResult`（仅整 pack 粒度且零引用，CO-R12） |

### CT-4 迁移策略（绞杀者，73 测试不破）

1. Registry 先建，**类型适配器注册表**驱动：每类内容一个 `TypeAdapter`（id 字段名/Definition 类/索引需求），17 个 `_load_*` 逐类改写为 adapter 数据，**一次迁一类、GATE2 全绿再迁下一类**；
2. ConfigManager 保留全部旧 `get_*` 签名，内部委托 Registry（facade）；存量测试调用点零改动；
3. UI 动效令牌/UI 音效/状态效果三个「非内容杂职」**不进 Registry**（它们是 Runtime 调参，归各自 Owner 模块，Phase4 迁走）；
4. 禁止一次性删除 ConfigManager（发生即违 §171）。

---

## 3. Loader（冻结项 2/8）

| # | 冻结内容 |
|---|---|
| LD-1 | **解析只发生在 infrastructure/content/**（S-1 边界）；Loader 拿到的是已解析 JSON 结构，转 Definition 前必须过 §6 校验 |
| LD-2 | **加载五段顺序（冻结）**：①base pack → ②依赖 pack 拓扑序（环=CONTENT_LOAD_FAILED）→ ③Index Build（§5）→ ④Binding 校验（引用/悬空/退役复用，03 §4）→ ⑤发 `ContentReadyEvent`（COMMITTED 语义，随 Phase1 事件契约） |
| LD-3 | **失败语义 fail-fast**：启动期任何 FATAL 违规 → 整体加载失败并列出违规清单（文件/ID/规则号），**禁止静默 fallback 缺省值继续跑**（内容错误比崩溃更危险——错误内容会写进存档）。运行期懒加载分片失败 → 按用例返回安全值 + GameLogger.error（沿用现对话分片语义） |
| LD-4 | **业务层 load 清零计划**：82 处 `load("res://...")` 逐处替换为 Definition 查询或 AssetBinding（场景路径经 §9 场景绑定表解析），随 Phase4 逐模块清零；arch_lint C-R10/CO-R01 兜底 |

---

## 4. Cache（冻结项 3/8）

| # | 冻结内容 |
|---|---|
| CA-1 | **三级缓存**：①Startup 常驻（小表全驻：player/difficulty/bond/world/ui 等）②**ShardCache**（大件懒加载：对话 13 分片、区域分片）③Index 缓存（Build 期生成后只读） |
| CA-2 | **ShardCache 契约冻结**（把现对话 LRU 通用化，参数进配置）：`max_entries=256` · `ttl_ms=2000` · `pin(id)`/`unpin(id)`（引用计数，>0 禁逐出——进行中对话/交易禁逐出）· 逐出回调由 Owner 注册 |
| CA-3 | **缓存键 = 内容 ID**（永不复用 ⇒ 键稳定）；**禁止以显示名/文件路径/中文串为键**（CO-R10） |
| CA-4 | **失效规则**：运行期内容不可变，**禁 invalidate**；仅 dev reload 路径（编辑器/工作室调试）允许整 pack 重载 |

---

## 5. Index（冻结项 4/8）

| # | 冻结内容 |
|---|---|
| IX-1 | **12 张必需索引（01 §46 全列，零删减）**：QuestByNPC · QuestByFaction · QuestByRegion · QuestByChapter · QuestByTag · DialogueByNPC · DialogueByQuest · ItemByCategory · ItemByTag · NPCByRegion · NPCByFaction · AbilityByActor |
| IX-2 | **生成时机 = Load 五段第③步（Build 期）**，运行期只查不建、禁全表扫描（CO-R03）；对应 C-R18 |
| IX-3 | **结构冻结**：`IndexKey -> Array[String]`（ID 数组）；禁存 Definition 对象、禁存 Dictionary |
| IX-4 | **收编计划**：现有对话 `_index.json` shards 表 → DialogueByNPC 雏形；`regions/<rid>/index.json` 的 npcs/quests/items/enemies/battles/dialogs 六表 → NPCByRegion 等 Region 系索引雏形；Quest 系 5 张随 Quest 模块 Phase 点亮，逐张登记进 PROJECT_STATUS |
| IX-5 | **反查**：沿用 ref_index `--who <id>` 能力，Registry 提供 `who_references(id)`（调试与删除影响面评估用） |

---

## 6. Validation（冻结项 5/8）

| # | 冻结内容 |
|---|---|
| VA-1 | **双通道**：构建期（GATE3/6 全仓静态）+ **运行期**（Registry 加载时逐条校验，产出 02 的 `ValidationViolation` 数组）——构建期拦得住的不该活到运行期，运行期校验是防外部内容（Mod/手改档）的最后一道 |
| VA-2 | **五层校验（顺序冻结）**：①Schema 形状（字段/类型/必填，对 03 Definition 契约）→ ②ID 层（正则/13 域白名单/唯一/退役复用，03 §3）→ ③引用层（悬空/环/只存 ID，03 §4）→ ④语义层（数值范围/条件引用的存在性/Binding 完整性）→ ⑤本地化层（display 键必须存在于 strings.csv，接 LN-G18） |
| VA-3 | **违规处置表**：FATAL=拒载该 pack（启动期连带 fail-fast）；ERROR=载入+登记 PROJECT_STATUS 可见；WARN=仅记录。每条违规必带 `rule_id + file + id + 证据` |
| VA-4 | **校验器归属**：五层校验逻辑写成纯函数校验器（RefCounted），构建期（Python 侧 ref_index 升级版）与运行期（GDScript 侧）**共用同一份规则描述**（规则表 JSON 化，双端读取，防两套规则漂移） |

---

## 7. Package（冻结项 6/8）

| # | 冻结内容 |
|---|---|
| PK-1 | 布局与 manifest 字段 = **03 §6 原文**（不重复冻结）；本图冻结**运行时 Pack 生命周期**：`discovered → loading → loaded → failed → unloaded`，状态迁移只发生在 Loader 五段与 Unload |
| PK-2 | **base pack = 现有 `data/configs/` 全量**（物理迁移到 `content/packs/base/` 按 ADR-0003 延 Phase5；逻辑上 Registry 先以「虚拟 base pack」聚合现有目录，manifest 由工具生成） |
| PK-3 | **区域分片收编**：`regions/<rid>/` 七文件结构即 sub-pack 形态 → RegionPack（`_map_index.json` 降级为 base pack 的 region 注册表，其 `index_file` 指针保留） |
| PK-4 | **禁止**：跨 pack 直接 import 对方内部文件；pack 间只许 ID 引用 + manifest 依赖声明 |

---

## 8. Version（冻结项 7/8）

| # | 冻结内容 |
|---|---|
| VE-1 | 四类版本定义 = 03 §5 原文。Registry 的职责落点：**content_fingerprint** = 已载 pack 按 id 排序后 `(pack_id, semver)` 序列的 SHA-256 前 16 位，**同时保存列表原文**（可读可复算，§14 C-4） |
| VE-2 | **进 SaveHeader**：03 的五字段中 `content_version` = 该指纹；读档时重算比对 |
| VE-3 | **兼容规则**：存档缺某 pack 记录=向后兼容（老档无此概念）；存档有、当前无=内容缺失，**ERROR 级提示**（允许进游戏但登记，禁 FATAL 拒读老档——「旧存档必须可用」红线）；schema MAJOR 升级必须走迁移（LN-G09） |

---

## 9. DLC / Mod Content 基础（冻结项 8/8）

| # | 冻结内容 |
|---|---|
| DM-1 | **一律 DLC = Mod = Pack**，无特权代码路径；区别仅在 manifest：`type: base\|expansion\|mod` · `priority` · `overrides: [id,...]` |
| DM-2 | **冲突解析（冻结）**：同 ID 冲突**默认拒绝加载**（FAIL 并列证据）；Mod 覆盖必须 manifest 显式声明 `overrides` 且记录 provenance（谁覆盖谁/原因/来源 pack）——**未声明的覆盖 = 违规，不是特性**（§14 C-2） |
| DM-3 | **安全边界（GDScript 无沙箱的硬约束）**：Mod **禁代码**——pack 目录内出现任何 `.gd/.tscn/.tres` 可执行资源 = 拒载（CO-R07）；只准数据 + 已注册 Asset ID 引用；禁引用未声明的依赖 pack；单 pack 文件数/体积上限进 manifest 校验 |
| DM-4 | **目录与发现顺序**：内置 `res://content/packs/` → 用户 `user://mods/`；同优先级按 manifest priority 升序、后载者仅在 override 声明项内生效 |
| DM-5 | **YAGNI 声明**：本项目当前 DLC/Mod = 0 个；本节只冻结**结构**（manifest 字段/冲突规则/安全边界），发现器与加载分形态 Phase5+ 随工作室「发布为 Pack」功能实装。结构先冻结的目的：防止现在写的 Registry API 把未来 Mod 路堵死 |

---

## 10. 现有资产迁移映射表

| 现状 | 目标 | Phase |
|---|---|---|
| ConfigManager 17 个 `_load_*` | Registry TypeAdapter ×17，壳 facade 委托 | Phase2 起，一次一类 |
| 对话 `_index.json` 13 shards + LRU/pin/TTL | DialogueByNPC 索引 + 通用 ShardCache | Phase2 |
| `_map_index.json`（v2.0.0）+ `regions/<rid>/` | RegionPack + Region 系索引 | Phase3 |
| `strings.csv` → 3 translation | LocalizationProvider（Registry 查键，LN-G18 校验） | Phase4 |
| 82 处业务 `load("res://")` | Definition 查询 / AssetBinding | Phase4 清零 |
| `_map_index` connections 裸名 `misty_town` | 修为 `region_misty_town`（03 C-R01）+ ref_index 拦截 | Phase1（数据修正，随基线） |
| `scene_path` 直存 Definition | `scene_binding` 表（Asset ID → 路径，infrastructure 持有） | Phase3 |
| 分片 `npc_id: ""` | Dialogue 模块主权内补全（§14 C-3） | Phase4 |

---

## 11. Enforcement：规则 → Gate 矩阵 CO-R01~CO-R12

| RULE_ID | 规则 | 严重度 | 执行层 | 检查器 / 测试 | Gate |
|---|---|---|---|---|---|
| CO-R01 | 业务层禁 `load("res://...")`（03 C-R10 的落地宿主） | FATAL | E3/E4 | forbidden_api_validator | GATE22 |
| CO-R02 | Definition 禁资源路径，资产只存 Asset ID | FATAL | E3 | asset_ref_validator | GATE17 |
| CO-R03 | 索引 Build 期生成，运行期禁全表扫描 | ERROR | E3 | content_index_validator | GATE06 |
| CO-R04 | Registry 查询只回 ID 数组/类型化 Definition，禁 Dictionary 逃逸（K-DB 白名单反向） | FATAL | E3 | forbidden_api_validator | GATE22 |
| CO-R05 | Pack 必过五层校验才可 ready | FATAL | E2 | registry_validation_test | GATE06 |
| CO-R06 | 启动期内容 FATAL 必 fail-fast，禁静默 fallback | FATAL | E2 | loader_failure_test | GATE06 |
| CO-R07 | Mod pack 禁代码文件（.gd/.tscn/.tres） | FATAL | E3 | pack_scanner | GATE06 |
| CO-R08 | 覆盖必须 manifest 声明 + provenance，未声明覆盖=拒载 | FATAL | E3 | pack_manifest_validator | GATE06 |
| CO-R09 | content_fingerprint 进 SaveHeader 且可复算 | FATAL | E2 | save_header_test | GATE08 |
| CO-R10 | 缓存键必须为内容 ID，禁显示名/路径/中文串为键 | ERROR | E3 | naming/shape validator | GATE21 |
| CO-R11 | pin 中会话（对话/交易）禁逐出 | FATAL | E2 | shard_cache_test | GATE02 |
| CO-R12 | Unload 仅整 pack 粒度且零引用 | ERROR | E3 | dependency_validator | GATE04 |

**E0（纯文档约束）计数 = 0**。Gate 列一律 LN 编号（04 §2.1 政策）。

---

## 12. Freeze 清单（`CONTENT-RUNTIME v1.2.0`）

| 冻结物 | 内容 |
|---|---|
| Registry | CT-1~CT-4（九职责 API 面 / 目录契约 / facade 迁移策略） |
| Loader | LD-1~LD-4（五段顺序 / fail-fast 语义 / 82 处清零计划） |
| Cache | CA-1~CA-4（三级 / ShardCache 契约 256+TTL+pin / 键=ID / 运行期不可变） |
| Index | IX-1~IX-5（12 张必需索引 / Build 期 / ID 数组结构 / --who 反查） |
| Validation | VA-1~VA-4（双通道 / 五层顺序 / 处置表 / 规则描述双端共用） |
| Package | PK-1~PK-4（生命周期五态 / 虚拟 base pack / RegionPack 收编） |
| Version | VE-1~VE-3（指纹算法 / SaveHeader / 兼容规则） |
| DLC/Mod | DM-1~DM-5（同一 Pack 机制 / 冲突默认拒绝+显式 override / 禁代码 / YAGNI 结构冻结） |
| CO-R01~CO-R12 | §11 全矩阵 |

---

## 13. 完成定义（DoD，7 条）

1. ContentRegistry 骨架（9 API + 五段 Loader + 三级 Cache）落地且 73 存量测试全绿（GATE2 零 ✗）；
2. 首批 ≥3 类内容（ability/item/dialog）走 TypeAdapter 迁移，ConfigManager facade 委托生效；
3. 五层校验器规则表 JSON 化，构建期（Python）与运行期（GDScript）读同一份；
4. 12 张索引登记表 + 首批 2 张（DialogueByNPC/NPCByRegion）Build 期生成；
5. `content_fingerprint()` 可复算并进 SaveHeader（与 03 §5 对齐）；
6. Mod 安全扫描器（禁代码/override 校验）就位，以 1 个测试用假 pack 验证拒载路径；
7. **全部为骨架与契约，未动任何生产源码**（本图产出阶段）。

---

## 14. 开放问题（必须 ADR 裁决，AI 不得自决）

| # | 问题 | 倾向 |
|---|---|---|
| C-1 | Registry 归属与 Autoload 过渡：Application 层 RefCounted 为目标，Phase3 前临时驻 ConfigManager autoload 位 | 按本图执行（01 §45 未指定宿主；Phase3 装配收敛本就迁移 autoload） |
| C-2 | 同 ID 冲突默认拒绝 vs Mod 社区惯例「后载覆盖」 | **默认拒绝 + 显式 override**（安全>灵活；覆盖可追溯才可调试） |
| C-3 | 对话分片 `npc_id: ""` 空置补全归属：Dialogue 模块主权 vs 工具侧（studio/ref_index）生成 | Dialogue 模块主权（内容归模块，工具只校验不代填） |
| C-4 | content_fingerprint 形态：纯哈希 vs 列表+哈希双存 | **列表+哈希双存**（哈希可比对，列表可读可迁移） |

---

## 15. 05 的一句话总纲

**内容机器只此一台：五段装载、三层缓存、十二索引、五层校验、指纹进档；Mod 是 Pack、覆盖须声明、Mod 里没有代码。**

---

## 关联文档

- `PROJECT_CONSTITUTION_V1.2.md`（§44~47 内容架构 / §84 契约测试 / §88 Gate 体系 / §98 Shared Foundation / Provenance）
- `01_总体架构施工图_V1.2.md`（§44 Content ID / §45 Registry 九职责 / §46 Index 12 张 / §47 Binding / §98）
- `03_Contract_Schema_DataContract施工图_V1.2.md`（§3 ID / §4 Reference / §5 Version / §6 Content Pack / §7 序列化）
- `04_Test_Infrastructure_Architecture_Gate施工图_V1.2.md`（§2 Gate Registry / §5 arch_lint / §6 Test Double）
- `02_Domain_Kernel施工图_V1.2.md`（ValidationResult 家族 / DomainEvent COMMITTED 语义）
