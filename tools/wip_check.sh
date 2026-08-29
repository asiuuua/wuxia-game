#!/usr/bin/env bash
# wip_check.sh — 并发编辑 / 在途 WIP 守卫
# 背景：本项目多窗口协作，曾发生"两个窗口同时改同一文件导致缩进损坏"的踩踏事故。
# 本脚本列出当前未提交、且触碰"共享地基/跨窗口配置"的文件，提交前跑一遍预警。
# 仅作提示（退出码 0），不阻断；真正拦截靠人工复核 + gate_check.sh。
# 用法：bash tools/wip_check.sh [project_root]
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-$(cd "$HERE/.." && pwd)}"
cd "$ROOT" || exit 1

# 高风险目录：多人/多窗口会同时改的共享面
RISKY="autoload/|core/|data/configs/|services/|tools/gen_contract"
echo "=== 在途 WIP 守卫：共享/跨窗口配置改动 ==="
hits=$(git status --porcelain | grep -E "^ M|^M |^??|^\?\?" | sed 's/^[^ ]* //' | grep -E "$RISKY" || true)
if [ -z "$hits" ]; then
  echo "  无共享/跨窗口配置在途改动"
else
  echo "  以下文件在途未提交，且属共享/跨窗口面，提交前请确认无并发编辑踩踏："
  echo "$hits" | sed 's/^/    - /'
  echo "  建议：改完立即 精确 git add <file> && git commit；勿用 -A 卷入他人在途文件。"
fi
exit 0
