# 16_Content_Production施工图_V1.4修复版

> 状态：**FROZEN**（2026-09-06 架构 Owner 批准；可依此实施）
> 序列位置：施工图序列 16/18（01 §128 Phase A）
> 证据基线：2026-09-05 机器实测（`data/configs/` 全量扫描 + 违例正则扫描 + version 全景核对）
> 上游：项目宪法 V1.4（最高执行标准）→ 01 总体架构 → 03 Contract/Schema/DataContract → 05 Content Registry/Pipeline → 15 Studio/Authoring

---

## 0. 编号命名空间声明（冲突检查）

本图启用 **CP**（Content Production）命名空间：

| 段 | 归属 | 说明 |
|---|---|---|
| `CP-1 ~ CP-8` | 本图冻结契约 | 内容生产域 8 件套 |
| `P-CP1 ~ P-CP10` | 本图实锤 | 机器扫描证据，带文件行号 |
| `CP-R01 ~ CP-R12` | 本图 Enforcement | 规则 → Gate 矩阵 |
| `CP-1 ~ CP-4`（§7） | 本图开放问题 | 必须用户/ADR 裁决，AI 不得自决 |

**撞号检查**：01~15 已占用 T / I / O / CT·CO·VA·PK·VE·DM·C / AC / WT / RF / IE / EC / AB / QD / SV / PV / ST。**CP 无撞号**。注意：05 图开放问题前缀为 `C-`（C-1~4），与 `CP-` 不同名，不冲突。

**编号接管声明**：本图**不接管**任何前序编号——
- ID 格式裁决权在 **03 §3.4 / ADR-0002**（本图只做生产面落地方案）；
- 对话分片 `npc_id` 补全归属在 **05 §14 C-3**（Dialogue 模块主权，本图只登记现状）;
- 运行时装载/校验/指纹在 **05 CT/VA/PK/VE/DM**（本图是生产端，不重复冻结）；
- Studio 写入六步在 **15 ST-2**（本图引用为写路径唯一契约）。

---

## 1. 定位

> **V1.4 修复版总注**：本图随宪法 V1.4（ADR-0005）与 01 图 V1.4 修复版同步升版——①宪法条款号零漂移，正文「宪法 §N / 0-C.x / 0-F.x」引用全部有效；②RULE 001 放软：Domain 经白名单 Adapter/Boundary 触达 Godot 属合法协作（判据=0-E.3/GATE15，白名单升表随 ACR）；③本图冻结契约与冻结物版本零变化，V1.2 原稿保留（§171 收编不丢弃）。域内衔接：Raw JSON 允许面（宪法 L308~320）与数据化目标条款号零漂移；内容生产红线与 GATE17 挂槽后口径一致。

**16 号 = 内容生产域**：治理「内容数据本体」——命名、版本、退役、真源结构、写入路径、测试内容隔离、本地化资产。

**与 05 号的分工（一句话）**：05 号管**运行时机器**（装载、注册、缓存、索引、校验、指纹、Pack 生命周期）；16 号管**生产面**（创作出来的那 56 个 JSON 怎么命名、怎么版本化、怎么退役、谁能写、写了怎么验）。两个域在「Validation」处交汇：05 VA-2 五层校验是**机器**，本图 CP-R 矩阵是**喂给机器的生产纪律**。

**宪法锚点**：
- L60：宪法自任「内容生产规范」——本图是该角色的施工化；
- L1595~1611：核心指标「高内容生产效率」、最终追求「**新增内容 → 尽可能数据化**」（本图的全部冻结项都服务于"加内容零代码"）；
- L308~320（0-B.3 Dictionary Policy）：**Raw JSON / Authoring 数据允许**用 Dictionary——内容 JSON 的合法性来自这里，禁止的是用 Dictionary 顶替 Runtime State / Command / Event 契约。

**一句话**：内容是数据不是代码，数据要有户口（ID）、有版本（SemVer）、有坟场（retired 名单）、有唯一入口（DataSink）、有体检（五层校验）。

---

## 2. 现状盘点（机器扫描证据，2026-09-05 实测）

### 2.1 资产表（宪法 §171：升级不丢弃）

