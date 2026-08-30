"""
从纯白背景视频抽取 31 帧 + 抠白 + 形态学闭运算填细孔 + 硬边输出。
输入：D:/LocalSend/保存文件/1788045776940..mp4 (720x1280, 白背景)
输出：assets/characters/matte_clean/matte_000NN.png (31帧 RGBA)
算法：
  1. 白背景判定：R,G,B 均 > WHITE_T → 透明
  2. 闭运算（morphology closing）填角色内部细小空洞（解决"发虚"根因）
  3. 边缘软化：距白边距离做 1~2px 渐变，其余硬边（alpha=255）
"""
import os, numpy as np
import imageio.v2 as imageio
from PIL import Image, ImageFilter

SRC = r"D:\LocalSend\保存文件\1788045776940..mp4"
DST = r"D:\武侠游戏\assets\characters\matte_clean"
os.makedirs(DST, exist_ok=True)

N_FRAMES = 31          # 输出帧数（与现有 idle 动画一致）
WHITE_T = 235          # 白背景阈值（纯白 255，留一点容差）
EDGE_SOFT = 3          # 边缘软化像素数（越小越硬）

reader = imageio.get_reader(SRC, "ffmpeg")
total = 0
for _ in reader:
    total += 1
reader.close()

# 均匀采样索引
idxs = [int(round(i * (total - 1) / (N_FRAMES - 1))) for i in range(N_FRAMES)]
print(f"video_total={total}  sample_idxs={idxs[0]}..{idxs[-1]}  out={N_FRAMES}")

reader = imageio.get_reader(SRC, "ffmpeg")
# 一次性读入所有帧（241帧 ~600MB，可接受）
all_frames = [f[:, :, :3].copy() for f in reader]
reader.close()
print(f"loaded {len(all_frames)} frames into memory")

saved = 0
for out_i, frame_i in enumerate(idxs, 1):
    rgb = all_frames[frame_i]
    # 1) 白背景蒙版
    white = (rgb[:, :, 0] > WHITE_T) & (rgb[:, :, 1] > WHITE_T) & (rgb[:, :, 2] > WHITE_T)
    alpha = np.where(white, 0, 255).astype(np.uint8)
    # 2) 闭运算填细孔：先膨胀再腐蚀，消除角色内部小透明洞
    amask = Image.fromarray(alpha, "L")
    amask = amask.filter(ImageFilter.MaxFilter(3))   # dilate：填小洞/连边
    amask = amask.filter(ImageFilter.MinFilter(3))   # erode：恢复外轮廓大小
    alpha = np.array(amask)
    # 3) 边缘软化：对"前景"做轻膨胀羽化（仅外缘 1~2px，内部保持硬）
    fg = Image.fromarray((alpha > 0).astype(np.uint8) * 255, "L")
    fg_soft = fg.filter(ImageFilter.MaxFilter(EDGE_SOFT))  # 外扩 EDGE_SOFT px
    edge = np.array(fg_soft)
    alpha = np.where(edge > 0, 255, alpha).astype(np.uint8)
    # 合成 RGBA
    out = np.dstack([rgb, alpha])
    im = Image.fromarray(out, "RGBA")
    fn = os.path.join(DST, f"matte_{out_i:05d}.png")
    im.save(fn, "PNG")
    saved += 1
print(f"SAVED {saved} frames to {DST}")
