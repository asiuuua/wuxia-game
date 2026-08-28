# 启动加载与主菜单 UI 详细设计（归档稿）

> 本文为外部设计稿的**归档存档**，原文由设计阶段产出，结构完整、风格清晰。
> 下方「翻译与落地须知」列出**直接套用本稿会踩的项目红线与缺失依赖**，落地前必须逐项处理。
> 原始设计正文见本文后半部分（自「一、整体 UI 架构」起）。

---

## 翻译与落地须知（针对本项目武侠江湖，必须先读）

本稿按通用 Godot 写法撰写，与本项目已确立的工程纪律存在以下冲突，**逐条对应、落地时照改**：

### 红线冲突（会导致解析/运行错误）

1. **autoload 不能写同名 `class_name`**
   稿中 `UIManager` / `TransitionManager` 写为 `class_name XxxManager extends Node`，若注册为同名 autoload（如 `UIManager="*res://..."`），会触发"与单例冲突"解析失败——**本会话 08-27 刚为此耗了 2 分钟**。`SaveManager.gd` 顶部注释已记录此坑。
   → 改为：**无 `class_name` 的纯 autoload**，全局名即 `UIManager`；或在脚本里用不同 `class_name` + `const XxxManager = preload(...)` 兜底（不推荐，增加复杂度）。

2. **`EventBus.bootstrap_progress` 信号不存在**
   当前 `EventBus` 只有 `bootstrap_started(total)` / `bootstrap_step_started` / `bootstrap_step_completed` / `bootstrap_completed`（见 `autoload/EventBus.gd:60-63`）。
   稿中 `LoadingScreen._ready` 直接 `connect(EventBus.bootstrap_progress, ...)` 会报"signal not found"。
   → 二选一：① 给 `EventBus` 补 `signal bootstrap_progress(current:int, total:int, message:String)` 并在 `Bootstrap` 每步发射；② `LoadingScreen` 改用现有 step 信号累加算进度（更省事，推荐 M1 用）。

3. **`SaveManager` 缺方法**
   稿中 `MainMenu._check_saves()` 用 `SaveManager.has_any_save()`、`_continue_game()` 用 `SaveManager.get_latest_save_slot()`——**均不存在**。`SaveManager` 现有 `save_to_slot / load_from_slot / register_saveable / get_saveable_count`，无"是否存在/最新槽位/删除"接口。
   → M3 前必须补：`has_any_save() -> bool`、`get_latest_save_slot() -> int`、`delete_save(slot:int) -> bool`、`list_saves() -> Array[Dictionary]`。

4. **`UISceneRegistry` 不存在**
   稿中 `UIManager.open_screen` 调用 `UISceneRegistry.get(screen_name)`。本项目无此注册表。
   → 新建数据驱动的界面注册表：建议 `data/configs/ui/screens.json`（键=界面名，值=`res://...tscn` 或脚本路径），`UIManager` 加载并索引；或直接用 `PathConstants` 常量映射（更简单，M1 推荐）。

5. **`SaveInfo` 类不存在**
   稿中 `SaveCard` 依赖 `SaveInfo`（含 `player_name / player_level / faction_name / format_time() / format_date() / thumbnail_path / scene_display_key`）。
   → 新建 `data/runtime/save_info.gd`（`extends RefCounted` 或 `Resource`），或由 `SaveManager.list_saves()` 直接返回 `Dictionary` 数组（更贴合现有 JSON 存档结构，推荐）。

6. **`GameManager.load_game(slot)` 不存在**
   稿中 `MainMenu._continue_game()` 调用 `GameManager.load_game(latest_slot)`。当前 `GameManager` 只有 `start_new_game()`（见 `autoload/GameManager.gd:40`），**无 `load_game`**。
   → 补 `GameManager.load_game(slot:int) -> void`（内部调 `SaveManager.load_from_slot` + `change_scene_to_file(SCENE_TOWN)`），或 `MainMenu` 直接调 `SaveManager.load_from_slot` + 切场景（现状 `MainMenu.gd` 已是这种写法）。

7. **`tr()` 本地化未搭建**
   稿大量用 `tr("loading_tip_01")` 等。本项目**无 CSV / 翻译文件**，未启用 `ProjectSettings` 本地化，`tr()` 会原样返回 key。
   → M1 先用普通字符串常量或独立 `data/configs/ui/loading_tips.json`；本地化（CSV + `tr()`）放到 M6 阶段统一接入。

### 工程纪律冲突（需调整写法，不致命但必须统一）

8. **主题色/字体硬编码**
   稿在脚本里写 `Color(0.85,0.75,0.4)`（金色）等字面量，且未引用统一 `.theme`。本项目规范（`docs/代码规范.md`）偏好主题资源/常量集中管理。
   → 把 8.1 色值表落到一个 `core/constants/ui_theme.gd`（或 `ui_theme.tres`），脚本引用常量，不散落硬编码；字体同理走 `ProjectSettings` 或 `.theme`。

9. **类型数组纪律（红線 #3）**
   稿中 `@onready var _menu_items: Array[MenuItem] = [$MenuItem_0, ...]` 是类型化数组字面量。从节点路径来源时 GDScript 可解析 `MenuItem` 类型，一般能编译；但本项目红線要求"从 Variant/JSON/Dictionary 来源用 untyped 或本地显式类型"。
   → 保留显式类型（安全），但 M2 实现时验证编译；若报错改用 `Array` + 循环内 `var item: MenuItem = _menu_items[i]`。

