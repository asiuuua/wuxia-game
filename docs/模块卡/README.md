# 模块卡索引（L2 · 逐模块）

> 中期#1 交付物。基于 `tools/desktop_studio/scan_deps.py`（L1 结构认知）与真实代码沉淀，逐模块记录：职责、关键文件、依赖（上游）/被依赖（下游）、对外 API、健康度、开放问题/待办、架构备注。
> 据实不臆造：所有路径/类名/信号名来自工程真实文件；BUG/派单号来自 `docs/代码审计报告_2026-09-02.md`、`docs/更改日志.md`、`docs/AI交接日志_2026-08-29_菜单解耦收尾.md`。

| 模块 | 文件 | 主权窗口 | 层定位 |
|---|---|---|---|
| 背包 Inventory | [背包.md](背包.md) | 背包窗口 | 服务层 + 数据层 + UI 层 |
| 对话 Dialogue | [对话.md](对话.md) | 对话窗口 | 服务层 + 数据层 + UI 层 |
| 结缘 Romance/Bond | [结缘.md](结缘.md) | 结缘窗口 | 服务层（多服务+门面）+ UI 层 |
| UI 框架 | [UI.md](UI.md) | UI 窗口 | autoload 单例 + 组件 + 配置/主题 |
| 存档 Save/Load | [存档.md](存档.md) | 未单独立窗（UI 表现归 UI 窗口） | 共享地基级 autoload 中枢 |
| 战斗 Combat | [战斗.md](战斗.md) | 战斗窗口 | 服务层（CombatCore 纯逻辑 + CombatService 适配）+ 数据层 + 场景层 |
| 商店 Shop | [商店.md](商店.md) | 商店窗口 | 服务层（无状态）+ 数据层 + UI 层 |
| 锻造 Forge | [锻造.md](锻造.md) | 锻造窗口 | 服务层（无状态）+ 数据层 + UI 层 |
| 炼药 Alchemy | [炼药.md](炼药.md) | 炼药窗口 | 服务层（无状态）+ 数据层 + UI 层 |
| 门派 Sect | [门派.md](门派.md) | 门派窗口 | 服务层（SectService 有状态 + ISaveable）+ 数据层 + UI 层 |

## 配套能力
- L1 依赖图（中期#2）：`GET /api/deps`（工作室任务总控 tab「🕸 依赖图」按钮），自动标注五层架构「向上依赖违例」。
- 当前唯一真实违例：`autoload/ui_manager.gd` → `scenes/ui/icon_registry.gd`（见 [UI.md](UI.md) 状态段），应走 EventBus 解耦，非阻断 minor 耦合。

## 使用方式
- 接任务前：先读本索引定位模块主权窗口与依赖，再 `tools/change_log.py query --module <嫌疑模块>` 看最近改了什么，交叉 `git log -- <文件>` 与 `tools/handoff.py dashboard` 确认非他人回归。
- 跨窗依赖（如 结缘→背包 聘礼/送礼、结缘→天数、UI→EventBus）：改前先 handoff 派单，严守「共享地基冻结」与「双闸门非绿即阻断」铁律。
