# 12 Quest / Dialogue / Story 施工图 V1.4 修复版

> 状态：**FROZEN**（2026-09-06 用户批准；可在该域实施）
> 依据：宪法 0-C.15 / §171 / L677 回放要素 / L2034-2065 State Owner 表；01 §50 Quest、§51 Dialogue、§52 Story、§80 Story Editor、§110 VS-002；02 Condition·Effect·Command·ErrorCode 契约、O-1 开放问题；03 ID·SemVer·本地化·资产 ID 契约、Reference 环检测；04 Gate Registry；05 ShardCache·Index·C-3；06 _global_flags→World-Story、_quest_phase→CampaignState；07 TimeConsumer 消费注册制；08 ModifyRelationshipEffect；09 add_item 事务；10 EC-R11 货币 Mutation。
> 冻结日期：2026-09-05。本域是 **P3 整改成果最集中**的域（统一条件 DSL / handler 注册表 / GameFacts 去定位器均已落地），本图职责：**condition 已归一，effect 也归一**。

---

## 0. 编号命名空间声明

本图门禁编号一律使用 **LN 逻辑编号 = 宪法 §88 GATE01~20 ∪ 01 §127 GATE21~32**（04 §2 政策，T-1 已追认 2026-09-06，见 ADR_INDEX §2）；不裸引物理槽位号。

---

## 1. 定位

> **V1.4 修复版总注**：本图随宪法 V1.4（ADR-0005）与 01 图 V1.4 修复版同步升版——①宪法条款号零漂移，正文「宪法 §N / 0-C.x / 0-F.x」引用全部有效；②RULE 001 放软：Domain 经白名单 Adapter/Boundary 触达 Godot 属合法协作（判据=0-E.3/GATE15，白名单升表随 ACR）；③本图冻结契约与冻结物版本零变化，V1.2 原稿保留（§171 收编不丢弃）。域内衔接：TimeConsumer 分相消费范式与 0-B.12 事件语义对齐；condition/effect 归一等五类收编已落地，QD-R 面零变化。

任务/对话/剧情是**内容驱动的中枢域**：所有跨模块「副作用」都从这里发起（发奖、改旗标、加好感、开战斗）。01 §50/§51/§52 给出的形状很明确——**奖励走 Effect、Dialogue 只产 Command/Effect、Story 只组合不重定义**。现状条件侧已经统一（`core/condition.gd` 三方言归一），**副作用侧却有五种形态并存**，这是本图要收口的主战场。

**本图负责**：Quest 六件套（含补齐 Branch）、Dialogue Runtime Graph 契约、Story 组合层级、副作用 Effect 统一、事件消费分相、旗标 Owner 收口。
**本图不负责**：条件求值器本体（02/`core/condition.gd`，已冻结）、旗标存储底座（GameState，迁移期 facade 保留）、战斗快照格式（11）、好感规则（08）。

---

## 2. 现状盘点（2026-09-05 机器实扫）

### 2.1 已有资产（§171：升级不丢弃）

| 资产 | 位置 | 行数 | 状态 |
| --- | --- | --- | --- |
| QuestService（接取/推进/交付/发奖） | `services/quest/quest_service.gd` | 262 | P3 前置门 fail-closed + P3-c 目标/奖励 handler 注册表 + P5 经 GameFacts 去定位器；订阅 combat_finished 快照（「蓝图铁律」注释） |
| QuestGraph（节点图解释器） | `services/quest/quest_graph.gd` | 179 | end/choice/flag_check + dialog/battle/give_item 触发型（action 交 handler 钩子）；条件委托 ConditionService；_MemStore 鸭子测试存储 |
| FlagStore（全局旗标门面） | `services/quest/flag_store.gd` | 54 | favor:/progress: 前缀常量；好感唯一真源=BondService 已落（08 咬合） |
| GameFacts 适配器 | `services/quest/facts.gd` | 60 | 02 契约落点：查询收敛鸭子接口 + 写入侧去服务定位器 |
| DialogueService（数据层+会话状态机） | `services/dialogue/dialogue_service.gd` | 298 | 编译缓存 + pin/unpin 分片 + 条件预检缓存 1s + DSL 三方言归一 + 会话隔离 |
| DialogueEventExecutor | `services/dialogue/dialogue_event_executor.gd` | 126 | P3-b CommandDispatcher 注册制 + 老 trigger_events match 并存 |
| 配置 | `quests/quests.json`、`dialogs/dialogue_events.json`、`npcs/dialogs/` 分片（05 已扫：13 shards、npc_id 全空） | — | — |
| 信号面 | quest_* 7 个 + dialogue_* 3 个 | — | reason String 形态待 ErrorCode 化 |