10. **`@export` 在纯代码组件里的有效性**
    `MenuItem` / `SaveCard` / `ConfirmDialog` 用 `@export var text: String`。若组件走 `.new()`/`.instantiate()` 纯代码构建，`@export` 不会在检查器显示，但语法合法。本项目现以纯代码实例化为主（如 `EquipmentScreen.new()`）。
    → 统一：纯代码组件用 `setup(...)` 构造参数传值（稿中 `ConfirmDialog.setup()` 已是此模式，保持）；若转 `.tscn` 场景则 `@export` 才有意义。

11. **`MainMenu` 现状会被整体替换**
    当前 `scenes/ui/screens/main_menu/MainMenu.gd` 是简化版（Start/Continue/Settings + 临时 Equipment/Alchemy 按钮），且**直接进入 Town 场景**。稿的 `MainMenu` 是完整重写，会替换它。注意保留"进游戏"入口（`start_new_game` / `load_game`），并确认 `PathConstants` 需补 `SCENE_LOADING` / `SCENE_SAVE_LOAD` / `SCENE_SETTINGS`（现仅有 `SCENE_MAIN_MENU` / `SCENE_TOWN` / `SCENE_BOOTSTRAP`）。

12. **`@onready var x := $Path` 推断陷阱（今日已踩）**
    稿里大多是显式类型（`@onready var _progress_bar: ProgressBar = $ProgressContainer/ProgressBar`），**这是安全的**，保留即可。切勿改成 `var x := $Path`（`$Path` 在某些上下文推断为 Variant，触发 `inference_on_variant=error`）。今日 `TownScene.gd:132` 的 `var node := factory.call()` 就是这个坑。

---

## 原始设计正文

# 武侠单机游戏 — 启动加载与主菜单 UI 详细设计

---

## 一、整体 UI 架构

### 1.1 UI 层级结构

```
┌─────────────────────────────────────────────────┐
│  Layer 6: SystemOverlay  系统顶层（加载遮罩/崩溃提示） │
├─────────────────────────────────────────────────┤
│  Layer 5: Tooltip        提示框/浮动信息           │
├─────────────────────────────────────────────────┤
│  Layer 4: Popup          弹窗/确认框/设置面板      │
├─────────────────────────────────────────────────┤
│  Layer 3: Fullscreen     全屏界面（主菜单/存档/设置）│
├─────────────────────────────────────────────────┤
│  Layer 2: Transition     转场遮罩（淡入淡出/水墨）  │
├─────────────────────────────────────────────────┤
│  Layer 1: Background     背景层（动态场景/视频）     │
└─────────────────────────────────────────────────┘
```

### 1.2 UI 管理器（UIManager）

```gdscript
# services/ui/ui_manager.gd
class_name UIManager
extends Node

enum Layer {
    BACKGROUND,
    TRANSITION,
    FULLSCREEN,
    POPUP,
    TOOLTIP,
    SYSTEM_OVERLAY,
}

var _layers: Dictionary = {}  # Layer -> CanvasLayer
var _screen_stack: Array = []  # 全屏界面栈
var _current_screen: Control = null

func setup() -> void:
    _init_layers()

func _init_layers() -> void:
    for layer in Layer:
        var canvas := CanvasLayer.new()
        canvas.layer = layer * 10
        canvas.name = "Layer_%s" % layer
        get_tree().root.add_child(canvas)
        _layers[layer] = canvas

func get_layer(layer: int) -> CanvasLayer:
    return _layers.get(layer, null)

func open_screen(screen_name: String, layer: int = Layer.FULLSCREEN) -> Control:
    var scene: PackedScene = UISceneRegistry.get(screen_name)
    var screen: Control = scene.instantiate()
    _layers[layer].add_child(screen)
    _screen_stack.append(screen)
    _current_screen = screen
    screen.show()
    return screen

func close_screen(screen: Control = null) -> void:
    var target: Control = screen if screen != null else _current_screen
    if target == null:
        return
    _screen_stack.erase(target)
    target.queue_free()
    _current_screen = _screen_stack.back() if _screen_stack.size() > 0 else null

func show_popup(popup_name: String) -> Control:
    return open_screen(popup_name, Layer.POPUP)

func show_tooltip(text: String, position: Vector2) -> void:
    pass

func hide_tooltip() -> void:
    pass
```

---

## 二、启动加载流程

### 2.1 完整启动时序

```
用户双击游戏图标
    ↓
[0s]  游戏进程启动 → Godot 引擎初始化
    ↓
[0.1s] 显示 Splash Screen（引擎Logo/发行商Logo）
    ↓
[1.5s] Splash 结束 → 进入 Bootstrap 场景
    ↓
[1.5s] 显示「加载中」界面（水墨风格，进度条0%）
    ↓
[1.5s-3.5s] 异步加载：
    ├─ 配置表加载（物品/武功/任务/NPC...）
    ├─ 本地化加载
    ├─ 音频系统初始化
    ├─ 输入系统初始化
    ├─ 存档系统初始化
    └─ 业务服务初始化（玩家/背包/装备...）
    ↓
[3.5s] 加载完成 → 进度条100% → 「点击进入」提示
    ↓
[用户点击] 淡入转场 → 主菜单界面
```

### 2.2 Splash Screen（启动Logo）

