#!/usr/bin/env python3
"""v3.7 map-independent visuals — code-drawn art with PIL only.
Style: bold clean cartoon military, thick dark outline, readable at
combat speed. Every sprite is drawn at 4x and downscaled (LANCZOS)
for smooth edges; PNG output is lossless, no blurry compression.
Run: python3 gen_v37_assets.py   (from the project root)
"""
import math, random
from PIL import Image, ImageDraw, ImageFont

SS = 4  # supersample factor
OUTLINE = (16, 14, 18, 255)
FONT_BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

def canvas(w, h):
    return Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))

def save(img, path, size):
    img = img.resize(size, Image.LANCZOS)
    img.save(path, "PNG")
    print("wrote", path, img.size, img.mode)

def S(v):
    return v * SS

def starburst_points(cx, cy, spikes, r_out, r_in, rot=0.0, vary=0.0, seed=1):
    rnd = random.Random(seed)
    pts = []
    for i in range(spikes * 2):
        ang = rot + math.pi * i / spikes
        r = r_out if i % 2 == 0 else r_in
        if vary:
            r *= 1.0 + rnd.uniform(-vary, vary)
        pts.append((cx + math.cos(ang) * r, cy + math.sin(ang) * r))
    return pts

def draw_starburst(d, cx, cy, spikes, r_out, r_in, colors, rot=0.0, vary=0.12, seed=1, squash_y=1.0):
    """colors: list of (color, scale) from outer to inner."""
    for color, scale in colors:
        pts = starburst_points(cx, cy, spikes, r_out * scale, r_in * scale, rot, vary, seed)
        pts = [(x, cy + (y - cy) * squash_y) for x, y in pts]
        d.polygon(pts, fill=color)

def outline_poly(d, pts, fill, width):
    d.line(pts + [pts[0]], fill=OUTLINE, width=S(width), joint="curve")
    d.polygon(pts, fill=fill)

# ---------------------------------------------------------------- flame
def flame(path):
    W, H = 32, 64
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    cx, top, h = S(16), S(4), S(56)
    def profile(t, wmax):
        # teardrop: narrow at the top (base), wide in the middle,
        # tapering to a wavy point at the bottom (tip).
        w = math.sin(math.pi * min(1.0, t * 1.05)) ** 0.8 * wmax
        wob = 1.0 + 0.12 * math.sin(t * 9.0)
        return w * wob
    def layer(wmax, hfrac, color):
        pts = []
        n = 48
        for i in range(n + 1):
            t = i / n
            y = top + t * h * hfrac
            w = profile(t, wmax)
            pts.append((cx - w, y))
        for i in range(n, -1, -1):
            t = i / n
            y = top + t * h * hfrac
            w = profile(t, wmax)
            pts.append((cx + w, y))
        d.polygon(pts, fill=color)
    # dark outline = biggest layer in outline colour, then fills.
    layer(S(13), 1.0, OUTLINE)
    layer(S(10.5), 0.98, (255, 110, 20, 255))   # orange outer
    layer(S(7.0), 0.80, (255, 200, 40, 255))    # yellow mid
    layer(S(3.8), 0.58, (255, 245, 180, 255))   # white-hot core
    save(img, path, (W, H))

# ---------------------------------------------------------------- muzzle
def muzzle(path, w, h, spikes, r_out, r_in, squash_y, seed, core_r):
    img = canvas(w, h)
    d = ImageDraw.Draw(img)
    cx, cy = S(w / 2), S(h / 2)
    # outline: same burst, slightly larger, in near-black
    draw_starburst(d, cx, cy, spikes, S(r_out * 1.18), S(r_in * 1.18),
                   [(OUTLINE, 1.0)], rot=0.0, vary=0.10, seed=seed, squash_y=squash_y)
    draw_starburst(d, cx, cy, spikes, S(r_out), S(r_in),
                   [((255, 120, 25, 255), 1.0), ((255, 205, 60, 255), 0.68),
                    ((255, 246, 190, 255), 0.38)],
                   rot=0.0, vary=0.10, seed=seed, squash_y=squash_y)
    d.ellipse([cx - S(core_r), cy - S(core_r * squash_y),
               cx + S(core_r), cy + S(core_r * squash_y)], fill=(255, 255, 240, 255))
    save(img, path, (w, h))

