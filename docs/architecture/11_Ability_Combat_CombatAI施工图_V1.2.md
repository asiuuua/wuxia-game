# 11 Ability / Combat / Combat AI 施工图 V1.2

> 状态：**FROZEN**（2026-09-06 用户批准；可在该域实施）
> 依据：宪法 0-C.15 / 0-C.19 / §171 / L2079 State Owner 表（CombatSession·CombatState·Combatant Runtime·CombatResult → Combat）/ §23A（ADR-0003 为什么 Combat 使用 CombatantSnapshot）；01 §61 Ability、§62 Combat、§63 Combat AI、§111 VS-003 Combat、§127 Gate 基线；02 ErrorCode·Transaction·Result；03 ID·Schema·本地化契约；04 Gate Registry；06 Actor Scheduler·State Owner；07 RNG Seed·TimeConsumer；09 InventoryTransaction。
> 冻结日期：2026-09-05。本图为 **0-C 与确定性铁律的第三主战场**（战斗域已自带最强确定性底子，本图负责把散落在外的收进来）。

---

## 0. 编号命名空间声明

本图门禁编号一律使用 **LN 逻辑编号 = 宪法 §88 GATE01~20 ∪ 01 §127 GATE21~32**（04 §2 政策，T-1 已追认 2026-09-06，见 ADR_INDEX §2）；不裸引 verify_all 物理槽位号。

---

## 1. 定位

战斗域是全项目**架构质量最高的域**：确定性 RNG（SeededRNG 注入、同 seed 同结果）、有序事件流（`Array[CombatEvent]` 强类型，不走 EventBus）、AI 与玩家共用结算管道、只读快照广播——01 §62/§63 的目标形状已现雏形。**本图职责不是重设计，而是把「散落在外的违例」收编进既有好底子**：双结算路径、直改回写、第二套条件文法、冷却双时钟、魔法系数、ID 违例。

**本图负责**：Ability 七件套（01 §61）、Combat 会话契约（01 §62）、Combat AI 契约（01 §63）、战斗数值公式集中、冷却统一、奖励与结算事务。
**本图不负责**：Actor 物化与四相循环（06，战斗入口「World Actor → Combatant Snapshot」的数据源）、背包容器（09）、时间推进（07）、难度配置本体（DifficultyManager，本图只消费其倍率）。

---

## 2. 现状盘点（2026-09-05 机器实扫）

### 2.1 已有资产（§171：升级不丢弃）

| 资产 | 位置 | 行数 | 状态 |
| --- | --- | --- | --- |
| CombatCore（确定性战斗内核：ATB/状态引擎/战棋网格/事件流） | `services/combat/combat_core.gd` | 607 | SeededRNG 注入「同 seed 同结果可存档/回放/单测」；高频有序流走返回值不走 EventBus |
| CombatService（会话编排：构建快照/难度注入/结算/奖励/快照广播） | `services/combat/combat_service.gd` | 475 | combat_finished 只读快照广播「规避时序 BUG」；逃跑走内核 RNG；战斗内禁用药产品决策（2026-09-02）已固化 |
| AbilityService（学习/快捷栏 6 槽/冷却读秒） | `services/ability/ability_service.gd` | 125 | ISaveable；load 有 typed Array 踩坑注释；use_combat_skill 已标 @deprecated |
| 数据类五件 | `data/runtime/combat_character·combat_state·combat_event·status_effect·battle_grid.gd` | — | 强类型 Domain 数据，不持 Node |
| 演出辅助 | `core/combat_event_renderer.gd`(109)、`core/combat_entity_pool.gd`(85) | 194 | 归属存疑（见开放问题 AB-4） |
| ConditionService 统一条件 DSL | `core/condition.gd` | 134 | 2026-09-04 整改产物，战斗 AI 未接入 |
| 配置五份 | `abilities/skills.json`(1.2.0)、`abilities/status_effects.json`、`combat/attribute_table.json`（换算系数集中表·五维派生·derive_mode 零回归开关）、`scenes/battles.json`（战斗真源）、`battles/grids/`（战棋布局） | — | 数值表 JSON 化已是好底子 |
| 测试九份 | test_combat_smoke / test_battle_grid / test_battle_roster / test_battle_turn_order / test_battle_status_content / test_ability_service / test_skill_bar_cd / test_combat_entity_pool / test_battle_scene_icons | 全项目最厚战斗测试面 | §171 保留升级 |

