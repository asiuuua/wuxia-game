AI驱动大型RPG工程施工总规范 V1.2
Project Engineering Constitution
AI-Driven Large-Scale RPG Engineering Specification
Version: 1.2
Status: Foundation / Mandatory / Integrated Edition / Supersedes V1.1
Applies To: Runtime / Content / Tools / Studio / Tests / AI Collaboration / Build / Save / DLC / Mod

---
0.1 V1.2 修订说明
V1.2 不推翻 V1.1 的治理骨架，而是在 V1.1 之上完成一次面向 Godot + GDScript + 多 AI 小团队实际施工的工程化整合。

V1.2 保留并升级：
- Domain / Application / Infrastructure / Presentation 分层
- 模块主权、唯一状态 Owner、公开契约
- AI Permission、Write Lease、ACR / ADR
- Context Pack、Freeze Manifest、Compatibility、Provenance
- Content Review / Publish Gate
- Performance Budget / Regression
- Architecture Health / Emergency Change
- Vertical Slice / 多 AI 施工治理

V1.2 新增或强化的核心工程能力：
1. Godot / GDScript 原生工程标准，不再机械模拟 C# / Java 语言能力。
2. Static Architecture Enforcement：把关键红线落到编译器、扫描器、测试和 Merge Gate。
3. Execution Foundation：明确 Command → Transaction → Domain Mutation → Commit / Rollback → Event 的真实执行语义。
4. Transaction / Mutation Journal / Rollback / Pending Event / Commit 规则。
5. Scheduler 分层：Command Scheduler、Actor Scheduler、World Simulation Scheduler、Persistence Scheduler。
6. 三张工程图：Architecture Graph、Foundation Graph、Build Graph。
7. Vertical Slice 从“阶段验收项”升级为“持续工程主线”。
8. AI Task Scope Lock、Changed-File Enforcement、Contract Freeze 与 Scope Drift Gate。
9. Rule → Enforcement Matrix：每条硬规则必须声明由谁、以什么方式、在哪个 Gate 执行。
10. GDScript 类型、Variant、Dictionary、Node、Autoload、Signal、RefCounted、@abstract 等具体施工约束。

V1.2 的原则性修正：
- “Interface”是架构角色，不强制对应 IXXX 命名或模拟其他语言的接口体系。
- “readonly”不作为 GDScript 假想能力，而采用私有字段 + 受控读取 / Mutation API。
- 不以泛型为核心架构前提，优先明确具体类型。
- 不以 Node / SceneTree 作为核心业务状态的事实源。
- 不以 Dictionary / Variant 作为跨模块万能运输结构。
- 不以“AI 自觉遵守”作为唯一架构防线。
- 文档编号、架构依赖顺序、实际施工顺序严格区分。

V1.1 与 V1.2 的关系：
V1.1 = 治理母版
V1.2 = 治理母版 + Godot/GDScript 执行规范 + Execution/Transaction 语义 + 机械化 Enforcement + Vertical Slice Build Protocol

V1.2 生效后：
V1.1 保留为历史基线；冲突时，以当前已批准且版本号最高的 V1.2 Project Constitution 为准。

---
0. 文档定位
本文件不是普通开发规范。
它是整个项目的：
- 工程宪法
- 架构最高约束
- AI 开发行为规范
- 多 AI 协同规范
- 模块边界规范
- 测试与验收规范
- 内容生产规范
- 数据与存档规范
- Studio 工具规范
- 架构演进规范
任何代码、数据、工具、编辑器、AI 任务、模块设计，都必须服从本规范。
当以下内容发生冲突时，优先级固定为：
项目宪法
    >
总体架构
    >
模块契约
    >
模块施工图
    >
任务卡
    >
AI自行推断
AI 不得以“为了完成需求”为理由绕过上层规则。

# 0-A. V1.2 工程执行总纲

本章定义：如何把本宪法真正落实到 Godot + GDScript + 多 AI 施工现场。

V1.2 不把架构防线建立在“AI 会自觉遵守”上。
所有关键规则必须尽量落到以下执行层之一：

E0 DOCUMENT
E1 REVIEW
E2 TEST
E3 STATIC CHECK
E4 BUILD BLOCK

优先级：
E4 > E3 > E2 > E1 > E0。

任何规则若只有 E0，必须说明为什么无法机械化；若本质上可以自动检查，则应逐步升级到 E2/E3/E4。

---
0-A.1 三张工程图

本项目从 V1.2 起同时维护三张图，不再使用“文档编号 = 实际依赖顺序”的单一解释。

A. Architecture Graph
回答：系统最终应该长什么样。

B. Foundation Graph
回答：哪些横向能力必须提前逐步铺设。

C. Build Graph
回答：多个 AI 当前可以安全地并行施工什么。

三者禁止混淆。

---
0-A.2 Architecture Graph

稳定架构关系原则：

Presentation
    ↓
Application
    ↓
Execution / Transaction Runtime
    ↓
Domain
    ↓
Kernel

Infrastructure 通过公开 Contract / Port 实现技术能力。
Content 提供 Definition / Schema / Pack / Index。
Actor 提供运行时实体承载，并通过明确 Contract 接入 Application / Domain / World / Content。

说明：Execution 是横向执行基础，不是新的业务 Domain；它负责执行语义、事务、调度、提交、回滚和事件提交时序。

---
0-A.3 Foundation Graph

以下能力不是“一次做完的一章”，而是横向 Foundation：

Contract
    ↓
Testing
    ↓
Execution
    ↓
Persistence Foundation
    ↓
Composition
    ↓
Content Foundation
    ↓
Actor Foundation
    ↓
Gameplay Modules

每一项先建立最小可用能力，再随着 Vertical Slice 增长。

---
0-A.4 Build Graph

多 AI 实际施工采用：

Frozen Contract
    ↓
Task Scope Lock
    ↓
Parallel Module Work
    ↓
Contract / Architecture Gates
    ↓
Integration
    ↓
Affected Vertical Slice
    ↓
Merge

并行施工的前提不是“不同窗口”，而是：
- 不共享同一 Write Lease。
- 不同时修改同一 Shared Foundation Scope。
- 所有跨模块交互都已冻结 Contract。
- Changed Files 不得越过授权范围。

---
0-A.5 Rule → Enforcement Matrix

每条强制性规则至少登记：
RULE_ID
RULE
SEVERITY
ENFORCEMENT_LEVEL
SCANNER / TEST / GATE
OWNER
EXCEPTION_POLICY

示例：

RULE-GODOT-DOMAIN
Rule：Domain 不得依赖 Godot
Severity：FATAL
Enforcement：E3 / E4
Scanner：Architecture Dependency Scanner
Gate：GATE14
Owner：Architecture

RULE-STATE-OWNER
Rule：核心状态只能拥有一个写 Owner
Severity：FATAL
Enforcement：E2 / E3
Test：Ownership Contract Test
Gate：GATE05
Owner：Module Architecture

RULE-TRANSACTION-ATOMICITY
Rule：纳入同一 Transaction 的状态变化必须全部成功或回到事务前状态
Severity：FATAL
Enforcement：E2 / E4
Test：Transaction / Rollback Suite
Gate：Execution Gate
Owner：Execution

---
0-A.6 V1.2 统一停止条件

任何以下情况，AI 必须停止实现，不得猜测：
- Contract 缺失。
- 状态 Owner 不明确。
- 事务边界无法定义。
- 失败路径无法定义。
- 需要跨越未授权模块边界。
- 需要修改 Shared Foundation 但无 Write Lease。
- 当前文档与批准 Contract 冲突。
- 实际代码与批准架构存在 Drift，且修复影响超出当前 Task。
- 必须新增核心全局单例才能继续。
- 需要把业务状态塞进 Node / Dictionary / Variant 才能“快速实现”。

状态统一：BLOCKED / UNKNOWN / ACR_REQUIRED。

---
0-A.7 最小实现原则

V1.2 不鼓励“架构为了架构”。
满足以下任一条件才建立新抽象：
1. 存在第二种实现。
2. 明确需要测试替身。
3. 存在平台差异。
4. 存在可替换策略。
5. 需要跨模块隔离。

否则优先直接使用具体、强类型、可测试的类。

---
0-A.8 机器验证优先于口头保证

以下陈述均不构成施工证据：
- “理论上可行。”
- “我已经检查过。”
- “应该没问题。”
- “以后再优化。”
- “这个改动很小。”

有效证据只能来自：
Compiler / Static Check / Test / Gate / Reproduction / Benchmark / Build Artifact / Change Record。

---
0-B. Godot + GDScript 工程标准

本章是 V1.2 的 Godot / GDScript 实施规范。

---
0-B.1 GDScript 类型策略

核心代码默认强类型。

应优先：
var actor: ActorRuntime
var actor_id: StringName
var quantity: int
var price: int

func buy_item(command: BuyItemCommand) -> CommandResult:
    ...

Typed Array：
var actors: Array[ActorRuntime] = []

核心 Runtime 中，Variant、Dictionary 只能在明确的数据边界使用。

---
0-B.2 Variant Policy

允许：
- Raw Content。
- 外部未知输入。
- Editor Metadata。
- Debug Metadata。
- Schema Parser Boundary。

默认禁止作为：
- Domain State。
- Command Payload。
- Event Payload。
- Actor Runtime State。
- Save DTO。
- 跨模块核心 Contract。

如确需使用，必须登记 Dynamic Data Boundary。

---
0-B.3 Dictionary Policy

允许：
- Raw JSON / Authoring 数据。
- 配置载荷。
- 临时工具数据。
- 明确的扩展 Metadata。

禁止：
- 用 Dictionary 代替核心 Runtime State。
- 用 Dictionary 代替 Command / Event Contract。
- 用 Dictionary 作为跨模块万能上下文。
- 用 Dictionary 隐藏字段版本变化。

核心状态优先 class_name + typed fields。

---
0-B.4 class_name Policy

跨模块公共类型必须拥有稳定 class_name。

公共类型至少包括：
- Command
- Query
- Event
- Error
- Result
- Definition Runtime Type
- Transaction Contract
- Actor Contract
- Repository Contract

---
0-B.5 @abstract Policy

@abstract 用于：
- 多实现 Contract。
- 测试替换点。
- 平台差异。
- 策略替换。

禁止为了“看起来像接口”而无意义抽象。

架构中的 Interface 是“角色”，不强制对应 IXXX 命名。

---
0-B.6 泛型 Policy

不以泛型为核心架构前提。

优先：
NpcRepository
QuestRepository
ItemRepository

而不是强行构造：
IRepository<T>
Cache<T>
Event<T>

原因：减少 GDScript 语言负担、降低 AI 误解和公共 Contract 复杂度。

---
0-B.7 Readonly Policy

GDScript 核心数据不得依赖“假想 readonly”。

使用：
- 私有 backing field。
- Getter。
- 受控 Mutation API。

例如：
var _actor_id: StringName

func get_actor_id() -> StringName:
    return _actor_id

不得提供一个无业务约束的公共 Setter 作为状态后门。

---
0-B.8 RefCounted Policy

以下类型优先使用 RefCounted / 纯数据对象，而非 Node：
- Command
- Query
- Result
- Error
- Domain State
- Transaction
- Domain Event
- Actor Runtime Core Contract
- Test Double

Node 留给 Godot Engine / Scene / Presentation / Adapter Boundary。

---
0-B.9 Node Boundary

核心 Domain 默认禁止：
Node
Node2D
Node3D
Control
SceneTree
Resource
PackedScene
Input
RenderingServer
AudioServer
FileAccess
DirAccess
ProjectSettings

除非明确属于 Godot Adapter 白名单。

---
0-B.10 Scene Boundary

Scene 是运行时载体，不是 Domain State。

Scene 可以承载：
- Presentation Node。
- ActorNodeAdapter。
- Physics / Navigation Adapter。
- UI。
- Animation。

Scene 不成为：
- Player 数据库。
- NPC 持久状态数据库。
- Quest State Source of Truth。

---
0-B.11 Autoload Policy

Autoload 必须进入白名单。

原则：
- 基础运行时入口可以使用。
- 业务状态不得通过 Global Singleton 共享。
- 每个 Service 一个 Autoload：默认禁止。
- GameManager 不能复活为 God Object。

Autoload 新增默认触发 STOP + Shared Foundation Review。

---
0-B.12 Signal Policy

Signal 用于：
- Presentation。
- Local component notification。
- Actor lifecycle / adapter notification。
- Animation / Audio / UI integration。

跨业务事实优先使用 Typed Domain Event。

禁止：
signal something_happened(data: Dictionary)

Signal 不能成为第二套隐形业务总线。

---
0-B.13 preload / load Policy

核心业务层禁止自行通过资源路径解决依赖。

业务代码优先使用：
- class_name。
- Registry。
- Factory。
- Provider。
- Contract。

Godot 资源加载由 Infrastructure / Presentation / Adapter 管理。

---
0-B.14 get_tree / get_node Policy

Domain / Kernel：禁止。
Application：默认禁止直接调用。
Actor Runtime：默认禁止通过绝对路径抓取业务对象。
Presentation / Godot Adapter：允许。

禁止：
get_node("/root/GameManager")

禁止通过 SceneTree 隐式获取业务依赖。

---
0-B.15 Side Effect Policy

Getter 不得修改业务状态。
Constructor 不得偷偷启动世界操作。
Parser 不得顺手写 Save。
Query 不得修改业务状态。
Event Publish 不得反向执行隐藏业务。

---
0-B.16 Result / Error Policy

禁止混乱返回：
true / false / null / Dictionary / String / Error 混合。

统一使用强类型 Result：
OperationResult
CommandResult
SaveResult
LoadResult
BuildResult
ValidationResult

Error 至少提供：
error_code
context
causation / correlation（适用时）

---
0-B.17 Command / Query Policy

Command：请求改变状态。
Query：读取状态，不改变状态。

所有玩家、AI、剧情、Editor Automation、Replay 的状态改变请求原则上统一映射为 Command。

---
0-B.18 Public API Policy

任何新增 Public：
- class
- method
- signal
- event
- enum
- field

必须更新：
Contract Registry
Module Card
Impact Radius

禁止“先公开，之后再说”。

---
0-B.19 Code Size / God Object Heuristic

自动检查可以提示：
- Public method 数量异常。
- 跨越多个业务职责。
- 同时拥有 Save / Combat / Quest / UI / Inventory 等多类职责。

该检查属于 REVIEW，不自动等同违法；但严重候选必须经过 Module Owner Review。

---
0-C. Execution / Transaction / Rollback 工程标准

本章正式把“状态变化如何执行”写成统一语义。

---
0-C.1 三种核心对象

State
= 当前事实。

Command
= 请求做什么。

Event
= 已经发生什么。

不得混用。

---
0-C.2 Execution 总链

Command
    ↓
Command Validation
    ↓
Transaction Begin
    ↓
Prepare / Precheck
    ↓
Domain Execution
    ↓
Mutation Journal
    ↓
Invariant Validation
    ↓
Commit / Rollback
    ↓
Committed Event Publish
    ↓
Projection / Presentation

