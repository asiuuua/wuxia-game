---
name: wuxia-game-dev
description: 武侠 RPG（Godot 4.7.2 纯 GDScript 单机）开发总纲 skill。当开发/审查/调试这个武侠游戏（新增系统、改 UI、加战斗、调数值、跑双闸门验证、多 AI 协同、定位编译或测试失败、把项目知识交接给其他 AI）时使用。覆盖架构铁律、GDScript 4.x 硬规、Godot 本机验证（双闸门+类缓存+沙箱）、共享地基冻结边界、多 AI 协同协议（提交队列+handoff 传递板）、UI 解耦范式（PopupBase+EventBus 收口）、当前待接管清单与快速上手命令。This skill should be used when the task touches the 武侠游戏 Godot project at D:/武侠游戏.
agent_created: true
---

# 武侠游戏开发总纲（Godot 4.7.2 · 纯 GDScript）

> 本 skill 是 `D:/武侠游戏` 项目的"开发大脑"。任何 AI 加载后应按此总纲一致地开发，避免踩已记录的坑、违反架构、跑崩双闸门。
> 详细内容在 `references/`：architecture / gdscript_rules / verification / collab / ui_paradigm / pending_work。

---

## 一、项目定位（先对齐，再动手）

- 等距 2.5D 武侠 RPG 单机；Godot **4.7.2**；**纯 GDScript**；个人开发（用户是新手，需给可直接复制的步骤）。
- 实际代码纯 2D（`TownScene` 根 `Node2D+Camera2D`；`BattleScene` 根 `Control`）。等距是目标态，技术路线待拍板（建议纯 2D+ysort）。
- 战斗：回合制+自动。平台 Win+安卓。世界：区域枢纽式（独立场景+读条切换）。
- 纯 GDScript；仅在瓶颈处增量 GDExtension，**绝不整体重写**。
- 工程根：`D:/武侠游戏`（**Windows 风格路径**，勿用 `/d/...`，否则 Godot 静默不跑）。

## 二、架构铁律（必守，详见 references/architecture.md）

- 依赖方向：`autoload` → `core` → `data` → `services`(RefCounted) → `scenes` → `resources/tests/tools`。
- 四底线：**单向依赖** / 跨模块**只走 EventBus** / 数值**全进 JSON** / 命名**见名知意**。
- 业务层**不持有 Node**；`GameManager`=装配中枢（`PlayerState`+9 Service+`pending_battle_id`）；`GameState`=存档唯一来源。
- `UIManager`：6 层 `CanvasLayer` + 屏幕栈，`screens.json` 名→脚本 `script.new()` 实例化；关闭只收口到 UIManager。
- 验证黄金标准（收尾 SOP）：双闸门 ① `--quit` 零 SCRIPT/PARSE/COMPILE ERROR；② `run_all.tscn` 零 `✗`。

## 三、GDScript 4.x 硬规（高频坑，详见 references/gdscript_rules.md）

- autoload 禁写同名 `class_name`；`const X=preload` 与全局 `class_name X` 会 shadowed。
- untyped Array 遍历出 Variant → 显式标类型或 `Array[T]`；**typed Array 禁 `as Array[String]`（崩）→ 循环 append**。
- tab 缩进；函数体不能空；场景树忙用 `call_deferred`。
- `@warning_ignore` 顶层声明须列首无缩进；类级注解在 `extends` 前；autoload signal 须逐条加 `@warning_ignore("unused_signal")`。
- **`mini/maxi` 仅 2 参** → 多参嵌套；写三参 Parse Error 级联拖垮存档套件。
- 删函数须全工程 grep 残留；`Invalid call Nonexistent function 'new'` 真因是某脚本 Parse Error。
- `Control.scale` 以 `pivot_offset` 为基准（默认左上角）→ 悬停放大先设 pivot 中心并监听 `resized`。

## 四、Godot 本机验证铁律（必记，详见 references/verification.md）

- console：`C:\Users\Administrator\.workbuddy\binaries\godot\Godot_v4.7.2-stable_win64_console.exe`
- ⚠️ **验证必须串行**：多 Godot 进程抢 `.godot` 类缓存 → 级联假红。
- ⚠️ POSIX 路径 `/d/xxx` 让 Godot 静默不跑（门禁误报绿）→ ROOT 必须 `D:/武侠游戏`。
- ⚠️ `get_tree().quit(code)` 退出码不传播 → 以 `run_all` 的 `✗` 标记判成败，不靠进程码。
- ⚠️ 沙箱 git 写不落盘；⚠️ `.godot` 缺失=双闸门全崩（误删后 `--editor --quit` 重建）；⚠️ 沙箱给 Godot 的是 git-HEAD 快照（untracked 新文件不可见→验证前必须 commit）。
- 标准流程：① 真实磁盘还原数据 ② unsandboxed 重建 .godot ③ commit 新文件 ④ unsandboxed 跑 GATE1/GATE2。