### 2.2 实锤缺陷（P-C1~P-C13，全部扫描所得）

- **P-C1【双结算路径】** `ability_service.use_combat_skill` L47-73 自注 @deprecated「绕过 CombatCore.player_skill 直调 take_damage/mp，可能双重结算」；其伤害公式 `(power + attack*0.5) × level_mult`（L66）与主路径 `power + effective_attack()*0.3`（combat_core L105）**系数不一致**——同一武学两条路径伤害系统性偏差。**好消息：全库 grep 无生产调用方**（仅定义本体），退役零阻力。
- **P-C2【结算回写直改】** `finalize()` L435-436 `ps.hp = _state.player.hp; ps.mp = _state.player.mp` 直改 PlayerState；败北 `ps.hp = max(1, ps.hp)` 软锁保护为内联产品规则——01 §62「Combat Result → World State Update」无唯一入口。
- **P-C3【奖励直调】** `_grant_rewards()` L452-460 直接 `ps.gain_exp()` + `GameManager.inventory_service.add_item(..., "drop:%s")`——战斗→背包直连；来源留痕 `drop:enemy_id` 格式已正确（好底子），但未经 09 事务。
- **P-C4【魔法系数散落】** 敌防御 `= attack*0.5*earm`（L75/L116）、同伴兜底 `0.7/0.8`（L122-125）、调息 `8%/15%`（core L123-124）、伤害防御减伤 `*0.5`（core L514）——attribute_table.json 已建却未覆盖这些，违「数值全进 JSON」铁律。
- **P-C5【services 层引 Autoload 枚举】** `_build_snapshots` L466 直接引 `GameState.UnitStatus`（Autoload）——services→Autoload 逆向依赖。
- **P-C6【随机违例两处】** ① escape roll 在 `_core.rng` 为 null 时 `randf()` 全局兜底（L417）；② `configure()` seed=0 时用 `Time.get_unix_time_from_system()` 墙钟派生（core L22-23）——战斗回放/复现的确定性缺口（07 W-R01 同源禁令）。
- **P-C7【敌友同源】** 友军/同伴战斗模板复用 `ConfigManager.get_enemy(uid)` 读 enemies.json（L110）——enemies.json 兼当友方模板，域语义混用；无模板时主角弱化 0.7/0.8 兜底。
- **P-C8【快照裸 Dictionary】** `_build_snapshots()` 返回 `Array[Dictionary]`（L464-475）——0-B.12 同族违例。
- **P-C9【日志硬编码】** `run_enemy_turns` L165 `_state.append_log("...攻击李十五...")` 中文拼接 + 主角名硬编码（03 本地化契约同族）。
- **P-C10【ID 违例】** skills.json 武学 ID `sword_/blade_/inner_/staff_` 裸类别前缀**不在 03 白名单 13 域**（合规域为 `abil_`）；status_effects.json 状态 ID 全拼音裸名（pojia/qianggong/gushou/zhuoshao/zhongdu，应 `stat_` 域）；`qi_cost/mp_cost` 双键并存（core L75 兼容读取）；description 中文内联（违 03「本地化只存 key」）。
- **P-C11【冷却双时钟】** 战斗内 `cooldowns[ability_id]=回合数(int)` vs 大世界 `ability_service.cd_remaining[slot]=秒(float)`，靠 combat_core L89-91「战斗计冷却(回合) → 大世界读秒(秒) **1:1 近似**」桥接（注释自认近似）；且 `cd_remaining` 由 `GameManager._process` 每帧递减 tick_cooldowns（ability_service L91-104）——Tick 直改 State（06 Scheduler 同款违例）。
- **P-C12【第二套条件文法】** `_condition_met`（core L259-274）私造文法 `always | player_hp_below:<0-1> | self_hp_below | self_mp_above`——与 `core/condition.gd` 统一 Condition DSL 平行，两套 parser 并存。
- **P-C13【会话状态散落 + 无实例身份】** CombatService 持 `_state/_core/_escaped/_grid_meta` 四个会话字段；`combat_id = battle_id`（配置 ID 兼实例 ID，多场同配置战斗不可区分）；RNG seed 未进会话记录——01 §111 VS-003 回放（AttackCommand→Deterministic RNG→…→Save）缺实例标识与种子。

### 2.3 已达标项（冻结确认，防退化）

