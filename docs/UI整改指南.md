# UI 整改指南（大厂标准审视 → 落地）

> 缘起：以一线大厂严苛标准审视 UI 层后，产出 P0/P1/P2 整改清单。
> 本次仅落地 **P0（字体 + 全局主题）**，P1/P2 为后续规划，未执行。
> 执行原则：单一真源、零侵入（不改任何界面脚本，靠工程默认主题统一下发）。

---

## P0 — 字体 + 全局主题（已完成 ✅）

### 问题
- 项目 0 个 CJK 字体、0 个 `.theme` 资源 → 中文界面渲染为方框/豆腐块。
- 配色靠 `add_theme_*_override` 散落在各脚本，无统一 StyleBox，按钮/面板观感不一致。
- 字体根本没设，只能靠 Godot 内置（无中文）字体兜底。

### 落地方案
1. **字体资产**：用户已放入 `resources/fonts/SiYuanSongTiRegular/`（思源宋体 7 个字重，已导入）。
   - Regular=`SourceHanSerifCN-Regular-1.otf`（正文默认）
   - Bold=`SourceHanSerifCN-Bold-2.otf`（富文本 `[b]` 加粗用）
2. **全局主题资源** `resources/themes/ui_theme.tres`（由 `tools/gen_ui_theme.gd` 脚本生成，可重复执行）：
   - `default_font = 思源宋体 Regular`，`default_font_size = 18`
   - `RichTextLabel` 的 `bold_font = 思源宋体 Bold`（供 `[b]` 加粗）
   - 配色直接复用 `core/constants/ui_theme.gd` 的 `UIPalette`（墨/宣纸/金/危险/墨绿），保证与既有美术一致
   - 内置 StyleBox：Panel（深棕底+金边）、Button（normal/hover/pressed/disabled/focus）、LineEdit（normal/focus）、ProgressBar（bg/fill）
3. **工程接线** `project.godot`：
   ```ini
   [gui]
   theme/custom="res://resources/themes/ui_theme.tres"
   ```
   作用：设为工程默认主题后，**所有控件（含 `script.new()` 动态生成的 Control）自动继承中文字体与样式**，无需逐个界面改造。

### 验证（已通过）
- 字形自检：思源宋体含「江湖」字形（生成器内 `has_char` 校验）。
- 端到端：构造 `Label` 挂树后 `get_theme_font("font")` 解析到 `SourceHanSerifCN-Regular-1.otf`，`has_char(江)=true` → 中文可渲染。
- 启动 parse-gate + 真实启动：无任何 `SCRIPT ERROR / Parse Error / freed object`。
- 全工程零界面脚本硬编码字体（grep 确认），全局主题全覆盖。

### 复现 / 重新生成
```bat
Godot_v4.7.2-stable_win64_console.exe --headless --path "D:/武侠游戏" --script "D:/武侠游戏/tools/gen_ui_theme.gd"
```
> ⚠️ 必须用 **4.7.2** 引擎（本机另有 4.3，版本错配会崩）。项目 `config/features` 为 4.7。

### 已知遗留 / 后续优化
- 完整思源宋体约 11MB/字重，PC 端内存可接受；安卓/iOS 上线前应**子集化字体**（仅保留用到的字形）以降包体与内存，属 P2/P3 优化项。
- 仅 Regular 作默认字体，标题层级目前靠各界面 `font_size` 覆盖；后续可在主题里加更大字号命名项做层级。

---

## P1 — 规划中（未执行）
- ③ 统一两套 UI 模型（UIManager 栈 vs TownScene 直接 instantiate），收敛为单一 ownership。
- ⑤ 补全剩余界面本地化（当前仅 4/14 界面接 `tr()`）。
- ⑥ 颜色/字号统一走 `UIPalette` + 主题常量，清除脚本内散落字面量。

## P2 — 规划中（未执行）
- 布局栅格化、焦点导航、动画过渡、Loading 进度表现等打磨项。
