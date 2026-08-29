# 当前待接管清单（后续 AI 认领用）

> 由 `docs/AI交接日志_2026-08-29_菜单弹窗解耦收尾.md` 提炼。本会话（菜单弹窗解耦）已收尾并推送，以下为仍 open / 残留待办。

## 一、open 派单（handoff 传递板，非本会话产生）

| 派单号 | 来源→目标 | 问题 | 下一步 |
|---|---|---|---|
| `fed3f00da584` | 战斗 → gameplay/town | `TownScene:52` 掉血崩（参数不匹配） | 核对战斗结算回 Town 的伤害入参类型/数量，对齐 CombatCore 接口 |
| `178267684159` | 结缘 → 背包 | 休息/睡觉未推进天数 | 确认 `advance_days` 在结缘休息路径的调用，天数应随休息递增 |
| `acf2246fd5f2` | 背包 → 结缘 | `propose` 聘礼跳过锁定 | 聘礼校验应走背包锁定的 `LOCKED/DISCARDABLE` 守卫，不可绕过 |

跟进：`python tools/handoff.py`（状态机 open→claimed→done→followup→closed）。派单窗口名 `/` 被 sanitize 成 `_`。

## 二、UI 模块审查残留待办（非本会话，待对应主权窗口认领）

来自 `docs/UI模块代码审查_2026-08-29.md`：
1. **BondRomanceScreen**：两条 "debug 满好感" 按钮混进生产代码 → 结缘窗口主权清理。
2. **DialogOverlay**：固定像素布局 + 越权逻辑 → 对话窗口主权重构为配置/自适应。
3. **主题铁律**：裸颜色散落在多处 `.gd`，未走 `core/constants/ui_theme.gd` → 全面收口到主题常量。
4. **Toast / 列表 refresh**：未池化，频繁开关有 GC 抖动 → UI 主权性能优化。

## 三、GATE2 flaky 定性复核（装备 / 战斗窗口）

- 现象：早期连跑 GATE2 时，失败用例在 `test_reset_clears_pops_on_reuse`（战斗实体池飘字 `_pop_layer` 延迟释放 race）与 `test_equip_swap_preserves_old_instance`（装备换装实例身份）之间随机漂移，有时全绿。
- 结论：根因是**并发 Godot 进程抢坏 `.godot` 类缓存**，部分 `test_*.gd` 解析失败被静默跳过（套件数 33↔34 漂移），**非测试逻辑 bug**；串行执行连跑 10 次全 34/0 稳定绿。
- ⚠️ **待复核**：`test_equip_swap_preserves_old_instance` 直接关联已知 `P1-3 装备实例身份`。本会话仅从环境竞态角度消除 flaky，未深入验证换装身份保留在真实游戏流程中是否 100% 正确。**建议装备窗口 owner 用真实换装路径（卸甲→重穿）复核实例 `iid`/耐久是否保留**，必要时补端到端断言。
- `run_all.gd` 已加固（静默 skip→明确计失败+缓存重建提示），将来缓存再坏会红得明确，不会假绿。

## 四、文件归属澄清

- `core/combat_event_renderer.gd`：并行 AI 新增，曾疑 static 调用缺类名前缀编译错——**已核实为误报**（磁盘版 GATE1 零硬错、已跟踪）。归属建议挂**战斗窗口**主权，后续改动走战斗窗口派单。

## 五、快速上手命令（复制即用）

```bash
G="C:/Users/Administrator/.workbuddy/binaries/godot/Godot_v4.7.2-stable_win64_console.exe"
# 双闸门（串行、unsandboxed）
"$G" --headless --path "D:/武侠游戏" --quit 2>&1 | grep -iE "SCRIPT ERROR|Parse ERROR|COMPILE ERROR"
"$G" --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn 2>&1 | grep -iE "套件：|✗ "
# 缓存损坏重建（勿 rm .godot）
"$G" --headless --editor --quit
# 提交（沙箱内不落盘，须 unsandboxed）；中文路径 git add 坑→工作树仅正当改动时用 git add -A
git add -A && git commit -m "[窗名] 简述"
```

## 六、认领流程

1. 在 `references/pending_work.md` 或 `docs/AI交接日志_*` 选一项。
2. `python tools/handoff.py` 把状态置 `claimed`（或开新派单）。
3. 改完跑双闸门全绿，写《变更通告》，提交（`[窗名]` 前缀）。
4. handoff 置 `done` → 源窗确认 `closed`。
