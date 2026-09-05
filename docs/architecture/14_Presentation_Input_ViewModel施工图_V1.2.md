# 14 Presentation / Input / ViewModel 施工图 V1.2

> 状态：FROZEN（2026-09-06 用户批准；可依此实施）
> 真源：宪法 §31/§32/§92/§97/§100（PROJECT_CONSTITUTION_V1.2.md L1680-1692 / L2097-2107 / L4080-4104 / L4194-4207 / L4240-4251）、01 图 §31 Layer 06 Presentation（L681-689）
> 前序：02 Kernel（Command/Query 契约）· 03 Contract（S-6）· 04 测试（LN GATE 双命名空间）· 11 AB-4/AB-5 · 12 QD-2/QD-6 · 13 SV-5/SV-6
> 铁律：本文档只冻结契约与迁移映射，**批准前不写任何实现代码**（01§104 CONTRACT BEFORE IMPLEMENTATION）。

---

## 0. 编号命名空间声明

本图启用三个前缀，已对 01~13 图全量核对，**无撞号**：

| 前缀 | 含义 | 归属 |
|---|---|---|
| `PV-1 ~ PV-8` | 冻结契约（Presentation 域） | 本图 |
| `P-V1 ~ P-V12` | 实锤缺陷（机器实扫证据，含文件行号） | 本图 |
| `PV-R01 ~ PV-R12` | Enforcement 矩阵条目 | 本图 |

- 实锤编号 `P-V` 系列与 12 图 `P-Q`、13 图 `P-S` 同构不同域，无冲突。
- 13 图已声明接管 06 图局部 `SV-1~4`（见 13 图 §0）；本图不接管任何前序编号。
- 11 图开放问题 AB-4（core 层演出辅助归属）由本图 PV-3 承接裁决素材，**编号不转移**，裁决落点回写 11 图。

---

## 1. 定位

表现层是「玩家摸得到的一切」：输入、UI、场景、动画、相机、音频触发、导航、视觉反馈、ViewModel（01 图 §31 全词）。

宪法给表现层立了两条流水线，本图全部契约都是这两条线的落地：

```
读（状态上屏）：  Query → ViewModel → UI
写（输入下注）：  Input → Command → Application（§92：Player/AI/Editor/Automation 四源归一）
```

一条禁令贯穿到底：**禁止 `Button → player.gold -= 100`**（01 §31 原文）。表现层不拥有业务状态（宪法 L2099），ViewModel 是「UI-local transient display state」（L2097），业务判定禁依赖表现层数据（11 图 AB-5 大世界读秒同款原则）。

**本项目的现实**：表现层是全工程**纪律最好的域**——scenes/ui 全域零直接数值写入（本图实测基线）、7 层 CanvasLayer 收口、IconRegistry 依赖反转是全项目唯一完成的方向反转治理、UIFeedback/hud_layout 全表驱动。但它有三块欠账：**ViewModel 整体缺失**（UI 直读 autoload 状态约 230 处）、**输入链未 Command 化**（UI 直连 GameManager 流程 + 直引 Service）、**键位/音量双真源**。本图任务 = 把纪律固化成机器门禁，把欠账排进绞杀者序列，不推翻任何现有资产。

---

## 2. 现状盘点（实扫 2026-09-05）

### 2.1 已有资产（§171 收编，升级不丢弃）

