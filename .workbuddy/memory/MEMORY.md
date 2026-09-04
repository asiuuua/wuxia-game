# 武侠江湖 项目记忆（精简主线）

## 定位与锁定
- 等距 2.5D 武侠 RPG 单机；Godot **4.7.2**；纯 GDScript；个人开发（用户新手）。实际代码纯 2D。战斗回合制+自动；平台 Win+安卓；世界区域枢纽式。

## 架构铁律
`autoload→core→data→services(RefCounted)→scenes→resources/tests/tools`。四底线：单向依赖 / 跨模块只走 EventBus / 数值全进 JSON / 命名见名知意。

## GDScript 4.x 硬规（必记）
- `Color()` 必须写满 4 参；typed Array 禁 `as Array[String]`；`mini/maxi` 仅 2 参。
- 闭包按值捕获值类型；解析外部配置用 `JSON.new()` + `json.parse(txt) != OK`。
- **mouse_filter 枚举反直觉**：STOP=0(拦截) / PASS=1 / IGNORE=2(穿透)。装饰子节点必须写 IGNORE(2)，绝不可写 0。
- **自动守卫已落地**：git pre-commit 钩子（真实源 `tools/hooks/pre-commit`，`python tools/install_hooks.py` 安装到 `.git/hooks/pre-commit`）含三道门禁：
  - 【GATE0a·拦截】`tools/lint_mouse_filter.py` 扫 mouse_filter=STOP(0) 装饰子节点（静默吞点击）；
  - 【GATE0b·拦截】`tools/audit_signal_contract.py` + `tools/audit_signal_baseline.json` 查 EventBus 无生产方死信号/未声明引用（基线模式，只拦新增）；
  - 【GATE0c·非阻断】`tools/gate0c_ambiguous_warn.py` 调 `tools/signal_audit.py --json`，提交 .gd 时打印 ambiguous 跳过 connect 清单作警告，exit 0 不拦截。
  - 另有 `tests/unit/test_ui_mouse_filter.gd`(GATE2 运行时断言)。四层 Enforcement：记忆→skill→启动卡口令→机器兜底。

## Godot 本机验证铁律
- console 路径；双闸门：①`--headless --path "D:/武侠游戏" --quit` 零 SCRIPT/PARSE/COMPILE ERROR；② `res://tests/unit/run_all.tscn` 零 ✗。
- ROOT 必须 Windows 风格；GATE2 判绿须同时满足 grep ✗==0 且 失败 M==0。
- 沙箱 git 写不落盘；验证前必须 commit；.godot 缺失=全崩。

## 纹理压缩铁律
- 项目出厂默认 mode=0（未压缩）；双保险：tscn_assets.py 写死 mode=2 + compress_textures.py 扫描改 mode=0→2。
- 取像素必须用 `Image.load_png_from_buffer` 解码源 PNG，不可对压缩纹理 get_pixel。

## 主权边界 & 多 AI 协同
- 共享地基冻结；UI/战斗/背包/结缘各有主权。
- 四铁律：留痕(change_log)、调前先查、双闸门才 commit(窗口署名)、门禁非绿即阻断。
- 提交队列 commit_queue.py + 隐患传递板 handoff.py。

## UI / B 路线
- 全量 .tscn 化已收官 2026-08-31；screens.json 21 项全 .tscn。

