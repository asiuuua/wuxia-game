#!/usr/bin/env python3
# tools/install_hooks.py
# 安装多 AI 协同的 git 钩子（机器级硬约束）。
# 把 tools/hooks/pre-commit 复制到 .git/hooks/pre-commit，使其对每次 commit 生效。
# 用法：python tools/install_hooks.py
import os
import shutil
import stat

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(REPO, "tools", "hooks", "pre-commit")
GIT_DIR = os.path.join(REPO, ".git")
DST = os.path.join(GIT_DIR, "hooks", "pre-commit")


def main():
    if not os.path.isfile(SRC):
        print("✗ 找不到源钩子：%s" % SRC)
        return 1
    if not os.path.isdir(GIT_DIR):
        print("✗ 不是 git 仓库根目录（找不到 .git）：%s" % REPO)
        return 1
    os.makedirs(os.path.dirname(DST), exist_ok=True)
    # 安全：若目标已存在且内容不同，先备份，绝不静默覆盖用户已有的钩子
    if os.path.isfile(DST) and not _same_file(SRC, DST):
        bak = DST + ".bak"
        shutil.copyfile(DST, bak)
        print("⚠ 检测到已有 pre-commit 钩子，已备份到 %s（如不再需要可删）" % bak)
    shutil.copyfile(SRC, DST)
    # 尝试加可执行位（Windows 上 git 用 sh 跑，位不重要，但加上无害）
    try:
        cur = os.stat(DST).st_mode
        os.chmod(DST, cur | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    except Exception:
        pass
    print("✓ 已安装 pre-commit 钩子 → %s" % DST)
    print("  以后每次 git commit 会自动扫描静默拦截 BUG（mouse_filter=STOP 的按钮装饰子节点）。")
    print("  验证：python tools/lint_mouse_filter.py --tier default")
    return 0


def _same_file(a, b):
    try:
        with open(a, "rb") as f:
            da = f.read()
        with open(b, "rb") as f:
            db = f.read()
        return da == db
    except Exception:
        return False


if __name__ == "__main__":
    raise SystemExit(main())