| # | 资产 | 位置 | 规模 | 收编说明 |
|---|---|---|---|---|
| 1 | UIManager 屏幕编排 | `autoload/ui_manager.gd` | 461 行 | 7 层 CanvasLayer 枚举（值显式固定）；.tscn-only B 路线；cache 弹窗模式；`popup_close_requested` 收口（弹窗不自毁）；BUG-02 防重复打开；Toast 对象池；`close_all_screens()`；安全区 `apply_safe_area`（安卓） |
| 2 | IconRegistry 依赖反转 | `scenes/ui/icon_registry.gd` + EventBus L165 | 60+ 行 | **全项目唯一完成的方向反转治理**：基础层不 preload 上层，UI 层经 EventBus 注入 Callable；美术零代码（5 扩展名探测 + 品红棋盘占位永不 null） |
| 3 | BaseScreen 编排基类 | `scenes/ui/components/base_screen/BaseScreen.gd` | 155 行 | 铺满+安全区/压暗底/键盘导航/顶层守卫/返回处理五件套；`call_deferred` 修复「首下点击被吞」Godot 已知行为 |
| 4 | HudDraggablePanel 拖拽基类 | `scenes/ui/overlays/hud/hud_draggable_panel.gd` | ~170 行 | 拖拽+缩放+落点持久化 `user://ui/hud_positions.json`；**mouse_filter 纪律正确示范**（按钮 STOP、其余装饰节点全 IGNORE） |
| 5 | UIFeedback 交互反馈 | `scenes/ui/components/ui_feedback/UIFeedback.gd` | ~150 行 | 悬停/按下/焦点/音效全读 `ui_anim.json`+`ui_sfx.json`（改手感只改表）；pivot 中心缩放/tween kill/键盘焦点三缺陷修复 |
| 6 | UIPalette 主题常量 | `core/constants/ui_theme.gd` | 87 行 | 色/字号阶梯/布局栅格全集中，禁裸 Color 字面量纪律载体 |
| 7 | UILayout 布局装载 | `core/ui_layout.gd` | 78 行 | `hud_layout.json` 参考分辨率等比缩放 + 三级 fallback 零破坏 |
| 8 | UICenterUtils 居中工具 | `scenes/ui/ui_center_utils.gd` | 83 行 | PRESET_CENTER 坑（Godot 4.7.2 清零 offset）绕行；`clamp_panel_size` 纯函数可单测 |
| 9 | AudioManager 池化音频 | `autoload/AudioManager.gd` | 239 行 | SFX 8 池化 + 流缓存 + 总线动态创建 + BGM 去重 |
| 10 | LocalizationManager | `autoload/localization_manager.gd` | 62 行 | strings.csv → Translation → TranslationServer，三 locale，BOM 处理 |
| 11 | TransitionManager | `autoload/transition_manager.gd` | 57 行 | 转场遮罩收口 + 重入保护（INK/BLACK 实装，余占位见 P-V10） |
| 12 | SettingsManager 键位画面 | `autoload/settings_manager.gd` | ~200 行 | 7 键位偏好 + 渲染/UI 缩放拆分（08-29 事故修复沉淀） |
| 13 | 配置面 11 json | `data/configs/ui/` | — | screens / menu_config / ui_anim / ui_sfx / hud_layout / main_menu_layout / main_menu_assets / loading_layout / loading_tips / login_bg_layout / login_button_bg |
| 14 | **零数值写入纪律** | scenes/ui 全域 | — | `\.(gold\|silver\|copper\|hp\|mp\|exp\|level)\s*=` **零命中**（本图实测，冻结为基线） |

### 2.2 实锤缺陷（P-V1 ~ P-V12）