# ---------------------------------------------------------------- trail
def trail(path):
    W, H = 64, 8
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for x in range(W):
        t = x / (W - 1)  # 0 tail -> 1 head
        a = int(255 * (t ** 1.6))
        r = int(255)
        g = int(120 + 135 * t)
        b = int(40 + 150 * t)
        for y in range(H):
            # vertical falloff: soft round profile
            v = math.sin(math.pi * (y + 0.5) / H)
            px[x, y] = (r, g, b, int(a * v))
    img.save(path, "PNG")
    print("wrote", path, img.size, img.mode)

# ---------------------------------------------------------------- dust
def dust(path):
    W, H = 64, 48
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    rnd = random.Random(7)
    puffs = [(16, 34, 11), (26, 28, 13), (38, 30, 12), (48, 36, 10),
             (22, 38, 9), (34, 40, 10), (44, 28, 8), (12, 40, 7)]
    for (x, y, r) in puffs:
        for k, alpha in ((1.0, 46), (0.72, 70), (0.45, 110)):
            rr = r * k
            d.ellipse([S(x - rr), S(y - rr), S(x + rr), S(y + rr)],
                      fill=(203, 184, 154, alpha))
    save(img, path, (W, H))

# ---------------------------------------------------------------- flags
def flag(path, cloth, dark, light):
    W, H = 72, 96
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # pole: dark grey, gold finial ball on top, base at bottom centre
    d.rounded_rectangle([S(33), S(4), S(39), S(94)], radius=S(3), fill=(52, 54, 60, 255))
    d.rounded_rectangle([S(34), S(4), S(38), S(94)], radius=S(2), fill=(96, 100, 110, 255))
    d.ellipse([S(31), S(1), S(41), S(9)], fill=(255, 210, 80, 255))
    d.ellipse([S(33), S(2), S(39), S(7)], fill=(255, 236, 160, 255))
    d.line([S(33), S(4), S(33), S(94)], fill=OUTLINE, width=S(1))
    d.line([S(39), S(4), S(39), S(94)], fill=OUTLINE, width=S(1))
    # waving cloth: flies to the right, two wave peaks
    cloth_pts = [(38, 10), (52, 12), (66, 9), (62, 20), (68, 28),
                 (54, 30), (64, 40), (38, 44)]
    pts = [(S(x), S(y)) for x, y in cloth_pts]
    outline_poly(d, pts, cloth, 2)
    # fold shading: darker band along the lower wave
    shade = [(38, 34), (52, 32), (64, 40), (38, 44)]
    d.polygon([(S(x), S(y)) for x, y in shade], fill=dark)
    # highlight along the upper wave
    hi = [(38, 10), (52, 12), (66, 9), (62, 20), (44, 18)]
    d.polygon([(S(x), S(y)) for x, y in hi], fill=light)
    # white star emblem
    sx, sy, sr = S(50), S(26), S(7)
    star = starburst_points(sx, sy, 5, sr, sr * 0.45, rot=-math.pi / 2, vary=0.0)
    d.polygon(star, fill=(255, 255, 255, 255))
    save(img, path, (W, H))

# ---------------------------------------------------------------- capture burst
def capture_burst(path):
    W, H = 96, 96
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    cx, cy = S(48), S(48)
    draw_starburst(d, cx, cy, 12, S(44), S(16),
                   [(OUTLINE, 1.0)], rot=0.0, vary=0.08, seed=3)
    draw_starburst(d, cx, cy, 12, S(40), S(14),
                   [((255, 170, 30, 255), 1.0), ((255, 220, 90, 255), 0.66),
                    ((255, 250, 200, 255), 0.38)],
                   rot=0.0, vary=0.08, seed=3)
    d.ellipse([cx - S(12), cy - S(12), cx + S(12), cy + S(12)], fill=(255, 255, 255, 255))
    # small orbiting sparks
    for ang in (0.4, 1.8, 3.3, 4.9):
        x = cx + math.cos(ang) * S(40)
        y = cy + math.sin(ang) * S(40)
        d.ellipse([x - S(3), y - S(3), x + S(3), y + S(3)], fill=(255, 220, 90, 255))
    save(img, path, (W, H))