### 2.2 实锤缺陷（P-Q1~P-Q12，全部扫描所得）

- **P-Q1【P0·死命令】** `dialogue_event_executor._complete_quest` L125 以 `has_method("complete_quest")` 探测后调用——**quest_service 根本没有该方法**（只有 `turn_in`）→ 对话里配 `quest_complete` 命令/事件**静默无效**（dialogue_events.json `_doc` 还在宣传该效果类型）。
- **P-Q2【回调重入链】** `_complete → auto_complete → turn_in → 奖励 add_item → inventory_item_added → _on_inventory_added → 遍历全部任务推进 give_item 目标`——任务完成瞬间发的奖励物品又会触发其他任务目标同步推进；事件回调内同步重入，无分相/入队。
- **P-Q3【进度双真源】** `facts.gd` L28 自认：「QuestService 的 objectives_progress 是另一套（P4 状态所有权时归一），此处不读它」——`objectives_progress` 字典 vs `progress:<quest_id>` 旗标并存，且旗标有三个写入口（FlagStore.set_progress / quest_graph ops / then_set 链）。
- **P-Q4【奖励发钱绕 Mutation】** `facts.add_silver` L52 `player_state.silver += amount` 直改字段——**不发 player_money_changed、无 Journal 留痕**（10 EC-R11 同源违例：任务奖励是货币流入第四端）。
- **P-Q5【副作用五形态并存】** ① quest_service `_reward_handlers`（Callable 注册表）；② quest_graph `_apply` ops（flag_set/favor_add/progress_set/emit_event 微内核）；③ 行内命令字符串协议（`"quest_accept:xxx"` 经 CommandDispatcher）；④ 老 `trigger_events` 查表 + `_apply_effect` match；⑤ 01 §50/§51 要求的 Effect/Command 体系。五套语义重叠、归一无期（注释自认「P3 统一 CommandDispatcher 时归一」）。
- **P-Q6【旗标跨域直写】** executor L26 `FlagStore.new().set_flag(key, val)`（临时对象直写 GameState 全局旗标）、quest `then_set` 直写 `_facts.set_flag`——**任意 key 无域校验**；06 已冻结 `_global_flags` Owner=World-Story，写入口未收口。
- **P-Q7【Quest State Owner 三分裂】** active/completed/tracked 在 QuestService、quest_phase 在 GameState（06 已定归 CampaignState）、progress 在旗标——01 §50「QuestState」无统一 Owner。
- **P-Q8【Branch 缺失】** 01 §50 六件套含 Branch——quests.json 无 branch 字段；`completed_quests` 存档只存 `keys()`（quest_service L247），**分支选择与 QuestGraph endings 结局不入档**，读档后剧情分支事实丢失。
- **P-Q9【ID/版本违例】** 任务 ID `q_bandit_001`（应 `quest_` 域）；战斗引用 `demo_battle` 裸名（`battle_bandit_001` 合规）；旗标键 `plot_advance` / `nv_flag_*` 无域规范；`dialogue_events.json` version `"1.0"` 违 03 SemVer 三段式；`desc` 中文内联（违 03 本地化 key 契约）。
- **P-Q10【演出落 services 层】** executor `_shake` 直接 `get_tree/viewport/camera/create_tween`操纵相机 + `randf_range`；`_play_sfx` `ResourceLoader.exists` 直查——services 层持 Node 演出 + 资产路径直存（03 C-R13 / 11 AB-R03 同族）。
- **P-Q11【双通道并存+隐式顺序】** 行内 `effects`（新协议）与 `trigger_events`（老协议）同场；`_present_current` 先 trigger_events 后 effects 的顺序无文档化契约。
- **P-Q12【零散】** tracked 上限 5 魔法数（L37）；`fail_quest` reason 字符串字面量 match（违 02 ErrorCode）；quest_graph `emit_event` op 只写 log 不真发（占位）；MAX_STEPS=800 是运行期防环兜底、构建期无拓扑环检测（03 Reference 契约咬合）。