- Combat 不持有 Node 引用（core/service 双注释铁律）→ **01 §62「不依赖 NPC Scene/Player Scene/Battle UI」现状达标**。
- AI 与玩家共用 `_cast_skill` 结算（core L47 注释「行为零变化」）→ 01 §63 同管道雏形达标。
- ATB/SEQUENTIAL 双回合模式 + 战术网格「只做目标过滤，绝不改动伤害结算」（core L373 注释）。
- 战斗内禁用药产品决策固化（combat_service L151-156 保留壳一律拒绝）。

---

## 3. 冻结契约

### AB-1 Ability 七件套（01 §61 全词落位）

- **AbilityDefinition**（skills.json 收编归 05 Pack）：`{ id, name_key, tier, description_key, cost, target, range, range_shape, power, effects[], cooldown, learned_by_default }`。
- **AbilityCost**：`qi_cost` 唯一键，`mp_cost` 退役（读档/旧配置映射兼容期一个版本）。
- **AbilityTarget**：枚举冻结 `enemy | self | all_enemies | all_allies`（core L93-104 现行为全集）+ 战棋面 `range/range_shape(diamond|square|cross|self)`。
- **AbilityCondition**：**统一接 `core/condition.gd` Condition DSL**（P-C12 收编）；战斗内谓词（self_hp_below 等）以 Condition handler 注册进 DSL，禁私造 parser；`player_hp_below` 改经 GameFacts 读参。
- **AbilityEffect**：`effects[{status_id, stacks}]` 引用 StatusEffectDefinition（status_effects.json 收编）；七类 EffectType（BUFF/DEBUFF/DOT/SHIELD/REFLECT/REVIVE/…）以 combat_enums 现值为准冻结。
- **AbilityCooldown**：战斗内唯一真源 = `CombatCharacter.cooldowns`（回合数）；分阶 `tier` 七值冻结：`basic | form2 | form3 | ultimate | qinggong | xinfa | rest`（现四值 + core L7 七分阶规划对齐）。
- **AbilityModifier**：等级倍率 `1.0+(level-1)*0.15` 等修正系数入 attribute_table（P-C4）；修炼升级入口（现 learned 恒=1 无升级路径）挂 Phase4+ 挂点。
- **扩展铁律**：新增武学/法术/暗器/阵法/毒术/轻功/内功 = 新增 Definition 数据 + tier/EffectType 枚举值，**禁改 Ability 核心**（01 §61 原文）。

### AB-2 Combat 会话契约（01 §62 + 宪法 L2079 State Owner）

- **Owner 归位冻结**：CombatSession / CombatState / Combatant Runtime / CombatResult → Combat 模块（宪法 L2079 原文）；会话字段 `_state/_core/_escaped/_grid_meta` 收编进 CombatSession 单一对象（P-C13）。
- **生命周期**：`World Actor → Combatant Snapshot → Combat Session → … → Combat Result → World State Update → Committed Events`（01 §62）；**开始快照 = 只读拷贝**（现 start_combat 逐字段拷贝 ✓ 冻结），战斗内禁回写 World State。
- **结算回写唯一入口 = CombatResultCommitCommand**（P-C2/P-C3 收口）：hp/mp 回写 + 败北保底 + 奖励发放 + 死亡判定 + 快照广播，**一事务一 Journal 全回滚**——战斗结算=宪法 L616「多 Owner 状态原子协调」标准用例；`ps.hp = 直改`、`gain_exp`、`add_item` 直调退役。
- **快照强类型**：`CombatUnitSnapshot { unit_id, is_player, status }`（P-C8 收编）；combat_finished 只读快照广播模式冻结（「任务系统只读快照，规避时序 BUG」从注释升为契约）。
- **禁依赖面冻结**：Combat 不依赖 NPC Scene / Player Scene / Battle UI（01 §62 原文；现状达标）；`GameState.UnitStatus` 引用改本域枚举映射（P-C5）。
- **产品决策固化**：战斗内禁用药（2026-09-02）；敌友模板分离挂开放问题 AB-3。

### AB-3 Combat AI 契约（01 §63 + §101 边界）