- **P-V1【键位双真源】** `TownScene.gd` L35-44 默认键位表 **8 动作**（含 `toggle_menu: KEY_G`）+ L527-533 运行期 InputMap 注册；`settings_manager.gd` L12 `REBINDABLE_ACTIONS` **7 键**（无 toggle_menu）+ L15-23 默认表。settings 注释自认「实际 InputMap 在游戏内由 TownScene 注册默认，这里仅存偏好」——同一件事两处定义，改默认键位要改两处，toggle_menu 永不可重绑。
- **P-V2【音量双真源】** `AudioManager.gd` L10-12 硬编码 `VOLUME_BGM=0.6/SFX=0.8/VOICE=1.0`；`settings_manager.gd` L63 audio 默认值是另一套（master 0.8/music 0.6/sfx 0.8/voice 1.0）。SFX 池播放器音量取常量（L61），用户设置与播放音量的关系靠两条总线间接缝合。
- **P-V3【ViewModel 全缺】** 全库 `ViewModel|view_model` **零命中**；scenes/ui 28 文件直引 `GameManager/game_state/player_state/ConfigManager`（count 实测）；HUD 面板订阅 6 个 `player_*` 信号后 `_refresh()` 直拉 PlayerState 字段（`status_card_panel.gd` L20-27 `_ATTRS` key=PlayerState 成员名）。§31 读链 `Query → ViewModel → UI` 的中段整体缺失。
- **P-V4【UI 直连流程单例】** UI 层 6 处 `GameManager.` 流程调用：MapScreen L85 `goto_region`、SaveLoadScreen L325 `load_game`/L333 `start_new_game`、MainMenu L387 `load_game`、EscMenu L128 `return_to_title`、DifficultySelect L114 `start_new_game`；另 UIManager L366-369 `start_battle/return_to_town`。输入链 `Input → Command → Application` 未建，UI 直呼 GameManager。
- **P-V5【UI 直引 Service】** scenes/ui 5 文件直引业务 Service：InventoryScreen 7 行、EquipmentScreen 2、ShopScreen 2、AlchemyScreen 1、ForgeScreen 1；最大单点 DialogOverlay L113-253 六处 `GameManager.dialogue_service.start/next/select_option/end`。写路径跳过 Command/Application（与 09/10 图事务化、12 图 QD-3 咬合）。
- **P-V6【防御性 has_method 探测】** `localization_manager.gd` L13 `if SettingsManager != null and SettingsManager.has_method("get_language")`——autoload 必然存在，探测恒真。非死命令（13 图 P-S1 级），但违反 12 图 QD-6「has_method 探测禁用」纪律的一致性。
- **P-V7【手写 CSV 分列】** `localization_manager.gd` L41 `lines[r].split(",")` 无引号处理——文案含逗号即断列错位（tr 输出错串）。BOM 已处理，逗号未处理。
- **P-V8【IO 风格四分裂蔓延 UI 域】** `ui_manager.gd` L74-81（FileAccess+`JSON.parse_string`）、`settings_manager.gd` L84-99（同款，且 save 无原子写、坏档无 .bak）、`ui_layout.gd` L64-77（`JSON.new()`）、`localization_manager.gd` L22-27（FileAccess 手写）。13 图 SV-6「IO 统一 JSONUtil + SV-5 原子写」的覆盖面确认：settings.json 是玩家唯一不可丢文件之一却走最弱写法。
- **P-V9【core 层驻 4 个表现辅助】** `core/ui_layout.gd`、`core/constants/ui_theme.gd`、`core/combat_event_renderer.gd`(109 行)、`core/combat_entity_pool.gd`(85 行)。依赖方向未破（core 不引 UI），但表现资产驻 core 归属错位（11 图 AB-4 已登记 renderer/entity_pool，本图补登前两者）。
- **P-V10【转场枚举承诺未兑现】** `transition_manager.gd` L9-16 六类型枚举，L51-56 `_color_for` 仅 INK/BLACK/MIST 有实色，SCROLL/PAGE/SLASH 静默走默认黑——调用方选「卷轴展开」得到黑屏，无告警。
- **P-V11【输入门控散布】** `TownScene.gd` L319/375/436-494 约 10 处重复 `if UIManager.is_any_screen_open(): return` 手写门控；与 BaseScreen 顶层守卫构成双轨。新交互入口（安卓虚拟键等）每处都要记得补门控。
- **P-V12【screens.json 无 schema 校验】** `ui_manager.gd` L70-81 解析失败仅 warn 后返回空表（全部界面静默不可开）；23 项注册的键域/路径存在性/cache 字段类型零校验。screens.json 实测 23 项（此前记忆 21 项，含新增 NpcGalleryScreen/RankSelectDialog 等）。

---

## 3. 冻结契约（PV-1 ~ PV-8）