---
0-C.3 Transaction Boundary

Transaction 是一组必须作为整体成功/失败的状态变化。

典型：
- Buy。
- Sell。
- Trade。
- Craft。
- Equipment Change。
- Marriage Formation。
- Quest Reward。
- Combat Resolution（当多个 Owner 状态必须原子协调时）。

不是所有函数都必须创建 Transaction；纯查询和纯计算不得制造无意义 Transaction。

---
0-C.4 Transaction Owner

Transaction Engine 拥有：
- Begin。
- Commit。
- Rollback。
- Mutation Journal 生命周期。
- Pending Event 生命周期。

业务 Module 拥有：
- 自己的 State。
- 自己的 Domain Rule。
- 自己的 Mutation。

Application 拥有：
- Use Case / Transaction Orchestration。

---
0-C.5 Mutation Journal

每个可逆 Mutation 必须登记：
- target_id
- owner_module
- state_key
- before
- after
- undo strategy
- sequence

Rollback 不允许依赖“猜测式补偿”。

错误：
扣 100
失败
再加 100

正确：
记录 Before = 500
记录 After = 400
Rollback = 恢复 500

---
0-C.6 Commit 规则

只有以下条件全部满足才允许 Commit：
- 所有 Required Mutation 完成。
- 所有 Invariant 通过。
- 所有 Required Cross-Module Precondition 满足。
- Transaction 未取消。
- Required Persistence Boundary 满足（若该 Transaction 要求持久化）。

---
0-C.7 Event 规则

事务内：Pending Event。

事务 Commit 后：Committed Event。

只有 Committed Event 才能进入公开 Event Dispatcher。

禁止：
Transaction 未 Commit
    ↓
Publish ItemPurchasedEvent

---
0-C.8 Rollback 规则

Rollback 必须：
1. 按 Mutation Journal 逆序执行。
2. 恢复事务前状态。
3. 不发布原事务的业务成功 Event。
4. 记录 Rollback Outcome。
5. 如 Rollback 自身失败，进入 FATAL / RECOVERY_REQUIRED，而不是静默吞错。

---
0-C.9 Rollback Failure

如果：
Mutation A 成功
Mutation B 成功
Mutation C 失败
Mutation B Undo 失败

则系统不得声称：
“已正常回滚”。

必须输出：
TRANSACTION_RECOVERY_REQUIRED

并记录：
transaction_id
mutation sequence
failed undo
current known state
recovery action

---
0-C.10 Nested Transaction Policy

V1.2 第一阶段默认：
Nested Transaction = JOIN EXISTING 或明确拒绝。

禁止未经定义的“Transaction 中再开 Transaction”产生两个独立 Commit。

若实现 Nested Savepoint，必须单独 ADR + Contract + Test。

---
0-C.11 Async Boundary

Domain 核心规则默认同步、确定性、可测试。

Async 可以存在于：
- Infrastructure。
- Presentation。
- Application Workflow。
- Save / Load。
- Streaming。

如果 Async 跨越 Transaction，必须显式记录：
PENDING
RUNNING
COMMITTED
FAILED
CANCELLED

禁止：
先修改状态
await
再决定是否完成事务

---
0-C.12 Cancellation

任何可取消的长期操作必须定义：
- Cancel Point。
- State Guarantee。
- Rollback / Resume Policy。
- Timeout。

---
0-C.13 Command Queue

所有会改变核心世界状态的命令建议进入统一 Command Scheduler / Queue。

Command 元数据至少包括：
command_id
sequence
source
actor_id（适用时）
timestamp / game_tick
correlation_id
causation_id

---
0-C.14 Command Ordering

同一执行域内优先按：
1. sequence
2. 明确定义的 priority
3. deterministic tie-breaker

禁止依赖 Dictionary 遍历顺序、Node Tree 偶然顺序或线程调度偶然顺序来决定业务结果。

---
0-C.15 Scheduler 分层

必须区分：
- Command Scheduler
- Actor Scheduler
- World Simulation Scheduler
- Persistence Scheduler

禁止一个万能 Scheduler 同时承担四类不同职责。

---
0-C.16 Actor Tick Policy

Actor Runtime 可拥有：
REALTIME
ACTIVE
REDUCED
SIMULATION
SUSPENDED

但 Actor Tick 不得取代 Command Execution。

---
0-C.17 Event Handler 失败

Event 是已提交事实。

一个后置 Handler 失败，不得反向声称原 Domain Transaction 未发生。

必须根据事件语义决定：
- Retry
- Dead-letter
- Rebuild Projection
- Recovery Task

而不是对已提交事实执行假回滚。

---
0-C.18 Save 与 Transaction

如果业务要求：
“Commit 成功后必须可持久化”
则 Save 应位于明确的 Post-Commit Persistence Boundary。

不能默认把：
Save 写盘
当成 Domain Transaction 的一部分，除非该边界有明确能力和 Recovery 策略。

第一版推荐：
Domain Transaction Commit
    ↓
Committed Event
    ↓
Persistence Snapshot / Journal Update
    ↓
Durability Gate

---
0-C.19 Purchase Golden Case

购买成功：
GoldAfter = GoldBefore - Price
InventoryAfter = InventoryBefore + Item

购买失败：
GoldAfter = GoldBefore
InventoryAfter = InventoryBefore

这是 VS-001 的永久 Golden Invariant。

---
0-C.20 Transaction Test Matrix

至少覆盖：
- 正常成功。
- Precheck 失败。
- 第一 Mutation 失败。
- 中间 Mutation 失败。
- 最后一 Mutation 失败。
- Invariant 失败。
- Cancel。
- Timeout。
- Event Handler 失败。
- Save Failure。
- Rollback Failure。

---
0-D. AI 施工执行协议 V1.2

---
0-D.1 AI 开工前必须读取

1. Current Constitution。
2. Current Architecture。
3. Module Card。
4. Contract Registry。
5. Current Task。
6. Required Tests。
7. Relevant Legacy Reference。
8. Current Freeze Manifest（如任务触及 Foundation）。

---
0-D.2 AI 开工前十问

1. 我在哪个 Module？
2. Module 负责什么？
3. Module 不负责什么？
4. 我要写入哪个 State？
5. State Owner 是谁？
6. 我要调用哪个 Contract？
7. 这是 Command / Query / Event / Condition / Effect / Rule 中哪一种？
8. 事务边界是什么？
9. 失败怎么回滚？
10. 我要增加什么 Test 与 Gate Evidence？

---
0-D.3 Task Scope Lock

每个 AI Task 必须声明：
TASK_ID
ROLE
PERMISSION
MODULE
OWNER
ALLOWED_FILES
FORBIDDEN_FILES
DEPENDENCIES
CONTRACT_VERSION
EXPECTED_IMPACT_RADIUS
REQUIRED_GATES
OUT_OF_SCOPE

---
0-D.4 Changed File Enforcement

AI 声明的 ALLOWED_FILES 与实际 Changed Files 必须比较。

实际范围 > 授权范围：
FAIL / REVIEW REQUIRED。

即使额外文件“只是顺手改了一下”，也不能绕过。

---
0-D.5 Shared Foundation Write Lease

Shared Foundation 修改必须拥有：
lease_id
owner
scope
reason
related_acr
related_adr
allowed_files
start_revision
release_condition

同一 Scope 不允许两个并行 Write Lease。

---
0-D.6 Contract Freeze

公共 Contract 一旦进入 FROZEN：
AI 可以消费。
AI 可以测试。
AI 可以提出 Proposal。
AI 不得未经授权修改。

---
0-D.7 Contract Change

修改 Public Contract 必须：
ACR
Impact Analysis
Decision
Version Bump
Consumer Scan
Migration / Compatibility
Tests
Gate

---
0-D.8 AI Failure / Blocked Report

AI 无法安全继续时必须输出：
TASK-ID
STATUS
FAILED_STAGE
EXPECTED
ACTUAL
REPRODUCTION
AFFECTED_FILES
AFFECTED_MODULES
OWNER
STOP_RULE
EVIDENCE
SAFE_CHANGES_ALREADY_MADE
ROLLBACK_STATUS
NEEDED_DECISION
SUGGESTED_NEXT_TASK

禁止用临时代码把 BLOCKED 改成 DONE。

---
0-D.9 AI 最小变更原则

默认：
修改最少文件。
新增最少公共 API。
增加最少依赖。
不做无关重构。
不做未经授权的“顺手优化”。

---
0-D.10 AI 不得自创 Manager

发现缺能力时，按顺序考虑：
已有 Contract
已有 Module
已有 Capability
已有 Provider
已有 Factory
已有 Registry
已有 Application Use Case

仍不足：
提交 ACR。

---
0-D.11 AI 不得自创术语

继续遵守 GLOSSARY。
新术语必须：
Proposal → ADR / Glossary → Contract（如适用）

---
0-D.12 AI 施工结果必须可复现

任何“修好”至少要提供：
Test Result
Architecture Result
Regression Result
必要时：
Seed
Clock
Command Sequence
Build Revision

---
0-E. 自动化 Enforcement 体系

---
0-E.1 Enforcement 层级

E0 = 文档说明。
E1 = Review。
E2 = 自动化 Test。
E3 = Static / Structural Scan。
E4 = Build / Merge Block。

---
0-E.2 Architecture Validator

第一阶段至少拥有：
- dependency_validator
- forbidden_api_validator
- module_scope_validator
- changed_file_scope_validator
- contract_drift_validator
- state_owner_validator
- naming_validator

---
0-E.3 Forbidden Dependency Check

至少扫描：
Domain → Godot
Domain → JSON
Domain → Database
Presentation → Domain mutation
Actor → Storage
Actor → absolute SceneTree access

---
0-E.4 Forbidden API Check

按 Module 白名单扫描：
FileAccess
DirAccess
JSON
ResourceLoader
SceneTree
get_tree
get_node
ProjectSettings
Random APIs
System Time APIs

不是全工程一律禁止，而是按层级与 Module Policy 检查。

---
0-E.5 Contract Drift Check

比对：
CONTRACTS
vs
实际 class / method / signal / event signature

发现 Drift：
FAIL。

---
0-E.6 State Ownership Check

扫描：
- 多模块写入同一核心状态。
- 非 Owner 直接 Mutation。
- Runtime State 与 Save State 无 Owner。
- 重复的完整状态副本。

发现：
FAIL / REVIEW REQUIRED。

---
0-E.7 Scope Gate

实际修改文件超出 Task Scope：
FAIL。

如属于 Shared Foundation：
WRITE LEASE_REQUIRED。

---
0-E.8 Architecture Health

继续使用 V1.1 已建立的：
Fan-in
Fan-out
Cross-module Imports
Circular Dependencies
Public API Count
Shared Foundation Change Frequency
Changed Files per Feature
Contract Drift
Schema Drift
Save Drift
God Object Warnings
Duplicate Infrastructure
Regression Failures
Performance Regression
Context Staleness
Unowned State

V1.2 新增：
- Scope Violations
- Enforcement Coverage
- Transaction Recovery Incidents
- Rollback Failure Count
- Command Queue Ordering Violations
- Contract Change Lead Time

---
0-E.9 verify_all

统一入口至少执行：
1. GDScript / Compiler Check
2. Warning Policy Check
3. Architecture Dependency Check
4. Forbidden API Check
5. Scope Check
6. Contract Drift Check
7. Unit Tests
8. Contract Tests
9. Integration Tests
10. Migration Tests（适用时）
11. Vertical Slice Tests（受影响时）
12. Performance Regression（受影响时）
13. Build Smoke

---
0-F. Vertical Slice Engineering Protocol

---
0-F.1 VS 不再是“大开发完成后的验收”

Vertical Slice 是持续开发主线。

每增加一层 Foundation，就至少有一个可运行 Slice 使用它。

---
0-F.2 VS-001 Merchant Purchase

最小范围：
Player
Merchant
Potion
Gold
Inventory
BuyItemCommand
Transaction
Save
Load

链路：
Player Input
 ↓
Command
 ↓
Application
 ↓
Transaction
 ↓
Economy
 ↓
Inventory
 ↓
Commit
 ↓
Committed Event
 ↓
Presentation
 ↓
Save
 ↓
Load
 ↓
Invariant Check

---
0-F.3 VS-001 必须故意测试失败

Case A：正常购买。
Case B：余额不足。
Case C：库存不足。
Case D：中间 Mutation 失败。
Case E：Rollback Failure。
Case F：Save Failure。
Case G：Reload。

---
0-F.4 VS-002 Dialogue / Quest

Player
 ↓
Talk
 ↓
Dialogue
 ↓
Choice
 ↓
Condition
 ↓
StartQuestCommand
 ↓
Quest State
 ↓
Save

---
0-F.5 VS-003 Combat

Player
 ↓
AttackCommand
 ↓
Combat
 ↓
Deterministic RNG
 ↓
Damage
 ↓
Death
 ↓
Loot
 ↓
Committed Events
 ↓
Save

---
0-F.6 VS-004 Time / Schedule

FakeClock
 ↓
Advance Time
 ↓
Schedule Resolver
 ↓
NPC Activity
 ↓
Shop Refresh / Quest Timeout / World Event
 ↓
Save

---
0-F.7 VS-005 Actor Materialization

World Simulation State
 ↓
Materialize
 ↓
Actor Runtime
 ↓
Active
 ↓
Dematerialize
 ↓
World Simulation State
 ↓
Rematerialize

核心状态必须一致。

---
0-F.8 Slice Regression Policy

任何影响：
Command
Transaction
Actor
Save
Content
Application
Domain
Presentation Critical Flow

的架构变更，必须重新运行对应 Vertical Slice。

---
0-G. 多 AI Build Protocol

---
0-G.1 Role 与 Permission 分离

继续采用：
Role = 负责什么。
Permission = 可以改什么。

---
0-G.2 推荐 AI 角色

AI-ARCH
AI-DOMAIN
AI-EXECUTION
AI-INFRA
AI-CONTENT
AI-ACTOR
AI-UI
AI-STUDIO
AI-TEST
AI-REVIEW

不要求每个角色都必须由独立模型承担。

---
0-G.3 Owner AI

一个模块的核心 Domain / Application / Infrastructure 最好只有一个 Owner AI 主导施工。

其他 AI：
Test
Content
Presentation
Proposal
可以并行。

---
0-G.4 Reviewer AI

Reviewer 默认：
READ ONLY

输出：
PASS
REQUEST_CHANGES
BLOCK

Reviewer 不得为了“帮忙”偷偷修改实现代码。

---
0-G.5 AI Context Pack

标准加载顺序：
Constitution
 ↓
Architecture
 ↓
Module Map
 ↓
Module Spec
 ↓
Task
 ↓
Contracts
 ↓
Tests
 ↓
Legacy

Legacy 永远最后读取。

---
0-G.6 Context Staleness

Context Pack 必须携带：
constitution_version
architecture_version
contract_versions
schema_versions
save_schema_version
verified_revision

如果与 Freeze Manifest 不一致：
STALE

STALE Context 不得用于 Foundation 修改。

---
0-G.7 AI Handoff