- **同管道铁律**：AI Decision → Command 与 Player Input → Command 走**同一条 Combat Command Pipeline**（01 §63 图）；禁 AI 私结算路径（P-C1 退役后 grep 防复活）。
- **AI 技能包契约**：`ai_kit: [{ability_id, weight, condition}]`（enemies.json abilities 字段收编为 AiKitDefinition；字符串简写归一化保留）；选招 = 可用性（真气/冷却）→ 条件门（DSL）→ 权重随机（SeededRNG）→ 射程过滤（战棋）四段顺序冻结（core _pick_enemy_ability 现序）。
- **目标选择策略化**：`_pick_player_target` 最低气血集火硬编码 → **AIProfile 挂点**（target_policy: lowest_hp | random | …，YAGNI 本期只留接口缺省 lowest_hp）。
- **托管同构**：玩家托管与敌人共用 `enemy_tactical_plan`（core L453 注释「行为一致」升为契约）；战术 AI「走位到最近可达格 + 射程内选招」冻结。
- **AI 边界**（01 §101）：AI 只产 Command，不直改 CombatState；决策输入只读快照。

### AB-4 战斗数值公式集中（「数值全进 JSON」铁律）

- `attribute_table.json` 扩容为战斗公式**唯一真源**：伤害公式（`power - defense×k1`）、暴击倍率、闪避/暴击概率、集气速率派生、调息回复（8%/15%）、敌防御派生（attack×0.5×earm）、同伴兜底系数（0.7/0.8）、等级倍率 0.15——全部入表，代码只读（P-C4 收口）。
- `derive_mode` 开关模式冻结（flat ↔ five_attr 零回归切换）为数值表标准形态。
- 禁止战斗/武学域代码出现裸算术系数字面量（见 AB-R05 扫描规则）。

### AB-5 冷却统一（P-C11 收口）

- 战斗内冷却（回合数，`CombatCharacter.cooldowns`）= **唯一业务真源**；回合计时随 `tick_unit` 递减（core L281-288 现序冻结：递减先于行动）。
- 大世界 HUD 读秒（`cd_remaining`）**降级为纯表现层缓存**：契约声明「1:1 近似仅为演出，业务判定禁依赖」；每帧递减从 Domain Service 迁 Application 表现计时器（GameManager._process 驱动保留，但 tick 落在表现层对象，06 Tick 禁直改 Domain 同款收口）。
- 战斗→大世界桥接 `set_cooldown(slot, 秒)` 保留为表现同步专用 API，签名冻结。

### AB-6 确定性与回放（VS-003 落地）

- **战斗随机必走 SeededRNG**：`randf()/randi()` 禁出现在 combat/ability 域（P-C6① 收口，escape roll 强制走内核 RNG，null 兜底改 FATAL）。
- **seed 显式必填**：`configure()` 的 seed=0 墙钟 fallback 退役——`start_combat` 显式生成并记录 seed（来源=GameClock 派生或全局 RandomProvider，禁墙钟直读）。
- **CombatSessionId 分配器**：战斗实例 ID ≠ battle_id（复用 09 EntityId 分配器，水位=max+1）；会话记录 = `{session_id, battle_id, rng_seed, command_seq}` 进回放（01 §111 VS-003：AttackCommand→Deterministic RNG→Damage→Death→Loot→Committed Events→Save）。
- `Array[CombatEvent]` 有序事件流冻结为战斗内唯一事实流（EventBus 只做会话级边界通知 combat_started/ended/finished）。

### AB-7 测试与回归面（§171 保留升级）

- 九份战斗测试保留升级：test_combat_smoke 升契约测试（同 seed 同事件流 golden 断言）；test_skill_bar_cd 覆盖表现层冷却近似。
- 新增：① 同 seed 双跑事件流逐位相等断言（确定性回归）；② CombatResultCommitCommand 失败回滚用例（0-C.20 复用）；③ AI 同管道等价断言（同一局面 AI Command 与玩家同 Command 事件流一致）。

---

## 4. 迁移映射表（绞杀者，禁一次性大改）