### 2.3 已达标项（冻结确认，防退化）

- 条件侧三方言归一完成（flag/favor/progress 键值对 + 对话 kind 风格 + quest_graph 委托 ConditionService）；unknown 语义两态明确（任务 fail-closed / 对话 unknown_true）。
- 战斗只发快照事件、任务订阅推进——「战斗模块不直接被调用」蓝图铁律达成（11 combat_finished 咬合）。
- 对话编译缓存 + pin/unpin + 会话隔离 + 防环 guard——05 ShardCache 机制的先行实现。
- 好感读写唯一真源=BondService（FlagStore P4 已落）。

---

## 3. 冻结契约

### QD-1 Quest 六件套（01 §50 全词落位）

- **QuestDefinition**（quests.json 收编归 05 Pack）：`{ id, name_key, desc_key, type(main|side|...), prerequisites, objectives[], rewards, then_set, auto_complete, branch? }`。
- **QuestState**：Owner 统一归 Quest 模块——active/completed/tracked 三字典之外，**quest_phase 迁入**（06 已定 CampaignState 为存档 Owner、Quest 模块为逻辑 Owner，迁移映射见 §4）。
- **Objective**：类型注册表冻结（现 `battle` / `give_item` 两类 + 显式 `type` 键优先的推断规则）；新增 flag/talk 类 = 注册 handler，零核心改动。
- **ObjectiveState/Progress**：`objectives_progress` = **唯一进度真源**（P-Q3 收口）；进度语义冻结：battle 类增量（_progress）、give_item 类绝对值同步（_sync_progress，随持有量增减可回退）；`progress:<qid>` 旗标降级为 QuestGraph 引擎内部通信，禁作跨模块进度事实源。
- **Branch（补齐）**：QuestState 增 `branch_choices` + `ending`；`completed_quests` 存档升级为 `{quest_id, ending, branches}`（P-Q8 收口；旧档裸 key 读兼容降级）。
- **QuestCompletedEvent → Reward Effect** 顺序冻结（01 §50 原文链）。

### QD-2 副作用统一 Effect 体系（P-Q5 收口，01 §50/§51 落地）

- **一套 Effect 注册表**（02 Effect 契约的 GDScript 落地，宿主裁决见开放问题 QD-1）：
  - `RewardEffect`：exp / silver / items / abilities（现四类 handler 收编；silver 必经 Money Mutation + MoneyChangedEvent——P-Q4 收口，10 EC-R11 咬合；items 必经 09 add_item 事务带 `quest:<id>` 留痕）；
  - `StoryFlagEffect`：flag_set → **SetStoryFlagCommand**（P-Q6 收口，见 QD-4）；
  - `RelationshipEffect`：favor_add → 08 ModifyRelationshipEffect 收编（禁再走 FlagStore favor 兜底写）；
  - `ProgressEffect`：quest 接受/完成/推进（quest_accept / quest_complete / turn_in 映射——**P-Q1 死命令修复：complete → turn_in 链路接通**）；
  - `PresentationEffect`：sfx / shake → 交表现层执行器（P-Q10 收口，services 只产指令不碰相机）。
- **双通道归一**：行内 `effects` 为新协议（保留字符串 DSL 作内容侧书写格式，执行落 Effect 注册表）；`trigger_events` 老协议退役映射（dialogue_events.json 效果表翻译为 Effect 配置，一版兼容后移除）；执行顺序显式冻结：**行 effects 先、选项 effects 次之、trigger_events 兼容期最后**。
- 禁新增第六种副作用形态（新 op/match/私造微内核一律拒绝，AB-R08/GATE24 同源）。

### QD-3 Dialogue 契约（01 §51 落地）

