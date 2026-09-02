# 工作室 · UI 模块使用手册

> 适用对象：零代码基础的内容/美术/策划同学。  
> 目标：不用写一行代码，就能在游戏里换界面、换皮肤、换贴图、调特效。

---

## 一、UI 模块在工作室里长什么样

打开桌面版工作室，顶部导航栏里有一个 **「UI 模块 ⬇️」** 按钮。点它，会展开一个下拉菜单：

```
UI 模块 ⬇️
  🎯 屏选择器（选要改哪个界面）
     ├ 设置弹窗 / 读档弹窗 / HUD 布局   ← 已落地
     └ 主菜单 · 确认框                   ← 即将上线
  🟢 换皮替换 · 零风险
     ├ 图标/贴图替换（UI 贴图）
     ├ 背景图替换（登录界面）
     └ 音乐音效                         ← 即将上线
  🔵 布局尺寸 · 低风险
     ├ 弹窗尺寸/位置（设置弹窗）
     ├ 读档卡片尺寸（读档弹窗）
     ├ HUD 大小/位置（HUD 布局）
     └ 主题配色（UI 皮肤定制）
  🟠 视觉特效 · 需护栏
     └ 流动烟雾·水面 / 视频层 / 骨骼动画  ← 即将上线
```

这样归类的好处是：**按「你到底想改什么」分**，而不是按文件/按模块分——小白心智是「我要换图标 / 改大小 / 换背景」，不再需要懂 json 在哪。每个分组标题用颜色标了风险等级（🟢 零风险换皮 / 🔵 低风险布局 / 🟠 需护栏特效），橙色那块别乱拉满。

> 🧭 **统一三步流（每个模块都一样，学会一个就会全部）**：① 选目标（哪个界面/元素）→ ② 改参数/传图（滑块·上传）→ ③ 预览并应用。进入任意 UI 模块后，页面顶部会自动出现「小白引导三行」（这是干嘛的 / 改了有啥用 / 怎么改），右下角都有「复原默认」一键回出厂值，零恐惧。

> 💡 所有改动都只写 **数据文件**（JSON / 图片），游戏代码只读不写，所以不会把程序改坏。

### 分类颜色与标注含义

进入每个 UI 子模块后，你还会看到带色小标签，代表该功能属于哪一类：

| 标签 | 含义 | 在哪些 tab 出现 |
|---|---|---|
| <span style="background:#1f3a2a;color:#7fe0a0;padding:2px 8px;border-radius:10px;font-size:12px">背景</span> | 改背景图、多分辨率变体、暗化/粒子/边色 | 登录界面 |
| <span style="background:#3a2f1a;color:#e6b35a;padding:2px 8px;border-radius:10px;font-size:12px">文案</span> | 改按钮文字、版本号等多语言文字 | 登录界面 |
| <span style="background:#1a2a3a;color:#5ab0e6;padding:2px 8px;border-radius:10px;font-size:12px">资源</span> | 换 Logo/图标/按钮底图/配色 | 登录界面、UI 贴图、UI 皮肤定制 |
| <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 拖拽/数值调整界面元素位置 | 登录界面、预加载界面、UI 皮肤定制 |
| <span style="background:#3a1a1a;color:#e66b6b;padding:2px 8px;border-radius:10px;font-size:12px">特效</span> | 粒子/动画类视觉效果 | UI 皮肤定制 |

---

## 二、四大子模块详细说明

### 2.1 登录界面（登录/主菜单）

**能改什么**：

