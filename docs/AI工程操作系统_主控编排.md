# 武侠江湖 · AI 工程操作系统（总控编排层）

> 本文件是**任务驱动的总控层**，不是又一套角色 Prompt。
> 它把上一版 `docs/提示词系统_全角色闭环自迭代.md` 里的**角色模板**降级为"可被自动调用的能力模块"，
> 新增 L0~L6 七层编排，让"人只说目标，AI 自己决定调谁、怎么查、怎么沉淀、怎么反哺平台"。
>
> **所有事实均来自本工程真实扫描（autoload 注册、EventBus 信号、场景文件、经验库篇目），非通用模板。**

---

## 0. 为什么需要这一层

上一版的问题不是缺角色，而是**角色驱动**：人要先想"我今天该调哪个 Prompt"。
正确形态是**任务驱动**：人只说"我要做什么"，总控自动完成：读状态 → 判模块 → 载经验 → 编排角色 → 正向设计 → 灾难模拟 → 执行 → 审查 → 测试 → 变更记录 → 经验提炼 → 平台反哺。

```
                          ┌──────────────────────┐
                          │   任务总控 AI (本文件)  │
                          └──────────┬───────────┘
              ┌──────────────────────┼──────────────────────┐
              ↓                      ↓                       ↓
        L0 项目身份            L1 结构认知              L2 模块卡
        (固定底座)            (autoload/信号图)        (每模块小脑)
              └──────────────────────┼──────────────────────┘
                                     ↓
                          ┌──────────────────────┐
                          │   L3 任务编排器(主控)   │ ← 唯一入口
                          └──────────┬───────────┘
       ┌──────┬──────┬──────┬──────┬──────┬──────┬──────┐
       ↓      ↓      ↓      ↓      ↓      ↓      ↓      ↓
      PM   架构师 程序员  UI/美工 测试  DevOps 迭代  性能
       └──────┴──────┴──────┴──────┴──────┴──────┴──────┘
                                     ↓
                        L4 执行 → L5 灾难模拟审查 → 测试
                                     ↓
                          L6 经验提炼(E1~E4 / 五维) → 平台反哺
```

---

## L0 · 项目身份层（固定底座，所有任务自动前置）

```
项目：武侠江湖（等距 2.5D 武侠 RPG 单机，实际代码纯 2D）
引擎：Godot 4.7.2，纯 GDScript；平台 Win + 安卓
架构：五层解耦＝ autoload(枢纽) → core(核心) → data(JSON) → services(RefCounted 业务) → scenes(视图) → resources/tests/tools
通信铁律：模块仅允许"公开接口 + EventBus 信号"通信；禁止跨层直接访问；
         业务层禁止直接操作 UI 节点；UI 层禁止直接读业务私有变量；数值全进 JSON(Live-Ops 数据驱动)
主权边界：共享地基冻结；UI/战斗/背包/结缘各有主权；多 AI 并行靠 commit_queue + handoff 板协同
门禁：双闸门——①`--headless --quit` 零 SCRIPT/PARSE/COMPILE ERROR；②`tests/unit/run_all.tscn` 零 ✗(grep ✗==0 且 失败 M==0)
```

**GDScript 4.x 硬规（总控每次必须强制校验）：**
- `Color()` 必须写满 4 参；typed Array 禁 `as Array[String]`；`mini/maxi` 仅 2 参
- 闭包按值捕获值类型；外部配置解析用 `JSON.new()` + `json.parse(txt) != OK`
- **mouse_filter 枚举反直觉**：`STOP=0`(拦截) / `PASS=1` / `IGNORE=2`(穿透)。装饰子节点必须写 `IGNORE(2)`，绝不可写 0
- 纹理压缩：项目出厂 `mode=0`；落地必须 `mode=2`（`tscn_assets.py` 写死 + `compress_textures.py` 扫描改）。取像素必须用 `Image.load_png_from_buffer` 解码源 PNG，**不可对压缩纹理 `get_pixel`**（latent bug）