# ---------------------------------------------------------------- items
def ammobox(path):
    W, H = 96, 56
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # olive drab ammo box, lid on top, stencil AMMO
    d.rounded_rectangle([S(6), S(14), S(90), S(50)], radius=S(4), fill=OUTLINE)
    d.rounded_rectangle([S(9), S(17), S(87), S(47)], radius=S(3), fill=(96, 104, 52, 255))
    d.rounded_rectangle([S(9), S(17), S(87), S(26)], radius=S(3), fill=(122, 130, 66, 255))
    d.rectangle([S(9), S(26), S(87), S(29)], fill=(60, 66, 32, 255))
    # handle on the lid
    d.rounded_rectangle([S(38), S(8), S(58), S(16)], radius=S(3), fill=OUTLINE)
    d.rounded_rectangle([S(41), S(10), S(55), S(15)], radius=S(2), fill=(70, 76, 38, 255))
    # corner rivets
    for x, y in ((14, 34), (82, 34), (14, 42), (82, 42)):
        d.ellipse([S(x - 2), S(y - 2), S(x + 2), S(y + 2)], fill=(60, 66, 32, 255))
    # stencil text
    f = ImageFont.truetype(FONT_BOLD, S(13))
    d.text((S(48), S(37)), "AMMO", font=f, fill=(255, 214, 90, 255), anchor="mm")
    save(img, path, (W, H))

def grenade(path):
    W, H = 56, 76
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # pin ring + lever on top, ridged olive body
    d.ellipse([S(38), S(4), S(52), S(18)], outline=OUTLINE, width=S(3))
    d.rounded_rectangle([S(24), S(2), S(34), S(22)], radius=S(3), fill=(90, 96, 100, 255))
    d.rounded_rectangle([S(26), S(4), S(32), S(20)], radius=S(2), fill=(140, 148, 152, 255))
    # lever down the right side
    d.rounded_rectangle([S(34), S(14), S(44), S(40)], radius=S(3), fill=(70, 78, 84, 255))
    # body
    d.rounded_rectangle([S(8), S(20), S(42), S(70)], radius=S(10), fill=OUTLINE)
    d.rounded_rectangle([S(11), S(23), S(39), S(67)], radius=S(8), fill=(74, 107, 47, 255))
    d.rounded_rectangle([S(14), S(26), S(24), S(64)], radius=S(4), fill=(96, 136, 62, 255))
    for y in (34, 46, 58):
        d.line([S(11), S(y), S(39), S(y)], fill=(52, 74, 32, 255), width=S(2))
    save(img, path, (W, H))

def healthkit(path):
    W, H = 64, 64
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([S(6), S(6), S(58), S(58)], radius=S(8), fill=OUTLINE)
    d.rounded_rectangle([S(9), S(9), S(55), S(55)], radius=S(6), fill=(245, 245, 240, 255))
    d.rounded_rectangle([S(9), S(44), S(55), S(55)], radius=S(6), fill=(205, 208, 200, 255))
    # green cross
    d.rounded_rectangle([S(26), S(15), S(38), S(49)], radius=S(2), fill=(34, 160, 70, 255))
    d.rounded_rectangle([S(15), S(26), S(49), S(38)], radius=S(2), fill=(34, 160, 70, 255))
    d.rounded_rectangle([S(28), S(17), S(36), S(47)], radius=S(1), fill=(74, 200, 105, 255))
    save(img, path, (W, H))

