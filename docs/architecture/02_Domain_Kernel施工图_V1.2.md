# 02 Domain Kernel 施工图 V1.2

- **Document ID**：ARCH-02
- **Version**：1.2
- **Status**：**FROZEN**（2026-09-06 架构 Owner 批准；可依此实施）
- **Authority**：01 总体架构施工图 V1.2（`docs/architecture/01_总体架构施工图_V1.2.md`）
- **Supersedes**：02 Domain Kernel V1.1（旧写法作废，**不得沿用**）
- **Applies To**：Kernel / Execution / Domain / Application / Infrastructure / Presentation / Tests
- **对应施工阶段**：01 §128 **Phase B：Execution 地基**
- **Change Policy**：Kernel 属 **Shared Foundation**（01 §98）。任何修改必须 `ACR → 影响分析 → ADR → 版本升版 → 迁移/兼容 → 测试 → Gate`，且**同一时间只能有一个 Write Lease**。

---

## 0. 本文档的定位与硬边界

**01 定义整座建筑如何站立；02 只做一件事：把最底下那块地基（Kernel）钉死。**

Kernel 是 Level 0，**不可删除、不可反向依赖任何东西**。

```
Kernel 依赖方向：
        Kernel  ──→  （无。Kernel 不依赖任何层，包括 Godot Runtime API）
        其他层  ──→  Kernel
```

**Kernel 只保存**（01 §9）：稳定身份、Value Object、Result、Error、Command、Query、Event、Condition Contract、Effect Contract、Rule Contract、Transaction Contract、Clock Contract、Random Contract、Repository Contract。

**Kernel 不保存**：Godot Node、SceneTree、UI、JSON、SQLite、Save 实现、Content 实现、Gameplay 编排。

> ⚠️ **实现约束**：以下代码块为**契约形态定义**，用于钉死签名与类型。实现时以 **GATE1（Godot 编译零错）** 为最终裁决；若 GDScript 4.7 语法与本稿冲突，**以编译器为准并回改本文档**（走 ACR，不得偷偷改代码迁就文档）。

---

## 1. Kernel 目录结构（01 §127）

```
kernel/
├── identity/
│   └── entity_id.gd              # EntityId（稳定身份）
├── result/
│   ├── operation_result.gd       # OperationResult（基类）
│   ├── command_result.gd         # CommandResult
│   ├── query_result.gd           # QueryResult
│   ├── validation_result.gd      # ValidationResult
│   ├── save_result.gd            # SaveResult
│   └── load_result.gd            # LoadResult
├── error/
│   ├── error_code.gd             # ErrorCode（常量表，机器可识别）
│   └── operation_error.gd        # OperationError
├── command/
│   └── command.gd                # Command（意图基类）
├── query/
│   └── query.gd                  # Query（只读基类）
├── event/
│   └── domain_event.gd           # DomainEvent（已发生事实基类）
├── condition/
│   ├── condition.gd              # Condition（@abstract）
│   └── game_facts.gd             # GameFacts（只读事实门面契约）
├── effect/
│   └── effect.gd                 # Effect（@abstract）
├── rule/
│   └── rule.gd                   # Rule（@abstract）
├── transaction/
│   ├── transaction_context.gd    # TransactionContext + State 枚举
│   ├── mutation_record.gd        # MutationRecord
│   └── undo_strategy.gd          # UndoStrategy（@abstract）
├── repository/
│   └── repository.gd             # Repository（契约标记基类）
├── clock/
│   └── game_clock.gd             # GameClock（@abstract）
└── random/
    └── random_provider.gd        # RandomProvider（@abstract）
```

**目录纪律**：`kernel/` 下**禁止**出现任何 gameplay 具体类型（NpcState / QuestState / ItemStack 等）。具体仓储（NPCRepository 等）属于**各模块自己的 `contracts/`**，不属于 Kernel。

---

## 2. Identity：EntityId

```gdscript
class_name EntityId extends RefCounted
## 稳定身份。ID 永不复用、不表达业务状态、不依赖显示名称、不随语言变化。
## 删除 = retired，绝不复用旧号（对应宪法第 26 节）。

const SEPARATOR := "_"

var _domain: StringName   # NPC / QUEST / ITEM / ABILITY / DIALOGUE / FACTION / LOCATION / EVENT / STORY
var _serial: String       # 000001

func _init(domain: StringName, serial: String) -> void:
    _domain = domain
    _serial = serial

static func of(domain: StringName, serial: String) -> EntityId:
    return EntityId.new(domain, serial)

## 解析 "NPC_000001"。失败返回 null（调用方必须处理 null，不得假设永远成功）
static func parse(raw: String) -> EntityId:
    if raw == "":
        return null
    var parts := raw.split(SEPARATOR, false)
    if parts.size() != 2:
        return null
    return EntityId.new(StringName(parts[0]), parts[1])

func get_domain() -> StringName:
    return _domain

func get_serial() -> String:
    return _serial

func equals(other: EntityId) -> bool:
    if other == null:
        return false
    return _domain == other.get_domain() and _serial == other.get_serial()

func _to_string() -> String:
    return _domain + SEPARATOR + _serial
```

