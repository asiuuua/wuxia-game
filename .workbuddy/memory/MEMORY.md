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
- **mouse_filter 枚举写反是高频静默吞输入坑**：`MOUSE_FILTER_STOP=0` / `MOUSE_FILTER_PASS=1` / `MOUSE_FILTER_IGNORE=2`（与直觉相反）。凡要把装饰子节点设成「点击穿透」，必须写 `2`(IGNORE) 或 `Control.MOUSE_FILTER_IGNORE`，**绝不可写 `0`**（那是 STOP=拦截，会让子节点盖住按钮本体、吞掉 mouse_entered/button_up，表现为「点不了/鼠标卡住/无报错」）。诊断此类静默拦截用无头 mouse-pick 模拟器（递归比各控件中心点的 topmost STOP 控件），逻辑单测抓不到。
- **自动守卫已落地（2026-09-02）**：`tools/lint_mouse_filter.py`(GATE0 静态扫描，提交前跑，零误报) + `tests/unit/test_ui_mouse_filter.gd`(GATE2 运行时断言，加载全部界面遍历节点树)，把「装饰子节点误写 STOP」这类静默拦截回归变成 ✗ 拦在合并前；`visible=false` 节点自动排除避免误报。
- **B 路线迁移回归**：界面从 `X.new()` 迁 .tscn 后，单测仍用 `X.new()` 构造会静默丢属性 → 测试改 `preload(x.tscn).instantiate()`；`instantiate()` 返回 Node 致类型推断失效需显式类型。

## Godot 本机验证铁律（必记）
- console：`C:\Users\Administrator\.workbuddy\binaries\godot\Godot_v4.7.2-stable_win64_console.exe`
- 双闸门：① `--headless --path "D:/武侠游戏" --quit` 零 SCRIPT/PARSE/COMPILE ERROR；② **`res://tests/unit/run_all.tscn`** 零 `✗`（⚠️ 正确路径是 `tests/unit/run_all.tscn`，不是 `tests/run_all.tscn`！误用后者会报 Cannot open file 让 GATE2 根本没跑）。
- ⚠️ 两条 Windows 致命：① ROOT 必须 Windows 风格 `D:/武侠游戏`（POSIX `/d/xxx` 让 Godot 静默不跑→门禁误报绿）；② `get_tree().quit(code)` 退出码不传播→以 `✗` 判成败。
- ⚠️ GATE2 盲点：套件自身 Parse Error 时不打印任何 `✗` → **判绿必须同时满足** `grep -c "✗"`==0 **且** `套件：通过 N · 失败 M` 的 M==0。
- ⚠️ 沙箱 git 写不落盘：git checkout/rm/stash 是空操作；恢复用 `git show HEAD:<path> > <path>`（重定向落盘）。**验证前必须 commit 新/改文件**，否则 Godot（沙箱给 git-HEAD 快照）看不到 untracked/未提交改动→报"数据文件不存在"。
- ⚠️ .godot 缺失=双闸门全崩（class_name 全报 not declared）→ unsandboxed `godot --headless --editor --quit` 重建。多 Godot 进程抢 `.godot` 缓存→验证串行；门禁统一 unsandboxed 跑。

## 纹理压缩铁律（2026-09-02 立，必记）
- **本项目对 2D 纹理的「出厂默认」就是 `compress/mode=0`（未压缩）**，不是 Godot 默认的压缩。删 `.import` 让 Godot 重导仍回 mode=0 → 必须显式改 `mode=2` 才压缩。
- **双保险机制（已落地，用户硬性要求）**：① 工作室 `tools/desktop_studio/tscn_assets.py` 的 `write_import` 写死 `mode=2`+`size_limit=2048`；② 本地/LocalSend/拖拽导入走 `tools/compress_textures.py`（扫 assets/+resources/ 改 mode=0→2+限速+删 .ctex 强制重导，跳过 `_backup`，支持 `--dry-run`）。两条都覆盖才真双保险。
- **重导铁律**：手改 `.import` 参数**不**触发 Godot 重导（仅源 md5 变或缺 .ctex 才重导）；改完必须 `godot --headless --editor --quit --path "D:/武侠游戏"` 全量重导生成 .ctex，否则仍按旧缓存加载。
- **项目级默认预设失效**：`.godot/imports/texture.import` 在 Godot 4.7 不识别（新图仍 mode=0），别再尝试此路线。
- **取像素铁规**：压缩纹理（`CompressedTexture2D`）的 `get_image().get_pixel()` 会刷屏 `Can't get_pixel() on compressed image` 拖死主线程。要取像素必须用 `Image.load_png_from_buffer(FileAccess.get_buffer(...))` 解码源 PNG（跨 4.x 稳定）；`Image.load_from_file` 在 4.7.2 已非实例方法（Parse Error）。
- **真凶教训**：把纹理改压缩后暴露的 latent bug（`UIBackground._sample_edge_stops` 取像素）才是"进主菜单卡死"的真因，不是"巨图 TDR"（用户 RTX 3070 Ti 8GB，引擎在跑）。诊断卡死先看日志刷屏量，别臆测硬件。