| 现有资产 | 目标 | 阶段 |
| --- | --- | --- |
| `ability_service.use_combat_skill`（@deprecated，无调用方） | 删除（测试先行确认零引用） | Phase2 |
| `finalize()` 直改回写 + `_grant_rewards()` | CombatResultCommitCommand Handler（一事务） | Phase2 |
| `_condition_met` 私有文法 | Condition DSL 注册战斗谓词 | Phase2 |
| `attribute_table.json` | 扩容吸收全部战斗系数（derive_mode 模式） | Phase1 契约 / Phase4 数据 |
| `ability_service.cd_remaining` 每帧递减 | Application 表现计时器（Domain 剥离） | Phase3 |
| `_build_snapshots` Dictionary 数组 | CombatUnitSnapshot 强类型 | Phase2 |
| skills.json `sword_/blade_/...` ID + status_effects.json 拼音 ID | `abil_`/`stat_` 域重映射（读档映射表 + `_retired_ids.json`，与 06-AC1 同方案） | Phase4 |
| `qi_cost/mp_cost` 双键 | `qi_cost` 唯一键（旧键兼容一版） | Phase4 |
| `core/combat_event_renderer·entity_pool` | 归属裁决后落位（开放问题 AB-4） | Phase3 |
| GameState.UnitStatus 引用 | 本域枚举 + 映射 | Phase2 |
| seed=0 墙钟 fallback / randf() 兜底 | 显式 seed + 内核 RNG 强制 | Phase2 |

---

## 5. Enforcement 矩阵（AB-R01~R12，E0 = 0）

| 规则 | 内容 | 载体（LN Gate） | 级 |
| --- | --- | --- | --- |
| AB-R01 | Ability 七件套词面齐备（Definition/Cost/Target/Condition/Effect/Cooldown/Modifier）；qi_cost 唯一键 | GATE06 schema validator | E3 |
| AB-R02 | AI 与玩家同 Command 管道；`use_combat_skill` 类私结算路径禁复活（grep 基线） | GATE24 契约漂移 + GATE28 命令序 | E2 |
| AB-R03 | Combat 域禁依赖 NPC Scene / Player Scene / Battle UI；services 禁引 GameState/Autoload 符号 | GATE05 / GATE12 arch_lint | E3 |
| AB-R04 | 结算回写唯一入口 CombatResultCommitCommand；combat/ability 域禁出现 `player_state.hp =` / `player_state.mp =` / `gain_exp(` / `inventory_service.add_item(` 直调 | GATE25 state_owner + 基线 | E3 |
| AB-R05 | 战斗/武学域禁裸算术系数字面量（0.5/0.3/0.7/0.8/0.08/0.15 类）；公式系数走 attribute_table | lint 扫描 + GATE06 | E3 |
| AB-R06 | 战斗域随机必走 SeededRNG；`randf()/randi()/Time.get_unix_time` 禁出现在 combat/ability 域（07 W-R01 同源扫描器扩展） | arch_lint api 规则 + GATE02 回归 | E3 |
| AB-R07 | 会话记录必含 {session_id, battle_id, rng_seed, command_seq}；VS-003 同 seed 重放事件流逐位相等 | GATE29 VS 回放套件 | E2 |
| AB-R08 | AI 条件门禁私造 parser（统一 Condition DSL）；`_condition_met` 类本地 split 文法禁新增 | GATE24 + 代码评审清单 | E3 |
| AB-R09 | 武学/状态/战斗 ID 白名单（`abil_`/`stat_`/`battle_` 域）；sword_/pojia 类入退役迁移名单 | GATE07 ref_index | E3 |
| AB-R10 | 跨模块快照/事件禁裸 Dictionary（CombatUnitSnapshot 强类型） | GATE24 + 0-B.12 同源扫描 | E3 |
| AB-R11 | 战斗结算（回写+奖励+死亡）一事务一 Journal，0-C.20 场景复用 | GATE26 / GATE27 | E2 |
| AB-R12 | 冷却双时钟：业务判定禁依赖大世界读秒近似（契约测试 + 注释守卫）；每帧 tick 禁落 Domain State | GATE25 + GATE02 | E3 |

> E0 占比 0%：每条规则都有扫描器或测试兜底，无「纯自觉」条款。

---

## 6. Freeze 清单（批准后冻结，改动需走 ACR）

- 文件面：`services/combat/combat_core·combat_service.gd`、`services/ability/ability_service.gd`、`data/runtime/` 战斗五件数据类、`core/condition.gd` 战斗谓词注册面、`abilities/skills.json`、`abilities/status_effects.json`、`combat/attribute_table.json`、`scenes/battles.json`、EventBus 战斗信号面（combat_started/ended/finished、ability_learned/used、notify_skill_*）、九份战斗测试。
- 契约面：AB-1~AB-7 全部条款；AB-R01~R12 矩阵；tier 七分阶；EffectType 全集；target 四枚举；回放会话记录四元组。
- 跨图咬合面：06（Combatant Snapshot 数据源 / Tick 禁直改）、07（RNG Seed·GameClock 派生）、09（InventoryTransaction / EntityId 分配器复用 / drop 留痕格式）、04（GATE26 事务矩阵复用）、05（配置 Pack 收编）、02（CombatResultCommitCommand 契约）。