- **Runtime Graph 四元组冻结**：`DialogueGraph → DialogueNode → DialogueChoice → Condition → Command/Effect`（现状结构达标）。
- **Dialogue 禁直改 Relationship / Quest / Inventory / Faction**（01 §51 原文）：现 `quest_accept` 直调、set_flag 直写全部改为产 Effect/Command（QD-2 落地后自然达成）；对话侧服务内禁出现对四域服务的直接写调用（QD-R02 机器化）。
- **会话机制冻结**：编译缓存（dialog_id → {lines, index}）+ pin/unpin 分片锁定 + 条件预检缓存 1s TTL + 会话终止清缓存——05 ShardCache 咬合（pin 引用计数语义一致）；`resolve_for_npc` 三级解析顺序（hint → npc_id → npc.dialog_id）冻结。
- **分片 npc_id 补全**归 Dialogue 主权（05 C-3 复述）；`voice`/立绘字段迁移 Asset ID（03 C-R13，Phase4 随 GATE17）。
- 条件缓存键 `(kind|arg|npc)` 冻结；缓存仅作性能优化，**条件事实源恒为实时求值**（缓存失效不改变语义，测试可关）。

### QD-4 Story 层与旗标 Owner（01 §52 + 06 咬合）

- **组合层级冻结**：Story → Arc → Chapter → Quest / Dialogue / Event / Scene；**Story 不重新定义 Condition / Command / Effect / Event，而组合已有能力**（01 §52 原文）；Story Editor 挂 §80（产出物即 Quest/Dialogue Definition，无独立运行时）。
- **旗标唯一写入口 = SetStoryFlagCommand**（World-Story Owner 校验）：键域白名单冻结 `story_*` / `plot_*`（`nv_flag_*` 等历史键入退役迁移映射）；FlagStore 降级为 Owner 底座 facade（读写签名保留，Owner 落位 Phase3）。
- **quest_phase = Chapter 进度**：CampaignState 存档 + Quest 模块逻辑（06 State Owner 六行咬合）；`quest_phase_changed` 信号保留。
- Chapter 推进条件 = 组合已有 Condition（禁私造章节判定 DSL）。

### QD-5 事件消费分相（07 TimeConsumer 同款，P-Q2 收口）

- 任务目标推进消费**注册制 + 分相处理**：battle_finished / inventory_item_added 等入队，帧末统一 dispatch（禁回调内同步重入推进——完成→交付→发奖→再推进链拆相）；消费顺序冻结：**先目标推进、后完成判定、最后奖励发放**。
- 奖励发放产生的次级事件（add_item 等）天然落入下一相，杜绝同帧递归。
- QuestGraph `emit_event` op 接真 EventBus（P-Q12 占位收口）。

### QD-6 确定性、留痕与死命令防线

- `fail_quest` reason → ErrorCode 常量（FAIL_DEAD_NPC / FAIL_ESCAPED / FAILED）；`quest_failed(reason: String)` 信号升级 ErrorCode（02 契约）。
- 图环检测：构建期挂 GATE07 拓扑环检测（03 Reference 契约扩 dialogue/quest 图）；MAX_STEPS=800 保留为运行期兜底。
- **死命令禁令（P-Q1 教训）**：注册命令/效果类型必须端到端可达（契约测试：dialogue_events.json 与 effects 协议中每个 type/命令各跑一条最小用例）；`has_method` 探测型静默失败禁用（改为显式注册缺失即 FATAL）。
- 任务/对话关键变迁（接取/完成/交付/分支选择/结局）留 Command 足迹进回放（宪法 L677）。

### QD-7 Enforcement 矩阵

见 §5。

---

## 4. 迁移映射表（绞杀者，禁一次性大改）

| 现有资产 | 目标 | 阶段 |
| --- | --- | --- |
| `_reward_handlers` / quest_graph `_apply` ops / 行内命令 / `_apply_effect` match | 统一 Effect 注册表五类（QD-2） | Phase2 |
| `facts.add_silver` 直改 | Money Mutation（add_money）+ 事件 | Phase2（随 10 EC-R11） |
| `_complete_quest` has_method 探测 | turn_in 直连 + 死命令契约测试 | Phase2（P0 先行） |
| 事件回调同步重入 | 分相队列（帧末 dispatch） | Phase2 |
| `progress:<qid>` 旗标（跨模块语义） | objectives_progress 唯一真源（引擎内部旗标保留） | Phase4（facts.gd L28 自认 P4） |
| quest_phase GameState → CampaignState | 06 State Owner 六行同步迁移 | Phase3 |
| `completed` 裸 keys 存档 | {quest_id, ending, branches}（旧档降级兼容） | Phase2 |
| trigger_events 老协议 | Effect 配置翻译 + 一版兼容退役 | Phase4 |
| `q_bandit_001` / `demo_battle` / `nv_flag_*` 键 | `quest_` 域重映射 + 旗标键白名单（`_retired_ids.json`） | Phase4 |
| executor `_shake/_play_sfx` 演出 | PresentationEffect → 表现层执行器 | Phase2 |
| voice/立绘路径直存 | Asset ID（GATE17） | Phase4 |

