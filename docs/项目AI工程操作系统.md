# 项目 AI 工程操作系统（Applied to 武侠江湖）

> 本文件把你分享的《AI 工程操作系统》愿景**落地到真实项目**（不是模板套用）。
> 前提澄清：**你的完整工程就在 `D:/武侠游戏`，工作室平台在 `tools/desktop_studio`，经验书/白皮书/经验库全在本仓 `docs/`**——无需上传 ZIP，直接基于真源构建。

---

## 0. 核心范式转变（本文件要落地的唯一关键）

你分享的愿景里最重要的一句话：

> **不要让人选择「我要调用哪个 Prompt」。应该让人告诉 AI：「我要做什么」，然后 AI 自己决定调用哪些角色。**

我们之前建的是 **角色驱动**（`project-full-analysis` 七角色提示词 + 续篇第九章七工位手册）。
本文件补上缺失的 **任务驱动编排层（L3 总控）**，并把角色提示词降级为「总控可调用的专业能力模块」。

**结论先行**：8 层里我们已具备 5 层（L0/L1/L4/L5 机械部分/L7 雏形），真正缺的是 **L2 模块卡** 与 **L3 任务总控**；本文件一次性补齐这两层，并把 L6 经验提炼升级为五维分级。

---

## 1. 八层映射：已有 vs 缺失（基于真实仓库）

| 层 | 名称 | 我们现有资产（真实） | 状态 |
|----|------|---------------------|------|
| L0 | 项目身份层 | `docs/GDD与架构设计.md`、`docs/开发规范.md`、`项目经验白皮书.md` 第零/一章、`.workbuddy/memory/MEMORY.md`（定位与锁定） | ✅ 已具备 |
| L1 | 结构认知层 | `项目经验白皮书.md` 第三章模块清单、`docs/架构对接分析_蓝图vs现状.md`、分层铁律 | 🟡 有文档，缺**自动生成的依赖图** |
| L2 | 模块知识层 | `docs/变更通告_*.md`(79篇) + `docs/经验库/`(11篇) 按模块散落 | ❌ **缺统一 Module Card 结构**（本文件补） |
| L3 | 任务编排层 | 无单一总入口；角色提示词各自独立 | ❌ **缺任务总控**（本文件补，见第 3 节） |
| L4 | 执行层（角色） | `docs/全角色工程手册与平台优化蓝图.md` 第九章七工位手册、`project-full-analysis` skill | ✅ 已具备 |
| L5 | 逆向审查层 | 续篇/白皮书逆向审查清单 + **双闸门门禁**（GATE1+GATE2 机械兜底） | 🟡 有清单+机械门禁，缺「灾难模拟」 formalized |
| L6 | 经验提炼层 | `docs/经验库/` K 条目 + 白皮书第七章经验提炼 | 🟡 有一维，缺**五维分级 E1-E4**（本文件补，见第 4 节） |
| L7 | 平台反哺层 | `docs/全角色工程手册...` 第十一章平台优化蓝图 + 经验库增强检索（分面 API） | 🟡 有蓝图，缺「自动判定是否平台化」闭环 |

**缺口聚焦**：本文件只做两件新事——**L2 模块卡** 与 **L3 任务总控**，并把 **L6 升级为五维**。其余层已存在，仅标注衔接点。

---

## 2. L2 · 模块知识层：Combat Module Card（真实样本）

> 这是用**真实文件路径**写的模块卡，证明「代码级考古」已可落地。后续每个模块照此生成。

