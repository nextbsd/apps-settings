# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# python3 make-icon.py UsersLogin.png
#

# Users & Login.app's icon: a rounded grey-blue tile with two white
# figures, one in front of the other, drawn the way Date & Time's and
# Energy's icons are (dark frame, gradient, gloss).
import struct, zlib, math, sys
N = 128; S = 4
def rrect(px, py, x0, y0, x1, y1, r):
    cx = min(max(px, x0+r), x1-r); cy = min(max(py, y0+r), y1-r)
    return math.hypot(px-cx, py-cy) <= r
def figure(px, py, cx, top, scale):
    """A head and shoulders: the head a circle, the body a half disc."""
    hr = 11*scale
    if math.hypot(px-cx, py-(top+hr)) <= hr: return True
    by = top + 2*hr + 26*scale       # the body's flat bottom
    br = 22*scale
    return py <= by and py >= top + 2*hr + 3*scale and math.hypot(px-cx, py-by) <= br
def glyph(px, py):
    """1: the front figure, 2: the one behind, 3: the gap between them,
    None: the tile."""
    if figure(px, py, 72, 40, 1.0): return 1
    if figure(px, py, 72, 40, 1.12) or figure(px, py, 72, 36, 1.12): return 3
    if figure(px, py, 48, 30, 0.85): return 2
    return None
rows = []
for y in range(N):
    row = bytearray([0])
    for x in range(N):
        acc = [0.0]*4
        for sy in range(S):
            for sx in range(S):
                px = x + (sx+0.5)/S; py = y + (sy+0.5)/S
                c = (0, 0, 0, 0)
                if rrect(px, py, 8, 8, 120, 120, 22):
                    c = (40, 44, 52, 255)
                    if rrect(px, py, 13, 13, 115, 115, 18):
                        t = (py-13)/102.0          # light to deep slate blue
                        c = (int(140 + (50-140)*t), int(160 + (70-160)*t), int(200 + (120-200)*t), 255)
                        if py < 13 + 40 and px + py < 150:
                            c = tuple(min(255, int(v*0.85 + 255*0.15)) for v in c[:3]) + (255,)
                        g = glyph(px, py)
                        if g == 1 and py < 113:
                            c = (255, 255, 255, 255)
                        elif g == 2 and py < 113:
                            c = (205, 212, 228, 255)
                for i in range(4):
                    acc[i] += c[i]
        a = acc[3]/(S*S)
        if a == 0:
            row += bytes(4)
        else:
            row += bytes([int(acc[0]/(acc[3]/255)), int(acc[1]/(acc[3]/255)), int(acc[2]/(acc[3]/255)), int(a)])
    rows.append(bytes(row))
def chunk(t, d):
    return struct.pack('>I', len(d)) + t + d + struct.pack('>I', zlib.crc32(t+d) & 0xffffffff)
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', N, N, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(b''.join(rows), 9)) + chunk(b'IEND', b'')
open(sys.argv[1], 'wb').write(png)