## 主权边界
- 共享地基（冻结，只增不改）：EventBus.gd / ConfigManager.gd / core/enums/*_enums.gd / screens.json / strings.csv。改须写《变更通告》「共享地基增量」并打招呼。
- UI 窗口：`scenes/ui/**` + `data/configs/ui/**` + `core/constants/ui_theme.gd` + `resources/themes/**` + `autoload/ui_manager.gd`。战斗/背包/结缘窗口各有主权，跨窗只派单不直改。

## 多 AI 协同（变更纪律 · 2026-09-02 立，必记）
- **总文档**：`docs/多AI协同机制_SOP.md`；**skill**：`change-tracking`（每次改/提交/修 BUG 自动遵守）。
- **铁律 1 留痕**：任何文件修改提交前 `python tools/change_log.py add --commit <sha> --module <顶层模块> --scope <含子路径> --what "..." --impact "..." --ref "..."`；共享地基/跨主权/大改动额外 `change_log.py notice` 生成 `docs/变更通告_YYYY-MM-DD_主题.md`。`docs/更改日志.md` 已从 git 历史回填（191 行），立即可查。
- **铁律 2 调前先查**：接到任何 BUG，**先** `change_log.py query --module <模块>`（或 `--keyword <文件名>`）+ `git log -- <文件>` + `handoff.py dashboard`，确认不是别人刚改的回归再深入。命中则在 changelog「关联」注「回归自 `<commit>`」并 handoff issue 给责任窗口。禁"不查日志直接改"（真实教训：误删 town.json 当死数据，查日志秒定位其为战术底图几何依赖）。
- **铁律 3 提交/push**：双闸门通过才 commit（禁`-A`、带`[模块]`前缀、窗口署名 `git config user.name "AI-<窗>"`）；无 BUG 的改动**必须 commit**留痕；push 由 PM/集成窗口整树双闸门全绿后统一推（单分支禁各窗盲目 push 互覆盖）。
- **铁律 4 门禁非绿即阻断**：GATE1/GATE2 一旦非绿（有 SCRIPT/PARSE/COMPILE ERROR 或 ✗），**立即修、禁止带红门禁继续开发或合并**；红门禁是「别人刚改崩」的最强信号，优先级高于任何新功能。本次教训：`BattleScene.gd _on_auto_pressed` 缩进错（`eid` 在 for 外）早已解析失败致 GATE2 红，却长期没人管。
- 提交队列 `tools/commit_queue.py` + 隐患传递板 `tools/handoff.py`（open→claimed→done→followup→closed；/ 被 sanitize 成 _）。
- `change_log.py` 纯标准库（本机托管 Python：`C:/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe`），命令 `add/notice/query/backfill`；`query --module` 匹配模块列与范围列，`--keyword` 匹配任意列。

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
- ⚠️ **更新交付 SOP（用户 2026-09-01 硬性要求，每次更新都要做）**：重打包/更新工作室 exe 后，必须自己先——① 清 8765 端口上**所有**旧进程（`Get-NetTCPConnection -LocalPort 8765` 取 PID → `Stop-Process -Force`；常驻会堆积 10+ 个旧进程，浏览器连到旧代码误以为"没更新"）；② 重打包务必 `--clean`（否则复用旧 .pyc 缓存丢功能）；③ 同步**全部**副本——工程内 4 处 + 桌面 `Desktop\` + 外部 `D:\工作室专业调教\` + 野副本 `D:\studio_push_tmp\dist\` 与 `D:\武侠游戏\tools\dist\`（不止 4 处！）；④ 启动新 exe 并 `curl` 验证 `/api/tool_version` 的 md5 与 `/api/main_menu/assets` 可用，**确认用户真能用上新版**再交差。
- **tscn_assets.py（UI 贴图直写 .tscn，2026-09-01 新增）**：核心库扫描 35 界面/41 槽位，贴图写 ext_resource 进 .tscn。两条铁律——① ext_resource **不写 uid**（避免 invalid UID 警告）；② **不预生成 .import**（Godot 会信任残缺 .import 跳过导入→加载失败，交给 Godot 自动导入零风险）。ctex 命名 = `md5("res://" + rel_path)`。