| # | 资产 | 实测 | 处置 |
|---|---|---|---|
| 1 | `data/configs/` 全量 | **72 JSON = 56 内容域 + 16 ui 域**；内容域 18 个顶层目录（含 root 级 player.json） | 收编为 05 PK-2 base pack（物理迁移随 ADR-0003 延 Phase5） |
| 2 | `regions/_map_index.json` | v2.0.0；10 区域；`_doc` 明文「区域ID=世界传送ID=内容分片ID，三处不得各自一套」；world/regions.json 真源分裂已修复删除 | **真源统一成果，冻结**（P-CP3） |
| 3 | `regions/<rid>/` 双区域分片 | newbie_village / misty_town 各 6 文件（battles/enemies/index/items/npcs/quests）+ 区内 dialogs；分片点名册 index.json | 收编为 05 PK-3 RegionPack sub-pack |
| 4 | `npcs/dialogs/_index.json` | 全局对话索引：KB 级常驻 + get_dialog 懒加载分片 + pin 保护进行中对话 | **好资产，冻结**（CP-3） |
| 5 | `npcs/dialogs/shards/` | 13 个分片文件，顶层结构 `{id, lines}` | 收编；归属映射靠 _index（P-CP5） |
| 6 | `strings.csv` | 453 行 | 14 PV-8 本地化唯一真源，不重复冻结 |
| 7 | `npcs/town_npcs.json` | 退役只读留档，GATE5 双写防线守着 | **事故教育资产**；CP-1 落地后登记进 retired 名单，GATE5 防线 Phase4 后退役 |
| 8 | `tools/ref_index.py` + `tools/ref_baseline.json` | 悬空引用静态反查 + 存量悬空白名单（修一个删一条） | 03 §4 冻结宿主；**CP-R03 复用同范式** |
| 9 | GATE 槽位群 | verify_all.py GATE1~9 | 15 ST-6 统一注册表收编；本图新增内容校验挂 GATE06 |
| 10 | `items/*.json` 四文件 | version 全部 `1.0.1` | **SemVer 实践标杆** |
| 11 | `abilities/skills.json` | version `1.2.0`（全库唯一非 1.0.x 内容文件） | 版本演进实例 |
| 12 | `_map_index._doc` 注释文化 | 设计决策写进数据文件 `_doc` 字段 | 知识随数据走，鼓励延续 |
| 13 | `battles/grids/` 2 件 + `maps/town.json` | 格子预设/城镇地图，无 version、非实体库 | 登记为**编辑器工具数据**（CP-R04 豁免清单） |
| 14 | `combat/attribute_table.json` | 数值表 | 「数值全进 JSON」铁律载体 |
| 15 | forge/alchemy recipes | 3 个配方 | recipe 域现状（P-CP2 家族 a） |
| 16 | `player.json` | 玩家初始档，顶层 `id: "player"` | **非内容域实体**（运行时/Save 域），建议豁免 13 域正则（CP-R04 豁免清单） |

### 2.2 实锤 P-CP1 ~ P-CP10

> 扫描口径：03 §3.3 冻结正则 `^(npc|dlg|quest|item|abil|stat|enemy|battle|region|shop|recipe|sect|flag)_[a-z0-9][a-z0-9_]*$`（ADR-0002 裁决前现状 C）；排除 `ui/`；正则扫全部 `"id"` 键（定义处+引用处一并命中）。

