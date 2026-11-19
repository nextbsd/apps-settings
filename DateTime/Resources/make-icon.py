# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# python3 make-icon.py DateTime.png
#

# Date & Time.app's icon: a rounded blue tile with a white clock face at
# ten past ten, drawn the way Energy's and Bluetooth's icons are (dark
# frame, gradient, gloss).
import struct, zlib, math, sys
N = 128; S = 4
def rrect(px, py, x0, y0, x1, y1, r):
    cx = min(max(px, x0+r), x1-r); cy = min(max(py, y0+r), y1-r)
    return math.hypot(px-cx, py-cy) <= r
def seg(px, py, x0, y0, x1, y1, w):
    dx, dy = x1-x0, y1-y0
    t = max(0.0, min(1.0, ((px-x0)*dx + (py-y0)*dy) / (dx*dx + dy*dy)))
    return math.hypot(px-(x0+t*dx), py-(y0+t*dy)) <= w/2
CX, CY, R = 64, 66, 38
def hand(angle, length):            # angle: degrees clockwise from 12
    a = math.radians(angle)
    return CX + math.sin(a)*length, CY - math.cos(a)*length
def glyph(px, py):
    """1: white (ring, ticks, hands), 0: the face, None: outside it."""
    d = math.hypot(px-CX, py-CY)
    if d > R: return None
    if d > R-6: return 1
    for i in range(12):
        x0, y0 = hand(i*30, R-9); x1, y1 = hand(i*30, R-(15 if i % 3 == 0 else 12))
        if seg(px, py, x0, y0, x1, y1, 4 if i % 3 == 0 else 2.5): return 1
    hx, hy = hand(305, 18); mx, my = hand(60, 27)
    if seg(px, py, CX, CY, hx, hy, 6) or seg(px, py, CX, CY, mx, my, 4.5): return 1
    if d <= 4.5: return 1
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