#### 设计规范
- **时长**：1.5秒（可跳过，按任意键/点击跳过）
- **内容**：引擎Logo → 发行商Logo → 开发商Logo（可合并为一屏）
- **风格**：纯黑背景，Logo淡入淡出，无多余元素
- **Godot 设置**：`Project Settings → Application → Boot Splash`

```
┌─────────────────────────────────────────┐
│                                         │
│                                         │
│            [游戏Logo/工作室Logo]         │
│                                         │
│                                         │
│           按任意键跳过                   │
│                                         │
└─────────────────────────────────────────┘
```

### 2.3 加载界面（Loading Screen）

#### 视觉设计

```
┌───────────────────────────────────────────────────┐
│                                                    │
│              水墨山水动态背景（缓慢流动）             │
│                                                    │
│          ┌──────────────────────────┐              │
│          │   江 湖 梦 华             │  游戏标题    │
│          │   （书法字体，带墨迹晕染）  │              │
│          └──────────────────────────┘              │
│                                                    │
│     ┌──────────────────────────────────────┐      │
│     │  ▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░░░░░░░░░░░░░░  │ 进度条  │
│     └──────────────────────────────────────┘      │
│              加载中... 67%                           │
│                                                    │
│        「正在整理行囊，准备踏入江湖...」             │  随机提示语
│                                                    │
│                                    v0.5.0  Build 20250827 │
└───────────────────────────────────────────────────┘
```

#### 设计要点

| 元素 | 规范 |
|------|------|
| **背景** | 水墨山水动态图，云雾缓慢飘动，水面微光，循环播放 |
| **标题** | 游戏名书法字体，带墨迹晕染动画，加载完成时完全显现 |
| **进度条** | 横向，宽度60%屏幕，高度8px，墨色填充，无数字百分比在条内 |
| **进度文字** | 进度条下方，"加载中... XX%"，宋体/楷体 |
| **提示语** | 随机显示武侠风短句，每2-3秒切换一条，淡入淡出 |
| **版本号** | 右下角，小字，浅灰色 |
| **跳过** | 不可跳过（加载必须完成） |

#### 加载提示语示例

```
「正在整理行囊，准备踏入江湖...」
「山雨欲来，江湖路远...」
「磨刀霍霍，只待出鞘...」
「一卷江湖，半世浮沉...」
「青山不改，绿水长流...」
「桃李春风一杯酒，江湖夜雨十年灯...」
「人在江湖，身不由己...」
「侠之大者，为国为民...」
```

#### 节点结构

```
LoadingScreen (Control)
├── Background (TextureRect)              # 水墨背景
│   └── CloudLayer (TextureRect)          # 云雾层（缓慢移动）
├── TitleContainer (CenterContainer)
│   └── TitleLabel (Label)                # 游戏标题（书法字体）
├── ProgressContainer (VBoxContainer)
│   ├── ProgressBar (ProgressBar)         # 进度条
│   └── ProgressLabel (Label)             # 进度文字
├── TipLabel (Label)                       # 提示语
├── VersionLabel (Label)                   # 版本号
└── LoadingAnimation (AnimationPlayer)     # 标题墨迹动画
```

#### 核心脚本

```gdscript
# scenes/ui/screens/loading/LoadingScreen.gd
class_name LoadingScreen
extends Control

@onready var _progress_bar: ProgressBar = $ProgressContainer/ProgressBar
@onready var _progress_label: Label = $ProgressContainer/ProgressLabel
@onready var _tip_label: Label = $TipLabel
@onready var _title_label: Label = $TitleContainer/TitleLabel
@onready var _animation: AnimationPlayer = $LoadingAnimation

var _tips: Array[String] = []
var _tip_index: int = 0
var _tip_timer: float = 0.0
const TIP_INTERVAL: float = 2.5

func _ready() -> void:
    _load_tips()
    _progress_bar.value = 0
    _animation.play("title_in")
    EventBus.bootstrap_progress.connect(_on_progress)
    EventBus.bootstrap_completed.connect(_on_complete)

func _process(delta: float) -> void:
    _tip_timer += delta
    if _tip_timer >= TIP_INTERVAL:
        _tip_timer = 0.0
        _next_tip()

func _on_progress(current: int, total: int, message: String) -> void:
    var percent: float = float(current) / float(total) * 100.0
    _progress_bar.value = percent
    _progress_label.text = "加载中... %d%%" % int(percent)

func _on_complete() -> void:
    _progress_bar.value = 100
    _progress_label.text = "加载完成"
    _tip_label.text = "「点击进入江湖」"
    # 等待用户点击
    gui_input.connect(_on_click)

func _on_click(event: InputEvent) -> void:
    if event is InputEventMouseButton and event.pressed:
        _fade_out_and_enter()

func _fade_out_and_enter() -> void:
    var tween := create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.8)
    tween.tween_callback(_enter_main_menu)

func _enter_main_menu() -> void:
    UIManager.close_screen(self)
    UIManager.open_screen("MainMenu")

func _load_tips() -> void:
    _tips = [
        tr("loading_tip_01"),
        tr("loading_tip_02"),
        tr("loading_tip_03"),
        # ...
    ]
    _tip_label.text = _tips[0]

func _next_tip() -> void:
    _tip_index = (_tip_index + 1) % _tips.size()
    # 淡入淡出
    var tween := create_tween()
    tween.tween_property(_tip_label, "modulate:a", 0.0, 0.5)
    tween.tween_callback(func(): _tip_label.text = _tips[_tip_index])
    tween.tween_property(_tip_label, "modulate:a", 1.0, 0.5)
```