**钉死要点**
- `EntityId` 是 **Value Object**：创建后不可变，无公共 setter。
- 业务判断**禁止**用裸字符串拼 ID；必须走 `EntityId.of/parse`。
- 现有工程的字符串 ID（如 `regions/_map_index.json` 里的区域 ID）迁移时统一走 `parse()` 收敛。

---

## 3. Error：ErrorCode + OperationError

### 3.1 ErrorCode（机器可识别常量表）

```gdscript
class_name ErrorCode extends RefCounted
## 机器可识别错误码。
## 铁律（01 §83）：禁止依赖中文错误字符串作为业务判断依据。
## 业务分支只能比较 ErrorCode 常量，永远不得比较 message。

const NONE: StringName                        = &"ERR_NONE"
const ITEM_NOT_FOUND: StringName              = &"ERR_ITEM_NOT_FOUND"
const INSUFFICIENT_FUNDS: StringName          = &"ERR_INSUFFICIENT_FUNDS"
const INSUFFICIENT_CAPACITY: StringName       = &"ERR_INSUFFICIENT_CAPACITY"
const INVALID_TARGET: StringName              = &"ERR_INVALID_TARGET"
const QUEST_NOT_AVAILABLE: StringName         = &"ERR_QUEST_NOT_AVAILABLE"
const REQUIREMENT_NOT_MET: StringName         = &"ERR_REQUIREMENT_NOT_MET"
const INVALID_STATE: StringName               = &"ERR_INVALID_STATE"
const MODULE_DEPENDENCY: StringName           = &"ERR_MODULE_DEPENDENCY"
const PRECHECK_FAILED: StringName             = &"ERR_PRECHECK_FAILED"
const INVARIANT_VIOLATION: StringName         = &"ERR_INVARIANT_VIOLATION"
const TRANSACTION_ROLLBACK_FAILED: StringName = &"ERR_TRANSACTION_ROLLBACK_FAILED"
const RECOVERY_REQUIRED: StringName           = &"ERR_TRANSACTION_RECOVERY_REQUIRED"
const CONTENT_REFERENCE_MISSING: StringName   = &"ERR_CONTENT_REFERENCE_MISSING"
const REPOSITORY_UNAVAILABLE: StringName      = &"ERR_REPOSITORY_UNAVAILABLE"

## 新增错误码必须：① 登记进 Contract Registry ② 升 CONTRACT 版本 ③ 补 Contract Test
```

### 3.2 OperationError

```gdscript
class_name OperationError extends RefCounted
## 错误对象。至少包含 error_code + context；适用时带 causation / correlation / transaction_id。

var _code: StringName
var _message: String                 # 仅供日志与玩家展示，禁止用于业务判断
var _context: Dictionary             # 【Dynamic Data Boundary K-DB-01】
var _correlation_id: StringName
var _causation_id: StringName
var _transaction_id: StringName

func _init(
    code: StringName,
    message: String = "",
    context: Dictionary = {},
    correlation_id: StringName = &"",
    causation_id: StringName = &"",
    transaction_id: StringName = &""
) -> void:
    _code = code
    _message = message
    _context = context
    _correlation_id = correlation_id
    _causation_id = causation_id
    _transaction_id = transaction_id

func get_code() -> StringName:
    return _code

func get_message() -> String:
    return _message

func get_context() -> Dictionary:
    return _context

func get_correlation_id() -> StringName:
    return _correlation_id

func get_causation_id() -> StringName:
    return _causation_id

func get_transaction_id() -> StringName:
    return _transaction_id

func has_code(code: StringName) -> bool:
    return _code == code
```

---

## 4. Result 家族（无泛型，按用例建具体类）

> **依据 01 §10 / 宪法 0-B.6**：不以泛型为核心架构前提。
> 因此**不建 `Result<T>`**，而是按用例建具体类：`OperationResult` / `CommandResult` / `QueryResult` / `ValidationResult` / `SaveResult` / `LoadResult`。

### 4.1 OperationResult（基类）

```gdscript
class_name OperationResult extends RefCounted
## 所有 Kernel 结果类型的基类。
## 铁律（宪法 0-B.16）：禁止返回 true / false / null / Dictionary / String / Error 混合。

var _ok: bool
var _error: OperationError

func _init(ok: bool, error: OperationError) -> void:
    _ok = ok
    _error = error

static func ok() -> OperationResult:
    return OperationResult.new(true, null)

static func fail(code: StringName, message: String = "", context: Dictionary = {}) -> OperationResult:
    return OperationResult.new(false, OperationError.new(code, message, context))

func is_ok() -> bool:
    return _ok

func is_failed() -> bool:
    return not _ok

func get_error() -> OperationError:
    return _error

func has_error_code(code: StringName) -> bool:
    return (not _ok) and _error != null and _error.has_code(code)
```

### 4.2 CommandResult