def weapon_icon(path):
    W, H = 72, 44
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # rifle pointing right: barrel, body, stock, magazine, grip, sight
    d.rectangle([S(46), S(18), S(68), S(22)], fill=OUTLINE)          # barrel
    d.rectangle([S(48), S(19), S(66), S(21)], fill=(70, 76, 84, 255))
    d.rectangle([S(64), S(16), S(70), S(24)], fill=OUTLINE)          # muzzle
    d.rectangle([S(65), S(17), S(69), S(23)], fill=(120, 126, 132, 255))
    d.rounded_rectangle([S(18), S(15), S(48), S(26)], radius=S(3), fill=OUTLINE)  # body
    d.rounded_rectangle([S(20), S(17), S(46), S(24)], radius=S(2), fill=(58, 64, 72, 255))
    d.polygon([(S(18), S(15)), (S(8), S(19)), (S(8), S(27)), (S(18), S(26))], fill=OUTLINE)  # stock
    d.polygon([(S(17), S(17)), (S(10), S(20)), (S(10), S(25)), (S(17), S(24))], fill=(122, 82, 48, 255))
    d.polygon([(S(28), S(26)), (S(32), S(26)), (S(34), S(36)), (S(28), S(36))], fill=OUTLINE)  # mag
    d.polygon([(S(29), S(26)), (S(31), S(26)), (S(32), S(34)), (S(29), S(34))], fill=(40, 44, 50, 255))
    d.polygon([(S(38), S(26)), (S(43), S(26)), (S(45), S(34)), (S(40), S(34))], fill=OUTLINE)  # grip
    d.polygon([(S(39), S(26)), (S(42), S(26)), (S(43), S(32)), (S(40), S(32))], fill=(122, 82, 48, 255))
    d.rectangle([S(30), S(11), S(36), S(15)], fill=OUTLINE)          # sight
    d.rectangle([S(31), S(12), S(35), S(14)], fill=(140, 148, 152, 255))
    save(img, path, (W, H))

def shield(path):
    W, H = 56, 64
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    pts = [(28, 4), (50, 10), (50, 32), (28, 60), (6, 32), (6, 10)]
    pts = [(S(x), S(y)) for x, y in pts]
    outline_poly(d, pts, (36, 110, 220, 255), 3)
    inner = [(28, 10), (45, 14), (45, 31), (28, 53), (11, 31), (11, 14)]
    d.polygon([(S(x), S(y)) for x, y in inner], fill=(70, 150, 250, 255))
    d.polygon([(S(28), S(10)), (S(45), S(14)), (S(45), S(20)), (S(28), S(17)),
               (S(11), S(14)), (S(11), S(20))], fill=(120, 185, 255, 255))
    star = starburst_points(S(28), S(32), 5, S(11), S(4.5), rot=-math.pi / 2, vary=0.0)
    d.polygon(star, fill=(255, 255, 255, 255))
    save(img, path, (W, H))

# ---------------------------------------------------------------- headgear
def bandana(path):
    W, H = 48, 28
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # red bandana: band across, knot + two tails on the right
    d.rounded_rectangle([S(3), S(6), S(34), S(20)], radius=S(5), fill=OUTLINE)
    d.rounded_rectangle([S(5), S(8), S(32), S(18)], radius=S(4), fill=(200, 40, 40, 255))
    d.rounded_rectangle([S(5), S(8), S(32), S(12)], radius=S(3), fill=(228, 70, 70, 255))
    # fold lines
    for x in (12, 20, 28):
        d.line([S(x), S(9), S(x), S(18)], fill=(160, 25, 25, 255), width=S(1))
    # knot
    d.ellipse([S(31), S(8), S(39), S(17)], fill=OUTLINE)
    d.ellipse([S(33), S(10), S(37), S(15)], fill=(200, 40, 40, 255))
    # tails
    d.polygon([(S(36), S(14)), (S(45), S(24)), (S(40), S(26)), (S(34), S(17))], fill=OUTLINE)
    d.polygon([(S(36), S(15)), (S(43), S(23)), (S(40), S(24)), (S(35), S(16))], fill=(200, 40, 40, 255))
    d.polygon([(S(32), S(16)), (S(36), S(26)), (S(31), S(26)), (S(29), S(17))], fill=OUTLINE)
    d.polygon([(S(32), S(17)), (S(35), S(24)), (S(32), S(24)), (S(30), S(17))], fill=(178, 32, 32, 255))
    save(img, path, (W, H))

