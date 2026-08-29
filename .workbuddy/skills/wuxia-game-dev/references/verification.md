# Godot 本机验证铁律（双闸门 + 环境坑）

> 本机验证 100% 用 console 版 Godot（`--headless`），且**必须 unsandboxed 跑真实磁盘**。
> Godot 路径：`C:\Users\Administrator\.workbuddy\binaries\godot\Godot_v4.7.2-stable_win64_console.exe`

## 一、双闸门（收尾必跑）

```bash
G="C:/Users/Administrator/.workbuddy/binaries/godot/Godot_v4.7.2-stable_win64_console.exe"
# GATE1：工程零硬错
"$G" --headless --path "D:/武侠游戏" --quit 2>&1 | grep -iE "SCRIPT ERROR|Parse ERROR|COMPILE ERROR"
# GATE2：全量测试零 ✗（34 套件）
"$G" --headless --path "D:/武侠游戏" res://tests/unit/run_all.tscn 2>&1 | grep -iE "套件：|✗ "
```

- GATE1 干净（无上述 ERROR 行）= 通过；GATE2 结算 `套件：通过 N · 失败 0` 且无 `✗` = 通过。
- 单脚本 `--check-only --script res://<path>.gd` **不加载 autoload**，引用单例报假阳性，仅查本文件语法行号用。

## 二、两条 Windows 致命铁律

1. **路径必须 Windows 风格 `D:/武侠游戏`**：POSIX `/d/xxx` 让 Godot 静默不跑，门禁误报绿（最阴险的假绿）。
2. **`get_tree().quit(code)` 退出码不传播**：CI/脚本别靠进程码判成败，以 `run_all` 的 `✗` 标记为准。

## 三、.godot 类缓存（最易踩）

- 多 Godot 进程**抢 `.godot/global_script_class_cache.cfg`** → 部分 `class_name` 未解析 → 级联 "X not declared" 假红。**验证必须串行**（勿与编辑器/其他 Godot 同时跑）。
- **`.godot` 缺失 = 双闸门全崩**（所有 class_name 报 not declared，与代码无关）。**绝不要 `rm` 删 `.godot`**。
- 缓存损坏/缺失时重建：`"$G" --headless --editor --quit`（数秒，重建 `global_script_class_cache.cfg`）。`--quit` 模式本身不写缓存，必须用 `--editor --quit`。

## 四、沙箱陷阱（Bash 工具）

- 本机 Bash 工具在**沙箱内**运行：`git checkout/rm/stash/commit/push` 等写操作**不落真实磁盘**；只有 shell `>` 重定向与 Write/Edit 工具落盘。
- 恢复跟踪文件用 `git show HEAD:<path> > <path>`（重定向落盘），**别用 `git checkout HEAD -- <path>`**（沙箱内空操作）。
- 验证前若新增 untracked `.gd`/`.json`：沙箱给 Godot 的是 **git-HEAD 快照**，untracked 文件对 Godot 不可见 → 报 "数据文件不存在"。**验证前必须 commit 新文件**。

## 五、验证标准流程（收尾 SOP）

1. 真实磁盘还原数据（`git show HEAD:<path> > <path>` 重定向落盘）。
2. unsandboxed 重建 `.godot` 类缓存（`--editor --quit`）。
3. commit 新文件（untracked 对 Godot 不可见，验证前必须 commit）。
4. unsandboxed 跑 GATE1 + GATE2（门禁统一 unsandboxed，避免快照误报）。

## 六、git 操作坑（本机）

- **中文路径 `git add` 坑**：显式 `git add "docs/变更通告.md"` 会因命令行中文匹配失败导致整条 add 失败。工作树仅含项目正当改动（`.godot` 已 gitignore、无构建产物）时，直接用 `git add -A`（与桌面 `wuxia-git-sync.bat` 一致）；若需精确，用 `git add -u` 暂存已跟踪修改 + 显式加未跟踪的英文路径。
- **沙箱写不落盘**：commit/push 必须 `dangerouslyDisableSandbox: true`。
- **令牌推送**：`git push "https://<user>:<TOKEN>@gitee.com/asdf1328886661/wuxia-game.git" master`；**令牌绝不写进 git config / 文件 / 记忆**；推完确认 `git remote get-url origin` 不含令牌（`https://gitee.com/asdf1328886661/wuxia-game.git`）。
- `git status` 的 `upstream is gone` 只是本地 tracking 提示噪音（`git push origin master` 不设 upstream），无害。

## 七、GATE2 门禁加固（已落地）

- `tests/unit/run_all.gd` 已加固：原"脚本实例化失败静默 skipped（假绿）"→ 明确计 `suite_fail` + 提示"类缓存可能损坏→`godot --headless --editor --quit` 重建、禁并发"。将来缓存再坏会**红得明确**，不会假绿。