```gdscript
class_name CommandResult extends OperationResult
## Command 执行结果。
## 铁律（01 §19）：只有 Committed Event 才能出现在这里。
## 未 Commit 的事务，committed_events 必须为空数组。

var _transaction_id: StringName
var _committed_events: Array[DomainEvent] = []

func _init(ok: bool, error: OperationError, transaction_id: StringName, committed_events: Array[DomainEvent]) -> void:
    super(ok, error)
    _transaction_id = transaction_id
    _committed_events = committed_events

## 成功提交
static func committed(transaction_id: StringName, events: Array[DomainEvent]) -> CommandResult:
    return CommandResult.new(true, null, transaction_id, events)

## Precheck / Invariant 失败：未产生任何状态变化，events 必须为空
static func rejected(code: StringName, transaction_id: StringName, context: Dictionary = {}) -> CommandResult:
    return CommandResult.new(false, OperationError.new(code, "", context, &"", &"", transaction_id), transaction_id, [])

## Rollback 自身失败 → RECOVERY_REQUIRED（01 §18）。禁止 catch 后 print 继续游戏。
static func recovery_required(transaction_id: StringName, context: Dictionary) -> CommandResult:
    return CommandResult.new(
        false,
        OperationError.new(ErrorCode.RECOVERY_REQUIRED, "rollback failed, manual recovery required", context, &"", &"", transaction_id),
        transaction_id,
        []
    )

func get_transaction_id() -> StringName:
    return _transaction_id

func get_committed_events() -> Array[DomainEvent]:
    return _committed_events

func is_recovery_required() -> bool:
    return has_error_code(ErrorCode.RECOVERY_REQUIRED)
```

### 4.3 QueryResult（强类型载荷，非 Variant）

```gdscript
class_name QueryResult extends OperationResult
## Query 结果。
## 铁律：payload 必须是显式强类型的只读 Snapshot（RefCounted）。
## 禁止 Variant / Dictionary 作为载荷（宪法 0-B.2）。

var _payload: RefCounted   # 具体类型由 Query 契约声明，调用方按契约 downcast

func _init(ok: bool, error: OperationError, payload: RefCounted) -> void:
    super(ok, error)
    _payload = payload

static func success(payload: RefCounted) -> QueryResult:
    return QueryResult.new(true, null, payload)

static func not_found(code: StringName = ErrorCode.ITEM_NOT_FOUND) -> QueryResult:
    return QueryResult.new(false, OperationError.new(code), null)

func get_payload() -> RefCounted:
    return _payload

## 按契约取具体快照类型；类型不符返回 null（调用方必须处理）
func get_payload_as(expected_type: Variant) -> RefCounted:
    if is_instance_valid(_payload) and is_instance_of(_payload, expected_type):
        return _payload
    return null
```

> **无泛型的替代约定**：每个 Query 声明自己返回的具体 `XxxSnapshot` 类型，并写入该模块的 `contracts/`。`QueryResult` 只做传输壳。这样既保持强类型，又不引入泛型体系。

### 4.4 ValidationResult / SaveResult / LoadResult

```gdscript
class_name ValidationResult extends OperationResult
## 校验结果。violations 为强类型数组。
var _violations: Array[ValidationViolation] = []
func get_violations() -> Array[ValidationViolation]:
    return _violations
func is_valid() -> bool:
    return _ok and _violations.is_empty()


class_name SaveResult extends OperationResult
## 存档结果（01 §69/70）。
var _save_version: StringName
var _persisted_path: String
func get_save_version() -> StringName:
    return _save_version


class_name LoadResult extends OperationResult
## 读档结果。payload 为强类型 SaveDTO。
var _dto: RefCounted
var _migrated_from: StringName   # 若发生过迁移，记录来源版本；未迁移则为空
func get_dto() -> RefCounted:
    return _dto
func was_migrated() -> bool:
    return _migrated_from != &""


class_name ValidationViolation extends RefCounted
## 强类型校验违约项。禁止用 Dictionary 表达。
var _code: StringName
var _field: StringName
var _detail: String
func get_code() -> StringName:
    return _code
```

---

## 5. Command / Query / Event

### 5.1 Command（意图）

```gdscript
class_name Command extends RefCounted
## 意图（01 §21）。可记录 / 可测试 / 可排序 / 可重放。
## Command 不修改 UI，不直接修改 Domain State。

var _command_id: StringName
var _sequence: int                 # 排序主键（01 §65）
var _source: StringName            # player / ai / story / debug / replay / editor
var _actor_id: EntityId
var _game_tick: int
var _correlation_id: StringName
var _causation_id: StringName

func _init(
    command_id: StringName,
    sequence: int,
    source: StringName,
    actor_id: EntityId,
    game_tick: int,
    correlation_id: StringName = &"",
    causation_id: StringName = &""
) -> void:
    _command_id = command_id
    _sequence = sequence
    _source = source
    _actor_id = actor_id
    _game_tick = game_tick
    _correlation_id = correlation_id
    _causation_id = causation_id

func get_command_id() -> StringName:        return _command_id
func get_sequence() -> int:                 return _sequence
func get_source() -> StringName:            return _source
func get_actor_id() -> EntityId:            return _actor_id
func get_game_tick() -> int:                return _game_tick
func get_correlation_id() -> StringName:    return _correlation_id
func get_causation_id() -> StringName:      return _causation_id

## 子类覆写，返回具体命令类型名（用于 Contract Registry 与 replay）
func get_type() -> StringName:
    return &"Command"
```

