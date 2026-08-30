# UI 架构整改方案 · 美术驱动「完全自定义外观」中立重估

> 前提变更：用户确认**后期所有外观都要改，走自定义控件，让美工完全重现国风雕花/木板/多层叠加**。
> 因此上一评测「九宫格非适用（美术方向不同）」**作废**——新目标下，九宫格 `.9-slice`、纹理贴图、美术可编辑面都从「非适用」变为「必备」。
> 本文立场：**中立**。不替你守「纯代码派」，也不替文字守「.tscn 派」，只客观比较两种落地路线在当前工程上的成本/收益/风险，并给出漏洞、实施、评分。

---

## 0. 先纠正一个结论

| 项 | 上一评测（玻璃拟态前提） | 本评测（美术完全自定义前提） |
|---|---|---|
| 九宫格 `.9-slice` | 非适用（你走 `StyleBoxFlat` 矢量玻璃） | **必备**（雕花木板贴图拉伸必变形） |
| 美术可编辑面 | 美术只丢图标即可 | **美术要能改底板/边框/雕花/光效**，且尽量不碰 GDScript |
| 复合控件外壳 | `.gd` 类 `new()` 足够 | 仍可用 `.gd`，但**外观数据必须外置成资源/表** |

实测现状（`scenes/ui`）：`StyleBoxFlat` 出现在 **13 个文件 / ~65 处**，`StyleBoxTexture`/`NinePatchRect` **0 处**。即：当前"外观"100% 是代码里手搓的矢量玻璃，**没有任何一处纹理贴图或九宫格**——这正是新目标要彻底替换的核心。

---

## 1. 两条落地路线（中立对比）

### 路线 A/C：在现有代码架构上，加一层「皮肤资源层」（推荐评估）
保留 `UIManager`(`script.new()` + `screens.json`) + 数据驱动，把"外观"从硬编码 `StyleBoxFlat` 抽成**一份 `UISkin` 资源（`.tres` 或 JSON）**，所有控件经工厂读取它，改用 `StyleBoxTexture`（九宫格）或 `NinePatchRect`。

- ✅ **成本最低**：不碰 `UIManager` 装配链、不碰 `screens.json`、不动双闸门范式；改动集中在"工厂 + UISkin 资源"。
- ✅ **美术可控**：美术改 `UISkin`（贴图路径、九宫格边距、边框、字体、兜底色）+ 往 `resources/ui/textures/<分类>/` 丢 PNG，即可全量换肤，**零 GDScript**。
- ✅ **复用已有资产**：`IconRegistry` 思路直接复用；`UIPalette` 颜色常量保留作兜底。
- ⚠️ **不提供编辑器内 WYSIWYG**：美术看不到实时布局，需跑游戏看效果（技术美术/你自己可接受；纯视觉美术会别扭）。
- ⚠️ **复合控件仍是代码布局**：雕花多层叠加靠代码摆 `TextureRect`，美术不能拖节点。

### 路线 B：全量迁移到 `.tscn` 复合控件 + Theme + 九宫格（文字原教旨）
按大厂篇：`SkillItem.tscn`/`CardButton.tscn` 之类，根 `Control` + 贴图子节点 + 透明 `Button`，`@export` 暴露属性，`ui_theme.tres` 管皮肤。

- ✅ **美术 WYSIWYG**：美术在编辑器里直接拖贴图、调九宫格、看效果，最贴合"美工完全重现"。
- ✅ **业界标准**：招人/接手成本低，文字即行业标准。
- ❌ **范式级返工**：`UIManager` 的 `script.new()` 装配 + 21 个 `screens.json` + 全部 `_build()` 要重写；`BaseScreen`/`PopupBase` 体系要重构。
- ❌ **双闸门风险**：迁移期必然红（`Parse Error`/`✗`），且单人开发回归面极大。
- ❌ **丢数据驱动优势**：`screens.json` 名→脚本的表驱动是现有强项，`.tscn` 不天然支持"加界面只改表"。

### 中立裁决
| 维度 | 路线 A/C（皮肤层） | 路线 B（.tscn 全迁） |
|---|---|---|
| 实现成本 | 低（加层+换工厂） | 高（范式重写） |
| 门禁风险 | 低（增量、可逐步绿） | 高（迁移期必红） |
| 美术 WYSIWYG | 中（跑游戏看） | 高（编辑器内） |
| 外观还原度 | 高（纹理+九宫格全支持） | 高 |
| 数据驱动保留 | 是 | 否（需另做机制） |
| 适合谁 | 技术美术 / 你自己兼美术 | 纯视觉美术、且愿意花数周返工 |