必须提供：
Current State
Known Issues
Changed Contracts
Tests
Pending Tasks
Risks
Current Revision
Context Version

---
0-G.8 AI 并行禁区

以下 Scope 不允许无锁并行：
Kernel
Public Command
Public Query
Public Event
Transaction Contract
Content Schema
Save Schema
Composition Root
Module Loader
Capability Registry

---
0-G.9 并行开发的正确条件

可以并行：
Actor + Content
NPC + Test
Combat + UI Preview
Quest + Content

前提：
Contract Frozen
Scope Non-overlap
Foundation Lease 不冲突

---
0-G.10 Merge Gate

Merge 必须满足：
Compiler PASS
Architecture PASS
Contract PASS
Required Tests PASS
Regression PASS
Scope PASS

受影响 Vertical Slice：必须 PASS。

---
0-H. 文档 / Contract / Task 三联机制

---
0-H.1 Constitution

最高规则。

---
0-H.2 Architecture

定义结构与边界。

---
0-H.3 Module Contract

定义公共交互。

---
0-H.4 Module Spec

定义具体模块怎么施工。

---
0-H.5 Task Card

定义当前 AI 这一次只能做什么。

---
0-H.6 三联关系

Constitution
    ↓
Architecture
    ↓
Module Contract
    ↓
Module Spec
    ↓
Task Card

任何向上修改都必须通过 ACR / ADR。

---
0-H.7 完工定义

COMPLETE 只有在：
Implementation
Contract Compliance
Architecture Compliance
Required Tests
Required Gates
Regression
Documentation

全部满足时成立。

---
0-I. 版本与变化的机械化传播

任何以下变化：
Constitution
Architecture
Contract
Schema
Save
Module Manifest
Capability Registry

必须执行：
Detect
 ↓
Impact Analysis
 ↓
Decision
 ↓
Version Bump
 ↓
Migration / Compatibility
 ↓
Context Rebuild
 ↓
Gate
 ↓
Implementation
 ↓
Verification
 ↓
Freeze

---
0-J. V1.2 施工哲学

不是要求 AI 永远不犯错。

而是让错误尽可能在最早层被发现：

拼写 / 类型错误
→ Compiler

错误依赖
→ Architecture Scanner

错误 Contract
→ Contract Test

错误业务规则
→ Domain Test

错误事务
→ Transaction Test

错误跨模块链路
→ Integration Test

错误完整行为
→ Vertical Slice

错误权限
→ Scope Gate

错误架构变化
→ ACR / ADR

最终目标：

让 AI 可以高速施工，
但不能通过猜测、越权、隐藏副作用、破坏事务一致性或制造全局耦合来换取速度。

---
---
1. 项目最高目标
本项目追求的不是：
尽可能少写代码。
也不是：
尽可能复杂地设计架构。
真正目标是：
在长期、大规模、多 AI、多人协作、持续增加内容、持续增加系统的情况下，使任何一次变化的影响范围尽可能小。
核心指标：
低耦合
高内聚
高可测试
高可替换
高可扩展
高可观测
高可维护
高可迁移
高内容生产效率
高 AI 协作稳定性
最终追求：
新增内容 → 尽可能数据化

新增规则 → 尽可能局部化

新增系统 → 尽可能模块化

替换基础设施 → 不影响 Domain

替换 UI → 不影响 Domain

替换数据库 → 不影响 Gameplay

替换 AI → 不影响 Combat

删除可选模块 → 不破坏核心系统

---
2. 最重要的十条铁律
RULE 001：Domain 不认识 Godot
Domain 禁止依赖：
Node
Node2D
Control
SceneTree
Resource
PackedScene
Input
RenderingServer
AudioServer
FileAccess
DirAccess
ProjectSettings
Domain 只能处理：
数据
规则
状态
命令
查询
事件
事务

---
RULE 002：Domain 不认识 JSON
Domain 不允许：
读取 JSON
写 JSON
解析 JSON
决定 JSON 路径
JSON 属于 Infrastructure / Content Pipeline。

---
RULE 003：Domain 不直接访问数据库
禁止：
NPC → SQLite
Quest → SQLite
Combat → SQLite
Marriage → SQLite
必须：
Domain
  ↓
Repository Interface
  ↓
Infrastructure Adapter
  ↓
Database

---
RULE 004：UI 不直接修改 Domain
错误：
Button
  ↓
player.gold -= 100
正确：
Button
 ↓
Command
 ↓
Application
 ↓
Domain
 ↓
Event
 ↓
ViewModel
 ↓
UI

---
RULE 005：Command、Query、Condition、Effect、Event、Rule 必须语义分离
Command
表达：
我要做什么。
例如：
BuyItemCommand
MarryCommand
AttackCommand
AcceptQuestCommand
EquipItemCommand
Query
表达：
当前是什么状态。
例如：
GetNPCQuery
GetRelationshipQuery
GetPlayerInventoryQuery
GetCombatStateQuery
Condition
表达：
能不能做。
例如：
HasEnoughMoneyCondition
MarriageEligibilityCondition
QuestRequirementCondition
LevelRequirementCondition
Effect
表达：
状态发生什么变化。
例如：
AddItemEffect
RemoveMoneyEffect
ChangeRelationshipEffect
ApplyStatusEffect
CompleteQuestEffect
Event
表达：
已经发生了什么。
例如：
ItemPurchasedEvent
MarriageFormedEvent
QuestCompletedEvent
CombatEndedEvent
NPCDiedEvent
Event 不负责主动执行其他业务。
Rule
表达：
一组业务判断为什么成立。
例如：
MarriageEligibilityRule
PurchaseRule
QuestCompletionRule
CombatActionRule
Rule 不负责 UI、文件、数据库、音频、场景或流程编排。

---
RULE 006：Definition、Runtime State、Save DTO 必须分离
Definition：
描述“它是什么”。

Runtime State：
描述“它现在是什么状态”。

Save DTO：
描述“它如何被持久化”。

禁止：
把 Content Definition、运行时状态、数据库字段、存档结构塞进同一个对象。
任何 Save 变化不得反向污染 Domain Definition。

---
RULE 007：每种核心状态必须存在唯一 Owner
任何可变化的核心状态：
必须且只能存在一个写入 Owner。

非 Owner 模块：
可以通过 Query 读取，
可以通过 Command 请求变化，
可以通过 Event 观察事实，
可以通过 Port / Interface 使用明确能力，
但不得直接修改 Owner 内部状态。

无法确定 Owner：
STOP。

---
RULE 008：跨模块只通过公开契约连接
跨 Domain Module 默认只允许：
Query
Command
Event
Port / Interface

禁止：
模块 A 直接调用模块 B 的内部 Service、Repository 实现、Entity 内部字段或私有 Handler。

跨模块需要新增依赖：
必须声明 Dependency Impact，
必要时进入 Architecture Review。

---
RULE 009：Shared Foundation 必须冻结并单线程治理
Kernel
Public Command
Public Query
Public Event
Repository Contract
Content Schema
Save Schema
Composition Root
Module Loader
Capability Registry
属于 Shared Foundation。

Shared Foundation 默认冻结。
同一时间只能存在一个明确 Write Owner / Write Lease。
普通 Gameplay AI 只能消费，不能擅自修改。

---
RULE 010：没有可复现证据，不算完成
AI 的：
“我检查过了”
“应该没问题”
“理论上能跑”
不等于 PASS。

完成必须至少存在：
Test Result
Architecture Gate
Required Contract Gate
Regression Evidence
Implementation Report

任何要求必须通过的 Gate 未执行或结果未知：
状态只能是 UNKNOWN / BLOCKED，
不能声明 COMPLETE。


---
3. 架构总层级
整体结构：
Presentation
      ↓
Application
      ↓
Execution / Transaction Runtime
      ↓
Domain
      ↓
Domain Contracts
      ↑
Infrastructure
      ↑
Content / Persistence / Platform
推荐目录：
project/
│
├── app/
│   ├── composition/
│   ├── bootstrap/
│   ├── module_loader/
│   └── application_root/
│
├── domain/
│   ├── kernel/
│   ├── actor/
│   ├── npc/
│   ├── world/
│   ├── relationship/
│   ├── faction/
│   ├── romance/
│   ├── marriage/
│   ├── family/
│   ├── children/
│   ├── progression/
│   ├── item/
│   ├── inventory/
│   ├── equipment/
│   ├── crafting/
│   ├── economy/
│   ├── shop/
│   ├── ability/
│   ├── combat/
│   ├── quest/
│   ├── dialogue/
│   ├── story/
│   └── achievement/
│
├── application/
│   ├── commands/
│   ├── queries/
│   ├── handlers/
│   ├── orchestration/
│   └── services/
│
├── infrastructure/
│   ├── persistence/
│   ├── repositories/
│   ├── database/
│   ├── filesystem/
│   ├── localization/
│   ├── audio/
│   ├── assets/
│   ├── platform/
│   ├── random/
│   └── clock/
│
├── presentation/
│   ├── scenes/
│   ├── ui/
│   ├── viewmodels/
│   ├── input/
│   ├── camera/
│   └── animation/
│
├── content/
│   ├── schemas/
│   ├── definitions/
│   ├── packs/
│   ├── localization/
│   ├── indexes/
│   └── generated/
│
├── studio/
│   ├── editor/
│   ├── inspector/
│   ├── graph/
│   ├── validator/
│   ├── preview/
│   └── builder/
│
├── tests/
│   ├── unit/
│   ├── integration/
│   ├── architecture/
│   ├── contract/
│   ├── migration/
│   ├── content/
│   ├── ui/
│   ├── performance/
│   └── regression/
│
├── tools/
│   ├── architecture/
│   ├── validation/
│   ├── build/
│   ├── migration/
│   ├── testing/
│   └── ai/
│
└── docs/
    ├── constitution/
    ├── architecture/
    ├── modules/
    ├── contracts/
    ├── adr/
    ├── ai/
    └── legacy/

---
4. 模块等级
所有模块必须属于以下等级之一。
Level 0：Kernel
不可删除。
ID
Result
Error
Command
Query
Condition
Effect
Event
Transaction
Clock
Random
Repository Contract

---
Level 1：Foundation
高度稳定。
Actor
World
Persistence
Content
Application
Composition
原则：
非重大 ADR 不修改。

---
Level 2：Gameplay Module
可独立开发。
例如：
NPC
Faction
Relationship
Marriage
Family
Quest
Dialogue
Combat
Crafting
Housing
Politics
Achievement

---
Level 3：Content
高度可变。
NPC Definition
Quest Definition
Dialogue
Item
Weapon
Enemy
Map
Story
Localization
内容变化原则上不应该修改 Domain。

---
5. 模块主权制度
每种核心状态必须存在唯一 Owner。
核心状态 Owner 基线表：
Kernel 基础抽象 / ID / Result / Command / Query / Event 抽象
→ Kernel / Core Architecture

Actor Identity / Actor 基础身份
→ Actor

NPC Identity / NPC Runtime State
→ NPC

Region / Location / Calendar / Weather / World State
→ World

NPC Schedule Definition / Schedule State
→ Schedule

Relationship Edge / Relationship Score / Relationship Type
→ Relationship

Romance Stage / Romance Progress
→ Romance

Marriage State / Proposal / Spouse State
→ Marriage

FamilyUnit / Household / ParentChildRelation / Inheritance
→ Family

Pregnancy State / Pregnancy Progress
→ Pregnancy

Child Age Stage / Child-specific Growth State
→ Children（Actor / NPC 仍拥有通用人物身份）

Faction State / Membership / Rank / Reputation / Faction Relation
→ Faction

Experience / Level / Talent / Skill Tree / Progression State
→ Progression

Item Definition / Item Instance Identity
→ Item

Inventory Container / Slot / Stack
→ Inventory

Equipment Slot / Loadout / Equip State
→ Equipment

Recipe / Crafting Transaction State
→ Crafting

Currency / Wallet / Price / Economic Transaction
→ Economy

Shop Definition / Shop Inventory / Buy-Sell Entry State
→ Shop

Ability Definition / Ability Cost / Cooldown / Ability Modifier
→ Ability

CombatSession / CombatState / Combatant Runtime / CombatResult
→ Combat

QuestDefinition / QuestState / Objective Progress
→ Quest

DialogueGraph / Dialogue Runtime State
→ Dialogue

Story Arc / Chapter / Story Orchestration State
→ Story

Content Definition / Content Pack / Content Version / Content Index
→ Content

SaveDTO / Save Version / Save Migration
→ Save / Persistence

ViewModel / UI-local transient display state
→ Presentation
但 Presentation 不拥有业务状态。

Owner 规则：
1. 一个状态只能有一个写 Owner。
2. “多个模块都需要”不等于“多个模块都能写”。
3. 其他模块只保存稳定 ID / Snapshot / Contract View，不复制 Owner 的完整可变状态。
4. 如果状态归属发生争议，必须先解决 Owner，再实现功能。
5. 新模块增加新状态时，module_contract.md 必须登记 Owner。
6. Architecture Test 应检查重复 Owner、越权写入和跨模块内部状态访问。

规则：
非 Owner 模块不得直接修改 Owner 状态。

---
6. 模块必须声明“负责什么”和“不负责什么”
每个模块文档必须存在：
Responsibilities

Non-Responsibilities
例如 Marriage：
负责：
- 婚姻资格
- 求婚
- 婚姻建立
- 婚姻解除
- 配偶关系状态

不负责：
- 恋爱好感
- 怀孕
- 子女
- 背包
- 婚礼 UI
- 任务奖励
这样可以防止模块无限膨胀。

---
7. 模块标准结构
每个模块必须拥有：
module/
├── domain/
├── application/
├── contracts/
├── infrastructure/
├── content/
└── tests/
模块施工图必须包含：
1. 模块定位
2. 职责
3. 非职责
4. 依赖
5. Entity
6. Value Object
7. Runtime State
8. Command
9. Query
10. Condition
11. Effect
12. Event
13. Repository
14. Content Schema
15. Save DTO
16. Error
17. Transaction
18. 生命周期
19. API
20. 测试
21. 扩展点
22. 删除策略
23. 性能策略
24. Migration
25. Debug

---
8. AI开发总原则
AI 不是架构师。
除非明确赋予 Architecture Role，否则：
AI 是实现者。
AI 可以：
分析
设计局部实现
编写代码
编写测试
发现问题
提出建议
AI 不可以自行：
修改核心架构
修改模块边界
增加基础依赖
改变公共契约
改变 Save Schema
改变数据库 Schema
新增 Autoload
新增全局单例
重新定义术语
创建重复系统
发现这些需求：
STOP
提交 Architecture Change Request。

---
9. AI任务开始前必须执行的流程
每个任务：
READ
↓
LOCATE
↓
UNDERSTAND
↓
PLAN
↓
BOUNDARY CHECK
↓
CONTRACT CHECK
↓
IMPLEMENT
↓
TEST
↓
ARCHITECTURE CHECK
↓
REGRESSION
↓
REPORT

---
10. AI必须先回答十个问题
开始写代码之前必须输出：
1. 当前任务属于哪个模块？

2. 当前模块负责什么？

