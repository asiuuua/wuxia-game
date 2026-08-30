# UI 架构评审 · 自定义 UI 方法论对照

> 评审对象：用户贴出的《游戏自定义 UI：控件、自定义外观底层逻辑（Godot 举例……）》长文
> 评审视角：程序员 / 项目经理 / 架构师 / 前端 / 运维
> 评审基准：本工程 `D:\武侠游戏` 现有 UI 真实代码（`scenes/ui/**`、`autoload/ui_manager.gd`、`resources/themes/ui_theme.tres`）
> 结论先行：**你早已落地了那段文字的「方案1 + 方案2」内核，差只差在「用 .tscn 还是纯代码 .gd」这一层皮。不要回炉重写成 .tscn。**

---

## 0. 一句话结论

| 维度 | 结论 |
|---|---|
| 那段文字「概念」可落地性 | **高** —— 你当前结构本就是它的实现体 |
| 那段文字「按字面照搬（.tscn + 透明 Button）」可落地性 | **低** —— 等于推翻现有 UI 构建范式，ROI 为负 |
| 你与文字的差异点 | ① 控件用 `.gd` 代码构建，不用 `.tscn` 存场景；② 交互是「真实 Button + 自写 `_gui_input`」混合，不是「永远透明 Button」；③ 主题你用 `.theme` 资源（方案1），文字只把它当可选项 |
| 最大隐患 | 纯代码 UI 无可视化编辑器，布局靠手算像素偏移；尺寸/间距未进 `UIPalette`，改分辨率要逐文件改 |
| 应立即做的 | 把「重复 StyleBoxFlat」抽成工厂；把「控件尺寸/间距」也收进统一常量；给美术一个「只改一处皮肤」的入口 |

---

## 1. 你当前的 UI 控件清单（按位置盘点）

### 1.1 全局装配层（autoload）
- `UIManager`（`autoload/ui_manager.gd`）：6 个 `CanvasLayer`（BACKGROUND=0 / HUD=50 / TRANSITION=100 / FULLSCREEN=200 / POPUP=300 / TOOLTIP=400 / SYSTEM_OVERLAY=500）+ 界面栈 + 缓存弹窗 + 安全区 + Toast 对象池。
- 关键事实：**所有全屏界面都是 `script.new()` 实例化 `.gd` 脚本，不依赖 `.tscn`**（注释明写「对齐本项目代码构建 Control 覆盖层的惯例」）。`screens.json` 里 21 个界面全是脚本路径。

### 1.2 进入游戏后的常驻 HUD（Layer 5，挂在 `Hud.tscn` 根 + 4 个面板脚本）
| 面板 | 实际控件 | 交互 |
|---|---|---|
| `StatusCardPanel`（左上状态卡） | `Panel`(玻璃底) + `TextureRect`(头像) + `Label`×N + 内部类 `_Bar`（`Panel`轨道 + `ColorRect`填充） | 纯展示，`focus_mode=NONE` |
| `TopRightMenuPanel`（右上） | 2 个真实 `Button`（姻缘/菜单，由 `ui_theme.tres` 上国风皮肤）+ `Label` 红点徽标 | `Button.pressed` |
| `QuestTrackPanel`（任务追踪，可拖动） | `Panel`(玻璃) + `ScrollContainer` + `VBoxContainer` + `Label`×N | 自写 `_gui_input`（拖拽+滚轮），落点持久化 `user://ui/hud_positions.json` |
| `SkillBarPanel`（底部技能栏） | 6 个内部类 `_Slot`（`Control` + `TextureRect`图标 + `Label`×2） | 纯展示，冷却读秒 |

### 1.3 战斗常驻（TacticalBattleScene，自绘四角 HUD，**不挂全局 HUD**）
- 真实 `Button`：加速/跳过/自动/返回/各行动按钮（`mouse_filter=STOP` 拦截点击）。
- `Label`×N（玩家/目标名、HP/MP、状态、提示）+ `Panel`(结算框) + `HBoxContainer`(行动条)。
- 战场视觉：`BattleGridNode`（程序化等轴测菱形 + 蓝绿红高亮）、`BattleEntity`（精灵 + `Tween` 移动 + `ColorRect` 血条 + 飘字）。

