#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
migrate_to_lfs.py — 把 4 个 runtime 大文件接入 Git LFS
=====================================================

背景（用户 2026-09-02 终拍板：大媒体外置 + 引入 Git LFS）
--------------------------------------------------------
仓库 assets/ 共 123MB，其中：
  * 9 个 _backup_hires / _jpg_backup 高清原图备份（~50MB）已在 .gitignore，
    本就不进版本库 —— 无需处理。
  * 4 个 runtime 大文件（~14.6MB）经 res:// 加载、必须留在工作树，
    但当前以普通 blob 进 git 对象库、撑爆仓库 —— 需接入 Git LFS。

本脚本只处理这 4 个 runtime 文件（绝不碰 _backup* 备份）：
  assets/ui/main_menu_bg.png        (MainMenu/SaveLoad/Loading 背景, BG_IMAGE_PATH)
  assets/battle_bg/preset_6x6.png   (战棋底图)
  assets/battle_bg/preset_12x12.png (战棋底图)
  assets/scenes/town_main.png       (TownScene 场景背景, SCENE_BG_PATH)

前置条件（必须由用户 / PM 先清空，本脚本会硬校验，不满足直接退出）
-----------------------------------------------------------------
  1. 本机已安装 Git LFS：git lfs version 正常。
  2. 远端 Gitee 泄漏的 token 已吊销，remote URL 已改为不含明文密码
     （改用 SSH / 凭据管理器 / 不含 user:pass 的 https）。

本脚本做什么（幂等；staging 后由 PM 用 commit_queue 收口提交，绝不自行 commit）
--------------------------------------------------------------------------------
  A. git lfs install --local          装 smudge/clean 钩子
  B. git lfs track <4 文件>           写 .gitattributes + 登记追踪（幂等）
  C. git add .gitattributes <4 文件>  精确 add，经 LFS filter 转成指针入库
  D. 打印后续步骤

关于历史大 blob
----------------
  默认只改「未来提交」：历史 commit 里仍含大 blob（单 master 不强制推历史重写更安全）。
  若确实要清理历史，加 --rewrite-history，脚本会提示风险并给出 git lfs migrate import 命令，
  该操作需要随后 force-push，请先备份。

安全护栏
--------
  * 运行前校验 git-lfs 已装、远端 URL 无明文 token，任一不满足即退出（exit 2/3）。
  * 不读取、不修改任何 _backup* 目录。
"""

import os
import sys
import shutil
import subprocess

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 仅这 4 个 runtime 大文件接入 LFS（其余一律不碰）
LFS_FILES = [
    "assets/ui/main_menu_bg.png",
    "assets/battle_bg/preset_6x6.png",
    "assets/battle_bg/preset_12x12.png",
    "assets/scenes/town_main.png",
]


def run(cmd, check=True):
    """在仓库根目录执行命令并打印。"""
    print("+ " + " ".join(cmd))
    r = subprocess.run(cmd, cwd=PROJECT_ROOT)
    if check and r.returncode != 0:
        sys.exit(r.returncode)
    return r


def git_lfs_available() -> bool:
    if shutil.which("git-lfs"):
        return True
    # Windows 上 git-lfs 可能只注册为 git 子命令
    return subprocess.run(
        ["git", "lfs", "version"], cwd=PROJECT_ROOT,
        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
    ).returncode == 0


def remote_has_plaintext_token() -> bool:
    """远端 URL 形如 https://user:pass@host 即判定含明文 token。"""
    r = subprocess.run(
        ["git", "remote", "get-url", "origin"], cwd=PROJECT_ROOT,
        capture_output=True, text=True,
    )
    url = r.stdout.strip()
    if "://" not in url:
        return False
    after_scheme = url.split("://", 1)[1]
    if "@" not in after_scheme:
        return False
    userinfo = after_scheme.split("@", 1)[0]
    # user:pass 才含明文密码；纯 user@ 或 SSH git@ 不算
    return ":" in userinfo


def main():
    rewrite = "--rewrite-history" in sys.argv

    # 护栏 1：git-lfs 已装
    if not git_lfs_available():
        print("✗ 前置未满足：本机未安装 Git LFS。")
        print("  请先安装（如从 https://git-lfs.com 下载，或 scoop install git-lfs），")
        print("  并运行一次 `git lfs install`，再回来执行本脚本。")
        sys.exit(2)

    # 护栏 2：远端无明文 token
    if remote_has_plaintext_token():
        print("✗ 安全护栏：远端 URL 仍含明文 token（已泄漏）。")
        print("  请先在 Gitee 吊销该 token，并把 remote URL 改为不含 user:pass 的形式：")
        print("    git remote set-url origin https://gitee.com/asdf1328886661/wuxia-game.git")
        print("  （推送时改用 SSH 或系统凭据管理器）。处理完再执行本脚本。")
        sys.exit(3)

    # 校验 4 个文件确实存在于工作树
    missing = [f for f in LFS_FILES if not os.path.isfile(os.path.join(PROJECT_ROOT, f))]
    if missing:
        print("✗ 以下 runtime 文件在工作树中缺失，无法接入 LFS：")
        for m in missing:
            print("    " + m)
        sys.exit(4)

    # A. 安装钩子
    run(["git", "lfs", "install", "--local"])

    # B. 登记追踪（幂等：已追踪则 git lfs track 不重复写）
    run(["git", "lfs", "track"] + LFS_FILES)

    # C. 精确 add（仅 .gitattributes + 这 4 个文件，绝不 git add -A/.）
    run(["git", "add", ".gitattributes"] + LFS_FILES)

    print("\n✅ 4 个 runtime 大文件已转为 LFS 指针并 stage（大 blob 不再进 git 对象库）。")
    print("   下一步：由 PM / 本对话用 `python tools/commit_queue.py add` 收口提交，")
    print("   不要自行 git commit / git push。")

    if rewrite:
        print("\n⚠️ --rewrite-history：将重写这些文件的历史以移除旧大 blob，需随后 force-push。")
        print("   建议先备份仓库，再执行：")
        print("     git lfs migrate import --include=" + ",".join(LFS_FILES))
        print("   然后由 PM 协调 force-push（单 master 需全员同步）。")
    else:
        print("（未重写历史：历史 commit 中仍含大 blob。如需彻底清理，加 --rewrite-history 并 force-push。）")


if __name__ == "__main__":
    main()
