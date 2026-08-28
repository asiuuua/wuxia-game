# 架构对接分析：百万文本/千支线 CRPG 蓝图 × 项目现状

> 生成时间：2026-08-28
> 目的：核对蓝图（用户粘贴的「Godot4 + GDScript｜面向百万文本、千条支线 CRPG 完整架构」）与项目当前实现，标出「已有 / 部分 / 缺失」，并给出分期落地顺序。
> 结论先行：**架构路线已高度同源（数据驱动 + 模块化 + EventBus + Service），蓝图是现有骨架的自然扩张，不是推翻重来。真正缺失的是 4 个中枢级组件 + 若干战斗/任务子能力 + CSV 体系决策。**

---

## 一、分层映射（蓝图 ↔ 现状）

| 蓝图层级 | 现状对应 | 吻合度 |
| --- | --- | --- |
| 表现层 UI | `scenes/ui/`（UIManager + screens + components） | ✅ 已对齐，UI 只展示、不发业务逻辑 |
| 业务层：任务剧情 | `services/quest/quest_service.gd` + `DialogOverlay` | 🟡 有接取/推进/完成，缺多失败分支/事件驱动判定/检定 |
| 业务层：回合战斗 | `services/combat/combat_service.gd` | 🟡 有回合/伤害/奖励，缺倒地/非致命/逃跑/多难度/自动AI/快照 |
| 业务层：检定系统 | —— | ❌ 完全缺失（蓝图要求预留空壳） |
| 业务层：AI 自动战斗 | 敌人回合仅 `basic_attack` | 🟡 雏形，无策略 AI |
| **中枢：EventBus** | `autoload/EventBus.gd` | ✅ 已存在，但**未严格区分 NOTIFY_/CMD_ 命名**，缺单位快照/倒地/逃跑事件 |
| **中枢：GameState** | `GameManager`(容器) + `PlayerState` + 各 Service 自带状态 | 🔴 **无统一全局状态中枢**；任务阶段/单位运行时/全局flag/难度散落各处 |
| **中枢：SaveValidator** | —— | 🔴 **完全缺失**；读档后无校验/自动修复矛盾 |
| 静态资源层：配置解析 | `autoload/ConfigManager.gd` | 🟡 **用 JSON 而非蓝图要求的 CSV**；无字段校验工具 |
| ModSupport 抽象层 | —— | ⏸ 后期（蓝图明确禁止前期） |
| Multiplayer 抽象层 | —— | ⏸ 极后期 |

---

## 二、逐组件核对（能否实现 / 现状 / 缺口）

### 0. 静态资源层｜配置解析管理器
- **现状**：`ConfigManager` 启动时加载 9 类 JSON（`skills/items/enemies/battles/quests/npcs/dialogs/recipes/world`），按 ID 查字典。逻辑与数据已分离 ✅。
- **缺口**：
  1. **格式分歧**：蓝图要求 **CSV 表格**（Excel 编辑、MOD 友好、外部剧情导入追加）。当前全 JSON。→ 需决策（见第四节）。
  2. **无配置校验工具**：蓝图风险点 #1「读 CSV 检查必填字段缺失」。当前 `_load_json` 只查文件存在/解析失败，**不校验每条记录的必填字段**。→ 需补 `ConfigValidator`。
  3. **无流式加载**：`strings.csv` 已存在（本地化文本雏形），但百万文本按需流式加载未做。

### 1-1 EventBus 事件总线
- **现状**：发布-订阅已落地，信号分模块声明（inventory/combat/ability/equipment/quest/player/dialogue/flow…）。
- **缺口**：
  1. **未区分 NOTIFY_/CMD_ 两类语义**（蓝图硬规）。当前 `combat_started`/`quest_completed` 等是通知，但**指令事件（CMD_START_COMBAT 等）基本没有**——战斗是靠 `GameManager.start_battle()` 直接调用 + `pending_battle_id` 触发，而非指令事件。
  2. **缺关键事件**：`NOTIFY_UNIT_KILLED`(带 snapshot)、`NOTIFY_UNIT_DOWNED`(倒地/非致命区分)、`NOTIFY_COMBAT_FINISHED`(带胜利/逃跑/全单位快照)、`NOTIFY_ESCAPE_SUCCESS/FAIL`、`CMD_SET_UNIT_FACTION`、`CMD_APPLY_STORY_BUFF`、`NOTIFY_DIALOG_END`(带选项ID)。