---

## L1 · 项目结构认知层（真实代码地图）

### 1.1 20 个 autoload 枢纽（`project.godot [autoload]`，全局单例）
| 枢纽 | 文件 | 职责 |
|---|---|---|
| EventBus | `autoload/EventBus.gd` | 全局信号总线（70+ 信号，见 1.2） |
| GameManager | `autoload/GameManager.gd` | 装配中枢（经验库/01） |
| UIManager | `autoload/ui_manager.gd` | 屏幕路由/弹窗收口（`ui_screen_*`、`popup_close_requested`） |
| SaveManager | `autoload/SaveManager.gd` | 存档读写 |
| SaveValidator | `autoload/save_validator.gd` | 存档校验（兼容性） |
| GameState | `autoload/game_state.gd` | 运行时全局状态 |
| ConfigManager | `autoload/ConfigManager.gd` | 配置加载（`config_loaded`/`config_validation_failed`） |
| DifficultyManager | `autoload/difficulty_manager.gd` | 难度（`cmd_set_difficulty`/`notify_difficulty_changed`） |
| WeatherTimeService | `autoload/weather_time_service.gd` | 世界时间天气（`world_*`） |
| AudioManager | `autoload/AudioManager.gd` | 音频 |
| GameManager… | `autoload/game_manager.gd` | — |
| DefeatHandler | `autoload/defeat_handler.gd` | 战败 CG（`notify_defeat_cg`/`notify_player_party_wiped_out`） |
| SettingsManager | `autoload/settings_manager.gd` | 设置 |
| LocalizationManager | `autoload/localization_manager.gd` | 本地化 |
| ErrorHandler | `autoload/error_handler.gd` | 错误上报（`game_error`） |
| TransitionManager | `autoload/transition_manager.gd` | 场景过渡 |
| PatchManager | `core/patch_manager.gd` | 补丁（`patch_applied`） |
| ObjectPool | `services/object_pool.gd` | 对象池（防节点堆积） |
| PerformanceMonitor | `tools/performance_monitor.gd` | 性能监控 |
| (Bootstrap) | `autoload` 引导 | `bootstrap_*` 信号 |

### 1.2 EventBus 真实信号分组（来自 `autoload/EventBus.gd`，编排时按模块检索）
- **背包**：`inventory_item_added/removed`、`inventory_weight_changed`、`inventory_add_overflow`、`item_used`、`item_used_in_battle`
- **战斗**：`combat_started/ended`、`combat_character_died`、`combat_finished(victory,escaped,unit_snapshots)`、`grid_highlight_update`、`grid_unit_moved`、`cmd_start_combat`、`cmd_set_unit_faction`、`cmd_apply_story_buff`、`notify_player_party_wiped_out`、`notify_escape_success/fail`、`notify_defeat_cg`
- **单位状态**：`player_hp_changed/mp_changed/level_up/exp_changed/died`、`unit_downed(is_non_lethal)`
- **能力/装备**：`ability_learned/used`、`combat_skill_equipped`、`equipment_equipped/unequipped/changed`
- **炼丹/锻造/交易**：`alchemy_refined/failed`、`cmd_forge`/`notify_forge_*`、`cmd_buy`/`cmd_sell`/`notify_trade_*`
- **门派**：`cmd_join_sect`/`notify_sect_*`
- **结缘关系**：`bond_affection_changed/level_up/event_triggered`、`bond_gift_given/disliked`、`bond_romance_formed/stage_changed`、`bond_relationship_changed`、`bond_child_born`、`bond_sworn_formed`、`bond_master_set`、`bond_apprentice_taken`、`bond_wedding_started(npc,wedding_type,scene_path)`、`celebration_started`
- **对话**：`dialogue_started/ended`、`dialogue_event_triggered`
- **任务**：`quest_accepted/objective_updated/completed/ready_to_turn_in/turned_in`、`quest_failed`、`quest_phase_changed`、`notify_quest_track_changed`
- **UI**：`ui_screen_opened/closed`、`ui_action_requested`、`popup_close_requested`
- **世界**：`world_day_advanced`、`world_weather_changed`、`world_time_changed`
- **系统**：`game_saved/loaded`、`scene_changed`、`game_error`、`notification_show`、`config_loaded/validation_failed`、`patch_applied`、`bootstrap_*`