### 1.4 全屏/弹窗界面（约 20 个，全部 `.gd` 代码构建）
- 通用基建：`BaseScreen`（铺满 + 安全区 + 键盘导航 + 返回守卫 + 压暗底）、`PopupBase`、`ConfirmDialog`、`Tooltip`、`UIFeedback`(悬停缩放+音效)、`UICenterUtils`。
- 复用复合控件（方案2 实质）：`ItemSlot`（背包格：`Control` + `Panel` + `TextureRect` + `Label`×2 + 拖拽/放下）、`MenuItem`（菜单项：`Control` + `Label` + 可选 `TextureRect` + 自写 `_gui_input` 导航）。
- 容器与皮肤：`HBox/VBox/Grid/Margin/ScrollContainer`、`Panel`、`ColorRect`、`StyleBoxFlat`（毛玻璃/圆角/阴影）、`Label`、`TextureRect`（图标全部走 `UIManager.get_icon` → `IconRegistry`）。

### 1.5 主题与图标系统（你做对的硬核部分）
- `resources/themes/ui_theme.tres` —— 项目级 `.theme` 资源，**已对 `Button/Panel/Label/LineEdit/ProgressBar/...` 全量定义国风皮肤**（棕底金边、思源宋体）。这正是文字里的「方案1 Theme 覆写」，且比你预期更完整。
- `core/constants/ui_theme.gd`（`UIPalette` RefCounted）—— 所有颜色/字号/布局边距的单一真相源，禁止裸 `Color` 字面量。
- `scenes/ui/icon_registry.gd`（`IconRegistry`）—— 按 id 取纹理，美术只丢 `resources/icons/<分类>/<名>.<ext>` 即生效，**零代码接入**。正是文字里「美术零代码替换图标」的完美落地。

---

## 2. 你与那段方法论的「方案命中」对照

| 文字方案 | 文字主张 | 你的现状 | 命中 |
|---|---|---|---|
| **方案1** Theme 覆写 | 用 `.theme` 资源改内置控件贴图/颜色 | ✅ `ui_theme.tres` 已全量 skin Button/Panel/Label；另加 `UIPalette` 代码常量兜底 | **完整命中（更强）** |
| **方案2** 复合控件 | `Control` 根 + `TextureRect` + **透明 Button**，存 `.tscn` 复用 | ✅ 复合控件思想命中（`ItemSlot`/`MenuItem`/`_Bar`/`_Slot`）—— 但**用 `.gd` 类 `X.new()` 复用，不用 `.tscn`**；交互**混合真实 Button + 自写 `_gui_input`**，非永远透明 Button | **内核命中，外壳不同** |
| **方案3** `_draw()` | 继承 Control 手绘，极少用 | ✅ 你用 `ColorRect` 做血条/进度，没碰 `_draw()` | **一致（规避）** |

**结论**：那段文字是「Unity prefab / Godot .tscn 派」的方案2 说明书；你用的是「纯代码派」的方案2。两者**产物等价**，纯代码派在你的单人开发 + 数据驱动 + autoload 生命周期语境下反而更可控。

---

## 3. 五角色评判

### 3.1 程序员（落地 / 正确性 / 维护）
- **可落地性（概念）**：高。文字说的「图片只管长相、交互只管点击、两者分离」你已落实。
- **可落地性（字面照搬 .tscn + 透明 Button）**：低。要改 `UIManager.script.new()` 装配链 + 21 个 `screens.json` 条目 + 全部 `_build()`，回归面极大，且双闸门会变红。
- **已做对**：`IconRegistry` 接口、`UIPalette` 集中、Toast 对象池、缓存弹窗、安全区。
- **痛点**：布局全靠 `offset_left = -178.0` 这类手算像素；尺寸/间距未进 `UIPalette`；`StyleBoxFlat` 在多处重复 new（ItemSlot `_apply_bg`、StatusCard `_build_avatar`）。
- **建议**：抽 `UIStyle.make_panel(bg, border, radius)` 工厂；尺寸/间距也收常量。