---

## 三、主菜单界面（Main Menu）

### 3.1 视觉设计

```
┌───────────────────────────────────────────────────────────┐
│   动态背景：水墨江湖场景（远山/孤舟/飘雪/落叶，缓慢循环）    │
│              ┌──────────────────────┐                     │
│              │    江 湖 梦 华        │  游戏标题（书法）    │
│              └──────────────────────┘                     │
│       ┌─────────────────┐                                │
│       │  开始新的旅程     │  ← 主菜单选项                 │
│       │  继续江湖路       │                                │
│       │  读取旧梦         │                                │
│       │  游戏设置         │                                │
│       │  江湖图鉴         │                                │
│       │  退出江湖         │                                │
│       └─────────────────┘                                │
│   左下角：版本号 / 制作组名单                              │
│   右下角：[设置图标] [音量图标] [语言图标]                 │
└───────────────────────────────────────────────────────────┘
```

### 3.2 主菜单选项规范

| 选项 | 功能 | 快捷键 | 说明 |
|------|------|--------|------|
| **开始新的旅程** | 新游戏 | N / Enter | 无存档时高亮，有存档时显示"确定要重新开始？"确认 |
| **继续江湖路** | 快速加载最新存档 | C | 有存档时显示，无存档时灰显 |
| **读取旧梦** | 存档选择界面 | L | 进入存档列表 |
| **游戏设置** | 设置界面 | O / Esc | 音频/画面/控制/语言 |
| **江湖图鉴** | 收集/成就/设定集 | G | 已收集内容查看（二周目/通关后解锁更多） |
| **退出江湖** | 退出游戏 | Q / Alt+F4 | 确认弹窗后退出 |

### 3.3 交互设计

#### 选项悬停效果
- 鼠标悬停：文字颜色从灰白变为金色，左侧出现一个小箭头「▶」，文字轻微右移2px
- 选中音效：轻柔的古琴拨弦音
- 不可选选项：灰色，无悬停效果，点击无反应

#### 选项点击效果
- 点击：文字闪烁一下，播放确认音效
- 进入子界面：当前菜单向左滑出，新界面从右滑入（或淡入淡出）
- 退出游戏：弹出确认框

#### 键盘导航
- ↑/↓：上下移动选择
- Enter/Space：确认
- Esc：返回上一级（主菜单按Esc弹出退出确认）
- 快捷键：直接触发对应选项

### 3.4 动态背景设计

| 元素 | 动画 | 时长 |
|------|------|------|
| 远山 | 缓慢平移（视差），颜色极淡 | 60秒循环 |
| 云雾 | 从左向右缓慢飘动，透明度变化 | 30秒循环 |
| 水面 | 微光闪烁，波纹动画 | 5秒循环 |
| 落叶/飘雪 | 随机从上方飘落 | 持续 |
| 孤舟 | 水面上轻微摇晃，缓慢移动 | 20秒循环 |
| 月光/阳光 | 从云层中透出，光柱缓慢移动 | 15秒循环 |

> 背景使用 Godot 的 `TextureRect` + `AnimationPlayer` 或 `Shader` 实现，确保低性能消耗。

### 3.5 节点结构

```
MainMenu (Control)
├── Background (Control)
│   ├── FarMountains (TextureRect)
│   ├── MidMountains (TextureRect)
│   ├── CloudLayer1 (TextureRect)
│   ├── CloudLayer2 (TextureRect)
│   ├── Water (TextureRect)
│   ├── Boat (TextureRect)
│   ├── FallingLeaves (CPUParticles2D)
│   └── LightShaft (TextureRect)
├── TitleContainer (CenterContainer)
│   └── TitleLabel (Label)
├── MenuContainer (VBoxContainer)
│   ├── MenuItem_0 (MenuItem)
│   ├── MenuItem_1 (MenuItem)
│   ├── MenuItem_2 (MenuItem)
│   ├── MenuItem_3 (MenuItem)
│   ├── MenuItem_4 (MenuItem)
│   └── MenuItem_5 (MenuItem)
├── BottomLeft (HBoxContainer)
│   ├── VersionLabel (Label)
│   └── CreditsLabel (Label)
├── BottomRight (HBoxContainer)
│   ├── SettingsButton (Button)
│   ├── VolumeButton (Button)
│   └── LanguageButton (Button)
├── MenuAnimation (AnimationPlayer)
└── BackgroundMusic (AudioStreamPlayer)
```

### 3.6 菜单项组件（MenuItem）

```gdscript
# scenes/ui/components/menu_item/MenuItem.gd
class_name MenuItem
extends Control

signal selected()
signal confirmed()

@export var text: String = ""
@export var shortcut_key: String = ""

@onready var _label: Label = $Label
@onready var _arrow: Label = $Arrow
@onready var _hover_sound: AudioStreamPlayer = $HoverSound
@onready var _confirm_sound: AudioStreamPlayer = $ConfirmSound

var _is_selected: bool = false
var _is_enabled: bool = true

func _ready() -> void:
    _label.text = text
    _arrow.visible = false
    mouse_filter = Control.MOUSE_FILTER_STOP

func set_selected(selected: bool) -> void:
    _is_selected = selected
    _arrow.visible = selected
    if selected:
        _label.add_theme_color_override("font_color", Color(0.85, 0.75, 0.4))
        _label.position.x = 8
    else:
        _label.remove_theme_color_override("font_color")
        _label.position.x = 0

func set_enabled(enabled: bool) -> void:
    _is_enabled = enabled
    if enabled:
        _label.modulate = Color.WHITE
    else:
        _label.modulate = Color(0.5, 0.5, 0.5, 0.6)

func _gui_input(event: InputEvent) -> void:
    if not _is_enabled:
        return
    if event is InputEventMouseMotion:
        if not _is_selected:
            set_selected(true)
            selected.emit()
            _hover_sound.play()
    elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
        _confirm()

func confirm() -> void:
    if not _is_enabled:
        return
    _confirm_sound.play()
    confirmed.emit()

func _confirm() -> void:
    confirm()
```