### PV-1 Presentation 分层与 ViewModel 契约
- 读链冻结：`Query → ViewModel → UI`。**ViewModel = UI-local transient display state**（宪法 L2097 原文锚定），表现层不拥有业务状态。
- ViewModel 形态：RefCounted 纯数据对象，字段=该屏展示所需的最小投影（含派生字段，如「负重百分比」「可否购买」）；输入端订阅 EventBus 信号 / 调 Query，输出端只被 UI 读。**ViewModel 禁反向写任何业务状态、禁持 Node 引用**。
- UI 组件（Screen/面板）只读自己的 ViewModel，不再直读 `player_state.*`/`GameManager.*` 现状字段（P-V3 收口）；Service/单例成员名（如 `_ATTRS` 的 PlayerState 字段 key）收敛进 ViewModel 映射层。
- 引入节奏=绞杀者逐屏，不搞一次性重写（见 §4）；ViewModel 命名 `XxxViewModel`，落位见开放问题 PV-1。

### PV-2 输入链契约
- 业务输入冻结：`Input → Command → Application`（宪法 §92：Player/AI/Editor/Automation 四源最终都映射 Command）。UI 不得为业务操作新开直连通道。
- 迁移期分级（现状→目标）：
  1. **数值/物品/装备/买卖类**：已禁（零命中基线），永久禁。一律经各域 Command（09/10 图）。
  2. **流程类**（读档/开局/回城/切区域/开战，P-V4 六处）：Phase3 Application 就位后改发 Command；此前维持白名单（PV-R03），只减不增。
  3. **UI-toggle 类**（开关背包/地图/菜单）：不 Command 化（见开放问题 PV-2），但 `_toggle_overlay` 收口为 `UIManager.toggle_screen(name)` 统一同键开关语义，TownScene 只留按键→转发的壳。
- 战斗输入同管道：Player Input 与 AI Input 都落 Command（11 图 AB-3 已冻结，本图认领 UI 侧执行面）。

### PV-3 PresentationEffect 执行器契约（承接 12 图 QD-2 / 11 图 AB-4）
- services 层只产指令：Effect 五类之 Presentation 类（sfx/shake/flash…）是**纯数据**，禁碰 Node/Tween/相机/ResourceLoader（12 图 QD-R10 已冻）。
- 执行器宿主落**表现层**：独立 `PresentationExecutor`（scenes 层演出段），订阅 EventBus Effect 指令，持 Tween/相机/AudioManager 执行。12 图 executor `_shake/_play_sfx` 迁移落点=此执行器（12 图 §4 Phase2 行的落地本体）。
- 11 图 `core/combat_event_renderer.gd`/`combat_entity_pool.gd` 归属随本契约一并裁决（开放问题 PV-3），战斗演出与任务演出共用同一执行器纪律：**演出代码只住 scenes，core/services 零演出**。

### PV-4 层级与屏幕生命周期契约
- 7 层 CanvasLayer 枚举值**显式冻结**（0/5/10/20/30/40/50），新增层级只可插入新值，禁改已有值（ui_manager L18 注释约定升格为契约）。
- 界面注册仅 `.tscn`（B 路线不回退）；`cache=true` 语义冻结（关闭仅隐藏、重开复用、重跑 `_on_open/_on_reopen`、补回栈）；弹窗关闭唯一路径=`popup_close_requested` → UIManager 收口，**任何界面禁止 queue_free 自己**；读档/新游戏必调 `close_all_screens()`。
- 打开唯一入口 `open_screen(name)`（防重复 + 缓存复用 + 统一淡入），禁绕过 UIManager 手动 add_child 到 UI 层。

### PV-5 键位单真源契约（P-V1 收口）
- `settings_manager` 是键位**唯一真源**：动作全集 = 移动 4 + toggle 4（补 `toggle_menu`）；`REBINDABLE_ACTIONS`、`DEFAULT_BINDINGS`、InputMap 注册三合一迁入 settings_manager（或其委托的输入段）。
- `TownScene` L35-44 默认表退役，只消费 `Input.is_action_pressed`/`is_action_pressed`，不定义、不注册。
- 键位偏好持久化仍走 `user://settings.json`（13 图 SV-6 `settings/` 域）。