## 五、共享地基边界（冻结，只增不改）

- **冻结文件**：`EventBus.gd` / `ConfigManager.gd` / `core/enums/*_enums.gd` / `screens.json` / `strings.csv`。改须写《变更通告》「共享地基增量」表并打招呼。
- **UI 窗口主权**：`scenes/ui/**` + `data/configs/ui/**` + `core/constants/ui_theme.gd` + `resources/themes/**` + `autoload/ui_manager.gd`。跨窗只派单不直改。

## 六、多 AI 协同协议（详见 references/collab.md）

- git 提交权收口：精确 `git add <文件>`（禁 `-A`），提交信息 `[窗名]` 前缀；各窗只产代码+双闸门+写《变更通告》。
- 提交队列 `tools/commit_queue.py`（队列化 `git add`，每小时自动化出队）。
- 隐患传递板 `tools/handoff.py`：open→claimed→done→followup→closed；派单与扫描窗口名须一致（`/` 被 sanitize 成 `_`）。
- 动接口→重跑 `gen_contract.gd`（`Godot console --headless --path "D:/武侠游戏" --script res://tools/gen_contract.gd`）更新 `docs/契约总表.md`。

## 七、UI 解耦范式（详见 references/ui_paradigm.md）

- 弹窗基类 `PopupBase`（`extends Control`）：提供 `make_glass_panel(size)` 居中玻璃面板 + `request_close()`（只 emit `EventBus.popup_close_requested`，**绝不自毁**）。
- 所有菜单弹窗继承 PopupBase；关闭逻辑 100% 走 EventBus→UIManager 收口（UIManager 订阅 `popup_close_requested`）。
- `UIManager` 6 层 `CanvasLayer`（POPUP=300）；`open_screen(name, layer)` 经 `screens.json` 注册；`_ready` 订阅 `popup_close_requested` 收口关闭。
- 菜单可由 `data/configs/ui/menu_config.json` **配置驱动**（加菜单零代码）。

## 八、当前待接管清单（详见 references/pending_work.md）

- open 派单：`fed3f00da584`(战斗→town 掉血崩) / `178267684159`(结缘→背包 休息不推进天数) / `acf2246fd5f2`(背包→结缘 聘礼跳过锁定)。
- UI 残留：BondRomance debug 按钮 / DialogOverlay 越权 / 主题裸色散落 / Toast 未池化。
- GATE2 flaky 真因=并发 Godot 抢缓存（已加固门禁防假绿）；`test_equip_swap_preserves_old_instance` 建议装备窗口复核 P1-3 实例身份。

## 九、快速上手命令

```bash
G="C:/Users/Administrator/.workbuddy/binaries/godot/Godot_v4.7.2-stable_win64_console.exe"
# 双闸门（串行、unsandboxed 跑真实磁盘）
"$G" --headless --path "D:/武侠游戏" --quit 2>&1 | grep -iE "SCRIPT ERROR|Parse ERROR|COMPILE ERROR"
"$G" --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn 2>&1 | grep -iE "套件：|✗ "
# 缓存损坏重建（勿 rm .godot，用此命令）
"$G" --headless --editor --quit
# 提交（沙箱内不落盘，须 unsandboxed）；中文路径 git add 坑→工作树仅项目正当改动时用 git add -A
git add -A && git commit -m "[窗名] 简述"
```

> 项目 `docs/` 含完整架构/GDD/变更通告/接管日志/契约总表（约 80 个 md），按需 Read 对应文档；本 skill 的 `references/` 是提炼后的高频知识。

---

## 给后续 AI 的上手检查单

1. 动手前先读 `references/architecture.md` 与 `references/collab.md`，确认改动落在正确主权边界。
2. 改完代码**必须串行跑双闸门**（GATE1 + GATE2），全绿才算完。
3. 碰冻结文件先写《变更通告》打招呼；跨窗改动只派单不直改。
4. 提交用精确 `git add`（或 `git add -A` 当工作树仅项目正当改动）；信息带 `[窗名]` 前缀。
5. 遗留待办见 `references/pending_work.md`，认领后到 `tools/handoff.py` 登记状态。