## 工作室工具（tools/desktop_studio）
- Python http.server + 单页 SPA；PyInstaller 打包 exe；安全红线（127.0.0.1 绑定、_is_valid_id 白名单、ZIP 校验、Origin 防护、security_selftest 15 断言）。
- **运行形态分清（2026-09-02 踩坑纠正）**：① **源码模式=用户日常用法**：双击 `tools/desktop_studio/studio_launcher.bat`（= `python studio_server.py`），直接读磁盘 `index.html`/`startup_card.json`，**改完刷新即时生效，无需重打包**；② **发行版 exe** 才需 PyInstaller 重打包（仅出发行版/发给用户时）。AI 改完工具相关文件应跑源码模式验证；**绝不要 kill 用户正在运行的源码服务再裸起 exe**，否则用户"看不到"工具。详见 `desktop-studio-exe-rebuild` skill（已修：源码模式优先）。
- **更新交付 SOP（仅出发行版 exe 时）**：清旧进程 → --clean 重打包 → 同步全部副本(6处+) → curl 验证 md5。
- tscn_assets.py：UI 贴图直写 .tscn（不写 uid、不预生成 .import）。
- **「更新到最新版」标准动作（2026-09-03 踩坑）**：工作树 `tools/desktop_studio/` 易被**混合未提交改动污染**（如 index.html 被回退成旧界面、但 .py 挂着半成品新逻辑），导致双击 bat 闪退。最新版在 git HEAD（`ed782d9`/`f35c2f5` 操作日志浮窗界面）。判定"版本不对"→ 直接 `git checkout HEAD -- tools/desktop_studio/` 还原工作树到 HEAD 即是最新版；HEAD 服务端自带端口顺延(8765→8785)+浏览器自动打开，本就满足"不走端口"。验证：`python -u studio_server.py` 看"已启动"日志 + curl 端口 HTTP 200。
- **「开发完必须释放」铁律（2026-09-03 用户痛点·闪退根因）**：每次改完 `tools/desktop_studio/` 源码，**不释放 = 用户双击 bat 闪退**。根因有两层：① 我们后台跑的测试服务进程没关，占着 876x 端口；② 工作树被改成半成品/混合状态（`import` 失败或运行时报错）→ 黑窗口闪退、浏览器不开。**收尾三件事（缺一不可）**：① **kill 自己起的测试服务**（后台 `python -u studio_server.py` 验证完立刻关掉，释放端口，绝不留残留进程）；② **工作树不留混合改动**——纯验证性改动验证后即 `git checkout HEAD -- tools/desktop_studio/` 还原；真实功能改动须确保 `import` 不报错再收尾；③ **收尾前跑一次启动验证**（看"已启动"日志 + curl HTTP 200）证明双击能用。**已加固**：`studio_launcher.bat` 加自愈合（双击先 PowerShell kill 任何残留 studio 进程再启动）；`studio_server.py` 启动入口加 try/except 兜底（出错打印真实 traceback 并停留，不再闪一下没）。用户视角：双击即用、端口被占自动顺延、万一真崩能直接看到错误。
- **平台本质再定位（2026-09-02 用户拍板）**：平台=**连接器而非容器**，只对接工程、不持有工程数据；三大复用能力 = ai_context(新AI秒懂架构) + reskin(换皮零成本) + knowledge(经验复用)。二维解耦：横向 Domain Module × 纵向 Project Adapter(manifest.yaml)。远程访问(Phase 4)**已决策延后**（紧迫度极低）。本地化应用：端口自动顺延(8765被占试+20)，用户免调端口。
- **反哺留存铁律（2026-09-02 用户纠正）**：连接器不持有工程项目数据（源码/美术/配置不进平台），但**从工程提炼的经验与数据反哺必须留存并 git 进仓库**——docs/经验库、docs/模块卡、更改日志.md、代码审计报告均随仓库走，周期经「平台反哺层」升级为 Lint/模板/插件/脚手架，凝练反哺工作室平台。连接器范式与留存反哺不矛盾：平台不替工程存数据，但工程沉淀的「方法论资产」必须留存并随仓库演进。
- **经验库增强检索（2026-09-02 落地，续篇第十一章#4）**：`/api/experience` 返回前由 `_exp_enrich()` 实时富化 `knowledge.refs`——角色/模块分面优先取每篇子文档「检索关键词」行(权威意图)，BUG 号从全文显式提取(无歧义)；零 schema/零文档改动。前端加标签云+角色/模块/BUG 分面过滤(组内OR/组间AND)+变更通告默认隐藏开关。踩坑：① `docs/变更通告_*.md` glob 展开出 79 篇会淹没核心知识→标记 `group=notice` 前端默认隐藏+勾选显示；② 标签云/分面只统计核心知识避免污染；③ 派生词表用短语级匹配(禁裸 `ui`/`平台`/`tscn`/`数据` 短串，否则过度赋值)；④ glob 绝对路径须 `os.path.relpath` 归一化正向斜杠，否则 `/api/experience/doc` 拼错。