| # | 实锤 | 证据 |
|---|---|---|
| **P-CP1** | **`_retired_ids.json` 不存在**——03 §3.3 冻结契约（删除 ID 登记退休名单，再出现即 Gate 拦截）零落地。I-1「永不复用」目前无机器兜底 | `data/configs/` 全目录扫描无此文件 |
| **P-CP2** | **内容 ID 违例全景：202 处 / 36 文件 / 0 解析失败**（13 域白名单正则下）。四大家族：<br>**a. 发明前缀**（不在白名单）：skills.json 11 处 `sword_/blade_/inner_/staff_/qinggong_/xinfa_…`（L5~L143）；equipment 15 处 `armor_/acc_`（L4~L18）；materials 18 处 `material_/demo_item_`（L5~L120）；pills 17 处 `pill_`（L4~L20）；weapons 19 处 `weapon_`（L4~L22）；forge/recipes.json L5 `forge_iron_sword`；quests.json 3 处 `q_`（L5/L28/L52）+ nv_qg_demo；scenes/battles.json 9 处全 `tactical_/demo_`（L15~L162）<br>**b. 裸名无前缀**：status_effects.json 10 个全裸拼音（`pojia` L5 … `buqu` L109）；npcs/enemies.json 敌人定义 8 个（`bandit_001` L5、`demo_enemy` L42、`wolf_001` L56…）；player.json L2 `player`<br>**c. 区域前缀 nv_/mt_**：双区域内容全量违例（newbie_village：npcs 6/enemies 2/items 2/quests 3/battles 1/dialogs 2；misty_town：npcs 2/enemies 1/items 1/quests 1/battles 1/dialogs 1）<br>**d. 内部结构行 ID** 约 40 处（对话行 `dg_1/l1/opt_*`、任务 objective `defeat/obj1/defend/give_item`、quest graph 节点 `good/neutral`）——归 05 C-3 与 12 图契约，不走 13 域正则 | 全量扫描清单（本图撰写时机器输出）；enemies.json 20 处中 12 处为技能引用行连坐 |
| **P-CP3** | **区域注册表两种 ID 风格并存**：`newbie_village`(L6)/`misty_town`(L14) 裸名 vs `region_sect_gate` 等 8 个 `region_` 前缀（L22~L75）。03 正则下裸名违例。**好消息**：_doc 三同铁律已落地、真源已统一 | `regions/_map_index.json` |
| **P-CP4** | **SemVer 覆盖双缺口**：① 3 文件 version=`"1.0"` 非 x.y.z（dialogs/dialogue_events.json、difficulty/difficulty_table.json、npcs/dialogs/_index.json L2）；② **20 个内容文件完全无 version 字段**（13 对话分片、player.json、battles/grids 2、bond 2、maps/town、npcs/npc_stats）。全景：56 内容文件 = 36 带 version（33 合规 x.y.z）+ 20 无 | version 全景核对（本图撰写时机器输出） |
| **P-CP5** | **对话分片顶层无 npc_id**（`{id, lines}`），NPC 归属靠 `_index.json` 映射（13 条中 9 有 npc_id、4 空 `dlg_*` 系）——05 §14 C-3 已登记补全归属，本图不接管 | `demo_npc.json` 顶层键 + `_index.json` L4~L70 |
| **P-CP6** | **内容量基线**（生产现状规模）：items 69（weapons 19/materials 18/pills 17/equipment 15）、技能 11、状态效果 10、敌人 11（主城 8+区域 3）、NPC 15 区域+主城、quests 8、战斗配置 11（scenes 9+区域 2）、shops 2、sects 2、recipes 3、对话分片 13、strings.csv 453 行 | 各文件逐条统计（本图撰写时机器输出） |
| **P-CP7** | `town_npcs.json` 退役留档 + GATE5 双写防线在役——退役机制**事实上存在但无契约**（靠门禁脚本硬编码而非 retired 名单数据） | GATE5 门禁行为 |
| **P-CP8** | 悬空引用防线已有工具宿主（ref_index.py + ref_baseline.json 存量白名单「修一个删一条」）但**未挂写路径**——Studio 保存后无增量反查（15 ST-2 六步落地前的缺口） | 15 P-ST7 同源证据 |
| **P-CP9** | `battles/grids/`、`maps/town.json` 属编辑器工具数据（Authoring 侧资产），与内容实体库同住 data/configs 无域标识、无 version——**生产数据与工具数据未分层** | 目录扫描 |
| **P-CP10** | **demo/tactical 测试内容混入生产真源**：scenes/battles.json 9 个战斗配置全部为 demo/tactical 系；newbie_village/npcs.json L52 `demo_npc`、L112 `tactical_demo_master`、L124 `event_demo_npc`；materials.json L45 `demo_item_jade`；quests.json L28 `demo_quest`。测试资产与生产资产无目录隔离，`tactical_studio_preview` 等明显是工具联调产物 | 逐文件行号（上表） |