### 1.3 场景文件图（真实 .tscn）
- 战斗：`scenes/gameplay/battle/BattleScene.tscn`、`TacticalBattleScene.tscn`、`tactical_test_riverside.tscn`
- 城镇/世界：`scenes/gameplay/town/TownScene.tscn`
- 结缘：`scenes/gameplay/bond/WeddingScene.tscn`、`scenes/ui/screens/bond_romance/BondRomanceScreen.tscn`
- 背包/装备：`scenes/ui/screens/inventory/InventoryScreen.tscn`、`EquipmentScreen.tscn`、`ItemSlot.tscn`
- 经济：`ShopScreen.tscn`、`ForgeScreen.tscn`、`AlchemyScreen.tscn`、`SectScreen.tscn`
- 对话：`scenes/ui/overlays/dialog/DialogOverlay.tscn`
- HUD：`scenes/ui/overlays/hud/Hud.tscn`、`QuestTrackPanel.tscn`、`SkillBarPanel.tscn`、`StatusCardPanel.tscn`、`TopRightMenuPanel.tscn`
- 引导：`scenes/bootstrap/Bootstrap.tscn`
- 弹窗组件：`ConfirmDialog.tscn`、`Tooltip.tscn`、`SaveNameDialog.tscn`、`SaveCard.tscn`

---

## L2 · 模块卡（每模块的"小脑"，编排时自动加载）

> 格式统一：职责 / 文件 / 信号 / 已知 BUG / 扩展点 / 禁止区 / 关联经验库。只列核心模块，其余套用同构。

### 模块卡 · COMBAT（战斗）
- **归属层**：业务服务层（逻辑内核）＋ 视图表现层（`BattleScene`/`TacticalBattleScene`）
- **文件**：`core/combat_event_renderer.gd`、`core/combat_entity_pool.gd`、`scenes/gameplay/battle/*`
- **信号**：`combat_started/ended`、`combat_finished`、`grid_*`、`cmd_start_combat`、`unit_downed`、`combat_character_died`
- **已知 BUG（真实）**：① 战斗→town 掉血崩（回城后 HP 状态未复位/重复结算）；② 战斗结算 `unit_snapshots` 与 GameState 不一致
- **扩展点**：中毒/灼烧等状态异常接入 `unit_downed(is_non_lethal)`；反击系统挂 `combat_character_died` 前序钩子
- **禁止区**：战斗逻辑不得直接 `get_node` 改 HUD 节点；伤害数值必须来自 `data/` JSON
- **关联经验库**：`02_EventBus契约`、`05_战斗系统_逻辑内核与视图接缝`、`06_卡住BUG根因`、`08_静默接缝BUG四层防线`

### 模块卡 · INVENTORY（背包/经济）
- **文件**：`scenes/ui/screens/inventory/*`、`ShopScreen`、`ForgeScreen`、`AlchemyScreen`、`core/item_flags.gd`
- **信号**：`inventory_item_added/removed`、`inventory_add_overflow`、`item_used(_in_battle)`、`cmd_buy/sell`、`cmd_forge`、`alchemy_*`
- **已知 BUG（真实）**：① BUG-04 售卖锁定物（带 `item_flags` 锁定的物品仍能被卖）；② 背包→结缘 `propose` 聘礼跳过锁定校验
- **扩展点**：新道具类型只需加 `item_flags` 位 + JSON 字段，无需改 UI 逻辑
- **禁止区**：背包**不直接改 PlayerState**；战斗用药须经战斗状态结算（`item_used_in_battle` → 战斗场景）
- **关联经验库**：`03_经济系统_事务化资产API`（事务化：扣钱不发货/扣料丢产出必须原子）