**中立结论**：若美术是你本人或能跑 Godot 的技术美术 → **路线 A/C 性价比碾压**。若美术是纯视觉、绝不碰引擎 → 你迟早要 B，但应**先 A/C 把皮肤层立起来、美术能换肤**，再对少数"重视觉复合控件"（卡牌/武学按钮）试点 `.tscn` 混合，而非一次性全迁。

---

## 2. 现有架构整改方向（以路线 A/C 为基准）

核心是**把"外观"从代码里彻底外置**，让现有 13 文件 / 65 处 `StyleBoxFlat` 塌缩成"工厂读 UISkin"的少数调用点。

1. **新增 `UISkin` 资源**（`core/constants/ui_skin.gd` 或 `resources/ui/ui_skin.tres`）：持有所有纹理化外观字段（见 §4）。
2. **工厂重构**：`make_glass_panel`(`popup_base.gd:27`) / `apply_glass_style`(`ui_center_utils.gd:36`) 改名为 `make_skinned_panel` / `apply_skin`，内部从 `StyleBoxFlat` 改为 `StyleBoxTexture`（设 `texture`、`region_rect`、九宫格 `margin`）。
3. **全屏/弹窗/HUD 全部经工厂**：13 个文件的 `StyleBoxFlat.new()` 改为调工厂（或工厂内部统一处理，调用方只传"面板类型"枚举）。
4. **复合控件纹理化**：`ItemSlot`/`SaveCard`/`Tooltip`/`StatusCard`/`ConfirmDialog`/`MainMenu` 的玻璃底 → 改用 `UISkin` 的底板/边框/雕花纹理（多层 `TextureRect` 叠加）。
5. **保留**：`UIManager` 6 层、`UIPalette` 颜色兜底、`IconRegistry`、`screens.json` 机制——它们与"外观纹理化"正交，不动。

---

## 3. 漏洞清单（现有架构在新目标下的脆弱点）

🔴 **P0（阻断美术完全重现）**
- **V-1 无纹理/九宫格能力**：全工程 `StyleBoxFlat` 矢量玻璃，0 处 `StyleBoxTexture`/`NinePatchRect`。美术要的雕花木板一拉伸就糊——**这是新目标的第一阻断点**。
- **V-2 外观硬编码在 65 处 `StyleBoxFlat`**：没有统一皮肤绑定层，换肤要改 13 个文件，美术无法自助。

🟠 **P1（一致性 / 美术协作）**
- **V-3 美术无编辑面**：现在美术只丢 `IconRegistry` 的图标；底板/边框/字体的外观数据无入口，纯视觉美术寸步难行。
- **V-4 皮肤策略分裂**：HUD 用真实 `Button`（吃 `ui_theme.tres`）＋`ItemSlot` 自绘玻璃——两套皮肤源。纹理化后要统一成"UISkin 单一真相"。
- **V-5 无图集 / AssetManager**：美术丢几十张 PNG → DrawCall 飙升、无引用计数/卸载（战斗侧同源缺口 AM-1），多场景切换内存抖动。

🟡 **P2（健壮性）**
- **V-6 像素布局（H-1）未解**：纹理 UI 尺寸应来自"纹理本身 + 九宫格边距 + 栅格常量"，不能再用 `offset_left=-178`。
- **V-7 响应式**：`StatusCard` 的 `scale=0.667` 形变在纹理 UI 下会更糊，需改锚点/最小尺寸策略。
- **V-8 迁移期门禁**：若走 B，双闸门必红，需规划"分屏迁移 + 逐步绿"的节奏，避免长期红灯掩盖真实错误。

---

## 4. 具体实施（分阶段，文件级）

> 以路线 A/C 为默认；阶段 6 标注 B 路线才需要的动作。

**阶段 1 — 立 UISkin 资源（美术入口）**
- 新建 `core/constants/ui_skin.gd`（或 `resources/ui/ui_skin.tres`），字段示例：
  ```gdscript
  # 面板/底板
  const panel_bg: Texture2D          # 九宫格底板（雕花木板）
  const panel_bg_9slice: Rect2       # 九宫格边距（左/上/右/下）
  const panel_border: Texture2D      # 边框雕花
  # 按钮四态
  const btn_normal / btn_hover / btn_pressed / btn_disabled: Texture2D
  # 复合控件
  const card_bg / card_frame / slot_bg / slot_locked: Texture2D
  # 兜底（美术资源缺失时）
  const fallback_color: Color = UIPalette.GLASS_BG
  ```
- 美术往 `resources/ui/textures/<分类>/<名>.<ext>` 丢图；`UISkin` 引用路径即生效（复用 `IconRegistry` 加载逻辑）。

