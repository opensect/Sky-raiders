#!/usr/bin/env python3
"""v3.7 Ironfall assets (QA-095/096): slice the Operation Ironfall sheets
into transparent sprites + draw tile_ironfall / bg_ironfall /
thumb_ironfall / thumb_neon with PIL only (no Gemini).

Background removal: the sheets are RGB on a near-uniform dark
blue-grey background (~25-41 brightness), and the sprite stone is
nearly as dark, so the Jungle brightness ramp would eat the stone.
Instead: flood-fill the background from the crop border (pixels
within colour distance 14 of the border-median background colour),
feather 0.7 px. Enclosed dark interiors (cave mouths, pure black)
are NOT connected to the border, so they stay opaque; pure-black
pixels (brightness < 10) are restored to opaque near-black after
the fill, so cave mouths stay dark instead of showing the sky.
Every output is verified on magenta + dark-green backgrounds.
"""
import os
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(ROOT, "assets", "ironfall")
OUT = os.path.join(ROOT, "assets", "ironfall_sliced")
os.makedirs(OUT, exist_ok=True)

# (sheet, name, x, y, w, h) — hand-boxed from visual inspection of
# each sheet (see BUGS.md QA-096).
BOXES = [
    ("09_extra_structures.png", "if_tower", 157, 20, 53, 93),
    ("09_extra_structures.png", "if_gantry", 228, 35, 101, 79),
    ("09_extra_structures.png", "if_derrick", 344, 20, 52, 93),
    ("03_bridges_platforms.png", "if_bridge", 5, 130, 117, 34),
    ("03_bridges_platforms.png", "if_bridge_metal", 145, 91, 171, 27),
    ("03_bridges_platforms.png", "if_plank", 143, 170, 171, 21),
    ("04_tunnels_caves.png", "if_cave", 11, 27, 123, 79),
    ("04_tunnels_caves.png", "if_cave2", 147, 30, 123, 76),
    ("04_tunnels_caves.png", "if_cavern", 281, 21, 262, 134),
    ("04_tunnels_caves.png", "if_rockledge", 11, 118, 111, 37),
    ("08_special_environment.png", "if_water", 6, 33, 159, 84),
    ("08_special_environment.png", "if_fall", 170, 28, 48, 92),
    ("08_special_environment.png", "if_spikes", 230, 28, 72, 86),
    ("08_special_environment.png", "if_vent", 323, 28, 74, 88),
    ("08_special_environment.png", "if_door", 402, 28, 46, 88),
    ("05_objects_props.png", "if_crate", 140, 13, 34, 51),
    ("05_objects_props.png", "if_barrel", 232, 26, 26, 40),
    ("05_objects_props.png", "if_sandbags", 144, 76, 47, 28),
    ("05_objects_props.png", "if_lamp", 344, 115, 22, 38),
    ("06_nature_decor.png", "if_palm", 5, 31, 120, 123),
    ("06_nature_decor.png", "if_vines", 257, 78, 130, 61),
    ("06_nature_decor.png", "if_rock", 127, 83, 114, 30),
    ("06_nature_decor.png", "if_tree", 389, 94, 56, 59),
    ("02_structures_buildings.png", "if_bunker", 235, 29, 126, 145),
    ("02_structures_buildings.png", "if_arch", 375, 17, 106, 157),
    ("02_structures_buildings.png", "if_comms", 505, 16, 86, 167),
]

from scipy import ndimage


def slice_one(sheet, name, x, y, w, h):
    im = Image.open(os.path.join(SRC, sheet)).convert("RGB")
    pad = 4
    x0 = max(0, x - pad); y0 = max(0, y - pad)
    x1 = min(im.width, x + w + pad); y1 = min(im.height, y + h + pad)
    crop = np.array(im.crop((x0, y0, x1, y1))).astype(np.float32)
    H, W, _ = crop.shape
    # background colour = median of the border pixels
    border = np.concatenate([crop[0].reshape(-1, 3), crop[-1].reshape(-1, 3),
                             crop[:, 0].reshape(-1, 3), crop[:, -1].reshape(-1, 3)])
    bg = np.median(border, axis=0)
    dist = np.sqrt(((crop - bg) ** 2).sum(axis=2))
    near_bg = dist < 14
    # flood-fill: only the near-bg components touching the border go
    lab, n = ndimage.label(near_bg)
    border_labels = set(np.unique(np.concatenate(
        [lab[0], lab[-1], lab[:, 0], lab[:, -1]]))) - {0}
    flood = np.isin(lab, list(border_labels))
    deep_black = crop.max(axis=2) < 10  # cave mouths etc.
    alpha = np.where(flood, 0.0, 255.0)
    alpha = ndimage.gaussian_filter(alpha, 0.7)
    alpha[alpha < 10] = 0
    # restore pure-black interiors as opaque near-black
    alpha[deep_black] = 255
    crop[deep_black] = [6, 6, 9]
    # clear 3 px corner discs
    yy, xx = np.ogrid[:H, :W]
    for cx, cy in [(0, 0), (W - 1, 0), (0, H - 1), (W - 1, H - 1)]:
        alpha[((xx - cx) ** 2 + (yy - cy) ** 2) <= 9] = 0
    out = np.dstack([np.clip(crop, 0, 255).astype(np.uint8),
                     np.clip(alpha, 0, 255).astype(np.uint8)])
    Image.fromarray(out, "RGBA").save(os.path.join(OUT, name + ".png"))
    transp = float((alpha == 0).mean() * 100)
    corners = [int(alpha[0, 0]), int(alpha[0, -1]), int(alpha[-1, 0]), int(alpha[-1, -1])]
    print(f"{name}: {W}x{H} transparent={transp:.1f}% corners={corners}")
    return out