---

## 7. DoD（Definition of Done，7 条）

1. 本图全部 AB-* 冻结项经用户批准升 FROZEN；
2. AB-R01~R12 每条有指定载体且实际落地，E0 = 0；
3. 同 seed 双跑事件流逐位相等断言进 GATE02 常绿；VS-003 回放（含 session_id + seed）走通 GATE29；
4. P-C1~P-C13 每项在迁移映射表有对应收编行，旧资产升级不丢弃（§171）；
5. CombatResultCommitCommand 事务通过 0-C.20 十一场景（GATE26），结算失败可整体回滚；
6. 配置五份经 GATE06 校验零错误，GATE07 零悬空（含 abil_/stat_ 退役迁移名单）；
7. 双闸门绿（GATE01/GATE02）且 `verify_all.py` 全绿，九份战斗测试零 ✗。

---

## 8. 开放问题（需用户 / ADR 裁决，AI 不自决）

> **【已追认 2026-09-06】** 用户整批复核：以下 AB-1~AB-4 全部按推荐执行；**跨图登记条目按建议落地**——宪法 §23A 预占题不占号，统一登记表 `docs/architecture/ADR_INDEX.md` 已建立，新 ADR 自 0005 顺延。本节保留原文供审计。

- **AB-1（ADR）实时 ATB 评估**：现 ATB 仍为回合离散（按集气速率排序出回合序列）；若未来做真·实时 ATB（集气满即插队行动），Command Pipeline 语义需重审——**推荐 YAGNI**：冻结回合离散模型，实时制挂 Phase5+ 评估，本图契约不预设。
- **AB-2 AIProfile 难度分层**：低难度 AI 降智（权重偏向低伤招/目标策略随机化）是否本期实装——**推荐只留 AIProfile 接口**，难度→Profile 映射 Phase4+。
- **AB-3 敌友模板分离**：友军/同伴现复用 enemies.json 模板——**推荐新建 units.json 战斗模板域（battle 域 ID）**，enemies.json 回归纯敌方；旧 allies 字段读兼容。
- **AB-4 演出辅助归属**：`core/combat_event_renderer.gd` / `combat_entity_pool.gd` 挂 core 层（renderer 名义存疑）——**推荐 Phase3 装配收敛时归 scenes 演出层/独立 Presentation 段**，core 只留纯逻辑。
- **【跨图登记·编号撞车】** 宪法 §23A 预占 ADR-0002~0005 选题（为什么采用 Repository / 为什么 Combat 使用 CombatantSnapshot / Marriage·Children / Save·RuntimeState）；03 图开放问题已使用 ADR-0002/0003/0004 编号——**需用户裁决 ADR 统一登记表**（建议：宪法预占题保持专名引用不占号，新 ADR 从现有序列顺延并建 `docs/architecture/ADR_INDEX.md`）。

---

## 9. 一句话总纲

**战斗内核已经把「同 seed 同世界」做对了一半——11 图把另一半（结算回写、奖励、公式系数、条件文法、冷却）也装进同一本确定性账本，让 AI 与玩家在 Command 层完全平等。**

---

## 10. 关联文档

- `01_总体架构施工图_V1.2.md` §61 Ability / §62 Combat / §63 Combat AI / §101 AI 边界 / §111 VS-003 / §127 Gate 基线
- `02_Domain_Kernel施工图_V1.2.md` Command·Query·Event / ErrorCode / Transaction / Result
- `03_Contract_Schema_DataContract施工图_V1.2.md` ID 白名单 / 本地化 key / Definition 四态
- `04_Test_Infrastructure_Architecture_Gate施工图_V1.2.md` Gate Registry / Test Double（FakeClock·SeededRandom）/ GATE26
- `05_Content_Registry_Content_Pipeline施工图_V1.2.md` skills/status_effects/attribute_table/battles Pack 收编
- `06_Actor_Player_NPC施工图_V1.2.md` Combatant Snapshot 数据源 / Tick 禁直改 / VS-005 物化
- `07_World_Time_Schedule施工图_V1.2.md` GameClock / RNG Seed 进回放 / 禁全局 randi
- `09_Item_Inventory_Equipment施工图_V1.2.md` InventoryTransaction / EntityId 分配器 / 来源留痕
