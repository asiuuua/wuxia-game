# 变更通告 · 2026-08-29 · inventory_smoke 对齐 move_instance 类型不变式

## 背景（门禁红根因）
- 多 AI 协同门禁 `gate[3]`（`inventory_smoke.tscn`）此前红：`INV_FAIL pass=9 fail=3`。
- 根因：**跨窗口契约漂移**，非逻辑 bug。背包窗口提交 `1bab4f4` 为 `move_instance` 增加了**类型不变式守卫**（拒绝武器/丹药等拖入材料栏/任务栏，避免破坏 `add_item` 路由不变量），并自带回归测试 `test_move_instance_rejects_cross_type` 佐证其为**有意设计**。
- UI 窗口自有冒烟用例 `tests/ui/inventory_smoke.gd` 仍断言旧的「武器可拖入材料栏并从中装备」，与新契约冲突，导致 3 条断言失败。

## 本次改动（UI 主权内，仅改自有测试）
文件：`tests/ui/inventory_smoke.gd`
1. 武器→`material` 由「断言成功」改为**负向断言**（被拒）：`not inv.move_instance(w_iid, "material", 0)`。
2. 断言武器移动后仍留在 `main` 栏（未跨栏）。
3. 新增**同栏重定位正向用例**：`move_instance(w_iid, "main", 0)` 成功（P2-1 拖拽重排仍可用）。
4. 装备用例由「从 material 取武器」改为「从 main 取武器」：`_first_iid_in(inv, "main", "weapon_sword_iron_001")`。

**未改动任何生产代码、未改动背包窗契约**（`move_instance` 类型不变式保持不变）。

## 验证（双闸门）
- gate[3]：`inventory_smoke.tscn` → `[INV] ALL_INV_OK pass=13 fail=0`（转绿，原 9/3）。
- `--headless --quit` 零 SCRIPT/PARSE/COMPILE/ERROR（本轮无代码改动，沿用既有绿态）。
- run_all 单元套件不受影响（smoke 不在 unit 套件内），沿用 13 套件 0 失败。

## 协同板
- handoff `f1e8ac0c4ce7`（UI窗口 → 背包窗口，原派单）已收口：UI 对齐自有用例，背包窗契约保持不变。
- 请背包窗口确认契约意图无误后 close 本条（若认为 UI 不该改此用例，可回退并改自身契约，但当前契约经其自带回归测试背书，建议保持）。
