#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
compress_textures.py — 武侠江湖 纹理自动压缩「双保险」第二层

背景
----
Godot 对本项目纹理的出厂默认导入是 `compress/mode=0`（未压缩），
且 4.7 不认 `.godot/imports/texture.import` 这类项目级默认预设。
未压缩 + 超大源图会导致显存暴涨、主线程卡顿。

第一层保险（工作室导入）：
    tools/desktop_studio/tscn_assets.py 的 write_import() 模板已写死
    compress/mode=2 + process/size_limit=2048，走工作室导入的图自动压缩。

第二层保险（本脚本，覆盖 LocalSend / 拖拽 / git pull 等「非工作室」路径）：
    扫 assets/ 下所有纹理 .import，把未压缩的改成 VRAM 压缩 + 限速 2048，
    并删除对应的 .godot/imported/*.ctex 缓存，强制 Godot 下次加载时
    按新设置重新生成压缩纹理。

⚠️ 关键坑（本次事故教训）：
    仅改 .import 的 [params] 不会触发 Godot 重导——Godot 只认
    source_md5 变化或缺失的 dest 文件。所以本脚本必须删除 stale .ctex，
    否则 Godot 仍按旧缓存加载未压缩纹理。
    （另：CompressedTexture2D.get_image().get_pixel() 会刷屏报错拖死主线程，
     取像素请走 Image.load_png_from_buffer 解码源文件，见 UIBackground.gd）

用法
----
    python tools/compress_textures.py            # 执行压缩 + 强制重导
    python tools/compress_textures.py --check    # 只报告有多少未压缩，不改
    python tools/compress_textures.py --dry-run  # 打印将改哪些，不落盘
    python tools/compress_textures.py --resize-sources
        # 额外把任一边长 >2048 的源 PNG 缩到 2048（需 Pillow，会先备份到 _backup_hires/）
        # 默认不开：process/size_limit=2048 已能让 Godot 在导入时降分辨率，无需改源。

安全边界
------
    * 只处理 importer="texture" 的 .import，跳过音频/字体/模型/着色器等。
    * 跳过任何含 _backup / _jpg_backup 的目录（那是备份，不进游戏）。
    * 只把 mode=0→2、size_limit=0 或 >2048→2048；已是压缩且限速合理的原样保留。
    * 幂等：重复运行不产生变化、不重复删缓存。
"""

import os
import re
import sys
import glob
import shutil

PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # .../武侠游戏
# 扫描根：游戏资源目录。tools/（工作室数据备份）与 .godot/（缓存）不扫。
SCAN_ROOTS = [
    os.path.join(PROJECT_ROOT, "assets"),
    os.path.join(PROJECT_ROOT, "resources"),
]
IMPORTED_DIR = os.path.join(PROJECT_ROOT, ".godot", "imported")

TARGET_MODE = 2          # 2 = VRAM 压缩 (S3TC/BPTC)
TARGET_SIZE_LIMIT = 2048 # 导入时限最大边长；0 表示不限制

# 跳过的目录（备份，不进游戏；或工具/缓存目录，不属游戏资源）
SKIP_DIR_FRAGMENTS = ("_backup", "_jpg_backup", "/tools/", "\\tools\\", ".godot")

# ---- 正则：从 [params] 段里抓 compress/mode 与 process/size_limit ----
RE_MODE = re.compile(r"^compress/mode=(\d+)\s*$", re.MULTILINE)
RE_SIZE = re.compile(r"^process/size_limit=(\d+)\s*$", re.MULTILINE)
RE_IMPORTER = re.compile(r'^importer="([^"]+)"\s*$', re.MULTILINE)


def is_skipped(path: str) -> bool:
    norm = path.replace("\\", "/")
    return any(frag in norm for frag in SKIP_DIR_FRAGMENTS)


def list_texture_imports():
    out = []
    for root in SCAN_ROOTS:
        if not os.path.isdir(root):
            continue
        for imp in glob.glob(os.path.join(root, "**", "*.import"), recursive=True):
            if is_skipped(imp):
                continue
            try:
                txt = open(imp, encoding="utf-8", errors="ignore").read()
            except Exception:
                continue
            m = RE_IMPORTER.search(txt)
            if m and m.group(1) == "texture":
                out.append((imp, txt))
    return out


def set_param(txt: str, key: str, value: int):
    """把 [params] 里的 key=value 改成 value；没有就追加到段末。返回 (新文本, 是否改动)。"""
    pat = re.compile(r"^" + re.escape(key) + r"=(\d+)\s*$", re.MULTILINE)
    m = pat.search(txt)
    if m:
        if int(m.group(1)) == value:
            return txt, False
        return pat.sub(f"{key}={value}", txt), True
    # 没有该键：追加到文件末尾（Godot 的 [params] 段在最末，直接追加即生效）
    if not txt.endswith("\n"):
        txt += "\n"
    return txt + f"{key}={value}\n", True


def delete_stale_ctex(import_path: str):
    """删除该资源在 .godot/imported 下的旧 .ctex/.md5，强制 Godot 重导。返回删除数量。"""
    base = os.path.splitext(import_path)[0]
    name = os.path.basename(base)
    removed = 0
    if os.path.isdir(IMPORTED_DIR):
        for f in glob.glob(os.path.join(IMPORTED_DIR, name + "-*")):
            try:
                os.remove(f)
                removed += 1
            except OSError:
                pass
    return removed


def maybe_resize_source(import_path: str):
    """可选：把源 PNG 缩到 <=2048（需 Pillow）。先备份原图到 _backup_hires/。返回信息串。"""
    base = os.path.splitext(import_path)[0]
    src = base + ".png"
    if not os.path.isfile(src):
        return ""
    try:
        from PIL import Image
    except Exception:
        return " (skip resize: Pillow 不可用)"
    try:
        im = Image.open(src)
        w, h = im.size
        if max(w, h) <= TARGET_SIZE_LIMIT:
            return ""
        scale = TARGET_SIZE_LIMIT / max(w, h)
        nw, nh = max(1, int(round(w * scale))), max(1, int(round(h * scale)))
        backup_dir = os.path.join(os.path.dirname(src), "_backup_hires")
        os.makedirs(backup_dir, exist_ok=True)
        shutil.copy2(src, os.path.join(backup_dir, os.path.basename(src)))
        im.resize((nw, nh), Image.LANCZOS).save(src)
        return f" (resized {w}x{h}->{nw}x{nh}, backup in _backup_hires)"
    except Exception as e:
        return f" (resize error: {e})"


def main():
    args = sys.argv[1:]
    dry_run = "--dry-run" in args
    check_only = "--check" in args
    resize = "--resize-sources" in args

    imports = list_texture_imports()
    total = len(imports)
    changed = 0
    skipped_ok = 0
    stale_removed = 0
    reports = []

    for imp, txt in imports:
        m = RE_MODE.search(txt)
        s = RE_SIZE.search(txt)
        cur_mode = int(m.group(1)) if m else 0
        cur_size = int(s.group(1)) if s else 0

        need_mode = cur_mode != TARGET_MODE
        need_size = cur_size == 0 or cur_size > TARGET_SIZE_LIMIT

        if not need_mode and not need_size:
            skipped_ok += 1
            continue

        rel = os.path.relpath(imp, PROJECT_ROOT).replace("\\", "/")
        note = []
        new_txt = txt
        if need_mode:
            new_txt, _ = set_param(new_txt, "compress/mode", TARGET_MODE)
            note.append(f"mode {cur_mode}->2")
        if need_size:
            new_txt, _ = set_param(new_txt, "process/size_limit", TARGET_SIZE_LIMIT)
            note.append(f"size_limit {cur_size}->2048")

        if check_only:
            reports.append(f"  [未压缩] {rel}: {', '.join(note)}")
            changed += 1
            continue

        if dry_run:
            reports.append(f"  [将改] {rel}: {', '.join(note)}")
            changed += 1
            continue

        # 落地
        with open(imp, "w", encoding="utf-8") as f:
            f.write(new_txt)
        # 删 stale .ctex 强制重导（核心保险动作）
        removed = delete_stale_ctex(imp)
        stale_removed += removed
        extra = maybe_resize_source(imp) if resize else ""
        reports.append(f"  [已压缩] {rel}: {', '.join(note)}; 删缓存 {removed}{extra}")
        changed += 1

    # 输出
    print(f"扫描纹理 .import 共 {total} 个")
    if check_only:
        print(f"未压缩（需处理）: {changed} 个；已合规: {skipped_ok} 个")
    elif dry_run:
        print(f"将改动: {changed} 个；已合规: {skipped_ok} 个")
    else:
        print(f"已改动: {changed} 个；原本已合规: {skipped_ok} 个；删除 stale 缓存: {stale_removed} 个")
    for r in reports:
        print(r)
    if not (check_only or dry_run) and (changed > 0 or stale_removed > 0):
        print("\n完成。下次 Godot 打开/加载时会按新设置重新生成压缩纹理（.s3tc.ctex）。")
        print("如需立即全部重导：在 Godot 编辑器内『导入』面板点『重新导入』，或运行")
        print("  Godot --headless --editor --quit --path \"D:/武侠游戏\"")
    return 0


if __name__ == "__main__":
    sys.exit(main())
