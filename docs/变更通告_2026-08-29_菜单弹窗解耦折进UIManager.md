# 变更通告：菜单/弹窗解耦折进 UIManager（2026-08-29）

## 背景
用户要求「后续菜单、婚姻图标可额外追加」，且符合大厂解耦（UI 只 emit、Service 路由、弹窗生命周期托管、占用最少资源）。
架构/PM/程序/前端/UI 五视角评审结论：

- 提案的**哲学正确**，且与本项目既有的「autoload→core→data→services→scenes」五层架构 + EventBus 完全一致；
- 但提案的**具体代码有 5 处与现有工程规范硬冲突**，且约 70% 能力 `UIManager` 早已有（open_screen/close_screen/close_all_screens/is_any_screen_open/get_open_screen + 6 层 CanvasLayer + get_icon/has_icon）。

评审拍板路线：**折进 UIManager，不新建 `UINavigationService`**（避免双导航器漂移，违反"单一依赖/不互相持有"铁律）。

## 评审隐患清单（已规避）
1. 双导航器漂移 → 不新建 autoload，路由并入 UIManager。
2. `.tres` 被 P7 校验器 `tools/validate_project.gd` 明文禁止 + 编辑器不可编辑 → 菜单配置用 **JSON**（menu_config.json）。
3. `change_scene_to_file` 切场景 = 回归"难度选择选2遍模式"类 bug（autoload CanvasLayer 残留 UI）→ 世界跳转走 `GameManager.start_battle/return_to_town`。
4. 字符串 `emit_signal` 丢失编译期检查 → 用 **typed signal** `ui_action_requested(action_id)`。
5. 弹窗缓存自造 Dictionary → P2 改为 UIManager 内置 `_screen_cache`（UI 弹窗缓存仅隐藏/复用、无需引用计数，不引入 P6 重量级资源管理器，避免杀鸡用牛刀）。

## 共享地基增量表（纯追加，未改既有签名）
| 文件 | 改动 | 类型 |
|---|---|---|
| `autoload/EventBus.gd` | 新增 `signal ui_action_requested(action_id: String)`（@warning_ignore 纯追加） | 共享地基·纯追加 |
| `autoload/ConfigManager.gd` | `MENU_FILES` 常量 + `_menus` 缓存 + `get_menu_config()` / `get_menu_item(action_id)` + `_load_menus()`（`_ready` 调用） | 共享地基·纯追加 |
| `autoload/ui_manager.gd` | `_ready` 订阅 `ui_action_requested` → `_on_ui_action_requested`（据 menu_config 路由：screen→open_screen，nav→GameManager，绝不 change_scene） | 共享地基·纯追加 |
| `data/configs/ui/menu_config.json` | 新增菜单数据（4 类 12 项，含 action_id/screen/badge，icon_id 预留接口） | 新增数据 |
| `scenes/ui/screens/game_menu/GameMenuScreen.gd` | 删除 in-code `_CATEGORIES`；读 menu_config.json 建按钮；按钮只 emit `ui_action_requested`（不再 `_open` 直接跳转）；icon_id 走 `UIManager.get_icon` | UI 窗口主权内 |

## 跨窗 emit 点
- `GameMenuScreen` 按钮 `pressed` → `EventBus.ui_action_requested.emit(action_id)`；`UIManager` 唯一订阅并路由。
- 婚姻（BondRomance）窗口主权：**菜单仅以 `action_id="open_bond"` 触发**，路由仍在 UIManager，未改 BondRomance 内部逻辑 → 无需结缘窗口改动、无需 handoff。
- 新增/删除菜单项 = 改 `menu_config.json`，**零代码改动** GameMenuScreen；新增婚姻/新图标只需在 JSON 加一条（含 `icon_id` 走图标注册表）。