### PV-6 配置面与 IO 契约（P-V8/P-V12 收口）
- 11 个 UI json 键域冻结：screens（name→{path:.tscn, cache:bool}）、menu_config（item→{nav/screen/battle_id}）、ui_anim（hover/press/focus/screen 预设）、ui_sfx（事件名→路径）、hud_layout（panels→{x,y,scale}）。新配置文件登记制。
- `screens.json` 加载后强校验：键非空、path 以 res:// 开头且 .tscn 结尾、文件存在、cache 布尔——违例**启动期 FATAL 列表输出**（fail-fast，禁静默空表降级）。
- UI 域全部 json IO 收敛 JSONUtil（13 图 SV-6），`settings.json` 写入升级原子写五步（13 图 SV-5，settings 属玩家不可丢数据）。

### PV-7 主题与图标契约
- 全 UI 禁裸 `Color(...)`/裸字号/裸边距字面量，一律 UIPalette（色/字号阶梯/栅格常量已有全量清单，升格为扫描项 PV-R09 前置纪律）。
- 图标唯一取径 `UIManager.get_icon(id)` / IconRegistry，禁代码 `load(png)`；icon id 形如 `<分类>/<名>` 不含扩展名；扩展名优先级 png>webp>svg>jpg>avif 冻结；缺图标=品红占位不崩溃（现行为冻结）。
- IconRegistry 依赖反转模式（EventBus 注入）冻结为「基础层需要上层能力时的标准解法」，禁再新增基础层 preload 上层的反向依赖。

### PV-8 本地化契约（P-V6/P-V7 收口）
- `strings.csv` 是界面文案唯一真源；界面禁硬编码中文玩家文案（数据配置内 `name_key` 引用优先，已有惯例升格）。
- locale 枚举冻结 `zh_CN/zh_TW/en` 三值；非法 locale 回退 zh_CN（现行为冻结）。
- CSV 解析必须处理引号包裹/逗号转义（P-V7 修复项），golden 含逗号文案 roundtrip；`has_method` 防御探测退役（P-V6）。

---

## 4. 迁移映射表（绞杀者分批，每步可停）

| # | 现状 | 目标 | Phase | 依据 |
|---|---|---|---|---|
| 1 | 键位双真源（P-V1） | settings_manager 三合一收口 | Phase2（低风险高价值） | PV-5 |
| 2 | 音量双真源（P-V2） | AudioManager 常量降级为默认兜底，读 settings | Phase2 | PV-6/PV-2 补 |
| 3 | IO 四分裂 + settings 弱写（P-V8） | JSONUtil 收编 + 原子写 | Phase2（随 13 SV-5/6） | PV-6 |
| 4 | CSV 逗号断列 + has_method（P-V6/7） | 解析器加固 + 探测退役 | Phase2 | PV-8 |
| 5 | screens.json 无校验（P-V12） | 启动期 schema 校验 | Phase2 | PV-6 |
| 6 | services 演出（12 图 P-Q10）+ core 演出辅助（P-V9） | PresentationExecutor 收口 + 归属裁决 | Phase2 起，Phase3 归位 | PV-3 |
| 7 | 输入门控散布（P-V11） | `toggle_screen` 收口 | Phase2 | PV-2 |
| 8 | 转场占位枚举（P-V10） | 未实现类型 warn 降级 BLACK + 登记占位 | Phase2 | PV-4 补 |
| 9 | UI 流程直连（P-V4 六处） | Command 化（白名单过渡） | Phase3（Application 就位） | PV-2 |
| 10 | core 表现辅助迁出（P-V9） | ui_layout/ui_theme → scenes/ui；renderer/pool 随 PV-3 | Phase3 | PV-3/开放 PV-3 |
| 11 | UI 直引 Service（P-V5） | 各域 Command（09/10/12 图承接） | Phase4 | PV-2 |
| 12 | ViewModel 逐屏引入（P-V3） | HUD 四面板 + Inventory 先行，其余随屏 | Phase4 | PV-1 |

---

## 5. Freeze 清单（批准后不可再改，改动走 ADR）

