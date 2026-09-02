# 模块卡：UI（框架）

> L2 模块卡 · 主权窗口：**UI 窗口** · 沉淀自真实代码（据实不臆造）

- **职责**：全局屏幕栈管理（open/close/popup/HUD 挂载）、转场动画、图标解析、安全区适配、Toast/Tooltip；所有界面场景的统一入口与生命周期收口。
- **层定位**：autoload 单例（UIManager）+ 基类/组件（scenes/ui）+ 配置/主题（core + data/configs/ui + resources/themes）。

## 关键文件
- 管理器：`res://autoload/ui_manager.gd`（`UIManager`，extends Node，**无 class_name**——注释说明避免与单例名冲突）
- 屏幕注册表：`res://data/configs/ui/screens.json`（界面名→.tscn 路径，支持 `{path,cache}`）
- 调色板/配置：`res://core/constants/ui_theme.gd`（`UIPalette`）、`res://data/configs/ui/ui_anim.json`、`res://data/configs/ui/menu_config.json`（`get_menu_item` 路由）、`res://data/configs/ui/skin/*.json`
- 基类/组件：`res://scenes/ui/components/base_screen/BaseScreen.gd`（`class_name BaseScreen`，全屏界面基类）、`screens/popup_base.gd`（PopupBase，关闭经 `EventBus.popup_close_requested`）、`icon_registry.gd`（`IconRegistry`，纯静态工具，**无 class_name**）、`ui_background/UIBackground.gd`、`ui_center_utils.gd`（`UICenterUtils`）、`components/{item_slot,menu_item,save_card,save_name_dialog,skill_slot,status_bar,tooltip,ui_feedback,wuxia_menu_button,confirm_dialog}/*.gd`、HUD `overlays/hud/Hud.gd` + 各 panel
- 框架层：`res://core/ui_skin.gd`（`UISkin`）、`ui_layout.gd`（`UILayout`）、`ui_vfx.gd`（`UIVFX`）
- 主题资源：`res://resources/themes/**`
- **UI 主权范围**（据 `AI交接日志`）：`scenes/ui/**` + `data/configs/ui/**` + `core/constants/ui_theme.gd` + `resources/themes/**` + `autoload/ui_manager.gd`

## 依赖（上游，它用到）
- `EventBus` 信号（UIManager `_ready` 订阅）：`notification_show`（→`show_tooltip`）、`inventory_add_overflow`（→Toast）、`ui_action_requested`（→`_on_ui_action_requested` 路由）、`popup_close_requested`（关闭收口）
- `ConfigManager`：`get_anim_trans/get_anim_ease/get_anim_preset`、`get_menu_item`
- `GameManager`：`start_battle` / `return_to_town`（菜单 nav 类动作，绝不 `change_scene`）
- `IconRegistry`（经 EventBus 运行时注入，非静态预加载——2026-09-02 已解耦）、`GameLogger`、`DisplayServer`（安全区 `get_display_safe_area`）

## 被依赖（下游，谁用它）
- 几乎全部界面场景调用 UIManager（屏幕栈/HUD/图标/Toast）；包括 `scenes/ui/screens/{main_menu,game_menu,esc_menu,difficulty_select,loading,settings,save_load,equipment,alchemy,forge,shop,sect,bond_romance,abilities}/`、`scenes/ui/overlays/{dialog,map,attributes,celebration,hud}/`、各组件、`Bootstrap.gd`、`TownScene.gd`、`top_right_menu_panel.gd`、HUD 测试

## 对外 API（核心入口）
- 层级：`get_layer(layer)`、`Layer` 枚举（BACKGROUND/HUD/TRANSITION/FULLSCREEN/POPUP/TOOLTIP/SYSTEM_OVERLAY）
- 屏幕栈：`open_screen(name,layer,init_data)` / `close_screen(screen,on_closed)` / `close_all_screens()` / `show_popup(name)` / `get_current_screen()` / `is_any_screen_open()` / `get_open_screen(name)` / `get_cached_screen(name)` / `is_popup_open()`
- HUD：`mount_hud(hud)` / `unmount_hud()`
- 图标：`get_icon(icon_id)` / `has_icon(icon_id)`（经 EventBus 注入的 IconRegistry 解析器委托，解析器未注入时回退占位，绝不返回 null）
- 安全区：`get_safe_area_margins()→Vector4` / `apply_safe_area(root)`
- Toast：`show_tooltip(text)` / `hide_tooltip()`

## 状态 / 健康度
- 已修复：`BUG-01`（缓存屏重开未回写栈 → 键盘守卫失效，Critical）、`BUG-02`（open_screen 不防重复）、`BUG-25`（SettingsScreen/LoadingScreen 信号无 `_exit_tree` disconnect，显式断开）
- 依赖图审计（中期#2）：原唯一真实向上依赖违例 `autoload/ui_manager.gd` preload → `scenes/ui/icon_registry.gd`，**已于 2026-09-02 经 EventBus 依赖反转解耦清零**（见变更 `fbcfa8b`；现 UIManager 经 `EventBus.icon_provider_registered` 在运行时接收 UI 层注入的解析器，零静态耦合）。

## 开放问题 / 待办（派单）
- `AI交接日志` 残留：Toast / 列表 refresh 未池化，频繁开关有 GC 抖动 → **UI 主权性能优化（未做）**
- ~~中期#2 违例 `ui_manager → icon_registry`~~ **已治理（2026-09-02，commit `fbcfa8b`）**：经 EventBus 依赖反转解耦，详见「状态/健康度」段。

## 架构备注
- UIManager 是「视图层中枢」，全工程最高频被依赖；其自身只依赖更基础的 autoload/core，不反向依赖 scenes（原 icon_registry 违例已于 2026-09-02 解耦）。
- 菜单 nav 一律走 GameManager 动作，绝不 `change_scene`，保枢纽式世界架构。