**钉死要点**
- 具体命令命名：`BuyItemCommand` / `ProposeMarriageCommand` / `AttackCommand`（意图式）。
- **禁止** `SetNPCStateCommand` 这类暴露内部实现的命令（宪法第 112 节）。
- 排序只依赖 `sequence`，**禁止**依赖 Dictionary 遍历顺序 / Node 树顺序 / 线程调度（01 §65）。

### 5.2 Query（只读）

```gdscript
class_name Query extends RefCounted
## 只读请求（01 §22）。
## 铁律：Query 只读、不改变 Domain State、不启动业务 Mutation（宪法第 111 节）。

var _query_id: StringName
var _actor_id: EntityId
var _game_tick: int
var _correlation_id: StringName

func get_query_id() -> StringName:      return _query_id
func get_actor_id() -> EntityId:        return _actor_id
func get_game_tick() -> int:            return _game_tick
func get_correlation_id() -> StringName: return _correlation_id

func get_type() -> StringName:
    return &"Query"
```

### 5.3 DomainEvent（已发生事实）

```gdscript
class_name DomainEvent extends RefCounted
## 已发生的事实（01 §23）。
## 命名铁律：过去时。ItemPurchasedEvent / MarriageFormedEvent / QuestCompletedEvent。
## 禁止：StartMarriageEvent / DoQuestEvent / ChangeNPCEvent（这些是 Command 语义）。

enum Phase { PENDING, COMMITTED }

var _event_id: StringName
var _event_type: StringName
var _phase: Phase
var _occurred_tick: int
var _causation_id: StringName      # 由哪个 Command 触发
var _correlation_id: StringName
var _transaction_id: StringName

func get_event_id() -> StringName:       return _event_id
func get_event_type() -> StringName:     return _event_type
func get_occurred_tick() -> int:         return _occurred_tick
func get_causation_id() -> StringName:   return _causation_id
func get_correlation_id() -> StringName: return _correlation_id
func get_transaction_id() -> StringName: return _transaction_id

## 铁律（01 §19）：只有 COMMITTED 才能驱动 Presentation / Persistence / Projection
func is_committed() -> bool:
    return _phase == Phase.COMMITTED

func get_type() -> StringName:
    return _event_type
```

**钉死要点**
- 跨业务事实一律用 **Typed Domain Event**；**禁止** `signal something_happened(data: Dictionary)`（宪法 0-B.12 / 01 §86）。
- Presentation 内部的 UI / 动画 / 音效通知**可以**用 Godot Signal，但**不得**承载跨业务事实。
- Event 不负责主动执行其他业务（宪法第 34 节）：`MarriageFormedEvent` 不得内部调用 FamilyService。

---

## 6. Condition / Effect / Rule 契约

```gdscript
@abstract
class_name Condition extends RefCounted
## 「能不能做」（01 §24 / 宪法 RULE 005）。
## 铁律：evaluate() 只读，不得修改任何状态（宪法 0-B.15）。
@abstract func evaluate(facts: GameFacts) -> bool


@abstract
class_name Effect extends RefCounted
## 「状态发生什么变化」（01 §24）。
## 铁律：Effect 在事务内执行，必须可登记进 Mutation Journal（可回滚）。
@abstract func apply(ctx: MutationContext) -> OperationResult


@abstract
class_name Rule extends RefCounted
## 「一组业务判断为什么成立」（01 §24 / 宪法 RULE 005）。
## Rule 不负责 UI / Audio / Scene / Save / File / Godot Runtime。
## 返回值：满足条件返回 OperationResult.ok()，否则 fail(具体 ErrorCode)
@abstract func evaluate(facts: GameFacts) -> OperationResult


@abstract
class_name GameFacts extends RefCounted
## 只读事实门面，供 Condition / Rule 求值。
## 实现由各 Module 或 Application 提供；Kernel 只定义契约。
## 铁律：GameFacts 只读，不得反向修改 Domain State。
## 禁止把 GameFacts 做成万能 Dictionary —— 取值方法必须强类型。
@abstract func get_int(key: StringName) -> int
@abstract func get_bool(key: StringName) -> bool
@abstract func get_entity_id(key: StringName) -> EntityId
```

> **迁移提示**：现有 `core/condition.gd`（ConditionService + GameFacts 适配器）与本节契约**语义同源**。迁移时保留其「统一条件 DSL + 适配器」思想，但把求值入口收敛到 `Condition.evaluate(facts) -> bool`，并把 `GameFacts` 升级为本节的 `@abstract` 契约。

---

## 7. Transaction 契约（Kernel 侧）

> **分界铁律（01 §16）**：
> **Transaction Contract（本节的 `TransactionContext` / `MutationRecord` / `UndoStrategy`）属于 Kernel**，只定义**生命周期语义与数据结构**。
> **`Begin / Prepare / Commit / Rollback / Recovery` 的运行时行为属于 Execution 的 `TransactionRuntime`**（03 施工图展开）。
> **禁止**把所有职责塞进一个 `TransactionManager` 造成新的 God Object。

### 7.1 TransactionContext

