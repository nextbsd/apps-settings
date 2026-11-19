# Copyright (C) 2026 Joseph Maloney <pkgdemonteam@gmail.com>
# SPDX-License-Identifier: BSD-2-Clause
#
# Keyboard.app's icon (Keyboard.png): a rounded tile in the settings
# apps' style (dark rim, two-tone gradient, as Bluetooth's) with a white
# keyboard glyph. Not part of the build; needs Pillow:
#   python3 make-icon.py Keyboard.png
import sys
from PIL import Image, ImageDraw

S = 4                      # supersampling
W = 128 * S
img = Image.new("RGBA", (W, W), (0, 0, 0, 0))
d = ImageDraw.Draw(img)

def r(v): return int(round(v * S))

# rim
d.rounded_rectangle([r(8), r(8), r(120) - 1, r(120) - 1], radius=r(20),
                    fill=(40, 44, 52, 255))
# gradient body, lighter top half (gloss), as Bluetooth's
top = (176, 184, 198); mid1 = (146, 155, 170); mid2 = (112, 121, 138); bot = (70, 78, 94)
grad = Image.new("RGBA", (W, W))
gd = ImageDraw.Draw(grad)
y0, y1 = r(13), r(115)
half = (y0 + y1) // 2
for y in range(y0, y1):
    if y < half:
        t = (y - y0) / (half - y0); a, b = top, mid1
    else:
        t = (y - half) / (y1 - half); a, b = mid2, bot
    c = tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3)) + (255,)
    gd.line([(0, y), (W, y)], fill=c)
mask = Image.new("L", (W, W), 0)
ImageDraw.Draw(mask).rounded_rectangle([r(13), r(13), r(115) - 1, r(115) - 1],
                                       radius=r(15), fill=255)
img.paste(grad, (0, 0), mask)

# the keyboard glyph: an outline with three rows of keys and a space bar
white = (255, 255, 255, 255)
kx0, ky0, kx1, ky1 = 26, 40, 102, 88
d.rounded_rectangle([r(kx0), r(ky0), r(kx1), r(ky1)], radius=r(7),
                    outline=white, width=r(4))
key = 7.0; gap = 2.6
inner_x0 = kx0 + 7
def keyrow(y, n, x0, w=key):
    for i in range(n):
        x = x0 + i * (w + gap)
        d.rounded_rectangle([r(x), r(y), r(x + w), r(y + key)], radius=r(1.4),
                            fill=white)
span = (kx1 - 7) - inner_x0
n1 = 7
w1 = (span - (n1 - 1) * gap) / n1
keyrow(ky0 + 7, n1, inner_x0, w1)
keyrow(ky0 + 7 + key + gap, n1, inner_x0, w1)
# bottom row: two keys, the space bar, two keys
y = ky0 + 7 + 2 * (key + gap)
x = inner_x0
for w in (w1, w1):
    d.rounded_rectangle([r(x), r(y), r(x + w), r(y + key)], radius=r(1.4), fill=white)
    x += w + gap
sp = 3 * w1 + 2 * gap
d.rounded_rectangle([r(x), r(y), r(x + sp), r(y + key)], radius=r(1.4), fill=white)
x += sp + gap
for w in (w1, w1):
    d.rounded_rectangle([r(x), r(y), r(x + w), r(y + key)], radius=r(1.4), fill=white)
    x += w + gap

img = img.resize((128, 128), Image.LANCZOS)
img.save(sys.argv[1])