### 模块卡 · BOND（结缘/关系）
- **文件**：`scenes/gameplay/bond/*`、`BondRomanceScreen.tscn`、`autoload` 关系状态
- **信号**：`bond_affection_*`、`bond_romance_*`、`bond_wedding_started`、`bond_child_born`、`bond_relationship_changed`
- **已知 BUG（真实）**：① BUG-03 关系双写（两处同时写关系状态，回城后不一致）；② 结缘→背包 休息未推进天数（`world_day_advanced` 未联动）
- **单一真源**：关系状态只一处写，其余经 `bond_relationship_changed` 广播
- **关联经验库**：`04_结缘系统_单一真源与回城编排`

### 模块卡 · DIALOGUE（对话）
- **文件**：`scenes/ui/overlays/dialog/DialogOverlay.tscn`、`data/` 对话 JSON
- **信号**：`dialogue_started/ended`、`dialogue_event_triggered`
- **扩展点**：分支/立绘/配音走 `data/` JSON + `streaming_media_loader.gd`（序列帧/骨骼/Live2D）
- **关联经验库**：`09_可复用模式清单`

### 模块卡 · UI / POPUP（弹窗管理）
- **文件**：`autoload/ui_manager.gd`、`ConfirmDialog.tscn`、`Tooltip.tscn`
- **信号**：`ui_screen_opened/closed`、`popup_close_requested`、`ui_action_requested`
- **铁律**：弹窗自身**不销毁自己**，`request_close` → UIManager 统一收口（隐藏缓存/销毁）；装饰子节点 `mouse_filter=IGNORE(2)`
- **关联经验库**：`08_静默接缝BUG四层防线`（lint_mouse_filter.py + test_ui_mouse_filter.gd 双闸门）

---

## L3 · 任务总控 Prompt（唯一入口，复制即用）

