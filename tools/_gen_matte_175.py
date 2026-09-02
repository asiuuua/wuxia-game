"""
matte_175 生成器 v3（ffmpeg + premultiplied alpha）

替换 Pillow LANCZOS 重采样为 ffmpeg lanczos + premultiply/unpremultiply，
根除半透明过渡像素带白色背景残留导致的光晕问题。
"""
import os
import subprocess
import shutil

# BUG-13 修复：路径相对化，避免硬编码绝对路径导致换机即废。
# 从本脚本向上查找带 project.godot 的工程根；找不到则回退环境变量/默认路径。
def discover_project_root():
    here = os.path.dirname(os.path.abspath(__file__))
    for _ in range(6):
        if os.path.exists(os.path.join(here, "project.godot")):
            return here
        parent = os.path.dirname(here)
        if parent == here:
            break
        here = parent
    return os.environ.get("WUXIA_PROJECT_ROOT", r"D:/武侠游戏")

ROOT = discover_project_root()
SRC = os.path.join(ROOT, "assets", "characters", "matte_clean")
DST = os.path.join(ROOT, "assets", "characters", "matte_175")
# ffmpeg 优先用环境变量/系统 PATH，最后回退本机 venv 内置二进制（仅本机兜底）
FFMPEG = (
    os.environ.get("FFMPEG_BIN")
    or shutil.which("ffmpeg")
    or (
        r"C:\Users\Administrator\.workbuddy\binaries\python\envs\default"
        r"\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"
    )
)
N = 31
OUT_W = 98   # 720 * (175/1280)
OUT_H = 175


def main():
    os.makedirs(DST, exist_ok=True)
    vf = f"format=rgba,premultiply=inplace=1,scale={OUT_W}:{OUT_H}:flags=lanczos,unpremultiply=inplace=1"

    for i in range(1, N + 1):
        inp = os.path.join(SRC, f"matte_{i:05d}.png")
        out = os.path.join(DST, f"matte_{i:05d}.png")
        r = subprocess.run(
            [FFMPEG, "-y", "-i", inp, "-vf", vf, out],
            capture_output=True,
        )
        if r.returncode != 0:
            print(f"ERROR frame {i}: {r.stderr.decode('utf-8', errors='replace')[:200]}")

    print(f"已生成 {N} 帧到 {DST} (ffmpeg lanczos + premultiplied alpha)")


if __name__ == "__main__":
    main()