### 3.2 项目经理（ROI / 范围 / 风险）
- **当规范文档看**：中——团队约定价值高。
- **当改造指令看**：低——纯代码→.tscn 是范式迁移，非增量，返工大、门禁风险高。
- **决策建议**：**吸收思想，不迁移实现**。把「复合控件 = `.gd` 类 + `new()`」「图标走 IconRegistry」「皮肤走 ui_theme.tres」定为团队铁律，写进《变更通告》。
- **风险点**：若某人照文字新建 `.tscn` 控件并 `preload`，会和现有 `script.new()` 体系形成**两套并行 UI 构建范式**，长期分裂。

### 3.3 架构师（分层 / 取舍 / 系统性）
- **架构已优于文字**：文字只讲「单控件怎么做」，没讲「界面栈/转场/缓存/安全区/对象池」——这些你已有 `UIManager` 6 层体系。
- **文字盲点**：未提「代码构建 vs 场景构建」的取舍、未提 autoload 生命周期、未提性能（对象池/飘字上限）、未提多语言、未提安卓安全区。你的实现补了这些。
- **隐患**：纯代码 UI 缺「可视化组建契约」，新控件无统一脚手架（BaseScreen 只覆盖全屏界面，HUD 面板各自为战）。
- **建议**：补一层「UI 控件工厂」：`UIWidgets.panel/button/icon_slot(...)`，所有面板统一从工厂取，杜绝散落的 `StyleBoxFlat.new()`。

### 3.4 前端 / UI（视觉一致性 / 美术协作 / 响应式）
- **对美术友好度**：文字的 `.tscn` + `@export` 拖拽 = 所见即所得，**比现状友好**。现状美术改布局得改代码（或只丢图标文件）。
- **已做对**：主题色板集中、图标接口干净、玻璃拟态/圆角/阴影到位、`ui_theme.tres` 统一 Button 皮肤（HUD 姻缘/菜单按钮不会变灰块）。
- **待改进**：
  1. 部分界面（ConfirmDialog/Settings/SaveLoad/MainMenu）**又手动 override Button 的 StyleBox**，与主题重复，且颜色可能和 `UIPalette` 漂移——应优先信任 `ui_theme.tres`，只在特殊态（如 MainMenu 透明按钮）才 override。
  2. 响应式靠手算像素 + 个别 `scale`（`StatusCard` `scale=0.667`）——极端分辨率可能溢出/错位。
- **建议**：纯展示/固定布局的控件可考虑改用 `.tscn`（混合模式可行），把美术从代码里解放；但交互复杂的（拖拽/键盘导航）保留代码派。

### 3.5 运维 / QA（稳定性 / 性能 / 回归）
- **已做对**：双闸门（GATE1 零错 + GATE2 零失败）、Toast 对象池防 GC、缓存弹窗防内存堆积、`_prune_invalid` 防幽灵节点、安全区防刘海切按钮。
- **隐患**：
  1. 纯代码 UI 出错难定位——没有场景树可视化，出 bug 只能靠日志/双闸门。
  2. 像素布局在超宽/折叠屏可能溢出（如 `_offset_left = -178.0` 假设固定宽度）。
  3. 手动 `_gui_input` 的 hover/press 态在多处自写，易出「点了没反应/拖不动」（QuestTrack 就曾因根 `size=0` 拖不动，已修）。
- **建议**：加 UI 截图冒烟（自动化 diff 关键界面）；尺寸抽常量便于统一改；保留 GATE2 覆盖控件刷新逻辑。

---

## 4. 优缺点对照表（文字方法论 vs 你现状）

| 项 | 文字主张（.tscn + 透明 Button） | 你现状（纯代码 .gd + 混合交互） | 谁更优 |
|---|---|---|---|
| 复用方式 | 存 `.tscn`，编辑器拖入复用 | `.gd` 类 `X.new()` 复用 | 各有场景；你更利于数据驱动 |
| 美术改 UI | 改 `.tscn` 即可，零代码 | 多需改 `.gd` | 文字优（对美术） |
| 交互统一性 | 透明 Button 自动 hover/press/焦点/手柄 | 真实 Button（自动）+ 自写 `_gui_input`（手动） | 文字更省事；但你为键盘导航/拖拽有意为之 |
| 主题皮肤 | `.theme` 资源（可选） | `.theme` 资源 + `UIPalette` 双保险 | 你优 |
| 图标接入 | 文字鼓励「美术丢图即生效」 | `IconRegistry` 已落地该理想 | 持平（你已做） |
| 可视化调试 | 编辑器场景树可见 | 无，靠日志/门禁 | 文字优 |
| 生命周期/转场/缓存 | 文字未提 | `UIManager` 6 层体系已解决 | 你优 |
| 多分辨率/安全区 | 文字未提 | 已处理 | 你优 |
| 入门门槛 | 低（所见即所得） | 高（要懂 GDScript 布局） | 文字优（对新手） |

