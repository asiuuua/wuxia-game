#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
export_ai_context.py —— 把项目"喂给"外部 AI（ChatGPT 等）的一键导出工具

背景：整个仓库 200MB+，但 assets/(119M) 与 resources/(88M) 全是图片，
      代码（scenes+tests+data+services+autoload+core）只有约 2.35MB。
      外部 AI 既不需要图片，上下文窗口也装不下全部代码。
      所以正确姿势是"分层投喂"，而不是打包整个仓库。

三种模式：
  1) summary（默认，强烈推荐首选）
     导出人工整理的架构摘要（projects/wuxia_game.yaml 的 ai_context）
     + 协同启动卡 + 契约总表。约 10~30KB，几秒读完，AI 立刻懂架构。

  2) module  --module <关键字>
     只导出与某个模块相关的源码。例：--module quest
     命中 services/quest/、data/configs/quests/、以及名字含 quest 的脚本。

  3) all  [--with-docs] [--with-tests]
     导出全部源码到一个文件（供 Custom GPT 检索 / 大上下文模型使用）。
     默认排除 docs 与 tests；图片、.import、.bak、.uid、.pyc 一律排除。

用法（在 D:/武侠游戏 下执行）：
  python tools/export_ai_context.py
  python tools/export_ai_context.py --mode module --module quest
  python tools/export_ai_context.py --mode all --with-tests
  python tools/export_ai_context.py --mode all --out D:/tmp/all.md