| 功能区 | 分类 | 作用 | 改完哪生效 |
|---|---|---|---|
| 大背景图 | <span style="background:#1f3a2a;color:#7fe0a0;padding:2px 8px;border-radius:10px;font-size:12px">背景</span> | 替换主菜单/加载/读档共用的背景 | `assets/ui/main_menu_bg.png` |
| 多分辨率变体 | <span style="background:#1f3a2a;color:#7fe0a0;padding:2px 8px;border-radius:10px;font-size:12px">背景</span> | 给 1080p / 2K / 4K 屏各准备一张背景 | `assets/ui/main_menu_bg_*.png` |
| 背景布局 | <span style="background:#1f3a2a;color:#7fe0a0;padding:2px 8px;border-radius:10px;font-size:12px">背景</span> | 暗化强度、自动取边色、是否开落叶粒子 | `data/configs/ui/login_bg_layout.json` |
| 按钮文字对照表 | <span style="background:#3a2f1a;color:#e6b35a;padding:2px 8px;border-radius:10px;font-size:12px">文案</span> | 改「继续游戏」「设置」等按钮文案（简/繁/英） | 多语言字符串表 |
| 版本文字 | <span style="background:#3a2f1a;color:#e6b35a;padding:2px 8px;border-radius:10px;font-size:12px">文案</span> | 改右下角版本号 | 项目版本号 |
| 主菜单资源替换 | <span style="background:#1a2a3a;color:#5ab0e6;padding:2px 8px;border-radius:10px;font-size:12px">资源</span> | 换 Logo、副标题、悬停笔触、5 个菱形图标 | `data/configs/ui/main_menu_assets.json` |
| 各按钮背景图 | <span style="background:#1a2a3a;color:#5ab0e6;padding:2px 8px;border-radius:10px;font-size:12px">资源</span> | 给每个主菜单按钮单独换背景 | `data/configs/ui/login_button_bg.json` |
| 主菜单布局 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 拖拽标题组、菜单区、版本文字、右下角栏 | `data/configs/ui/main_menu_layout.json` |

**小白步骤**：
1. 点顶部「登录界面」。
2. 想换背景 → 在「大背景图」处点「选择文件」→ 点「替换大背景图」。
3. 想移动按钮位置 → 滚动到「主菜单布局（自由拖拽）」→ 拖动画布里的彩色块 → 点「保存布局」。
4. 改文案 → 在「按钮文字对照表」里直接改 → 点「保存文案」。
5. 进游戏或编辑器运行，按 F5/重新加载场景即可看到。

**注意**：
- 大背景图会被主菜单、加载界面、读档界面**三处共用**。
- 替换前工具会自动备份旧图（去「回收站」可找回）。
- 按钮背景图请传**横版图**，尺寸参考 280×44，竖图会被裁切。

---

### 2.2 预加载界面（加载界面）

**能改什么**：

| 元素 | 分类 | 作用 | 改完哪生效 |
|---|---|---|---|
| 进度条 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 加载进度条的位置、宽度、高度 | `data/configs/ui/loading_layout.json` |
| 进度百分比文字 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 0% 的位置 | `data/configs/ui/loading_layout.json` |
| 随机提示文字 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | "正在整理行囊…" 的位置 | `data/configs/ui/loading_layout.json` |
| 版本号文字 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 右下角版本号的位置 | `data/configs/ui/loading_layout.json` |

**小白步骤**：
1. 点顶部「预加载界面」。
2. 在画布上拖动进度条、百分比、提示文字、版本号到想要的位置。
3. 用「进度条宽度」滑块调长短。
4. 点「保存布局」。

**注意**：
- 坐标是「窗口比例归一化」（0~1），所以 PC、带鱼屏、iPad、手机都会自动适配。
- 随机提示语本身在 `data/configs/ui/loading_tips.json` 里，本页目前只改位置，不改文案。

---

### 2.3 UI 贴图

**能改什么**：

| 能力 | 分类 | 作用 | 改完哪生效 |
|---|---|---|---|
| 扫描界面 | — | 列出所有 UI 场景（背包、MainMenu、技能…） | — |
| 加背景图槽位 | <span style="background:#1a2a3a;color:#5ab0e6;padding:2px 8px;border-radius:10px;font-size:12px">贴图</span> | 给某个界面加一张背景图 | 直接写进对应 `.tscn` |
| 替换已有贴图 | <span style="background:#1a2a3a;color:#5ab0e6;padding:2px 8px;border-radius:10px;font-size:12px">贴图</span> | 上传新图覆盖旧槽位 | 对应 `.tscn` + `assets/` |

**小白步骤**：
1. 点顶部「UI 贴图」。
2. 左侧列表搜「背包」「MainMenu」等，点一个界面。
3. 点「＋ 给该界面加背景图槽位」或点已有槽位换图。
4. 上传 PNG（建议透明底）。
5. 打开 Godot 编辑器，找到对应场景，按 `场景 → 重新加载场景`，或重启编辑器。

**注意**：
- 这里**只换图，不动位置**。
- 位置、大小、层级一律回 Godot 编辑器里拖拽。
- 传图后若没刷新，用 Godot 的「重新加载场景」。