```text
你是【武侠江湖】项目的 AI 工程总控。不要直接回答问题，先按流程组织工程角色完成任务。
本次任务：{只写"我要做什么"，例如"增加中毒状态" / "修复背包拖拽错位" / "婚礼后回城天数不推进"}

# 阶段 0 · 读取项目状态（自动，不要求人粘贴）
- 加载本文件 L0/L1/L2（项目身份/结构图/模块卡）
- 加载经验库：docs/经验库/00~10（按任务关键词检索相关篇目，不要全量塞入）
- 加载历史 BUG：docs/代码审计报告_2026-09-02.md 的 BUG-01~33（检索与本次模块相关的）
- 加载近期变更：docs/更改日志.md / 变更通告_*.md / 当前 git diff
- 若信息不足，标记【信息缺失】，禁止编造项目结构

# 阶段 1 · 任务定位
1. 一级模块？ 2. 二级模块？ 3. 架构层？ 4. 涉及文件（带路径）？
5. 依赖哪些模块？ 6. 哪些旧功能可能受影响？ 7. 历史是否有同类问题？
8. 命中哪些经验库篇目 / 哪些 BUG 编号？

# 阶段 2 · 自动角色编排（只选需要的）
可选角色：PM / 架构师 / 程序员 / UI·美工 / 测试 / DevOps / 迭代 / 性能
每项给：【角色】【为何需要】【负责什么】【依赖谁】。不需要的不要强行参与。

# 阶段 3 · 正向设计
需求 → 模块 → 子功能 → 数据结构(JSON字段) → 接口 → 事件(引用 L1.2 真实信号) →
核心流程 → 文件变更清单 → 实现步骤 → 验收标准。
强制遵守 L0 铁律（五层解耦 / 数据驱动 / mouse_filter / Color 四参 / 纹理 mode=2）。

# 阶段 4 · 灾难模拟（逆向推演，重点）
假设本方案已上线且"坏了"，倒推为什么坏：
- 逐链路追问：哪一步重复触发？哪一步可能无限循环？哪一步引用已 queue_free 的节点？
  哪一步返回 null？哪一步重复结算？哪一步触发两个死亡/双写事件？
- 输出【风险】【触发条件】【影响】【概率】【预防】【测试点】

# 阶段 5 · 执行（变更清单）
每条修改写：【文件】【位置】【原因】【内容】【影响模块】【潜在副作用】。
禁止无关重构；禁止改任务外代码；动态节点必须明确生命周期(queue_free / ObjectPool)。

# 阶段 6 · 自我审查
以独立审查员身份重查：架构/数据/业务/实体/事件/UI/性能/异常/资源生命周期/兼容性/测试。
不得因代码由自己生成就默认正确。重点扫：_process 重逻辑、硬编码、跨层访问、节点未释放。

# 阶段 7 · 测试
冒烟（核心功能）/ 边界（空/最大/最小/重复/非法/快速连点/中途退出/切场景）/ 回归（受影响旧功能列表）。

# 阶段 8 · 变更记录
【Change】版本 / 模块 / 修改文件 / 内容 / 原因 / 影响 / 测试 / 风险。
同步写入 docs/更改日志.md，多 AI 并行则经 commit_queue + handoff 板署名。

# 阶段 9 · 经验提炼（见 L6 等级与五维）
无则【无新增经验】；有则按 E1~E4 + 五维格式输出，并指明落入哪个真实文件。

# 阶段 10 · 平台反哺
该经验是否跨项目复用？属于【模板/脚手架/Lint规则/自动检查/UI组件/代码生成/测试工具/平台工作流】？
输出：平台能力 / 解决什么 / 当前人工成本 / 自动化后成本 / 优先级。

# 最终输出顺序
1 定位 → 2 影响范围 → 3 角色编排 → 4 正向设计 → 5 逆向风险 →
6 修改清单 → 7 自我审查 → 8 测试 → 9 变更记录 → 10 新经验 → 11 平台反哺
```

---

## L4 · 执行层：角色能力模块（被总控调用，不复用则废弃）

总控在阶段 2 决定调用哪些。各角色的**完整正向+逆向模板**见 `docs/提示词系统_全角色闭环自迭代.md` 第 3 章（3.1 PM / 3.2 架构 / 3.3 程序 / 3.4 UI / 3.5 美工 / 3.6 运维 / 3.7 复盘）。
总控调用时，把本文件 L0/L1/L2 + 命中的经验库篇目 + 命中的 BUG 编号**作为上下文注入**对应角色块，角色块末尾仍强制输出 `【K】` 沉淀条目（其归档目标见 L6）。

---

## L5 · 灾难模拟审查层（实例：战斗中毒状态）

> 任务："增加中毒（每回合扣血，可驱散）"。总控已定位到 COMBAT 模块卡。

倒推链路（基于真实信号）：
```
cmd_start_combat → combat_started → grid_unit_moved(动画)
 → combat_character_died 结算 → unit_downed(is_non_lethal)
   → combat_finished(victory,escaped,unit_snapshots)
     → EventBus → HUD(player_hp_changed) / UIManager
```
灾难假设与追问：
- **重复结算**：中毒扣血若写在 `_process` 而非回合事件，会每帧扣 → 必须挂在回合边界信号（非帧回调）。→ 命中经验库/06、K001(帧回调重逻辑)。
- **已释放节点**：中毒飘字/图标若 `add_child` 后无 `queue_free`，连续战斗 100 次节点堆积 → 必须用 `ObjectPool` 或明确销毁。→ 命中 K005。
- **存档兼容**：中毒状态若新增字段未走 `SaveValidator`，旧档读档崩溃 → 必须在 `data/` 加字段 + 校验。→ 命中 L0 门禁。
- **双写/回城**：中毒若在战斗与 GameState 两处写，回城 town 掉血崩复现 → 单一真源，战斗只 emit，GameState 监听。→ 命中 BUG-战斗→town 掉血崩。
- **驱散边界**：驱散触发 `unit_downed`？中毒致死是否走 `combat_character_died` 一次且仅一次？→ 防双死亡事件。

