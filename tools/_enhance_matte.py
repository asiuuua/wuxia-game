"""
增强 matte 序列帧：消除半透明灰边 + 轻度锐化，提升游戏内观感清晰度。
输入：assets/characters/matte/matte_000NN.png (31帧)
输出：assets/characters/matte_enh/matte_000NN.png (增强版，同尺寸)
配套 .tres：matte_enh_idle.tres（ExtResource 引用，避免之前的路径字符串坑）
不改原 matte/，可随时切回。
"""
import os, glob
from PIL import Image, ImageFilter, ImageChops

SRC = r"D:\武侠游戏\assets\characters\matte"
DST = r"D:\武侠游戏\assets\characters\matte_enh"
os.makedirs(DST, exist_ok=True)

files = sorted(glob.glob(os.path.join(SRC, "matte_*.png")))
print(f"src frames={len(files)}")

uid_lines = []
frames_entries = []
for i, f in enumerate(files, 1):
    im = Image.open(f).convert("RGBA")
    # 1) alpha 硬边化：>128 -> 255，否则 -> 0（消除半透明灰边发虚）
    r, g, b, a = im.split()
    a = a.point(lambda v: 255 if v > 128 else 0)
    im = Image.merge("RGBA", (r, g, b, a))
    # 2) 轻度锐化（原图可能偏糊）
    rgb = im.convert("RGB")
    sharp = rgb.filter(ImageFilter.UnsharpMask(radius=1.2, percent=120, threshold=2))
    im = sharp.convert("RGBA")
    im.putalpha(a)
    out = os.path.join(DST, os.path.basename(f))
    im.save(out, "PNG")
    # 读真实 UID（从增强帧自己的 .import 文件，避免编假 UID 导致编辑器解析 null）
    base = os.path.basename(f)
    import_path = os.path.join(DST, base + ".import")
    real_uid = f"matteenh{i:05d}"  # fallback
    if os.path.exists(import_path):
        with open(import_path, "r", encoding="utf-8") as ip:
            for line in ip:
                if "uid=" in line:
                    real_uid = line.strip().split('uid="')[1].split('"')[0].replace("uid://", "")
                    break
    uid_lines.append(f'[ext_resource type="Texture2D" uid="uid://{real_uid}" path="res://assets/characters/matte_enh/{base}" id="{i}"]')
    frames_entries.append(f'{{"duration":0.08,"texture":ExtResource({i})}}')

# 写 .tres
tres = os.path.join(DST, "matte_enh_idle.tres")
with open(tres, "w", encoding="utf-8") as fh:
    fh.write('[gd_resource type="SpriteFrames" load_steps=%d format=3 uid="uid://matteenhidle1"]\n\n' % (len(files) + 1))
    fh.write("\n".join(uid_lines) + "\n")
    fh.write('\n[resource]\nanimations=[\n{\n"frames":[\n' + ",\n".join(frames_entries) + "\n],\n"
          '"loop":true,\n"name":"idle",\n"speed":12.0\n}\n]\n')
print("written", tres)
print("DONE")
