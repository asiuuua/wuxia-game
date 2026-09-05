# 03 Contract / Schema / Data Contract 施工图 V1.2

- **Document ID**：ARCH-03
- **Version**：1.2
- **Status**：**FROZEN**（2026-09-06 架构 Owner 批准；可依此批量改数据）
- **Authority**：01 总体架构施工图 V1.2（§41~§47 / §69~§71 / §127）
- **对应施工阶段**：01 §128 **Phase A 收尾**（Contract Registry → 依赖规则 → Enforcement Matrix）
- **冻结范围**：**Definition Contract / ID Contract / Reference Contract / Schema Version / Content Pack Contract / 基础序列化契约**
- **Change Policy**：ID Contract 与 Schema Version 属 **Shared Foundation**（01 §98）。变更后**旧存档、旧 Content、旧工具全部受影响**，必须 `ACR → 影响分析 → ADR → 版本升版 → 迁移 → 兼容测试 → Gate`。

---

## 0. 定位

01 定义建筑如何站立，02 钉死最底下的 Kernel。03 钉死的是**「世界是怎么被描述出来的」**——即内容层六大契约。

这六项一旦冻结，才能安全地做后面两件事：

1. Content 生产可以**并行**（多个 AI / 多个窗口同时加 NPC、加任务，互不破坏）
2. Content Registry / Index 才有**可校验的输入**（否则 Registry 只是把混乱搬进内存）

---

## 1. 现状盘点（机器扫描证据）

> 依据宪法 0-A.8：以下为实扫结果。

### 1.1 已有资产（**应升级，不丢弃**——宪法第 171 节）

| 资产 | 现状 | 对应契约 |
|---|---|---|
| `data/schemas/*.gd`（4 个） | **GDScript 强类型 Definition 类**：`ability_data.gd`、`item_data.gd`、`pill_data.gd`、`weapon_data.gd` | Definition Contract ✅ **良好基础** |
| 各配置 `version` 字段 | 普遍存在（见 1.2） | Schema Version ⚠️ **格式不统一** |
| `tools/ref_index.py`（GATE6） | 已实现**引用索引 + 悬空校验 + 反查**；支持 9 类实体、baseline 机制、`--who <id>` | Reference Contract ✅ **可直接升级** |
| `data/configs/regions/<rid>/` | 每区域一个分片 + `index.json` | Content Pack 🟡 **分片雏形** |
| `_map_index.json` | `version: 2.0.0`，10 个区域，区域 ID = 传送 ID = 分片 ID | 区域真源 ✅ |

### 1.2 必须解决的问题