---

### 2.4 UI 皮肤定制

**能改什么**：

| 卡片 | 分类 | 作用 | 改完哪生效 |
|---|---|---|---|
| ① 确认框尺寸 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 调「确认/取消」弹窗的宽高 | `data/configs/ui/skin/confirm_dialog.layout.json` |
| ② 主题配色 | <span style="background:#1a2a3a;color:#5ab0e6;padding:2px 8px;border-radius:10px;font-size:12px">配色</span> | 调面板底色、描边、标题颜色、正文颜色 | `data/configs/ui/skin/theme.json` |
| ③ 视觉特效 | <span style="background:#3a1a1a;color:#e66b6b;padding:2px 8px;border-radius:10px;font-size:12px">特效</span> | 主菜单水墨背景：飘叶/流云/水面/小船 | `data/configs/ui/skin/main_menu.vfx.json` |

**小白步骤**：
1. 点顶部「UI 皮肤定制」。
2. 调确认框大小 → 拖滑块 → 点「应用」。
3. 换配色 → 点取色器 → 点「应用」。
4. 调特效 → 开关 + 速度滑块 → 点「应用」。
5. 任何一步点「复原默认」都能回到出厂值。

**注意**：
- 所有改动都带**数值护栏**（比如确认框 240~900px、飘叶数量 0~120），点坏了也点不到崩溃值。
- 视觉特效如果让手机卡顿，把「飘叶」关掉或数量调低即可。

---

### 2.5 HUD 布局（战斗/地图常驻四面板）

**能改什么**：HUD 四块常驻面板的**默认摆放位置 + 大小（缩放）**——状态卡（左上）、任务追踪（状态卡下方）、右上菜单（姻缘/菜单）、快捷技能栏（底部）。位置用坐标 (x, y)，大小用统一缩放系数 `scale`（0.6×~2.5×，不改内部布局比例，不会把字/条拉变形）。

| 面板 | 分类 | 默认位置（参考分辨率 1920×1080） | 改完哪生效 |
|---|---|---|---|
| 状态卡 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 左上角 (12, 12) | `data/configs/ui/hud_layout.json` |
| 任务追踪 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 状态卡正下方 (12, 362) | `data/configs/ui/hud_layout.json` |
| 右上菜单 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 右上角 (1700, 12) | `data/configs/ui/hud_layout.json` |
| 技能栏 | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 底部居中 (782, 980) | `data/configs/ui/hud_layout.json` |

**小白步骤**：
1. 点顶部「UI 模块 → HUD 布局」。
2. 在 16:9 画布里**拖动面板色块**到想要的位置；拖动面板**右下角白点手柄**缩放大小（0.6×~2.5×）。
3. 点「保存布局」→ 写入工程，游戏下次进 HUD 即按此默认摆放与大小。

**注意**：
- 坐标是「参考分辨率 1920×1080」下的绝对像素；游戏运行时按当前视口**等比缩放**坐标、并按 `scale` 缩放面板，所以 4K / 带鱼屏上比例一致（右上角仍是右上角）。
- 这是**出厂默认值**，不是强制锁定：玩家在游戏里既可拖动面板、也可拖右下角手柄缩放，落点会存到个人存档（`user://ui/hud_positions.json`，含 x/y/scale）覆盖此处设定；点工作室「恢复默认」即回到本页数值。
- 文件缺失 / 写坏 → 游戏自动回退各面板既有默认位置与 scale=1，零破坏。

---

### 2.6 设置弹窗（设置面板几何）

**能改什么**：设置弹窗整体的**面板几何**——面板封顶宽高、左右/上下留白比例、左侧分类按钮最小尺寸。

| 参数 | 分类 | 默认值（参考分辨率 1920×1080） | 改完哪生效 |
|---|---|---|---|
| 面板封顶宽 `panel_max_width` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 960 | `data/configs/ui/skin/settings_screen.layout.json` |
| 面板封顶高 `panel_max_height` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 680 | `data/configs/ui/skin/settings_screen.layout.json` |
| 左右留白比例 `margin_x_ratio` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 0.08 | `data/configs/ui/skin/settings_screen.layout.json` |
| 上下留白比例 `margin_y_ratio` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 0.10 | `data/configs/ui/skin/settings_screen.layout.json` |
| 分类按钮最小宽 `category_button_min_width` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 160 | `data/configs/ui/skin/settings_screen.layout.json` |
| 分类按钮最小高 `category_button_min_height` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 42 | `data/configs/ui/skin/settings_screen.layout.json` |