### 3.7 主菜单核心脚本

```gdscript
# scenes/ui/screens/main_menu/MainMenu.gd
class_name MainMenu
extends Control

@onready var _menu_items: Array[MenuItem] = [
    $MenuContainer/MenuItem_0,
    $MenuContainer/MenuItem_1,
    $MenuContainer/MenuItem_2,
    $MenuContainer/MenuItem_3,
    $MenuContainer/MenuItem_4,
    $MenuContainer/MenuItem_5,
]
@onready var _animation: AnimationPlayer = $MenuAnimation
@onready var _bgm: AudioStreamPlayer = $BackgroundMusic

var _selected_index: int = 0
var _has_save: bool = false

func _ready() -> void:
    _setup_menu_items()
    _check_saves()
    _play_enter_animation()
    _bgm.play()
    Input.set_default_cursor_shape(Input.CURSOR_SHAPE_ARROW)

func _setup_menu_items() -> void:
    for i in _menu_items.size():
        _menu_items[i].selected.connect(_on_item_selected.bind(i))
        _menu_items[i].confirmed.connect(_on_item_confirmed.bind(i))

func _check_saves() -> void:
    _has_save = SaveManager.has_any_save()
    _menu_items[1].set_enabled(_has_save)
    if not _has_save:
        _selected_index = 0
    else:
        _selected_index = 1
    _update_selection()

func _play_enter_animation() -> void:
    _animation.play("main_menu_in")

func _update_selection() -> void:
    for i in _menu_items.size():
        _menu_items[i].set_selected(i == _selected_index)

func _on_item_selected(index: int) -> void:
    _selected_index = index
    _update_selection()

func _on_item_confirmed(index: int) -> void:
    match index:
        0: _new_game()
        1: _continue_game()
        2: _load_game()
        3: _open_settings()
        4: _open_archive()
        5: _quit_game()

func _new_game() -> void:
    if _has_save:
        _show_confirm_dialog(
            "确定要开始新的旅程吗？当前进度将不会丢失，但会开始新的存档。",
            _confirm_new_game
        )
    else:
        _confirm_new_game()

func _confirm_new_game() -> void:
    _fade_out()
    await get_tree().create_timer(0.8).timeout
    UIManager.close_screen(self)
    GameManager.start_new_game()

func _continue_game() -> void:
    var latest_slot: int = SaveManager.get_latest_save_slot()
    if latest_slot == -1:
        return
    _fade_out()
    await get_tree().create_timer(0.8).timeout
    UIManager.close_screen(self)
    GameManager.load_game(latest_slot)

func _load_game() -> void:
    UIManager.open_screen("SaveLoadScreen")

func _open_settings() -> void:
    UIManager.open_screen("SettingsScreen")

func _open_archive() -> void:
    UIManager.open_screen("ArchiveScreen")

func _quit_game() -> void:
    _show_confirm_dialog("确定要退出江湖吗？", _confirm_quit)

func _confirm_quit() -> void:
    get_tree().quit()

func _show_confirm_dialog(message: String, confirm_callback: Callable) -> void:
    var dialog: ConfirmDialog = UIManager.show_popup("ConfirmDialog")
    dialog.setup(message, confirm_callback)

func _fade_out() -> void:
    var tween := create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.8)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_up"):
        _move_selection(-1)
    elif event.is_action_pressed("ui_down"):
        _move_selection(1)
    elif event.is_action_pressed("ui_accept"):
        _menu_items[_selected_index].confirm()
    elif event.is_action_pressed("ui_cancel"):
        _quit_game()

func _move_selection(direction: int) -> void:
    var new_index: int = _selected_index
    for i in _menu_items.size():
        new_index = wrapi(new_index + direction, 0, _menu_items.size())
        if _menu_items[new_index]._is_enabled:
            break
    _selected_index = new_index
    _update_selection()
    _menu_items[_selected_index]._hover_sound.play()
```

---

## 四、存档选择界面（Save/Load Screen）

### 4.1 视觉设计