---

## 3. 冻结契约 CP-1 ~ CP-8

### CP-1 退役名单落地（承接 03 §3.3）

| # | 冻结内容 |
|---|---|
| a | `data/configs/_retired_ids.json` 建立，Schema：`{ "retired": [ { "id": "...", "reason": "...", "retired_at": "日期", "successor": "替代ID或空" } ] }` |
| b | **首个登记动作**：`npc_town_npcs` 体系退役 ID 登记（town_npcs.json 历史实体），GATE5 防线由「脚本硬编码」升级为「读名单数据」，Phase4 分片迁移完成后 GATE5 退役 |
| c | 校验器规则：任何内容 JSON 中出现 retired 名单内 ID = **FATAL**（I-1 永不复用的机器化） |

### CP-2 ID 违例收敛路线（生产面落地方案，格式裁决权在 ADR-0002）

| # | 冻结内容 |
|---|---|
| a | **新内容铁律**：ADR-0002 裁决前按 03 §3.3 现状 C 正则命名（03 L199 已冻结），不得发明新前缀——四大家族一个都不许再扩员 |
| b | **存量收敛 = 基线模式**（同 ref_baseline 范式）：`tools/id_baseline.json` 冻结 202 处存量违例（文件+行号+ID 快照），校验器**基线外零容忍、基线内只减不增**（修一个删一条） |
| c | **域归属映射表（冻结，字面待 ADR-0002）**：`armor_/acc_/material_/pill_/weapon_/demo_item_ → item_`；`sword_/blade_/inner_/staff_/qinggong_/xinfa_/huti_/jingci_/buqu_ → abil_`；`pojia 等 10 裸名 → stat_`；`bandit_001 等 8 敌人 → enemy_`；`q_ → quest_`；`forge_ → recipe_`；`tactical_/demo_ 战斗 → battle_`；`nv_/mt_ → 按域拆分`（CP-2 开放问题）；`newbie_village/misty_town → region_`（CP-2 开放问题）；`player → 豁免（非内容域）` |
| d | **引用同步红线**：任何 ID 改名必须同一次变更内完成「数据定义 + 全部引用（JSON/GDScript/存档迁移层）+ ref_index 反查零悬空 + change_log 留痕」；**禁止**只改数据文件（02 图 Command 化同理） |
| e | **存档红线**：凡已被存档引用的实体 ID 改名，必须配套 Save Migration（13 图 SV 契约），「旧存档必须可用」不可破 |

### CP-3 真源与分片契约（冻结现有统一成果）

| # | 冻结内容 |
|---|---|
| a | `_map_index.json` 是**唯一区域注册表**；「区域ID = 传送ID = 分片ID」三同铁律进机器校验（_doc 承诺 → CP-R06） |
| b | 双区域分片六件套结构（battles/enemies/index/items/npcs/quests + 区内 dialogs）= RegionPack 形态，与 05 PK-3 对齐 |
| c | 对话归属**单点映射**：分片文件保持 `{id, lines}` 纯数据结构，npc 归属唯一真源 = `_index.json` 的 npc_id 字段；与 05 C-3「Dialogue 模块主权」兼容（模块主权管内容补全，本图冻结的是「不许出现第二处归属真源」） |
| d | `_index.json` 懒加载机制（KB 级常驻 + 按需加载 + pin 保护）= 好资产冻结，05 Cache 收编 |

### CP-4 版本契约落地（承接 03 统一 SemVer + 05 VE）

| # | 冻结内容 |
|---|---|
| a | **内容实体库文件**（ weapons/pills/equipment/materials/skills/status_effects/enemies/npcs/quests/battles/recipes/shops/sects 等）version 必须 x.y.z（SemVer 三段） |
| b | 3 个 `"1.0"` 违例文件补齐为 `1.0.0`；20 个无 version 文件按豁免清单处置（CP-R04） |
| c | 豁免清单（冻结）：13 对话分片（version 随 _index）、player.json（Save 域）、battles/grids 2、maps/town.json、bond 布局 2、npc_stats.json——工具数据与派生数据不入实体库版本序列 |
| d | 版本演进纪律：改内容必升 patch，加实体升 minor，破 Schema 升 major 并触发 13 图迁移链（05 VE-3 / LN-G09） |

