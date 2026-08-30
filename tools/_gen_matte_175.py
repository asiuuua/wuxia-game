import os, re
import numpy as np
from PIL import Image, ImageFilter

SRC = "D:/武侠游戏/assets/characters/matte_clean"
DST = "D:/武侠游戏/assets/characters/matte_175"
N = 31
TARGET_H = 175  # 与世界体 PLAYER_SCENE_H 一致


def main():
    os.makedirs(DST, exist_ok=True)
    # 读原图尺寸确定缩放比（所有帧同为 720x1280）
    sample = Image.open(os.path.join(SRC, "matte_00001.png")).convert("RGBA")
    W, H = sample.size
    scale = TARGET_H / H
    out_w = max(1, int(round(W * scale)))
    out_h = TARGET_H
    print(f"原图 {W}x{H} → 目标 {out_w}x{out_h} (scale={scale:.4f})")

    for i in range(1, N + 1):
        im = Image.open(os.path.join(SRC, "matte_%05d.png" % i)).convert("RGBA")
        # 1) 高质量降采样（LANCZOS 保细节）
        rgb = im.resize((out_w, out_h), Image.LANCZOS)
        # 2) alpha 通道单独轻高斯，消除硬边发丝缩小后的碎噪
        a = im.split()[3]
        a_small = a.resize((out_w, out_h), Image.LANCZOS)
        a_blur = a_small.filter(ImageFilter.GaussianBlur(radius=0.6))
        arr = np.asarray(a_blur, dtype=np.float32)
        # 3) 反阈值化：>128 视为不透明，但保留轻过渡羽化（发丝轮廓平滑）
        #    用 smoothstep 在 [100,180] 做柔边，避免纯硬边锯齿又不过度发虚
        lo, hi = 100.0, 180.0
        out_a = np.clip((arr - lo) / (hi - lo), 0.0, 1.0) * 255.0
        out_a = out_a.astype(np.uint8)
        rgb.putalpha(Image.fromarray(out_a, "L"))
        rgb.save(os.path.join(DST, "matte_%05d.png" % i), "PNG")
    print(f"已生成 {N} 帧到 {DST}")

    # 4) 触发 Godot 导入生成 .import（含真实 UID）
    print("注：.import 由 Godot --import 生成，本脚本只出 PNG；运行后需引擎 import。")


if __name__ == "__main__":
    main()
