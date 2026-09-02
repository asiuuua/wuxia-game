# 01 · 装配中枢 GameManager（依赖注入容器）

> 检索关键词：GameManager、装配、DI、依赖注入、服务实例、场景切换、读档写档

## 角色定位
`GameManager`（`autoload`）是工程的**装配中枢 / DI 容器**：
- 持有并实例化全部 `services` 层 `RefCounted` 服务（inventory / shop / forge / alchemy / combat / bond / romance / sworn / master / relationship / quest / sect / dialogue / equipment / save 等）。
- 是**场景切换 / 读档 / 写档**的统一入口；其它模块经 `GameManager.xxx_service` 取服务实例，不直接 `new()` 互相依赖。
- 不持有任何玩法逻辑，只做装配与编排（编排同样走 EventBus 连线，如 `combat_finished → quest_service._on_combat_finished`）。

## 关键公开方法（契约总表摘录）
- `player_state: PlayerState` —— 玩家状态（等级/力量/银两/性别）。
- `inventory_service` / `shop_service` / `forge_service` / `alchemy_service` —— 经济域服务。
- `bond_service` / `romance_service` / `sworn_service` / `master_service` / `relationship_service` —— 结缘域服务。
- `combat_service` / `dialogue_service` / `quest_service` / `sect_service` / `equipment_service` —— 玩法域服务。
- `start_combat(battle_id)` / `change_scene(scene_path)` / `load_game()` / `save_game()` —— 编排入口。

## 为什么这样设计（解决的问题）
- **解耦**：services 之间不互相 `new`，经 GameManager 取单例，避免分散实例化导致状态不一致。
- **可测**：单测里可手动注入固定 service / 固定 seed，验证确定性（如战斗 `SeededRNG`）。
- **装配即文档**：新 AI 读 `GameManager` 即可一眼看清工程有哪些服务、如何取得，秒懂架构意图。

## 隐患
- GameManager 过于庞大时成为「上帝对象」——当前用契约总表 + 服务拆分兜底，新增能力应进对应 service 而非堆进 GameManager。
- 取服务实例必须判空（`if inv == null: return`），避免 autoload 就绪顺序问题（services 在 `_init` 不访问 ConfigManager，调用时再取）。

## 关联
- 见 `02_EventBus契约与信号接缝.md`（跨模块通信方式）
- 见 `10_平台连接器三段_ai_context_reskin_knowledge.md`（ai_context 把此架构意图喂给新 AI）