---

## 5. 隐患清单（按严重度）

🔴 **P0（不改会持续痛）**
- H-1 布局靠手算像素偏移，无统一尺寸/间距常量 → 改分辨率/加控件要逐文件调。
- H-2 纯代码 UI 无可视化，新人或美术无法自助，且出错定位难。

🟠 **P1（一致性/技术债）**
- H-3 多处重复 `StyleBoxFlat.new()` + 手写圆角/边色，与 `UIPalette`/`ui_theme.tres` 可能漂移。
- H-4 部分界面手动 override Button 皮肤，绕过主题，长期双源。
- H-5 若有人照文字新建 `.tscn` 控件，会与 `script.new()` 体系形成两套并行范式。

🟡 **P2（健壮性）**
- H-6 个别 `scale` 形变（StatusCard）在极端 DPI 可能模糊/错位。
- H-7 手动 `_gui_input` 的 hover/press 在多控件复制，易出输入类 bug（需 GATE2 覆盖）。

---

## 6. 落地清单（可立即执行的行动项）

> 原则：**吸收思想、不迁范式**。以下全部可在现有纯代码体系内做，不碰 `.tscn` 化。

- [ ] **L1（P0）** 在 `ui_theme.gd` 或新增 `ui_layout.gd` 增加「控件尺寸/间距常量」（`SLOT_SIZE`、`HUD_PADDING`、`PANEL_RADIUS` 等），把 `_build()` 里的裸数字逐步替换。
- [ ] **L2（P1）** 新增 `scenes/ui/components/ui_style.gd`（或 `UIWidgets` 工厂）：`make_glass_panel()` / `make_button_skin()` / `make_icon_slot()` 统一构造 StyleBoxFlat，消除散落 new。
- [ ] **L3（P1）** 清理 ConfirmDialog/Settings/SaveLoad/MainMenu 里**重复的 Button StyleBox override**，默认信任 `ui_theme.tres`；仅 MainMenu 透明按钮等特例保留。
- [ ] **L4（P0/P2）** 给美术写一份《UI 接入手册》：图标丢 `resources/icons/<分类>/<名>`；颜色/字号改 `UIPalette`；皮肤改 `ui_theme.tres`；**不要新建 `.tscn` 控件**。
- [ ] **L5（架构）** 把「复合控件 = `.gd` 类 + `new()` 复用」「交互优先真实 Button、拖拽/键盘导航才自写 `_gui_input`」写入《变更通告·共享地基增量》，防止后续分裂。
- [ ] **L6（运维）** 加一条 UI 截图冒烟（关键界面启动后截一张，纳入 GATE 或独立定时任务），防像素布局在极端分辨率悄悄坏掉。
- [ ] **L7（可选·前端友好）** 对「纯展示、固定布局」的控件（如头像框、徽标）试点用 `.tscn` + `@export`，让美术可直接调——**仅作为混合模式的补充，不替换现有体系**。

---

## 7. 结论：要不要迁 .tscn？

**不要。** 你现有结构已经是那段文字的「方案1 + 方案2」生产级实现，只是把「存 .tscn」换成了「纯代码 `.gd` 构建」。迁移到 `.tscn` 是**范式级返工**，会冲击 `UIManager` 装配链、21 个 `screens.json`、`_build()` 体系，且对单人开发 + 数据驱动 + 门禁绿的现状**没有净收益**。

真正要补的，是文字没讲、但你已搭好骨架后该收口的两件事：
1. **把尺寸/间距/StyleBox 抽成统一工厂与常量**（治 H-1/H-3）；
2. **给美术一个「只改一处皮肤」的入口并立规矩**（治 H-2/H-4/H-5）。

做到这两点，你这套「纯代码派方案2」就比文字里的「.tscn 派方案2」更稳、更可控。