1. 7 层 CanvasLayer 枚举值（0/5/10/20/30/40/50）。
2. 两条流水线（Query→ViewModel→UI / Input→Command→Application）与「禁 Button→数值直写」禁令。
3. ViewModel 三禁：禁写业务状态、禁持 Node、禁业务判定读表现数据。
4. `.tscn`-only 注册、cache 语义、弹窗收口单路径、open_screen 唯一入口。
5. PV-R03 流程调用白名单的**存在形式**（白名单内容随 Phase 收窄，形式冻结）。
6. 键位动作全集 8 动作与 settings 唯一真源归属。
7. 11 个 UI 配置 json 的文件名与键域。
8. locale 三枚举；图标扩展名优先级五元组。
9. P-V1~P-V12 编号（缺陷登记永不回收，修复后在 Enforcement 基线表销账）。

---

## 6. DoD（本图完成的定义）

1. PV-1~PV-8 全部契约有宪法/01 图条款锚点，无 AI 自创标准。
2. P-V1~P-V12 每条含文件+行号级实锤，可被任何人独立复核。
3. 迁移映射 12 行每行有 Phase 归属，且不与 09/11/12/13 图 Phase 冲突。
4. 开放问题 PV-1~4 每条带推荐项，标注「AI 不自决，待用户/ADR」。
5. Enforcement 矩阵 PV-R01~R12 每条有 LN Gate 编号与验收方式，E0=0 如实登记。
6. §171 资产 14 项全部给出收编方式（升级/冻结/退役），零丢弃。
7. 本文档不包含任何实现代码，未改动任何生产源码。

---

## 7. 开放问题（AI 不自决，待用户/ADR 裁决）

> **【已追认 2026-09-06】** 用户整批复核：以下 PV-1~PV-4 全部按推荐执行（本节保留原文供审计）。

- **PV-1【ViewModel 落位与引入节奏】** 推荐：RefCounted 对象随屏落 `scenes/ui/<screen>/viewmodel_*.gd`（不建统一目录，跟屏走）；Phase4 从 HUD 四面板 + InventoryScreen 起步（P-V3 耦合最深处），其余屏幕「改哪屏带哪屏」；不引第三方 MVVM 框架（YAGNI）。
- **PV-2【UI-toggle 是否 Command 化】** 推荐：不化。开关面板是 UI 内部事务，Command 化徒增一层空转；但 `_toggle_overlay` 收口 `UIManager.toggle_screen()`（PV-2 分级第 3 类）必须做。业务操作（含菜单里 start_battle）一律 Command。
- **PV-3【core 层 4 个表现辅助归属】** 推荐：Phase3 一并迁出——`ui_layout.gd`/`ui_theme.gd` → `scenes/ui/theme/`（UIPalette 消费方全在 UI 层，preload 无方向问题）；`combat_event_renderer/entity_pool` 随 PV-3 落 scenes 演出段（11 图 AB-4 推荐一致）。迁移零行为变化，纯挪文件改 preload 路径。
- **PV-4【音频域边界】** 推荐：AudioManager 保留 autoload 形态，本图只冻结「Audio Trigger 归表现层、play_ui_sfx 表驱动」边界；音频总线细节/BGM 状态机不在 14 图展开，若后续需要另立 15 号后补图（宪法模块序列 01-18 无独立 Audio 章，01 §31 的 Audio Trigger 归本图管辖，深度按需分期）。

---

## 8. 一句话总纲

**表现层已是全工程纪律最好的域——本图把「自觉」变「门禁」，把缺失的 ViewModel/输入链/单真源三块欠账排进绞杀者队列，零推翻、全收编。**

---

## 9. 关联文档

- 宪法 §31/§32（管线与 Node 边界）、§92（四源归一）、§97/§100（分类与替换 0 修改）、L5887-5888（换 UI=Presentation 局部承担）
- 01 图 §31 Layer 06 Presentation、§32/§33（Godot 边界与 Scene 定位）
- 02 图 Command/Query 契约（PV-2 的 Command 宿主）
- 03 图 S-6（Save 序列化禁入 UI）
- 04 图 LN GATE 双命名空间（PV-R 矩阵编号依据）
- 09/10 图（UI 写路径的 Command 终点）、11 图 AB-3/AB-4/AB-5、12 图 QD-2/QD-3/QD-6、13 图 SV-5/SV-6
