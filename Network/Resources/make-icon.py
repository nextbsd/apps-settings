# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# python3 make-icon.py Network.png
#

# Network.app's icon: a rounded blue tile with a white globe (its rim,
# the equator, two parallels and three meridians), drawn the way Date &
# Time's and Energy's icons are (dark frame, gradient, gloss).
import struct, zlib, math, sys
N = 128; S = 4
def rrect(px, py, x0, y0, x1, y1, r):
    cx = min(max(px, x0+r), x1-r); cy = min(max(py, y0+r), y1-r)
    return math.hypot(px-cx, py-cy) <= r
CX, CY, R = 64, 64, 40
def ellipse(px, py, rx, ry, w):
    """On the outline of an ellipse about the centre, w wide."""
    if rx == 0: return abs(px-CX) <= w/2 and abs(py-CY) <= ry
    d = math.hypot((px-CX)/rx, (py-CY)/ry)
    return abs(d-1) * min(rx, ry) <= w/2
def glyph(px, py):
    """1: white (rim, lines), 0: the globe, None: outside it."""
    d = math.hypot(px-CX, py-CY)
    if d > R: return None
    if d > R-5: return 1
    if abs(py-CY) <= 1.5: return 1                     # the equator
    for lat in (-0.55, 0.55):                          # two parallels
        y = CY + lat*R
        if abs(py-y) <= 1.5: return 1
    for rx in (0, R*0.45, R*0.8):                      # meridians
        if ellipse(px, py, rx, R, 3): return 1
    return 0
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
                        t = (py-13)/102.0          # light to deep blue
                        c = (int(110 + (30-110)*t), int(170 + (80-170)*t), int(240 + (180-240)*t), 255)
                        if py < 13 + 40 and px + py < 150:
                            c = tuple(min(255, int(v*0.85 + 255*0.15)) for v in c[:3]) + (255,)
                        g = glyph(px, py)
                        if g == 1:
                            c = (255, 255, 255, 255)
                        elif g == 0:
                            c = (32, 48, 92, 255)
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