## 设计要点（对齐"占用最少资源"）
- UI 弹窗本就在 autoload CanvasLayer 上（独立于 `TownScene` 树），开菜单/婚姻弹窗不阻塞、不占 gameplay 场景树 → 已满足"不占场景资源"。
- **内存（销毁 vs 缓存）P2 已落地**（见下方 P2 小节）：`screens.json` 加 `cache` 标记（设置/存档 `cache:true`）+ `UIManager` 缓存/销毁分支（关闭即 `queue_free` 或仅隐藏复用）+ `PopupBase.gd`（关闭只 emit 请求，绝不 self.queue_free）。缓存表在 `UIManager` 内置，UI 弹窗缓存是轻量显隐、无需引用计数，故不复用 P6 `ResourceManager`。

## 待办
- **P2**：弹窗生命周期增强（cache/销毁 + PopupBase.gd）—— ✅ 已落地（见下方 P2 小节）。
- **P4**：run_all 双闸门 0✗ + `gen_contract.gd` 更新 `docs/契约总表.md` 登记信号 —— ✅ 已落地（`ui_action_requested` + `popup_close_requested` 均登记）。

## 回归防护
- `tests/unit/test_menu_config_driven.gd`：菜单配置加载 / GameMenu 建 12 按钮且各 emit 正确 action_id / UIManager 路由 `open_bond`→`BondRomance`。

## P2 已落地（弹窗生命周期：缓存 / 销毁 + PopupBase）

### 共享地基增量表（P2）
| 文件 | 改动 | 类型 |
|---|---|---|
| `data/configs/ui/screens.json` | `SaveLoadScreen` / `SettingsScreen` 改为 `{path, cache:true}` 对象写法；其余条目保持纯路径字符串（`_resolve_screen` 兼容两种写法，向后兼容） | 共享地基·结构扩展（向后兼容） |
| `autoload/EventBus.gd` | 新增 `signal popup_close_requested(popup: Control)`（@warning_ignore 纯追加） | 共享地基·纯追加 |
| `autoload/ui_manager.gd` | 新增 `_screen_cache` / `_exit_tweens`；`open_screen` 据 `cache` 复用或新建；`close_screen` 按 `cache` 隐藏(保留)或 `queue_free`(销毁)；`get_cached_screen(name)`；`close_all_screens` 一并释放缓存实例并清缓存；`_ready` 订阅 `popup_close_requested` → `_on_popup_close_requested` | 共享地基·纯追加 |
| `scenes/ui/screens/popup_base.gd` | 新增弹窗基类：`popup_id` + 复用 `EventBus.popup_close_requested`（统一总线，不自声明重复信号）+ `make_glass_panel(size)` 统一玻璃主面板 + `request_close()`（只经 EventBus emit，绝不 self.queue_free） | 新增基类 |

### 行为
- 弹窗分两种模式：**常驻缓存**（高频：设置/存档，关闭只隐藏、保留在层上，重开复用同一实例，省重建开销）vs **一次性销毁**（默认，关闭 `queue_free` 彻底释放，防内存堆积）。
- 弹窗自身**绝不 `queue_free` 自己**：关闭只 `request_close()` emit `popup_close_requested`，由 `UIManager` 统一收口（隐藏或销毁）。
- 缓存复用安全：重开时 kill 进行中的关闭补间（`_exit_tweens`），避免动画结束后把复用实例误隐藏。
- `close_all_screens`（读档/新游戏）连缓存实例一并 `queue_free` + 清 `_screen_cache`，无残留隐藏节点。
- 想新增缓存弹窗：在 `screens.json` 把该条目写成 `{path, cache:true}` 即可，**零代码改动**。

### 回归防护
- `tests/unit/test_popup_lifecycle.gd`：① 设置(cache:true)打开入缓存、关闭保留、重开复用同一实例；② 装备(默认)不进缓存、关闭走销毁；③ `PopupBase.request_close` 只 emit `popup_close_requested(self)`，不自我销毁。

## P2.5 五子屏迁移继承 PopupBase + 信号路由修复（用户授权"按你的逻辑来"）

