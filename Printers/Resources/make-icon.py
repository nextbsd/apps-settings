# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# python3 make-icon.py Printers.png
#

# Printers.app's icon: a rounded blue tile with a white printer, a sheet
# coming out of it, drawn the way Date & Time's icon is (dark frame,
# gradient, gloss).
import struct, zlib, math, sys
N = 128; S = 4
def rrect(px, py, x0, y0, x1, y1, r):
    cx = min(max(px, x0+r), x1-r); cy = min(max(py, y0+r), y1-r)
    return math.hypot(px-cx, py-cy) <= r
def glyph(px, py):
    """1: white (the paper), 2: pale (the printer), 0: dark detail,
    None: neither."""
    # The paper going in at the top and coming out at the front.
    if 42 <= px <= 86 and 26 <= py <= 50: return 1
    if 40 <= px <= 88 and 74 <= py <= 102:
        if 47 <= px <= 81 and py in (83, 84, 90, 91): return 0   # lines of text
        return 1
    # The body, with its slot.
    if rrect(px, py, 26, 48, 102, 86, 8):
        if 36 <= px <= 92 and 72 <= py <= 76: return 0           # the slot
        if math.hypot(px-90, py-58) <= 3: return 0                # the light
        return 2
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
                        t = (py-13)/102.0          # light to deep blue
                        c = (int(110 + (30-110)*t), int(170 + (80-170)*t), int(240 + (180-240)*t), 255)
                        if py < 13 + 40 and px + py < 150:
                            c = tuple(min(255, int(v*0.85 + 255*0.15)) for v in c[:3]) + (255,)
                        g = glyph(px, py)
                        if g == 1:
                            c = (255, 255, 255, 255)
                        elif g == 2:
                            c = (200, 214, 236, 255)
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