### 1-2 GameState 全局状态中枢
- **现状**：**没有独立 GameState**。运行时状态分散——任务阶段在 `quest_service.active_quests`；玩家数据在 `PlayerState`；NPC/单位世界态（存活/倒地/死亡/阵营/好感）**根本不存在持久态**（战斗中死亡只活在 `CombatState`，战斗结束即弃）；全局 flag 字典不存在；难度只在 `SettingsManager` 里当 UI 选项，没接入战斗。
- **缺口（蓝图核心）**：需新建统一 `GameState` 单例，集中持有：
  1. 每个 quest_id 的 phase 阶段（多失败枚举）
  2. 全局 flag 字典（世界开关/剧情变量）
  3. Unit 运行时状态（alive/downed/dead/faction/affinity）
  4. 当前难度等级
  5. **作为存档序列化唯一来源**（替代当前「各 Service 各自 register_saveable」的分散式）

### 1-3 SaveValidator 存档校验&自动修复器
- **现状**：**完全缺失**。`SaveManager` 只有读写，读档后直接进入游戏，**无任何矛盾检测**。
- **缺口**：需新建 `SaveValidator`，在读档完成、业务模块启动前执行：遍历进行中任务 → 取配置条件 → 对比 GameState 单位真实状态 → 冲突则置对应失败 phase + 抛修复通知 + 写修复日志。

### 2-1 QuestDialogSystem 任务&对话
- **现状**：`quest_service` 有 accept/objective 推进/complete/turn_in/奖励/存档。对话有 `DialogOverlay` + `dialogs.json`。
- **缺口**：
  1. **多失败分支**：当前只有 ACTIVE/COMPLETED/TURNED_IN，无 `FAIL_DEAD_NPC`/`FAIL_ESCAPED` 等。
  2. **事件驱动判定缺失，且存在反向硬调用**：`combat_service.finalize()` 直接 `GameManager.quest_service.on_battle_won(...)`——这正是蓝图明令禁止的「直接函数调用」。**应改为战斗结束发快照事件，任务系统订阅判定**。
  3. **条件 JSON 评估缺失**：当前目标只匹配 `target_battle`，无 `{"unit_id":..,"must_alive":true}` 通用条件引擎。
  4. **技能检定模块**：完全缺失，蓝图要求先留空壳 + 配置字段预留。

### 2-2 CombatSystem 回合战斗
- **现状**：回合流转/伤害/暴击/奖励/事件通知已具备。
- **缺口**：
  1. 倒地状态 / 非致命击倒（两个独立枚举，事件区分通知）
  2. 逃跑机制（成功/失败 → `NOTIFY_ESCAPE_*`）
  3. 多难度系数（读 `difficulty_table` 改数值，当前难度未接入战斗）
  4. 自动战斗 AI（独立子组件，当前敌人仅普攻，无策略）
  5. **战斗结束发单位快照事件**（当前 `combat_ended(combat_id, result:int)`，无快照，任务无法读"关键NPC是否死亡"）

### 2-3 / 2-4 ModSupport / Multiplayer
- **现状**：均无。
- **处置**：严格按蓝图——**前期不做**。架构预留接口位即可（配置层可合并、事件总线可转发），不写实现。

### 3. 表现 UI 层
- **现状**：已对齐「UI 只展示、点击发 CMD 事件」原则（`open_screen` 传参、`SaveCard` 等组件化）。
- **缺口**：随下层事件/状态补全，UI 订阅新事件即可，无独立风险。

---

## 三、当前代码违反蓝图铁律的 2 处（需优先整改）
1. **跨模块直接调用**：`combat_service.finalize()` → `GameManager.quest_service.on_battle_won()`。违反「禁止直接函数调用，全部走事件」。
2. **无统一状态中枢**：NPC 世界态不持久化，导致「村长该活却死了」这类矛盾无从检测，也直接造成 SaveValidator 无数据可修。

---

## 四、需要决策的分歧点（记录待批）
- **A. 配置格式 JSON vs CSV**：蓝图点名 CSV（MOD/外部导入友好）。当前全 JSON，且已稳定跑通。建议：**保留 JSON 作为开发期源格式，新增一个 CSV↔JSON 转换/合并层**（满足蓝图「MOD 提供 CSV 补丁 → 合并解析」），不推翻现有 JSON 管线。待用户拍板。
- **B. GameState 是新建单例还是演进 GameManager**：建议新建独立 `GameState` 单例（职责单一），`GameManager` 退为「场景编排 + Service 容器」，避免单例膨胀。

## 五、分期落地顺序（对齐蓝图四阶段 + 现状）

