#!/usr/bin/env python3
"""No-stuck audit, v3.7 rewrite of the QA-063 /tmp/audit_gaps.py
(the original lived in /tmp and is gone). Parses MAPS + decor
textures + DECOR_INSETS + SOLID_DECOR_KINDS / BRIDGE_DECOR_KINDS
from game.gd; player capsule 34 px wide, 86 px tall, normal jump
apex ~137 px.

Trap definition (QA-063): a ground-level slot in [34,60) px that
the player can enter (jump over the lower wall, or drop in from a
platform above) but cannot jump out of (headroom-capped max rise
< wall height). Platform-level gaps are open underneath, not
traps, but still counted as TIGHT.
"""
import re
import sys
from PIL import Image

GD = "/home/hatch/workspace/mini-militia-lan/game.gd"
ASSETS = "/home/hatch/workspace/mini-militia-lan/assets"
src = open(GD).read()

# --- texture sizes for decor kinds (from DECOR_TEX preloads)
tex = {}
for kind, path in re.findall(r'"(\w+)": DECOR_(\w+),', src):
    pass
# simpler: map kind -> file via the const preloads
consts = dict(re.findall(r'const DECOR_(\w+): Texture2D = preload\("res://([^"]+)"\)', src))
decor_tex = dict(re.findall(r'"(\w+)": DECOR_(\w+),', src))
for kind, const in decor_tex.items():
    if const in consts:
        p = consts[const].replace("assets/", ASSETS + "/")
        tex[kind] = Image.open(p).size
# generic decor consts (crate etc.) are DECOR_CRATE-style names
for kind, const in re.findall(r'"(\w+)": (DECOR_\w+),', src):
    pass
generic = {"crate": "assets/tiles/crate.png", "barrels": "assets/tiles/barrels.png",
           "sandbags": "assets/tiles/sandbags.png", "palms": "assets/tiles/palms.png",
           "rock": "assets/tiles/rock.png", "bridge": "assets/tiles/wood_bridge.png",
           "column": "assets/tiles/stone_column.png"}
for kind, path in generic.items():
    tex[kind] = Image.open(ASSETS + "/" + path.split("assets/")[1]).size

solid = set(re.findall(r'const SOLID_DECOR_KINDS := \[(.*?)\]', src, re.S)[0].replace('"', '').replace(',', ' ').split())
insets = dict((k, int(v)) for k, v in re.findall(r'"(\w+)": (\d+)', src[src.index("const DECOR_INSETS"):src.index("func _build_arena")]))

# --- parse MAPS: split on "name": and take blocks
maps_src = src[src.index("const MAPS := ["):src.index("const DECOR_TEX")]
blocks = maps_src.split('"name":')[1:]
CAP_W, CAP_H, APEX = 34.0, 86.0, 137.0
total_trap = total_tight = 0
for b in blocks:
    name = b.split('"')[1]
    size = re.search(r'"size": Vector2\((\d+), (\d+)\)', b)
    W, H = int(size.group(1)), int(size.group(2))
    plats = [tuple(map(float, m)) for m in re.findall(r'Rect2\(([\d.]+), ([\d.]+), ([\d.]+), ([\d.]+)\)', b.split('"platforms"')[1].split('"spawns"')[0])]
    decor = re.findall(r'\["(\w+)", (\d+), (\d+)\]', b)
    solids = [tuple(map(float, p)) for p in plats]
    # walls + ceiling
    solids.append((0, 0, 24, H)); solids.append((W - 24, 0, 24, H)); solids.append((0, 0, W, 24))
    for kind, x, y in decor:
        if kind in solid:
            w, h = tex[kind]
            ins = insets.get(kind, 6)
            w2, h2 = max(8.0, w - ins * 2), max(8.0, h - ins)
            solids.append((int(x) - w2 / 2, int(y) - h + ins, w2, h2))
    # slots: horizontal gaps between solids whose y-ranges overlap
    issues = []
    n = len(solids)
    for i in range(n):
        ax, ay, aw, ah = solids[i]
        for j in range(n):
            if i == j:
                continue
            bx, by, bw, bh = solids[j]
            if bx < ax + aw:
                continue
            gap = bx - (ax + aw)
            if not (CAP_W <= gap < 60):
                continue
            # vertical overlap of the two walls
            ov_top = max(ay, by); ov_bot = min(ay + ah, by + bh)
            if ov_bot - ov_top < 20:
                continue
            # slot floor = the lower of the two bottoms (the ground
            # the player stands on inside the slot)
            floor_y = max(ay + ah, by + bh)
            # headroom: lowest solid bottom above the slot floor,
            # within the slot's x-range
            head = None
            for (cx, cy, cw, ch) in solids:
                if cx < bx and cx + cw > ax + aw and cy + ch > floor_y and cy < floor_y:
                    pass
            for (cx, cy, cw, ch) in solids:
                if cx + cw > ax + aw and cx < bx and cy >= floor_y - 1 and cy + ch <= floor_y:
                    continue
            # find any solid whose bottom edge is above the slot
            # floor and whose x-range covers the slot centre
            midx = ax + aw + gap / 2
            above = [cy + ch for (cx, cy, cw, ch) in solids
                     if cx <= midx <= cx + cw and cy + ch <= floor_y + 1 and cy + ch > floor_y - 400]
            # the platform the slot stands on: its top is floor_y;
            # headroom is the distance to the next solid ABOVE that
            # overhangs the slot (a platform whose bottom is above
            # floor_y and spans the slot)
            overhang = [cy for (cx, cy, cw, ch) in solids
                        if cx <= midx <= cx + cw and cy > floor_y and cy - floor_y < 400]
            headroom = min(overhang) - floor_y if overhang else 9999.0
            wall_h = min(ah, bh)
            # ground-level slot: its floor is a platform top (within
            # 2 px of some platform's top) — otherwise it is a
            # platform-level gap, open underneath.
            ground = any(abs(floor_y - (py + ph)) < 2.0 for (_, py, _, ph) in plats)
            max_rise = min(APEX, headroom - CAP_H)
            is_trap = ground and max_rise < wall_h
            issues.append((gap, ax + aw, floor_y, wall_h, headroom, max_rise, is_trap))
    # dedupe by (gap x, floor)
    seen = {}
    for g in issues:
        seen.setdefault((round(g[1]), round(g[2])), g)
    traps = [g for g in seen.values() if g[6]]
    tights = [g for g in seen.values() if not g[6]]
    total_trap += len(traps); total_tight += len(tights)
    print(f"{name}: {len(traps)} TRAP, {len(tights)} TIGHT ({len(plats)} platforms)")
    for gap, x, fy, wh, hr, mr, trap in sorted(seen.values()):
        print(f"   {'TRAP' if trap else 'TIGHT'} gap={gap:.0f}px at x={x:.0f} floor_y={fy:.0f} wall_h={wh:.0f} headroom={hr:.0f} max_rise={mr:.0f}")
print(f"TOTAL: {total_trap} TRAP / {total_tight} TIGHT")
sys.exit(1 if total_trap or total_tight else 0)