```gdscript
class_name TransactionContext extends RefCounted
## 事务契约（Kernel）。只定义状态与标识，不实现执行。

enum State {
    PENDING,            # 已创建，未开始
    RUNNING,            # 执行中，Mutation 正在登记
    COMMITTED,          # 已提交
    ROLLED_BACK,        # 已回滚
    RECOVERY_REQUIRED,  # 回滚自身失败 → FATAL，需人工/自动恢复（01 §18）
}

var _transaction_id: StringName
var _state: State
var _started_tick: int
var _correlation_id: StringName
var _causation_id: StringName

func get_transaction_id() -> StringName:   return _transaction_id
func get_state() -> State:                 return _state
func get_started_tick() -> int:            return _started_tick
func get_correlation_id() -> StringName:   return _correlation_id
func get_causation_id() -> StringName:     return _causation_id

func is_committed() -> bool:
    return _state == State.COMMITTED

func is_recovery_required() -> bool:
    return _state == State.RECOVERY_REQUIRED
```

### 7.2 MutationRecord

```gdscript
class_name MutationRecord extends RefCounted
## 单个可逆变更的登记（01 §17）。
## 铁律：Rollback 必须按 sequence 逆序执行；
##      禁止「扣100 → 失败 → 再加100」这种猜测式补偿。
##      正确做法：由 Owner 提供 UndoStrategy，持有 before 值并知道如何恢复。

var _sequence: int                 # Journal 内序号，回滚按此逆序
var _transaction_id: StringName
var _target_id: StringName         # 被变更对象
var _owner_module: StringName      # 状态 Owner 模块
var _state_key: StringName         # 被变更的状态键
var _undo: UndoStrategy            # 持有 before，提供 restore()

func get_sequence() -> int:              return _sequence
func get_transaction_id() -> StringName: return _transaction_id
func get_target_id() -> StringName:      return _target_id
func get_owner_module() -> StringName:   return _owner_module
func get_state_key() -> StringName:      return _state_key
func get_undo() -> UndoStrategy:         return _undo
```

### 7.3 UndoStrategy

```gdscript
@abstract
class_name UndoStrategy extends RefCounted
## 回滚策略。由 State Owner 提供，持有 before 值。
## restore() 返回 true = 恢复成功；返回 false = undo 失败 → RECOVERY_REQUIRED。
## 铁律（01 §18）：undo 失败不得被 catch + print 掩盖。
@abstract func restore() -> bool
```

**具体策略示例（由各模块提供，不属于 Kernel）**

```gdscript
## 例：Economy 模块提供 —— 恢复钱包金币到 before
## class_name RestoreWalletGoldStrategy extends UndoStrategy
##
## var _wallet: Wallet
## var _before: int
##
## func _init(wallet: Wallet, before: int) -> void:
##     _wallet = wallet
##     _before = before
##
## func restore() -> bool:
##     _wallet.set_gold(_before)      # 受控 Mutation API（宪法 0-B.7）
##     return true
```

**钉死要点**
- **禁止用反射 / `Object.call()` 字符串方法名**做通用恢复（宪法第 153 节：禁止过度魔法）。每个状态键由 Owner 提供具体 Strategy 类。
- before/after 的具体值封装在 Strategy 内，Kernel 不感知业务类型 —— 这样 Kernel 保持纯净，同时满足「按 before 恢复」的要求。

---

## 8. Repository Contract

```gdscript
@abstract
class_name Repository extends RefCounted
## 仓储契约基类（01 §28）。
## Kernel 只定义「仓储是什么」；具体仓储按实体建，不建 IRepository<T>（01 §10）。
## 实现位于 infrastructure/repositories/。Domain 只依赖契约。

@abstract func get_repository_id() -> StringName
```

**具体仓储的位置与形态（不属于 Kernel，属各模块 `contracts/`）**

```gdscript
## 例：domain/npc/contracts/npc_repository.gd
## @abstract
## class_name NpcRepository extends Repository
##
## @abstract func find_by_id(id: EntityId) -> NpcState
## @abstract func save(state: NpcState) -> OperationResult
## @abstract func remove(id: EntityId) -> OperationResult
```

**钉死要点**
- **禁止 `Domain → JSON` / `Domain → SQLite`**（01 §28）。存储实现替换时，**Domain 必须 0 修改**（宪法第 100 节验收）。
- 当前工程 `services/` + `core/` 中有 **7 个文件 / 26 处 `FileAccess`、5 个文件 / 6 处 `JSON.`** —— 这些是 Phase 5 必须清零的违规项（详见 ACR-0001）。

---

## 9. Clock Contract

```gdscript
@abstract
class_name GameClock extends RefCounted
## 游戏时间契约（01 §29）。
## 铁律：游戏逻辑禁止直接读系统时间（Time.get_unix_time_from_system 等）。
## 实现：RealClock / FakeClock / ReplayClock，位于 infrastructure/clock/。

## 当前游戏 tick（唯一权威时间）
@abstract func now_tick() -> int

## 游戏内时间戳（非系统时间）
@abstract func now_timestamp() -> int

## 推进时间。RealClock 实现应拒绝调用或空实现；Fake/Replay 实现有效
@abstract func advance(delta_tick: int) -> void

## 是否允许推进（RealClock = false）
@abstract func can_advance() -> bool
```