### 改动
- 装备/锻造/炼药/商铺/门派 5 个子屏：`extends Control` → `extends PopupBase`（统一弹窗基类）；删除各自的 `const UICenterUtils`，玻璃面板改用 `make_glass_panel(size)`（去掉手写的 `Panel.new`+`center`+`apply_glass_style` 三行）；关闭按钮 `close.pressed.connect(UIManager.close_screen.bind(self))` → `close.pressed.connect(request_close)`（视图只 emit，UIManager 经事件总线收口）；`_ready` 设 `popup_id`。
- 5 屏结构同构，改造纯机械化、零业务改动，画风/布局/居中全部保持不变。

### ⚠️ 修复 P2 遗留架构断裂（关键）
- P2 的 `PopupBase` 自声明了本地 `signal popup_close_requested`，而 `UIManager` 订阅的是 `EventBus.popup_close_requested`——**两条独立信号**，导致 `request_close()` 发射后无人收口。P2 因无真实弹窗走 `request_close` 关闭，该断裂未暴露。
- 修复：`PopupBase` 删除本地信号，`request_close()` 改为 `EventBus.popup_close_requested.emit(self)`，统一走全局事件总线；UIManager（`_on_popup_close_requested`）据此 `close_screen`，缓存/销毁决策不变。
- 同步修测试：原 `test_popup_base_request_close_emits_signal` 连的是 PopupBase 本地信号（已删）→ 改连 `EventBus.popup_close_requested`；新迁移测试亦连 EventBus。

### 测试坑（再记）
- GDScript 4.7.2 lambda 内写外层局部变量不生效（同 P2）——连接一律用"测试方法 Callable + 实例变量"，不写 lambda 捕获赋值。
- `get_open_screen(name)` 按名查，前一条测试 `queue_free` 的实例未真正释放前仍占名，重开被 Godot 自动改名 `@2` → 按名断言失败；断言改用 `is_any_screen_open()`（不依赖名字），并选未被其它测试占用名字的 `ForgeScreen` 走真实路径。

### 回归防护
- `tests/unit/test_popup_lifecycle.gd` 增至 5 项：① 设置缓存复用 ② 装备销毁 ③ PopupBase.request_close 经 EventBus emit ④ 子屏继承 PopupBase + request_close 经总线 emit ⑤ 子屏经 UIManager 打开后 request_close 关闭（is_any_screen_open 归 false）。

### 双闸门
- GATE1 `--quit` 零 SCRIPT/PARSE/COMPILE ERROR；GATE2 `run_all` 全程 0✗（含 P2.5 新 2 项）。
- ⚠️ 新增 `class_name PopupBase` 后须 `godot --headless --editor --quit` 重建 `global_script_class_cache.cfg`，否则 5 屏 `extends PopupBase` 报 "Could not resolve script"（headless `--quit` 不重建缓存）。本次已重建。

## P2.6 六屏统一继承 PopupBase（用户授权"统一"）

### 改动（属性/背包/结缘/技艺/设置/菜单根）
- 6 屏 `extends Control` → `extends PopupBase`（与 P2.5 同构改造）；删除各自手写的玻璃块（`Panel.new`+`center`+`apply_glass_style`），改 `make_glass_panel(size)` 居中玻璃面板；关闭按钮 `close.pressed.connect(UIManager.close_screen.bind(self))` → `close.pressed.connect(request_close)`；`_ready` 设 `popup_id`（Attributes/Inventory/BondRomance/Abilities/Settings/GameMenu）。
- **GameMenuScreen 冲突修复**：其自带 `const UICenterUtils = preload(...)` 与父类 `PopupBase` 同名 const 冲突（`The member UICenterUtils already exists in parent class`）→ 删除该 const（父类已提供；迁移后居中由 `make_glass_panel` 接管，不再直接引用）。
- **SettingsScreen 自适应保留**：`_build_panel_frame` 内的动态 `_fit_panel` 自适应逻辑不动（区别于固定 size 的 `make_glass_panel`）；`_go_back()` 改 `request_close()`，借此一处统一"返回按钮 / 遮罩点击 / ESC(ui_cancel)"全部关闭路径。
- **两处程序化关屏补统一**（关闭只走总线）：
  - `InventoryScreen._unhandled_input` 的 `ui_cancel` 分支：`UIManager.close_screen(self)` → `request_close()`。
  - `BondRomanceScreen._on_wedding` 婚礼成功后关屏：`UIManager.close_screen(self)` → `request_close()`。