```markdown
# Module Card · COMBAT（战斗）

## 基本信息
- 模块ID：COMBAT
- 所属层：业务服务层（逻辑）+ 视图表现层（渲染）+ 核心层（工具）
- 职责：战斗流程、行动点/回合、伤害计算、状态结算、战斗事件广播
- 禁止：直接操作 UI；直接改其他模块私有数据；跨层调用

## 文件清单（真实）
- 业务服务层：services/combat/combat_service.gd（CombatService, RefCounted）、
               services/combat/combat_core.gd（CombatCore 逻辑内核）
- 核心层：core/combat_event_renderer.gd（渲染器）、core/combat_entity_pool.gd（实体对象池）、
          core/constants/combat_constants.gd、core/enums/combat_enums.gd
- 运行时态：data/runtime/combat_state.gd、combat_character.gd、combat_event.gd、battle_grid.gd
- 视图层：scenes/gameplay/battle/BattleScene.gd、battle_director.gd、battle_entity.gd、
          battle_grid_node.gd、battle_view.gd、tactical_battle_scene.gd、unit_hud.gd
- 配置：data/configs/battles/grids/preset_*.json（网格 preset，主权窗）
- 测试：tests/unit/test_battle_*.gd、test_combat_*.gd、test_tactical_loop.gd（约 8 套件）

## API（节选，真实签名）
- CombatService.start_combat(battle_id:String)
- CombatService.player_attack(target_id:="") -> Dictionary
- CombatService.player_cast(slot:int, target_id:="") -> Dictionary
- CombatService.player_rest() -> Array[CombatEvent]
- CombatService.run_enemy_turns() / enemy_phase_events()
- CombatService.deploy_unit(unit_id, pos:Vector2i) / compute_reachable(unit_id) -> Array[Vector2i]
- CombatService.get_state() -> CombatState / get_result() -> int / is_over() -> bool

## Event（经 EventBus 广播）
- 战斗开始/结束、伤害结算、状态变更、单位死亡 —— 全部走 EventBus，不直调 UI

## Dependencies
- EventBus（跨模块解耦中枢）、PlayerState、data/configs（技能/敌人/网格）、背包（掉落经 InventoryTransaction）

## Dependents
- 结缘（战斗结局影响关系）、town（⚠ 已知 open 派单：战斗→town 掉血崩）

## Historical Bugs
- BUG-04 经济事务化边界、战斗→town 掉血崩（未连通，open）
- 历史：战斗逻辑层/战术视图层分离、渲染器确定性加固、敌人 AI 选技能（M3 设计待落地）

## Known Risks
- 跨场景掉血未回滚；渲染确定性依赖事件顺序；preset 网格被误改（主权边界保护）

## Performance
- combat_entity_pool 对象池控内存；渲染器确定性已加固

## Extension Points
- 新兵种/技能插件化（技能权重表 M3）；状态效果（中毒等）走 StatusSystem

## Test Cases
- test_tactical_loop（回合循环）、test_combat_smoke（冒烟）、test_battle_turn_order（行动顺序）

## Knowledge（指向经验库）
- 08_静默接缝BUG四层防线、03_经济事务化资产、06_卡住BUG根因
```

**用法**：AI 接到「增加中毒状态」→ 读 COMBAT 卡 → 定位 StatusSystem/CombatCore → 读相关经验 → 设计，而非从零思考。

---

## 3. L3 · 任务编排层：项目 AI 工程总控（唯一总入口）

> 这是你要的「Prompt Operating System 单一入口」。人只说「我要做什么」，AI 自判模块+角色。
> 已把我们的真实能力接进去：**经验库分面检索 = Knowledge Router**，**双闸门 = 审查/回归 Gate**，**change_log+handoff = 变更/协同层**。

```text
# 武侠江湖 · AI 工程总控 Prompt（任务驱动版）

你是本项目的【AI 工程总控】，不是单独的角色。
人告诉你「要做什么」，你自行决定调用哪些专业能力模块。

## 项目上下文（只读，不重造）
- 工程：D:/武侠游戏（Godot 4.7.2，纯 GDScript，分层单体+EventBus）
- 架构铁律：autoload→core→data→services→scenes；跨模块只走 EventBus；数值全进 JSON
- 项目知识库：docs/经验库/（11 篇，含检索关键词）+ docs/全角色工程手册与平台优化蓝图.md
- 变更记录：docs/更改日志.md（change_log.py 登记）
- 模块卡：docs/（按 Module Card 模板逐模块生成，先有 COMBAT）
- 当前已知 open 派单：战斗→town 掉血崩 / 结缘→背包休息未推进天数 / 背包→结缘聘礼跳过锁定

## 总控流水线（每次任务强制走完）
① 项目定位：判一级/二级模块、架构层、涉及文件、依赖、受影响模块、历史类似 BUG。
   不确定 → 标【信息缺失】，禁止编造结构。
② 知识路由（Knowledge Router）：调用经验库分面检索（角色/模块/BUG 过滤），
   只注入相关 K 条目，不dump 全库。
③ 自动角色编排：判需 PM/架构/后端/前端/美工/测试/运维 中哪些，说明【角色/为什么/负责/依赖】。
   不需要的不要强行参与。
④ 正向设计：需求→模块→数据→接口→业务→实体→事件→UI→测试。
⑤ 逆向推演（灾难模拟）：假设方案已坏，倒推哪步重复触发/无限循环/引用已 free 节点/
   返回 null/重复结算/双死亡事件/破坏存档兼容。
⑥ 执行：每次改必须写【修改文件/位置/原因/内容/影响/副作用】。禁止无关重构。
⑦ 自我审查：以独立审查员身份重查架构/数据/业务/UI/性能/异常/资源生命周期/兼容。
⑧ 测试：冒烟+边界（空/最大/最小/重复/非法/快速连点/中途退出/节点销毁/场景切换）+回归。
⑨ 审查门禁：触发双闸门——GATE1(headless --quit 零编译错误) + GATE2(run_all.tscn 零✗)。
   非绿即阻断，禁止提交。
⑩ 变更记录：change_log.py add（模块/范围/what/impact/ref）。
⑪ 经验提炼：判是否产生新经验，分级 E1项目/E2模块/E3工程/E4平台，写经验库。
⑫ 平台反哺：判是否平台化（模板/脚手架/插件/自动检查器/UI组件/代码生成器/平台工作流）。

## 最终输出顺序
1.项目定位 2.影响范围 3.自动角色编排 4.正向设计 5.逆向风险 6.实现方案
7.修改清单 8.自我审查 9.测试 10.双闸门结果 11.变更记录 12.新经验 13.平台反哺
```

