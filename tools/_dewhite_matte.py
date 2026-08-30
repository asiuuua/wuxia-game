"""
去白边（纯 numpy，无需 scipy）：
matte_clean 硬边抠图后，角色轮廓（含较厚白边）最外圈像素 RGB 仍是白背景色，
在深色背景下显白边。本脚本：
1) target = 所有「前景 且 邻域有背景 且 RGB 偏白」的像素（覆盖整个轮廓白边厚度）
2) 多遍扩散：每遍对 target 像素取 3x3 邻居中「非白色的前景像素」颜色均值填充，
   白边逐层被内侧角色本色替换；迭代收敛后白边消失，alpha 保持硬边。
处理完覆盖回 matte_clean/，供 _gen_matte_175.py 重采样。
"""
import numpy as np
from PIL import Image, ImageFilter
from numpy.lib.stride_tricks import sliding_window_view

SRC = "D:/武侠游戏/assets/characters/matte_clean"
N = 31
WHITE_T = 225  # R,G,B 均>该值视为「白」


def dewhite(path: str) -> int:
    im = Image.open(path).convert("RGBA")
    a = np.asarray(im)
    rgb = a[:, :, :3].astype(np.float64)
    alpha = a[:, :, 3]
    fg = alpha > 128
    # 背景膨胀 1px 与前景相交 = 轮廓前景像素
    bg = ~fg
    bg_dil = np.asarray(Image.fromarray(bg.astype("u1") * 255).filter(ImageFilter.MaxFilter(3))) > 128
    edge_fg = fg & bg_dil
    whiteish = (rgb[:, :, 0] > WHITE_T) & (rgb[:, :, 1] > WHITE_T) & (rgb[:, :, 2] > WHITE_T)
    target = edge_fg & whiteish

    filled = rgb.copy()
    for _ in range(15):
        # 当前白图（动态）
        cur_white = (filled[:, :, 0] > WHITE_T) & (filled[:, :, 1] > WHITE_T) & (filled[:, :, 2] > WHITE_T)
        sw_rgb = sliding_window_view(filled, (3, 3), axis=(0, 1))          # (H-2,W-2,3,3,3)
        sw_white = sliding_window_view(cur_white, (3, 3))                  # (H-2,W-2,3,3)
        sw_fg = sliding_window_view(fg, (3, 3))                            # (H-2,W-2,3,3)
        valid = (~sw_white) & sw_fg                                       # 合格邻居
        vals = np.where(valid[..., None], sw_rgb, 0.0).sum(axis=(3, 4))    # (H-2,W-2,3)
        cnt = valid.sum(axis=(2, 3))                                      # (H-2,W-2)
        cnt_safe = np.maximum(cnt, 1)
        mean = vals / cnt_safe[..., None]
        rmask = target[1:-1, 1:-1]
        sub = filled[1:-1, 1:-1].copy()
        sub[rmask] = mean[rmask]
        filled[1:-1, 1:-1] = sub

    out = rgb.copy()
    out[target] = filled[target]
    res = np.dstack([out.astype(np.uint8), alpha])
    Image.fromarray(res, "RGBA").save(path)
    return int(target.sum())


if __name__ == "__main__":
    tot = 0
    for i in range(1, N + 1):
        tot += dewhite(f"{SRC}/matte_{i:05d}.png")
    print(f"去白边完成，处理像素总数={tot}（31帧合计）")