---

## L6 · 经验提炼引擎（E1~E4 等级 + 五维知识分类）

### 6.1 等级（决定沉淀到哪、是否平台化）
- **E1 项目经验**：仅本项目有用（如"某 NPC 场景不能直接访问 CombatManager"）→ 落 `docs/更改日志.md` 或模块卡
- **E2 模块经验**：同类模块通用（如"所有动态战斗特效必须统一生命周期回收"）→ 落对应 `经验库/0x` 篇
- **E3 工程经验**：跨项目通用（如"临时节点必须有明确生命周期"）→ 落 `经验库/06` 或 `09_可复用模式清单`
- **E4 平台能力**：不应再靠人记，应变成插件/Lint/脚手架/自动检查 → 落 `经验库/10` + 平台代码（`tools/` 或 `desktop_studio`）

### 6.2 五维知识分类 → 映射到本工程真实文件
| 维度 | 落入真实文件 | 说明 |
|---|---|---|
| Project | `docs/经验库/00_架构铁律与分层.md`、`MEMORY.md`、`docs/项目经验白皮书.md` | 项目级铁律/分层 |
| Module | `docs/经验库/02~05`（按模块）、各模块卡 | 模块专属信号/接口/已知 BUG |
| Engineering | `docs/经验库/06_卡住BUG速查`、`07_双闸门`、`08_静默接缝`、`09_可复用模式` | 跨模块工程规范 |
| AntiPattern | `docs/代码审计报告_2026-09-02.md` 的 **BUG-01~33**、`经验库/06` | 已发生的具体故障 |
| Platform | `docs/经验库/10_平台连接器三段`、`tools/desktop_studio` `/api/experience` | 可平台化的能力 |

### 6.3 沉淀条目格式（保留你习惯的 `【K】`，强制带"归档目标"）
```
【K{自增}】｜等级[E1/E2/E3/E4]｜维度[Project/Module/Engineering/AntiPattern/Platform]
｜分类[BUG经验/编码规范/UI踩坑/架构风险/协同规范/性能优化]
｜现象｜根因｜修复/实现手段｜预防手段｜测试校验点
｜关联模块[ combat/inventory/bond/... ]｜命中BUG[ BUG-xx ]
｜归档目标[ 经验库/06 | 代码审计报告 BUG-xx | MEMORY.md | 经验库/10 ]
｜建议升级平台能力[ Lint规则/自动检查/模板/插件 ]（仅 E3/E4 填）
```

### 6.4 闭环自动载回（无需飞书，平台已具备）
- 经验落 `经验库/0x` 后，工作室平台 `desktop_studio` 的 `/api/experience` + `_exp_enrich()` 会实时富化 `knowledge.refs`（角色/模块分面、BUG 号提取、标签云）。
- 下一轮任务：总控阶段 0 直接经平台 API 按模块/关键词**检索相关条目注入**，不再全量粘贴 → 解决"知识鲸鱼"膨胀问题。
- 多 AI 并行：新经验先写 `handoff.py` 隐患传递板，再合并入 `经验库`，避免冲突。

---

## 平台反哺层（经验 → 平台能力 的判定与落地）

