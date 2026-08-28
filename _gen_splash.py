import struct, zlib

W, H = 1280, 720
bg = (26, 22, 18)
gold = (212, 175, 55)

raw = bytearray()
for y in range(H):
    raw.append(0)  # filter type 0 per scanline
    for x in range(W):
        c = bg
        # 占位 Logo：居中矩形描边（真实 Logo 后覆盖）
        if 440 <= x <= 840 and 280 <= y <= 440:
            if x < 446 or x > 834 or y < 286 or y > 434:
                c = gold
            else:
                c = bg
        raw.extend(c)

def chunk(typ, data):
    body = typ + data
    return struct.pack(">I", len(data)) + body + struct.pack(">I", zlib.crc32(body) & 0xffffffff)

sig = b'\x89PNG\r\n\x1a\n'
ihdr = struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)
idat = zlib.compress(bytes(raw))
png = sig + chunk(b'IHDR', ihdr) + chunk(b'IDAT', idat) + chunk(b'IEND', b'')
with open('assets/ui/splash.png', 'wb') as f:
    f.write(png)
print("splash written, bytes =", len(png))
