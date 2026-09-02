#!/usr/bin/env python3
# tools/gen_icons.py
# 图标批量生成器（UI 窗口主权 · 美术接入工具）
#
# 用途：按 IconRegistry 的文件约定（resources/icons/<分类>/<id>.png）生成"真实占位图标"，
#       替换品红棋盘 PlaceholderTexture2D。生成的图标是带分类配色的圆角汉字徽标，
#       远优于紫块；待美术出真图后，按 id 同名丢入即自动覆盖（本脚本遇到已存在文件会跳过）。
#
# 设计：纯 Pillow 生成，无第三方美术依赖；字形取实体中文名前 2 字（CJK），无中文则取 id 前 2 字母。
#       分类配色：skills 青 / items 金 / enemies 赤 / npc 碧 / menu 靛 / status 紫。
#
# 用法：
#   python tools/gen_icons.py            # 生成全部（已存在跳过）
#   python tools/gen_icons.py --force    # 强制覆盖重生成
#   python tools/gen_icons.py --dry      # 仅打印将生成的清单，不写盘
#
# 数据来源（只读）：
#   data/configs/abilities/skills.json         -> skills/<id>
#   data/configs/abilities/status_effects.json -> status/<id>
#   data/configs/items/{equipment,materials,pills,weapons}.json -> items/<id>
#   data/configs/npcs/enemies.json             -> enemies/<id>
#   data/configs/npcs/town_npcs.json          -> npc/<id>
#   data/configs/npcs/npc_stats.json           -> npc/<id> 缺中文名时取 title
#   menu 图标按 menu_config.json 的 action_id 映射生成 -> menu/<id>

import json
import os
import sys
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ICON_ROOT = os.path.join(ROOT, "resources", "icons")
SIZE = 128

# 分类配色 (top, base) —— 武侠水墨基调
PALETTES = {
    "skills":  ((0x3E, 0x94, 0xB8), (0x25, 0x61, 0x78)),
    "items":   ((0xE0, 0xAE, 0x55), (0xA9, 0x77, 0x2A)),
    "enemies": ((0xCF, 0x4B, 0x4B), (0x8E, 0x25, 0x25)),
    "npc":     ((0x3F, 0xB0, 0x85), (0x23, 0x70, 0x4F)),
    "menu":    ((0x5A, 0x6F, 0xA6), (0x36, 0x44, 0x65)),
    "status":  ((0x9B, 0x6F, 0xC4), (0x5E, 0x3F, 0x85)),
}
GLYPH_COLOR = (247, 239, 221, 255)  # 米白

FONT_CANDIDATES = [
    "C:/Windows/Fonts/simhei.ttf",
    "C:/Windows/Fonts/msyh.ttc",
    "C:/Windows/Fonts/simsun.ttc",
]


def load_json(rel):
    with open(os.path.join(ROOT, rel), encoding="utf-8") as f:
        return json.load(f)


def find_font():
    for p in FONT_CANDIDATES:
        if os.path.exists(p):
            return p
    return None


def is_cjk(ch):
    return "\u4e00" <= ch <= "\u9fff"


def glyph_of(name, fallback_id):
    src = name if name else fallback_id
    cjk = [c for c in src if is_cjk(c)]
    if len(cjk) >= 2:
        return "".join(cjk[:2])
    if len(cjk) == 1:
        return cjk[0]
    asc = "".join(c for c in src if c.isalnum())[:2].upper()
    return asc or "?"


def lerp(c1, c2, t):
    return tuple(int(c1[i] + (c2[i] - c1[i]) * t) for i in range(3))


def make_icon(top, base, glyph, font_path):
    img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mask = Image.new("L", (SIZE, SIZE), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [0, 0, SIZE - 1, SIZE - 1], radius=int(SIZE * 0.22), fill=255
    )
    grad = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    gd = ImageDraw.Draw(grad)
    for y in range(SIZE):
        gd.line([(0, y), (SIZE, y)], fill=lerp(top, base, y / SIZE) + (255,))
    img = Image.composite(grad, img, mask)

    d = ImageDraw.Draw(img)
    d.rounded_rectangle(
        [2, 2, SIZE - 3, SIZE - 3], radius=int(SIZE * 0.22),
        outline=(255, 255, 255, 70), width=3,
    )
    fsize = 56 if len(glyph) >= 2 else 82
    fnt = ImageFont.truetype(font_path, fsize)
    bb = d.textbbox((0, 0), glyph, font=fnt)
    tw, th = bb[2] - bb[0], bb[3] - bb[1]
    d.text(((SIZE - tw) / 2 - bb[0], (SIZE - th) / 2 - bb[1]),
           glyph, font=fnt, fill=GLYPH_COLOR)
    return img