def nvg(path):
    W, H = 48, 30
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # night-vision goggles: dark housing, two glowing green lenses
    d.rounded_rectangle([S(4), S(8), S(44), S(24)], radius=S(5), fill=OUTLINE)
    d.rounded_rectangle([S(6), S(10), S(42), S(22)], radius=S(4), fill=(28, 32, 38, 255))
    for cx in (16, 32):
        d.ellipse([S(cx - 7), S(10), S(cx + 7), S(24)], fill=OUTLINE)
        d.ellipse([S(cx - 5), S(12), S(cx + 5), S(22)], fill=(20, 90, 40, 255))
        d.ellipse([S(cx - 3), S(14), S(cx + 3), S(20)], fill=(80, 255, 130, 255))
        d.ellipse([S(cx - 2), S(14), S(cx), S(17)], fill=(220, 255, 230, 255))
    # top knobs
    for cx in (12, 24, 36):
        d.rounded_rectangle([S(cx - 2), S(4), S(cx + 2), S(9)], radius=S(1), fill=(28, 32, 38, 255))
    save(img, path, (W, H))

def camo_helmet(path):
    W, H = 49, 32
    img = canvas(W, H)
    d = ImageDraw.Draw(img)
    # dome + brim, olive base, camo blotches clipped to the dome
    mask = Image.new("L", (W * SS, H * SS), 0)
    md = ImageDraw.Draw(mask)
    md.pieslice([S(4), S(2), S(45), S(40)], 180, 360, fill=255)
    md.rounded_rectangle([S(2), S(18), S(47), S(26)], radius=S(4), fill=255)
    base = Image.new("RGBA", (W * SS, H * SS), (0, 0, 0, 0))
    bd = ImageDraw.Draw(base)
    bd.rectangle([0, 0, S(W), S(H)], fill=(96, 104, 52, 255))
    rnd = random.Random(11)
    for col in ((74, 82, 40, 255), (122, 100, 60, 255), (58, 66, 44, 255), (140, 118, 74, 255)):
        for _ in range(3):
            x, y = rnd.uniform(6, 42), rnd.uniform(4, 22)
            rx, ry = rnd.uniform(4, 8), rnd.uniform(3, 5)
            bd.ellipse([S(x - rx), S(y - ry), S(x + rx), S(y + ry)], fill=col)
    img.paste(base, (0, 0), mask)
    d = ImageDraw.Draw(img)
    d.arc([S(4), S(2), S(45), S(40)], 180, 360, fill=OUTLINE, width=S(3))
    d.rounded_rectangle([S(2), S(18), S(47), S(26)], radius=S(4), outline=OUTLINE, width=S(3))
    d.line([S(3), S(22), S(46), S(22)], fill=OUTLINE, width=S(2))
    save(img, path, (W, H))

# ---------------------------------------------------------------- particle dot
def particle_dot(path):
    # soft radial dot for GPUParticles2D (QA-091 blast burst): white
    # centre fading to transparent, so the tint colour shows through.
    W, H = 32, 32
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    px = img.load()
    for y in range(H):
        for x in range(W):
            d = math.hypot(x - 15.5, y - 15.5) / 16.0
            a = max(0.0, 1.0 - d)
            px[x, y] = (255, 255, 255, int(255 * a * a))
    img.save(path, "PNG")
    print("wrote", path, img.size, img.mode)