| # | 问题 | 证据 |
|---|---|---|
| **P-1** | **Schema 版本号格式不统一** | 实扫：`1.0`（dialogue_events / difficulty_table / npcs dialogs index）、`1.0.0`（多数）、`1.0.1`（items/*）、`1.2.0`（skills）、`2.0.0`（_map_index）——**三种格式并存** |
| **P-2** | **ID 格式与 01 §44 冲突** | 规范举例 `NPC_000001` / `DIALOGUE_000001`；实扫现有为语义化 `npc_su_waner` / `dlg_sect` / `mt_dialog_priest` / `nv_dialog_elder` |
| **P-3** | Schema 覆盖不全 | 仅 4 个 `.gd` Definition 类，而配置有 20 个子目录（npcs / quests / dialogs / battles / abilities / shop …） |
| **P-4** | 内容入口未收敛 | 业务代码是否存在散布 `load("res://...")` 需 GATE 扫描（01 §45 明令禁止） |

---

## 2. Definition Contract（冻结项 1/6）

### 2.1 三分法铁律（01 §40 / §84）

```
Definition   是什么（静态描述，来自 Content）
Runtime State 现在是什么状态（可变，Owner 持有）
Execution State 当前事务/命令正在做什么（Execution 持有）
Save DTO     怎么持久化（Persistence 持有）
```

**四者不得混成一个对象。**

**禁止**：`NPCDefinition` 同时保存当前位置 / 当前血量 / 当前任务 / 当前关系。
**正确**：`NPCDefinition` / `NPCState` / `NPCSaveDTO` 三者分离。

同样适用于：Quest、Item、Faction、Ability、Shop、Dialogue、Story。

### 2.2 Definition 的承载形式

**采用 GDScript 强类型类（沿用现有 `data/schemas/*.gd` 的成功实践），而非运行时裸 Dictionary。**

```gdscript
class_name ItemDefinition extends RefCounted
## 内容定义。只读，来自 Content，经 Schema 校验后由 ContentRegistry 提供。
## 铁律：Definition 不得保存任何运行时可变状态。

var _id: EntityId
var _name_key: StringName       # 本地化键，禁止硬编码中文（宪法第 123 节）
var _icon_id: StringName         # Asset ID，禁止保存资源路径（宪法第 124 节）
var _category: StringName
var _base_price: int

func get_id() -> EntityId:          return _id
func get_name_key() -> StringName:  return _name_key
func get_icon_id() -> StringName:   return _icon_id
func get_category() -> StringName:  return _category
func get_base_price() -> int:       return _base_price
```

**钉死要点**

| 规则 | 内容 |
|---|---|
| D-1 | Definition 类继承 `RefCounted`，**禁止**继承 `Node` / `Resource` |
| D-2 | Definition 字段**全部私有 + getter**，无公共 setter（宪法 0-B.7） |
| D-3 | 面向玩家的文本一律存**本地化键**，禁止硬编码中文 |
| D-4 | 资源一律存 **Asset ID**（`portrait_id` / `icon_id` / `scene_id`），**禁止**存文件路径 |
| D-5 | Definition 不得引用 Domain 实现类（01 §43） |
| D-6 | 每个 Definition 必须有对应 Schema 校验器与 Content Test |

### 2.3 Definition 覆盖率路线（解决 P-3）

现状 4 个 Definition 类 → 目标覆盖全部内容域。按**内容变更频率 × 出 bug 代价**排序推进：

| 批次 | 内容域 | 理由 |
|---|---|---|
| 第一批 | `item` / `equipment` / `weapon` / `pill` | 已有 4 个类，直接规范化 |
| 第二批 | `npc` / `dialog` / `quest` | 数量最大、引用最密（ref_index 已覆盖） |
| 第三批 | `ability` / `status_effect` / `enemy` / `battle` | 战斗相关，出错代价高 |
| 第四批 | `shop` / `recipe`（forge/alchemy）/ `region` / `sect` | 变更频率较低 |
| 第五批 | `bond`（relations/celebrations/portraits）/ `world` / `localization` | 收尾 |

**未定义 Schema 的内容域，不得新增内容条目**（Content Gate 拦截）。

---

## 3. ID Contract（冻结项 2/6）

> ⚠️ **本节含一个必须 ADR 裁决的冲突，见 §3.4。**

### 3.1 三条不可谈判的铁律（宪法第 26 节 / 01 §44）

| 规则 | 内容 |
|---|---|
| **I-1 永不复用** | ID 一旦分配，永不重新分配给别的实体。删除 = `retired`（进退休名单），不是回收 |
| **I-2 不表达业务状态** | ID 中不得编码「是否已婚 / 是否完成 / 等级」等会变的信息 |
| **I-3 不依赖显示名称** | 改 NPC 的显示名，ID 不变。ID 不随语言变化 |
| **I-4 机器可验证** | 必须能用正则 + 域白名单自动校验；**校验失败即 Gate 拦截** |
| **I-5 引用只存 ID** | 对象之间只保存 ID，**禁止**保存完整对象树（宪法第 30 节，防循环引用 / 存档爆炸） |

### 3.2 ID 结构

```
<DOMAIN><SEP><LOCAL>
```

- `DOMAIN`：域标识，取自**封闭白名单**
- `SEP`：分隔符 `_`
- `LOCAL`：域内唯一标识

**域白名单（冻结，新增域须 ACR）**

| DOMAIN | 含义 | 现有前缀（实测） |
|---|---|---|
| `npc` | 人物 / NPC | `npc_` |
| `dlg` | 对话 | `dlg_` |
| `quest` | 任务 | — |
| `item` | 物品（含装备/丹药/材料） | — |
| `abil` | 技能 / 武学 | — |
| `stat` | 状态效果 | — |
| `enemy` | 敌人 | — |
| `battle` | 战斗配置 | — |
| `region` | 世界区域 | 区域 ID（= 传送 ID = 分片 ID） |
| `shop` | 商店 | — |
| `recipe` | 配方（锻造/炼丹） | — |
| `sect` | 门派 / 势力 | — |
| `flag` | 剧情旗标 | — |

### 3.3 校验正则（机器执行）

```python
# 冻结：ID 校验正则（GATE 使用）
ID_PATTERN = r'^(?P<domain>npc|dlg|quest|item|abil|stat|enemy|battle|region|shop|recipe|sect|flag)_(?P<local>[a-z0-9][a-z0-9_]*)$'
```

校验规则：
- 必须全小写（`[a-z0-9_]`）
- `local` 段不得以数字或下划线开头
- 域必须在白名单内
- 全局唯一（同域内不得重复；跨域允许同名 `local`）

**retired 名单**：`data/configs/_retired_ids.json`，删除的 ID 登记于此，**再出现相同 ID 即 Gate 拦截**（落实 I-1）。

### 3.4 ⚠️ 必须 ADR 裁决：ID 格式与 01 §44 的冲突

**冲突事实**

| 来源 | 格式 | 样例 |
|---|---|---|
| 01 §44 规范举例 | 大写域 + 数字序列 | `NPC_000001`、`QUEST_000001`、`DIALOGUE_000001` |
| 本工程实测现状 | 小写域 + 语义名 | `npc_su_waner`、`dlg_sect`、`mt_dialog_priest`、`nv_dialog_elder` |

**三个方案对比**

| 方案 | 形态 | 迁移成本 | 可读性 | 存档影响 | 评注 |
|---|---|---|---|---|---|
| **A 严格合规范** | `NPC_000001` | **极高**（72 JSON + 全部代码引用 + 语义映射表） | **差**（人类无法从 ID 看出是谁） | ⚠️ **破坏旧存档**（存档内含 ID 引用，需全量迁移） | 字面完全合规，但对单人开发不友好 |
| **B 折中** | `NPC_SU_WANER` / `DIALOG_SECT` | 中（可脚本机械改名 + 存档迁移层） | 好 | ⚠️ 需存档迁移层 | 满足「域_标识」结构 + 大写域，保留可读性 |
| **C 保留现状（推荐）** | `npc_su_waner` | **零** | 最好 | ✅ **无**（不碰存档） | 满足规范**实质**要求 |

**推荐方案 C，理由：**

1. **规范 §44 的实质是「机器验证 + 永不复用 + 不依赖显示名」，数字序列只是举例形式**，不是唯一合法形态。C 方案同样满足 I-1~I-5 全部五条铁律。
2. **存档红线**：01 §71 / 宪法第 32 节明令「禁止旧存档不能用了」。A/B 方案都会改动存档内的 ID 引用，必须配套全量 Save Migration——这是本阶段最大的风险源。
3. **可读性对单人开发是真实生产力**。`npc_su_waner` 能让人一眼看出是苏婉儿；`NPC_000001` 需要额外查表。
4. **零迁移成本**意味着可以把精力放在真正 gap 上（Schema 覆盖、引用校验、Registry）。

**代价与补偿**：C 偏离规范字面。补偿措施是——在 ID Contract 中把**域白名单 + 正则 + retired 名单 + 唯一性**四项全部钉死并机器拦截，使「机器可验证」这条实质要求被严格满足。

> **需 ADR 裁决（ADR-0002）**：选 A / B / C。在裁决前，**ID 格式冻结为现状 C 的正则（§3.3）**，新内容按此规则命名，不得发明新前缀。

---

## 4. Reference Contract（冻结项 3/6）

### 4.1 铁律

| 规则 | 内容 |
|---|---|
| **R-1** | 对象之间**只保存 ID**，禁止保存完整对象树（宪法第 30 节） |
| **R-2** | 引用必须**可静态校验**——构建期发现 `QUEST_000123 不存在`，而不是运行时崩溃（01 §42） |
| **R-3** | 循环引用**禁止**在数据结构层出现（可通过 Event / Query 在行为层解耦，宪法第 147 节） |
| **R-4** | 跨模块引用通过 **Binding 对象**组合，禁止硬编码嵌套（01 §47） |

**错误**（R-1 违规）：
```
Marriage
 ├── NPC_A
 │   ├── Inventory
 │   ├── Quest
 │   └── ...
 └── NPC_B
```

**正确**：
```
MarriageState
    spouse_a_id: EntityId
    spouse_b_id: EntityId
```

### 4.2 现有引用关系（升级 `ref_index.py` 为契约 Enforcement）

**实扫 `tools/ref_index.py` 已覆盖的定义侧 / 引用侧，直接继承为契约基线：**

**定义侧（9 类实体）**

| 实体 | 来源 |
|---|---|
| `npc` | `regions/*/npcs.json` |
| `quest` | `regions/*/quests.json` + `quests/quests.json` |
| `item` | `items/{equipment,materials,pills,weapons}.json` + `regions/*/items.json` |
| `battle` | `regions/*/battles.json` + `battles/*.json` |
| `enemy` | `regions/*/enemies.json` + `npcs/enemies.json` |
| `dialog` | `npcs/dialogs/_index.json` 分片 + `regions/*/index.json dialogs` |
| `ability` | `abilities/skills.json` |
| `flag` | 任务 `then_set` 键 + 对话 `set_flag` 命令 |
| `region` | `regions/_map_index.json` |

**引用侧（悬空即拦）**

```
npc.dialog_id        → dialog
npc.quest_id         → quest
npc.battle_id        → battle
quest.objectives[].target_battle → battle
quest.objectives[].need_item     → item
quest.rewards.items[].item_id    → item
quest.rewards.abilities[]        → ability
quest.prerequisites              → flag（只告警不硬拦：旗标可运行时定义）
对话行 next_id / options.jump_id → 同分片行 id（对话图内部可达）
```

**保留机制**：`tools/ref_baseline.json` 存量悬空白名单，**修一个删一条**（防止欠债扩大）。

### 4.3 升级要求（现有 GATE6 → Reference Contract Gate）

| 现状 | 升级目标 |
|---|---|
| 局部扫描（已知字段名精准提取） | 覆盖全部新增内容域（§2.3 五批） |
| 悬空即拦 | 追加：**重复 ID 检测**、**retired 复用检测**、**循环引用检测** |
| 单一报告 | 产出**机器可读引用索引**（供 Content Index 消费，01 §46） |
| 命令行工具 | 接入 `verify_all.py` 统一入口 |

---

## 5. Schema Version Contract（冻结项 4/6）

### 5.1 统一 SemVer（解决 P-1）

**冻结格式：`MAJOR.MINOR.PATCH`，三段，缺段即 Gate 拦截。**

```
MAJOR  破坏性结构变化（字段删除/改名/语义变更）→ 旧数据需迁移
MINOR  向后兼容的新增（加可选字段、加新枚举值）
PATCH  不改变语义的修正（错字、注释、文档）
```

**实扫待收敛项**（`1.0` → 必须补为 `1.0.0`）：

| 文件 | 现值 | 目标 |
|---|---|---|
| `data/configs/dialogs/dialogue_events.json` | `1.0` | `1.0.0` |
| `data/configs/difficulty/difficulty_table.json` | `1.0` | `1.0.0` |
| `data/configs/npcs/dialogs/_index.json` | `1.0` | `1.0.0` |

> 其余已为三段式，无需改动。

### 5.2 版本层级（01 §70 / 宪法 23C）

四类版本**独立版本化**，互不混用：

| 版本 | 载体 | 当前值 |
|---|---|---|
| `schema_version` | 单个内容 Schema | 各配置 `version` 字段 |
| `content_version` | Content Pack 整体 | 待建（`content/manifests/`） |
| `save_schema_version` | 存档结构 | `SAVE_VERSION = "1.1.0"`（`SaveManager.gd:8`） |
| `game_version` | 游戏构建 | `project.godot` config |

**Save Header 必须包含全部四项 + timestamp + checksum**（01 §70）：

```gdscript
class_name SaveHeader extends RefCounted
var save_version: StringName      # 存档结构版本
var game_version: StringName      # 游戏构建版本
var content_version: StringName   # 内容包版本
var timestamp: int                # 游戏内时间戳（非系统时间，走 GameClock）
var checksum: String              # 完整性校验
```

### 5.3 版本变更铁律

| 规则 | 内容 |
|---|---|
| V-1 | 内容结构明显改变但版本号不变 = **违规**，Gate 拦截 |
| V-2 | MAJOR 升版必须配套 **Migration + 兼容测试 + Fixture** |
| V-3 | **禁止旧存档不能用了**（宪法第 32 节 / 01 §71） |
| V-4 | Schema / Content / Save / Architecture 版本任一变化 → **旧 Context Pack 自动失效**（宪法 133 节） |

---

## 6. Content Pack Contract（冻结项 5/6）

### 6.1 Content Pack 结构

```
content/
├── schemas/          # Schema 定义（现有 data/schemas/*.gd 迁入）
├── definitions/      # 内容定义（现有 data/configs/** 迁入）
├── packs/            # 内容包
│   └── <pack_id>/
│       ├── manifest.json
│       └── ...
├── indexes/          # 生成的索引（01 §46）
├── localization/     # 本地化
└── manifests/        # 包清单
```

### 6.2 Manifest 契约

```json
{
  "id": "region_newbie_village",
  "version": "1.0.0",
  "minimum_game_version": "0.1.0",
  "dependencies": ["core_items", "core_dialogs"],
  "optional_dependencies": ["region_misty_town"],
  "content": {
    "npcs": ["regions/newbie_village/npcs.json"],
    "quests": ["regions/newbie_village/quests.json"],
    "dialogs": ["regions/newbie_village/dialogs/*.json"]
  },
  "capabilities": [],
  "checksum": ""
}
```

**字段契约**

| 字段 | 必填 | 说明 |
|---|---|---|
| `id` | ✅ | 包 ID，全局唯一，永不复用 |
| `version` | ✅ | SemVer 三段 |
| `minimum_game_version` | ✅ | 最低游戏版本 |
| `dependencies` | ✅ | 硬依赖，缺失即拒绝加载 |
| `optional_dependencies` | ⬜ | 软依赖，缺失降级 |
| `content` | ✅ | 内容条目清单 |
| `capabilities` | ⬜ | 该包启用哪些 Capability（01 §77） |
| `checksum` | ✅ | 完整性校验 |

> **DLC / Mod 扩展字段（2026-09-05 由 05 §9 定义）**：`type: base|expansion|mod`（base 必填为 type，缺省按 base）· `priority`（mod/expansion 必填）· `overrides: [id,...]`（mod 覆盖声明，未声明的同 ID 冲突=拒载）。base pack 三字段可缺省；运行时冲突/安全语义冻结在 `05_Content_Registry_Content_Pipeline施工图_V1.2.md` §9。

### 6.3 迁移映射：现有 regions 分片 → Content Pack

**现有 `data/configs/regions/<rid>/`（含 `index.json` + npcs/quests/dialogs/items/enemies/battles）已是天然的 Pack 雏形。**

| 现有 | 迁移后 |
|---|---|
| `regions/<rid>/index.json` | `packs/region_<rid>/manifest.json` 的 `content` 段 |
| `regions/_map_index.json`（v2.0.0，10 区域） | 区域总索引（真源保留） |
| `data/configs/{items,abilities,quests,...}/` | `packs/core_*/` 基础包 |

**铁律**：区域 ID = 传送 ID = 分片 ID（现有真源裁定，**保持不变**）。

---

## 7. 基础序列化契约（冻结项 6/6）

### 7.1 JSON 边界（Dynamic Data Boundary K-DB-02，承接 02 §11.3）

| 规则 | 内容 |
|---|---|
| **S-1** | JSON 只允许出现在 **Infrastructure / Content 边界**（`infrastructure/content`、`content/`） |
| **S-2** | **Domain 禁止读/写/解析 JSON**（宪法 RULE 002）。当前 `services/` + `core/` 有 **5 个文件 / 6 处 `JSON.`** —— Phase 5 必须清零 |
| **S-3** | 解析必须显式检查返回值（项目既有惯例）：`var json := JSON.new(); if json.parse(text) != OK: → 失败处理` |
| **S-4** | 解析产物必须转为**强类型 Definition**，禁止把 Dictionary 直接传进业务层 |
| **S-5** | **禁止业务代码散布 `load("res://...")`**（01 §45）。资源加载统一走 `ContentRegistry` / `AssetProvider` |
| **S-6** | Save 序列化：Runtime Object **不得直接当 Save DTO**（01 §70）。必须经 SaveDTO 转换 |

### 7.2 加载链路（01 §42 / §45）

```
Raw Content (JSON)
   ↓  【K-DB-02 边界：此处允许 Dictionary/Variant】