### ✅ 阶段1 骨架对齐（已完成 · 2026-08-28）
| 组件 | 状态 | 落点 |
| --- | --- | --- |
| `GameState` 全局状态中枢 | ✅ 已实现 | `autoload/game_state.gd`：global_flags / unit_runtime（存活-倒地-死亡·阵营·好感）/ difficulty + 类型化 API + serialize/load/reset，已注册为可存档 |
| `SaveValidator` 读档校验修复器 | ✅ 已实现 | `autoload/save_validator.gd`：订阅 game_loaded，按 `fail_conditions` 比对 GameState 单位态，冲突置 `FAIL_DEAD_NPC`/失败 + 抛 `quest_failed` + 修复日志 |
| EventBus NOTIFY_/CMD_ 事件 | ✅ 已实现 | 新增 `combat_finished(combat_id,victory,escaped,snapshots)` / `quest_failed` / `cmd_start_combat` 等，严格区分通知/指令 |
| combat→quest 解耦 | ✅ 已实现 | `combat_service.finalize()` 改为发快照事件 + 删硬调用；`quest_service` 订阅推进目标；`GameManager` 连接战斗事件 |
| 自动化验证 | ✅ 通过 | 临时脚本模拟「村长死亡+任务要求存活」→ 读档后自动置 FAIL_DEAD_NPC（场景A通过）；村长存活不误判（场景B通过）；整工程 parse-gate EXIT=0 |

> ⚠️ **已知阶段性偏差（记录在案，不阻塞）**：① 任务阶段目前仍由 `quest_service.active_quests` 持有（蓝图要求放 GameState），待阶段2 再评估迁移；② `cmd_start_combat` 信号已定义但未自动开启战斗（我们的战斗以 battle_id 配置驱动，与蓝图 attacker/defender 列表语义不同，留作后期对话/任务发指令时再接线）；③ `ConfigValidator` 字段校验工具尚未补（蓝图风险点#1，列入阶段2 收尾）。

### 🟡 阶段2 业务填充（下一步）
- 战斗：倒地 / 非致命击倒 / 逃跑 / 多难度系数接入 / 自动战斗 AI / 快照字段补全（downed）
- 任务：多失败分支判定引擎 / 条件 JSON 评估 / 技能检定模块留空壳
- 配套：`ConfigValidator` 字段校验（读配置时校验必填字段）
### ⏸ 阶段3 内容扩张
- CSV/JSON 大批量填文本/支线（只改数据不动码）
### ⏸ 阶段4 后期扩展
- ModSupport（CSV 补丁合并 + 文本流式加载）、Multiplayer（事件转发，单机禁用）

> ⚠️ 心声共识：骨架稳定前不堆几百条支线文本；MOD/联机前期碰了必烂尾。

---

## 六、JSON vs CSV 决策（用户 2026-08-28 提问，结论已采纳）

### 两者优缺点
| 维度 | JSON（当前使用） | CSV（蓝图推荐） |
| --- | --- | --- |
| 嵌套结构 | ✅ 原生支持（对象/数组任意嵌套） | ❌ 纯平面，嵌套需把 JSON 塞进单元格或拆多表 |
| 编辑器友好 | ⚠️ 需文本/专用工具，非技术 MOD 作者不友好 | ✅ Excel 直接开，策划/模组作者最爱 |
| 引擎解析 | ✅ Godot 原生 `JSON.parse_string` | ⚠️ 无内置 CSV 解析，需自写或用 `CSV` 资源 |
| 类型推断 | ✅ 数字/布尔/字符串自动保留 | ❌ 全变字符串，需 `int()`/`float()`/`bool()` 手动转 |
| MOD/外部导入 | ⚠️ 合并需程序逻辑 | ✅ 丢一个 CSV 补丁文件即可合并，最契合 Steam 模组 |
| 编码陷阱 | 一般 | ⚠️ UTF-8 BOM（本项目 strings.csv 已踩过坑，需显式处理） |

### 共同使用会不会 BUG / 影响业务或性能？
- **不会污染业务**：只要约定「内存里统一为 Dictionary，JSON 和 CSV 都只是『加载期的不同来源』」。配置层加一个合并器：核心配置走 JSON，MOD/外部补丁走 CSV，加载时统一解析成同一套字典，业务层只认字典、不关心来源。
- **不会出 BUG 的关键纪律**：① 单一事实源——同一张表不能同时由 JSON 和 CSV 定义，冲突时约定「CSV 补丁覆盖/追加 JSON」（明确优先级）；② 类型归一——CSV 读出后必须过一道类型转换，避免 `"18"` 当字符串比大小；③ 编码统一——CSV 一律 UTF-8（无 BOM），加载器做 BOM 剥离；④ 键唯一——合并时检测 key 重复并报错，不让静默覆盖。
- **不影响性能**：JSON/CSV 解析都只在「加载期」发生一次，运行期全在内存字典里查，零差别。百万文本的性能问题靠「按需流式加载」解决（用到某 text_id 才加载该条），与格式无关。

### 采纳结论（写入长期记忆）
- **保留 JSON 作为开发期源格式**（已跑通、嵌套友好、零迁移成本）；
- **新增 CSV↔JSON 合并层**满足蓝图「MOD 提供 CSV 补丁 → 合并解析」需求，不推翻现有 JSON 管线；
- 阶段3 内容扩张时再实际落地 CSV 批量导入 + 流式加载，**阶段1/2 不动格式**。