**小白步骤**：
1. 点顶部「UI 模块 → 设置弹窗」。
2. 在 6 个数值框里调面板宽高、留白比例、分类按钮尺寸（也可直接拖画布里的面板色块）。
3. 点「保存布局」→ 写入工程，游戏下次打开设置弹窗即按此几何自适应。
4. 点「恢复默认」回到出厂值。

**注意**：
- 数值是「参考分辨率 1920×1080」下的**封顶值 / 比例值**；游戏运行时按当前视口等比自适应，且不超过封顶值——4K / 带鱼屏上比例一致。
- 这是**出厂默认值**，游戏侧只读不写；文件缺失 / 写坏自动回退默认，零破坏。

---

### 2.7 读档弹窗（存档卡片列几何）

**能改什么**：读档界面里那一条**居中存档卡片列**的几何——卡片列封顶宽高、左右/上下留白比例、单张存档卡片最小尺寸。

| 参数 | 分类 | 默认值（参考分辨率 1920×1080） | 改完哪生效 |
|---|---|---|---|
| 卡片列封顶宽 `content_max_width` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 640 | `data/configs/ui/skin/saveload_screen.layout.json` |
| 卡片列封顶高 `content_max_height` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 724 | `data/configs/ui/skin/saveload_screen.layout.json` |
| 左右留白比例 `margin_x_ratio` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 0.0 | `data/configs/ui/skin/saveload_screen.layout.json` |
| 上下留白比例 `margin_y_ratio` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 0.15 | `data/configs/ui/skin/saveload_screen.layout.json` |
| 卡片最小宽 `card_min_width` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 640 | `data/configs/ui/skin/saveload_screen.layout.json` |
| 卡片最小高 `card_min_height` | <span style="background:#2a1a35;color:#c98be6;padding:2px 8px;border-radius:10px;font-size:12px">布局</span> | 112 | `data/configs/ui/skin/saveload_screen.layout.json` |

**小白步骤**：
1. 点顶部「UI 模块 → 读档弹窗」。
2. 在 6 个数值框里调卡片列宽高、留白比例、单卡尺寸。
3. 点「保存布局」→ 写入工程，游戏下次打开读档界面即按此几何自适应。
4. 点「恢复默认」回到出厂值。

**注意**：
- 数值是「参考分辨率 1920×1080」下的**封顶值 / 比例值**；游戏运行时按当前视口等比自适应，且不超过封顶值。
- 这是**出厂默认值**，游戏侧只读不写；文件缺失 / 写坏自动回退默认，零破坏。

---

## 三、5 分钟快速上手路径

如果你是第一次用，建议按这个顺序玩一遍：

1. **换主菜单背景**：UI 模块 → 登录界面 → 大背景图 → 选图 → 替换。
2. **移动主菜单按钮**：登录界面 → 主菜单布局 → 拖动菜单区 → 保存布局。
3. **改弹窗颜色**：UI 模块 → UI 皮肤定制 → 主题配色 → 挑颜色 → 应用。
4. **关特效省电**：UI 皮肤定制 → 视觉特效 → 关掉飘叶/小船 → 应用。
5. **给加载界面换个布局**：UI 模块 → 预加载界面 → 拖动进度条 → 保存布局。
6. **重新摆 / 缩放 HUD 四面板**：UI 模块 → HUD 布局 → 拖动面板改位置 / 拖右下角白点改大小 → 保存布局。
7. **调读档卡片列**：UI 模块 → 读档弹窗 → 调 6 个数值 → 保存布局。

全部改完，进 Godot 编辑器按 F6 运行，即可实时看到效果。

---

## 四、数据文件对照表