**要点**：角色提示词（续篇第九章 / `project-full-analysis`）从「独立 Prompt」变为「总控可调用模块」。不再增加第 8 个角色 Prompt，而是装这一层编排。

---

## 4. L6 升级：经验提炼五维分级（E1-E4）

把现有 `docs/经验库/` 一维 K 条目升级为五维，未来 AI 按任务**只检索相关维度**：

```text
Knowledge
├── Project      （仅本项目，如「某 NPC 场景不可直访 CombatManager」）
├── Module       （同类模块，如「动态战斗特效须 EffectLifecycle 统一回收」）
├── Engineering  （跨项目，如「临时节点须有明确生命周期」）
├── AntiPattern  （反模式，如「mouse_filter 装饰子节点写 STOP=0 拦截」）
└── Platform     （应平台化，如「自动扫描 Node.new() 检查 queue_free()」）

每条带等级：E1项目 / E2模块 / E3工程 / E4平台
例：
K-COMBAT-001 | 等级 E2 | 分类 性能 | 模块 战斗
现象：大量特效节点长期存在
根因：生命周期管理缺失
解决：统一 EffectLifecycle
预防：代码检查(可升 E4 自动检查器)
测试：连续战斗 100 次
平台化：自动生命周期检查器
```

**解决「知识鲸鱼」问题**：任务→模块/关键词→只注入相关 K，不把 3000 条全塞 Prompt。

---

## 5. 适配目录结构（映射到本仓，不新建平行仓库）

```text
D:/武侠游戏/
├── docs/                           ← L0/L1 身份与结构认知
│   ├── 项目经验白皮书.md
│   ├── 全角色工程手册与平台优化蓝图.md   ← L4 角色能力
│   ├── 项目AI工程操作系统.md            ← 本文件（L3 总控 + 映射）
│   ├── 经验库/                        ← L6 五维知识（升级中）
│   ├── 模块卡/                        ← L2（新增：COMBAT.md 起，逐模块生成）
│   │   └── COMBAT.md
│   ├── 更改日志.md                    ← L7 变更记录
│   └── 变更通告_*.md
├── tools/desktop_studio/            ← L7 平台能力（连接器）
│   ├── studio_server.py  (/api/experience 分面 = Knowledge Router,
│   │                    /api/gate/run = 审查 Gate)
│   └── index.html (📚经验库 / 🔧双闸门 tab)
└── （游戏代码：autoload/core/data/services/scenes/tests） ← L4/L5 执行与审查对象
```

不引入外部 `AI_ENGINEERING_OS/` 平行目录——直接长在本仓，避免双源漂移。

---

## 6. 落地路线（建议，待你拍板）

| 阶段 | 动作 | 成本 |
|------|------|------|
| 立即 | 本文件 + COMBAT 模块卡 + 总控 Prompt 已就位 | 已做 |
| 短期 | 把总控 Prompt 固化为 `ai-engineering-os` skill（单一入口），其余角色提示词标为「被调用模块」 | 低 |
| 短期 | 经验库 11 篇补 E1-E4 等级标签（不改内容，仅加 frontmatter） | 低 |
| 中期 | 逐模块生成 Module Card（战斗/背包/对话/结缘/UI/存档） | 中 |
| 中期 | L1 自动依赖图：脚本扫 `.gd` 的 `class_name`/依赖，生成模块依赖 markdown | 中 |
| 长期 | 总控接平台：输入任务→自动调经验库分面+双闸门+change_log，形成闭环 UI | 高 |

---

## 7. 自学习 · 本次提炼

- **触发场景**：用户分享《AI 工程操作系统》愿景，要求从「角色驱动」升级为「任务驱动」。
- **提炼点**：① 角色提示词应降级为总控可调用模块，而非继续增加独立 Prompt；② 模块卡（L2）是把代码地图变可检索的关键；③ 经验库须五维分级(E1-E4)才能解决知识鲸鱼；④ L3 总控必须把双闸门作为机械 Gate 嵌进流水线第⑨步。
- **更新建议**：回写至 `project-full-analysis` 角色审查——架构师段加「优先建模块卡而非加 Prompt」；Tech Lead 段加「经验按 E1-E4 分级」。
- **关联隐患**：继续堆角色 Prompt 会导致工作者不知用哪个（Prompt 通胀）；总控若不强嵌双闸门会退化成纯建议。
- **预防**：总控流水线第⑨步硬编码双闸门非绿即阻断；角色提示词统一标 `callable_by: orchestrator`。