**迁移映射**：现有 `autoload/weather_time_service.gd` 承担天气/时间推进。迁移时其**时间职责**收敛为 `GameClock` 实现，天气职责留在 World 模块。

---

## 10. Random Contract

```gdscript
@abstract
class_name RandomProvider extends RefCounted
## 确定性随机契约（01 §30）。
## 铁律：Domain / Kernel 禁止 randf() / randi() / RandomNumberGenerator.new()。
## 实现：SeededRandomProvider，位于 infrastructure/random/。

@abstract func set_seed(seed_value: int) -> void
@abstract func get_seed() -> int
@abstract func next_float() -> float
@abstract func next_int(min_value: int, max_value: int) -> int
```

**钉死要点**
- Deterministic Replay 至少记录：Build Version、Content Version、Schema Version、RNG Seed、Command Sequence、Game Time、Relevant External Inputs、Checkpoints（01 §30）。
- **迁移映射**：现有 `services/combat/combat_core.gd` 已用 SeededRNG（有过「固定种子修非确定性测试」的实践）。这是**良好基础**，迁移时把 SeededRNG 提升为 `RandomProvider` 的 Infrastructure 实现即可，不必重写随机算法。

---

## 11. GDScript 原生类型策略（钉死）

> 依据 01 §87 / 宪法 0-B.1 ~ 0-B.8 / 0-B.16。

### 11.1 类型使用边界

| 场景 | 允许 | 禁止 |
|---|---|---|
| 字段声明 | `var id: EntityId`、`var qty: int`、`var ids: Array[String]` | 裸 `var x`（Variant 推断） |
| 返回类型 | 必须显式 `-> T`；无返回值用 `-> void` | 省略返回类型 |
| 参数类型 | 必须显式 `p_x: T` | 省略参数类型 |
| 数组 | `Array[DomainEvent]`、`Array[MutationRecord]`（Typed Array） | `Array`（无类型） |
| 跨模块核心契约 | `class_name` + 强类型字段 | `Dictionary` / `Variant` |
| Command / Event 载荷 | 具体 `class_name` 类型 | `Dictionary` |
| Domain State | 具体 `class_name` 类型 + 私有字段 | `Dictionary` / Node |
| Save DTO | 具体 `class_name` 类型（SaveDTO） | 直接序列化 Runtime Object |
| 对象基类 | `RefCounted`（Command/Query/Result/Error/Event/Transaction/State） | `Node`（除非确需引擎能力） |

### 11.2 Variant / Dictionary 允许边界

**Variant 允许**：Raw Content、外部未知输入、Editor Metadata、Debug Metadata、Schema Parser Boundary。
**Variant 默认禁止**：Domain State、Command Payload、Event Payload、Actor Runtime State、Save DTO、跨模块核心 Contract。

**Dictionary 默认仅用于**：Raw JSON、Authoring Data、Config、临时工具数据、明确的扩展 Metadata。
**Dictionary 禁止**：成为 Universal Context / Runtime State / Command / Event Transport。

### 11.3 Dynamic Data Boundary 登记表（强制）

> 宪法 0-B.2：「如确需使用，必须登记 Dynamic Data Boundary」。不登记即视为违规。

| ID | 位置 | 类型 | 用途 | 约束 |
|---|---|---|---|---|
| **K-DB-01** | `OperationError._context` | `Dictionary` | 错误扩展元数据（诊断/日志） | **禁止**承载业务判断依据；读取后不得用于分支决策 |
| **K-DB-02** | Content Schema Parser Boundary | `Dictionary`/`Variant` | 原始 JSON → Definition 转换 | **仅限** `infrastructure/content`、`data/schemas`；转换产物必须是强类型 Definition |
| **K-DB-03** | `QueryResult.get_payload_as(expected_type)` 参数 | `Variant`（类型对象） | GDScript 无泛型下的类型校验 | 仅用于 `is_instance_of` 校验，**不**作为数据载荷 |

**新增任何 Variant/Dictionary 用途，必须先登记新 K-DB 号并走 ACR。**

### 11.4 readonly / 抽象 / 泛型三条铁律

| 能力 | 立场 |
|---|---|
| `readonly` | **不存在**。一律用 **私有 backing field（`_x`）+ `get_x()` + 受控 Mutation API**。禁止无业务约束的公共 setter 作为状态后门。 |
| 泛型 | **不作为架构前提**。用 `NPCRepository`/`QuestRepository`/`ItemRepository` 具体类，不建 `IRepository<T>`。 |
| `@abstract` | **仅用于**：多实现契约、测试替身、平台差异、策略替换。**禁止**为「看起来像接口」而抽象（宪法 0-B.5）。本稿中仅 6 处使用：`Condition` / `Effect` / `Rule` / `GameFacts` / `UndoStrategy` / `Repository` / `GameClock` / `RandomProvider`。 |
| `IXXX` 命名 | 不强制。Interface 是**架构角色**，不是命名规范。 |

---

## 12. Enforcement：规则 → 执行层 → Gate 矩阵

