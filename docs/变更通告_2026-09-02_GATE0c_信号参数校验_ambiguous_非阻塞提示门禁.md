# 变更通告 2026-09-02 · GATE0c 信号参数校验 ambiguous 非阻塞提示门禁

> 模块：质量门禁/共享地基(pre-commit 钩子)　改动范围：tools/gate0c_ambiguous_warn.py tools/signal_audit.py tools/hooks/pre-commit　commit：（待提交后补）

## 变更项
pre-commit 新增 GATE0c（非阻塞提示门禁）：提交 .gd 时调用 signal_audit.py --json，提取同名信号跨类多签名冲突(ambiguous)导致的跳过 connect 清单并打印警告，exit 0 绝不拦截提交。signal_audit.py 增加 --json 结构化输出模式（不加 flag 时行为完全不变，仍 Exit 2/0）。

## 变更原因
signal_audit.py v5 已能识别「同名信号跨类多签名冲突（ambiguous）」——Godot 允许不同类声明同名 `signal confirmed` 但签名不同（如 ConfirmDialog.confirmed() 0 参 vs SaveNameDialog.confirmed(save_name: String) 1 参）。v5 对此类信号选择「跳过 DEFINITE 判定」避免永久假红，但代价是这些 connect 的参数个数**不再被校验覆盖**。若将来有人把参数写错，会因 ambiguous 被跳过而没被发现。
GATE0c 把这批「当前未被参数校验覆盖的 connect」在提交时打印成警告清单，提醒开发者人工核对——满足「让开发者知道这 4 处 connect 未被覆盖、避免将来写错参数却没被发现」的需求。性质为**非阻塞提示**，绝不拦截提交。

## 影响面
- 仅影响 pre-commit 钩子与 tools/ 下的审计脚本；**不涉及任何游戏运行时代码、EventBus 共享地基、或 .tscn/.gd 游戏文件**。
- GATE0a（mouse_filter 拦截）、GATE0b（信号契约拦截）逻辑未改动、仍照常拦截。
- 行为变化：提交 .gd 时，终端会多打印一段「【GATE0c · 非阻塞提示】」黄色警告（当前 4 处 confirmed 连接），但提交照常成功。
- 共享地基：本改动触及 pre-commit 钩子（机器级硬约束模板 tools/hooks/pre-commit），属协同基础设施；已按纪律走 change_log + 变更通告。

## 回滚方案
- 单文件回退即可，无数据/运行时影响：
  - `tools/hooks/pre-commit` 删 GATE0c 段（或 `git checkout` 到改动前版本），再 `python tools/install_hooks.py` 重新安装；
  - `tools/gate0c_ambiguous_warn.py` 可整体删除（钩子已做「脚本缺失则跳过」fail-open）；
  - `tools/signal_audit.py` 的 `--json` 分支可删除（不加 --json 时行为不变，删除零影响）。
- 应急绕过单条提交：`git commit --no-verify`（禁止常规使用）。

## 协同方需知
- 各窗口无需改动任何代码；重装/换机器后跑一次 `python tools/install_hooks.py` 即生效（钩子模板已含 GATE0c）。
- 看到 GATE0c 警告不必处理：它表示这些 connect 的参数校验被 ambiguous 跳过，属已知盲区；若要消除盲区，需统一同名信号签名或在 signal_audit 做按类细化（非本次范围）。
- 双闸门 GATE1/GATE2 不受影响，仍须全绿。
- 已知盲区提醒：参数个数不匹配的 DEFINITE 级隐患**当前没有拦截门禁**（GATE0b 是「无生产方死信号」基线模式，不查参数个数；GATE0c 只提示 ambiguous 跳过项）。若该盲区需要拦截，另行立项。

## 关联
- commit：（待提交后补，由 PM/背包窗口 commit_queue flush 落地）
- 上游：signal_audit.py v5（同名信号跨类多签名冲突 ambiguous 跳过，2026-09-02）
- changelog：docs/更改日志.md
- 本批入队 entry：（待 commit_queue add 生成）