---

## 5. Enforcement 矩阵（QD-R01~R12，E0 = 0）

| 规则 | 内容 | 载体（LN Gate） | 级 |
| --- | --- | --- | --- |
| QD-R01 | Quest 六件套词面齐备（含 Branch 补齐、ending 入档） | GATE06 schema validator | E3 |
| QD-R02 | Dialogue 域禁直写 Relationship/Quest/Inventory/Faction（服务内禁 `quest_service.accept` 类直调面之外的四域写调用；白名单基线） | GATE12 arch_lint + GATE24 | E3 |
| QD-R03 | 副作用唯一形态 = Effect 注册表；禁新增私造 op / match / 微内核 | GATE24 契约漂移 | E3 |
| QD-R04 | 任务进度唯一真源 `objectives_progress`；`progress:` 旗标禁新增跨模块读写 | GATE25 state_owner | E3 |
| QD-R05 | 奖励必走 Effect：货币经 Money Mutation、物品经 09 事务带 `quest:<id>` 留痕（禁 `silver +=` 类直改复活） | GATE25 + 10 EC-R11 同源扫描 | E3 |
| QD-R06 | `_global_flags` 写入唯一入口 SetStoryFlagCommand + 键域白名单（story_/plot_） | GATE25 | E3 |
| QD-R07 | 任务事件消费分相（回调禁同步重入推进；完成→奖励链禁同帧递归） | GATE28 命令序 + 契约测试 | E2 |
| QD-R08 | 任务/对话/旗标 ID 与键域白名单（quest_/dlg_/story_/plot_）+ SemVer 三段式 | GATE07 + GATE06 | E3 |
| QD-R09 | 死命令禁令：effects/trigger_events 每个命令与效果类型端到端可达（注册缺失=FATAL，has_method 探测禁用） | GATE02 契约用例生成 | E2 |
| QD-R10 | services 层禁 Node 演出（Tween/相机/ResourceLoader 直查；演出交 PresentationEffect） | GATE05 / GATE22 arch_lint | E3 |
| QD-R11 | completed 存档含 ending + branch_choices；旧档裸 key 降级读兼容 | GATE08 save_header/roundtrip | E2 |
| QD-R12 | quest/dialogue 图构建期拓扑环检测；MAX_STEPS 仅运行期兜底 | GATE07 扩展 | E3 |

> E0 占比 0%：每条规则都有扫描器或测试兜底，无「纯自觉」条款。

---

## 6. Freeze 清单（批准后冻结，改动需走 ACR）

- 文件面：`services/quest/quest_service·quest_graph·flag_store·facts.gd`、`services/dialogue/dialogue_service·dialogue_event_executor.gd`、`data/configs/quests/quests.json`、`data/configs/dialogs/dialogue_events.json`、`npcs/dialogs/` 分片协议、EventBus quest_*/dialogue_* 10 信号。
- 契约面：QD-1~QD-6 全部条款；QD-R01~R12 矩阵；Effect 五类注册表；旗标键域白名单；执行顺序（effects → trigger_events 兼容尾）。
- 跨图咬合面：02（Effect/Command 契约 + O-1 行内命令归一）、03（ID/SemVer/环检测）、05（ShardCache/Pack/分片 npc_id）、06（World-Story Owner/CampaignState）、07（分相消费）、08（RelationshipEffect）、09（物品事务）、10（Money Mutation）、11（combat_finished 消费端）。

---

## 7. DoD（Definition of Done，7 条）

