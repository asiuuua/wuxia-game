# 启动加载与主菜单 UI 落地路线图

> 配套设计稿：`docs/启动加载与主菜单UI详细设计.md`
> 目标：把"启动加载 + 主菜单 + 存档/设置/弹窗/转场"整套 UI 落到本项目（武侠江湖，Godot 4.3，数据驱动 + 模块化 + 无 autoload class_name 纪律）。
> 周期估算沿用设计稿十二章的 M1–M6，但**按本项目现状标注前置依赖与翻译项**。

---

## 0. 项目现状盘点（落地前必读）

### 0.1 已存在（可直接复用）
- `Bootstrap.gd`：启动初始化序列，已发射 `bootstrap_started(total)` / `bootstrap_step_started` / `bootstrap_step_completed` / `bootstrap_completed`。
- `SaveManager`：`save_to_slot` / `load_from_slot` / `register_saveable` / `get_saveable_count`（**无** `has_any_save` / `get_latest_save_slot` / `delete_save` / `list_saves`）。
- `GameManager`：有 `start_new_game()`（**无** `load_game(slot)`）。
- `EventBus`：有 bootstrap 系列信号（**无** `bootstrap_progress`）。
- `PathConstants`：有 `SCENE_BOOTSTRAP` / `SCENE_MAIN_MENU` / `SCENE_TOWN`（**无** `SCENE_LOADING` / `SCENE_SAVE_LOAD` / `SCENE_SETTINGS`）。
- `MainMenu.gd`：简化版（Start/Continue/Settings + 临时 Equipment/Alchemy 按钮），直接进 Town——**将被本稿完整重写**。
- 主题/字体规范：见 `docs/代码规范.md` / `docs/开发规范.md`，需补 `ui_theme` 常量/资源。

### 0.2 完全缺失（需新建）
- `UIManager`（autoload，无 class_name）
- `TransitionManager`（autoload，无 class_name）
- `UISceneRegistry`（界面注册表：JSON 或 PathConstants 映射）
- `SaveInfo`（存档信息结构：RefCounted 或 Dictionary）
- `LoadingScreen` / `MainMenu`（重写）/ `SaveLoadScreen` / `SettingsScreen` / `ArchiveScreen`
- `MenuItem` / `SaveCard` / `ConfirmDialog` 组件
- 主题资源（`ui_theme.tres` 或 `core/constants/ui_theme.gd`）
- 本地化 CSV（M6）

### 0.3 红线注意（全程）
- **autoload 脚本一律不写与单例同名的 `class_name`**（今日 08-27 刚踩坑）。`UIManager`/`TransitionManager` 注册为 autoload 时，脚本保持无 `class_name`。
- **`var x := $Path` 推断陷阱**：保持稿中显式类型写法（`@onready var x: T = $Path`），切勿改 `:=`。
- **类型数组**：从节点/Dictionary 来源用 untyped `Array` 或本地显式类型变量。
- **主题不散落硬编码**：色值/字体集中到主题常量或 `.theme`。

---

## 1. M1 — UI 框架 + 加载界面 + Splash（基础，必先做）

**目标**：建立可复用 UI 骨架；让游戏启动后先过"加载界面 → 主菜单"。

**交付物**
1. `autoload/UIManager.gd`（无 class_name）
   - `enum Layer {BACKGROUND, TRANSITION, FULLSCREEN, POPUP, TOOLTIP, SYSTEM_OVERLAY}`
   - `_init_layers()` 在 `get_tree().root` 下挂 6 个 `CanvasLayer`（layer = 枚举值*10）
   - `open_screen(name, layer)` / `close_screen` / `show_popup` / `get_layer`
   - 界面来源：M1 先用 `PathConstants` 常量映射或 `data/configs/ui/screens.json`（新建），不依赖外部 `UISceneRegistry` 复杂实现
2. `data/configs/ui/screens.json`（界面名 → 场景/脚本路径）+ `ConfigManager` 读取（或先常量映射）
3. `scenes/ui/screens/loading/LoadingScreen.gd`（+ `.tscn`）
   - 进度来源：用 `EventBus.bootstrap_step_*` 累加算百分比（**不新增 `bootstrap_progress` 信号**，M1 最简方案）；或给 `EventBus` 补 `bootstrap_progress` 并在 `Bootstrap` 每步发射（二选一，推荐前者）
   - 提示语：先用 `data/configs/ui/loading_tips.json`（武侠短句数组），不用 `tr()`
   - 完成 → 点击进入 → `UIManager.open_screen("MainMenu")`
4. `Bootstrap.gd` 调整：在初始化完成后先 `change_scene_to_file(SCENE_LOADING)`，由 LoadingScreen 接管并跳 MainMenu（替代当前直跳 MainMenu）
5. Splash：用 Godot Boot Splash（`project.godot` `application/boot_splash` + 一张占位 PNG），配置项，低代码
6. `PathConstants` 补 `SCENE_LOADING`

**验收**：headless 零解析错误；编辑器 F5 → 过 Splash → 加载界面(进度跑满) → 点击进主菜单（此时主菜单仍是现有简化版，M2 替换）。

**依赖翻译项**：红线#1（无 class_name）、#2（bootstrap 信号）、#7（tr→JSON）、#11（PathConstants 补常量）。

---

## 2. M2 — 主菜单界面（动态背景 + 交互 + 动画）

**目标**：用完整版 `MainMenu` 替换现有简化版，含动态水墨背景、键盘/鼠标导航、入场动画。