```
┌───────────────────────────────────────────────────────────┐
│  ← 返回                          读 取 旧 梦                │
├───────────────────────────────────────────────────────────┤
│  ┌─────────────────────────────────────────────────────┐  │
│  │  [缩略图]  存档1                                      │  │
│  │            令狐冲  Lv.15  华山派                      │  │
│  │            游戏时间：03:25:41                          │  │
│  │            保存时间：2025-08-27 14:32                  │  │
│  │            所在场景：华山派 · 思过崖                    │  │
│  │                                             [读取] [删除]│  │
│  └─────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  [缩略图]  存档2                                      │  │
│  │            令狐冲  Lv.22  无门无派                     │  │
│  │            游戏时间：12:08:15                          │  │
│  │            保存时间：2025-08-26 22:15                  │  │
│  │            所在场景：洛阳城 · 酒馆                       │  │
│  │                                             [读取] [删除]│  │
│  └─────────────────────────────────────────────────────┘  │
│  ┌─────────────────────────────────────────────────────┐  │
│  │  [空槽位]  存档3                                      │  │
│  │            —— 空 ——                                    │  │
│  │                                             [新的旅程]  │  │
│  └─────────────────────────────────────────────────────┘  │
│                    自动存档：[槽位]                         │
└───────────────────────────────────────────────────────────┘
```

### 4.2 存档卡片设计

| 元素 | 说明 |
|------|------|
| **缩略图** | 保存时的游戏截图，320x180，左上角 |
| **存档编号** | 存档1/存档2... 或自动存档 |
| **角色名** | 玩家角色名 |
| **等级** | Lv.XX |
| **门派** | 当前门派（无门无派则显示） |
| **游戏时间** | 总游玩时长 HH:MM:SS |
| **保存时间** | 实际保存日期时间 |
| **所在场景** | 保存时所在场景名称 |
| **操作按钮** | 读取 / 删除（空槽位显示"新的旅程"） |

### 4.3 交互设计

- **读取**：点击后弹出确认"确定读取此存档？当前进度将丢失"
- **删除**：点击后弹出确认"确定删除此存档？此操作不可撤销"，删除后卡片变为空槽位
- **新的旅程**：空槽位点击，开始新游戏并存入此槽位
- **键盘导航**：↑/↓切换存档，Enter读取，Delete删除
- **悬停**：卡片边框高亮金色，轻微放大1.02倍

### 4.4 自动存档区

- 单独区域在手动存档下方
- 显示最近3个自动存档
- 自动存档卡片标注「自动」标签
- 自动存档不可手动删除（被新自动存档覆盖）

### 4.5 节点结构

```
SaveLoadScreen (Control)
├── Header (HBoxContainer)
│   ├── BackButton (Button)
│   └── TitleLabel (Label)
├── SaveList (ScrollContainer)
│   └── SaveContainer (VBoxContainer)
│       ├── SaveCard_0 (SaveCard)
│       ├── SaveCard_1 (SaveCard)
│       ├── SaveCard_2 (SaveCard)
│       └── ...
├── AutoSaveLabel (Label)
├── AutoSaveList (HBoxContainer)
│   ├── AutoSaveCard_0
│   ├── AutoSaveCard_1
│   └── AutoSaveCard_2
└── EnterAnimation (AnimationPlayer)
```

### 4.6 存档卡片组件

```gdscript
# scenes/ui/components/save_card/SaveCard.gd
class_name SaveCard
extends Control

signal load_requested(slot_index: int)
signal delete_requested(slot_index: int)
signal new_game_requested(slot_index: int)

@export var slot_index: int = 0

@onready var _thumbnail: TextureRect = $Thumbnail
@onready var _save_number: Label = $Info/SaveNumber
@onready var _char_name: Label = $Info/CharName
@onready var _level: Label = $Info/Level
@onready var _faction: Label = $Info/Faction
@onready var _playtime: Label = $Info/Playtime
@onready var _savetime: Label = $Info/Savetime
@onready var _scene: Label = $Info/Scene
@onready var _load_button: Button = $Actions/LoadButton
@onready var _delete_button: Button = $Actions/DeleteButton
@onready var _new_game_button: Button = $Actions/NewGameButton
@onready var _empty_overlay: Control = $EmptyOverlay
@onready var _auto_tag: Label = $AutoTag

var _save_info: SaveInfo = null

func setup(info: SaveInfo) -> void:
    _save_info = info
    if info == null:
        _show_empty()
    else:
        _show_info(info)

func _show_empty() -> void:
    _empty_overlay.visible = true
    _load_button.visible = false
    _delete_button.visible = false
    _new_game_button.visible = true
    # ...
```

---

## 五、设置界面（Settings Screen）

### 5.1 视觉设计

```
┌───────────────────────────────────────────────────────────┐
│  ← 返回                          游 戏 设 置                │
├──────────┬────────────────────────────────────────────────┤
│  音频设置 │  [音频] [画面] [控制] [游戏] [语言]            │
│  画面设置 │────────────────────────────────────────────────│
│  控制设置 │  主音量        ──●──────────  80%             │
│  游戏设置 │  背景音乐      ──●──────────  60%             │
│  语言设置 │  音效          ────●────────  70%             │
│          │  语音          ──────●──────  100%             │
│          │  [测试音频]                                     │
└──────────┴────────────────────────────────────────────────┘
```

### 5.2 设置分类与内容（摘要）

- **音频**：主音量/背景音乐/音效/语音/环境音 滑块 + 音频测试
- **画面**：分辨率/显示模式/画面质量/垂直同步/帧率限制/抗锯齿/阴影/纹理/特效/亮度/对比度
- **控制**：按键绑定（列表+重绑定）/鼠标灵敏度/手柄灵敏度/震动/自动瞄准/输入模式
- **游戏**：难度/自动存档+频率/小地图/任务指引/伤害数字/屏幕震动/血腥/对话自动播放/文字速度
- **语言**：简中/繁中/English

### 5.3 交互设计

