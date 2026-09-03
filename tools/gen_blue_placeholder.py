#!/usr/bin/env python3
# tools/gen_blue_placeholder.py
# 为新增的可结缘女性 NPC 生成「蓝色占位」资源（纯 stdlib，无第三方依赖）：
#   1) 半身立绘  assets/characters/half_body/<id>.png   (300x420 蓝色剪影)
#   2) 世界体    assets/characters/<id>.png             (160x240 蓝色全身剪影)
#   3) 头像图标  resources/icons/npc/<id>.png           (128x128 蓝色圆角汉字徽标)
# 用法：python tools/gen_blue_placeholder.py
import os, zlib, struct

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HALF_DIR = os.path.join(ROOT, "assets", "characters", "half_body")
BODY_DIR = os.path.join(ROOT, "assets", "characters")
ICON_DIR = os.path.join(ROOT, "resources", "icons", "npc")

# 蓝色系（用户指定蓝色占位）
BLUE_TOP = (0x3E, 0x94, 0xB8)     # 亮蓝
BLUE_BASE = (0x1E, 0x4E, 0x78)    # 深蓝
SKIN = (0x93, 0x80, 0x72)

NPC_IDS = ["npc_liu_ruyan", "npc_mu_wanqing"]


def _crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xffffffff


def _chunk(typ: str, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + typ.encode("ascii") + data + struct.pack(">I", _crc32(typ.encode("ascii") + data))


def write_png(path: str, w: int, h: int, rgba: bytes) -> None:
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        raw.extend(rgba[y * w * 4:(y + 1) * w * 4])
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0)
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(_chunk("IHDR", ihdr))
        f.write(_chunk("IDAT", idat))
        f.write(_chunk("IEND", b""))


def lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def gen_half_body(nid: str) -> None:
    W, H = 300, 420
    cx = W / 2
    head_r = 78
    head_cy = 150
    buf = bytearray(W * H * 4)
    for y in range(H):
        for x in range(W):
            a = 0.0
            col = (0, 0, 0)
            dx, dy = x - cx, y - head_cy
            if dx * dx + dy * dy <= head_r * head_r:
                a = 1.0
                col = SKIN
            if abs(x - cx) <= 26 and 215 <= y <= 245:
                a = 1.0
                col = SKIN
            if y >= 245:
                half_w = 26 + (y - 245) * 0.95
                if abs(x - cx) <= half_w and y <= H - 10:
                    a = 1.0
                    sh = 0.85 if y > H - 60 else 1.0
                    col = lerp(BLUE_TOP, BLUE_BASE, y / H)
                    col = tuple(int(c * sh) for c in col)
            if dy < 0 and dx * dx + dy * dy <= (head_r + 10) * (head_r + 10) and dy < -head_r * 0.35:
                a = 1.0
                col = (0x1B, 0x3A, 0x5C)
            i = (y * W + x) * 4
            buf[i] = col[0]
            buf[i + 1] = col[1]
            buf[i + 2] = col[2]
            buf[i + 3] = int(a * 255)
    write_png(os.path.join(HALF_DIR, nid + ".png"), W, H, bytes(buf))


def gen_world_body(nid: str) -> None:
    W, H = 160, 240
    cx = W / 2
    buf = bytearray(W * H * 4)
    head_cx, head_cy, head_r = cx, 40, 26
    for y in range(H):
        for x in range(W):
            a = 0.0
            col = (0, 0, 0)
            dx, dy = x - head_cx, y - head_cy
            if dx * dx + dy * dy <= head_r * head_r:
                a = 1.0
                col = SKIN
            if 70 <= y <= 150:
                half_w = 22 + (y - 70) * 0.12
                if abs(x - cx) <= half_w:
                    a = 1.0
                    col = lerp(BLUE_TOP, BLUE_BASE, y / H)
            if 80 <= y <= 150:
                for side in (-1, 1):
                    ax = cx + side * 34
                    if abs(x - ax) <= 8:
                        a = 1.0
                        col = lerp(BLUE_TOP, BLUE_BASE, y / H)
            if 150 <= y <= 230:
                for side in (-1, 1):
                    lx = cx + side * 12
                    if abs(x - lx) <= 9:
                        a = 1.0
                        col = lerp(BLUE_TOP, BLUE_BASE, y / H)
            i = (y * W + x) * 4
            buf[i] = col[0]
            buf[i + 1] = col[1]
            buf[i + 2] = col[2]
            buf[i + 3] = int(a * 255)
    write_png(os.path.join(BODY_DIR, nid + ".png"), W, H, bytes(buf))


def gen_icon(nid: str) -> None:
    SIZE = 128
    buf = bytearray(SIZE * SIZE * 4)
    r = int(SIZE * 0.22)
    for y in range(SIZE):
        for x in range(SIZE):
            inside = True
            for (px, py) in [(x, y), (x, SIZE - 1 - y), (SIZE - 1 - x, y), (SIZE - 1 - x, SIZE - 1 - y)]:
                if px < r and py < r and (r - px) ** 2 + (r - py) ** 2 > r * r:
                    inside = False
            if not inside:
                continue
            col = lerp(BLUE_TOP, BLUE_BASE, y / SIZE)
            i = (y * SIZE + x) * 4
            buf[i] = col[0]
            buf[i + 1] = col[1]
            buf[i + 2] = col[2]
            buf[i + 3] = 255
    cx = cy = SIZE / 2
    for y in range(SIZE):
        for x in range(SIZE):
            d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
            if 40 <= d <= 46:
                i = (y * SIZE + x) * 4
                buf[i] = 247
                buf[i + 1] = 239
                buf[i + 2] = 221
                buf[i + 3] = 255
    write_png(os.path.join(ICON_DIR, nid + ".png"), SIZE, SIZE, bytes(buf))


def main() -> None:
    os.makedirs(HALF_DIR, exist_ok=True)
    os.makedirs(BODY_DIR, exist_ok=True)
    os.makedirs(ICON_DIR, exist_ok=True)
    for nid in NPC_IDS:
        gen_half_body(nid)
        gen_world_body(nid)
        gen_icon(nid)
        print("generated blue placeholder for %s" % nid)
    print("done -> half_body / characters / icons/npc")


if __name__ == "__main__":
    main()
