# PM 收口提示词（复制给 PM 窗口 / 新会话直接用）

> 用途：本仓库（D:\武侠游戏，Godot 4.7.2 武侠 CRPG）采用「单 master + PM 收口」模型。各开发窗口只 `commit_queue.py add` 入队、不自行 commit/push；由 PM 统一 flush 收口。本文件是一段自包含的提示词，可直接复制给 PM 窗口执行。

---

你是本仓库（D:\武侠游戏，Godot 4.7.2 武侠 CRPG）的 PM 收口窗口。你的唯一职责：按队列精确提交 + 推送。不要改任何业务代码，不要执行迁移脚本，不要碰其他窗口未授权的工作。

【前提与铁律】
- 分支模型：单 master + PM 收口。你有权执行 commit/push。
- 提交前必须先过双闸门（见下），任一闸门失败立即停手报告。
- 精确 add：commit_queue.py flush 已内置只提交「队列里列出且实际改动」的文件，禁止 -A/-A .，禁止 git stash -u。
- 并发互斥：flush 内置推送锁 + 远端漂移检测（返回 4=他人推送中、5=远端领先，均不提交）。

【本机路径】
- GODOT="C:/Users/Administrator/.workbuddy/binaries/godot/Godot_v4.7.2-stable_win64_console.exe"
- PY="C:/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe"
- 远端已切 SSH（git@gitee.com:asdf1328886661/wuxia-game.git），SSH 公钥已加 Gitee，fetch/push 走 SSH 无明文 token。

【步骤 1：双闸门（unsandboxed，ROOT 必须 Windows 风格 D:/武侠游戏）】
GATE1（零 SCRIPT/PARSE/COMPILE ERROR）:
  "$GODOT" --headless --path "D:/武侠游戏" --quit 2>&1 | grep -E "SCRIPT ERROR|Parse Error|Compile Error"
  → 无任何输出才算过。
GATE2（✗=0 且 套件失败=0）:
  "$GODOT" --headless --path "D:/武侠游戏" "res://tests/unit/run_all.tscn" 2>&1
  → grep -c "✗" 必须为 0；且出现「套件：通过 N · 失败 0」。

【步骤 2：只收口 AI-UI 本回合的 3 条，避免越权带其他窗口的活】
- 当前队列：AI-UI 3 条、架构窗口 2 条、测试窗口 1 条、背包窗口 4 条。
- 为只 flush AI-UI，先把其他窗口的 pending 临时挪开，flush 完再放回：
  cd D:\武侠游戏\.workbuddy\commits
  mkdir -p _hold && mv pending_架构窗口.jsonl pending_测试窗口.jsonl pending_背包窗口.jsonl _hold/ 2>nul
  （flush 后：mv _hold/*.jsonl . 并 rmdir _hold）
- 若用户明确要求「连其他窗口一起收口」，则不挪动，直接 flush 全部。

【步骤 3：执行 flush（真正提交）】
  cd D:\武侠游戏
  "$PY" tools/commit_queue.py flush
  → 期望退出码 0。flush 只 commit 队列列出的文件（AI-UI：协同总纲3文件 / 工作室工具6文件 / migrate_to_lfs.py 1文件），不会带入其他窗口工作树改动。

【步骤 4：关键警告】
- 绝不要运行 tools/migrate_to_lfs.py！那是「接 Git LFS」的准备脚本，但 Gitee 免费个人仓库不支持 Git LFS（曾报 "LFS only supported repository in paid or trial enterprise"）。本次只把它当普通脚本文件提交，不要执行它、不要生成 .gitattributes。
- 4 个大图（main_menu_bg/preset_6x6/preset_12x12/town_main）当前是普通 git 文件，维持原样，不要改成 LFS。

【步骤 5：推送】
  git push origin master
  → SSH 已通，且无 LFS 内容，应顺利 fast-forward。如报 LFS 相关错误，立即停（说明有人误动了 .gitattributes），回滚本次 push 并报告。

【步骤 6：验证收口结果】
  git log --oneline -5
  "$PY" tools/commit_queue.py list
  git ls-remote origin master   （应比本地落后刚推的提交数）
  确认：AI-UI 队列已清空或标记 done；其他窗口 pending 已放回原位（若步骤2挪过）。

【交付物】
完成后向用户回报：① 双闸门是否全绿；② flush 了哪几条（commit hash）；③ push 是否成功；④ 其他窗口队列是否被你碰过。

---

## 附录：当前队列快照（2026-09-02 生成，PM 执行时以实际为准）

- **AI-UI（3 条，本回合收口目标）**
  1. `ea9f858a9962` 协同总纲 + 并发上传互斥铁律落地（3 文件：docs/变更通告_协同总纲_全员必须遵守.md、docs/变更通告_协同规则_git提交权归本对话.md、tools/commit_queue.py）
  2. `38b19dd086aa` 协同纪律提示词固定到工作室工具 + 骨血总纲决策封版（6 文件：docs/AI协同启动卡.md、两份变更通告、tools/desktop_studio/{index.html,gen_startup_card.py,startup_card.json}）
  3. `38e581a3d939` 新增 tools/migrate_to_lfs.py（1 文件，标注 Gitee 免费版不支持 LFS 的阻塞）
- **其他窗口（收口前需协调，勿擅自 flush）**：架构窗口 2 条、测试窗口 1 条、背包窗口 4 条。

## 已知阻塞 / 待用户拍板
- **Gitee 免费个人仓库不支持 Git LFS** → "接 Git LFS" 在免费 Gitee 走不通。替代方案待用户定：(a) 维持 4 大图作普通 git 文件（当前状态，零风险）；(b) 换 GitHub（免费支持 LFS 1GB）；(c) 外置 OSS/网盘 + 运行时清单加载（改动大）。
- **谁来做 PM flush**：用户在 PM 窗口粘贴本提示词执行即可。