## Git LFS 与大媒体 / 远端鉴权（2026-09-02 落地）
- 用户决策「大媒体外置 + 引入 Git LFS」。assets/ 123MB：~50MB 的 `_backup_hires`/`_jpg_backup` 高清备份本就在 .gitignore（未进版本库）；4 个经 res:// 加载的 runtime 大文件（main_menu_bg / preset_6x6 / preset_12x12 / town_main，~14.6MB）已转 Git LFS 指针（.gitattributes + `git lfs track`），大 blob 存 `.git/lfs/objects`，不再进 git 对象库。
- **git-lfs 安装位置**：`C:\Users\Administrator\.workbuddy\binaries\PortableGit\versions\1.2.0\mingw64\bin\git-lfs.exe`（v3.8.0），与 git 同目录；`git lfs install --local` 已装钩子。注意本机 git 实际是 PortableGit（非 `binaries/git/`），路径别找错。
- **远端：GitHub 为唯一 remote（origin），Gitee 本地 remote 已删除（2026-09-02 末）**。`origin` = `git@github.com:asiuuua/wuxia-game.git`（承载代码 + 4 个大图 LFS）。`git remote -v` 已确认只剩 origin，无 gitee。Gitee 网站上的旧仓库仍在（删 remote 不动云端），如要彻底消失需用户去 Gitee 网页删仓库。ed25519 密钥 `~/.ssh/id_ed25519` 同一把已加进 Gitee 和 GitHub（公钥 `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHvWbllPSi1tSJUQoavJaFt7Cil0tih76qjHbrzJNqGA wuxia-game@local`）。旧 token `03e77e1503a846d796c01921f37f7dd3` 仍有效、须用户在 Gitee 吊销（已不用于任何 remote URL）。
- **全量迁移已完成（2026-09-02 收尾）**：GitHub(origin) master = `7981d8c`，是 Gitee(`2a2a10e`) 的超集（Gitee 的 ef95a2e+2a2a10e 提交都在 GitHub 历史里），且含 4 个大图 LFS（4/4 已传 GitHub LFS，endpoint `github.com/asiuuua/wuxia-game.git/info/lfs`）。`git push origin master` 已为 up-to-date。Gitee 上少了 LFS 那 1 个提交（因 Gitee 免费版不支持 LFS，不推是对的）。从此默认 `git push/pull` 走 GitHub。工作树仍为真实 PNG，`res://` 加载不受影响。
- 准备脚本 `tools/migrate_to_lfs.py`（两护栏：git-lfs 已装 + 远端无明文 token；`--rewrite-history` 可清历史需 force-push）。

## 当前 open 派单
- (2026-09-02 结缘窗口对账) 结缘相关两项已闭环：178267684159(休息推进天数，结缘源窗 close，生产驱动 948d146 已落地) / acf2246fd5f2(propose 聘礼锁定，UI 修+结缘对账确认) 均已 done/closed；BondRomanceScreen debug 按钮已清。战斗→town 掉血崩(old fed3f00da584)在板亦已 [closed]。

## 架构整改收官（2026-09-04，P0-P5 全部完成）
- **一键验证铁律**：提交前 `python tools/verify_all.py` 六门禁（headless零错/单测全绿/工程规范基线/预设红线/双写防线/引用校验）；GATE1 自愈重建类缓存。
- **新增 Core 原语**：ConditionService（core/condition.gd，统一条件 DSL + GameFacts 适配器）、CommandDispatcher（core/command_dispatcher.gd，"cmd:arg" 注册表路由）。新增条件/命令/目标/奖励类型=注册 handler+写数据，不改核心服务。
- **真源裁定**：区域唯一注册表=regions/_map_index.json v2（区域ID=传送ID=分片ID）；NPC 唯一真源=regions/<rid>/npcs.json；好感唯一真源=BondService；town_npcs.json/world regions.json 已退役。任务链驱动：prerequisites 前置门 + then_set 回写。
- **引用反查**：`python tools/ref_index.py --who <id>` 查被谁引用；悬空引用 GATE6 阻断。
- 坑：新 class_name 必须 --import 重建缓存；Git Bash 中文 pathspec 用目录级 add 绕过；Godot 缺 USERPROFILE/APPDATA 时 user:// 变相对路径（verify_all 已根治）。
