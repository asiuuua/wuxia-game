# 多 AI 协同协议

> 项目采用"提交队列 + 隐患传递板"双板协同，多 AI 并行开发同一仓库。核心目标：各窗只产代码，git 写操作统一收口，跨窗只派单不直改。

## 一、主权边界（谁能动什么）

- **共享地基（冻结，只增不改）**：`EventBus.gd` / `ConfigManager.gd` / `core/enums/*_enums.gd` / `screens.json` / `strings.csv`。改动须写《变更通告》「共享地基增量」表并**打招呼**（通知其他窗口 owner）。
- **UI 窗口主权**：`scenes/ui/**` + `data/configs/ui/**` + `core/constants/ui_theme.gd` + `resources/themes/**` + `autoload/ui_manager.gd`。
- **战斗/背包/结缘/装备/武学/任务窗口**各有主权；跨窗协作**只派单不直改**对方文件。

## 二、git 提交规范

- 提交信息前缀：`[窗名]`（如 `[UI模块]` `[背包窗口]` `[战斗]` `[协同]`）。
- 精确 `git add <文件>`（项目铁律禁 `-A`）；仅当工作树 100% 为项目正当改动（无垃圾/构建产物）时才可接受 `git add -A`。
- 各窗只产：代码 + 双闸门绿 + 写《变更通告》。动接口（新增/改 signal、函数签名）→ 重跑 `gen_contract.gd` 更新 `docs/契约总表.md`。
- 提交权统一收口 UI 模块（历史约定）；其他窗口按各自派单产出。

## 三、提交队列 `tools/commit_queue.py`

- 用途：把 `git add` 队列化（`pending_<窗>.jsonl`，已 gitignore），每小时自动化出队提交，避免并行 AI 互相冲掉暂存。
- 各窗把待提交文件写入自己窗口的 pending jsonl；调度器按队列出队。
- 手动提交仍可用 `git commit`（遵循前缀与精确 add 规范）。

## 四、隐患传递板 `tools/handoff.py`

- 状态机：`open` → `claimed` → `done` → `followup` → `closed`。
- 跨窗派单：源窗口开 `open` 派单，目标窗口 `claim` 后处理，`done` 后源窗确认 `closed`；有后续再 `followup`。
- **派单与扫描窗口名须一致**：路径中的 `/` 会被 sanitize 成 `_`（如 `UI/菜单` → `UI_菜单`）。
- 派单号形如 `fed3f00da584`（短哈希），用于跨 AI 追踪。

## 五、变更通告

- 每次收口产出《变更通告_`日期`_`模块`.md》，记录：改了什么、双闸门结果、共享地基增量（若有）、待办/派单号。
- 文档位于 `docs/`（项目已有约 80 个变更通告/接管日志/设计文档），是权威历史；新 AI 认领前先 Read 对应模块通告。

## 六、令牌推送（本机无凭据时的推送方式）

- 用临时 push URL：`git push "https://asdf1328886661:<TOKEN>@gitee.com/asdf1328886661/wuxia-game.git" master`。
- `<TOKEN>` 由用户经对话提供，**绝不写入 git config / 文件 / 记忆**；推完 `git remote get-url origin` 应为无令牌的 `https://gitee.com/asdf1328886661/wuxia-game.git`。
- 桌面 `wuxia-git-sync.bat` 是用户端一键提交推送（内部 `git add -A` + `git commit` + `git push origin master`），但需用户本机凭据；AI 代推用上述临时 URL 法。

## 七、协同避坑

- 并行开发**勿并发跑 Godot 验证**（抢 `.godot` 缓存，见 references/verification.md）。
- 派单认领后先 `claimed`，避免两 AI 抢同一项。
- 冻结文件改动必须先写《变更通告》"共享地基增量"并通知，否则其他窗口编译会崩。