| 工作室入口 | 改的数据文件 | 游戏侧读取脚本 | 回退方式 |
|---|---|---|---|
| 登录界面 → 大背景图 | `assets/ui/main_menu_bg.png` | `MainMenu.gd` / `LoadingScreen.gd` | 回收站找回备份 |
| 登录界面 → 多分辨率变体 | `assets/ui/main_menu_bg_*.png` | 按窗口宽度自动挑选 | 删除变体文件即回主图 |
| 登录界面 → 背景布局 | `data/configs/ui/login_bg_layout.json` | `MainMenu.gd` | 点「复原默认」 |
| 登录界面 → 主菜单资源 | `data/configs/ui/main_menu_assets.json` | `MainMenu.gd` | 重新上传原图 / 改回默认 |
| 登录界面 → 按钮背景图 | `data/configs/ui/login_button_bg.json` | `MainMenu.gd` | 点「体检：修复扩展名错配」或重新上传 |
| 登录界面 → 主菜单布局 | `data/configs/ui/main_menu_layout.json` | `MainMenu.gd` | 点「恢复默认」 |
| 预加载界面 → 布局 | `data/configs/ui/loading_layout.json` | `LoadingScreen.gd` | 点「恢复默认」 |
| UI 贴图 | 各 `scenes/ui/**/*.tscn` + `assets/` | 对应场景的 `.gd` | 用 git / 回收站恢复 |
| UI 皮肤定制 → 确认框尺寸 | `data/configs/ui/skin/confirm_dialog.layout.json` | `ConfirmDialog.gd` | 点「复原默认」 |
| UI 皮肤定制 → 主题配色 | `data/configs/ui/skin/theme.json` | `UISkin`（通用装载器） | 点「复原默认」 |
| UI 皮肤定制 → 视觉特效 | `data/configs/ui/skin/main_menu.vfx.json` | `UIVFX`（通用装载器） | 点「复原默认」 |
| HUD 布局 | `data/configs/ui/hud_layout.json` | `core/ui_layout.gd`（通用装载器 `hud_default_pos`/`hud_default_scale`）+ 四面板 `_init_drag`、quest_track 自带实现 | 点「恢复默认」 |
| 设置弹窗 | `data/configs/ui/skin/settings_screen.layout.json` | `SettingsScreen.gd`（`_load_layout_config` 通用装载器） | 点「恢复默认」 |
| 读档弹窗 | `data/configs/ui/skin/saveload_screen.layout.json` | `SaveLoadScreen.gd`（`_load_layout_config` 通用装载器） | 点「恢复默认」 |

---

## 五、安全与回退

1. **自动备份**：替换图片时，工具会自动把旧图备份到回收站/备份目录，不怕手滑覆盖。
2. **复原默认**：所有 JSON 配置页面都有「恢复默认」或「复原默认」按钮，一键回到工程初始值。
3. **数值护栏**：滑块、输入框都有上下限，点不到会让游戏崩溃的数值。
4. **只改数据不动代码**：所有改动只影响 `data/configs/ui/` 和 `assets/ui/`，不会改 `.gd` 脚本。
5. **生效前提**：
   - 在 Godot 编辑器里运行 → 改完立刻生效（可能需要重新加载场景）。
   - 已打包发行的 exe → **必须重新打包游戏**才会生效。

---

## 六、常见问题速查

| 问题 | 原因 | 怎么办 |
|---|---|---|
| 换了背景图但游戏里没变 | 用了打包版 exe，或 Godot 没重新导入 | 在编辑器里运行；或「场景 → 重新加载场景」 |
| 主菜单按钮背景没了 | 图片格式和扩展名对不上（如 JPEG 存成 .png） | 登录界面 → 点「体检：修复扩展名错配」 |
| 弹窗颜色改完不生效 | 没点「应用」，或游戏读的是打包资源 | 点应用；编辑器里运行验证 |
| 手机版特别卡 | 水墨特效开太高 | UI 皮肤定制 → 视觉特效 → 关飘叶/降数量 |
| 不知道某个文件在哪 | 看上面的「数据文件对照表」 | 按表搜索 |

---

## 七、谁该用哪个入口

| 角色 | 常用入口 | 典型操作 |
|---|---|---|
| 美术同学 | UI 贴图、UI 皮肤定制、登录界面 | 换背景、换图标、调配色、调特效 |
| 策划同学 | 登录界面、预加载界面 | 改按钮文案、调布局、换加载提示 |
| 程序同学 | 双闸门 | 验证改动是否导致游戏报错 |
| 任何人 | 回收站 | 找回被覆盖/删除的图片 |