**交付物**
1. 重写 `MainMenu.gd`（去掉临时 Equipment/Alchemy 按钮，改 6 选项 + 键盘导航 + 快捷键 N/C/L/O/G/Q）
2. `MenuItem` 组件（`scenes/ui/components/menu_item/MenuItem.gd` + `.tscn`）：悬停金色箭头、选中音效、禁用态灰显
3. 动态背景：远山/云雾/水面/孤舟/落叶粒子/光柱（`TextureRect` + `AnimationPlayer`，但 M2 先用占位色块/简单动画，真实素材后补——参考已接好的 `assets/characters` 占位套路）
4. 主题接入：`ui_theme` 常量（金色 #D4AF37、米白 #F0E6D2 等），菜单项引用常量不硬编码
5. `GameManager.load_game(slot)` 补（或 MainMenu 直接调 `SaveManager.load_from_slot` + 切场景，沿用现状写法）
6. `SaveManager.has_any_save()` / `get_latest_save_slot()`（M2 用到"继续江湖路"可用性判断）

**验收**：主菜单显示；↑/↓ 导航 + 回车确认；有/无存档时"继续"正确灰显；Esc 弹退出确认（确认弹窗 M5 才做，M2 可先用占位或临时 `print`）；进游戏正常。

**依赖翻译项**：红线#1、#3（SaveManager 缺方法）、#6（load_game）、#8（主题常量）、#9（类型数组）。

---

## 3. M3 — 存档选择界面

**交付物**
1. `SaveLoadScreen`（Header 返回 + 列表 + 自动存档区）
2. `SaveCard` 组件 + `SaveInfo` 结构（由 `SaveManager.list_saves()` 返回 `Dictionary` 数组，避免新建 Resource）
3. `SaveManager` 补 `list_saves()` / `delete_save(slot)` / `get_latest_save_slot()`
4. 读取/删除/新游戏确认（确认弹窗 M5 做，M3 先接 `ConfirmDialog` 占位或直接调用）
5. 缩略图：M3 先用默认占位图（`default_save_thumb.png`），真实截图后补
6. `PathConstants` 补 `SCENE_SAVE_LOAD`

**验收**：主菜单"读取旧梦"→ 存档列表；空槽显示"新的旅程"；读取/删除有确认；自动存档区只读。

**依赖翻译项**：#5（SaveInfo→Dictionary）、#3（SaveManager 方法）。

---

## 4. M4 — 设置界面（音频/画面/控制/语言 + 按键绑定）

**交付物**
1. `SettingsScreen`（左侧分类 + 右侧动态内容）
2. 各分类设置项（滑块/下拉/开关），修改实时生效并写入用户配置（JSON 落 `user://`）
3. 按键绑定：读取/重绑定 `InputMap`（注意：本项目键位已在 `TownScene` 用 `InputMap` 注册 WASD/B/M/Tab，设置界面可复用同一套重绑定逻辑）
4. `PathConstants` 补 `SCENE_SETTINGS`

**验收**：各分类切换正常；滑块/开关实时生效；按键重绑定后游戏内生效；返回主菜单。

**依赖翻译项**：#8（主题）、与已落地的键位系统对接。

---

## 5. M5 — 确认弹窗 / Tooltip / 转场

**交付物**
1. `ConfirmDialog` 组件（`setup(title, content, confirm_cb, cancel_cb)` 模式，稿中已是此写法，保留）
2. `TransitionManager`（autoload 无 class_name）+ 水墨淡入淡出（M5 先用色块/简单 Shader，真实水墨后补）
3. Tooltip / 通知提示（轻量 `Label` + tween）
4. 把 M2/M3 里临时确认的弹窗统一接到 `ConfirmDialog`

**验收**：退出/读取/删除确认弹窗统一样式与动画；场景切换走转场；Tooltip 悬停显示。

**依赖翻译项**：红线#1（无 class_name）、#10（@export→setup 传参）。

---

## 6. M6 — 多分辨率 / 无障碍 / 本地化 / 性能

**交付物**
1. 多分辨率：Stretch `canvas_items` + `keep`，设计分辨率 1920x1080（改 `project.godot`）
2. 无障碍：字号下限、键盘全可达、对比度
3. 本地化：搭建 CSV + `tr()`，把 M1 的 `loading_tips.json` 等迁到 `tr()`；UI 文字膨胀适配
4. 性能：背景动画 CPU<5% / GPU<10%，主菜单 <200MB

**验收**：多分辨率下 UI 不破版；`tr()` 切换简/繁/英；PerfMonitor 抽检内存/帧率达标。

**依赖翻译项**：#7（tr 本地化体系）、主题集中。

---

## 实施建议

- **严格按 M1 → M6 顺序**：M1 是地基（UIManager + LoadingScreen + 流程改造），后面的屏幕全挂在它之上。
- **每阶段独立可编译、headless 零错误**再进下一阶段（沿用今日教训：一个解析错误会雪崩成几十个）。
- **美术素材先占位**：背景/头像/缩略图全用程序生成的占位 PNG（参考已落地的 `assets/characters` 套路），真图后同名覆盖。
- **主题集中**：8.1 色值表落地到 `ui_theme` 常量/资源，脚本只引用，不散落 `Color(...)`。
- **本轮 backlog**：此前收到的「缱绻值系统」设计稿尚未归档，建议在 M 系列之外另开一轮处理（它依赖结缘/BondService，排期在四大系统之后）。
