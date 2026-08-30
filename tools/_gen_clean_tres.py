import re, os

SRC = "D:/武侠游戏/assets/characters/matte_clean"
OUT = os.path.join(SRC, "matte_clean_idle.tres")
N = 31


def get_uid(i):
    p = os.path.join(SRC, "matte_%05d.png.import" % i)
    with open(p, encoding="utf-8") as f:
        txt = f.read()
    m = re.search(r'uid="(uid://[^"]+)"', txt)
    return m.group(1)


uids = [get_uid(i) for i in range(1, N + 1)]

lines = []
lines.append('[gd_resource type="SpriteFrames" load_steps=%d format=3 uid="uid://matteclnidle1"]' % (N + 1))
lines.append("")
for i, u in enumerate(uids, 1):
    lines.append('[ext_resource type="Texture2D" uid="%s" path="res://assets/characters/matte_clean/matte_%05d.png" id="%d"]' % (u, i, i))
lines.append("")
lines.append("[resource]")
lines.append("animations=[")
lines.append("{")
lines.append('"frames":[')
for i in range(1, N + 1):
    comma = "," if i < N else ""
    lines.append('{"duration":0.08,"texture":ExtResource(%d)}%s' % (i, comma))
lines.append("],")
lines.append('"loop":true,')
lines.append('"name":"idle",')
lines.append('"speed":0.55,')
lines.append('"from":0,')
lines.append('"to":%d' % (N - 1))
lines.append("}")
lines.append("]")
lines.append("animations/idx_idle=0")
lines.append("")

with open(OUT, "w", encoding="utf-8") as f:
    f.write("\n".join(lines) + "\n")

print("已生成", OUT)
print("首行:", lines[0])
print("帧0:", lines[3 + N])
print("speed 行存在:", any('"speed":0.55' in l for l in lines))