> 依据 01 §91 ~ §96 / 宪法 0-A.5。**能自动检查的规则不得长期停留在 E0。**
>
> **编号命名空间（2026-09-05 与 04 联合勘定）**：本表 Gate 列使用**逻辑编号 LN** = 宪法 §88（GATE01~20）∪ 01 §127（GATE21~32）；本矩阵引用的 GATE21~28 全部为 01 §127 原名，无需改动。LN↔物理槽位映射唯一权威表在 `04_Test_Infrastructure_Architecture_Gate施工图_V1.2.md` §2.2。

| RULE_ID | 规则 | 严重度 | 执行层 | 检查器 / 测试 | Gate |
|---|---|---|---|---|---|
| K-R01 | Kernel 不得依赖任何层（含 Godot Runtime API） | FATAL | E3 / E4 | `dependency_validator` | GATE22 |
| K-R02 | Kernel 内禁止 `Node` / `SceneTree` / `get_tree` / `get_node` | FATAL | E3 / E4 | `forbidden_api_validator` | GATE22 |
| K-R03 | Kernel 内禁止 `FileAccess` / `DirAccess` / `JSON` / `ResourceLoader` / `ProjectSettings` | FATAL | E3 / E4 | `forbidden_api_validator` | GATE22 |
| K-R04 | Kernel 内禁止 `randf()` / `randi()` / `RandomNumberGenerator` | FATAL | E3 / E4 | `forbidden_api_validator` | GATE22 |
| K-R05 | Kernel 内禁止系统时间 API | FATAL | E3 / E4 | `forbidden_api_validator` | GATE22 |
| K-R06 | Kernel 内禁止无类型 `var` / 无返回类型函数 | ERROR | E3 | `gdscript_type_validator` | GATE21 |
| K-R07 | Kernel 内禁止裸 `Array`（须 Typed Array） | ERROR | E3 | `gdscript_type_validator` | GATE21 |
| K-R08 | Kernel 内禁止 `Dictionary` 载荷（K-DB 登记项除外） | FATAL | E3 / E4 | `forbidden_api_validator`（白名单 K-DB） | GATE22 |
| K-R09 | Kernel 所有公共字段必须私有 backing + getter，禁止公共 setter | ERROR | E3 | `state_owner_validator` | GATE25 |
| K-R10 | Kernel 类型必须继承 `RefCounted`，禁止继承 `Node` | FATAL | E3 | `dependency_validator` | GATE22 |
| K-R11 | 错误判断只能比较 `ErrorCode` 常量，禁止比较 message 字符串 | FATAL | E3 | `naming_validator` + 自定义扫描 | GATE24 |
| K-R12 | Event 命名必须过去时；禁止 `Start*Event` / `Do*Event` | ERROR | E3 | `naming_validator` | GATE24 |
| K-R13 | `CommandResult` 未提交时 `committed_events` 必须为空 | FATAL | E2 | `transaction_test`（Contract Test） | GATE26 |
| K-R14 | Rollback 必须按 MutationRecord.sequence 逆序 | FATAL | E2 | `transaction_test` | GATE27 |
| K-R15 | Rollback 失败必须产出 `RECOVERY_REQUIRED`，禁止静默 | FATAL | E2 | `transaction_test` | GATE27 |
| K-R16 | Command 排序只依赖 `sequence`，禁止依赖 Dictionary/Node/线程顺序 | FATAL | E2 | `command_ordering_test` | GATE28 |
| K-R17 | Kernel 公共 API 变更必须同步 Contract Registry | FATAL | E3 | `contract_drift_validator` | GATE24 |
| K-R18 | 修改 Kernel 文件必须持有 Write Lease 且在 scope 内 | FATAL | E4 | `changed_file_scope_validator` | GATE23 |

**Enforcement 覆盖率目标**：本表 18 条规则中，**E3/E4 共 12 条、E2 共 5 条、E1 共 0 条、E0 共 0 条**（K-R17 同时含 E3）。**E0 占比 0%**，满足「不得长期停留在 E0」。

---

## 13. Freeze 清单（批准后冻结）

冻结后 **AI 可以消费、实现、测试、提出变更提案**；**不得**私自修改、偷改参数、新增 Event（01 §100）。

| 冻结项 | 内容 |
|---|---|
| 类型签名 | 本文档第 2~10 节全部 `class_name`、方法签名、参数/返回类型 |
| `ErrorCode` 常量表 | 现有 14 个常量的名称与字符串值 |
| `TransactionContext.State` 枚举 | 5 个状态取值与语义 |
| `DomainEvent.Phase` 枚举 | PENDING / COMMITTED |
| Dynamic Data Boundary | K-DB-01 ~ K-DB-03 及其约束 |
| 目录结构 | `kernel/` 下 13 个子目录划分 |

**冻结版本号**：`KERNEL-CONTRACT v1.2.0`（随 ADR 升版）

---

## 14. 完成定义（DoD，01 §135）

02 施工图「完成」必须**同时**满足：