### CP-5 内容校验器群（喂给 05 VA-2 五层机器的生产纪律）

| # | 冻结内容 |
|---|---|
| a | 五检对应：①Schema 形状（03 Definition 契约）→ ②ID 层（CP-R01/R02/R10）→ ③引用层（CP-R07）→ ④语义层（数值范围/条件存在性）→ ⑤本地化层（CP-R08） |
| b | 构建期 Python 校验器与运行期 GDScript 校验器**共用同一份规则表 JSON**（05 VA-4 双端同源，防规则漂移） |
| c | 校验器注册进 15 ST-6 统一注册表，物理槽 GATE06（03 C-R01 指定槽位）；每条违规必带 `rule_id + file + id + 证据`（05 VA-3） |

### CP-6 生产写入路径（唯一入口，承接 15 ST-2）

| # | 冻结内容 |
|---|---|
| a | 内容文件写入**一律过 DataSink 六步**（15 ST-2：ID 白名单 → Schema → _backup → 落盘 → ref_index 增量反查悬空即回滚 → change_log）；手改文件 = 绕过质量门，GATE 靠基线 diff 抓 |
| b | 写入幂等：同内容重复保存不产生 diff 噪音（_backup 轮转不变） |
| c | 区域内容写入必须同步 `_map_index` 登记一致性（三同铁律校验前置） |

### CP-7 内容 Pack 生产端（承接 05 PK/DM 的创作侧）

| # | 冻结内容 |
|---|---|
| a | 「打包一个区域」= 校验（CP-5 五检）→ manifest 生成 → 依赖声明（ID 引用 + manifest dependencies）→ 指纹登记（05 VE-1 content_fingerprint 输入） |
| b | 禁止跨 pack 直接 import 文件（05 PK-4）；生产端工具同罚 |
| c | Mod 生产预埋：DM-1 三类 manifest（base/expansion/mod）与 DM-3「Mod 禁代码」在生产端工具里前置校验，不等到运行期才拒载 |

### CP-8 本地化资产治理（对齐 14 PV-8，不重复冻结）

| # | 冻结内容 |
|---|---|
| a | strings.csv 453 行 = 唯一真源；内容 JSON 中 display/i18n 键必须存在于 strings.csv（CP-R08，接 LN-G18） |
| b | 键命名域规则随 14 PV-8 冻结；本图冻结**内容侧纪律**：新增内容实体必须同步补 display 键，缺失 = ERROR 级违规 |

---

## 4. 现有资产迁移映射表（绞杀者分批）

| 现状 | 目标 | Phase | 备注 |
|---|---|---|---|
| `_retired_ids.json` 缺失 | CP-1 名单建立 + town_npcs 体系登记 | **Phase1**（纯新增，零风险） | GATE5 升级为读名单 |
| 202 处 ID 存量违例 | `tools/id_baseline.json` 基线冻结 | **Phase1** | 先冻结止涨，收敛随内容迭代 |
| 3 文件 version `"1.0"` | 补为 `1.0.0` | **Phase1** | 3 行改动，零引用风险 |
| id_validator + CP-R01~R12 校验器 | GATE06 槽位上线（15 ST-6 注册表） | **Phase2** | 规则表 JSON 双端同源（05 VA-4） |
| demo/tactical 混产内容 | 独立测试内容目录（如 `data/configs_test/` 或 manifest type 标记） | **Phase2~3** | CP-R09 隔离；区域分片内 demo NPC 随区域迁移 |
| nv_/mt_ 区域前缀 ID | 按 CP-2 域归属映射改名（配套引用同步+存档迁移） | **Phase3~4**（**须 ADR-0002 裁决后**） | 存档红线（CP-2e）；分批按区域 |
| 发明前缀/裸名 ID（item/abil/stat/enemy/quest/recipe/battle 七域） | 同上 | **Phase4** | 引用面大，逐域批次 |
| 20 文件 version 补齐（实体库部分） | CP-4c 豁免清单外全补 | **Phase4** | 随各域迁移顺手做 |
| data/configs 物理迁移 content/packs/base/ | 05 PK-2 | **Phase5**（随 ADR-0003） | 逻辑虚拟 base pack 先行 |
| GATE5 town_npcs 双写防线 | 退役（retired 名单接管） | **Phase4 后** | CP-1b |