- 左侧分类点击切换右侧内容，当前高亮金色
- 滑块拖动实时生效；下拉点击展开；开关点击切换带动画
- 按键绑定：点击进入绑定状态，按新键完成，Esc取消
- 每个分类底部"恢复默认"；修改自动保存；Esc/返回按钮退出

### 5.4 节点结构

```
SettingsScreen (Control)
├── Header (HBoxContainer)
│   ├── BackButton (Button)
│   └── TitleLabel (Label)
├── Content (HBoxContainer)
│   ├── CategoryList (VBoxContainer)
│   │   ├── CategoryButton_0..4
│   └── SettingsPanel (ScrollContainer)
│       └── PanelContainer → VBoxContainer（动态生成）
└── EnterAnimation (AnimationPlayer)
```

---

## 六、确认弹窗（Confirm Dialog）

### 6.1 视觉设计

```
┌─────────────────────────────────────┐
│         确 定 要 退 出 江 湖 吗 ？    │
│     未保存的进度将会丢失。           │
│     ┌─────────┐ ┌─────────┐        │
│     │  确 定   │ │  取 消   │        │
│     └─────────┘ └─────────┘        │
└─────────────────────────────────────┘
```

### 6.2 设计规范

| 元素 | 规范 |
|------|------|
| 背景遮罩 | 半透明黑色（alpha 0.6），点击遮罩不关闭 |
| 弹窗 | 居中，宽度400-600px，木质/宣纸边框风格 |
| 标题 | 居中，书法字体，金色，字号24 |
| 内容 | 居中，宋体，白色，字号16，支持多行 |
| 按钮 | 并排，确定左/取消右，确定默认聚焦 |
| 动画 | 弹窗从中心缩放出现（0.3s），关闭时淡出 |

### 6.3 核心脚本

```gdscript
# scenes/ui/components/confirm_dialog/ConfirmDialog.gd
class_name ConfirmDialog
extends Control

signal confirmed()
signal cancelled()

@onready var _title_label: Label = $Panel/TitleLabel
@onready var _content_label: Label = $Panel/ContentLabel
@onready var _confirm_button: Button = $Panel/ButtonContainer/ConfirmButton
@onready var _cancel_button: Button = $Panel/ButtonContainer/CancelButton
@onready var _animation: AnimationPlayer = $Animation

var _confirm_callback: Callable = Callable()
var _cancel_callback: Callable = Callable()

func setup(title: String, content: String, confirm_callback: Callable = Callable(), cancel_callback: Callable = Callable(), confirm_text: String = "确定", cancel_text: String = "取消") -> void:
    _title_label.text = title
    _content_label.text = content
    _confirm_button.text = confirm_text
    _cancel_button.text = cancel_text
    _confirm_callback = confirm_callback
    _cancel_callback = cancel_callback
    _animation.play("dialog_in")
    _confirm_button.grab_focus()

func _ready() -> void:
    _confirm_button.pressed.connect(_on_confirm)
    _cancel_button.pressed.connect(_on_cancel)

func _on_confirm() -> void:
    if _confirm_callback.is_valid():
        _confirm_callback.call()
    confirmed.emit()
    _close()

func _on_cancel() -> void:
    if _cancel_callback.is_valid():
        _cancel_callback.call()
    cancelled.emit()
    _close()

func _close() -> void:
    var tween := create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.2)
    tween.tween_callback(queue_free)

func _unhandled_input(event: InputEvent) -> void:
    if event.is_action_pressed("ui_accept"):
        _on_confirm()
    elif event.is_action_pressed("ui_cancel"):
        _on_cancel()
```

---

## 七、转场界面（Transition）

### 7.1 转场类型

| 转场类型 | 使用场景 | 动画 | 时长 |
|---------|---------|------|------|
| **水墨淡入淡出** | 主菜单↔游戏、场景切换 | 水墨晕染覆盖→清除 | 1.0s |
| **黑屏淡入淡出** | 死亡/重生、剧情跳转 | 纯黑渐变 | 0.8s |
| **卷轴展开** | 进入文档/图鉴/信件 | 竖卷轴从上向下展开 | 0.6s |
| **书页翻动** | 任务日志/图鉴翻页 | 3D书页翻转 | 0.4s |
| **剑气划过** | 战斗开始/结束 | 一道剑气从左划到右 | 0.3s |
| **云雾弥漫** | 进入秘境/特殊区域 | 云雾聚集→消散 | 1.2s |

### 7.2 水墨淡入淡出设计

```
阶段1（0-0.5s）：水墨从四周向中心晕染，逐渐覆盖全屏
阶段2（0.5-0.6s）：完全水墨覆盖，切换场景/数据
阶段3（0.6-1.1s）：水墨从中心向四周消散，露出新场景
```

使用 Godot Shader 实现水墨晕染效果，或使用预渲染的水墨纹理序列帧。

### 7.3 转场管理器

```gdscript
# services/ui/transition_manager.gd
class_name TransitionManager
extends Node

var _current_transition: Control = null
var _is_transitioning: bool = false

func transition_to(transition_type: int, callback: Callable = Callable()) -> void:
    if _is_transitioning:
        return
    _is_transitioning = true
    var scene: PackedScene = _get_transition_scene(transition_type)
    _current_transition = scene.instantiate()
    UIManager.get_layer(UIManager.Layer.TRANSITION).add_child(_current_transition)
    _current_transition.play_in()
    await _current_transition.transition_midpoint
    if callback.is_valid():
        callback.call()
    _current_transition.play_out()
    await _current_transition.transition_finished
    _current_transition.queue_free()
    _current_transition = null
    _is_transitioning = false

func is_transitioning() -> bool:
    return _is_transitioning
```