3. 当前模块不负责什么？

4. 本任务需要哪些外部能力？

5. 外部能力属于哪些 Owner？

6. 我通过什么方式访问？
   Command / Query / Event / Port

7. 是否需要修改其他模块？

8. 如果需要，为什么？

9. 是否存在架构风险？

10. 本任务需要新增哪些测试？
没有完成这十项，不允许进入实现阶段。

---
11. AI上下文加载顺序
AI 不得一开始读取整个项目然后自行总结架构。
标准上下文：
Level 1
PROJECT_CONSTITUTION

Level 2
ARCHITECTURE

Level 3
MODULE_MAP

Level 4
CURRENT_MODULE_SPEC

Level 5
CURRENT_TASK

Level 6
RELATED_CONTRACTS

Level 7
RELATED_TESTS

Level 8
LEGACY_REFERENCE
旧项目最后读取。

---
12. Legacy旧工程使用规则
旧工程定义：
LEGACY REFERENCE
而不是：
CURRENT ARCHITECTURE
旧代码可以用于：
功能考古
玩法发现
边界发现
Bug发现
测试迁移
数据迁移
UI行为参考
禁止用于：
架构复制
依赖复制
Service复制
API复制
命名权威
设计权威
冲突时：
NEW ARCHITECTURE WINS

---
13. Legacy迁移规则
旧系统迁移必须经历：
Legacy
 ↓
Feature Extraction
 ↓
Behavior Specification
 ↓
Data Extraction
 ↓
Test Extraction
 ↓
New Module Design
 ↓
New Implementation
 ↓
Migration
 ↓
Regression
绝不：
复制旧代码
↓
改名字
↓
宣布重构完成

---
14. AI禁止自行发明概念
所有领域术语必须进入：
docs/GLOSSARY.md
已有：
Relationship
AI 不得自行创建：
Bond
Affinity
SocialLink
Connection
Relation
来表达相同概念。
如果确实需要新概念：
ADR
+
Glossary

---
15. AI禁止重复创建基础设施
已有：
EventDispatcher
不得再创建：
NpcEventBus
QuestEventBus
MarriageEventManager
CombatSignalHub
除非架构明确批准。

---
16. STOP规则
以下情况必须停止：
STOP-001
修改 Kernel

STOP-002
修改公共 Contract

STOP-003
增加模块依赖

STOP-004
增加循环依赖

STOP-005
修改 Save Schema

STOP-006
修改 Database Schema

STOP-007
新增 Autoload

STOP-008
新增 Global Singleton

STOP-009
改变术语

STOP-010
修改其他模块内部实现

STOP-011
修改测试以适配错误代码

STOP-012
需求与架构冲突

STOP-013
无法确定数据 Owner

STOP-014
需要跨越模块边界

STOP-015
发现架构文档与实际代码不一致

---
16A. AI Failure / Blocked Protocol
当任务无法安全继续时，不允许用临时代码、TODO、关闭 Gate、修改测试或扩大权限掩盖问题。

必须输出：
AI FAILURE / BLOCKED REPORT

TASK-ID:

STATUS:
FAILED / BLOCKED / UNKNOWN

FAILED_STAGE:
READ / PLAN / IMPLEMENT / TEST / CONTRACT / ARCHITECTURE / REGRESSION / BUILD

EXPECTED:

ACTUAL:

REPRODUCTION:

AFFECTED_FILES:

AFFECTED_MODULES:

OWNER:

STOP_RULE:

EVIDENCE:

SAFE_CHANGES_ALREADY_MADE:

ROLLBACK_STATUS:

NEEDED_DECISION:

SUGGESTED_NEXT_TASK:

规则：
1. FAILED 表示已有明确失败证据。
2. BLOCKED 表示存在权限、依赖、契约、资料或环境阻塞。
3. UNKNOWN 表示无法验证，不得伪装成 PASS。
4. Failure Report 不自动授权 AI 修复上层架构。
5. Bug 修复仍遵守：Reproduce → Failing Test → Fix → Regression → Gate。
6. 如果失败来自规范/代码漂移，进入 STOP-015。
7. 如果失败来自架构冲突，进入 STOP-012，并提交 ACR。


---
17. AI任务卡标准
每个任务必须：
TASK-ID

TITLE

OBJECTIVE

MODULE

ALLOWED_FILES

FORBIDDEN_FILES

DEPENDENCIES

REQUIRED_IMPLEMENTATION

REQUIRED_TESTS

EXPECTED_GATES

IMPACT_RADIUS

OUT_OF_SCOPE
示例：
TASK-ID: NPC-CORE-001

TITLE:
建立NPC Identity Domain

MODULE:
NPC