# ---------------------------------------------------------------- menu bg
def menu_bg(path):
    from PIL import ImageFilter
    W, H = 1920, 1080
    SS2 = 2
    img = Image.new("RGB", (W * SS2, H * SS2))
    d = ImageDraw.Draw(img, "RGBA")
    rnd = random.Random(21)
    # dusk sky: smooth vertical gradient (low-res ramp, bicubic upscaled)
    stops = [(0.00, (8, 12, 34)), (0.30, (16, 24, 58)), (0.48, (52, 34, 78)),
             (0.58, (122, 52, 62)), (0.64, (198, 96, 48)), (0.68, (24, 18, 34))]
    ramp = Image.new("RGB", (1, 512))
    rp = ramp.load()
    for y in range(512):
        t = y / 511 * 0.68
        for i in range(len(stops) - 1):
            t0, c0 = stops[i]
            t1, c1 = stops[i + 1]
            if t0 <= t <= t1:
                f = (t - t0) / max(1e-6, t1 - t0)
                rp[0, y] = tuple(int(c0[k] + (c1[k] - c0[k]) * f) for k in range(3))
                break
        else:
            rp[0, y] = stops[-1][1]
    sky_img = ramp.resize((W * SS2, int(H * SS2 * 0.68)), Image.BICUBIC)
    img.paste(sky_img, (0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    # stars in the upper sky
    for _ in range(220):
        x = rnd.uniform(0, W * SS2)
        y = rnd.uniform(0, H * SS2 * 0.42)
        r = rnd.uniform(0.8, 2.2) * SS2
        a = rnd.randint(90, 220)
        d.ellipse([x - r, y - r, x + r, y + r], fill=(255, 255, 255, a))
    # low sun glow on the horizon: blurred radial glow, clipped above the wall
    glow = Image.new("RGBA", (W * SS2, H * SS2), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gy = H * SS2 * 0.66
    for r, a in ((520, 90), (380, 120), (250, 150), (150, 180)):
        gd.ellipse([W * SS2 * 0.5 - r * SS2, gy - r * SS2 * 0.62,
                    W * SS2 * 0.5 + r * SS2, gy + r * SS2 * 0.62],
                   fill=(255, 150, 70, a))
    glow = glow.filter(ImageFilter.GaussianBlur(90 * SS2))
    img.paste(Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB"), (0, 0))
    d = ImageDraw.Draw(img, "RGBA")
    # distant mountains
    mtn = [(0, 0.66), (0.08, 0.58), (0.16, 0.63), (0.24, 0.55), (0.33, 0.62),
           (0.42, 0.57), (0.52, 0.64), (0.62, 0.56), (0.72, 0.63),
           (0.82, 0.58), (0.92, 0.64), (1.0, 0.60)]
    pts = [(x * W * SS2, y * H * SS2) for x, y in mtn] + [(W * SS2, H * SS2 * 0.68), (0, H * SS2 * 0.68)]
    d.polygon(pts, fill=(22, 20, 44, 255))
    # far arena wall silhouette with watchtowers (edges only — centre stays clear)
    d.rectangle([0, H * SS2 * 0.66, W * SS2, H * SS2 * 0.70], fill=(16, 18, 34, 255))
    for tx in (0.06, 0.94):
        x0 = tx * W * SS2
        d.rectangle([x0 - 26 * SS2, H * SS2 * 0.56, x0 + 26 * SS2, H * SS2 * 0.70], fill=(14, 16, 30, 255))
        d.polygon([(x0 - 34 * SS2, H * SS2 * 0.56), (x0 + 34 * SS2, H * SS2 * 0.56),
                   (x0 + 20 * SS2, H * SS2 * 0.52), (x0 - 20 * SS2, H * SS2 * 0.52)], fill=(14, 16, 30, 255))
        # floodlight head + soft cone (low alpha, aimed inward/down)
        d.ellipse([x0 - 10 * SS2, H * SS2 * 0.545, x0 + 10 * SS2, H * SS2 * 0.575], fill=(255, 240, 190, 255))
        inward = 1 if tx < 0.5 else -1
        d.polygon([(x0, H * SS2 * 0.56), (x0 + inward * 260 * SS2, H * SS2 * 0.86),
                   (x0 + inward * 420 * SS2, H * SS2 * 0.86)], fill=(255, 235, 170, 22))
    # ground: dark, smooth gradient (low-res ramp upscaled)
    gramp = Image.new("RGB", (1, 256))
    gp = gramp.load()
    for y in range(256):
        t = y / 255
        gp[0, y] = tuple(int(18 + 10 * t) for _ in range(3))
    gnd = gramp.resize((W * SS2, int(H * SS2 * 0.30)), Image.BICUBIC)
    img.paste(gnd, (0, int(H * SS2 * 0.70)))
    d = ImageDraw.Draw(img, "RGBA")
    # ground detail at the edges: crates + barriers, never in the centre
    for gx, gw, gh in ((0.03, 90, 60), (0.10, 60, 44), (0.88, 70, 50), (0.95, 90, 62)):
        x0, y0 = gx * W * SS2, H * SS2 - gh * SS2
        d.rectangle([x0, y0, x0 + gw * SS2, H * SS2], fill=(20, 22, 36, 255))
        d.line([x0, y0, x0 + gw * SS2, y0], fill=(40, 44, 64, 255), width=2 * SS2)
    # hazard stripe on the front edge (subtle, dark yellow)
    for i in range(0, int(W * SS2), 90 * SS2):
        d.polygon([(i, H * SS2), (i + 45 * SS2, H * SS2),
                   (i + 70 * SS2, H * SS2 - 14 * SS2), (i + 25 * SS2, H * SS2 - 14 * SS2)],
                  fill=(150, 120, 30, 90))
    # vignette: darken the corners so the menu UI pops
    vig = Image.new("L", (W * SS2, H * SS2), 0)
    vd = ImageDraw.Draw(vig)
    vd.ellipse([-W * SS2 * 0.25, -H * SS2 * 0.25, W * SS2 * 1.25, H * SS2 * 1.25], fill=255)
    vig = vig.point(lambda p: 255 - int((255 - p) * 0.55))
    black = Image.new("RGB", (W * SS2, H * SS2), (0, 0, 0))
    img = Image.composite(img, black, vig)
    img = img.resize((W, H), Image.LANCZOS)
    img.save(path, "PNG")
    print("wrote", path, img.size, img.mode)

if __name__ == "__main__":
    import os
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    flame("assets/effects/jetpack_flame.png")
    muzzle("assets/effects/muzzle_pistol.png", 48, 24, 3, 20, 7, 0.55, 11, 5)
    muzzle("assets/effects/muzzle_rifle.png", 64, 28, 4, 26, 9, 0.6, 12, 6)
    muzzle("assets/effects/muzzle_shotgun.png", 80, 40, 6, 32, 11, 0.7, 13, 8)
    muzzle("assets/effects/muzzle_sniper.png", 88, 20, 4, 40, 7, 0.35, 14, 5)
    muzzle("assets/effects/muzzle_rocket.png", 72, 56, 8, 28, 12, 0.95, 15, 10)
    trail("assets/effects/bullet_trail.png")
    dust("assets/effects/dust.png")
    flag("assets/effects/flag_red.png", (214, 48, 48, 255), (160, 28, 28, 255), (238, 96, 96, 255))
    flag("assets/effects/flag_blue.png", (52, 110, 230, 255), (30, 70, 180, 255), (96, 150, 245, 255))
    capture_burst("assets/effects/capture_burst.png")
    ammobox("assets/items/ammobox.png")
    grenade("assets/items/grenade.png")
    healthkit("assets/items/healthkit.png")
    weapon_icon("assets/items/weapon.png")
    shield("assets/items/shield.png")
    bandana("assets/headgear/bandana_red.png")
    nvg("assets/headgear/nvg.png")
    camo_helmet("assets/headgear/helmet_camo.png")
    particle_dot("assets/effects/particle_dot.png")
    menu_bg("assets/backgrounds/menu_arena_dusk.png")
    print("ALL DONE")
