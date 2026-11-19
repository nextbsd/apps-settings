# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# python3 make-icon.py Energy.png
#

# Energy.app's icon: a rounded green tile with a white battery and bolt,
# drawn the way Bluetooth.app's icon is (dark frame, gradient, gloss).
import struct, zlib, math, sys
N = 128; S = 4
def rrect(px, py, x0, y0, x1, y1, r):
    cx = min(max(px, x0+r), x1-r); cy = min(max(py, y0+r), y1-r)
    return math.hypot(px-cx, py-cy) <= r
def in_poly(px, py, pts):
    inside = False; j = len(pts)-1
    for i in range(len(pts)):
        xi, yi = pts[i]; xj, yj = pts[j]
        if (yi > py) != (yj > py) and px < (xj-xi)*(py-yi)/(yj-yi) + xi:
            inside = not inside
        j = i
    return inside
# The battery, on its side: body outline, terminal nub, bolt inside.
BX0, BY0, BX1, BY1, BR, BW = 24, 40, 96, 88, 9, 6.5
bolt = [(66, 46), (48, 67), (60, 67), (54, 82), (74, 59), (62, 59), (68, 46)]
def glyph(px, py):
    outer = rrect(px, py, BX0, BY0, BX1, BY1, BR)
    inner = rrect(px, py, BX0+BW, BY0+BW, BX1-BW, BY1-BW, BR-BW+1)
    if outer and not inner: return True
    if rrect(px, py, BX1+1, 54, BX1+9, 74, 3) and px > BX1: return True
    return in_poly(px, py, bolt)
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
                        t = (py-13)/102.0          # light to deep green
                        c = (int(125 + (25-125)*t), int(220 + (135-220)*t), int(110 + (60-110)*t), 255)
                        if py < 13 + 40 and px + py < 150:
                            c = tuple(min(255, int(v*0.85 + 255*0.15)) for v in c[:3]) + (255,)
                        if glyph(px, py):
                            c = (255, 255, 255, 255)
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