---

## 5. Freeze 清单（`CONTENT-PROD v1.2.0`）

1. 13 域白名单正则（引用 03 §3.3，本图不另立字面）+ 新内容禁发明前缀；
2. `id_baseline.json` 基线模式三规则（基线外零容忍 / 只减不增 / 修一删一）；
3. 域归属映射表（CP-2c 九行）；
4. retired 名单 Schema 与 FATAL 规则（CP-1）；
5. 三同铁律机器化（CP-3a）+ 分片归属单点映射（CP-3c）；
6. 豁免清单（CP-4c，13 文件）；version 演进纪律（CP-4d）;
7. DataSink 六步唯一写入口（CP-6，引用 15 ST-2 原文）；
8. 校验规则表 JSON 双端同源（CP-5b，引用 05 VA-4）；
9. Enforcement 矩阵 CP-R01~R12 的 Gate 归属。

---

## 6. 完成定义（DoD，7 条）

1. `data/configs/_retired_ids.json` 存在且 town_npcs 体系已登记，GATE5 逻辑切换为读名单（绿）；
2. `tools/id_baseline.json` 冻结 202 处存量，CI 可证**基线外违例 = 0 且基线行数单调不增**；
3. 内容实体库文件 version 100% 为 x.y.z，豁免清单 13 文件冻结在案；
4. 三同铁律机器校验上线：_map_index ↔ 分片目录 ↔ 传送点 一致性 FATAL；
5. Studio 内容写路径 100% 过 DataSink 六步，保存后 ref_index 增量反查零悬空（15 ST-2 联测）；
6. 五层校验规则表 JSON 单一来源，Python/GDScript 双端读取同表（05 VA-4 验收）;
7. demo/tactical 测试内容完成目录隔离，生产真源内测试资产计数 = 0。

---

## 7. 开放问题（必须用户/ADR 裁决，AI 不得自决）

> **【已追认 2026-09-06】** 用户整批复核：以下 CP-1~CP-4 全部按推荐执行（CP-2 并入 ADR-0002 联动裁决，登记见 `ADR_INDEX.md`）。本表保留原文供审计。

| # | 问题 | 倾向（AI 建议，仅供决策参考） |
|---|---|---|
| CP-1 | 202 处存量违例收敛方式：**基线冻结只拦新增** vs 一次性大改名迁移 | **基线冻结**（推荐）：一次性改名会横扫 36 文件+全部代码引用+存档迁移，是 ADR-0002 裁决后的事；基线模式先止血，把「不得更烂」锁死，收敛随内容自然迭代。与 ref_baseline「修一个删一条」成熟范式同构 |
| CP-2 | `nv_/mt_` 双区域前缀与 `newbie_village/misty_town` 裸名的最终形态：迁移到白名单域前缀（如 `npc_nv_chief`）vs 登记区域作用域变体合法化 | **迁移到白名单域前缀，local 段内嵌区域标识**（推荐）：全局唯一性（03 §3.3「同域内不得重复」）要求 `npc_chief` 这类裸 local 在多区域重复时会撞车，`npc_nv_chief` 既合规又保可读；裸名区域 ID 同理升 `region_newbie_village`。**须与 ADR-0002 合并裁决**，且触发存档迁移链 |
| CP-3 | 对话归属真源：维持 `_index.json` 单点映射 vs 分片文件内补 `npc_id` 字段 | **维持 _index 单点**（推荐）：分片保持纯数据，避免归属双真源；与 05 C-3「Dialogue 模块主权」兼容（主权管内容补全质量，本图管结构唯一性）。若 C-3 裁决要求分片自带 npc_id，则 _index 降级为派生缓存并加一致性校验 |
| CP-4 | 无 version 的 20 文件处置：全部强制补齐 vs 豁免清单 | **豁免清单**（推荐）：13 分片随 _index 版本、player 归 Save 域、grids/maps/npc_stats 属工具数据；只对内容实体库强制 x.y.z。强制全覆盖会产生「版本号表演」（改了格子系统却要升 20 个无关文件的版本） |

