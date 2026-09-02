# 武侠江湖 项目记忆（精简主线）

## 定位与锁定
- 等距 2.5D 武侠 RPG 单机；Godot **4.7.2**；纯 GDScript；个人开发（用户新手）。实际代码纯 2D。战斗回合制+自动；平台 Win+安卓；世界区域枢纽式。

## 架构铁律
`autoload→core→data→services(RefCounted)→scenes→resources/tests/tools`。四底线：单向依赖 / 跨模块只走 EventBus / 数值全进 JSON / 命名见名知意。

## GDScript 4.x 硬规（必记）
- `Color()` 必须写满 4 参；typed Array 禁 `as Array[String]`；`mini/maxi` 仅 2 参。
- 闭包按值捕获值类型；解析外部配置用 `JSON.new()` + `json.parse(txt) != OK`。
- **mouse_filter 枚举反直觉**：STOP=0(拦截) / PASS=1 / IGNORE=2(穿透)。装饰子节点必须写 IGNORE(2)，绝不可写 0。
- **自动守卫已落地**：`tools/lint_mouse_filter.py`(GATE0 静态扫描) + `tests/unit/test_ui_mouse_filter.gd`(GATE2 运行时断言) + git pre-commit 钩子。四层 Enforcement：记忆→skill→启动卡口令→机器兜底。

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
- **更新交付 SOP**：清旧进程 → --clean 重打包 → 同步全部副本(6处+) → curl 验证 md5。
- tscn_assets.py：UI 贴图直写 .tscn（不写 uid、不预生成 .import）。
- **平台本质再定位（2026-09-02 用户拍板）**：平台=**连接器而非容器**，只对接工程、不持有工程数据；三大复用能力 = ai_context(新AI秒懂架构) + reskin(换皮零成本) + knowledge(经验复用)。二维解耦：横向 Domain Module × 纵向 Project Adapter(manifest.yaml)。远程访问(Phase 4)**已决策延后**（紧迫度极低）。本地化应用：端口自动顺延(8765被占试+20)，用户免调端口。
- **反哺留存铁律（2026-09-02 用户纠正）**：连接器不持有工程项目数据（源码/美术/配置不进平台），但**从工程提炼的经验与数据反哺必须留存并 git 进仓库**——docs/经验库、docs/模块卡、更改日志.md、代码审计报告均随仓库走，周期经「平台反哺层」升级为 Lint/模板/插件/脚手架，凝练反哺工作室平台。连接器范式与留存反哺不矛盾：平台不替工程存数据，但工程沉淀的「方法论资产」必须留存并随仓库演进。
- **经验库增强检索（2026-09-02 落地，续篇第十一章#4）**：`/api/experience` 返回前由 `_exp_enrich()` 实时富化 `knowledge.refs`——角色/模块分面优先取每篇子文档「检索关键词」行(权威意图)，BUG 号从全文显式提取(无歧义)；零 schema/零文档改动。前端加标签云+角色/模块/BUG 分面过滤(组内OR/组间AND)+变更通告默认隐藏开关。踩坑：① `docs/变更通告_*.md` glob 展开出 79 篇会淹没核心知识→标记 `group=notice` 前端默认隐藏+勾选显示；② 标签云/分面只统计核心知识避免污染；③ 派生词表用短语级匹配(禁裸 `ui`/`平台`/`tscn`/`数据` 短串，否则过度赋值)；④ glob 绝对路径须 `os.path.relpath` 归一化正向斜杠，否则 `/api/experience/doc` 拼错。

## 当前 open 派单
- (2026-09-02 结缘窗口对账) 结缘相关两项已闭环：178267684159(休息推进天数，结缘源窗 close，生产驱动 948d146 已落地) / acf2246fd5f2(propose 聘礼锁定，UI 修+结缘对账确认) 均已 done/closed；BondRomanceScreen debug 按钮已清。战斗→town 掉血崩(old fed3f00da584)在板亦已 [closed]。
