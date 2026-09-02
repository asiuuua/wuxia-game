# tools/desktop_studio/compress_textures.py
# 纹理压缩治理工具：把 resources 下 .import 的 compress/mode 从 0(Lossless) 批量修为 2(Compress/VRAM)
# 规范 §纹理压缩：出厂默认 mode=0（未压缩）；发布/优化需切成 mode=2 以省运行时显存。
# 用法（默认只扫描报告，不加参数不写盘）：
#   python tools/desktop_studio/compress_textures.py                 # 只扫描统计
#   python tools/desktop_studio/compress_textures.py --apply          # 应用：备份后改 mode=0->2
#   python tools/desktop_studio/compress_textures.py --restore        # 从 .bak 回滚本次改动
#   python tools/desktop_studio/compress_textures.py --root resources/ui  # 限定目录
# 注意：改完 .import 后须经 Godot 编辑器 reimport 才会使 GPU 压缩真正生效。
import argparse
from pathlib import Path
import sys

MODE_0 = "compress/mode=0"
MODE_2 = "compress/mode=2"


def collect_import_files(root: Path) -> list:
    if not root.is_dir():
        print(f"[FATAL] 根目录不存在: {root}")
        sys.exit(2)
    return list(root.rglob("*.import"))


def read_mode0(files: list) -> list:
    """返回 (文件, 是否含 mode=0, 含 mode=2) 的三元列表。"""
    out = []
    for f in files:
        try:
            text = f.read_text(encoding="utf-8")
        except OSError as e:
            print(f"[WARN] 读取失败 {f}: {e}")
            continue
        has0 = MODE_0 in text
        has2 = MODE_2 in text
        out.append((f, has0, has2))
    return out


def scan(root: Path) -> list:
    files = collect_import_files(root)
    info = read_mode0(files)
    mode0 = [f for f, has0, _ in info if has0]
    already2 = [f for f, has0, has2 in info if (not has0) and has2]
    print(f"扫描 {root}：共 {len(files)} 个 .import")
    print(f"  mode=0（待改，Lossless）: {len(mode0)}")
    print(f"  已是 mode=2（Compress/VRAM）: {len(already2)}")
    for f in mode0:
        print(f"    - {f}")
    return mode0


def apply(root: Path, dry: bool = True) -> int:
    files = collect_import_files(root)
    info = read_mode0(files)
    mode0 = [f for f, has0, _ in info if has0]
    changed = 0
    for f in mode0:
        bak = Path(str(f) + ".bak")
        try:
            text = f.read_text(encoding="utf-8")
        except OSError as e:
            print(f"[WARN] 读取失败 {f}: {e}")
            continue
        new_text = text.replace(MODE_0, MODE_2)
        if new_text == text:
            continue
        if dry:
            print(f"[dry-run] 将改 {f} -> mode=2")
            changed += 1
            continue
        # 先备份再写
        if not bak.exists():
            bak.write_text(text, encoding="utf-8")
        f.write_text(new_text, encoding="utf-8")
        print(f"[apply] {f}")
        changed += 1
    print(f"[{'dry-run' if dry else 'done'}] 修改 {changed} 个 .import（mode=0 -> 2）")
    return changed


def restore(root: Path) -> int:
    files = collect_import_files(root)
    restored = 0
    for f in files:
        bak = Path(str(f) + ".bak")
        if not bak.exists():
            continue
        f.write_text(bak.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"[restore] 已回滚 {f}")
        restored += 1
    print(f"[restore done] 回滚 {restored} 个 .import")
    return restored


def main() -> int:
    ap = argparse.ArgumentParser(description="纹理 .import 压缩模式治理工具")
    ap.add_argument("--root", default="resources", help="扫描根目录（默认 resources）")
    ap.add_argument("--apply", action="store_true", help="应用修改（默认只扫描报告）")
    ap.add_argument("--restore", action="store_true", help="从 .bak 回滚 mode=2 -> mode=0")
    args = ap.parse_args()

    root = Path(args.root)
    if args.restore:
        return restore(root)
    if args.apply:
        return apply(root, dry=False)
    return apply(root, dry=True)


if __name__ == "__main__":
    sys.exit(main())