def collect_ids():
    ids = []  # (category, id, name)

    def add(cat, pairs):
        for i, n in pairs:
            ids.append((cat, i, n))

    # skills
    d = load_json("data/configs/abilities/skills.json")
    add("skills", [(e["id"], e.get("name", "")) for e in d.get("skills", []) if "id" in e])
    # status
    d = load_json("data/configs/abilities/status_effects.json")
    add("status", [(e["id"], e.get("name", "")) for e in d.get("status_effects", []) if "id" in e])
    # items
    for sub in ["equipment", "materials", "pills", "weapons"]:
        d = load_json(f"data/configs/items/{sub}.json")
        add("items", [(e["id"], e.get("name", "")) for e in d.get("items", []) if "id" in e])
    # enemies
    d = load_json("data/configs/npcs/enemies.json")
    add("enemies", [(e["id"], e.get("name", "")) for e in d.get("enemies", []) if "id" in e])
    # npc: town_npcs
    d = load_json("data/configs/npcs/town_npcs.json")
    add("npc", [(e["id"], e.get("name", "")) for e in d.get("npcs", []) if "id" in e])
    # npc: 用 npc_stats 的 title 补中文名（town_npcs 缺名的）
    stats = load_json("data/configs/npcs/npc_stats.json")
    name_by_id = {}
    for k, v in stats.items():
        if isinstance(v, dict) and "title" in v:
            name_by_id[k] = v["title"]
    for i in range(len(ids)):
        if ids[i][0] == "npc" and not ids[i][2] and ids[i][1] in name_by_id:
            ids[i] = (ids[i][0], ids[i][1], name_by_id[ids[i][1]])
    # npc: player（status_card 硬编码 npc/player）
    ids.append(("npc", "player", "主角"))
    # menu: 按 action_id 映射
    menu_map = {
        "open_attributes": ("attributes", "性"),
        "open_inventory": ("inventory", "包"),
        "open_equipment": ("equipment", "装"),
        "open_bond": ("bond", "缘"),
        "open_sect": ("sect", "派"),
        "open_map": ("map", "图"),
        "open_abilities": ("abilities", "艺"),
        "open_forge": ("forge", "锻"),
        "open_alchemy": ("alchemy", "药"),
        "open_shop": ("shop", "铺"),
        "open_settings": ("settings", "设"),
        "open_save": ("save", "档"),
    }
    for action_id, (mid, glyph) in menu_map.items():
        ids.append(("menu", mid, glyph))
    return ids


def main():
    force = "--force" in sys.argv
    dry = "--dry" in sys.argv
    font_path = find_font()
    if not font_path:
        print("ERROR: no CJK font found", file=sys.stderr)
        sys.exit(1)
    ids = collect_ids()
    made, skipped = 0, 0
    for cat, iid, name in ids:
        folder = os.path.join(ICON_ROOT, cat)
        os.makedirs(folder, exist_ok=True)
        out = os.path.join(folder, iid + ".png")
        if os.path.exists(out) and not force:
            skipped += 1
            continue
        glyph = name if is_cjk(name) or len(name) <= 2 else glyph_of(name, iid)
        if len(glyph) > 2 and is_cjk(glyph):
            glyph = glyph[:2]
        top, base = PALETTES[cat]
        img = make_icon(top, base, glyph, font_path)
        if dry:
            print(f"[dry] {cat}/{iid}.png  glyph={glyph}  name={name}")
        else:
            img.save(out)
            made += 1
    if dry:
        print(f"[dry] total={len(ids)}")
    else:
        print(f"generated={made}  skipped(existing)={skipped}  total={len(ids)}")
        print(f"font={font_path}")


if __name__ == "__main__":
    main()