判定树（阶段 10 执行）：
```
经验命中 E3/E4？
 ├─ 是 → 属哪类平台能力？
 │    ├─ Lint规则   → 扩展 tools/lint_mouse_filter.py / 新增 lint（如"Node.new 必须有 queue_free"）
 │    ├─ 自动检查   → 接入 desktop_studio /api/gate0（整合 4 个静态守卫）
 │    ├─ 模板       → 落 tools/desktop_studio 模块模板资产库（战斗/对话/背包/弹窗）
 │    ├─ 插件       → 落 经验库/10 + manifest.yaml(Project Adapter)
 │    └─ 工作流     → 派单看板 tab / 角色化提示词组装器
 └─ 否 → 仅落经验库对应篇目，下一轮自动载回
```
**平台现有可吸收能力（真实）**：`/api/experience` 富化检索、`ai_context`(新 AI 秒懂架构)、`reskin`(换皮零成本)、`knowledge`(经验复用)、`manifest.yaml`(Domain×Adapter 二维解耦)、`security_selftest 15 断言`、`deploy.py`(6 副本同步)。缺口见 `提示词系统_全角色闭环自迭代.md` 第四章（P0：写 deploy.py 机器化副本同步 + 整合 /api/gate0；P1：派单看板 + 语义经验检索）。

---

## 建议落地目录（增量，不推翻现有）
```
docs/
 ├─ 提示词系统_全角色闭环自迭代.md   ← 角色能力模块库（L4 引用）
 ├─ AI工程操作系统_主控编排.md        ← 本文件（L0~L6 总控）
 ├─ 经验库/00~10                     ← 五维知识真源（Project/Module/Engineering/Platform）
 ├─ 代码审计报告_*.md                ← AntiPattern(BUG-01~33)
 └─ 更改日志.md / 变更通告_*.md       ← Change 层
```
> 不新建 `AI_ENGINEERING_OS/` 巨型目录——本项目铁律是"不污染、增量演进"，上述即在现有 `docs/` 内闭环。

---

## 使用范式（人只说目标）
1. 复制 **L3 任务总控 Prompt**，把 `{只写"我要做什么"}` 填实（其余上下文让总控自动读，不要人贴）。
2. 发送 → 总控自动：读 L0/L1/L2 + 检索经验库/BUG + 编排角色 + 输出 1~11。
3. 末尾 `【K】` 条目：人工（或脚本）合并入对应 `经验库/0x` 或 `代码审计报告`，下一轮平台自动载回。
4. 周期（每月）：把 E3/E4 条目经"平台反哺层"升级为 Lint/模板/插件，趋近"同一种 BUG 没机会再出现"。

> 这不再是 Prompt 库，而是**工程生产流水线**：人提目标 → AI 判调用 → 正逆双推 → 执行审查 → 沉淀反哺。
> 真正的 0 成本 = 经验→Prompt→自动检查→平台能力→默认正确。

---

## 反哺留存铁律（Connect 不持有 · Learn 必须留存）

**平台本质=连接器而非容器**：不持有任何工程项目数据（源码/美术/配置不进平台；项目数据始终在各自工程仓库）。

**但——从工程学习到的经验与数据反哺必须存留**：
- 经验库（`docs/经验库/00~10`）、模块卡（`docs/模块卡/*`）、更改日志（`docs/更改日志.md`）、代码审计报告（`docs/代码审计报告_*.md`）均在 `docs/` 内，并 **git 进仓库**随工程演进；
- 周期经「平台反哺层」把 E3/E4 条目升级为 Lint 规则 / 模板 / 插件 / 脚手架，凝练反哺工作室平台（如 `lint_mouse_filter.py`、`/api/gate0`、`/api/experience` 富化检索均已从项目经验反哺为平台能力）；
- 多 AI 并行时，新经验先经 `handoff.py` 隐患传递板，再合并入 `经验库`，避免冲突。

> **连接器范式与留存反哺不矛盾**：平台不替工程存数据，但工程沉淀的「方法论资产」必须留存并随仓库演进——否则每个新项目都从零开始，永远无法趋近 0 成本。
