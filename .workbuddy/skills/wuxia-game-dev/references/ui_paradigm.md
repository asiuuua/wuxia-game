# UI 解耦范式（PopupBase + EventBus 收口）

> 菜单弹窗系统已统一为大厂级解耦架构：视图只渲染/接收点击，关闭只"请求"，生命周期由 UIManager 统一管。

## 一、弹窗基类 `PopupBase`

位置：`scenes/ui/screens/popup_base.gd`。所有菜单弹窗继承它。

```gdscript
extends Control
class_name PopupBase
const UICenterUtils = preload("res://scenes/ui/ui_center_utils.gd")
var popup_id: String = ""

func _ready() -> void:
    pass

func make_glass_panel(size: Vector2) -> Panel:
    var p := Panel.new()
    p.size = size; p.custom_minimum_size = size
    UICenterUtils.center_panel(p); UICenterUtils.apply_glass_style(p)
    return p

func request_close() -> void:
    EventBus.popup_close_requested.emit(self)
```

- **`make_glass_panel(size)`**：居中玻璃面板，替代各屏手写锚点/StyleBoxFlat。
- **`request_close()`**：**只 emit `EventBus.popup_close_requested`，绝不自毁节点**。子类关闭按钮统一 `close.pressed.connect(request_close)`。

## 二、关闭收口（关键铁律）

- `UIManager` 在 `_ready` 订阅 `EventBus.popup_close_requested`（`ui_manager.gd:49`），收到后统一 `close_screen`——缓存隐藏或销毁都由 UIManager 决定。
- 子类**任何关闭路径**（按钮、ESC、`ui_cancel`、程序化关屏）都走 `request_close()`，禁止直接 `UIManager.close_screen(self)`（绕过事件总线会破坏解耦，且可能重复触发）。
- 迁移清单（已落地，11 屏继承 PopupBase）：属性/背包/结缘/技艺/设置/菜单根 + 装备/锻造/炼药/商铺/门派。`Inventory`(ESC) 与 `BondRomance`(婚礼后) 两处程序化关屏已改为 `request_close()`。

## 三、UIManager 6 层 CanvasLayer

- 层级常量：`Layer.POPUP = 300`（等），HUD=50（真实 layer 50，世界0↔转场100 之间），转场=100。
- `open_screen(name, layer)`：经 `screens.json` 注册，脚本 `script.new()` 实例化，`cache:true` 标记缓存屏（设置/存档）。
- `screens.json` 注册键约定：`BondRomance` / `GameMenu` **不带** `Screen` 后缀（其余带）；测试/打开时用键名而非文件名。
- `_ready` 订阅 `popup_close_requested` 收口；`mount_hud`/`unmount_hud` 管理常驻 HUD。

## 四、菜单配置驱动（加菜单零代码）

- `data/configs/ui/menu_config.json`：声明菜单项（文本/图标/跳转 screen/回调），UI 读取后动态生成菜单。新增菜单项改 JSON 即可，无需改 `.gd`。
- 图标接口：`UIManager.get_icon(id)` / `has_icon(id)`（id 派生实体 id），多处已接线。

## 五、玻璃面板与主题

- 主题色集中在 `core/constants/ui_theme.gd`（共享地基边界外但 UI 主权内）。**禁止裸颜色散落**到各 `.gd`（已知待办：主题铁律收口）。
- 玻璃样式由 `UICenterUtils.apply_glass_style(panel)` 统一施加。

## 六、组件与特殊 overlay（不混用 PopupBase）

- 组件：`ConfirmDialog` / `SaveCard` / `MenuItem` / `UIBackground` 是复用构件，非顶层弹窗。
- 特殊 overlay：`MapScreen` / `DialogOverlay` / `CelebrationOverlay`（CG 播放）/ `LoadingScreen`（转场）各有独立生命周期，故意不继承 PopupBase。
- HUD 5 面板（Hud/quest_track/status_card/skill_bar/top_right_menu）是常驻 HUD，不继承 PopupBase。

## 七、写新弹窗的标准步骤

1. 新建 `.gd` `extends PopupBase`，设 `popup_id`。
2. `_ready` 内 `var panel := make_glass_panel(Vector2(w, h))` 作为根容器。
3. 关闭按钮 `close.pressed.connect(request_close)`；ESC/`ui_cancel` 也走 `request_close()`。
4. 在 `screens.json` 注册键（注意后缀约定）。
5. 若需配置驱动，写入 `menu_config.json`。
6. 加 `test_*.gd` 验证可打开/关闭，跑双闸门。