Schema Validation        ← schema_version 校验 + 结构校验
   ↓
ID Validation           ← 域白名单 + 正则 + 唯一性 + retired 检查
   ↓
Reference Validation    ← ref_index 全量悬空/重复/循环检查
   ↓
Condition Validation    ← 条件表达式可解析
   ↓
Dependency Validation   ← Pack manifest 依赖解析
   ↓
Localization Validation ← 本地化键存在
   ↓
Balance Validation      ← 数值区间检查（可选）
   ↓
Build → Index Generation
   ↓
Content Package
   ↓
ContentRegistry         ← 【边界结束：此后一律强类型 Definition】
   ↓
Runtime Consumption (Domain / Application)
```

**铁律：边界之后不得再有 Dictionary 进入业务层。** `ContentRegistry` 是唯一出口。

### 7.3 Content Index 契约（01 §46）

必须建立（避免运行时全表扫描）：

| 索引 | 键 → 值 |
|---|---|
| `QuestByNPC` | npc_id → Array[quest_id] |
| `QuestByRegion` | region_id → Array[quest_id] |
| `QuestByFaction` | faction_id → Array[quest_id] |
| `QuestByTag` | tag → Array[quest_id] |
| `DialogueByNPC` | npc_id → Array[dlg_id] |
| `DialogueByQuest` | quest_id → Array[dlg_id] |
| `ItemByCategory` | category → Array[item_id] |
| `NPCByRegion` | region_id → Array[npc_id] |
| `AbilityByActor` | actor_id → Array[abil_id] |

**索引由 Build 阶段生成，禁止运行时动态全表扫描构建。**

---

## 8. Enforcement：规则 → Gate 矩阵

> **编号命名空间（2026-09-05 与 04 联合勘定）**：本表 Gate 列一律使用**逻辑编号 LN** = 宪法 §88（GATE01~20）∪ 01 §127（GATE21~32）。verify_all 的**物理槽位**编号与 LN 不同（如物理 GATE6=引用校验 对应 **LN-G07** Reference Integrity；物理 GATE8/GATE9=结构兜底/JS 门禁，与 LN-G08 Save/Load、LN-G09 Migration **无关**）。物理↔逻辑映射的唯一权威表在 `04_Test_Infrastructure_Architecture_Gate施工图_V1.2.md` §2.2。

| RULE_ID | 规则 | 严重度 | 执行层 | 检查器 / 测试 | Gate |
|---|---|---|---|---|---|
| C-R01 | ID 必须匹配域白名单正则 | FATAL | E3/E4 | `id_validator` | GATE06 |
| C-R02 | ID 全局唯一，同域不得重复 | FATAL | E3/E4 | `id_validator` | GATE06 |
| C-R03 | retired ID 不得被复用 | FATAL | E3/E4 | `id_validator` | GATE06 |
| C-R04 | Schema 版本号必须三段 SemVer | ERROR | E3 | `schema_version_validator` | GATE06 |
| C-R05 | 内容结构变更必须升版本号 | FATAL | E3 | `schema_version_validator` | GATE06 |
| C-R06 | 引用不得悬空 | FATAL | E3/E4 | `ref_index.py`（现有物理 GATE6 升级） | GATE07 |
| C-R07 | 数据结构层禁止循环引用 | FATAL | E3 | `reference_cycle_validator` | GATE07 |
| C-R08 | 对象引用只存 ID，禁止对象树 | FATAL | E3 | `reference_shape_validator` | GATE07 |
| C-R09 | Domain / Kernel 禁止 `JSON.` | FATAL | E3/E4 | `forbidden_api_validator` | GATE22 |
| C-R10 | 业务代码禁止 `load("res://...")` | FATAL | E3/E4 | `forbidden_api_validator` | GATE22 |
| C-R11 | Definition 类必须 `RefCounted` + 私有字段 + getter | ERROR | E3 | `definition_shape_validator` | GATE21 |
| C-R12 | Definition 禁止硬编码中文（须本地化键） | ERROR | E3 | `localization_validator` | GATE18 |
| C-R13 | Definition 禁止存资源路径（须 Asset ID） | ERROR | E3 | `asset_ref_validator` | GATE17 |
| C-R14 | Pack manifest 必填字段完整 | FATAL | E3 | `pack_manifest_validator` | GATE06 |
| C-R15 | Pack 依赖可解析、无循环 | FATAL | E3 | `pack_dependency_validator` | GATE06 |
| C-R16 | Save Header 必须含 4 版本 + timestamp + checksum | FATAL | E2/E3 | `save_header_test` | GATE08 |
| C-R17 | Save 兼容：旧存档可读 | FATAL | E2 | `migration_test` | GATE09 |
| C-R18 | Content Index 必须 Build 期生成 | ERROR | E3 | `content_index_validator` | GATE06 |

**覆盖率**：E3/E4 共 13 条、E2 共 2 条（C-R16/17 同时含 E3/E2）、**E0 = 0 条**。

---

## 9. Freeze 清单

| 冻结项 | 内容 |
|---|---|
| Definition 三分法 | Definition / Runtime / Execution / Save DTO 四项分离 |
| Definition 类形态 | `RefCounted` + 私有字段 + getter + 本地化键 + Asset ID |
| ID 结构 | `<domain>_<local>`，13 个域白名单，正则（§3.3） |
| ID 五铁律 | I-1 永不复用 / I-2 不表达状态 / I-3 不依赖显示名 / I-4 机器可验证 / I-5 只存 ID |
| 引用关系表 | §4.2 的 9 类定义侧 + 全部引用侧 |
| 版本格式 | SemVer `MAJOR.MINOR.PATCH` 三段 |
| 四类版本 | schema / content / save / game 独立版本化 |
| Save Header | 4 版本 + timestamp + checksum |
| Pack Manifest | §6.2 字段契约 |
| Content Index | §7.3 九类索引 |
| 序列化边界 | JSON 仅止于 Content/Infrastructure；ContentRegistry 是强类型唯一出口 |

**冻结版本号**：`CONTENT-CONTRACT v1.2.0`

---

## 10. 完成定义（DoD）

- [ ] **Implementation**：`id_validator` / `schema_version_validator` / `pack_manifest_validator` 落地并接入 `verify_all.py`
- [ ] **Schema 收敛**：`1.0` → `1.0.0` 三处补段完成，全仓版本号三段式
- [ ] **Contract Compliance**：13 个域的 Definition 类按 §2.3 批次推进（至少完成第一批）
- [ ] **Architecture Compliance**：C-R01~C-R18 全绿
- [ ] **Required Tests**：ID 唯一性 / retired / 悬空引用 / 循环引用 / Save 兼容 五类测试齐备
- [ ] **Regression**：现有 9 门禁仍全绿，**零既有测试被删改**
- [ ] **Documentation**：Contract Registry 登记、变更通告、ADR（含 §11 三项）已出

**缺一：NOT COMPLETE。**

---

## 11. 开放问题（必须 ADR 裁决）

> **【已追认 2026-09-06】** 用户整批复核：ADR-0002 按推荐 **C** 落定（联动 06 AC-1 扩展 B 与 16 CP-2 白名单域前缀）、ADR-0003 延 Phase 5、ADR-0004 保留 `.gd`——登记见 `ADR_INDEX.md`；本表保留原文供审计。

| ID | 问题 | 影响 | 建议 |
|---|---|---|---|
| **ADR-0002** | **ID 格式**：A 严格 `NPC_000001` / B 折中 `NPC_SU_WANER` / C 保留 `npc_su_waner` | 影响 72 JSON、全部代码引用、**旧存档** | **推荐 C**（零迁移、不动存档红线、满足规范实质五铁律） |
| **ADR-0003** | **目录迁移时机**：`data/configs/**` → `content/definitions/**` 何时执行 | 大范围路径变更，影响所有加载代码 | **建议延后至 Phase 5**（先用契约约束，待 Registry 就绪时一次性搬迁，避免二次返工） |
| **ADR-0004** | **Schema 表达形式**：继续用 GDScript `.gd` 类，还是引入 JSON Schema？ | 决定校验器实现方式 | **建议保留 `.gd` 强类型类**（现有实践良好、与 GDScript 类型体系天然一致、编译器即校验器），另生成机器可读的 Schema 摘要供工具消费 |

---

## 12. 03 的一句话总纲

> **内容不是「一堆 JSON」，而是一套有身份、有引用、有版本、有边界的契约体系。**
> ID 让它可被唯一指认，Reference 让它可被静态验证，Schema Version 让它可被安全演进，Content Pack 让它可被组合与分发，序列化边界让它不把 Dictionary 泄漏进业务层——**Definition 则保证「世界是什么」与「世界现在怎么样」永不混淆。**

---

## 关联文档

- 上位：`docs/constitution/PROJECT_CONSTITUTION_V1.2.md`、`docs/architecture/01_总体架构施工图_V1.2.md`
- 平级：`docs/architecture/02_Domain_Kernel施工图_V1.2.md`、`docs/architecture/三张工程图_V1.2.md`、`docs/architecture/ACR-0001_采纳V1.2宪法与目标架构迁移.md`
- 下位（待产）：`04 Test Infrastructure / Architecture Gate 施工图`、`05 Content Registry / Pipeline 施工图`