**阶段 2 — 工厂切换 StyleBoxFlat → StyleBoxTexture（九宫格）**
- `popup_base.gd` 的 `make_glass_panel` → `make_skinned_panel(type: int)`：
  ```gdscript
  func make_skinned_panel(type: int) -> Panel:
      var p := Panel.new()
      var sb := StyleBoxTexture.new()
      sb.texture = UISkin.panel_bg
      sb.region_rect = UISkin.panel_bg_9slice  # 九宫格
      p.add_theme_stylebox_override("panel", sb)
      return p
  ```
- `ui_center_utils.gd` 的 `apply_glass_style` 同样改读 `UISkin`。

**阶段 3 — 13 文件 65 处塌缩到工厂**
- `ItemSlot`/`SaveCard`/`Tooltip`/`StatusCard`/`ConfirmDialog`/`Settings`/`SaveLoad`/`MainMenu`/`Loading`/`QuestTrack`/`SkillBar` 等：删各自 `StyleBoxFlat.new()`，改调工厂或 `apply_skin`。
- 这一步是主要工作量，但**纯替换、不改结构**，双闸门逐屏转绿。

**阶段 4 — 复合控件多层纹理化**
- `ItemSlot` 等加 `TextureRect` 叠加层（底板+边框+雕花+光效），纹理全部来自 `UISkin`；锁定/空态走 `UISkin.slot_locked` 等。
- 引入轻量 `set_state(NORMAL/DISABLED/LOCKED)`（呼应上篇 ST-1），消除内联 if。

**阶段 5 — AssetManager lite（UI 侧）**
- 扩展 `IconRegistry` 为「UI 纹理引用计数 + 可选图集」，与战斗侧阶段 B 合并，治 V-5/AM-1。

**阶段 6 —（仅路线 B 需要）`.tscn` 复合控件迁移**
- 把 `SkillItem`/`CardButton`/`ItemSlot` 等存 `.tscn` + `@export`；`UIManager` 改用 `preload/load .tscn` + `instantiate`；`screens.json` 改存 `.tscn` 路径。分阶段逐屏切，每切一屏跑双闸门保绿。

---

## 5. 综合评分（中立，0–10）

评分对象 = **现有架构对「美术驱动完全自定义外观」这一新目标的适配度**。

| 维度 | 当前 | 整改后(A/C) | 说明 |
|---|---|---|---|
| 结构分层（UIManager 6层/栈/缓存） | 9 | 9 | 与新目标正交，已是强项 |
| 数据驱动/可维护 | 8 | 8 | script.new + screens.json 保留 |
| 主题/Token 集中 | 7 | 9 | UIPalette 颜色已集中；加 UISkin 纹理后补全 |
| **纹理/九宫格支持** | **2** | **9** | 当前 0 处；阶段1-3 补齐 |
| **美术可编辑面** | **3** | **8** | 当前只丢图标；UISkin 让美术改外观零代码 |
| 复合控件复用 | 7 | 8 | 纹理化后仍复用，加 set_state |
| 性能/资源治理 | 4 | 7 | 阶段5 AssetManager lite + 图集 |
| 迁移风险/门禁安全 | — | 高(A低/B高) | A 增量绿；B 迁移期红 |
| **综合** | **~5.4** | **~8.4** | 骨头好，缺「皮肤/纹理/美术面」一层 |

> 说明：**当前 ~5.4 不是架构烂，而是"外观层缺失"拉低**——结构、分层、数据驱动都是 8–9 分。补上 UISkin + 九宫格 + 工厂塌缩 + AssetManager lite，即达 ~8.4（大厂可行线）。若再走 B 全 .tscn，潜力 9 但需额外数周且门禁长期红，性价比不如 A/C。

---

## 6. 中立最终建议

1. **撤回"九宫格非适用"**：新目标下它是必备，现有 0 处九宫格是首要整改点。
2. **架构没坏，缺的是"皮肤层"**：不要因为文字说".tscn 才是正道"就推倒重来。你的 `UIManager`/数据驱动/双闸门是真实资产，应**在上面加 UISkin 层**，而非拆掉。
3. **先 A/C 立皮肤层**（阶段1–5，成本周级、门禁可保持绿），美术即可全量换肤、完全重现国风雕花。
4. **仅当美术是纯视觉、绝不碰引擎**，才对少数重视觉复合控件试点 `.tscn`（阶段6 混合），且务必"分屏迁移 + 每屏保绿"，别一次性全迁把门禁搞红。
5. **漏洞优先级**：V-1/V-2（九宫格+皮肤层）是 P0 阻断点，先解；V-3/V-4（美术面+策略统一）是 P1 协作前提；V-5（AssetManager）上线前必补。

走 A/C，你这套架构在"美术完全自定义外观"目标下能达到 **8/10 以上**且风险可控；盲目全迁 `.tscn` 是用高成本换一个你当前并不必须（技术美术可跑游戏看效果）的 WYSIWYG。
