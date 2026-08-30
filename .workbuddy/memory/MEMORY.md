# 武侠江湖 项目记忆（精简主线）

## 定位与锁定
- 等距 2.5D 武侠 RPG 单机；Godot **4.7.2**；纯 GDScript；个人开发（用户新手）。实际代码纯 2D（等距目标态待拍板）。战斗回合制+自动；平台 Win+安卓；世界区域枢纽式（独立场景+读条切换）。瓶颈才增量 GDExtension，绝不整体重写。

## 架构铁律
`autoload→core→data→services(RefCounted)→scenes→resources/tests/tools`。四底线：单向依赖 / 跨模块只走 EventBus / 数值全进 JSON / 命名见名知意。业务层不持有 Node；GameManager=装配中枢；GameState=存档唯一来源。UIManager：6 层 CanvasLayer + 屏幕栈。

## GDScript 4.x 硬规（必记）
- 手写 .tscn 的 `Color()` 必须写满 4 参，否则整份 .tscn Parse Error（错误指向 .tscn 行号，易误判）。
- typed Array 禁 `as Array[String]`（崩）→ 循环 append；untyped Array 遍历出 Variant → 显式标类型。
- `mini/maxi` 仅 2 参 → 多参嵌套；写三参 Parse Error 级联拖垮存档套件。
- 闭包按值捕获值类型：`func(): made += 1` 不回写外层 → 测试计数用 Array/RefCounted/Dictionary 原地改。
- 解析外部配置用 `JSON.new()` + `json.parse(txt) != OK`，别用 `JSON.parse_string()`（失败刷屏）。
- 删函数须全工程 grep 残留；`Invalid call Nonexistent function 'new'` 真因是某脚本 Parse Error。
- Control 绝对定位坑：anchor 四值归零且 offset_left==offset_right → 宽度恒 0；要绝对定位就四个 offset 全写死。
- **B 路线迁移回归**：界面从 `X.new()` 迁 .tscn 后，单测仍用 `X.new()` 构造会静默丢属性 → 测试改 `preload(x.tscn).instantiate()`；`instantiate()` 返回 Node 致类型推断失效需显式类型。

## Godot 本机验证铁律（必记）
- console：`C:\Users\Administrator\.workbuddy\binaries\godot\Godot_v4.7.2-stable_win64_console.exe`
- 双闸门：① `--headless --path "D:/武侠游戏" --quit` 零 SCRIPT/PARSE/COMPILE ERROR；② `run_all.tscn` 零 `✗`。
- ⚠️ 两条 Windows 致命：① ROOT 必须 Windows 风格 `D:/武侠游戏`（POSIX `/d/xxx` 让 Godot 静默不跑→门禁误报绿）；② `get_tree().quit(code)` 退出码不传播→以 `✗` 判成败。
- ⚠️ GATE2 盲点：套件自身 Parse Error 时不打印任何 `✗` → **判绿必须同时满足** `grep -c "✗"`==0 **且** `套件：通过 N · 失败 M` 的 M==0。
- ⚠️ 沙箱 git 写不落盘：git checkout/rm/stash 是空操作；恢复用 `git show HEAD:<path> > <path>`（重定向落盘）。**验证前必须 commit 新/改文件**，否则 Godot（沙箱给 git-HEAD 快照）看不到 untracked/未提交改动→报"数据文件不存在"。
- ⚠️ .godot 缺失=双闸门全崩（class_name 全报 not declared）→ unsandboxed `godot --headless --editor --quit` 重建。多 Godot 进程抢 `.godot` 缓存→验证串行；门禁统一 unsandboxed 跑。

## 主权边界
- 共享地基（冻结，只增不改）：EventBus.gd / ConfigManager.gd / core/enums/*_enums.gd / screens.json / strings.csv。改须写《变更通告》「共享地基增量」并打招呼。
- UI 窗口：`scenes/ui/**` + `data/configs/ui/**` + `core/constants/ui_theme.gd` + `resources/themes/**` + `autoload/ui_manager.gd`。战斗/背包/结缘窗口各有主权，跨窗只派单不直改。

## 多 AI 协同
- git 提交权收口 UI 模块：精确 `git add <文件>`（禁 `-A`），提交 `[窗名]` 前缀。
- 提交队列 `tools/commit_queue.py` + 隐患传递板 `tools/handoff.py`（open→claimed→done→followup→closed；/ 被 sanitize 成 _）。

## UI / B 路线（全量 .tscn 化已收官 2026-08-31）
- 方向：上层编排架构不变；**仅叶子构造从 `script.new()`+`_build()` 改 `.tscn` 实例化**。screens.json 21 项全 .tscn；动态列表（背包/技能栏/商店行等）仍代码 instantiate 模板 .tscn（设计预期）。
- HUD v2 四面板（状态卡/任务追踪/右上菜单/技能栏）已 .tscn；SaveCard 末组件 2026-08-31 迁入 .tscn（b8b06cc），双闸门 44 套件 0 ✗。
- 残留 `_build_ui()` 经核对均为「静态壳已进 .tscn、仅接线/动态列表」，非静态结构未迁。
- 待决策：HUD 是否在战斗中常驻（BattleScene mount_hud 视觉重叠风险）。

## 历史大模块（已落地）
- 背包数据层 100%（2a9ed85）。战术战棋逻辑+视图（92e79b0/d5fd587）。欢庆模块（docs/变更通告_2026-08-29_欢庆模块.md）。

## 当前 open 派单
- `fed3f00da584` 战斗→town：TownScene:52 掉血崩。
- `178267684159` 结缘→背包：休息/睡觉未推进天数（实测未实现）。
- `acf2246fd5f2` 背包→结缘：propose 聘礼跳过锁定。

## 收尾 SOP
- 双闸门门禁（见上）。动接口→重跑 `gen_contract.gd` 更新 `docs/契约总表.md`。

## 工作室工具 + 安全红线（tools/desktop_studio）
- Python http.server + 单页；PyInstaller 打 `dist/工作室专业调教.exe`（.gitignore 忽略，发行产物）。游戏侧对工具零依赖（懒加载+缺省回退），可整体卸载。
- 安全红线：服务只绑 127.0.0.1；用户输入拼路径必过 `_is_valid_id()` 白名单；回收站先 `basename`；ZIP 解压前逐条目校验；HTTP 层 `_origin_allowed()`（无 Origin/127.0.0.1/localhost/file 放行，其余 403）。改完必跑 `security_selftest.py`（15 断言）。
- PyInstaller 须 `pyinstaller 工作室专业调教.spec`（直接传 .py 会覆盖丢 datas/console=False）。打包 exe 是精简解释器→第三方库装不上，图片解析纯标准库。Godot 按扩展名选解码器→写图必须按文件头定真扩展名。
- ⚠️ 进程模型：studio_server.py 常驻阻塞，后台跑永不退出被判 failed；自检须 run_in_background 起→curl→TaskStop 主动停，且补刀 `Stop-Process` 清 8765 端口。