---

## 8. Enforcement：规则 → Gate 矩阵 CP-R01 ~ CP-R12

> E0 = 当前执行率 0%（基线建立前全靠人工纪律）；Gate 槽位归属遵循 15 ST-6 统一注册表。

| # | 规则 | 级别 | 执行点 | Gate |
|---|---|---|---|---|
| CP-R01 | 新增内容 ID 必须匹配 03 §3.3 冻结正则（13 域白名单） | FATAL | id_validator | GATE06 |
| CP-R02 | retired 名单内 ID 再现 = 永不复用违约 | FATAL | id_validator + _retired_ids.json | GATE06 |
| CP-R03 | ID 违例基线只减不增（基线外零容忍） | FATAL | id_validator + id_baseline.json diff | GATE06 |
| CP-R04 | 内容实体库 version 必须 x.y.z；豁免清单外无 version = 违规 | ERROR | schema 校验器 | GATE06 |
| CP-R05 | 内容文件写入必须过 DataSink 六步（15 ST-2） | FATAL | Studio 写路径强制 + 变更审计 | GATE7 联测 |
| CP-R06 | 区域三同铁律：_map_index ↔ 分片目录 ↔ 传送点 一致 | FATAL | region 校验器 | GATE06 |
| CP-R07 | 引用悬空 = FATAL（ref_index 反查；存量走 ref_baseline 白名单） | FATAL | ref_index.py | GATE3/6 |
| CP-R08 | display/i18n 键必须存在于 strings.csv | ERROR | 本地化校验器（05 VA-2 第⑤层） | GATE06 |
| CP-R09 | 生产真源内禁新增 demo/tactical 测试资产（隔离完成前冻结增量） | ERROR | id_validator（前缀家族规则） | GATE06 |
| CP-R10 | 同域 ID 唯一性（同域重复 = FATAL；跨域同名 local 允许） | FATAL | id_validator | GATE06 |
| CP-R11 | 内容变更必留痕 change_log（多 AI 协同铁律） | ERROR | 提交钩子抽查 | pre-commit |
| CP-R12 | 运行期五层校验产出 ValidationViolation 并按 05 VA-3 处置 | ERROR | Registry 加载期（05 VA-1 双通道） | 运行期 |

---

## 9. 16 的一句话总纲

**内容要有户口、有版本、有坟场、有唯一写入口、有五层体检；新内容零代码，旧违例只减不增，测试资产不进真源。**

---

## 10. 关联文档

- 项目宪法 V1.4（L60 内容生产规范 / L308~320 Raw JSON 允许 / L1595~1611 数据化目标）
- 01_总体架构施工图_V1.4修复版.md（§44 ID 规范 / §92 Validators / §128 Phase A 序列）
- 02_Domain_Kernel施工图_V1.4修复版.md（ErrorCode / Result / ValidationViolation）
- 03_Contract_Schema_DataContract施工图_V1.4修复版.md（§3 ID 契约 / §3.4 ADR-0002 / §4 Reference / C-R01）
- 05_Content_Registry_Content_Pipeline施工图_V1.4修复版.md（CT/VA/PK/VE/DM 运行时机器；C-3 分片归属主权）
- 12_Quest_Dialogue_Story施工图_V1.4修复版.md（任务/对话/Story Graph 结构契约）
- 13_Save_Persistence_Migration施工图_V1.4修复版.md（存档红线与迁移链）
- 14_Presentation_Input_ViewModel施工图_V1.4修复版.md（PV-8 本地化）
- 15_Studio_Authoring_Validator_Preview施工图_V1.4修复版.md（ST-2 DataSink / ST-6 校验器注册表 / ST-4 studio 拆分）
- ACR-0001（迁移总纲：施工范围未批，本图为契约文档，不含实现代码）