---

## 八、主题与风格规范

### 8.1 色彩规范

| 用途 | 颜色 | 色值 |
|------|------|------|
| 主背景 | 深墨色 | #1A1612 |
| 面板背景 | 深棕/宣纸色 | #2B2420 / #E8DCC8 |
| 主文字 | 米白 | #F0E6D2 |
| 次要文字 | 灰白 | #A89B8C |
| 高亮/选中 | 金色 | #D4AF37 / #C9A961 |
| 可交互 | 暖白 | #E8DCC8 |
| 不可交互 | 灰色 | #6B5D52 |
| 危险/删除 | 暗红 | #8B3A3A |
| 成功/确认 | 墨绿 | #4A6741 |
| 进度条填充 | 墨色渐变 | #3D342B → #1A1612 |

### 8.2 字体规范

| 用途 | 字体 | 字号 |
|------|------|------|
| 游戏标题 | 书法字体 | 48-72 |
| 界面标题 | 楷体/宋体 | 28-32 |
| 菜单选项 | 楷体 | 22-24 |
| 正文内容 | 宋体 | 16-18 |
| 提示/说明 | 宋体 | 14 |
| 数字/英文 | 等宽字体 | 14-16 |

### 8.3 UI 元素风格

| 元素 | 风格 |
|------|------|
| 按钮 | 木质边框/宣纸底，悬停时金色描边，按下时轻微凹陷 |
| 面板 | 宣纸纹理+木质边框，四角有装饰纹样 |
| 进度条 | 水墨填充，无光泽，边缘有毛笔晕染感 |
| 滑块 | 木质滑轨+玉石/铜质滑块 |
| 下拉框 | 宣纸底+木质边框，展开时有淡入动画 |
| 开关 | 铜质开关，滑动动画 |
| 滚动条 | 细窄墨色，滑块为木质 |
| 分隔线 | 细金线或墨色虚线 |

### 8.4 动画规范

| 动画 | 时长 | 缓动 |
|------|------|------|
| 界面入场 | 0.4-0.6s | Ease Out |
| 界面退场 | 0.3-0.4s | Ease In |
| 按钮悬停 | 0.15s | Ease Out |
| 按钮按下 | 0.08s | Ease In |
| 弹窗出现 | 0.3s | Back Out |
| 弹窗消失 | 0.2s | Ease In |
| 转场 | 0.8-1.2s | 自定义 |
| 文字淡入 | 0.3s | Ease Out |
| 进度条变化 | 0.2s | Ease Out |

---

## 九、性能要求

| 指标 | 要求 |
|------|------|
| 主菜单帧率 | 稳定60fps（最低30fps） |
| 主菜单内存 | < 200MB（含背景动画） |
| 加载界面加载时间 | < 5秒（SSD），< 10秒（HDD） |
| 界面切换响应 | < 100ms |
| 弹窗出现延迟 | < 50ms |
| 转场黑屏时间 | < 200ms（水墨转场无纯黑） |
| 存档列表加载 | < 500ms（10个存档+缩略图） |
| 设置项响应 | 实时生效 |
| 背景动画CPU占用 | < 5% |
| 背景动画GPU占用 | < 10% |

---

## 十、多分辨率适配

| 分辨率 | 适配策略 |
|--------|---------|
| 1920x1080（16:9） | 基准设计分辨率 |
| 2560x1440（16:9） | 等比放大 |
| 3840x2160（16:9） | 4K资源 |
| 1280x720（16:9） | 等比缩小 |
| 16:10（1920x1200） | 上下增加背景填充 |
| 21:9（2560x1080） | 左右增加背景填充 |
| 4:3（1024x768） | 等比缩放，左右裁剪背景 |

**Godot 设置**：Stretch Mode `canvas_items`；Stretch Aspect `keep`；设计分辨率 1920x1080。

---

## 十一、无障碍与本地化

### 11.1 无障碍
- 所有可交互元素支持键盘操作
- 文字最小字号不低于14px（正文），标题不低于20px
- 颜色对比度符合 WCAG AA（4.5:1）
- 重要信息不依赖颜色单独传达
- 支持屏幕阅读器（Godot Accessibility 插件）
- 字幕/文字描述可调节大小
- 手柄操作时所有功能可通过手柄完成

### 11.2 本地化
- 所有文字通过 `tr()`，禁止硬编码
- 翻译文件使用 CSV，支持简中/繁中/英文
- UI 布局支持文字膨胀（英文比中文长30%）
- 字体支持多语言字符集
- 日期/时间格式按语言区域调整

---

## 十二、规划程度

| 阶段 | 内容 | 周期 |
|------|------|------|
| M1 | UI框架（UIManager/层级/主题）、加载界面、Splash | 1周 |
| M2 | 主菜单界面（含动态背景/菜单交互/动画） | 1.5周 |
| M3 | 存档选择界面（存档卡片/读取/删除/新游戏） | 1周 |
| M4 | 设置界面（音频/画面/控制/游戏/语言，含按键绑定） | 1.5周 |
| M5 | 确认弹窗/通知提示/Tooltip/转场系统 | 1周 |
| M6 | 多分辨率适配/无障碍/本地化/性能优化 | 1周 |
