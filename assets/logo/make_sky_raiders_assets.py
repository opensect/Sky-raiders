#!/usr/bin/env python3
"""Worker P (QA-145): build Sky Raiders icon PNGs + menu logo from the generated webp.
Real converter: PIL. Old icon/logo kept on disk as backup (not overwritten).
"""
from PIL import Image, ImageDraw, ImageFont
from collections import deque
import os

LOGO = "assets/logo"
SRC = f"{LOGO}/media-generation-sky-raiders-icon-0-50bc66d4-4530-450f-a497-08e8ea84478e.webp"
ORANGE = (255, 114, 0)

# ---------- 1. Icon: webp -> RGBA PNGs, white rounded corners -> transparent ----------
im = Image.open(SRC).convert("RGBA")
assert im.size == (1600, 1600), im.size
px = im.load()
W, H = im.size
# Flood-fill near-white pixels connected to the 4 corners -> transparent.
seen = set()
q = deque([(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)])
def is_white(x, y):
    r, g, b, _a = px[x, y]
    return r > 235 and g > 235 and b > 235
while q:
    x, y = q.popleft()
    if (x, y) in seen or not (0 <= x < W and 0 <= y < H):
        continue
    if not is_white(x, y):
        continue
    seen.add((x, y))
    r, g, b, _a = px[x, y]
    px[x, y] = (r, g, b, 0)
    q.extend([(x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)])
print("transparent corner pixels:", len(seen))

# Master project icon 512x512 (same size as old frag_arena_icon.png)
im512 = im.resize((512, 512), Image.LANCZOS)
im512.save(f"{LOGO}/sky_raiders_icon.png")
print("wrote sky_raiders_icon.png", im512.size, im512.mode)
im.resize((192, 192), Image.LANCZOS).save(f"{LOGO}/sky_raiders_icon_192.png")
im.resize((432, 432), Image.LANCZOS).save(f"{LOGO}/sky_raiders_icon_432_fg.png")
bg = Image.new("RGBA", (432, 432), ORANGE + (255,))
bg.save(f"{LOGO}/sky_raiders_icon_432_bg.png")
print("wrote 192 / 432_fg / 432_bg")

# ---------- 2. Menu logo: same style as old frag_arena_logo.png ----------
# 1239x320 transparent canvas, cyan crosshair emblem left, Orbitron wordmark
# "SKY" cyan #00E5FF + " RAIDERS" ice #E0F7FF, matching the old "FRAG"/"ARENA" split.
CYAN = (0, 229, 255, 255)
ICE = (224, 247, 255, 255)
NAVY = (3, 18, 26, 255)
FONT_PATH = "assets/fonts/orbitron/Orbitron-Variable.ttf"

canvas = Image.new("RGBA", (1239, 320), (0, 0, 0, 0))
d = ImageDraw.Draw(canvas)
cx, cy = 155, 160
# crosshair emblem: outer ring, 4 cardinal ticks, inner ring, 4 diagonal spokes, centre dot
d.ellipse([cx - 132, cy - 132, cx + 132, cy + 132], outline=CYAN, width=14)
for dx, dy, w, h in [(0, -152, 16, 34), (0, 118, 16, 34), (-152, 0, 34, 16), (118, 0, 34, 16)]:
    d.rectangle([cx + dx - w // 2, cy + dy - h // 2, cx + dx + w // 2, cy + dy + h // 2], fill=CYAN)
d.ellipse([cx - 72, cy - 72, cx + 72, cy + 72], outline=CYAN, width=10)
import math
for ang in (45, 135, 225, 315):
    a = math.radians(ang)
    x1, y1 = cx + 30 * math.cos(a), cy + 30 * math.sin(a)
    x2, y2 = cx + 62 * math.cos(a), cy + 62 * math.sin(a)
    d.line([x1, y1, x2, y2], fill=CYAN, width=12)
d.ellipse([cx - 12, cy - 12, cx + 12, cy + 12], fill=CYAN)

# wordmark: fit "SKY RAIDERS" into x=265..1225, cap height ~85px
def make_font(size):
    f = ImageFont.truetype(FONT_PATH, size)
    try:
        f.set_variation_by_axes([800])  # Orbitron wght 800
    except Exception as e:
        print("variation note:", e)
    return f

size = 120
while size > 40:
    f = make_font(size)
    w1 = d.textlength("SKY", font=f)
    w2 = d.textlength(" RAIDERS", font=f)
    if w1 + w2 <= 895:
        break
    size -= 2
print("logo font size:", size, "text width:", w1 + w2)
# vertical centre: textbbox for cap-height centring
bbox = d.textbbox((0, 0), "SKY RAIDERS", font=f)
th = bbox[3] - bbox[1]
x, y = 330, cy - th // 2 - bbox[1]
d.text((x, y), "SKY", font=f, fill=CYAN, stroke_width=2, stroke_fill=NAVY)
d.text((x + w1, y), " RAIDERS", font=f, fill=ICE, stroke_width=2, stroke_fill=NAVY)
canvas.save(f"{LOGO}/sky_raiders_logo.png")
print("wrote sky_raiders_logo.png", canvas.size, canvas.mode)
