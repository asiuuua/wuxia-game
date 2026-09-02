# 02 · EventBus 契约与信号接缝

> 检索关键词：EventBus、信号、NOTIFY、CMD、接缝、跨模块通信、signal
> 等级：E2

## 角色定位
`EventBus`（`autoload`）是跨模块**唯一信号通道**，全工程 **100 个信号**；模块间严禁直接持有对方引用调用逻辑，一律走 EventBus。

## 信号分类铁律：NOTIFY vs CMD
- **NOTIFY（状态变化广播）**：无返回值，纯「我变了，你们自己更新」。例：`inventory_item_added` / `bond_affection_changed` / `combat_finished` / `item_used_in_battle`。
- **CMD（请求动作）**：表达「请做某事」，返回结果经由调用方本地处理（不靠信号回传）。例：UI 点击 → 调 service 方法 → 方法内部 emit NOTIFY。
- **严格分离**：NOTIFY 不该被用作「请求」并期待返回值；CMD 语义不该混进广播信号，否则接缝混乱、难测。

## 高频有序流走返回值，不刷 EventBus
- 战斗内高频有序流程（攻击→结算→下一回合）返回 `Array[CombatEvent]`，**不走 EventBus**，避免信号刷屏与乱序。
- 只有**跨模块通知**（`combat_finished`）与**网格视图更新**（`grid_highlight_update` / `grid_unit_moved`）才走 EventBus。
- 视图层 `Tween` 与逻辑帧需对齐，否则表现错位。

## 接缝测试守卫（GATE2）
- `tests/unit/test_ui_mouse_filter.gd` 等断言「信号接缝不被静默吞掉」；门禁非绿即阻断。
- 新增跨模块信号必须在契约总表登记，否则审计/门禁会抓。

## 解决了什么
- 根除「模块 A 直接调模块 B 私有方法」的隐式耦合 → 单向依赖铁律可落地。
- 战斗/结缘/经济各自只 emit 自己的 NOTIFY，UI 监听刷新，逻辑层零 Node 引用。

## 隐患
- 信号名拼写错 → 静默不触发（无报错）；靠 GATE2 接缝测试 + 契约总表兜底。
- NOTIFY 在 `_ready` 之前 emit 可能无人监听；装配顺序由 GameManager 保证服务先于场景就绪。

## 关联
- 见 `00_架构铁律与分层.md`（跨模块只走 EventBus 铁律）
- 见 `08_静默接缝BUG四层防线.md`（信号接缝被静默吞的防御）