- [ ] **Implementation**：`kernel/` 全部契约类落地，`--headless --quit` 零 SCRIPT/PARSE/COMPILE ERROR
- [ ] **Contract Compliance**：每个契约类有对应 Contract Test（签名/类型/不可变性）
- [ ] **Architecture Compliance**：K-R01~K-R18 全绿（GATE21/22/23/24/25）
- [ ] **Required Tests**：Transaction Test 覆盖 01 §118 全部 11 种失败路径
- [ ] **Required Gates**：GATE21/22/24/25/26/27/28 全绿
- [ ] **Regression**：现有 `verify_all.py` 9 门禁仍全绿，**零既有测试被删改**
- [ ] **Documentation**：Contract Registry 已登记、变更通告已出、ADR 已建

**缺一：NOT COMPLETE。**

---

## 15. 与现有工程的迁移映射

> 依据 01 §105（Legacy 是 Reference 不是 Authority）与宪法第 171 节（旧工程资产应升级而非丢弃）。

| 现有资产 | 现状 | 迁移去向 | 处理方式 |
|---|---|---|---|
| `core/condition.gd`（ConditionService + GameFacts 适配器） | 统一条件 DSL | `Condition` + `GameFacts` 契约 | **保留思想**，收敛求值入口 |
| `core/command_dispatcher.gd`（`"cmd:arg"` 字符串路由） | 命令分发 | Execution 的 Command Dispatcher | ⚠️ **语义冲突**，见 §16 开放问题 O-1 |
| `autoload/EventBus.gd`（84 信号，2 处 Dictionary） | 全局事件总线 | Typed Domain Event + Infrastructure Dispatcher | **保留单一总线（未分裂，符合宪法第15节）**，升级载荷为强类型 |
| `services/combat/combat_core.gd`（SeededRNG） | 确定性随机 | `RandomProvider` 实现 | **良好基础**，提升为 Infrastructure 实现 |
| `autoload/weather_time_service.gd` | 天气 + 时间 | `GameClock` 实现 + World 模块 | **拆分**：时间→Clock，天气→World |
| `autoload/SaveManager.gd`（`SAVE_VERSION 1.1.0` + 迁移步骤） | 存档 | `SaveResult` / `LoadResult` + Persistence Boundary | **已有版本化与迁移**，属优良资产，直接升级 |
| `data/schemas/` + 72 个 JSON | 内容定义 | `content/definitions/` + Content Registry | **保留**，Phase 5 补 Registry/Index |
| `verify_all.py`（9 门禁） | 工程门禁 | `verify_all` 统一入口 | **保留并扩充**（01 §126 的 GATE21~32） |
| 73 个测试文件 | 测试资产 | `tests/{unit,contract,architecture,...}/` | **保留**，按宪法第 172 节迁移为行为测试 |

---

## 16. 开放问题（必须 ACR / ADR 裁决，不得 AI 自行决定）

| ID | 问题 | 冲突点 | 需要的决策 |
|---|---|---|---|
| **O-1** | 现有 `core/command_dispatcher.gd` 是 `"cmd:arg"` **字符串路由**，与 Kernel 的**强类型 Command** 语义不同 | 二者都叫「Command」，但一个是脚本字符串指令（对话/演出用），一个是事务化意图 | **ADR 裁决**：是①合并为一套（字符串→强类型 Command 适配层）、还是②保留两套并明确命名边界（如脚本指令改名 `ScriptDirective`，避免术语混淆）。**倾向②**，避免 LLM/演出链路被事务化拖重 |
| **O-2** | `Query` 返回值在无泛型下如何保证强类型 | GDScript 无泛型（宪法 0-B.6） | **本稿已定**：每个 Query 声明自己的 `XxxSnapshot`，`QueryResult` 只做传输壳 + `get_payload_as()` 类型校验。需在 ADR 中确认 |
| **O-3** | Mutation Journal 的 `before` 值存储 | Kernel 不能感知业务类型 | **本稿已定**：由 State Owner 提供具体 `UndoStrategy`，持有 before。需在 ADR 中确认「每状态键一个类」带来的类数量增长可接受 |
| **O-4** | Kernel 落地节奏 | 本稿契约约 20 个类，是否一次性落地 | **建议**：Phase B 一次性落地**契约骨架 + Transaction Test**（不改任何既有业务代码），确保零回归；具体 Command/Query 由各模块在 Phase D 增量实现 |

---

## 17. 02 的一句话总纲

> **Kernel 不实现任何玩法，它只把「身份、成功/失败、意图、事实、事务、时间、随机、存储」这八件事的形状钉死。**
> 钉死之后，上层所有模块讲的是同一种语言；AI 无论开多少个窗口，都只能在同一种语言里说话——这就是「让架构不允许 AI 靠猜测施工」的第一块地基。

---

## 关联文档

- 上位：`docs/constitution/PROJECT_CONSTITUTION_V1.2.md`、`docs/architecture/01_总体架构施工图_V1.2.md`
- 平级：`docs/architecture/三张工程图_V1.2.md`、`docs/architecture/ACR-0001_采纳V1.2宪法与目标架构迁移.md`
- 下位（待产）：`03 Execution 与 Transaction Runtime 施工图`、`04 Contract / Schema 施工图`、`05 Test Infrastructure / Architecture Gate 施工图`
