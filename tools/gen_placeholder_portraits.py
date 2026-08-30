# tools/gen_placeholder_portraits.py
# 生成占位用「半身立绘」PNG（纯 stdlib，无需 PIL）。
# 每个 NPC / 主角 一张，按 id 派生稳定色相，画一个简单半身剪影 + 肩线，
# 让对话框 / 欢庆窗口 / NPC 面板先「有立绘可看」，后续美术直接替换同名文件即可。
# 输出目录：assets/characters/half_body/<id>.png（主角用 player）
import json, os, zlib, struct, math

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "assets", "characters", "half_body")
NPC_JSON = os.path.join(ROOT, "data", "configs", "npcs", "town_npcs.json")

W, H = 300, 420

def _crc32(data: bytes) -> int:
    return zlib.crc32(data) & 0xffffffff

def _chunk(typ: str, data: bytes) -> bytes:
    return struct.pack(">I", len(data)) + typ.encode("ascii") + data + struct.pack(">I", _crc32(typ.encode("ascii") + data))

def write_png(path: str, rgba: bytes) -> None:
    # rgba: W*H*4
    raw = bytearray()
    for y in range(H):
        raw.append(0)  # filter type 0
        raw.extend(rgba[y*W*4:(y+1)*W*4])
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)  # 8-bit RGBA
    idat = zlib.compress(bytes(raw), 9)
    with open(path, "wb") as f:
        f.write(sig)
        f.write(_chunk("IHDR", ihdr))
        f.write(_chunk("IDAT", idat))
        f.write(_chunk("IEND", b""))

def hue_to_rgb(h: float) -> tuple:
    h = h % 1.0
    r = abs(h*6-3)-1
    g = 2-abs(h*6-2)
    b = 2-abs(h*6-4)
    return (max(0.0,min(1.0,r)), max(0.0,min(1.0,g)), max(0.0,min(1.0,b)))

def gen_for(seed: str, out_name: str) -> None:
    # 稳定色相
    h = (sum(ord(c) for c in seed) % 360) / 360.0
    base = hue_to_rgb(h)
    skin = (0.93, 0.80, 0.72)
    bg = (0.06, 0.07, 0.10, 0.0)  # 透明背景
    buf = bytearray(W*H*4)
    cx = W/2
    head_r = 78
    head_cy = 150
    for y in range(H):
        for x in range(W):
            px = x/W
            py = y/H
            a = 0.0
            col = bg[:3]
            # 头部（圆）
            dx, dy = x-cx, y-head_cy
            if dx*dx + dy*dy <= head_r*head_r:
                a = 1.0
                col = skin
            # 脖子
            if abs(x-cx) <= 26 and 215 <= y <= 245:
                a = 1.0; col = skin
            # 肩 / 半身躯干（梯形）
            if y >= 245:
                half_w = 26 + (y-245)*0.95
                if abs(x-cx) <= half_w and y <= H-10:
                    a = 1.0
                    # 衣服：用基础色，下摆略深
                    sh = 0.85 if y > H-60 else 1.0
                    col = (base[0]*sh, base[1]*sh, base[2]*sh)
            # 头发（头顶弧）
            if dy < 0 and dx*dx+dy*dy <= (head_r+10)*(head_r+10) and dy < -head_r*0.35:
                a = 1.0
                col = (base[0]*0.45, base[1]*0.45, base[2]*0.45)
            i = (y*W+x)*4
            buf[i]   = int(col[0]*255)
            buf[i+1] = int(col[1]*255)
            buf[i+2] = int(col[2]*255)
            buf[i+3] = int(a*255)
    write_png(os.path.join(OUT_DIR, out_name), bytes(buf))

def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    ids = ["player"]
    if os.path.exists(NPC_JSON):
        d = json.load(open(NPC_JSON, encoding="utf-8"))
        for n in d.get("npcs", []):
            ids.append(n["id"])
    # 关系网 NPC（可结缘对象等多在 relations.json 的 relations 数组）也补占位立绘
    rel_path = os.path.join(ROOT, "data", "configs", "bond", "relations.json")
    if os.path.exists(rel_path):
        try:
            r = json.load(open(rel_path, encoding="utf-8"))
            rel_list = r.get("relations", []) if isinstance(r, dict) else []
            for item in rel_list:
                nid = item.get("id", "")
                if nid and nid not in ids:
                    ids.append(nid)
        except Exception:
            pass
    for nid in ids:
        gen_for(nid, nid + ".png")
    print("generated %d placeholder portraits -> %s" % (len(ids), OUT_DIR))

if __name__ == "__main__":
    main()
