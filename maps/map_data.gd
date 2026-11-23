class_name MapData
extends RefCounted


# QA-140 (v3.15): the map table, moved out of game.gd so no .gd file
# is over 1000 lines. game.gd keeps a 1-line alias
# (`const MAPS := MapData.MAPS`), so every existing `game.MAPS`
# reference keeps working unchanged. Data only — no logic.


const MAPS := [
# QA-095 (v3.7): 5 maps only, in this order — Ironfall,
# Neon City, Volcanic Cavern, Pirate Island, Skyfall.
# QA-146 (v4.2): Outpost (map 1, added QA-145) DELETED entirely;
# Skyfall is now map index 4.
# The other 8 maps are deleted (map data, tiles, thumbs,
# backgrounds, lobby entries — nothing references them).
	{
		# QA-143 (v4.0) — REBUILT from the real the reference game
		# Outpost map (1outpost_new.tmx, unpacked from the classic
		# APK: assets/hd/1outpost_new.tmx, 52x18 tiles of 128 px =
		# 6656x2304). The TMX "tile" layer is the solid terrain;
		# rows 2-11 are the platforms above the floor (floor top
		# y1536), rows 12-17 the solid base mass with a central
		# chasm (1 tile wide at the surface, widening below).
		# Object coords in the TMX sit in the left half only on
		# every classic map checked (Outpost, High Tower,
		# Crossfire) — read as half-width space (x2 = full map),
		# which puts team spawns at opposite ends (ctf_sp_1
		# x155-736 vs ctf_sp_2 x2587-3093) and the flags at
		# fp_1 x224 / fp_2 x2874.
		# Mapping onto Ironfall's 3200x1400 (x * 3200/6656,
		# y mapped floor 1536 -> 1352 and top platform 256 ->
		# 330, then snapped to Ironfall's 170 px tiers):
		# Outpost's per-row runs become the tier runs below —
		# one high perch, a 4-spread tier, dense staggered
		# mid tiers, long lower shelves. Two adjacent Outpost
		# rows land on each 170 px tier and merge where they
		# overlap; the 1180 tier's merged 862 px run is split
		# back into two (1538-1908 / 2092-2400) so the gap
		# stays a passage, and the 62 px nub is joined to the
		# left shelf (492-800). Kept from Ironfall: the central
		# peak fortress (1400-1800 @ 330, bunker + comms + red
		# flag) — Outpost's highest platform is upper-left, so
		# that perch is kept TOO (308-615 @ 330) as the second
		# summit; the floor stays one full slab (Outpost's
		# central chasm is NOT cut — the waterfall pool sits
		# at bottom centre x1600 and the slab is only 48 px
		# thick, so a pit would be a death hole). Spawns stay
		# 6 left / 6 right, one per tier, re-anchored to the
		# new platform tops; pickups re-anchored the same way
		# (5 of 6 kept their exact spots; #0 moved 300 -> 750
		# on the y1180 left shelf — its old floor spot sat on
		# spawn#0's feet and the spawning player collected the
		# SMG at once, tripping P00). All 30 platforms
		# reachable from spawn#0 (validator: <=320 up,
		# <=340 across, <=420 down); every tier step up has
		# a zero-gap route. Size class unchanged (3200x1400).
		"name": "Ironfall", "size": Vector2(3200, 1400), "tile": 0,
		"bg": 0,
		"sky_top": Color(0.13, 0.16, 0.28), "sky_bottom": Color(0.45, 0.30, 0.22),
		"hill": Color(0.10, 0.12, 0.20), "sun": Color(1.00, 0.95, 0.80), "fx": "dust",
		"platforms": [
			Rect2(0, 1352, 3200, 48),
			# y330 — Outpost row 2 (upper-left high perch) + the
			# Ironfall central peak fortress (kept, QA-111).
			Rect2(308, 330, 307, 48),
			Rect2(1400, 330, 400, 48),
			# y500 — Outpost rows 3+4.
			Rect2(308, 500, 307, 48),
			Rect2(862, 500, 123, 48),
			Rect2(1108, 500, 246, 48),
			Rect2(2031, 500, 246, 48),
			Rect2(2585, 500, 184, 48),
			# y670 — Outpost rows 5+6 (long left shelf 185-677).
			Rect2(185, 670, 492, 48),
			Rect2(862, 670, 123, 48),
			Rect2(1108, 670, 246, 48),
			Rect2(1662, 670, 246, 48),
			Rect2(2092, 670, 123, 48),
			Rect2(2462, 670, 246, 48),
			Rect2(2831, 670, 123, 48),
			# y840 — Outpost row 7 (long left shelf 185-800).
			Rect2(185, 840, 615, 48),
			Rect2(1477, 840, 431, 48),
			Rect2(2277, 840, 308, 48),
			Rect2(2831, 840, 123, 48),
			# y1010 — Outpost rows 8+9.
			Rect2(246, 1010, 554, 48),
			Rect2(985, 1010, 307, 48),
			Rect2(1477, 1010, 369, 48),
			Rect2(2154, 1010, 308, 48),
			Rect2(2708, 1010, 123, 48),
			Rect2(2892, 1010, 123, 48),
			# y1180 — Outpost rows 10+11; the merged centre run
			# is split (1538-1908 / 2092-2400) to keep the gap.
			Rect2(492, 1180, 308, 48),
			Rect2(862, 1180, 430, 48),
			Rect2(1538, 1180, 370, 48),
			Rect2(2092, 1180, 308, 48),
			Rect2(2585, 1180, 492, 48),
		],
		"spawns": [Vector2(300, 1318), Vector2(900, 1318), Vector2(1100, 1146), Vector2(600, 976), Vector2(700, 806), Vector2(500, 636), Vector2(2100, 1318), Vector2(2900, 1318), Vector2(2200, 1146), Vector2(2300, 976), Vector2(2300, 806), Vector2(2550, 636)],
		"pickups": [Vector2(750, 1150), Vector2(2700, 1150), Vector2(1500, 1320), Vector2(1600, 810), Vector2(400, 640), Vector2(2250, 470)],
		"decor": [["if_palm", 150, 1352], ["if_derrick", 420, 1352], ["crate", 750, 1352], ["if_vent", 700, 1352], ["if_sandbags", 650, 1180], ["barrels", 950, 1352], ["if_door", 1050, 1352], ["if_cave", 1150, 1352], ["if_lamp", 1300, 1352], ["if_bridge_metal", 1600, 1180], ["crate", 1500, 1010], ["if_lamp", 1700, 1352], ["if_cave2", 1850, 1352], ["column", 2000, 1352], ["if_plank", 2150, 1180], ["if_tower", 500, 670], ["if_gantry", 900, 1180], ["if_rockledge", 600, 1010], 		# QA-145 (v4.1, Worker W): the 125 px if_bridge sprite
		# (2646-2770) floated in the 246 px gap between the
		# (2277,840) shelf and the (2831,840) perch — 61 px short
		# of both ends, 0% supported (screenshot-verified). It
		# cannot span that gap, so it now rests on the left
		# 840 shelf (2368-2493, fully on 2277-2585), next to
		# the gap it was meant to mark.
		["if_bridge", 2430, 840], ["barrels", 2400, 1010], ["if_barrel", 2300, 1352], ["if_rock", 2400, 1352], ["if_spikes", 2500, 1352], ["if_crate", 2600, 1352], ["if_fall", 1600, 1352], ["if_water", 1600, 1352], ["if_bunker", 1500, 330], ["if_comms", 1680, 330], ["if_tower", 2900, 670], ["if_bridge_metal", 2770, 670], ["if_palm", 600, 670], ["if_palm", 2800, 1010], ["if_cave", 450, 1352]],
	},
	{
		"name": "Neon City", "size": Vector2(3400, 1800), "tile": 2,
		# QA-145 (v4.1, Worker U): "bg" REMOVED — bg_neon.png has
		# baked-in platform pills + a sign that read as REAL
		# platforms in play (players try to land on them and fall
		# through). The map now keeps the full procedural gradient
		# (dark purple dusk) like Pirate Island — calm, no fake
		# shapes. BG_TEX[2] stays preloaded (indices must not
		# shift); the lobby map card still uses bg_neon.png.
		"sky_top": Color(0.05, 0.04, 0.16), "sky_bottom": Color(0.16, 0.10, 0.32),
		"hill": Color(0.08, 0.06, 0.20), "sun": Color(1.00, 0.45, 0.75), "fx": "rain",
		"platforms": [
			Rect2(0, 1752, 1450, 48),
			Rect2(1950, 1752, 1450, 48),
			Rect2(150, 1580, 420, 48),
			Rect2(850, 1580, 650, 48),
			Rect2(2830, 1580, 420, 48),
			Rect2(1500, 1580, 400, 48),
			Rect2(1900, 1580, 930, 48),
			Rect2(1300, 1400, 800, 48),
			Rect2(250, 1100, 520, 48),
			Rect2(2630, 1100, 520, 48),
			Rect2(850, 1280, 320, 48),
			Rect2(2180, 1250, 320, 48),
			Rect2(1050, 950, 300, 48),
			Rect2(2050, 950, 300, 48),
			Rect2(400, 800, 380, 48),
			Rect2(2620, 800, 380, 48),
			# QA-145 (v4.1, Worker S): centre mid step — the centre
			# bowl (pit bridge 1500-1900 @1580, 1300-2100 @1400) had
			# no direct way up: 1400 -> 950 is 450 px, reachable only
			# via a side tower or half a jetpack tank. This 600-wide
			# step makes it a real third route: 1400 -> 1120 (280 up)
			# -> 950 (170 up), and it links both side mids (850 @1280
			# and 2180 @1250, 230/180 px across). No spawn or pickup
			# sits on it.
			Rect2(1400, 1120, 600, 48),
		],
		"spawns": [Vector2(300, 1718), Vector2(900, 1718), Vector2(350, 1546), Vector2(1000, 1246), Vector2(500, 1066), Vector2(580, 766), Vector2(2550, 1718), Vector2(3100, 1718), Vector2(3000, 1546), Vector2(2330, 1216), Vector2(2900, 1066), Vector2(2800, 766)],
		"pickups": [Vector2(600, 1722), Vector2(2800, 1722), Vector2(500, 1550), Vector2(1700, 1370), Vector2(3000, 1550), Vector2(1700, 1550)],
		"decor": [["sb_vent", 720, 1752], ["crate", 1320, 1752], ["barrels", 2070, 1752], ["sb_vent", 2670, 1752], ["crate", 2970, 1752], ["barrels", 3220, 1752], ["sb_vent", 210, 1752], ["sb_vent", 1090, 1280], ["crate", 1200, 1580], ["barrels", 2400, 1752], ["sb_vent", 590, 1100], ["sb_vent", 670, 800], ["sb_vent", 3090, 1580], ["sb_vent", 2420, 1250], ["sb_vent", 2990, 1100], ["sb_vent", 2890, 800]],
	},
	{
		"name": "Volcanic Cavern", "size": Vector2(3000, 1500), "tile": 3,
		# QA-145 (v4.1, Worker U): "bg" REMOVED — same reason as
		# Neon City: bg_volcanic.png's baked-in orange pills +
		# orange mountains read as real platforms and made the
		# backdrop busy on top of the lava, embers and fire traps.
		# Full procedural gradient now (dark red dusk), like
		# Pirate Island. BG_TEX[1] stays preloaded (indices must
		# not shift); the lobby map card still uses bg_volcanic.png.
		"sky_top": Color(0.12, 0.05, 0.05), "sky_bottom": Color(0.30, 0.10, 0.08),
		"hill": Color(0.15, 0.06, 0.06), "sun": Color(1.00, 0.55, 0.20), "fx": "embers",
		"lava": [Rect2(1000, 1400, 250, 100), Rect2(1750, 1400, 250, 100)],
		# QA-145 (v4.1): fire traps — QA-126 numbers (10 HP / 1 s tick,
		# ONLY while HOT, 2 s on / 2 s off per 4 s cycle, host-only,
		# telegraphed, shield blocks). Every rect sits on a platform
		# (bottom = platform top) with walk-around room; no spawn or
		# pickup sits inside any rect. Kinds: fire_jet (ping-pong
		# flame_jet frames), fire_ring (forward fire_ring loop),
		# fire_tornado (forward fire_tornado loop, side platform —
		# jetpack past it). Worker S: the tornado was 160 wide on the
		# 240-wide (100,1110) ledge (50 px room left, 30 right) —
		# narrowed to 120 (60 px each side, still > the 40 px player
		# box). The summit jet taxes the (1200,600) summit: 240 px
		# safe room on the right, pickup (1400,570) 80 px clear.
		"fire_traps": [
			{"rect": Rect2(900, 1196, 140, 84), "kind": "fire_jet"},
			{"rect": Rect2(1950, 1196, 140, 84), "kind": "fire_jet"},
			{"rect": Rect2(1290, 1026, 220, 84), "kind": "fire_ring"},
			{"rect": Rect2(160, 1026, 120, 84), "kind": "fire_tornado"},
			{"rect": Rect2(1200, 516, 120, 84), "kind": "fire_jet"},
		],
		"platforms": [
			Rect2(0, 1452, 1000, 48),
			Rect2(1250, 1452, 500, 48),
			Rect2(2000, 1452, 1000, 48),
			Rect2(250, 1280, 420, 48),
			Rect2(1300, 1280, 460, 48),
			Rect2(2350, 1280, 420, 48),
			Rect2(670, 1280, 630, 48),
			Rect2(1760, 1280, 590, 48),
			Rect2(100, 1110, 240, 48),
			Rect2(700, 1110, 360, 48),
			Rect2(1800, 1110, 360, 48),
			Rect2(1060, 1110, 740, 48),
			Rect2(2700, 1110, 276, 48),
			Rect2(450, 940, 320, 48),
			Rect2(1250, 940, 400, 48),
			Rect2(2050, 940, 320, 48),
			Rect2(800, 770, 320, 48),
			Rect2(1900, 770, 320, 48),
			Rect2(300, 600, 260, 48),
			Rect2(1200, 600, 360, 48),
			Rect2(2500, 600, 260, 48),
		],
		"spawns": [Vector2(300, 1418), Vector2(1300, 1418), Vector2(1400, 1246), Vector2(850, 1076), Vector2(600, 906), Vector2(950, 736), Vector2(1600, 1418), Vector2(2600, 1418), Vector2(2500, 1246), Vector2(2000, 1076), Vector2(2200, 906), Vector2(2050, 736)],
		"pickups": [Vector2(450, 1250), Vector2(2720, 1250), Vector2(1500, 1250), Vector2(1500, 910), Vector2(950, 740), Vector2(1400, 570)],
		"decor": [["crate", 200, 1452], ["column", 1540, 1452], ["barrels", 2200, 1452], ["crate", 1450, 1110], ["crate", 2860, 1452], ["crate", 720, 1452], ["barrels", 2420, 1452], ["crate", 1390, 1452], ["crate", 940, 1110], ["crate", 690, 940], ["crate", 1040, 770], ["crate", 2690, 1452], ["crate", 2590, 1280], ["crate", 2090, 1110], ["crate", 2290, 940], ["crate", 2140, 770]],
	},
	{
		"name": "Pirate Island", "size": Vector2(3000, 1500), "tile": 4,
		"sky_top": Color(0.45, 0.75, 0.95), "sky_bottom": Color(0.85, 0.93, 0.97),
		"hill": Color(0.30, 0.50, 0.35), "sun": Color(1.00, 0.95, 0.60), "fx": "none",
		"platforms": [
			Rect2(0, 1452, 3000, 48),
			Rect2(100, 1280, 350, 48),
			Rect2(450, 1280, 300, 48),
			Rect2(350, 1110, 320, 48),
			Rect2(600, 940, 300, 48),
			Rect2(900, 940, 600, 48),
			Rect2(1500, 940, 900, 48),
			Rect2(850, 770, 280, 48),
			Rect2(1050, 600, 260, 48),
			Rect2(1400, 1110, 400, 48),
			Rect2(1800, 1110, 200, 48),
			Rect2(1500, 1280, 300, 48),
			Rect2(2050, 1280, 550, 48),
			Rect2(2000, 1110, 650, 48),
			Rect2(2400, 940, 300, 48),
			Rect2(2550, 770, 240, 48),
			# QA-145 (v4.1, Worker S): right summit — the left side
			# had the map's only summit (1050-1310 @600, with the
			# (1150,570) pickup) while the right topped out at 770,
			# so the left spawn owned the high ground. This mirrors
			# it (2400-2660 @600, 170 up from 2550 @770); no pickup
			# added, the perch itself is the balance fix.
			Rect2(2400, 600, 260, 48),
		],
		"spawns": [Vector2(300, 1418), Vector2(250, 1246), Vector2(500, 1076), Vector2(750, 906), Vector2(1150, 566), Vector2(1450, 1076), Vector2(2700, 1418), Vector2(2200, 1246), Vector2(2200, 1076), Vector2(2550, 906), Vector2(2650, 736), Vector2(1900, 1418)],
		"pickups": [Vector2(600, 1422), Vector2(2910, 1422), Vector2(2420, 1250), Vector2(1500, 1080), Vector2(2550, 910), Vector2(1150, 570)],
		"decor": [["palms", 400, 1452], ["palms", 2850, 1452], ["crate", 720, 1452], ["barrels", 1020, 1452], ["column", 1320, 1452], ["crate", 1620, 1452], ["barrels", 2220, 1452], ["column", 2520, 1452], ["crate", 2820, 1452], ["crate", 210, 1452], ["crate", 340, 1280], ["crate", 600, 1280], ["column", 1800, 1452], ["crate", 590, 1110], ["crate", 840, 940], ["crate", 1240, 600], ["crate", 1540, 1110], ["crate", 2290, 1280], ["crate", 2290, 1110], ["crate", 2640, 940], ["crate", 2740, 770], ["crate", 1990, 1452]],
	},
	{
		# QA-123 (v3.11): SKYFALL — The Last Ascent. Vertical
		# battlefield, 3400x10800, 6 levels x 1800 px (L1 Twin Base
		# Camp + Broken Cliffs at the bottom, L6 The Last Stand +
		# Flag Summit at the top). Rebuilt from the v3.9 8x900 layout:
		# merged pairs stack directly (old L1+L2 = new L1, old L7+L8
		# = new L6); single old levels stretch x2 inside the level.
		# QA-132 (v3.12 fix round): 55 platforms, one clean zigzag
		# climb — L1 untouched (19), L2 re-stepped to 300 px rises
		# (10), L3-L6 one 600-wide platform per 280 px rise, lanes
		# alternating LEFT / CENTRE / RIGHT so consecutive platforms
		# always touch or overlap (never a 600 px lane jump), plus
		# the arena floor, 2 summit steps, the summit floor and the
		# 2 side perches. No stepping stones, no boundary stones:
		# every rise is <= 300 px (validator limit 320), so the
		# climb needs no patches. Right edge pulled in 3600 -> 3400
		# (QA-132 task 3). CTF lives ONLY here (mode 4); the other
		# 4 maps keep FFA/TDM/Survival/LMS. Level strips in the pack
		# are WIRED IN as per-level backdrops (see _build_skyfall,
		# QA-124).
		"name": "Skyfall", "size": Vector2(3400, 10800), "tile": 5,
		"bg": 3,
		"sky_top": Color(0.07, 0.06, 0.16), "sky_bottom": Color(0.45, 0.30, 0.22),
		"hill": Color(0.10, 0.12, 0.20), "sun": Color(0.92, 0.92, 0.98), "fx": "dust",
		"platforms": [
			# L1 (0-18, UNTOUCHED — user: level 1 is fine).
			Rect2(0, 10752, 3400, 48), Rect2(300, 10582, 500, 48), Rect2(2800, 10582, 500, 48),
			Rect2(900, 10412, 500, 48), Rect2(2200, 10412, 500, 48), Rect2(1550, 10242, 500, 48),
			Rect2(1200, 10072, 500, 48), Rect2(1900, 10072, 500, 48), Rect2(800, 9902, 500, 48),
			Rect2(2300, 9902, 500, 48), Rect2(1200, 9732, 500, 48), Rect2(1900, 9732, 500, 48),
			Rect2(600, 9562, 500, 48), Rect2(2500, 9562, 500, 48), Rect2(1100, 9392, 500, 48),
			Rect2(2100, 9392, 500, 48), Rect2(1200, 9222, 500, 48), Rect2(1900, 9222, 500, 48),
			Rect2(1550, 9052, 500, 48),
			# L2 (19-28): the old 8764/8424/8084/7744/7404 rows were
			# 340 px apart and only reachable via stepping stones —
			# re-stepped to 300 px (8764/8464/8164/7864/7564) so the
			# stones can go. Boundary row 8764 kept as the L1/L2 floor.
			Rect2(200, 8764, 150, 48), Rect2(350, 8764, 300, 48),
			Rect2(650, 8764, 2300, 48), Rect2(2950, 8764, 300, 48), Rect2(3250, 8764, 150, 48),
			Rect2(1500, 8464, 600, 48), Rect2(400, 8164, 2800, 48), Rect2(1500, 7864, 600, 48),
			Rect2(1200, 7564, 500, 48), Rect2(1900, 7564, 500, 48),
			# L3 (29-35): 280 px rises, lanes C/L/C/R/C/L/C.
			Rect2(1500, 7264, 600, 48), Rect2(900, 6984, 600, 48), Rect2(1500, 6704, 600, 48),
			Rect2(2100, 6424, 600, 48), Rect2(1500, 6144, 600, 48), Rect2(900, 5864, 600, 48),
			Rect2(1500, 5584, 600, 48),
			# L4 (36-41): 280 px rises, lanes R/C/L/C/R/C.
			Rect2(2100, 5304, 600, 48), Rect2(1500, 5024, 600, 48), Rect2(900, 4744, 600, 48),
			Rect2(1500, 4464, 600, 48), Rect2(2100, 4184, 600, 48), Rect2(1500, 3904, 600, 48),
			# L5 (42-47): 280 px rises, lanes L/C/R/C/L/C.
			Rect2(900, 3624, 600, 48), Rect2(1500, 3344, 600, 48), Rect2(2100, 3064, 600, 48),
			Rect2(1500, 2784, 600, 48), Rect2(900, 2504, 600, 48), Rect2(1500, 2224, 600, 48),
			# L6 (48-54): last step 1944 (232 px to the arena),
			# arena floor, 2 centre summit steps (288/282/280 px),
			# summit floor, 2 side perches (172 px up, 100 px gap).
			Rect2(2100, 1944, 600, 48), Rect2(600, 1712, 2400, 48),
			Rect2(1500, 1424, 600, 48), Rect2(1500, 1142, 600, 48), Rect2(1200, 862, 1200, 48),
			Rect2(700, 690, 400, 48), Rect2(2500, 690, 400, 48),
		],
		"spawns": [Vector2(300, 10718), Vector2(700, 10718), Vector2(550, 10548), Vector2(1150, 10378), Vector2(1700, 10208), Vector2(1450, 10038), Vector2(3300, 10718), Vector2(2900, 10718), Vector2(3050, 10548), Vector2(2450, 10378), Vector2(2150, 10038), Vector2(2500, 9868)],
		"pickups": [Vector2(400, 10548), Vector2(3200, 10548), Vector2(1800, 10208), Vector2(1800, 1678), Vector2(1800, 8730), Vector2(1200, 4710)],
		# QA-132: L1 decor only. Every L2-L6 decor entry is GONE
		# (user: clean everything unnecessary) — crates, barrels,
		# columns, vents, jtree, jbush, if_lamp all removed; the
		# code-drawn L2 tunnel lamp dots stay (see _build_skyfall).
		"decor": [["if_rock", 500, 10582], ["if_rock", 3100, 10582], ["crate", 1600, 10242], ["barrels", 2000, 10072], ["if_spikes", 2500, 9902]],
		"skyfall": true,
		# Power-up spots: [x, y, kind] — one per power-up, spread
		# across the heights (kinds 8-13, see pickup.gd — kinds
		# UNCHANGED by the rebuild, only positions moved). QA-132:
		# every spot re-anchored to a platform top (y = top - 34)
		# and OUT of the hazard rects — the old shield spot sat
		# INSIDE the lava and the old invisibility spot floated
		# 304 px above the nearest platform.
		# QA-143 (v4.0): Health Potion (kind 7) REMOVED — 6 spots now.
		"skyfall_pickups": [[2600, 10378, 10], [1350, 9358, 11], [1400, 2470, 8], [1200, 5830, 12], [1800, 6110, 13], [2600, 1678, 9]],
		# Vertical CTF: both flags at the summit, extraction zones
		# at the bases. Red steals the BLUE flag to the RED zone.
		"ctf": {"flag_red": Vector2(1400, 862), "flag_blue": Vector2(2200, 862), "extract_red": Vector2(450, 10752), "extract_blue": Vector2(3150, 10752)},
		# Team respawn checkpoints, per level: [red, blue] positions
		# for L1 (base), L2 (tunnels), L4 (sniper top), L6 (arena).
		# QA-132: L4 checkpoints re-anchored to the new L4 centre
		# row (1500,3904,600): y = 3904 - 34 = 3870.
		"checkpoints": [[Vector2(450, 10718), Vector2(3150, 10718)], [Vector2(800, 8730), Vector2(2800, 8730)], [Vector2(1600, 3870), Vector2(2000, 3870)], [Vector2(1000, 1678), Vector2(2600, 1678)]],
		# QA-114 (v3.9): relay stations — partial scoring. Either team
		# banks the flag here for +1 point (level 3 bridge, level 6
		# arena); the flag then returns to the summit.
		# QA-132: L3 relay re-anchored to the new L3 centre row
		# (1500,6704,600): (1800, 6670).
		"relay": [Vector2(1800, 6670), Vector2(1800, 1678)],
		# QA-114 (v3.9): movement options — grapple points and marked
		# jetpack lines straight through the two wind zones. QA-129:
		# +2 risky grapple points: (1800,6100) in the bridge wind
		# zone and (1800,2050) over the L5 lava — fast, exposed.
		"grapple": [Vector2(900, 9800), Vector2(2700, 9800), Vector2(900, 7000), Vector2(2700, 7000), Vector2(1200, 3000), Vector2(2400, 3000), Vector2(1800, 6100), Vector2(1800, 2050)],
		"jetpack_lines": [{"from": Vector2(1800, 5400), "to": Vector2(1800, 4000)}, {"from": Vector2(1800, 6800), "to": Vector2(1800, 6000)}],
		# Emergency ladders (climb rects; visuals are sf_ladder decor).
		# QA-132: re-anchored to the new rows — L3 spans 6984-7312
		# (rows 6984/7264), L4 spans 3344-3672 (rows 3344/3624),
		# L6 spans 1424-1760 (summit step 1424 / arena 1712).
		"ladders": [Rect2(1400, 9688, 96, 384), Rect2(1600, 6984, 96, 328), Rect2(1300, 3344, 96, 328), Rect2(1300, 1424, 96, 336)],
		# Moving elevators: the original L6 pair (now L5) + a pair in
		# the tunnels (L2) and a pair on the bridge (L3). x, width,
		# top/bottom y, phase.
		# QA-132: re-anchored to the new rows — each elevator shuttles
		# between two adjacent rows (L5: 3344/3624 and 3064/3344;
		# L2: 8164/8464 and 8464/8764; L3: 6984/7264 and 6424/6704).
		# QA-134 (v3.13): travel ranges SHORTENED so no elevator's
		# swept rect (body 48 tall) ever passes under or through a
		# static platform — each now docks 40 px clear of the
		# platform above it (verified by FT-SF-MOVER-CLEAR).
		"elevators": [{"x": 900, "w": 500, "y_top": 3344, "y_bottom": 3576, "phase": 0.00}, {"x": 2100, "w": 500, "y_top": 3112, "y_bottom": 3344, "phase": 0.50}, {"x": 1500, "w": 600, "y_top": 8212, "y_bottom": 8416, "phase": 0.00}, {"x": 600, "w": 500, "y_top": 8464, "y_bottom": 8716, "phase": 0.50}, {"x": 900, "w": 500, "y_top": 7032, "y_bottom": 7264, "phase": 0.25}, {"x": 2100, "w": 500, "y_top": 6472, "y_bottom": 6704, "phase": 0.75}],
		# Rotating platform (L5): orbits its centre.
		# QA-132: centre moved (1800,2644) -> (1900,2444) — the old
		# centre's orbit clipped the new L5 centre row (1500,2784).
		"rotator": {"center": Vector2(1900, 2444), "radius": 120.0, "speed": 0.5, "w": 400},
		# Platform indices (into "platforms"): collapsing bridge
		# middle + 4 crumbling mid ledges, trapdoor segments.
		# QA-132: re-counted from scratch for the 55-platform list —
		# collapsing [31,36,41,44,48] (one per level L3-L6 + the
		# last L6 step), trapdoors [20,22,24,38] (2 boundary-row
		# pieces, the L2 8464 row, one L4 row). The storm-disable
		# list is GONE (QA-132 task 1e — the perches stay landable).
		# QA-135 (v3.13): DIFFERENT trap mix per level — L2 gets
		# two more trapdoors (19, 23: the boundary-row edge pieces,
		# appended so _sf_trapdoors[0] stays idx 20 for
		# FT-SF-COMBO-TRAP) and L6 gets two more collapsing steps
		# (50, 51: the summit steps). See BUGS.md for the full mix.
		"collapsing": [31, 36, 41, 44, 48, 50, 51],
		"trapdoors": [20, 22, 24, 38, 19, 23],
		# Summit gate (blocks the middle of the summit floor until
		# it opens 45 s into the match) + control switch on the
		# arena floor (activates the summit elevator for 30 s).
		"gate": {"x": 1800, "y": 862},
		"switch": {"pos": Vector2(1800, 1712)},
		"summit_elevator": {"x": 1200, "w": 300, "y_bottom": 1664, "y_top": 910}, # QA-134 (v3.13): moved x 1650 -> 1200 and travel 862-1712 -> 910-1664 so it dodges the summit steps (x 1500-2100) and docks flush at both ends (body bottom at the arena floor top 1712, body top at the summit floor bottom 910); never under a static platform (FT-SF-MOVER-CLEAR).
		# Destructible barricades (shoot to break, respawn in 30 s).
		# QA-132: L3 pair re-anchored to the new rows — (1200,6984)
		# on the L row, (2400,6424) on the R row.
		"barricades": [{"pos": Vector2(1200, 1712)}, {"pos": Vector2(2400, 1712)}, {"pos": Vector2(1200, 6984)}, {"pos": Vector2(2400, 6424)}],
		# Wind zones: push + weaken the jetpack inside the rect.
		# QA-135 (v3.13): a SECOND L3 wind zone (upper bridge,
		# y 5400-6000, pushes left) so L3 is the wind-gust level —
		# different trap mix per level (see BUGS.md).
		# QA-145 (v4.1, Worker S): the L4 zone SHRUNK 4000-5400 ->
		# 4400-5000 — it used to cover 5 of L4's 6 rows and stacked
		# on every other L4 trap (pendulum row 4184, collapse rows
		# 5304/3904): dodging the ball while pushed left at 150 with
		# a weakened jetpack was unfair. Now a mid-L4 gust band over
		# 4464 + 4744 only (the 4744 trapdoor stack stays: the wind
		# pushes you across it faster, and crossing takes ~0.3 s
		# against the 1.0 s open timer). Strength unchanged (150).
		"wind": [{"rect": Rect2(1400, 4400, 800, 600), "dir": Vector2(-1, 0), "strength": 150.0}, {"rect": Rect2(600, 6000, 2400, 800), "dir": Vector2(1, 0), "strength": 120.0}, {"rect": Rect2(900, 9500, 1800, 400), "dir": Vector2(-1, 0), "strength": 100.0}, {"rect": Rect2(1400, 5400, 800, 600), "dir": Vector2(-1, 0), "strength": 150.0}],
		# Falling rocks (L1 Broken Cliffs). QA-135 (v3.13): L1 is
		# the falling-rocks level — heavier: interval 4 s -> 2.5 s,
		# wider drop band (700-2900), up to 4 falling at once
		# (was 3). Same 25 HP damage (QA-126), telegraphed by the
		# ground-crack marker (QA-129).
		"rocks": {"x_min": 700, "x_max": 2900, "y_top": 9050, "interval": 2.5, "max": 4},
		# QA-126 hazard zones (damage on a cycle — see
		# _sf_update_hazards): lava pool + fire jet on the
		# Mechanical Ascent (L5). rect / kind / dmg per 1 s tick /
		# cycle seconds (2 s hot, 2 s safe — the flame shows it).
		# QA-132: re-anchored to the new L5 rows — lava sits on the
		# L row (900,2504): rect y 2420 + 84 = 2504; fire sits on
		# the C row (1500,2224): rect y 2140 + 84 = 2224.
		# QA-135 (v3.13): L5 is the lava/fire level — two more
		# hazards: a second lava pool on the R row (2100,3064) and
		# a second fire jet on the C row (1500,3344). Same 10 HP
		# per 1 s tick while HOT (QA-126); both leave room to walk
		# around them and the climb stays completable.
		"hazards": [{"rect": Rect2(950, 2420, 300, 84), "kind": "lava", "dmg": 10, "cycle": 4.0}, {"rect": Rect2(1750, 2140, 200, 84), "kind": "fire", "dmg": 10, "cycle": 4.0}, {"rect": Rect2(2150, 2980, 300, 84), "kind": "lava", "dmg": 10, "cycle": 4.0}, {"rect": Rect2(1750, 3260, 200, 84), "kind": "fire", "dmg": 10, "cycle": 4.0}],
		# QA-137 (v3.14): swinging spiked wrecking-ball pendulums
		# (the user's trap sheet). Each hangs from a pivot in open
		# air and swings across the platform below it - L4 over the
		# (2100,4184) platform, L2 over the (1500,7864) platform.
		# Both platforms are STATIC (not collapsing, not trapdoors)
		# and the pivots sit in the gaps between the platforms
		# above, so the chain never clips a platform; the ball
		# sweeps just above the platform below (25 HP on hit,
		# QA-126 rules - dodgeable, telegraphed, no one-hit kill).
		"pendulums": [{"pivot": Vector2(2400, 3930), "len": 220.0}, {"pivot": Vector2(1800, 7610), "len": 220.0}],
		# QA-145 (v4.1, Worker T): proximity mines — the ambush trap.
		# Mine 1 on the L3 side lane (900,5864 row, idx 34 — static,
		# not collapsing, outside both L3 wind zones, 200 px from
		# the Thunder power-up spot so grabbing it never trips the
		# mine) and mine 2 on the big L2 tunnel row (400,8164, idx
		# 25 — static, not a trapdoor). Trigger 70 px, 1.0 s
		# blinking fuse, 25 HP in a 120 px blast (QA-126
		# rock/pendulum numbers), 30 s re-arm (barricade standard).
		# Both leave room to walk around them and the climb stays
		# completable. Positions are the mine-disc centres, ~12 px
		# above the platform top.
		"mines": [{"pos": Vector2(1000, 5852)}, {"pos": Vector2(800, 8152)}],
	},

]