输出：单文件，默认写到 _ai_export/ 目录；打印体积与"估算 token"供判断是否超限。
"""

import os
import sys
import argparse
import datetime

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# 允许导出的文本后缀（AI 读得懂的东西）
TEXT_EXT = {
    ".gd", ".py", ".tscn", ".tres", ".json", ".csv", ".md",
    ".yaml", ".yml", ".cfg", ".txt", ".gdshader", ".shader",
}

# 永不导出的目录（图片/构建产物/缓存/第三方/设计参考）
EXCLUDE_DIRS = {
    ".git", ".godot", ".workbuddy", "__pycache__", "build", "dist",
    "assets", "resources", "inventory-design-reference",
    "wuxia-ui-design-reference", "addons", "Desktop",
}

# 永不导出的文件后缀（二进制 / Godot 自动生成 / 备份）
EXCLUDE_EXT = {
    ".import", ".uid", ".pyc", ".bak", ".png", ".jpg", ".jpeg",
    ".webp", ".wav", ".ogg", ".mp3", ".ttf", ".otf", ".exe",
    ".zip", ".log", ".pyz", ".toc", ".pck",
}

# 单文件体积上限，超过则跳过并提示（防止某个巨型 json 撑爆导出）
MAX_FILE_BYTES = 300 * 1024

# 生成摘要模式时优先携带的"高信号文档"（相对 ROOT）
SUMMARY_DOCS = [
    "tools/desktop_studio/projects/wuxia_game.yaml",
    "docs/AI协同启动卡.md",
    "docs/契约总表.md",
    "README.md",
    ".workbuddy/memory/MEMORY.md",
]


def is_excluded(rel_path: str) -> bool:
    """判断某相对路径是否应被排除。"""
    parts = rel_path.replace("\\", "/").split("/")
    for p in parts[:-1]:
        if p in EXCLUDE_DIRS:
            return True
    ext = os.path.splitext(rel_path)[1].lower()
    return ext in EXCLUDE_EXT


def iter_text_files(with_docs: bool, with_tests: bool, module: str = ""):
    """遍历仓库，产出 (相对路径, 绝对路径)。"""
    hits = []
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        for fn in filenames:
            rel = os.path.relpath(os.path.join(dirpath, fn), ROOT).replace("\\", "/")
            if is_excluded(rel):
                continue
            ext = os.path.splitext(fn)[1].lower()
            if ext not in TEXT_EXT and fn not in ("project.godot", ".gitignore"):
                continue
            if not with_docs and rel.startswith("docs/"):
                continue
            if not with_tests and (rel.startswith("tests/") or rel.startswith("tools/")):
                continue
            if module:
                low = rel.lower()
                if module.lower() not in low:
                    continue
            hits.append((rel, os.path.join(dirpath, fn)))
    return sorted(hits)


def read_text(path: str):
    """读文本文件，失败返回 None。"""
    try:
        if os.path.getsize(path) > MAX_FILE_BYTES:
            return None, "SKIP_TOO_LARGE"
        with open(path, "r", encoding="utf-8", errors="replace") as f:
            return f.read(), None
    except Exception as e:  # noqa: BLE001
        return None, str(e)


def emit(files, out_path: str, title: str, note: str = "") -> int:
    """把文件列表写进单文件，返回总字符数。"""
    lines = []
    lines.append("# %s" % title)
    lines.append("")
    lines.append("> 生成时间：%s" % datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S"))
    lines.append("> 生成工具：tools/export_ai_context.py（图片/二进制/构建产物已排除）")
    if note:
        lines.append("> %s" % note)
    lines.append("")
    lines.append("## 文件清单（共 %d 个）" % len(files))
    lines.append("")
    for rel, _ in files:
        lines.append("- `%s`" % rel)
    lines.append("")
    lines.append("---")
    lines.append("")

    skipped = []
    for rel, abspath in files:
        content, err = read_text(abspath)
        lines.append("")
        lines.append("=" * 70)
        lines.append("### FILE: %s" % rel)
        lines.append("=" * 70)
        lines.append("")
        if err:
            lines.append("（跳过：%s）" % err)
            skipped.append(rel)
        else:
            lines.append(content.rstrip())
        lines.append("")

    text = "\n".join(lines)
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w", encoding="utf-8") as f:
        f.write(text)

    print("✓ 已生成: %s" % out_path)
    print("  文件数: %d（跳过 %d）" % (len(files), len(skipped)))
    print("  体积  : %.1f KB / %d 字符" % (os.path.getsize(out_path) / 1024.0, len(text)))
    # 粗略估算：中文按 1 字符≈1 token，英文按 4 字符≈1 token，取中值
    est = int(len(text) / 2.2)
    print("  估算 token: 约 %s（中文为主，仅供参考）" % format(est, ","))
    if est > 120000:
        print("  ⚠ 体积偏大，多数模型一次读不完 —— 建议改用 --mode module 分模块投喂，")
        print("    或只把本文件放进支持检索的 Custom GPT / Project。")
    if skipped:
        print("  跳过文件: %s" % ", ".join(skipped[:5]))
    return len(text)


def cmd_summary(out_path: str):
    """摘要模式：人工整理的架构上下文 + 高信号文档。"""
    files = []
    for rel in SUMMARY_DOCS:
        abspath = os.path.join(ROOT, rel)
        if os.path.exists(abspath):
            files.append((rel, abspath))
    if not files:
        print("✗ 未找到任何摘要文档，检查路径：%s" % SUMMARY_DOCS[:2])
        return
    # 额外附一份"目录结构速览"，让 AI 知道去哪找东西
    tree_lines = ["# 项目目录速览（已排除图片与构建产物）", ""]
    for dirpath, dirnames, filenames in os.walk(ROOT):
        dirnames[:] = [d for d in dirnames if d not in EXCLUDE_DIRS]
        rel_dir = os.path.relpath(dirpath, ROOT).replace("\\", "/")
        if rel_dir == ".":
            rel_dir = ""
        n = len([f for f in filenames if os.path.splitext(f)[1].lower() in TEXT_EXT])
        if n:
            tree_lines.append("- `%s/` （%d 个文本文件）" % (rel_dir, n))
    tree_path = os.path.join(os.path.dirname(out_path), "_目录速览.md")
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(tree_path, "w", encoding="utf-8") as f:
        f.write("\n".join(tree_lines))
    files.append(("_目录速览.md", tree_path))

    note = "投喂建议：先把本文件上传给 AI，让它读架构；再按问题用 --mode module 补具体源码。"
    emit(files, out_path, "武侠江湖 · 项目架构摘要（给外部 AI）", note)
    try:
        os.remove(tree_path)
    except OSError:
        pass


def main():
    ap = argparse.ArgumentParser(description="导出项目上下文给外部 AI")
    ap.add_argument("--mode", default="summary",
                    choices=["summary", "module", "all"], help="导出模式")
    ap.add_argument("--module", default="", help="module 模式下的关键字，如 quest / bond / combat")
    ap.add_argument("--with-docs", action="store_true", help="all 模式下附带 docs/")
    ap.add_argument("--with-tests", action="store_true", help="all 模式下附带 tests/ 与 tools/")
    ap.add_argument("--out", default="", help="输出文件路径")
    args = ap.parse_args()

    outdir = os.path.join(ROOT, "_ai_export")
    if args.out:
        out_path = args.out
    elif args.mode == "summary":
        out_path = os.path.join(outdir, "01_架构摘要_先传这个.md")
    elif args.mode == "module":
        out_path = os.path.join(outdir, "02_模块_%s.md" % (args.module or "x"))
    else:
        out_path = os.path.join(outdir, "99_全部源码.md")

    if args.mode == "summary":
        cmd_summary(out_path)
    elif args.mode == "module":
        if not args.module:
            print("✗ module 模式必须给 --module <关键字>，例如 --module quest")
            sys.exit(1)
        files = iter_text_files(with_docs=False, with_tests=True, module=args.module)
        if not files:
            print("✗ 没找到与 '%s' 相关的文件，换个关键字试试（quest/bond/combat/ui/...）" % args.module)
            sys.exit(1)
        emit(files, out_path, "模块源码：%s" % args.module,
             note="仅含与 '%s' 相关的源码，供针对性提问。" % args.module)
    else:
        files = iter_text_files(with_docs=args.with_docs, with_tests=args.with_tests)
        extra = []
        if args.with_docs:
            extra.append("docs")
        if args.with_tests:
            extra.append("tests/tools")
        note = "全部源码（已排除图片与二进制）。附带：%s" % ("、".join(extra) if extra else "无")
        emit(files, out_path, "武侠江湖 · 全部源码", note=note)


if __name__ == "__main__":
    main()