ALLOWED:
domain/npc/identity/**
tests/unit/npc/identity/**

FORBIDDEN:
combat/**
marriage/**
quest/**
save/**
presentation/**

DEPENDENCIES:
Kernel
Actor

IMPACT_RADIUS:
L1

---
18. Impact Radius
所有修改必须声明影响范围：
L0 = 单文件

L1 = 单模块

L2 = 模块 + 测试

L3 = 多模块

L4 = Foundation

L5 = Core / Save / Public Contract
AI申报：
Impact Radius: L1
自动工具实际扫描：
L4
则：
WARNING / REVIEW REQUIRED

---
19. 共享地基权限
以下属于 Shared Foundation：
Kernel
Command
Query
Event
Repository Contract
ContentRegistry
Save
CompositionRoot
ModuleLoader
CapabilityRegistry
默认：
单AI单独占用
修改需要：
Architecture Review
+
Change Log
+
Regression

---
20. 多AI并行开发
推荐：
                    ARCHITECT
                        │
                    CONTRACT
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
      NPC AI         Combat AI        Quest AI
        │               │               │
        ▼               ▼               ▼
      Tests           Tests            Tests
        │               │               │
        └───────────────┼───────────────┘
                        ▼
                   Integration
                        ↓
                      Gates
允许：
NPC + Combat + Quest
并行。
禁止：
NPC AI
Combat AI
Quest AI
同时修改：
Kernel
Event
Save
CompositionRoot

---
21. AI角色划分
推荐固定角色：
AI-ARCH
负责：
架构
ADR
Contract
依赖
模块边界
AI-DOMAIN
负责：
Domain
Application
AI-CONTENT
负责：
Schema
Data
Localization
Content
AI-TEST
负责：
Unit
Integration
Regression
Architecture Test
AI-STUDIO
负责：
Editor
Validator
Build
Preview
AI-UI
负责：
Presentation
Scene
UI

---
21A. AI 权限等级与写权限
AI Role 与 AI Permission 是两件事：
Role 表示“负责什么”。
Permission 表示“允许改什么”。

P0 READ
允许：
读取文档、代码、测试、日志、Legacy。
禁止任何写入。

P1 CONTENT / TEST LOCAL
允许：
在任务卡授权范围内修改普通 Content、测试夹具、局部测试。
不得修改业务公共契约。

P2 MODULE IMPLEMENTER
允许：
修改单一模块内部 Domain / Application / Infrastructure / Tests。
前提：
ALLOWED_FILES 明确，
模块 Contract 已冻结，
不触碰 Shared Foundation。

P3 MODULE OWNER
允许：
批准模块内部 API 演进，
合并模块内变更，
协调模块级 Migration。
不得自行批准 Kernel / Save / Shared Contract 变化。

P4 SHARED FOUNDATION MAINTAINER
允许：
在 Architecture Change 已批准并取得 Write Lease 后修改：
Kernel
Public Contract
Content Schema
Composition
Module Loader
Capability Registry
Save Foundation

P5 ARCHITECTURE OWNER
允许：
批准 ACR / ADR / Foundation Freeze Change。
仍必须经过 Review、Migration Plan、Rollback Plan 与 Gates。
任何 AI 不得因为拥有 P5 Role 就跳过证据链。

权限原则：
最小权限。
任务结束即释放 Write Lease。
权限不能从“需要完成需求”反向推导。
没有明确权限：
视为无权限。


---
22. Architecture Change Request
需要架构变化时：
ARCHITECTURE CHANGE REQUEST

Reason

Current Problem

Affected Modules

Proposed Change

Alternative Solutions

Dependency Impact

Save Impact

Content Impact

Test Impact

Migration Plan

Rollback Plan
AI不得自行批准。

---
23. ADR制度
重大架构决策写：
ADR-XXXX
例如：
ADR-0001
为什么Domain不能依赖Godot

ADR-0002
为什么采用Repository

ADR-0003
为什么Combat使用CombatantSnapshot

ADR-0004
为什么Marriage不拥有Children

ADR-0005
为什么Save与RuntimeState分离
ADR一旦确立：
后续 AI 必须服从。
除非创建新的 ADR 推翻旧 ADR。

---
23A. 架构变更完整闭环
Architecture Change 不是“写一份 ADR”就结束。

必须经历：
Detect
↓
STOP / Quarantine
↓
Architecture Change Request
↓
Impact Analysis
↓
Architecture Review
↓
Decision
↓
ADR
↓
Version Bump
↓
Migration / Compatibility Plan
↓
Update Constitution / Architecture / Contract / Docs
↓
Rebuild AI Context Packs
↓
Implementation
↓
Architecture Gate
↓
Contract / Migration / Regression
↓
Freeze
↓
Change Log

任何一步缺失：
不得宣称架构变更完成。

---
23B. 架构决策状态
ACR 状态统一：
DRAFT
PROPOSED
UNDER_REVIEW
APPROVED
REJECTED
SUPERSEDED
IMPLEMENTED
VERIFIED
ROLLED_BACK

ADR 状态统一：
PROPOSED
ACCEPTED
SUPERSEDED
DEPRECATED

只有：
APPROVED / ACCEPTED
才能授权对应架构施工。

---
23C. 架构版本语义
Project Constitution、Architecture、Kernel Contract、Content Schema、Save Schema 均必须独立版本化。

推荐：
MAJOR.MINOR.PATCH

MAJOR：
破坏性架构或公共契约变化。

MINOR：
向后兼容的新能力、新规则或新字段。

PATCH：
不改变语义的修正、澄清、错字、文档修复。

禁止：
内容明显改变但版本号不变。

---
23D. 规范冲突处理
当两个已加载文档冲突：
1. 比较 Authority Level。
2. Authority 相同则比较已批准版本。
3. 仍无法确定则 STOP。
4. 不允许使用“更新日期看起来较新”代替正式版本。
5. 不允许 AI 自行把下位文档解释成已推翻上位文档。
6. 解决后必须产生 ADR / Change Log，并使旧规则明确 SUPERSEDED。


---
24. Entity规则
Entity：
具有稳定Identity
例如：
NPC
ItemInstance
Combatant
QuestState
MarriageState
Family
Entity 不负责：
数据库
UI
场景
动画
文件
输入

---
25. Definition / Runtime / Save三分法
所有复杂对象原则上分：
Definition
RuntimeState
SaveDTO
例如 NPC：
NPCDefinition
NPCState
NPCSaveDTO
Definition：
它是什么。
Runtime：
它现在是什么状态。
Save：
怎么保存。
三者不得混成一个对象。

---
26. ID规范
所有持久化对象拥有稳定 ID：
NPC_000001
QUEST_000001
ITEM_000001
FACTION_000001
DIALOGUE_000001
规则：
ID永不复用
ID不表达业务状态
ID不依赖显示名称
ID不随语言变化
删除：
retired
而不是重新使用。

---
27. Repository规范
Domain只依赖：
INPCRepository
IQuestRepository
IItemRepository
而不是：
SQLiteNPCRepository
JSONQuestRepository
FileItemRepository
后者属于 Infrastructure。

---
28. Database设计
数据库不是业务层。
建议逻辑划分：
Content Database
Runtime Database
Save Database
Content Database
保存：
NPC Definition
Item Definition
Quest Definition
Dialogue Definition
Ability Definition
Runtime Database
保存：
NPC State
Quest State
Relationship State
Faction State
World State
Save Database
保存：
SaveDTO
Version
Metadata
Checksum
Migration Information

---
29. Database不等于模块
禁止：
NPC Database
Marriage Database
Combat Database
Quest Database
每个系统都拥有一套数据库。
正确：
Domain Modules
       ↓
Repository
       ↓
Persistence Layer
       ↓
Database

---
30. 数据引用规则
对象之间尽量保存：
ID
而不是：
完整对象树
例如：
MarriageState
    spouse_a_id
    spouse_b_id
而不是：
Marriage
 ├── NPC_A
 │   ├── Inventory
 │   ├── Quest
 │   └── ...
 └── NPC_B
这样可以避免：
循环引用
巨大存档
重复状态
序列化爆炸

---
31. Save架构
Save Header：
save_version
game_version
content_version
timestamp
checksum
正文：
Player
World
NPCs
Quests
Relationships
Factions
Inventory
Equipment
Progression
CustomModules
必须支持：
Save Migration

---
32. Save Migration原则
禁止：
旧存档不能用了
除非经过明确版本策略。
迁移：
Save v1
 ↓
Migration v2
 ↓
Migration v3
 ↓
Current
每次 Migration 必须测试：
Input
Expected Output

---
33. Event规范
Event必须：
immutable
past tense
事实
推荐：
MarriageFormedEvent
ItemPurchasedEvent
QuestCompletedEvent
CombatEndedEvent
NPCDiedEvent
不要：
StartMarriageEvent
DoQuestEvent
ChangeNPCEvent
后者更像 Command。

---
34. Event不负责业务调用
错误：
MarriageFormedEvent
    ↓
Event内部调用
FamilyService
QuestService
AchievementService
正确：
MarriageFormedEvent
    ↓
Event Dispatcher
    ├── Family Handler
    ├── Quest Handler
    ├── Achievement Handler
    └── Journal Handler
Marriage不知道这些 Handler 存不存在。

---
35. Capability机制
可选模块使用：
CapabilityRegistry
例如：
MARRIAGE
HOUSING
POLITICS
CRAFTING
CHILDREN
查询：
is_capability_enabled(MARRIAGE)
而不是整个项目到处：
if marriage_service != null
删除 Marriage：
Capability = OFF
其他模块不应因此崩溃。

---
36. NPC模块
NPC只负责：
Identity
State
Attributes
Knowledge
Memory
NPC不拥有：
Combat
Quest
Marriage
Inventory
Faction
Relationship
Dialogue
这些是其他能力。
NPC通过：
Query
Command
Event
参与这些系统。

---
37. NPC Memory
建议：
PermanentMemory
TemporaryMemory
RumorMemory
FactionMemory
PersonalMemory
Memory本身可以成为独立模块。
NPC不需要知道 Memory 如何存数据库。

---
38. NPC Schedule
独立：
ScheduleDefinition
ScheduleEntry
ScheduleCondition
ScheduleOverride
ScheduleState
流程：
WorldTimeChanged
 ↓
ScheduleResolver
 ↓
NPCScheduleState
 ↓
NPCPosition / NPCActivity
NPC本体不硬编码一天的路线。

---
39. Relationship
Relationship负责：
人与人之间的关系
关系类型
关系状态
关系数值
关系规则
不负责：
婚姻
怀孕
子女
婚礼
这些是上层模块。

---
40. Romance
Romance建立在 Relationship 之上：
Relationship
      ↓
Romance
负责：
Romance Stage
Romance Eligibility
Romance Progress
Romance State
Romance Events
不负责：
Marriage
Pregnancy
Children

---
41. Marriage
Marriage负责：
Marriage Eligibility
Proposal
Proposal Acceptance
Marriage Formation
Marriage Dissolution
Spouse State
Marriage Events
流程：
ProposeMarriageCommand
 ↓
MarriageEligibilityRule
 ↓
Proposal
 ↓
ProposalAcceptedEvent
 ↓
MarriageTransaction
 ↓
MarriageFormedEvent
Marriage不负责：
Pregnancy
Children
Inventory
Quest Rewards
Wedding UI

---
42. Family
Family负责：
FamilyUnit
ParentChildRelation
Household
FamilyMembership
Inheritance
FamilyRules
Marriage形成：
MarriageFormedEvent
 ↓
Family Handler
而不是：
MarriageService直接创建Child

---
43. Pregnancy
独立模块：
PregnancyState
PregnancyRule
PregnancyProgress
PregnancyEvent
BirthEvent
Birth：
BirthEvent
 ↓
Family
 ↓
NPC
 ↓
Progression
 ↓
World

---
44. Children
Child应该是正常 Actor/NPC 体系的一部分。
不要创建：
ChildNPC
这种完全不同的生物。
应该：
Actor
  ↓
NPC
  ↓
Child State / Age Stage
年龄变化：
Infant
 ↓
Child
 ↓
Teen
 ↓
Adult

---
45. Faction
Faction负责：
FactionDefinition
FactionState
Member
Rank
Reputation
FactionRelation
Policy
Resource
Faction不拥有：
NPC
Quest
Combat
NPC只是 Faction Member。

---
46. Progression
负责：
Experience
Level
Attributes
Stats
Talent
SkillTree
Unlock
Milestone
Combat只读取：
CombatantSnapshot
不直接操作 Progression。

---
47. Item
分：
ItemDefinition
ItemInstance
ItemStack
ItemModifier
Affix
Definition：
物品是什么。
Instance：
这个具体物品是谁。

---
48. Inventory
Inventory负责：
Container
Slot
Stack
Add
Remove
Move
Split
Merge
Transaction
Inventory不负责：
Equipment
Shop
Crafting
Economy

---
49. Equipment
Equipment负责：
EquipmentSlot
Equip
Unequip
Loadout
Requirement
Modifier
装备产生 Modifier。
Inventory只负责拥有物品。

---
50. Crafting
统一：
Forge
Alchemy
Cooking
Crafting
使用：
RecipeDefinition
CraftingRule
CraftingRequirement
CraftingEffect
CraftingResult
不要为每种制作方式建立一套完全不同的系统。

---
51. Economy
Economy拥有：
Currency
Wallet
Price
EconomicRule
Transaction
Shop只负责：
商品展示
商店库存
购买/出售入口
真正金钱变化属于 Economy。

---
52. Ability
Ability数据驱动：
AbilityDefinition
AbilityCost
TargetRule
Condition
Effect
Cooldown
Modifier
例如一个技能：
Skill
 ↓
Target
 ↓
Condition
 ↓
Cost
 ↓
Effect
 ↓
Event

---
53. Combat
Combat必须是独立引擎。
核心：
CombatSession
CombatState
Combatant
Team
Turn
Action
Target
Ability
Modifier
StatusEffect
Damage
CombatResult
CombatLog

---
54. World与Combat隔离
正确：
World NPC
 ↓
CombatantSnapshot
 ↓
CombatSession
 ↓
CombatResult
 ↓
World
错误：
NPC extends Combatant
NPC直接进入战斗内部
这样可以让 Combat 独立测试。

---
55. Combat Action
统一：
Attack
UseAbility
UseItem
Move
Defend
Flee
Interact
Wait
Switch
玩家输入和 AI 都生成：
CombatCommand
所以：
Player
 ↓
Command Producer
 ↓
Combat

AI
 ↓
Command Producer
 ↓
Combat
Combat不关心是谁发出的命令。

---
56. Combat Damage Pipeline
统一：
BaseDamage
 ↓
AbilityModifier
 ↓
AttackStat
 ↓
WeaponModifier
 ↓
DefenseModifier
 ↓
Resistance
 ↓
Critical
 ↓
Random
 ↓
FinalDamage
每一层都是可测试规则。

---
57. Status Effect
采用：
StatusDefinition
StatusInstance
Duration
StackRule
TickRule
RemoveRule
例如：
Poison
Burn
Bleed
Stun
Buff
Debuff
Combat不应该硬编码几十种状态。

---
58. Combat AI
Combat AI 不属于 Combat Core。
AI负责：
分析
选择行动
生成 Command
Combat负责：
验证
执行
结算
AI类型：
Aggressive
Defensive
Support
Coward
Boss
Scripted
未来可以替换 AI，而不改 Combat。

---
59. Quest
Quest负责：
QuestDefinition
QuestState
Objective
ObjectiveState
Branch
Progress
QuestRule
Quest不直接实现：
奖励
背包
金钱
婚姻
对话
它通过：
Effect
Command
Event
连接其他系统。

---
60. Dialogue
Dialogue：
DialogueDefinition
DialogueNode
DialogueChoice
DialogueCondition
DialogueAction
DialogueVariable
DialogueContext
Dialogue不直接：
修改NPC
修改背包
修改婚姻
修改任务
而是：
Choice
 ↓
Command / Effect

---
61. Story
Story是最高层流程编排。
层级：
Story
 ↓
Arc
 ↓
Chapter
 ↓
Quest
 ↓
Dialogue
 ↓
Event
Story不重新发明 Quest。
它只负责：
剧情流程
分支
阶段
触发
汇合

---
62. World
World负责：
Region
Location
Time
Calendar
Weather
Travel
WorldState
WorldEvent
世界时间变化：
TimeAdvancedEvent
 ↓
Schedule
 ↓
Weather
 ↓
Quest
 ↓
Relationship
 ↓
Economy
 ↓
WorldEvent
各模块独立响应。

---
63. Content系统
核心原则：
内容是数据，不是代码。
内容：
NPC
Item
Quest
Dialogue
Faction
Ability
Recipe
Shop
Map
Story
尽可能：
Schema + Data
而不是：
每个NPC一个脚本
每个任务一个脚本
每个武器一个脚本

---
64. Content Pipeline
标准：
Raw Content
 ↓
Schema Validation
 ↓
ID Validation
 ↓
Reference Validation
 ↓
Condition Validation
 ↓
Dependency Validation
 ↓
Localization Validation
 ↓
Balance Validation
 ↓
Build
 ↓
Index Generation
 ↓
Content Package
 ↓
Runtime

---
64A. Content Review / Publish Gate
Schema PASS 只表示“格式正确”，不表示“内容可发布”。

正式 Content 建议经历：
Generate / Author
↓
Schema Validation
↓
ID Validation
↓
Reference Validation
↓
Condition / Effect Validation
↓
Dependency Validation
↓
Localization Validation
↓
Balance Validation
↓
Narrative / Design Review
↓
Ownership Review
↓
Build
↓
Index Generation
↓
Content Package
↓
Publish Gate
↓
Runtime

以下内容默认需要 Owner / Human Review：
主线剧情
不可逆世界状态变化
经济核心参数
付费/DLC关键内容
大规模数值重平衡
Save 兼容相关 Definition 变化
公共术语与世界观核心事实

AI 批量生成内容必须记录：
generator
model_or_agent
source_task
generated_at
schema_version
content_version
review_status

ContentRegistry 只加载：
满足当前 Release Policy 的 Content Package。


---
65. Content Registry
负责：
加载
缓存
版本
DLC
Mod
依赖
索引
查询
Content Registry 不负责业务规则。

---
66. Content Index
建立：
ByID
ByRegion
ByChapter
ByFaction
ByNPC
ByTag
ByPrerequisite
ByContentPack
避免运行时全表扫描。

---
67. Studio
Studio不是：
JSON编辑器。
Studio是：
Content Authoring System。
包含：
Schema Editor
NPC Editor
Quest Editor
Dialogue Editor
Story Graph
Condition Editor
Effect Editor
Reference Inspector
Dependency Graph
Preview
Validation
Build

---
68. Story Graph
故事编辑器基于：
StoryGraph
StoryNode
Condition
Choice
Command
Event
Variable
Branch
Join
例如：
Start
 ↓
Condition
 ├── True → Dialogue A
 │            ↓
 │         Choice
 │
 └── False → Dialogue B

---
69. Dependency Graph
Studio必须能够回答：
“我修改这个 NPC，会影响什么？”
例如：
NPC_000123
 ├── Dialogue
 ├── Quest
 ├── Faction
 ├── Relationship
 ├── Marriage
 └── Story
这样大型项目才能控制影响范围。

---
70. DLC / Mod
每个扩展包：
ContentPack
包含：
id
version
dependencies
optional_dependencies
content
assets
localization
模块：
ModuleManifest
包含：
module_id
version
dependencies
optional_dependencies
capabilities

---
71. Module Loader
启动：
Read Manifest
 ↓
Validate
 ↓
Resolve Dependencies
 ↓
Topological Sort
 ↓
Initialize
 ↓
Register
 ↓
Enable
不能：
随机初始化

---
72. Autoload原则
Autoload严格控制数量。
禁止：
每个Service一个Autoload
推荐：
ApplicationRoot
统一装配：
Repositories
Application
Domain
Event
Content
Infrastructure
Autoload是基础设施入口，不是业务容器垃圾桶。

---
73. GameManager规则
禁止重新制造：
God Object
如果存在：
GameManager
它只能：
Application Root / Composition
不能变成：
NPC管理
Quest管理
Combat管理
Save管理
Marriage管理
Inventory管理

---
74. Application Service规则
Application Service负责：
Use Case orchestration
Transaction orchestration
权限
流程
模块组合
不负责：
核心业务规则
核心规则属于 Domain。

---
75. Transaction规则
V1.2 采用 0-C 的统一 Execution / Transaction 语义。
涉及多个状态变化：
Precheck
 ↓
Transaction Begin
 ↓
Execute / Mutation Journal
 ↓
Invariant Validation
 ↓
Commit
 ↓
Committed Event
失败：
Rollback

详细规则以 0-C 为唯一执行语义依据。
典型：
Buy
Craft
Trade
Marriage
Quest Reward
Equipment

---
76. Error模型
禁止：
return {}
隐藏业务错误。
使用：
Result<T>
Error
ErrorCode
ErrorContext
例如：
MARRIAGE_NOT_ELIGIBLE
INSUFFICIENT_FUNDS
ITEM_NOT_FOUND
QUEST_NOT_AVAILABLE
INVALID_TARGET
错误必须可测试。

---
77. Logging
日志分级：
TRACE
DEBUG
INFO
WARN
ERROR
FATAL
生产日志不得：
打印巨大对象
打印敏感数据
无限循环输出
关键 Domain 操作必须可追踪。

---
78. Deterministic Random
所有随机性通过：
IRandomProvider
不要：
randf()
randi()
散落在业务代码里。
这样可以：
测试
Replay
Debug
Simulation

---
79. Game Clock
时间通过：
IGameClock
测试可以：
冻结时间
快进时间
回退测试时间
NPC、Quest、Marriage、World Event都不能直接读取系统时间。

---
80. Debug系统
Debug属于独立模块。
可以提供：
Inspect NPC
Inspect Quest
Inspect Relationship
Inspect Combat
Advance Time
Trigger Event
Give Item
Set Relationship
但是 Debug API 必须明确：
Production Safe
Development Only
Test Only

---
81. Test体系
测试不是开发后的补丁。
测试必须与模块一起建设。
每个模块至少：
Unit Test
Contract Test
Integration Test
Regression Test

---
82. Unit Test
测试：
Entity
Value Object
Rule
Condition
Effect
Command Handler
Query
Transaction
禁止依赖：
真实场景
真实数据库
真实时间
真实随机

---
83. Architecture Test
必须自动检查：
Domain → Godot
Domain → JSON
Domain → Database
NPC → Marriage Implementation
Quest → Inventory Implementation
Combat → NPC Implementation
UI → Domain State
任何非法依赖：
FAIL

---
84. Contract Test
所有公共 Contract：
Command
Query
Event
Repository
都必须拥有 Contract Test。
防止一个模块修改接口后悄悄破坏十个模块。

---
85. Integration Test
验证：
模块 A
 ↓
Contract
 ↓
模块 B
例如：
Marriage
 ↓
MarriageFormedEvent
 ↓
Family

---
86. Migration Test
每个 Save Migration：
Old Save Fixture
 ↓
Migration
 ↓
Current Save
必须验证。

---
87. Regression Test
旧 Bug：
BUG-001
BUG-002
BUG-003
必须永久进入 Regression Suite。
Bug 修复以后：
测试不能删除。

---
88. Gate体系
推荐至少：
GATE01 Compile
GATE02 Unit
GATE03 Integration
GATE04 Architecture Dependency
GATE05 Module Boundary
GATE06 Content Schema
GATE07 Reference Integrity
GATE08 Save / Load
GATE09 Migration
GATE10 Event Contract
GATE11 API Contract
GATE12 Forbidden Dependency
GATE13 God Object
GATE14 Direct DB Access
GATE15 Domain Godot Access
GATE16 Studio Smoke
GATE17 Asset Contract
GATE18 Localization
GATE19 Performance
GATE20 Full Regression
最终：
verify_all
作为统一入口。

---
89. Gate通过原则
只有：
PASS
才允许：
Merge
AI的：
“我已经检查过了。”
不等于 PASS。

---
90. 测试失败时AI禁止这样做
禁止：
代码失败
 ↓
修改测试
 ↓
PASS
除非：
正式需求改变
+
测试本身已经过时
+
ADR / Task明确允许
否则测试是裁判。

---
91. UI规则
UI：
Input
 ↓
Command
 ↓
Application
 ↓
Domain
刷新：
Domain Event
 ↓
Query
 ↓
ViewModel
 ↓
UI
UI不拥有业务状态。

---
92. AI与UI
AI不能因为：
“直接调用 Service 最快”
就绕过 Application。
所有用户操作统一：
Player Input
AI Input
Editor Input
Automation Input
最终都可以映射到：
Command

---
93. 性能原则
默认原则：
不优化不存在的瓶颈
但架构必须支持：
Cache
Index
Lazy Loading
Batch Query
Snapshot
Object Pool
Simulation Tick
Domain不得为了性能直接依赖 Godot。

---
94. 大世界/NPC性能
禁止每个 NPC：
每帧执行完整AI
每帧扫描整个世界
每帧查询数据库
采用：
Tick
Schedule
Interest Area
Event
Simulation Level
NPC可以分：
Full Simulation
Reduced Simulation
Background Simulation
Dormant

---
94A. Performance Budget / Simulation Budget
“不提前优化”不等于“不设预算”。

关键系统必须逐步建立可测预算：
Boot Time
Save Time
Load Time
Content Lookup
NPC Tick
World Simulation Tick
Event Dispatch
Quest Evaluation
Relationship Update
Combat Turn Resolution
Combat AI Decision
Memory Usage
Content Package Size

预算规则：
1. 数值由目标平台、Vertical Slice 与真实 Profile 建立，不在宪法里写死万能毫秒数。
2. 每个性能预算必须注明测试环境、场景规模、数据规模和统计口径。
3. 超预算先 Profile，再优化。
4. 不允许为了过性能 Gate 破坏 Domain 边界。
5. 性能优化若改变可观察业务结果，视为业务变更而不是“纯优化”。
6. Simulation Level 切换必须有一致性测试，防止 Full / Reduced / Background 得到互相矛盾的世界状态。
7. 大规模 NPC / World Simulation 应有固定规模基准场景，进入 Performance Regression Suite。


---
95. AI NPC与Gameplay AI区分
NPC日常行为：
Schedule / World Simulation
战斗决策：
Combat AI
剧情行为：
Story / Quest
三者不要混成：
NPCBrain
万能大脑。

---
96. Content与Code边界
如果出现：
“增加100个NPC。”
应该：
新增Data
而不是：
新增100个脚本
如果出现：
“新增一个NPC行为规则。”
应该：
新增Rule
而不是：
修改NPC核心

---
97. 新功能分类
每次需求首先判断：
A. Content
B. Rule
C. Module
D. Infrastructure
E. Presentation
F. Core
优先选择：
A > B > C > D/E > F
也就是说：
能用数据解决，就不要写代码。
能局部规则解决，就不要修改核心。
能新增模块解决，就不要污染已有模块。

---
98. 新增模块标准
例如新增：
Housing
必须做到：
新增 Housing Module
新增 Capability
新增 Contracts
新增 Tests
新增 Content
尽量不修改：
Combat
NPC Core
Inventory Core
Quest Core

---
99. 模块删除标准
删除：
Marriage
必须验证：
Game Boot
NPC
Relationship
Quest
Dialogue
Save
World
仍可运行。

---
100. 模块替换标准
例如：
JSON
 ↓
SQLite
要求：
Domain = 0修改
Gameplay = 0修改
Presentation = 0修改
只改变：
Infrastructure

---
101. 三个架构验收实验
Experiment A：Add
新增：
Housing
目标：
旧模块最小修改

---
Experiment B：Remove
删除：
Marriage
目标：
核心游戏继续启动

---
Experiment C：Replace
替换：
Persistence Adapter
目标：
Domain 0修改
这三个实验是架构健康度的重要指标。

---
102. AI施工报告
每次任务完成必须：
IMPLEMENTATION REPORT

Task:
Module:

Objective:

Changed Files:

Added Files:

Removed Files:

Dependencies Added:

Dependencies Removed:

Public API Changed:

Event Contract Changed:

Save Schema Changed:

Content Schema Changed:

Impact Radius:

Tests Added:

Tests Passed:

Architecture Gates:

Regression:

Known Issues:

Follow-up:

---
103. Change Tracking
所有重大修改必须：
Query
 ↓
Modify
 ↓
Add Change Log
 ↓
Run Gates
 ↓
Report
如果修改共享地基：
Change Notice
+
Architecture Review

---
104. Commit规则
提交必须：
小步
单一目的
可回滚
可定位
禁止：
“顺手重构一下”
一次提交混合：
NPC
Combat
UI
Save
除非这是明确的 Integration Task。

---
105. “顺手优化”禁止制度
AI最容易说：
“我发现这里也可以优化，所以顺便……”
禁止。
任务外修改：
记录
不执行
另建 Task。

---
106. Bug修复制度
Bug：
Reproduce
 ↓
Test
 ↓
Fix
 ↓
Regression
 ↓
Gate
必须先有：
失败测试
再修复。

---
107. 架构Bug与普通Bug分离
普通：
Null Reference
Wrong Calculation
Incorrect UI
架构：
循环依赖
God Object
直接数据库访问
跨模块内部调用
公共Contract污染
架构Bug必须：
ADR / Architecture Task
而不是只打一块补丁。

---
108. God Object检测
自动扫描：
method count
dependency count
module references
state ownership
responsibility count
如果一个类：
同时拥有多个领域状态
则警告。

---
109. God Service检测
如果一个 Service 同时负责：
NPC
Relationship
Marriage
Quest
Inventory
Save
必须拆分。

---
110. Public API规则
模块公开 API 必须尽量小。
内部：
private
公开：
contract
原则：
不让外部知道，就不要公开。

---
111. Query API
Query必须：
无副作用
可重复
可测试
禁止：
GetNPC()
偷偷修改：
NPC
Cache
Quest
Relationship

---
112. Command API
Command必须表达意图：
MarryCommand
AttackCommand
BuyCommand
CraftCommand
AcceptQuestCommand
而不是：
SetNPCStateCommand
这种过度暴露内部实现的命令。

---
113. Condition复用
常见条件应组件化：
HasItem
HasMoney
LevelAtLeast
RelationshipAtLeast
QuestCompleted
FactionReputationAtLeast
TimeBetween
LocationIs
CapabilityEnabled
Quest、Dialogue、Story、Marriage都可以复用。

---
114. Effect复用
例如：
AddItem
RemoveItem
AddMoney
RemoveMoney
ChangeRelationship
SetQuestState
ApplyStatus
UnlockAbility
AdvanceTime
EmitEvent
减少重复逻辑。

---
115. Story不应该拥有一套独立规则语言
Story使用：
Condition
Command
Effect
Event
Variable
不要：
StoryCondition
QuestCondition
DialogueCondition
MarriageCondition
把相同语义复制四遍。

---
116. Database Hook设计
所有需要数据库的系统：
Domain
 ↓
Repository Interface
 ↓
Repository Registry
 ↓
Persistence Adapter
 ↓
Database
模块永远不知道：
SQLite
JSON
Binary
Cloud
Memory
具体实现。

---
117. Database事务
跨实体操作：
Begin
 ↓
Validate
 ↓
Write
 ↓
Commit
失败：
Rollback
数据库事务与 Domain Transaction 可以组合，但两者职责必须区分。

---
118. Runtime缓存
缓存必须：
可失效
可重建
可替换
缓存不能成为唯一数据源。

---
119. Event Log
可以建立：
Event Log
用于：
Debug
Journal
Replay
Analytics
Simulation
但 Event Log 不等于 Save。

---
120. Replay能力
由于：
Command
Clock
Random
Event
被抽象，可以未来支持：
Replay
Debug Replay
Combat Replay
Simulation Replay
这也是架构设计的长期收益。

---
121. Simulation
未来可以：
Fast World Simulation
不加载 UI。
例如：
一天过去
 ↓
NPC Schedule
 ↓
Faction
 ↓
Economy
 ↓
Quest
 ↓
Relationship
全部可以 Headless 运行。

---
122. Headless优先
核心 Domain 必须能够：
Headless
运行。
这样：
测试
服务器
Simulation
批量内容验证
都可以使用。

---
123. Localization
文本必须：
String ID
例如：
dialogue.npc_001.greeting
代码禁止直接硬编码面向玩家的文本。

---
124. Asset
资源通过：
Asset ID
引用。
不要：
Domain保存路径
Domain只知道：
portrait_id
scene_id
icon_id

---
125. Platform
Windows / Android / Web / 未来其他平台属于：
Infrastructure
Presentation Adapter
Domain不改变。

---
126. Input
Input Adapter：
Keyboard
Mouse
Touch
Gamepad
AI
Automation
统一转换：
Command

---
127. Mobile
移动端不应该重新写：
Combat Domain
Quest Domain
NPC Domain
只替换：
Input
Presentation
Platform

---
128. Debug与Production隔离
开发命令：
DebugCommand
不能混入普通玩家 API。
例如：
DebugSetRelationship
DebugGiveItem
DebugAdvanceTime
必须明确：
DEV_ONLY
TEST_ONLY

---
129. Content Pack版本
每个内容包：
id
version
minimum_game_version
dependencies
内容更新不能随意修改旧 ID 语义。

---
130. 数据兼容原则
修改：
字段
枚举
ID
结构
必须考虑：
旧Content
旧Save
DLC
Mod

---
131. AI上下文大小管理
AI不应永久加载：
全部源码
采用：
Project Constitution
+
Relevant Architecture
+
Current Module
+
Relevant Contracts
+
Relevant Tests
+
Legacy Relevant Section
上下文越精准，AI越不容易产生错误假设。

---
132. AI Context Pack
建议自动生成：
_ai_context/
├── constitution.md
├── architecture.md
├── module_map.md
├── current_task.md
├── contracts/
├── tests/
└── legacy/
根据任务动态组装。

---
133. AI Context版本与完整性
每个 Context Pack 至少包含：
context_version
constitution_version
architecture_version
roadmap_version
kernel_version
module_version
contract_version
schema_version
save_schema_version
generated_at
source_revision
context_manifest_hash

Context Pack 必须记录：
包含了哪些文档
每份文档的版本
每份 Contract 的版本
当前 Task ID
当前 Module Owner
当前 Write Permission
当前 Write Lease（如果存在）

以下变化发生后，旧 Context Pack 自动失效：
Constitution Version Change
Architecture Version Change
相关 ADR Accepted
Kernel Version Change
Current Module Contract Change
相关 Public Contract Change
相关 Content Schema Change
相关 Save Schema Change
Task Scope Change
Module Owner Change

失效 Context：
不得继续写代码。
必须重新生成或显式验证后再施工。

目标不是防止“文件旧三天”。
而是防止：
AI 使用已经被正式推翻的架构事实。

---
134. 架构漂移检测
定期比较：
Architecture Document
vs
Actual Dependency Graph
发现：
文档允许 A → B
实际出现 A → C
必须报警。

---
135. Contract Drift检测
比较：
Document Contract
vs
Code Contract
不一致：
FAIL

---
136. Documentation Drift
任何公共 API变化：
Code
+
Contract
+
Docs
+
Tests
必须同步。

---
137. Definition Drift
Schema变化：
Schema
 ↓
Validator
 ↓
Content
 ↓
Tests
不能只改 Schema。

---
138. Save Drift
Save结构变化：
DTO
 ↓
Serializer
 ↓
Migration
 ↓
Fixture
 ↓
Tests
必须一起变化。

---
139. 新增内容验收
新增 NPC：
Schema PASS
ID PASS
Reference PASS
Localization PASS
Portrait PASS
Dialogue PASS
Save PASS
不需要修改 NPC Domain。

---
140. 新增任务验收
新增 Quest：
Definition
Objectives
Conditions
Effects
Rewards
References
Localization
原则：
任务内容不改 Quest Engine。

---
141. 新增武器
应该：
ItemDefinition
EquipmentDefinition
Modifier
而不是：
NewWeapon.gd

---
142. 新增技能
应该：
AbilityDefinition
Target
Condition
Cost
Effect
Modifier
尽可能数据化。

---
143. 新增敌人
应该：
NPCDefinition
CombatantDefinition
AI Profile
Ability Set
Loot Definition
而不是修改 Combat Core。

---
144. 新增玩法
例如：
政治
房屋
继承
赌博
贸易
声望
优先：
New Module
而不是：
修改NPC
修改Quest
修改Combat
修改GameManager

---
145. 删除模块
删除必须先：
Disable Capability
 ↓
Run Dependency Scan
 ↓
Run Integration Tests
 ↓
Remove Implementation
 ↓
Run Save Migration
 ↓
Run Full Regression

---
146. 新模块依赖检查
新模块必须提供：
Module Manifest
声明：
dependencies
optional_dependencies
capabilities
version
不能偷偷依赖。

---
147. 循环依赖
禁止：
NPC → Quest
Quest → NPC
应该：
NPC
 ↓
Contract

Quest
 ↓
Contract
或者通过：
Event
Query
解除循环。

---
148. 模块之间的四种连接
优先级：
1. Query
2. Command
3. Event
4. Port / Interface
尽量避免：
直接实例调用

---
149. 什么情况下允许直接调用
只有：
同一模块内部
或者：
明确声明的 Application orchestration
跨 Domain Module 默认禁止直接调用实现。

---
150. 设计优先级
当AI面对多个实现方案：
方案A：
修改核心

方案B：
修改多个模块

方案C：
新增局部Rule

方案D：
新增数据
优先：
D
 ↓
C
 ↓
B
 ↓
A

---
151. AI不追求“最少文件”
错误：
为了少几个文件，把所有逻辑塞进一个 Service。
正确：
为了清晰职责，允许合理拆分。

---
152. AI不追求“最少代码”
错误：
把所有东西压成万能函数。
正确：
清晰、可测试、可维护优先。

---
153. AI不追求“最聪明实现”
AI应该：
显式
可读
可测试
可追踪
禁止过度魔法：
反射黑魔法
隐式注册
隐式依赖
动态修改公共结构
除非有明确架构理由。

---
154. Magic Number
禁止业务代码：
100
50
0.25
999
应：
Definition
Config
Rule
Balance Data

---
155. Hardcoded Content
禁止：
if npc_id == "NPC_001":
这种业务内容散落代码。
改成：
Content Definition
Condition
Tag
Rule

---
156. 特例处理
如果出现：
NPC_001必须特殊处理
先问：
这是内容差异，还是规则差异？
内容差异：
Data
规则差异：
Rule
真正的新机制：
Module
不要：
if NPC_001

---
157. AI开发阶段控制
每个模块：
Design
 ↓
Contract
 ↓
Skeleton
 ↓
Unit Tests
 ↓
Implementation
 ↓
Integration
 ↓
Content
 ↓
UI
而不是：
UI
 ↓
发现没有Domain
 ↓
现场补Domain
 ↓
现场补Save
 ↓
现场补数据库

---
158. Vertical Slice
在大规模开发之前必须完成：
1 NPC
1 Quest
1 Dialogue
1 Item
1 Combat
1 Relationship
1 Save
形成完整链路：
World
 ↓
NPC
 ↓
Dialogue
 ↓
Quest
 ↓
Combat
 ↓
Reward
 ↓
Relationship
 ↓
Save
 ↓
Load
这条链路跑通后再大规模扩张。

---
159. Horizontal Foundation
Vertical Slice之前：
Kernel
Application
Persistence
Content
Testing
Composition
必须稳定。

---
160. 第一阶段完成标准
必须：
Game Boot
Domain Tests
Save
Load
Content Load
Command
Query
Event
Repository
Basic NPC
Basic World
Basic Combat
全部 PASS。

---
161. 第二阶段
建立：
NPC
World
Relationship
Faction
Item
Inventory
Ability
Quest
Dialogue

---
162. 第三阶段
建立：
Romance
Marriage
Family
Children
Crafting
Economy
Shop
Progression

---
163. 第四阶段
建立：
Combat
Combat AI
Advanced Quest
Story
World Simulation

---
164. 第五阶段
建立：
Studio
Story Editor
Content Builder
Dependency Graph
Preview
Validation

---
165. 第六阶段
建立：
DLC
Mod
Localization Pipeline
Platform
Performance

---
166. 多AI施工顺序
推荐：
AI-ARCH
 ↓
Kernel Contract
 ↓
AI-TEST
 ↓
Architecture Tests
 ↓
AI-DOMAIN
 ↓
Modules
 ↓
AI-CONTENT
 ↓
Content
 ↓
AI-UI
 ↓
Presentation
 ↓
AI-STUDIO
 ↓
Tools

---
167. 不允许多AI同时施工同一模块核心
同一个模块：
Domain
Application
Infrastructure
最好由：
一个 Owner AI
负责。
其他 AI：
Test
Content
UI
可以并行。

---
168. 模块Owner制度
每个模块拥有：
Module Owner
Owner负责：
Contract
Architecture
Integration
其他 AI修改必须通过 Owner。

---
168A. Shared Foundation Write Lease
Shared Foundation 不仅需要“有人负责”，还需要明确写锁。

每次 Foundation 修改必须登记：
lease_id
owner
scope
reason
related_acr
related_adr
allowed_files
start_revision
expires_or_release_condition

同一 scope：
不得存在两个并行 Write Lease。

其他 AI 在 Lease 存在期间：
可以读取
可以写测试建议
可以提出 Proposal
不得修改被锁定 Foundation。

Lease 结束前必须：
提交 Change Log
运行 Required Gates
更新 Freeze Manifest
释放 Lease


---
169. AI交接
交接必须：
Current State
Known Issues
Changed Contracts
Tests
Pending Tasks
Risks
而不是：
“你接着做吧。”

---
170. AI记忆文件
每个模块可以拥有：
AI_CONTEXT.md
内容：
Module Purpose
Current Status
Public Contracts
Known Pitfalls
Recent Changes
Forbidden Patterns
Test Commands

---
171. 旧工程经验迁移
旧项目最值得迁移的不是：
Service代码
而是：
测试
门禁
Bug
数据
需求
工具经验
协同规则
旧工程目前已有的：
编译门禁
单测门禁
工程规范
引用校验
Studio冒烟
结构保护
应升级，而不是丢弃。

---
172. Test Migration
旧测试：
Legacy Test
 ↓
Behavior
 ↓
New Domain Test
测试表达：
旧项目已经证明这个行为重要。
而不是：
新项目必须复制旧实现。

---
173. Legacy Bug Archive
建立：
legacy/known_issues/
每个：
BUG-ID
Description
Root Cause
Old Fix
New Architecture Prevention
Regression Test
这样旧项目踩过的坑不会再次出现。

---
174. 架构经验库
建立：
docs/architecture/lessons/
记录：
问题
原因
解决方案
为什么当时会发生
新架构如何阻止

---
175. “AI不能猜”
当资料不足时：
STOP
不能：
假设
脑补
自行创建规则
必须输出：
UNKNOWN
并列出：
Missing Information

---
176. “合理”不是架构依据
AI不得说：
“这样比较合理，所以我改了。”
必须说明：
依据：
Constitution Rule
Architecture Rule
Module Contract
ADR
Task
没有依据：
Proposal
而不是直接实施。

---
177. 架构决策依据等级
Level 1
Constitution

Level 2
ADR

Level 3
Architecture

Level 4
Module Contract

Level 5
Task

Level 6
AI推断
AI推断永远最低。

---
178. Code Review
每个模块完成：
Function Review
Architecture Review
Test Review
Content Review
至少检查：
职责
依赖
副作用
错误
测试
性能
命名
可删除性

---
179. Review问题清单
Reviewer必须问：
这个类为什么存在？

它负责什么？

它不负责什么？

谁拥有这个状态？

为什么这里需要依赖另一个模块？

能不能使用 Event？

能不能使用 Query？

能不能数据化？

能不能删除？

能不能替换？

能不能测试？

---
180. 最重要的维护原则
未来看到：
if marriage:
不要立即删。
先问：
为什么这里需要知道 Marriage？
如果答案只是：
因为婚姻发生后有一个事实。
那么应该：
MarriageFormedEvent
而不是：
if MarriageService exists

---
181. Architecture Smell
以下都是危险信号：
GodManager
GodService
GlobalState
DirectDatabase
DirectNode
DirectJSON
CircularDependency
MagicID
HardcodedNPC
HardcodedQuest
HugeSwitch
HugeDictionary
RepeatedRules
DuplicateEventBus
DuplicateCondition
DuplicateEffect

---
182. 巨型switch
例如：
match action_type:
    ATTACK:
    MARRY:
    CRAFT:
    BUY:
    QUEST:
    DIALOGUE:
如果不断增长：
应考虑拆分 Handler / Module。

---
183. 巨型Dictionary
禁止：
GameState["npc"]["relationship"]["marriage"]["quest"]["..."]
这种无限嵌套结构。
使用明确：
NPCState
RelationshipState
MarriageState
QuestState

---
184. Global State
禁止所有模块读写：
GlobalGameState
应该拆成：
WorldState
PlayerState
NPCState
QuestState
RelationshipState
并由 Owner 管理。

---
185. 数据库Hook原则
如果以后接：
SQLite
PostgreSQL
Cloud
Remote
Gameplay不变。
只有：
Repository Adapter
变化。

---
186. Cloud Save
未来：
Local Save
Cloud Save
都实现：
ISaveRepository
Domain不感知。

---
187. Analytics
Analytics不应该侵入业务。
使用：
Domain Event
 ↓
Analytics Handler

---
188. Achievement
Achievement监听：
Event
而不是：
Combat → AchievementService
Quest → AchievementService
Marriage → AchievementService

---
189. Journal
Journal监听：
Event
形成：
Event
 ↓
Journal Entry

---
190. Codex
Codex也是：
Content
+
Discovery State
而不是散落在 NPC / Quest 中。

---
191. 关系、婚姻、家庭最终关系
最终结构：
Relationship
      │
      ├── Friendship
      ├── Hostility
      ├── Romance
      │      ↓
      │   Marriage
      │      ↓
      │   Family
      │      ↓
      │   Children
      │
      └── Other Relationship Types
但它们不是一个 Service。
而是：
基础关系模型
+
多个独立能力模块

---
192. 复杂系统的共同模式
以后新增：
Politics
Housing
Inheritance
Guild
Religion
Reputation
Trade
Crime
Law
优先使用：
Definition
State
Command
Query
Condition
Effect
Event
Repository
形成统一语言。

---
193. 系统之间真正的“胶水”
不是：
Service互相调用
而是：
Command
Query
Event
Condition
Effect
这五类东西就是整个项目的“连接器”。

---
194. AI开发时的最优先检查
每次修改前：
Who owns this state?
每次跨模块：
What contract connects us?
每次新增代码：
Can this be data?
每次修改核心：
Can this be localized?
每次出现特殊情况：
Is this content, rule, or new mechanism?
每次准备复制代码：
Is there already a reusable abstraction?

---
195. 最终AI开发检查表
AI提交前必须回答：
[ ] 我知道当前模块Owner

[ ] 我没有修改模块边界

[ ] 我没有新增未经批准的依赖

[ ] 我没有直接访问数据库

[ ] 我没有让Domain依赖Godot

[ ] 我没有让UI直接修改Domain

[ ] 我没有硬编码内容

[ ] 我没有重复创建已有系统

[ ] 我没有偷偷修改测试

[ ] 我增加了必要测试

[ ] Save没有被破坏

[ ] Content引用完整

[ ] Event Contract完整

[ ] Public API完整

[ ] Architecture Gate通过

[ ] Regression通过

[ ] 已生成施工报告

---
196. 最终工程验收标准
一个模块只有同时满足：
Code
+
Contract
+
Test
+
Content
+
Persistence
+
Documentation
+
Architecture
才能视为：
COMPLETE

---
197. 完成不是“能运行”
“能运行”只代表：
Runtime Smoke PASS
真正完成：
Runtime
+
Test
+
Architecture
+
Persistence
+
Content
+
Documentation
全部通过。

---
198. 项目最终成熟形态
目标架构：
                 CONTENT
                    │
                    ▼
              CONTENT REGISTRY
                    │
                    ▼
                 DOMAIN
                    │
          ┌─────────┼─────────┐
          ▼         ▼         ▼
        Actor      World     Social
          │         │         │
          └────┬────┴────┬────┘
               ▼         ▼
            Gameplay   Story
               │         │
               └────┬────┘
                    ▼
               APPLICATION
                    │
                    ▼
             INFRASTRUCTURE
          ┌─────────┼──────────┐
          ▼         ▼          ▼
       Database    Save      Platform
                    │
                    ▼
               PRESENTATION

---
199. 最终目标不是“绝对解耦”
不存在绝对解耦。
真正目标：
高内聚
+
低耦合
+
明确边界
+
稳定契约
+
可替换实现
+
可测试
+
可观察
+
可迁移

---
200. 最终判断标准
以后不要问：
“这个架构是不是完美？”
只问：
新增功能会影响多少模块？

删除模块会影响多少模块？

替换基础设施会影响多少模块？

迁移存档会影响多少模块？

新增1000条内容需要修改多少代码？

换UI需要修改多少Domain？

换AI需要修改多少Combat？

换数据库需要修改多少Gameplay？
这些答案才真正代表架构质量。

---
201. 项目最高级原则
最终把整个工程浓缩成一句话：
让变化发生在它应该发生的地方。
内容变化：
Content
规则变化：
Domain Rule
玩法变化：
Module
存储变化：
Infrastructure
UI变化：
Presentation
平台变化：
Platform Adapter
流程变化：
Application / Story
不要让：
内容变化
变成：
核心代码变化。
不要让：
UI变化
变成：
Domain变化。
不要让：
数据库变化
变成：
Combat变化。
不要让：
新增婚姻
变成：
NPC + Quest + Combat + Save 全部重写。

---
202. AI最高级施工原则
AI开发整个项目时，必须牢记：
我不是来“把功能做出来”的。

我是来：
在既定架构边界内，
用最小影响范围，
实现当前施工单，
并用自动化测试证明没有破坏工程。

---
203. V1.1正式施工口令
以后任何 AI 接到开发任务，第一句话应该是：
我将先确认：
项目宪法
架构
模块Owner
模块契约
任务边界
相关测试
Legacy参考范围

在边界确认前不修改代码。
然后：
PLAN
IMPLEMENT
TEST
VERIFY
REPORT

---
204. 最终AI工程协议
AI永远遵守：
READ BEFORE WRITE

UNDERSTAND BEFORE MODIFY

CONTRACT BEFORE IMPLEMENTATION

TEST BEFORE CLAIMING COMPLETE

GATE BEFORE MERGE

STOP BEFORE ARCHITECTURE VIOLATION

ASK BEFORE CORE CHANGE

DOCUMENT BEFORE DECISION

---
205. 这套体系的最终效果
理想状态下：
新增NPC
Data
新增100个NPC
Data
新增1000个NPC
Data + Content Build
新增Quest
Data
新增武器
Data
新增技能
Data + Effect/Rule
新增婚姻玩法
Marriage Module
新增房屋
Housing Module
删除婚姻
Disable Marriage Capability
换数据库
Infrastructure
换UI
Presentation
换AI
AI Adapter
换平台
Platform Adapter
修改存档
Migration
增加DLC
ContentPack / Module
这就是本工程真正追求的：
“局部变化，局部承担。”
而不是：
“牵一发而动全身。”

---
206. V1.1之后的工程文档与施工顺序
本规范完成以后，不直接进入大量 Gameplay 开发。

V1.1 修正一个重要问题：
“文档编号”不再等于“唯一依赖顺序”。
因为 Application、Persistence、Testing、Composition 属于横向基础能力，
它们会在多个阶段逐步建立，而不是某一天一次性“做完”。

因此采用：
主施工路线
+
横向 Foundation Track

一、主施工路线
01 总体架构施工图

02 Domain Kernel + 核心契约施工图

03 Contract / Schema / Data Contract 施工图
冻结：
Definition Contract
ID Contract
Reference Contract
Schema Version
Content Pack Contract
基础序列化契约

04 Test Infrastructure / Architecture Gate 施工图
建立：
Unit Test 基础
Contract Test 基础
Architecture Linter
Deterministic Test Double
CI / verify_all 骨架

05 Content Registry / Content Pipeline 施工图
实现：
Registry
Loader
Cache
Index
Validation
Package
Version
DLC / Mod Content 基础

06 Actor / Player / NPC

07 World / Time / Schedule

08 Relationship / Faction

09 Item / Inventory / Equipment

10 Economy / Shop / Crafting

11 Ability / Combat / Combat AI

12 Quest / Dialogue / Story

13 Save / Persistence / Migration

14 Presentation / Input / ViewModel

15 Studio / Authoring / Validator / Preview

16 Content Production

17 Simulation / Balance / Performance Hardening

18 Release Hardening / Compatibility / Migration Verification

二、横向 Foundation Track
以下不使用“某一章一次性做完”的理解：

APP-FND Application Foundation
在 02~06 之间建立最小：
Command Handler Contract
Query Handler Contract
Use Case Orchestration Convention
Transaction Orchestration Convention

随后：
每个 Gameplay Module 与自己的 Application Use Case 一起施工。
禁止提前制造一个巨型 GameApplicationService。

PERSIST-FND Persistence Foundation
早期只建立：
Repository Contract
Memory/Fake Adapter
Persistence Port
Serializer Contract

正式：
Save
Database Adapter
Migration
在 13 阶段集中完成并验证。

CMP-FND Composition Foundation
早期建立：
ApplicationRoot
Dependency Injection
Module Registration
但只装配已经批准的模块。
禁止通过 Composition Root 偷偷创造业务依赖。

TEST-FND Testing Foundation
必须早于大规模业务模块。
测试基础设施不是最后补齐的章节。

三、稳定文档 ID
为了避免以后再次发生“03 到底是哪一章”的冲突，
每份关键文档除显示编号外，还必须拥有稳定 Document ID。

推荐：
CONST-PROJECT
ARC-OVERALL
KRN-CORE
DAT-CONTRACT
TST-INFRA
CNT-REGISTRY
APP-FOUNDATION
PERSIST-FOUNDATION
MOD-NPC
MOD-QUEST
MOD-COMBAT
SAVE-ARCH
STUDIO-ARCH
AI-COLLAB

引用规范时优先使用：
Document ID + Version
而不是只写“03”。

四、每张施工图必须下沉到
目录
文件
Class
Interface
Field
Method
Command
Query
Condition
Effect
Event
Repository
Schema
Runtime State
Save DTO
Database Table
Index
Dependency
Lifecycle
Error
Transaction
Test
Extension
Removal
Migration
Owner
Permission
Version
Compatibility
Observability
Performance Budget（适用时）
Rollback

施工图阶段不再只讨论：
“应该怎么设计。”

而是必须能回答：
这个文件为什么存在？
谁拥有它？
谁能写？
谁能调用？
依赖从哪里来？
公共契约是什么？
数据在哪里？
Schema 怎么验证？
存档怎么挂？
数据库怎么替换？
事件怎么追踪？
性能怎么测？
失败怎么回滚？
删除以后怎么保证不炸？
AI 用哪个版本的 Context 才能施工？

---
207. Constitution Version Governance
Project Constitution 自身也必须像代码一样被治理。

每个版本必须声明：
version
status
supersedes
effective_from
approved_by_role
change_summary
related_adr
migration_required
context_rebuild_required

状态：
DRAFT
ACTIVE
DEPRECATED
SUPERSEDED

同一时刻只能有一个 ACTIVE Constitution Major Line 作为默认最高规则。

历史版本：
不得删除。
用于：
审计
迁移
Legacy Task 解释
Bug 调查

---
208. Approval Matrix
默认批准权：

普通模块内部实现
→ Module Owner / Reviewer

模块 Public Contract
→ Module Owner + Contract Review

跨模块 Dependency
→ Architecture Review

Content Schema
→ Content Architecture Owner + Migration Review

Save Schema
→ Save Owner + Architecture Review + Migration Test

Kernel / Shared Foundation
→ Architecture Owner + Core Maintainer + Architecture Gate

Project Constitution
→ Architecture Owner / Human Project Authority

原则：
提出者不能作为唯一批准者。
实现者不能仅凭自己测试通过批准自己的架构变更。

---
209. Change Propagation Rule
任何已批准的上位变化必须向下传播。

Constitution Change
↓
Architecture
↓
Module Map
↓
Affected Contracts
↓
Task Templates
↓
AI Context Pack
↓
Tests / Gates
↓
Implementation

禁止：
只改 Constitution，
但旧 Contract、旧 Context、旧 Gate 继续工作。

Change Propagation 必须可追踪到 Change ID。

---
210. Freeze Manifest
Shared Foundation 每次冻结必须生成：
FOUNDATION_FREEZE_MANIFEST

包含：
constitution_version
architecture_version
kernel_version
public_contract_versions
schema_versions
save_schema_version
module_loader_version
capability_registry_version
composition_version
verified_revision
gate_results
frozen_at

业务 AI 开工前：
应确认所依赖的 Foundation 版本存在于有效 Freeze Manifest。

---
211. Compatibility Policy
所有长期公共结构必须声明兼容性。

兼容等级：
BACKWARD_COMPATIBLE
FORWARD_TOLERANT
BREAKING

涉及：
Command DTO
Event Payload
Repository Contract
Content Schema
Save DTO
Module Manifest
Content Pack Manifest

BREAKING Change 必须：
Version Bump
Migration
Compatibility Test
Affected Consumer Scan
Rollback Plan

“增加一个字段”不能自动假设兼容。
必须考虑：
旧 Content
旧 Save
DLC
Mod
旧客户端/工具
测试 Fixture

---
212. Deprecation Policy
全工程弃用统一流程：
ACTIVE
↓
DEPRECATED
↓
MIGRATION WINDOW
↓
REMOVED

DEPRECATED 必须记录：
replacement
deprecated_since
removal_not_before
migration_guide
affected_consumers

禁止：
同一提交中无迁移地删除广泛使用的 STABLE API。

---
213. AI Permission Evidence
AI 每次提交报告必须附带：
effective_role
permission_level
module_owner
allowed_files
write_lease_id（如适用）

自动扫描实际 Changed Files。
如果：
实际修改范围 > 授权范围
则：
FAIL / REVIEW REQUIRED。

权限证据与代码结果一样属于施工证据。

---
214. Build / Content Provenance
正式 Build 与 Content Package 必须可追溯。

建议记录：
build_id
source_revision
game_version
constitution_version
architecture_version
content_version
schema_version
save_schema_version
enabled_modules
enabled_content_packs
dependency_lock
generated_at

目标：
任何线上问题都能回答：
“这个运行结果究竟是由哪套代码、内容、Schema、模块和规范构建出来的？”

---
215. Observability / Correlation
关键跨模块业务链建议携带稳定关联 ID：
task_id
command_id
transaction_id
event_id
correlation_id
causation_id

例如：
BuyItemCommand
correlation_id = X
↓
Transaction X
↓
MoneyChangedEvent
ItemAddedEvent
PurchaseCompletedEvent

这样 Debug / Replay / Journal / Analytics 能回答：
“这一连串变化最初由什么触发？”

Domain 不因此依赖具体日志系统。
关联 ID 属于稳定业务追踪元数据。

---
216. Performance Regression Governance
性能问题也必须防回归。

每个已建立的关键 Benchmark：
保存基线
输入规模
环境
结果分布
允许波动
版本

性能修复完成后：
Benchmark 不删除。

如果功能正确但性能超过 Release Budget：
状态可以是 FUNCTIONAL PASS，
但不能是 RELEASE PASS。

---
217. Content Quality Governance
AI Content 的目标不是：
“能过 Schema 就大量生成。”

正式内容必须同时考虑：
一致性
世界观
可玩性
重复度
数值
引用完整
本地化
可维护性
可撤回性

批量生成前：
先小样本。
小样本通过 Review：
再扩大批量。

禁止：
一次生成几万条内容后才第一次验证内容体系。

---
218. Architecture Health Report
定期生成：
ARCHITECTURE HEALTH REPORT

至少包含：
Module Fan-out
Module Fan-in
Cross-module Imports
Circular Dependencies
Public API Count
Shared Foundation Change Frequency
Changed Files per Feature
Architecture Violations
Contract Drift
Schema Drift
Save Drift
God Object Warnings
Duplicate Infrastructure
Regression Failure Count
Performance Regression
Context Staleness
Unowned State Count

目标不是追求某个万能数字。
目标是观察：
趋势是否越来越差。

---
219. Emergency Rule
紧急 Bug 不等于可以破坏架构。

如果 Production Emergency 必须临时绕过正常流程：
必须建立：
EMERGENCY CHANGE

包含：
incident_id
reason
temporary_scope
risk
owner
expiry
rollback
follow_up_task

临时架构债务必须有到期条件。
禁止：
“先这样以后再说”
永久存在。

安全性、存档损坏、数据丢失等严重事故：
可以提高处理优先级，
不能取消审计与回滚要求。

---
220. V1.2 完成与生效标准
V1.2 只有满足以下条件才进入 ACTIVE：

□ 修复“十条铁律只有五条”的结构缺陷
□ 模块 Owner 基线可直接读取
□ ACR / ADR 有完整闭环
□ Constitution 自身已版本化
□ AI Permission 可表达
□ Shared Foundation 有 Write Lease
□ AI Failure / Blocked 有标准报告
□ Context Pack 能识别失效
□ Contract / Schema 有兼容等级
□ Content 有 Publish Gate
□ Performance 有 Budget / Regression 机制
□ Foundation 有 Freeze Manifest
□ Build / Content 可追溯
□ 施工路线与 01 / 02 不再自相矛盾
□ 关键文档拥有稳定 Document ID
□ Architecture / Contract / Documentation Drift 可以进入 Gate
□ V1.1 被明确标记为 SUPERSEDED
□ GDScript Engineering Standard 已纳入并可检查
□ Enforcement Matrix 已建立
□ Execution / Transaction / Rollback Contract 已冻结
□ VS-001 Merchant Purchase 已真实运行并通过失败回滚测试
□ verify_all 已具备统一入口
□ Build Graph / Foundation Graph / Architecture Graph 已建立
□ Task Scope Lock / Changed File Enforcement 已可执行

V1.2 一句话总纲：
让变化发生在它应该发生的地方；
让每一次变化都有 Owner、权限、版本、证据、迁移与回滚；
让 AI 可以高速施工，但不能靠猜测、越权和隐式副作用换取速度。

---
221. V1.2 整合版实施索引

本索引不是新的架构层，而是为了让 AI 在施工时快速定位规范。

A. 架构与依赖：0-A、1、2、3、4
B. GDScript 工程：0-B
C. Execution / Transaction：0-C、74、75、76
D. AI 施工：0-D、0-G、8、9、11、16、17、20、21A、169、170、176、203、204
E. Enforcement：0-E、83、84、88、89、90
F. Vertical Slice：0-F、158、159、160、166
G. Content：63、64、64A、65、66、217
H. Save：31、32、86、145-146、211
I. Performance：93、94、94A、216
J. Governance：23A-23D、207-213、219

---
222. V1.2 权威来源与冲突处理补充

当同一主题在多个旧章节重复出现时：
1. V1.2 新增执行语义优先于旧的非细化描述。
2. 0-C 为 Transaction 执行语义唯一权威来源。
3. 0-B 为 GDScript 工程实现唯一权威来源。
4. 0-E 为 Enforcement 执行方式权威来源。
5. 0-F 为 Vertical Slice 施工语义权威来源。
6. V1.1 历史描述若与 V1.2 冲突，视为 SUPERSEDED。

不得因为旧章节存在不同表述而让 AI 自行择优。
发现无法自动解释的冲突：STOP。

---
223. V1.2 模块施工图统一模板

以后任何 01～18 主施工路线中的模块施工图必须至少回答以下问题：

1. Module ID
2. Version
3. Status
4. Owner
5. Permission
6. Purpose
7. Responsibilities
8. Non-Responsibilities
9. Inputs
10. Outputs
11. State Owner
12. Entity
13. Runtime State
14. Definition
15. Save DTO
16. Command
17. Query
18. Condition
19. Effect
20. Rule
21. Event
22. Repository / Port
23. Content Schema
24. Error
25. Transaction Boundary
26. Rollback Strategy
27. Lifecycle
28. Dependency
29. Forbidden Dependency
30. GDScript Types
31. Godot Adapter Boundary
32. Performance Budget
33. Observability
34. Tests
35. Gates
36. Migration
37. Extension
38. Removal
39. Known Limitations
40. Context Pack Version
41. Required Vertical Slice

如果模块施工图缺失“失败怎么处理”和“怎么验证”，则不允许进入 IMPLEMENTED。

---
224. V1.2 Actor 施工补充规则

Actor 的运行时定位：

Content Definition
    ↓
Actor Instance
    ↓
Actor Runtime
    ↓
Components / Capability
    ↓
Controller
    ↓
Intent
    ↓
Command
    ↓
Application / Execution
    ↓
Domain

Actor 不等于：
- Godot Node
- Domain Entity 的全部替代物
- Content Definition
- Save DTO
- God Object

Actor 可以承载 Runtime Identity、Lifecycle、Components、Controller 与受控的运行时能力；业务 Owner 仍归具体 Gameplay Module。

---
225. V1.2 Content 施工补充规则

Content Pipeline：

Raw Content
 ↓
Schema
 ↓
ID
 ↓
Reference
 ↓
Condition / Effect
 ↓
Dependency
 ↓
Localization
 ↓
Balance
 ↓
Design Review
 ↓
Publish Gate
 ↓
Content Package
 ↓
Runtime Registry

Content 能描述：
“这个世界里有什么”。

Content 不直接决定：
“这个业务状态如何执行”。

执行仍通过 Contract / Command / Domain Rule 完成。

---
226. V1.2 Save 施工补充规则

Save 必须记录足以复原：
- game_version
- constitution_version
- architecture_version
- content_version
- schema_version
- save_schema_version
- enabled_modules
- enabled_content_packs
- dependency_lock（适用时）

核心 Save Round Trip：

Create State
 ↓
Mutate
 ↓
Save DTO
 ↓
Persist
 ↓
Destroy Runtime
 ↓
Load
 ↓
Rebuild
 ↓
Compare Invariants

要求：
保存前后关键业务不变量一致。

---
227. V1.2 事务事故调查模板

发生“扣钱不发货”或类似事故时，禁止只检查最后一个函数。

必须沿链调查：

Task
 ↓
Command
 ↓
Handler
 ↓
Transaction
 ↓
Mutation Journal
 ↓
Domain Rule
 ↓
Commit
 ↓
Event
 ↓
Persistence
 ↓
Presentation

必须提供：
transaction_id
command_id
correlation_id
causation_id
state_before
mutation_sequence
failure_point
rollback_result
committed_events
persistence_result

这样可以回答：
“钱在哪一步减少？货在哪一步没有增加？事务在哪一步失去原子性？”

---
228. V1.2 统一 Gate 编号建议

在现有 GATE01-GATE20 基础上，允许增加：

GATE21 GDScript Type Policy
GATE22 Forbidden API
GATE23 Changed File Scope
GATE24 Contract Drift
GATE25 State Ownership
GATE26 Transaction Atomicity
GATE27 Rollback Recovery
GATE28 Command Ordering
GATE29 Vertical Slice
GATE30 Context Freshness
GATE31 Permission Evidence
GATE32 Foundation Freeze Consistency

新增 Gate 必须进入 CONTRACTS / PROJECT STATUS / verify_all。

---
229. V1.2 第一阶段真正开工顺序

不是直接进入大规模 Gameplay。

阶段 A：工程地基
1. Constitution v1.2
2. Architecture Graph
3. Foundation Graph
4. Build Graph
5. Contract Registry
6. Dependency Rules
7. Enforcement Matrix
8. Task Scope Lock
9. verify_all 骨架

阶段 B：Execution 地基
10. Command Contract
11. Result / Error Contract
12. Transaction Contract
13. Mutation Journal
14. Rollback Test
15. Event Commit Boundary
16. Command Scheduler

阶段 C：VS-001
17. Merchant
18. Player
19. Item
20. Currency
21. Inventory
22. Buy Command
23. Transaction
24. Save / Load
25. VS-001 Success / Failure / Rollback

阶段 D：再进入 01～06 主施工路线
按 Build Graph 分配 AI，而非仅按文档编号分配 AI。

---
230. V1.2 第一阶段禁止项

在 VS-001 未通过前，默认禁止：
- 全量 NPC 社会模拟。
- 全量 AI Brain。
- LLM NPC。
- 复杂 ECS 重构。
- 全面多线程化。
- 10000 NPC 性能极限优化。
- 大规模 Studio 自动生成。
- 完整 DLC / Mod 热插拔。
- 大型 Combat AI。
- 复杂 Marriage / Family 全链路。

可以设计 Contract / Stub，但不能把这些功能冒充 ACTIVE。

---
231. V1.2 AI 最终施工口令

AI 接到任务后必须遵循：

READ BEFORE WRITE

UNDERSTAND BEFORE MODIFY

CONTRACT BEFORE IMPLEMENTATION

SCOPE BEFORE EDIT

OWNER BEFORE MUTATION

TRANSACTION BEFORE MULTI-STATE CHANGE

TEST BEFORE CLAIMING COMPLETE

GATE BEFORE MERGE

STOP BEFORE ARCHITECTURE VIOLATION

ASK / ACR BEFORE CORE CHANGE

DOCUMENT BEFORE DECISION

---
232. V1.2 一句话总纲

让变化发生在它应该发生的地方；
让状态只由一个 Owner 写入；
让跨模块交互经过明确 Contract；
让每一次状态变化拥有清晰的执行、提交、失败与回滚语义；
让每一次 AI 修改都拥有范围、权限、版本和证据；
让每一次架构变化都能够传播到 Contract、Context、Test、Gate 与代码；
让项目尽早通过真实 Vertical Slice；
让 AI 可以高速施工，但不能靠猜测、越权、隐式副作用和临时架构换取速度。

