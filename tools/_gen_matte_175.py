"""
matte_175 生成器 v3（ffmpeg + premultiplied alpha）

替换 Pillow LANCZOS 重采样为 ffmpeg lanczos + premultiply/unpremultiply，
根除半透明过渡像素带白色背景残留导致的光晕问题。
"""
import os
import subprocess

SRC = "D:/武侠游戏/assets/characters/matte_clean"
DST = "D:/武侠游戏/assets/characters/matte_175"
FFMPEG = (
    r"C:\Users\Administrator\.workbuddy\binaries\python\envs\default"
    r"\Lib\site-packages\imageio_ffmpeg\binaries\ffmpeg-win-x86_64-v7.1.exe"
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