- 至此"菜单模块弹窗"11 屏（装备/锻造/炼药/商铺/门派 + 属性/背包/结缘/技艺/设置/菜单根）全部继承 `PopupBase`，关闭逻辑 100% 经 `EventBus.popup_close_requested` → `UIManager` 收口。

### 未纳入统一（刻意边界，非缺口）
- HUD 5 面板（Hud/quest_track/status_card/skill_bar/top_right_menu）：常驻 HUD，非弹窗。
- 组件（ConfirmDialog/SaveCard/MenuItem/UIBackground）：复用构件，非顶层屏。
- 特殊 overlay（MapScreen/DialogOverlay/CelebrationOverlay/LoadingScreen）：地图/对话/CG/转场各有独立生命周期，故意不统一。
- BaseScreen 体系（MainMenu/SaveLoad/DifficultySelect）：走另一套基类，设计上不混用。

### 回归防护
- `tests/unit/test_popup_lifecycle.gd` 增至 6 项：`test_remaining_screens_migrated_and_unified` 遍历 6 屏键名（注意 `BondRomance`/`GameMenu` 在 `screens.json` 不带 `Screen` 后缀）打开→断言继承 PopupBase→`close_screen`；菜单专属稳定 6/0。

### 双闸门（本次）
- GATE1 `--quit` 零硬错（干净）。
- GATE2 菜单专属 0✗；`test_popup_lifecycle` 6/0 稳定。
- ⚠️ **GATE2 flaky 真因（已定位，非测试逻辑 bug、非菜单主权）**：早前连跑偶发 `test_reset_clears_pops_on_reuse` / `test_equip_swap_preserves_old_instance` 两种不同失败、且套件文件数在 33↔34 漂移。根因是**类缓存 `global_script_class_cache.cfg` 被并发 Godot 进程跑坏**（并行 AI 活动时多进程抢 `.godot` 缓存，部分 `test_*.gd` 因 `class_name` 未解析而解析失败/被静默跳过）。串行执行（无并发 Godot）连跑 5 次全 34/0 稳定绿；`test_equip_swap_preserves_old_instance` 自带 `before_each` 已 `reset` 两 service，非真实换装 bug。
- ⚠️ **`core/combat_event_renderer.gd` 编译错误为误报**：该文件为并行 AI 新增的 untracked 文件，早前汇总疑其有 static 调用缺类名前缀，现核实磁盘版本 GATE1 零硬错、可正常编译，无需修复（但建议提交以免丢失）。
- 🔧 **GATE2 门禁加固（`tests/unit/run_all.gd`，纯测试脚手架）**：原 `sc.new() as TestBase` 为 null 时静默 `skipped`（可能假绿）→ 改为**明确计入 suite_fail 并提示缓存重建**；加载失败路径补"类缓存可能损坏→`godot --headless --editor --quit` 重建、禁并发"提示。消除假绿，缓存再坏也红而非静默跳过。
- ✅ **GATE2 正确跑法（铁律）**：① 无并发 Godot 进程（串行验证）；② 若怀疑缓存坏，先 `godot --headless --editor --quit` 重建 `global_script_class_cache.cfg` 再跑 `run_all.tscn`；③ **切勿 `rm` 直接删类缓存文件**——`--quit` 模式不写缓存，删后 GATE1 会全崩报 `not declared`，须用 `--editor --quit` 重建（本次排查曾误删并重建，已恢复）。