def verify_contact_sheet():
    """All slices on magenta + on dark green, one sheet each."""
    files = sorted(os.listdir(OUT))
    files = [f for f in files if f.endswith(".png")]
    cell = 180
    cols = 5
    rows = (len(files) + cols - 1) // cols
    for bgname, bg in [("magenta", (255, 0, 255)), ("darkgreen", (10, 60, 25))]:
        sheet = Image.new("RGB", (cols * cell, rows * cell), bg)
        for i, f in enumerate(files):
            im = Image.open(os.path.join(OUT, f)).convert("RGBA")
            im.thumbnail((cell - 8, cell - 8))
            sheet.paste(im, ((i % cols) * cell + 4, (i // cols) * cell + 4), im)
        sheet.save(f"/tmp/ironfall_contact_{bgname}.png")
    print("contact sheets: /tmp/ironfall_contact_magenta.png, /tmp/ironfall_contact_darkgreen.png")


# ---------------------------------------------------------------- code-drawn
def draw_tile_ironfall():
    """128x48 iron plate tile, tiling continuous left-to-right:
    dark gunmetal plates, rivets, rust-orange top edge; the left and
    right edge columns are the same dark outline, like the other tiles."""
    S = 4
    w, h = 128 * S, 48 * S
    im = Image.new("RGB", (w, h), (38, 42, 48))
    d = ImageDraw.Draw(im)
    # body: steel plates
    d.rectangle([0, 10 * S, w, h], fill=(44, 49, 57))
    d.rectangle([0, 10 * S, w, 13 * S], fill=(52, 58, 67))
    # vertical plate seams (kept off the edges so the joint is clean)
    for x in (32, 64, 96):
        d.rectangle([x * S - S, 10 * S, x * S, h], fill=(28, 31, 37))
        d.rectangle([x * S, 10 * S, x * S + S, h], fill=(60, 66, 76))
    # horizontal seam
    d.rectangle([0, 30 * S, w, 31 * S], fill=(28, 31, 37))
    # rivets
    for x in (16, 48, 80, 112):
        for yy in (20, 40):
            d.ellipse([x * S - 2 * S, yy * S - 2 * S, x * S + 2 * S, yy * S + 2 * S],
                      fill=(70, 76, 86), outline=(20, 22, 26))
    # rust-orange top edge (walkable top), dark outline below it
    d.rectangle([0, 0, w, 9 * S], fill=(176, 92, 26))
    d.rectangle([0, 7 * S, w, 10 * S], fill=(120, 58, 16))
    d.rectangle([0, 0, w, 2 * S], fill=(214, 128, 48))
    # hazard ticks on the top edge
    for x in range(0, 128, 16):
        d.polygon([(x * S, 9 * S), ((x + 8) * S, 9 * S), ((x + 4) * S, 2 * S)],
                  fill=(40, 36, 30))
    # dark outline at both side edges (shared joint line)
    d.rectangle([0, 0, S, h], fill=(22, 24, 28))
    d.rectangle([w - S, 0, w, h], fill=(22, 24, 28))
    im = im.resize((128, 48), Image.LANCZOS)
    im.save(os.path.join(ROOT, "assets", "tiles", "tile_ironfall.png"))
    a = np.array(im)
    print("tile_ironfall: left-vs-right edge col mean diff:",
          float(np.abs(a[:, 0].astype(int) - a[:, -1].astype(int)).mean()))


def draw_bg_ironfall():
    """960x540 far-parallax background: dusk steel-blue sky, low
    orange sun glow, distant factory skyline + smokestacks + crane
    silhouettes. Horizon features span the full width so the
    mirrored parallax copy (mirrored at 1286) has no hard seam."""
    S = 2
    w, h = 960 * S, 540 * S
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for yy in range(h):
        t = yy / h
        r = int(58 + (24 - 58) * t); g = int(70 + (30 - 70) * t); b = int(102 + (48 - 102) * t)
        d.line([(0, yy), (w, yy)], fill=(r, g, b))
    # sun glow, low centre-left
    glow = Image.new("RGB", (w, h), (0, 0, 0))
    gd = ImageDraw.Draw(glow)
    gd.ellipse([(300 * S, 300 * S), (560 * S, 560 * S)], fill=(255, 140, 50))
    glow = glow.filter(ImageFilter.GaussianBlur(60 * S))
    im = Image.fromarray(np.clip(np.array(im).astype(int) + np.array(glow).astype(int) * 0.55, 0, 255).astype(np.uint8))
    d = ImageDraw.Draw(im)
    # far skyline (dark blue-grey), full width
    import random
    rnd = random.Random(7)
    x = 0
    while x < w:
        bw = rnd.randint(50, 130) * S
        bh = rnd.randint(60, 150) * S
        d.rectangle([x, 400 * S - bh, x + bw, 400 * S], fill=(30, 36, 52))
        x += bw + rnd.randint(4, 20) * S
    # smokestacks with smoke puffs
    for sx in (180 * S, 700 * S, 860 * S):
        d.rectangle([sx, 250 * S, sx + 18 * S, 400 * S], fill=(26, 31, 44))
        d.rectangle([sx - 3 * S, 244 * S, sx + 21 * S, 252 * S], fill=(26, 31, 44))
        for i, (ox, oy, r) in enumerate([(0, -18, 12), (10, -34, 16), (-8, -50, 20)]):
            d.ellipse([sx + ox * S - r * S, 240 * S + oy * S - r * S,
                       sx + ox * S + r * S, 240 * S + oy * S + r * S],
                      fill=(90, 95, 110))
    # crane silhouette, right side
    d.rectangle([760 * S, 200 * S, 772 * S, 400 * S], fill=(24, 28, 40))
    d.rectangle([700 * S, 196 * S, 900 * S, 206 * S], fill=(24, 28, 40))
    d.line([(772 * S, 200 * S), (700 * S, 280 * S)], fill=(24, 28, 40), width=4 * S)
    # near ridge (darker), full width
    d.rectangle([0, 400 * S, w, h], fill=(18, 22, 32))
    x = 0
    while x < w:
        bw = rnd.randint(80, 200) * S
        bh = rnd.randint(20, 70) * S
        d.polygon([(x, 400 * S), (x + bw // 2, 400 * S - bh), (x + bw, 400 * S)],
                  fill=(18, 22, 32))
        x += bw
    im = im.resize((960, 540), Image.LANCZOS)
    im.save(os.path.join(ROOT, "assets", "skybrawl", "maps", "bg_ironfall.png"))
    print("bg_ironfall: 960x540 saved")


def draw_thumb(name, sky_top, sky_bot, ground, accent, cue):
    """96x64 thumbnail, no text: gradient sky, ground + 2 platforms,
    one theme cue. Matches the Part 2 thumb style."""
    S = 4
    w, h = 96 * S, 64 * S
    im = Image.new("RGB", (w, h))
    d = ImageDraw.Draw(im)
    for yy in range(h):
        t = yy / h
        c = tuple(int(sky_top[i] + (sky_bot[i] - sky_top[i]) * t) for i in range(3))
        d.line([(0, yy), (w, yy)], fill=c)
    if cue == "sun":
        d.ellipse([(66 * S, 8 * S), (86 * S, 28 * S)], fill=accent)
    elif cue == "neon":
        for cx, cy, r in [(20, 14, 6), (70, 10, 5), (48, 20, 4)]:
            d.ellipse([(cx - r) * S, (cy - r) * S, (cx + r) * S, (cy + r) * S], fill=accent)
        d.rectangle([0, 30 * S, w, 32 * S], fill=accent)
    elif cue == "tower":
        d.rectangle([68 * S, 12 * S, 78 * S, 44 * S], fill=(30, 34, 42))
        d.polygon([(66 * S, 12 * S), (80 * S, 12 * S), (73 * S, 4 * S)], fill=(176, 92, 26))
        d.rectangle([70 * S, 18 * S, 76 * S, 24 * S], fill=accent)
    d.rectangle([0, 44 * S, w, h], fill=ground)
    d.rectangle([0, 44 * S, w, 47 * S], fill=accent)
    d.rectangle([10 * S, 34 * S, 34 * S, 40 * S], fill=ground)
    d.rectangle([10 * S, 34 * S, 34 * S, 36 * S], fill=accent)
    d.rectangle([62 * S, 30 * S, 88 * S, 36 * S], fill=ground)
    d.rectangle([62 * S, 30 * S, 88 * S, 32 * S], fill=accent)
    im = im.resize((96, 64), Image.LANCZOS)
    im.save(os.path.join(ROOT, "assets", "thumbs", name))
    print(name, "saved")


if __name__ == "__main__":
    for sheet, name, x, y, w, h in BOXES:
        slice_one(sheet, name, x, y, w, h)
    verify_contact_sheet()
    draw_tile_ironfall()
    draw_bg_ironfall()
    draw_thumb("thumb_ironfall.png", (52, 62, 92), (24, 26, 40), (44, 49, 57),
               (214, 128, 48), "tower")
    draw_thumb("thumb_neon.png", (38, 16, 74), (120, 40, 130), (22, 18, 44),
               (255, 80, 200), "neon")