1. 本图全部 QD-* 冻结项经用户批准升 FROZEN；
2. QD-R01~R12 每条有指定载体且实际落地，E0 = 0；
3. P-Q1 死命令修复 + 九类命令/效果端到端契约用例进 GATE02 常绿（QD-R09）；
4. P-Q1~P-Q12 每项在迁移映射表有对应收编行，旧资产升级不丢弃（§171）；
5. Effect 注册表五类全部有单测；分相队列重入用例（完成任务发奖不再同帧触发他任务推进）常绿；
6. quests/dialogue_events 经 GATE06 零错误、GATE07 零悬空（含 quest_ 域迁移名单与图环检测）；
7. 双闸门绿（GATE01/GATE02）且 `verify_all.py` 全绿；旧档读入 ending 缺省降级不拒读（GATE08/09）。

---

## 8. 开放问题（需用户 / ADR 裁决，AI 不自决）

> **【已追认 2026-09-06】** 用户整批复核：以下 QD-1~QD-4 全部按推荐执行（QD-2 与 02 O-1 联动：对话行内命令同批归入 ScriptDirective）。本节保留原文供审计。

- **QD-1 Effect 注册表宿主**：Quest/Dialogue 域本地注册表（现 handler 模式扩容为域级 EffectRegistry，**推荐**——绞杀者零迁移）vs 02 Kernel 全局 EffectRegistry（跨域共享但要动 Kernel 冻结契约）。推荐理由：五类 Effect 的 handler 本就分布各域（Reward 在 Quest、Presentation 在表现层），域内注册 + 02 契约约束签名即可，无需 Kernel 新增全局单例。
- **QD-2 行内命令字符串协议归宿**：保留 `"quest_accept:xxx"` 字符串 DSL 作内容书写格式 + 执行映射 Effect（**推荐**——内容侧可读性好、工作室剧情台已按此产出）vs 改结构化 JSON effects 对象。**与 02 O-1（command_dispatcher 字符串路由）联动裁决**：若 O-1 定 ScriptDirective，对话行内命令同批归入。
- **QD-3 quest_phase 迁移时机**：随 06 State Owner 六行 Phase2/Phase3 迁（**推荐随 Phase3 装配收敛**，GameState 收编同批）vs Phase4 单独迁。
- **QD-4 trigger_events 退役节奏**：一版双协议兼容后 Phase4 移除（**推荐**——dlg_tutorial 等存量分片在用，翻译脚本 + 基线防新增）vs 立即冻结禁扩展但永不删除。

---

## 9. 一句话总纲

**任务发奖、对话改世界、剧情推章节——五支笔并成一支 Effect；condition 已经归一，effect 归一后，这个域才真正「内容驱动、核心不动」。**

---

## 10. 关联文档

- `01_总体架构施工图_V1.4修复版.md` §50 Quest / §51 Dialogue / §52 Story / §80 Story Editor / §110 VS-002 / §127 Gate 基线
- `02_Domain_Kernel施工图_V1.4修复版.md` Condition·Effect·Command 契约 / ErrorCode / O-1 开放问题
- `03_Contract_Schema_DataContract施工图_V1.4修复版.md` ID 白名单 / SemVer / 本地化 key / 资产 ID / Reference 环检测
- `04_Test_Infrastructure_Architecture_Gate施工图_V1.4修复版.md` Gate Registry / 契约测试六类
- `05_Content_Registry_Content_Pipeline施工图_V1.4修复版.md` ShardCache·pin / Index / Pack 收编 / C-3 分片 npc_id
- `06_Actor_Player_NPC施工图_V1.4修复版.md` _global_flags→World-Story / _quest_phase→CampaignState
- `07_World_Time_Schedule施工图_V1.4修复版.md` TimeConsumer 分相消费范式
- `08_Relationship_Faction施工图_V1.4修复版.md` ModifyRelationshipEffect 收编
- `09_Item_Inventory_Equipment施工图_V1.4修复版.md` add_item 事务 / 来源留痕 quest:<id>
- `10_Economy_Shop_Crafting施工图_V1.4修复版.md` Money Mutation / MoneyChangedEvent / EC-R11
- `11_Ability_Combat_CombatAI施工图_V1.4修复版.md` combat_finished 快照消费端 / learn_ability
