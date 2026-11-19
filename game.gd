extends Node2D

# Game scene: side-view arena, LAN multiplayer (ENet), HUD, touch controls.
# LAN only. No online play, no bots, no accounts.
#
# JOIN FIX (v2): the server spawns a client's player ONLY after that client
# has loaded this scene and sent a `request_spawn` RPC (see _announce_ready).
# v1 spawned in _on_peer_connected, before the client had a MultiplayerSpawner,
# so the spawn was dropped and the client sat on "Connecting..." forever.
# v2.4: the client retries the request every 2 s until it is spawned or
# the 8 s timeout fires, so one lost UDP packet can no longer strand it.
# There is also an 8s join timeout with Back / Retry, and players are
# despawned when their peer disconnects.
#
# HOST-AUTHORITATIVE (v2.4): the host decides damage, kills, health,
# deaths, respawns, timer, scoreboard and settings. Clients send inputs
# and fire requests; the host validates (fire rate + ammo) and applies
# damage. No client can award itself kills or damage another player.

const PLAYER_SCENE: PackedScene = preload("res://player.tscn")
const PICKUP_SCENE: PackedScene = preload("res://pickup.tscn")
const BULLET_SCENE: PackedScene = preload("res://bullet.tscn")
const JOYSTICK_SCRIPT: Script = preload("res://joystick.gd")
const AUDIO_SCRIPT: Script = preload("res://audio.gd")

# v3.2 NEON ARENA theme (THEME_SPEC.md): Orbitron titles, Rajdhani
# body/numbers, cyan-on-navy. Fonts are SIL OFL 1.1 (see Settings
# credit line in main.gd). The gohud theme drives the look; these
# consts are only for the few places game code still sets a colour
# directly (HUD numbers, bar inks).
const FONT_TITLE: Font = preload("res://assets/fonts/orbitron/Orbitron-Variable.ttf")
const FONT_BODY: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Regular.ttf")
const FONT_BODY_MEDIUM: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Medium.ttf")
const FONT_BODY_SEMIBOLD: Font = preload("res://assets/fonts/rajdhani/Rajdhani-SemiBold.ttf")
const FONT_BODY_BOLD: Font = preload("res://assets/fonts/rajdhani/Rajdhani-Bold.ttf")
const UI_ACCENT := Color(0.0, 0.898, 1.0) # cyan #00E5FF
const UI_ACCENT_DARK := Color(0.012, 0.071, 0.102) # on-accent #03121A
const UI_FONT := Color(0.847, 0.957, 1.0) # ice #D8F4FF
const UI_FONT_MUTED := Color(0.522, 0.655, 0.741) # muted #85A7BD
const UI_SUCCESS := Color(0.231, 1.0, 0.647) # mint #3BFFA5
const UI_DANGER := Color(1.0, 0.302, 0.427) # coral #FF4D6D
const UI_WARNING := Color(1.0, 0.773, 0.239) # amber #FFC53D

const PORT := 7777
const DISCOVERY_PORT := 7778
const DISCOVERY_MAGIC := "LANARENA"
const MAX_PLAYERS := 12 # absolute cap; the room setting is max_players (GameData)
const JOIN_TIMEOUT := 8.0

const TILE_TEX: Array[Texture2D] = [
	preload("res://assets/tiles/tile_catacombs.png"),
	preload("res://assets/tiles/tile_military.png"),
	preload("res://assets/tiles/tile_desert.png"),
	preload("res://assets/tiles/tile_factory.png"),
	preload("res://assets/tiles/tile_frozen.png"),
	preload("res://assets/tiles/tile_jungle.png"),
	preload("res://assets/tiles/tile_space.png"),
	preload("res://assets/tiles/tile_city.png"),
	preload("res://assets/tiles/tile_volcanic.png"),
	preload("res://assets/tiles/tile_pirate.png"),
	# Phase 5 — Sky Brawl tiles, alpha-flattened + resized to 128x48
	# (SKY_BRAWL_USE.md): 10 Neon City (purple brick), 11 Ancient
	# Temple (tan stone; Airship Fleet reuses it as its deck tile).
	preload("res://assets/skybrawl/tiles/tile_neon.png"),
	preload("res://assets/skybrawl/tiles/tile_temple.png"),
]
# Phase 5 — Sky Brawl arena backgrounds as a FAR parallax layer
# (viewport scale ~1.3x, parallax 0.25, never stretched over a map).
# Index matches the map's "bg" key: 0 Catacombs, 1 Industrial,
# 2 Space Station, 3 City Underground, 4 Volcanic Cavern,
# 5 Neon City, 6 Ancient Temple.
const BG_TEX: Array[Texture2D] = [
	preload("res://assets/skybrawl/maps/bg_catacombs.png"),
	preload("res://assets/skybrawl/maps/bg_industrial.png"),
	preload("res://assets/skybrawl/maps/bg_space.png"),
	preload("res://assets/skybrawl/maps/bg_city.png"),
	preload("res://assets/skybrawl/maps/bg_volcanic.png"),
	preload("res://assets/skybrawl/maps/bg_neon.png"),
	preload("res://assets/skybrawl/maps/bg_temple.png"),
]
const DECOR_CRATE: Texture2D = preload("res://assets/tiles/crate.png")
const DECOR_BARRELS: Texture2D = preload("res://assets/tiles/barrels.png")
const DECOR_SANDBAGS: Texture2D = preload("res://assets/tiles/sandbags.png")
const DECOR_PALMS: Texture2D = preload("res://assets/tiles/palms.png")
const DECOR_ROCK: Texture2D = preload("res://assets/tiles/rock.png")
const DECOR_BRIDGE: Texture2D = preload("res://assets/tiles/wood_bridge.png")
const DECOR_COLUMN: Texture2D = preload("res://assets/tiles/stone_column.png")
# Jungle Ruins slices (from the user's asset pack; black atlas background
# removed, transparency verified — no dark box in-game).
const DECOR_JTREE: Texture2D = preload("res://assets/jungle/jungle_tree.png")
const DECOR_JPALM: Texture2D = preload("res://assets/jungle/jungle_palm.png")
const DECOR_JTOWER: Texture2D = preload("res://assets/jungle/jungle_watchtower.png")
const DECOR_JSTATUE: Texture2D = preload("res://assets/jungle/jungle_statue.png")
const DECOR_JPILLAR: Texture2D = preload("res://assets/jungle/jungle_pillar.png")
const DECOR_JCRATE: Texture2D = preload("res://assets/jungle/jungle_crate.png")
const DECOR_JROCK: Texture2D = preload("res://assets/jungle/jungle_rock.png")
const DECOR_JBUSH: Texture2D = preload("res://assets/jungle/jungle_bush.png")
const DECOR_JBRIDGE: Texture2D = preload("res://assets/jungle/jungle_bridge.png")
const DECOR_JARCH: Texture2D = preload("res://assets/jungle/jungle_arch.png")
const DECOR_JPLATFORM: Texture2D = preload("res://assets/jungle/jungle_platform.png")
# Phase 5 — Sky Brawl structures (SKY_BRAWL_USE.md). Huts/blocks/
# vents/crates are SOLID cover (see SOLID_DECOR_KINDS); slabs,
# trapezoids and the altar stone are visual dressing only.
const DECOR_SB_HUT: Texture2D = preload("res://assets/skybrawl/structures/sb_hut.png")
const DECOR_SB_HUT_PINK: Texture2D = preload("res://assets/skybrawl/structures/sb_hut_pink.png")
const DECOR_SB_HUT_BLUE: Texture2D = preload("res://assets/skybrawl/structures/sb_hut_blue.png")
const DECOR_SB_VENT: Texture2D = preload("res://assets/skybrawl/structures/sb_vent.png")
const DECOR_SB_SLAB: Texture2D = preload("res://assets/skybrawl/structures/sb_slab.png")
const DECOR_SB_TRAP: Texture2D = preload("res://assets/skybrawl/structures/sb_trap.png")
const DECOR_SB_SHRINE: Texture2D = preload("res://assets/skybrawl/structures/sb_shrine.png")
const DECOR_SB_BLOCK: Texture2D = preload("res://assets/skybrawl/structures/sb_block.png")
const DECOR_SB_ALTAR: Texture2D = preload("res://assets/skybrawl/structures/sb_altar.png")
const DECOR_SB_HUT_GREEN: Texture2D = preload("res://assets/skybrawl/structures/sb_hut_green.png")
const DECOR_SB_CRATE: Texture2D = preload("res://assets/skybrawl/structures/sb_crate.png")
const DECOR_SB_VENT_ORANGE: Texture2D = preload("res://assets/skybrawl/structures/sb_vent_orange.png")

const MAPS := [
	{
		"name": "Catacombs", "size": Vector2(3200, 1400), "tile": 0,
		"bg": 0,
		"sky_top": Color(0.07, 0.08, 0.15), "sky_bottom": Color(0.14, 0.16, 0.26),
		"hill": Color(0.04, 0.05, 0.09), "sun": Color(0.95, 0.70, 0.35), "fx": "dust",
		"platforms": [
			Rect2(0, 1352, 3200, 48),
			Rect2(300, 1180, 420, 48),
			Rect2(1350, 1180, 500, 48),
			Rect2(2480, 1180, 420, 48),
			Rect2(100, 1010, 240, 48),
			Rect2(950, 1010, 900, 48),
			Rect2(2300, 1010, 300, 48),
			Rect2(2860, 1010, 240, 48),
			Rect2(650, 840, 340, 48),
			Rect2(1450, 840, 300, 48),
			Rect2(2150, 840, 340, 48),
			Rect2(350, 670, 320, 48),
			Rect2(1500, 670, 260, 48),
			Rect2(2200, 670, 360, 48),
			Rect2(200, 500, 320, 48),
			Rect2(1450, 500, 300, 48),
			Rect2(2680, 500, 320, 48),
		],
		"spawns": [Vector2(300, 1320), Vector2(900, 1320), Vector2(500, 1148), Vector2(1200, 978), Vector2(800, 808), Vector2(500, 638), Vector2(2300, 1320), Vector2(2800, 1320), Vector2(2650, 1148), Vector2(2450, 978), Vector2(2300, 808), Vector2(2350, 638)],
		"pickups": [Vector2(500, 1150), Vector2(2700, 1150), Vector2(1400, 1150), Vector2(1600, 810), Vector2(400, 640), Vector2(1600, 470)],
		"decor": [["column", 650, 1352], ["crate", 1600, 1010], ["crate", 1320, 1352], ["barrels", 1920, 1352], ["column", 2520, 1352], ["sandbags", 3120, 1352], ["crate", 210, 1352], ["crate", 810, 1352], ["crate", 590, 1180], ["crate", 1290, 1010], ["crate", 890, 840], ["crate", 590, 670], ["crate", 2390, 1352], ["crate", 2890, 1352], ["crate", 2540, 1010], ["crate", 2390, 840], ["crate", 2440, 670]],
	},
	{
		"name": "Military Base", "size": Vector2(2880, 1440), "tile": 1,
		"sky_top": Color(0.45, 0.70, 0.95), "sky_bottom": Color(0.85, 0.92, 0.95),
		"hill": Color(0.35, 0.50, 0.35), "sun": Color(1.00, 0.95, 0.60), "fx": "none",
		"platforms": [
			Rect2(0, 1392, 2880, 48),
			Rect2(200, 1220, 400, 48),
			Rect2(1150, 1220, 400, 48),
			Rect2(2150, 1220, 400, 48),
			Rect2(700, 1050, 360, 48),
			Rect2(1650, 1050, 360, 48),
			Rect2(2500, 1050, 300, 48),
			Rect2(400, 880, 320, 48),
			Rect2(1600, 880, 320, 48),
			Rect2(2200, 880, 360, 48),
			Rect2(1000, 710, 420, 48),
			Rect2(200, 710, 260, 48),
			Rect2(2400, 710, 260, 48),
			Rect2(850, 540, 300, 48),
			Rect2(1450, 540, 300, 48),
			Rect2(1250, 370, 380, 48),
		],
		"spawns": [Vector2(300, 1360), Vector2(900, 1360), Vector2(1350, 1188), Vector2(850, 1018), Vector2(550, 848), Vector2(1150, 678), Vector2(2100, 1360), Vector2(2600, 1360), Vector2(2350, 1188), Vector2(1800, 1018), Vector2(2350, 848), Vector2(1750, 508)],
		"pickups": [Vector2(400, 1190), Vector2(2400, 1190), Vector2(1350, 1190), Vector2(1440, 340), Vector2(1600, 510), Vector2(1000, 510)],
		"decor": [["column", 250, 710], ["sandbags", 720, 1392], ["crate", 1020, 1392], ["barrels", 1320, 1392], ["column", 1620, 1392], ["sandbags", 2220, 1392], ["crate", 210, 1392], ["crate", 1440, 1220], ["crate", 940, 1050], ["crate", 640, 880], ["crate", 1240, 710], ["crate", 2690, 1392], ["crate", 2440, 1220], ["crate", 1890, 1050], ["crate", 2440, 880], ["crate", 1660, 540]],
	},
	{
		"name": "Desert Outpost", "size": Vector2(3000, 1500), "tile": 2,
		"sky_top": Color(0.95, 0.75, 0.45), "sky_bottom": Color(0.99, 0.90, 0.65),
		"hill": Color(0.65, 0.45, 0.25), "sun": Color(1.00, 0.85, 0.50), "fx": "dust",
		"platforms": [
			Rect2(0, 1452, 3000, 48),
			Rect2(250, 1280, 420, 48),
			Rect2(1300, 1280, 460, 48),
			Rect2(2350, 1280, 420, 48),
			Rect2(100, 1110, 240, 48),
			Rect2(700, 1110, 360, 48),
			Rect2(1800, 1110, 360, 48),
			Rect2(2700, 1110, 240, 48),
			Rect2(450, 940, 320, 48),
			Rect2(1250, 940, 400, 48),
			Rect2(2050, 940, 320, 48),
			Rect2(800, 770, 320, 48),
			Rect2(1900, 770, 320, 48),
			Rect2(300, 600, 260, 48),
			Rect2(1200, 600, 360, 48),
			Rect2(2500, 600, 260, 48),
		],
		"spawns": [Vector2(300, 1420), Vector2(900, 1420), Vector2(450, 1248), Vector2(850, 1078), Vector2(600, 908), Vector2(950, 738), Vector2(2100, 1420), Vector2(2600, 1420), Vector2(2500, 1248), Vector2(2000, 1078), Vector2(2200, 908), Vector2(2050, 738)],
		"pickups": [Vector2(450, 1250), Vector2(2720, 1250), Vector2(1500, 1250), Vector2(1500, 910), Vector2(950, 740), Vector2(1400, 570)],
		"decor": [["palms", 400, 1452], ["palms", 2850, 1452], ["crate", 720, 1452], ["sandbags", 1020, 1452], ["column", 1320, 1452], ["barrels", 1620, 1452], ["crate", 1920, 1452], ["sandbags", 2220, 1452], ["column", 2820, 1452], ["crate", 210, 1452], ["crate", 540, 1280], ["crate", 940, 1110], ["crate", 690, 940], ["crate", 1040, 770], ["crate", 2690, 1452], ["crate", 2590, 1280], ["crate", 2090, 1110], ["crate", 2290, 940], ["crate", 2140, 770]],
	},
	{
		"name": "Industrial Factory", "size": Vector2(3200, 1600), "tile": 3,
		"bg": 1,
		"sky_top": Color(0.25, 0.28, 0.35), "sky_bottom": Color(0.55, 0.50, 0.45),
		"hill": Color(0.20, 0.18, 0.20), "sun": Color(1.00, 0.80, 0.40), "fx": "sparks",
		"platforms": [
			Rect2(0, 1552, 3200, 48),
			Rect2(300, 1380, 420, 48),
			Rect2(1400, 1380, 460, 48),
			Rect2(2500, 1380, 420, 48),
			Rect2(100, 1210, 240, 48),
			Rect2(750, 1210, 380, 48),
			Rect2(1950, 1210, 380, 48),
			Rect2(2900, 1210, 240, 48),
			Rect2(500, 1040, 340, 48),
			Rect2(1300, 1040, 420, 48),
			Rect2(2100, 1040, 340, 48),
			Rect2(900, 870, 340, 48),
			Rect2(2000, 870, 340, 48),
			Rect2(400, 700, 280, 48),
			Rect2(1300, 700, 400, 48),
			Rect2(2600, 700, 280, 48),
			Rect2(1500, 530, 320, 48),
		],
		"spawns": [Vector2(300, 1520), Vector2(900, 1520), Vector2(1500, 1348), Vector2(950, 1178), Vector2(650, 1008), Vector2(1050, 838), Vector2(2100, 1520), Vector2(2700, 1520), Vector2(2650, 1348), Vector2(2150, 1178), Vector2(2250, 1008), Vector2(2150, 838)],
		"pickups": [Vector2(500, 1350), Vector2(2700, 1350), Vector2(1600, 1350), Vector2(1600, 1010), Vector2(1050, 840), Vector2(1650, 500)],
		"decor": [["bridge", 1300, 1040], ["barrels", 720, 1552], ["crate", 1320, 1552], ["column", 1620, 1552], ["sandbags", 1920, 1552], ["barrels", 2520, 1552], ["crate", 2820, 1552], ["column", 3120, 1552], ["crate", 210, 1552], ["crate", 810, 1552], ["crate", 1040, 1210], ["crate", 740, 1040], ["crate", 1140, 870], ["crate", 2740, 1380], ["crate", 2240, 1210], ["crate", 2340, 1040], ["crate", 2240, 870]],
	},
	{
		# QA-033 (MAP_AUDIT §Similarity-3): rebuilt as the game's small
		# duel map (~2200x1400, 2-4 players) instead of a Template A
		# clone shifted to 2800. New layout: open ice-slide centre
		# (floor x450-1750 is the low-friction zone, kept clear of
		# floor decor so the slide run is unobstructed), hot zone on
		# the frozen lake platform (850-1350 @1180, centre pickup at
		# spot 3), dense cover on the flanks + platforms (the old
		# map's signature), snow fx kept. Jump rises 170-172 px.
		# TDM: spawns[0:6] left half, spawns[6:12] right half.
		"name": "Frozen Fortress", "size": Vector2(2200, 1400), "tile": 4,
		"sky_top": Color(0.55, 0.70, 0.90), "sky_bottom": Color(0.85, 0.90, 0.97),
		"hill": Color(0.60, 0.70, 0.85), "sun": Color(0.95, 0.95, 1.00), "fx": "snow",
		"platforms": [
			Rect2(0, 1352, 2200, 48),
			Rect2(150, 1180, 340, 48),
			Rect2(850, 1180, 500, 48),
			Rect2(1710, 1180, 340, 48),
			Rect2(80, 1010, 220, 48),
			Rect2(550, 1010, 300, 48),
			Rect2(1350, 1010, 300, 48),
			Rect2(1850, 1010, 220, 48),
			Rect2(350, 840, 300, 48),
			Rect2(950, 840, 300, 48),
			Rect2(1550, 840, 300, 48),
			Rect2(250, 670, 260, 48),
			Rect2(950, 670, 300, 48),
			Rect2(1690, 670, 260, 48),
			Rect2(950, 500, 300, 48),
		],
		"spawns": [Vector2(250, 1320), Vector2(700, 1320), Vector2(320, 1148), Vector2(700, 978), Vector2(500, 808), Vector2(380, 638), Vector2(1950, 1320), Vector2(1500, 1320), Vector2(1880, 1148), Vector2(1500, 978), Vector2(1700, 808), Vector2(1820, 638)],
		"pickups": [Vector2(320, 1150), Vector2(1880, 1150), Vector2(380, 640), Vector2(1100, 1150), Vector2(1100, 810), Vector2(1820, 640)],
		"decor": [["sandbags", 120, 1352], ["barrels", 1800, 1352], ["column", 150, 1010], ["crate", 250, 1010], ["crate", 450, 1180], ["crate", 1980, 1180], ["crate", 800, 1010], ["crate", 1400, 1010], ["crate", 600, 840], ["crate", 1600, 840], ["crate", 450, 670], ["crate", 1750, 670]],
	},
	{
		"name": "Jungle Ruins", "size": Vector2(3200, 1400), "tile": 5,
		"sky_top": Color(0.35, 0.65, 0.85), "sky_bottom": Color(0.80, 0.92, 0.75),
		"hill": Color(0.20, 0.40, 0.20), "sun": Color(1.00, 0.95, 0.60), "fx": "leaves",
		"platforms": [
			Rect2(0, 1352, 3200, 48),
			Rect2(150, 1180, 300, 48),
			Rect2(700, 1180, 350, 48),
			Rect2(1100, 1180, 600, 48),
			Rect2(2000, 1180, 350, 48),
			Rect2(2600, 1180, 300, 48),
			Rect2(450, 1010, 550, 48),
			Rect2(800, 840, 280, 48),
			Rect2(1050, 1010, 700, 48),
			Rect2(1150, 840, 260, 48),
			Rect2(1500, 840, 260, 48),
			Rect2(1350, 670, 200, 48),
			Rect2(1750, 1010, 250, 48),
			Rect2(2000, 1010, 400, 48),
			Rect2(2150, 840, 300, 48),
			Rect2(2750, 1010, 260, 48),
			Rect2(2500, 670, 260, 48),
			Rect2(2900, 840, 240, 48),
			Rect2(300, 670, 260, 48),
			Rect2(2100, 500, 300, 48),
		],
		"spawns": [Vector2(300, 1320), Vector2(900, 1320), Vector2(1300, 1148), Vector2(1200, 978), Vector2(950, 808), Vector2(450, 638), Vector2(2100, 1320), Vector2(2900, 1320), Vector2(2200, 1148), Vector2(2200, 978), Vector2(2300, 808), Vector2(2600, 638)],
		"pickups": [Vector2(300, 1150), Vector2(2700, 1150), Vector2(1400, 1150), Vector2(1600, 810), Vector2(2300, 810), Vector2(2600, 640)],
		"decor": [["jtree", 130, 1352], ["jpalm", 3000, 1352], ["jstatue", 1400, 1010], ["jpillar", 1100, 1010], ["jpillar", 1700, 1010], ["jtower", 2400, 840], ["jbridge", 1875, 1010], ["jarch", 2100, 1010], ["jtree", 2300, 840], ["jbush", 600, 1352], ["jcrate", 720, 1352], ["jpillar", 1320, 1352], ["jcrate", 1620, 1352], ["jcrate", 1920, 1352], ["jpillar", 2520, 1352], ["jcrate", 3120, 1352], ["jcrate", 210, 1352], ["jcrate", 810, 1352], ["jcrate", 1040, 840], ["jcrate", 360, 670], ["jcrate", 2010, 1352], ["jcrate", 2990, 1352], ["jcrate", 2290, 1180], ["jcrate", 2290, 1010], ["jcrate", 2690, 670], ["barrels", 1100, 1352]],
	},
	{
		"name": "Space Station", "size": Vector2(3000, 1500), "tile": 6,
		"bg": 2,
		"sky_top": Color(0.02, 0.03, 0.08), "sky_bottom": Color(0.08, 0.10, 0.22),
		"hill": Color(0.05, 0.07, 0.16), "sun": Color(0.90, 0.95, 1.00), "fx": "none",
		"platforms": [
			Rect2(0, 1452, 950, 48),
			Rect2(1250, 1452, 950, 48),
			Rect2(2500, 1452, 500, 48),
			Rect2(1300, 1280, 400, 48),
			Rect2(1350, 1110, 300, 48),
			Rect2(1300, 940, 400, 48),
			Rect2(1400, 770, 260, 48),
			Rect2(1350, 600, 300, 48),
			Rect2(100, 1280, 420, 48),
			Rect2(2480, 1280, 420, 48),
			Rect2(350, 1110, 320, 48),
			Rect2(2330, 1110, 320, 48),
			Rect2(200, 940, 300, 48),
			Rect2(2500, 940, 300, 48),
			Rect2(450, 770, 280, 48),
			Rect2(2270, 770, 280, 48),
		],
		"spawns": [Vector2(250, 1420), Vector2(1400, 1420), Vector2(300, 1248), Vector2(500, 1078), Vector2(350, 908), Vector2(580, 738), Vector2(2650, 1420), Vector2(2850, 1420), Vector2(2680, 1248), Vector2(2480, 1078), Vector2(2650, 908), Vector2(2400, 738)],
		"pickups": [Vector2(400, 1422), Vector2(2700, 1422), Vector2(300, 1250), Vector2(1500, 570), Vector2(2700, 1250), Vector2(1500, 1080)],
		"decor": [["sb_hut", 720, 1452], ["crate", 1670, 1452], ["column", 1970, 1452], ["crate", 160, 1452], ["crate", 1490, 1452], ["crate", 390, 1280], ["crate", 590, 1110], ["crate", 440, 940], ["crate", 670, 770], ["crate", 2740, 1452], ["crate", 2770, 1280], ["crate", 2570, 1110], ["crate", 2740, 940], ["crate", 2490, 770], ["barrels", 1800, 1452]],
	},
	{
		"name": "City Underground", "size": Vector2(3200, 1600), "tile": 7,
		"bg": 3,
		"sky_top": Color(0.03, 0.04, 0.10), "sky_bottom": Color(0.10, 0.12, 0.25),
		"hill": Color(0.08, 0.08, 0.14), "sun": Color(0.95, 0.95, 0.90), "fx": "rain",
		"platforms": [
			Rect2(0, 1552, 3200, 48),
			Rect2(600, 1400, 300, 48),
			Rect2(1450, 1400, 400, 48),
			Rect2(2300, 1400, 300, 48),
			Rect2(0, 1240, 3200, 48),
			Rect2(300, 1065, 400, 48),
			Rect2(1400, 1065, 400, 48),
			Rect2(2500, 1065, 400, 48),
			Rect2(700, 885, 320, 48),
			Rect2(2200, 885, 320, 48),
			Rect2(1300, 720, 400, 48),
		],
		"spawns": [Vector2(300, 1520), Vector2(750, 1368), Vector2(500, 1208), Vector2(500, 1033), Vector2(860, 853), Vector2(1400, 688), Vector2(2900, 1520), Vector2(2450, 1368), Vector2(2700, 1208), Vector2(2700, 1033), Vector2(2340, 853), Vector2(1700, 1368)],
		"pickups": [Vector2(600, 1522), Vector2(2600, 1522), Vector2(900, 1210), Vector2(1600, 1370), Vector2(2300, 1210), Vector2(1620, 690)],
		"decor": [["column", 720, 1552], ["crate", 1320, 1552], ["barrels", 1620, 1552], ["sandbags", 1920, 1552], ["column", 2520, 1552], ["crate", 3120, 1552], ["crate", 210, 1552], ["crate", 590, 1240], ["crate", 590, 1065], ["crate", 950, 885], ["crate", 1490, 720], ["crate", 2990, 1552], ["crate", 2790, 1240], ["crate", 2790, 1065], ["crate", 2430, 885], ["crate", 1790, 1400]],
	},
	{
		"name": "Volcanic Cavern", "size": Vector2(3000, 1500), "tile": 8,
		"bg": 4,
		"sky_top": Color(0.12, 0.05, 0.05), "sky_bottom": Color(0.30, 0.10, 0.08),
		"hill": Color(0.15, 0.06, 0.06), "sun": Color(1.00, 0.55, 0.20), "fx": "embers",
		"lava": [Rect2(1000, 1400, 250, 100), Rect2(1750, 1400, 250, 100)],
		"platforms": [
			Rect2(0, 1452, 1000, 48),
			Rect2(1250, 1452, 500, 48),
			Rect2(2000, 1452, 1000, 48),
			Rect2(250, 1280, 420, 48),
			Rect2(1300, 1280, 460, 48),
			Rect2(2350, 1280, 420, 48),
			Rect2(100, 1110, 240, 48),
			Rect2(700, 1110, 360, 48),
			Rect2(1800, 1110, 360, 48),
			Rect2(2700, 1110, 240, 48),
			Rect2(450, 940, 320, 48),
			Rect2(1250, 940, 400, 48),
			Rect2(2050, 940, 320, 48),
			Rect2(800, 770, 320, 48),
			Rect2(1900, 770, 320, 48),
			Rect2(300, 600, 260, 48),
			Rect2(1200, 600, 360, 48),
			Rect2(2500, 600, 260, 48),
		],
		"spawns": [Vector2(300, 1420), Vector2(1300, 1420), Vector2(1400, 1248), Vector2(850, 1078), Vector2(600, 908), Vector2(950, 738), Vector2(1600, 1420), Vector2(2600, 1420), Vector2(2500, 1248), Vector2(2000, 1078), Vector2(2200, 908), Vector2(2050, 738)],
		"pickups": [Vector2(450, 1250), Vector2(2720, 1250), Vector2(1500, 1250), Vector2(1500, 910), Vector2(950, 740), Vector2(1400, 570)],
		"decor": [["crate", 200, 1452], ["column", 1500, 1452], ["crate", 2800, 1452], ["crate", 720, 1452], ["barrels", 2420, 1452], ["crate", 1390, 1452], ["crate", 940, 1110], ["crate", 690, 940], ["crate", 1040, 770], ["crate", 2690, 1452], ["crate", 2590, 1280], ["crate", 2090, 1110], ["crate", 2290, 940], ["crate", 2140, 770]],
	},
	{
		"name": "Pirate Island", "size": Vector2(3000, 1500), "tile": 9,
		"sky_top": Color(0.45, 0.75, 0.95), "sky_bottom": Color(0.85, 0.93, 0.97),
		"hill": Color(0.30, 0.50, 0.35), "sun": Color(1.00, 0.95, 0.60), "fx": "none",
		"platforms": [
			Rect2(0, 1452, 3000, 48),
			Rect2(100, 1280, 350, 48),
			Rect2(350, 1110, 320, 48),
			Rect2(600, 940, 300, 48),
			Rect2(850, 770, 280, 48),
			Rect2(1050, 600, 260, 48),
			Rect2(1400, 1110, 400, 48),
			Rect2(1500, 1280, 300, 48),
			Rect2(2050, 1280, 550, 48),
			Rect2(2000, 1110, 650, 48),
			Rect2(2400, 940, 300, 48),
			Rect2(2550, 770, 240, 48),
		],
		"spawns": [Vector2(300, 1420), Vector2(250, 1248), Vector2(500, 1078), Vector2(750, 908), Vector2(1150, 568), Vector2(1450, 1078), Vector2(2700, 1420), Vector2(2200, 1248), Vector2(2200, 1078), Vector2(2550, 908), Vector2(2650, 738), Vector2(1900, 1420)],
		"pickups": [Vector2(600, 1422), Vector2(2910, 1422), Vector2(2420, 1250), Vector2(1500, 1080), Vector2(2550, 910), Vector2(1150, 570)],
		"decor": [["palms", 400, 1452], ["palms", 2850, 1452], ["crate", 720, 1452], ["barrels", 1020, 1452], ["column", 1320, 1452], ["crate", 1620, 1452], ["barrels", 2220, 1452], ["column", 2520, 1452], ["crate", 2820, 1452], ["crate", 210, 1452], ["crate", 340, 1280], ["crate", 590, 1110], ["crate", 840, 940], ["crate", 1240, 600], ["crate", 1540, 1110], ["crate", 2290, 1280], ["crate", 2290, 1110], ["crate", 2640, 940], ["crate", 2740, 770], ["crate", 1990, 1452]],
	},
	{
		"name": "Neon City", "size": Vector2(3400, 1800), "tile": 10,
		"bg": 5,
		"sky_top": Color(0.05, 0.04, 0.16), "sky_bottom": Color(0.16, 0.10, 0.32),
		"hill": Color(0.08, 0.06, 0.20), "sun": Color(1.00, 0.45, 0.75), "fx": "rain",
		"platforms": [
			Rect2(0, 1752, 1450, 48),
			Rect2(1950, 1752, 1450, 48),
			Rect2(150, 1580, 420, 48),
			Rect2(2830, 1580, 420, 48),
			Rect2(1500, 1580, 400, 48),
			Rect2(1300, 1400, 800, 48),
			Rect2(250, 1100, 520, 48),
			Rect2(2630, 1100, 520, 48),
			Rect2(850, 1280, 320, 48),
			Rect2(2180, 1250, 320, 48),
			Rect2(1050, 950, 300, 48),
			Rect2(2050, 950, 300, 48),
			Rect2(400, 800, 380, 48),
			Rect2(2620, 800, 380, 48),
		],
		"spawns": [Vector2(300, 1720), Vector2(900, 1720), Vector2(350, 1548), Vector2(1000, 1248), Vector2(500, 1068), Vector2(580, 768), Vector2(2550, 1720), Vector2(3100, 1720), Vector2(3000, 1548), Vector2(2330, 1218), Vector2(2900, 1068), Vector2(2800, 768)],
		"pickups": [Vector2(600, 1722), Vector2(2800, 1722), Vector2(500, 1550), Vector2(1700, 1370), Vector2(3000, 1550), Vector2(1700, 1550)],
		"decor": [["sb_vent", 720, 1752], ["crate", 1320, 1752], ["barrels", 2070, 1752], ["sb_vent", 2670, 1752], ["crate", 2970, 1752], ["barrels", 3270, 1752], ["sb_vent", 210, 1752], ["sb_vent", 1090, 1280], ["sb_vent", 590, 1100], ["sb_vent", 670, 800], ["sb_vent", 3090, 1580], ["sb_vent", 2420, 1250], ["sb_vent", 2990, 1100], ["sb_vent", 2890, 800]],
	},
	{
		"name": "Ancient Temple", "size": Vector2(3000, 1750), "tile": 11,
		"bg": 6,
		"sky_top": Color(0.10, 0.16, 0.12), "sky_bottom": Color(0.45, 0.55, 0.35),
		"hill": Color(0.25, 0.35, 0.20), "sun": Color(1.00, 0.80, 0.35), "fx": "dust",
		"platforms": [
			Rect2(0, 1552, 1200, 48),
			Rect2(1800, 1552, 1200, 48),
			Rect2(1150, 1702, 700, 48),
			Rect2(1200, 1620, 200, 48),
			Rect2(1600, 1620, 200, 48),
			Rect2(250, 1380, 420, 48),
			Rect2(2330, 1380, 420, 48),
			Rect2(1050, 1210, 900, 48),
			Rect2(1200, 1040, 600, 48),
			Rect2(1350, 870, 300, 48),
			Rect2(450, 1210, 300, 48),
			Rect2(2250, 1210, 300, 48),
			Rect2(600, 1040, 300, 48),
			Rect2(2100, 1040, 300, 48),
		],
		"spawns": [Vector2(300, 1520), Vector2(900, 1520), Vector2(450, 1348), Vector2(600, 1178), Vector2(1300, 1588), Vector2(1200, 1178), Vector2(2100, 1520), Vector2(2700, 1520), Vector2(2500, 1348), Vector2(2400, 1178), Vector2(1700, 1588), Vector2(1800, 1178)],
		"pickups": [Vector2(600, 1522), Vector2(2400, 1522), Vector2(450, 1350), Vector2(1500, 840), Vector2(2500, 1350), Vector2(1500, 1672)],
		"decor": [["sb_block", 1200, 1702], ["sb_block", 1800, 1702], ["sb_shrine", 720, 1552], ["sb_block", 1020, 1552], ["column", 1920, 1552], ["sb_shrine", 2220, 1552], ["sb_block", 2520, 1552], ["column", 2820, 1552], ["column", 210, 1552], ["column", 540, 1380], ["column", 1290, 1210], ["column", 2490, 1210], ["column", 1890, 1210], ["barrels", 1150, 1552]],
	},
	{
		"name": "Airship Fleet", "size": Vector2(3200, 1500), "tile": 11,
		"sky_top": Color(0.55, 0.30, 0.45), "sky_bottom": Color(0.98, 0.70, 0.45),
		"hill": Color(0.45, 0.30, 0.35), "sun": Color(1.00, 0.75, 0.40), "fx": "dust",
		"platforms": [
			Rect2(0, 1380, 1000, 48),
			Rect2(1250, 1210, 700, 48),
			Rect2(2200, 1380, 1000, 48),
			Rect2(1000, 1452, 1200, 48),
			Rect2(350, 1210, 300, 48),
			Rect2(400, 1040, 260, 48),
			Rect2(1550, 1040, 300, 48),
			Rect2(1600, 870, 260, 48),
			Rect2(2600, 1210, 300, 48),
			Rect2(2650, 1040, 260, 48),
		],
		"spawns": [Vector2(200, 1348), Vector2(1400, 1178), Vector2(500, 1178), Vector2(530, 1008), Vector2(1150, 1420), Vector2(1450, 1420), Vector2(2500, 1348), Vector2(3000, 1348), Vector2(2750, 1178), Vector2(2780, 1008), Vector2(1750, 1420), Vector2(2050, 1420)],
		"pickups": [Vector2(450, 1350), Vector2(2750, 1350), Vector2(1300, 1422), Vector2(1600, 840), Vector2(1700, 1010), Vector2(500, 1180)],
		"decor": [["column", 1600, 1452], ["sb_block", 720, 1380], ["crate", 2620, 1380], ["crate", 110, 1380], ["crate", 1490, 1210], ["crate", 590, 1210], ["crate", 620, 1040], ["crate", 1240, 1452], ["crate", 3090, 1380], ["crate", 2840, 1210], ["crate", 2870, 1040], ["crate", 2140, 1452], ["barrels", 600, 1380]],
	},
]
const DECOR_TEX := {
	"crate": DECOR_CRATE, "barrels": DECOR_BARRELS, "sandbags": DECOR_SANDBAGS,
	"palms": DECOR_PALMS, "rock": DECOR_ROCK, "bridge": DECOR_BRIDGE,
	"column": DECOR_COLUMN,
	"jtree": DECOR_JTREE, "jpalm": DECOR_JPALM, "jtower": DECOR_JTOWER,
	"jstatue": DECOR_JSTATUE, "jpillar": DECOR_JPILLAR, "jcrate": DECOR_JCRATE,
	"jrock": DECOR_JROCK, "jbush": DECOR_JBUSH, "jbridge": DECOR_JBRIDGE,
	"jarch": DECOR_JARCH, "jplatform": DECOR_JPLATFORM,
	"sb_hut": DECOR_SB_HUT, "sb_hut_pink": DECOR_SB_HUT_PINK,
	"sb_hut_blue": DECOR_SB_HUT_BLUE, "sb_vent": DECOR_SB_VENT,
	"sb_slab": DECOR_SB_SLAB, "sb_trap": DECOR_SB_TRAP,
	"sb_shrine": DECOR_SB_SHRINE, "sb_block": DECOR_SB_BLOCK,
	"sb_altar": DECOR_SB_ALTAR, "sb_hut_green": DECOR_SB_HUT_GREEN,
	"sb_crate": DECOR_SB_CRATE, "sb_vent_orange": DECOR_SB_VENT_ORANGE,
}
const PLAYER_COLORS := [
	Color(0.95, 0.3, 0.25), Color(0.25, 0.55, 0.95), Color(0.3, 0.85, 0.4),
	Color(0.95, 0.8, 0.2), Color(0.75, 0.4, 0.9), Color(0.95, 0.5, 0.2),
]
const WEAPON_ICONS := {
	0: preload("res://assets/weapons/rifle.png"),
	1: preload("res://assets/weapons/smg.png"),
	2: preload("res://assets/weapons/shotgun.png"),
	3: preload("res://assets/weapons/sniper.png"),
	4: preload("res://assets/weapons/rocket.png"),
	5: preload("res://assets/weapons/pistol.png"),
}
const EXPLOSION_TEX: Texture2D = preload("res://assets/effects/explosion1.png")
const FIREBALL_TEX: Texture2D = preload("res://assets/effects/fireball1.png")
const SMOKE_TEX: Texture2D = preload("res://assets/effects/smoke.png")
# Phase 4/6 — Sky Brawl art (SKY_BRAWL_USE.md): flat-vector effects
# with clean transparency. effect_006 is the small hit spark,
# effect_001 the explosion sunburst.
const SB_HIT_TEX: Texture2D = preload("res://assets/skybrawl/effects/effect_006.png")
const SB_EXPLOSION_TEX: Texture2D = preload("res://assets/skybrawl/effects/effect_001.png")
const SB_SMOKE_TEX: Texture2D = preload("res://assets/skybrawl/effects/effect_004.png")

var players_node: Node2D
var bullets_node: Node2D
var pickups_node: Node2D
var grenades_node: Node2D
var fx_node: Node2D
var spawner: MultiplayerSpawner
var audio # GameAudio
var map_size: Vector2 = Vector2(2880, 1440)
var map_id: int = 0
var game_mode: int = 0 # 0 FFA, 1 TDM
var kill_limit: int = 10
var match_over: bool = false
var _leaving: bool = false # set when leaving for the menu: _process must stop (multiplayer is torn down before the scene change lands)

var hud: CanvasLayer
var hp_bar: GoBar # v3.2: gohud bar (label + VALUE readout built in)
var fuel_bar: GoBar
var kills_label: Label
var deaths_label: Label
var players_label: Label
var weapon_icon: TextureRect
var weapon_label: Label
var grenade_label: Label
var timer_label: Label
var score_label: Label
var message_label: Label
var host_ip_label: Label
var scoreboard_panel: PanelContainer
var scoreboard_list: VBoxContainer
var pause_panel: PanelContainer
var end_panel: PanelContainer
var end_title: Label
var end_list: VBoxContainer
var _end_box: VBoxContainer # Phase 4: MVP banner is inserted here
var _mvp_nodes: Array = [] # Phase 4: banner widgets, cleared per match
var end_rematch_btn: Button
var error_panel: PanelContainer
var error_label: Label
var move_stick
var aim_stick
var grenade_button: Button
var switch_button: Button
var reload_button: Button # v2.4
var pause_button: Button
var score_button: Button
var _topright_btn_row: HBoxContainer # QA-057: SCORE + pause live in the top-right panel
var hint_label: Label
var bullet_pool: BulletPool # v2.4: pooled bullets
var shooting_sync: ShootingSync # v2.4: host-side fire-rate/ammo validation
var max_players: int = 8 # room setting (GameData); MAX_PLAYERS is the cap

# Touch input state, read by the local player.
# v2.2: the left stick is a full 2D vector now (x = move, y = jump/fly).
# There is no JUMP button any more — pushing the left stick up jumps,
# holding it up while airborne is the jetpack.
# v3.2: firing comes from the AIM stick (Mini Militia style) — the
# right stick aims AND fires while held (see _update_touch_state).
# There is no FIRE button any more (CONTROLS_CHANGE.md).
var touch_move_vec: Vector2 = Vector2.ZERO
var touch_aim: Vector2 = Vector2.ZERO
var touch_aim_active: bool = false
var touch_firing: bool = false

var _move_touch_id: int = -1
var _aim_touch_id: int = -1
# QA-054: when the last touch ended (msec clock). The mouse-aim
# fallback in player.gd must never fire from a touch Godot emulated
# as a mouse press — touch_recently_used() is true while any stick
# is held and for 500 ms after the last touch ends, so even a stale
# emulated button-up in the release frame cannot swing the aim.
var _last_touch_msec: int = -1000000
# v3.2 right-stick fire (CONTROLS_CHANGE.md §2): semi-auto weapons fire
# once per fresh ZERO -> non-zero transition of the aim vector. The
# transition arms one pending shot (QA-027 carry-over: a flick fires
# even if the finger is gone by the time the shooting step runs);
# the shooting step consumes it, reload/respawn/pause/countdown
# discard it. Auto weapons ignore the flag and fire on touch_firing.
var _aim_fire_pending: bool = false
var _aim_vec_prev_nonzero: bool = false
var _next_index: int = 1
var _spawned: Dictionary = {}
var _spawn_data: Dictionary = {} # v3.2 QA-047: pid -> spawn data dict, kept so the server can re-send a spawn (retry / late joiner) and answer player-list requests.
var _server_answered: bool = false # v3.2 QA-047: any spawn/list packet received from the server (shown in the join error so a Wi-Fi problem can be told apart from a game bug).
var _udp_broadcast: PacketPeerUDP
var _udp_broadcast_sockets: Array[PacketPeerUDP] = [] # v2.4: one socket per broadcast address
var _broadcast_timer: float = 0.0
var _pickup_timer: float = 0.0
# Phase 5 — pinned centre weapon: pickups[3] is the centre spot on
# every map; it spawns ONLY Sniper (3) / Rocket (4), alternating,
# and the HUD shows a visible timer for the next one.
var _centre_kind_next: int = 3 # Sniper first, then Rocket, alternating
var _centre_label: Label
# Phase 3B physics systems (GAP-37/45/51/64/66):
var _pickup_spot_timers: Dictionary = {} # spot index -> seconds until respawn
var _damage_event_seq: int = 0 # unique damage event ids (GAP-43)
# QA-031 (T-56): host-side kill-credit lock. Two shooters landing
# lethal hits on the same victim in the same moment used to both
# credit a kill: the host reads the victim's replicated health,
# stale by ~33 ms + latency, so both hits computed lethal. The first
# credit locks the victim (peer id -> lock msec); a second credit
# inside KILL_CREDIT_LOCK_MS is denied. The lock expires after 1 s
# so a later genuine kill in the victim's next life is never blocked
# (respawn takes 3 s, and the lock is also cleared on disconnect /
# round reset). Server-only: only the host ever populates it.
var _kill_credit_lock: Dictionary = {}
const KILL_CREDIT_LOCK_MS: int = 1000
var _barrels: Array = [] # {rect, sprite, shape, hp, alive} (GAP-64)
var _bounce_pads: Array = [] # {rect, area, cooldowns{peer: t}} (GAP-66)
var _physics_test: bool = false # --physics-test harness (T-01..T-75 support)
var _phys_steps: Array = []
var _phys_step: int = 0
var _phys_in_step: bool = false
var _phys_timer: float = 0.0
var _phys_passed: int = 0
var _phys_failed: int = 0
var _phys_done: bool = false
var _phys_data: Dictionary = {}
var _perf_test: bool = false # --perf-test harness (GAP-73)
var _perf_elapsed: float = 0.0
var _perf_mem0: int = 0
var _perf_done: bool = false
var _perf_seconds: float = 60.0 # T-73: --perf-seconds=N overrides (default 60)
var _perf_bots: int = 0 # T-73: --perf-bots=N idle bot players (default 0)
var _perf_bots_spawned: bool = false
var _initial_pickups_done: bool = false
var _local_player: Node = null
var _join_timer: float = 0.0
var _join_failed: bool = false
var _ready_announced: bool = false
var _time_left: float = 300.0
var _time_sync_timer: float = 0.0
var _end_shown: bool = false
var _smoke_test: bool = false
var _smoke_elapsed: float = 0.0
var _smoke_phase: int = -1
var _smoke_logged: bool = false
var _smoke_grenade_done: bool = false
var _smoke_switch_done: bool = false
var _smoke_shot_aim_done: bool = false
var _smoke_shot_boom_done: bool = false
var _smoke_move_idx: int = -1
var _smoke_aim_idx: int = -1
var _smoke_fire_owns_aim: bool = false # v3.2: _smoke_set_fire holds the aim stick when nothing else does
var _hint_timer: float = 10.0
var _joystick_test: bool = false
var _joy_steps: Array = []
var _joy_step: int = 0
var _joy_in_step: bool = false
var _joy_timer: float = 0.0
var _joy_passed: int = 0
var _joy_failed: int = 0
var _joy_done: bool = false
var _joy_shots_before: int = 0
var _joy_fuel_before: float = 0.0
var _joy_pos_before: Vector2 = Vector2.ZERO
var _joy_vel_before: Vector2 = Vector2.ZERO
var _joy_mouse_seen: bool = false # QA-054: emulated mouse button was actually down during the hold
var _joy_mouse_pos_seen: Vector2 = Vector2.ZERO # QA-054: emulated mouse position during the hold
var _joy_aim_before: float = 0.0 # QA-054: aim angle before the push-right hold
var _lava_cd: Dictionary = {} # peer id -> seconds until next lava damage tick
var _round_wins: Dictionary = {} # v2.4 Survival: peer id -> rounds won
# Phase 4 — kill feed, streaks, countdown, hitmarkers, spectator.
var _kill_feed_list: VBoxContainer
var _kill_feed_entries: Array = [] # {label, expiry}
var _kill_streaks: Dictionary = {} # peer id -> current kill streak
var _best_streaks: Dictionary = {} # peer id -> best kill streak this match
var _fed_deaths: Dictionary = {} # peer id -> true once this death was fed (no double entries)
var _alive_watch: Dictionary = {} # peer id -> was alive last frame (host death watcher)
var _countdown_active: bool = false
var _countdown_t: float = 0.0
var _countdown_last_shown: int = -1
var _fight_timer: float = 0.0
var _countdown_label: Label
var _countdown_sub: Label
var _hitmarker_label: Label
var _hitmark_timer: float = 0.0
var _last_hitmark_seq: int = 0
var fps_label: Label
var _spectate_cam: Camera2D
var _spectate_label: Label
var _spectate_next_btn: Button
var _spectate_target: Node = null
var _spectate_idx: int = 0
var _spectating: bool = false
var _weapon_panel: PanelContainer
var _weapon_list: VBoxContainer
# Phase 4 — features test harness (--features-test).
var _features_test: bool = false
var _feat_steps: Array = []
var _feat_step: int = 0
var _feat_in_step: bool = false
var _feat_timer: float = 0.0
var _feat_passed: int = 0
var _feat_failed: int = 0
var _feat_done: bool = false
var _feat_bot: Node = null
var _round_number: int = 1 # v2.4 Survival: current round
var _spawn_retry_timer: float = 0.0 # v2.4: request_spawn retry clock
var _fire_test: bool = false # v2.4: --fire-test harness
var _fire_steps: Array = []
var _ft_fire_owns_aim: bool = false # v3.2: _ft_press_fire holds the aim stick when nothing else does
var _fire_step: int = 0
var _fire_in_step: bool = false
var _fire_timer: float = 0.0
var _fire_passed: int = 0
var _fire_failed: int = 0
var _fire_done: bool = false
var _fire_shots_before: int = 0
var _fire_pos_before: Vector2 = Vector2.ZERO
var _fire_grenades_before: int = 0
var _ft_tap_left: int = 0 # T-33 rapid-tap driver: taps remaining
var _ft_tap_timer: float = 0.0 # T-33: time until the next press/release
var _ft_tap_phase: int = 0 # T-33: 0 = press next, 1 = release next
var _fire_weapon_before: int = 0
# v3.2 two-peer join regression test (--join-test-host / --join-test-client).
var _join_test_host: bool = false
var _join_test_client: bool = false
var _join_test_timer: float = 0.0
var _join_test_done: bool = false
var _join_test_status_t: float = 0.0
var _join_test_moved: bool = false
var _join_test_pos_snap: Dictionary = {}
# v3.2 QA-047 — replication simulation harness (--repl-sim-test).
# True two-peer ENet cannot run in the sandbox (the OS blocks UDP
# sends), so this simulates the wire in one process: a server game
# instance plus a shadow client instance, with the server's spawn /
# list payloads delivered to the shadow by hand. It proves the
# handler logic and the retry re-send; it does NOT prove live ENet
# delivery — that still needs two real phones (see BUGS.md QA-047).
var _repl_sim_test: bool = false
var _repl_sim_step: int = 0
var _repl_sim_timer: float = 0.0
var _repl_sim_passed: int = 0
var _repl_sim_failed: int = 0
var _repl_sim_done: bool = false
var _repl_sim_sent: Array = [] # payloads _send_all_players_to recorded in sim mode
var _repl_sim_shadow = null # second Game instance playing the client
var _repl_sim_server_list: Array = []
var _repl_sim_move_start: Vector2 = Vector2.ZERO # CONTROLS-ATTACH snapshot
var _repl_sim_c2s_start: Vector2 = Vector2.ZERO # QA-053 RPC-C2S baseline (server pid-2 pos)
var _repl_sim_s2c_start: Vector2 = Vector2.ZERO # QA-053 RPC-S2C baseline (shadow pid-1 pos)
var _repl_sim_seq: int = 0 # QA-053: snapshot sequence for streamed snapshots
var _repl_sim_stream_x: float = 0.0 # QA-053: streamed snapshot target x (steady +5 px/frame)
var _repl_sim_stream_y: float = 0.0 # QA-053: streamed snapshot target y
var _repl_sim_track_prev: Vector2 = Vector2.INF # QA-053: smoothness tracker, previous pos
var _repl_sim_track_max_step: float = 0.0 # QA-053: biggest single-frame step RATE (px/s) seen
var _repl_sim_track_max_back: float = 0.0 # QA-053: biggest backward (snap-back) step seen
var _repl_sim_track_best_x: float = -INF # QA-053: furthest forward x reached (snap-back baseline)
var _repl_sim_warm_done: bool = false # QA-053: warm-up window passed (buffer full, tracking live)
var _repl_sim_bullet_a = null # QA-055: server instance bullet under test
var _repl_sim_bullet_b = null # QA-055: shadow instance bullet under test
var _repl_sim_bullet_max_err: float = 0.0 # QA-055: max pos error between the two bullets
var _repl_sim_bullet_max_step: float = 0.0 # QA-055: max step RATE (px/s) of the shadow bullet
var _repl_sim_bullet_prev_b: Vector2 = Vector2.INF # QA-055: previous shadow bullet pos
var _repl_sim_bullet_frames: int = 0 # QA-055: frames both bullets were tracked
var _net_test: bool = false # v2.4: --net-test harness
var _net_steps: Array = []
var _net_step: int = 0
var _net_in_step: bool = false
var _net_timer: float = 0.0
var _net_passed: int = 0
var _net_failed: int = 0
var _net_done: bool = false
var _nt_dc_kills_a: int = 0 # QA-031 double-credit test state
var _nt_dc_first: bool = false
var _nt_dc_second: bool = false
# v2.4 full-flow check: handed over from the menu via GameData
# (flow_phase 1 = in the match). The menu prints the final result
# when we return (phase 2).
var _flow_test: bool = false
var _game_shots: bool = false # v3.2: --game-shots captures HUD/countdown/pause/scoreboard/end to user://shot_*.png
var _gs_timer: float = 0.0
var _gs_stage: int = -1
var _flow_steps: Array = []
var _flow_step: int = 0
var _flow_in_step: bool = false
var _flow_timer: float = 0.0
var _flow_passed: int = 0
var _flow_failed: int = 0
var _flow_done: bool = false


func _ready() -> void:
	add_to_group("game")
	# v3.2 NEON ARENA: wire the gohud theme once, early, so the HUD
	# and dialogs inherit it (same preset as the menu in main.gd).
	GoUi.config = preload("res://ui/gohud_config.tres")
	GoUi.use_preset(GoThemePresets.SCIFI_DARK)
	process_mode = Node.PROCESS_MODE_ALWAYS
	map_id = clampi(GameData.map_id, 0, MAPS.size() - 1)
	game_mode = GameData.game_mode
	kill_limit = GameData.kill_limit
	max_players = clampi(GameData.max_players, 2, MAX_PLAYERS)
	_time_left = float(GameData.match_minutes * 60)
	_smoke_test = "--smoke-test" in OS.get_cmdline_user_args()
	_joystick_test = "--joystick-test" in OS.get_cmdline_user_args()
	_fire_test = "--fire-test" in OS.get_cmdline_user_args()
	_net_test = "--net-test" in OS.get_cmdline_user_args()
	_flow_test = GameData.flow_test and GameData.flow_phase == 1
	_scale_test = "--scale-test" in OS.get_cmdline_user_args()
	_collision_test = "--collision-test" in OS.get_cmdline_user_args()
	_physics_test = "--physics-test" in OS.get_cmdline_user_args()
	_perf_test = "--perf-test" in OS.get_cmdline_user_args()
	_features_test = "--features-test" in OS.get_cmdline_user_args()
	_game_shots = "--game-shots" in OS.get_cmdline_user_args()
	_join_test_host = "--join-test-host" in OS.get_cmdline_user_args()
	_join_test_client = "--join-test-client" in OS.get_cmdline_user_args() or "--join-test-client-quick" in OS.get_cmdline_user_args()
	_repl_sim_test = "--repl-sim-test" in OS.get_cmdline_user_args()
	# Test-only map override: --map=N loads that map (the collision
	# test uses it to run its pass-through checks on Jungle Ruins).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = clampi(int(a.trim_prefix("--map=")), 0, MAPS.size() - 1)
		elif a.begins_with("--perf-seconds="):
			_perf_seconds = maxf(10.0, float(a.trim_prefix("--perf-seconds=")))
		elif a.begins_with("--perf-bots="):
			_perf_bots = clampi(int(a.trim_prefix("--perf-bots=")), 0, 11)
	audio = AUDIO_SCRIPT.new()
	add_child(audio)
	audio.set_volumes(GameData.sfx_volume, GameData.music_volume)
	audio.set_music_enabled(GameData.music_enabled)
	# Phase 6: the match plays the battle track. The menu scene owns
	# the menu track; leaving the match stops this one (see
	# _on_leave_pressed) so music never overlaps or plays on.
	audio.play_battle_music()
	# Phase 4 — spectator camera (Survival/LMS): off until the local
	# player dies with no respawn coming (see _update_spectator).
	_spectate_cam = Camera2D.new()
	_spectate_cam.name = "SpectateCam"
	_spectate_cam.enabled = false
	add_child(_spectate_cam)
	# Phase 4 — match countdown (3-2-1-FIGHT). Skipped in every
	# scripted harness (they move/shoot from frame one) and in the
	# features test, which drives the countdown itself in step 1.
	var _is_test_mode := _smoke_test or _joystick_test or _fire_test or _net_test or _flow_test or _scale_test or _collision_test or _physics_test or _perf_test or _features_test or _repl_sim_test
	if not _is_test_mode:
		_countdown_active = true
		_countdown_t = 3.0
		_countdown_last_shown = -1
	var map: Dictionary = MAPS[map_id]
	map_size = map["size"]
	_build_background(map)
	_build_arena(map)
	_build_ice_zone(map)
	_build_bounce_pads(map)
	_build_lava(map)
	_build_ambient_fx(map)
	_build_nodes()
	# v2.4: bullet pool + host-side shooting validation live on the game.
	bullet_pool = BulletPool.new(BULLET_SCENE, bullets_node, 160) # GAP-67: 96 = 12/player at 8 players, below the 16-32 spec budget
	shooting_sync = ShootingSync.new()
	_build_hud()
	_build_touch_controls()
	_countdown_sub.text = _match_goal_text()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	if multiplayer.is_server():
		_start_broadcast()
		# Host spawns its own player now that the spawner exists.
		call_deferred("_spawn_self")
	else:
		# Client: tell the server we are ready ONLY now that our scene
		# (and its MultiplayerSpawner) exists. This is the v2 join fix.
		call_deferred("_announce_ready")
	_update_host_ip_label()


# --- Bullet pool (v2.4) ---

func obtain_bullet() -> Node:
	if bullet_pool != null:
		return bullet_pool.obtain()
	var b = BULLET_SCENE.instantiate()
	b.pooled = false
	return b


func return_bullet(b: Node) -> void:
	if bullet_pool != null:
		bullet_pool.release(b)
	else:
		b.queue_free()


func get_spawn_point(player_index: int) -> Vector2:
	var spawns: Array = MAPS[map_id]["spawns"]
	return spawns[(player_index - 1) % spawns.size()]


func next_damage_event_id() -> int:
	# Unique damage event ids (GAP-43, spec §17.8): the host numbers
	# every damage event; victims ignore repeats of an id they saw.
	_damage_event_seq += 1
	return _damage_event_seq


func is_spawn_valid(pos: Vector2, exclude_peer: int) -> bool:
	# Validated spawn (GAP-45, spec §17.7): inside the map, not
	# overlapping solid geometry, and >150 px from any live enemy.
	if pos.x < 40.0 or pos.y < 40.0 or pos.x > map_size.x - 40.0 or pos.y > map_size.y - 40.0:
		return false
	for child in players_node.get_children():
		if child.peer_id == exclude_peer or not child.alive:
			continue
		if child.global_position.distance_to(pos) < PhysicsConfig.SPAWN_ENEMY_CLEARANCE:
			return false
	var cap := CapsuleShape2D.new()
	cap.radius = 17.0
	cap.height = 52.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cap
	q.transform = Transform2D(0.0, pos)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var space := get_world_2d().direct_space_state
	return space.intersect_shape(q, 1).is_empty()


func get_valid_spawn_point(player_index: int, exclude_peer: int) -> Vector2:
	# Try the player's own spawn first, then every other spawn in
	# order; if none is valid, return INF and the caller retries
	# (0.5 s) instead of teleporting into a wall or a camper.
	# Phase 5 (TDM): spawns[0:6] are the left half (team 0) and
	# spawns[6:12] the right half (team 1) — a team tries its own
	# half first, then the other half, so teams never spawn
	# interleaved. FFA keeps the old round-robin order.
	var spawns: Array = MAPS[map_id]["spawns"]
	var n := spawns.size()
	var start := (player_index - 1) % n
	var order: Array = []
	if game_mode == 1:
		var team := (player_index - 1) % 2
		var half_start := team * 6
		for k in 6:
			order.append(half_start + ((start - half_start + k) % 6))
		for k in 6:
			order.append((1 - team) * 6 + k)
	else:
		for k in n:
			order.append((start + k) % n)
	for idx in order:
		var cand: Vector2 = spawns[int(idx)]
		if is_spawn_valid(cand, exclude_peer):
			return cand
	return Vector2.INF


func is_on_ice(pos: Vector2) -> bool:
	# Ice zone (GAP-51, spec §18.A): Frozen Fortress (map 4) only.
	# A floor-level zone; the player reads it in _apply_movement.
	# The zone is a separate system (game-side query), not code
	# inside the player controller.
	# QA-033: the duel rebuild shrank the map to 2200x1400 (floor
	# 1352) — the zone is the open slide lane x450-1750, kept clear
	# of floor decor so the slide run is unobstructed.
	if map_id != 4:
		return false
	var floor_top := 1352.0
	return pos.y > floor_top - 60.0 and pos.x > 450.0 and pos.x < 1750.0


func has_line_of_sight(from: Vector2, to: Vector2) -> bool:
	# Explosion wall obstruction (GAP-12, spec §10): a solid body
	# between the blast and the player blocks the damage/knockback.
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, 1)
	var hit: Dictionary = space.intersect_ray(query)
	if hit.is_empty():
		return true
	var hit_pos: Vector2 = hit["position"]
	return hit_pos.distance_to(from) >= from.distance_to(to) - 10.0


func _build_background(map: Dictionary) -> void:
	var grad := Gradient.new()
	grad.set_color(0, map["sky_top"])
	grad.set_color(1, map["sky_bottom"])
	var gtex := GradientTexture2D.new()
	gtex.gradient = grad
	gtex.width = 4
	gtex.height = 512
	gtex.fill_from = Vector2(0.5, 0.0)
	gtex.fill_to = Vector2(0.5, 1.0)
	var sky := Sprite2D.new()
	sky.texture = gtex
	sky.position = map_size * 0.5
	sky.scale = Vector2(map_size.x / 4.0, map_size.y / 512.0)
	sky.z_index = -10
	add_child(sky)
	# Phase 5 — far parallax image layer (Sky Brawl arena art).
	# Viewport scale only (~1.3x upscale of the 960x540 image),
	# horizontal parallax 0.25, tiled so it never runs out; the
	# procedural gradient stays in front at 50% alpha so the horizon
	# still matches the map palette. Maps without a "bg" key (the 5
	# POOR-fit day maps) keep the full procedural gradient.
	var bg_idx := int(map.get("bg", -1))
	if bg_idx >= 0 and bg_idx < BG_TEX.size():
		sky.modulate = Color(1, 1, 1, 0.5)
		var pb := ParallaxBackground.new()
		pb.layer = -100
		add_child(pb)
		var player_layer := ParallaxLayer.new()
		player_layer.motion_scale = Vector2(0.25, 0.0)
		player_layer.motion_mirroring = Vector2(1286, 0)
		pb.add_child(player_layer)
		var bg_spr := Sprite2D.new()
		bg_spr.texture = BG_TEX[bg_idx]
		bg_spr.scale = Vector2(1286.0 / 960.0, 723.0 / 540.0)
		bg_spr.position = Vector2(643, 362)
		player_layer.add_child(bg_spr)
	# Sun / moon.
	var sun := Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 32:
		var a := TAU * float(i) / 32.0
		pts.append(Vector2(cos(a), sin(a)) * 70.0)
	sun.polygon = pts
	sun.color = Color(map["sun"].r, map["sun"].g, map["sun"].b, 0.9)
	sun.position = Vector2(map_size.x * 0.8, 180)
	sun.z_index = -9
	add_child(sun)
	# Distant hills.
	for h in 2:
		var hill := Polygon2D.new()
		var hp := PackedVector2Array()
		var base_y := map_size.y - 130.0 - h * 60.0
		hp.append(Vector2(0, map_size.y))
		var steps := 24
		for i in steps + 1:
			var x := map_size.x * float(i) / steps
			var y := base_y - sin(float(i) * 0.9 + h * 2.0) * 70.0 - sin(float(i) * 0.37) * 40.0
			hp.append(Vector2(x, y))
		hp.append(Vector2(map_size.x, map_size.y))
		hill.polygon = hp
		hill.color = Color(map["hill"].r, map["hill"].g, map["hill"].b, 0.75 - h * 0.2)
		hill.z_index = -8 + h
		add_child(hill)


# QA-030: solid decor kinds — these are real cover. They get a
# collision rectangle on layer 1 (the same layer the bullet raycast
# and the player use), so bullets stop at them and players cannot walk
# through them. Everything else (trees, palms, bushes, bridges,
# arches) stays visual dressing with no collision, exactly as before.
const SOLID_DECOR_KINDS := ["crate", "barrels", "sandbags", "rock", "column",
	"jpillar", "jstatue", "jtower", "jcrate", "jrock",
	# Phase 5 — Sky Brawl solid structures (huts/blocks/vents/crate).
	"sb_hut", "sb_hut_pink", "sb_hut_blue", "sb_vent", "sb_vent_orange",
	"sb_shrine", "sb_block", "sb_hut_green", "sb_crate"]
# GAP-13: bridges/arches look walkable — they now get a thin top plank
# (24 px at the sprite's top edge), not the full texture.
const BRIDGE_DECOR_KINDS := ["bridge", "jbridge", "jarch"]
# GAP-14: per-kind inset (px trimmed per side) so the solid rect
# matches the visible sprite, not the transparent padding.
const DECOR_INSETS := {"crate": 6, "barrels": 8, "sandbags": 6, "rock": 10,
	"column": 10, "jpillar": 10, "jstatue": 8, "jtower": 10, "jcrate": 6, "jrock": 10,
	"sb_hut": 10, "sb_hut_pink": 10, "sb_hut_blue": 10, "sb_vent": 10,
	"sb_vent_orange": 10, "sb_shrine": 10, "sb_block": 10, "sb_hut_green": 10,
	"sb_crate": 10}


func _build_arena(map: Dictionary) -> void:
	var arena := StaticBody2D.new()
	arena.name = "Arena"
	arena.collision_layer = 1
	arena.collision_mask = 0
	add_child(arena)
	var platforms: Array = map["platforms"]
	for rect in platforms:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		arena.add_child(shape)
	_draw_tiles(map, platforms)
	# Walls + ceiling (collision only, no visual).
	var bounds := [
		Rect2(0, 0, 24, map_size.y), Rect2(map_size.x - 24, 0, 24, map_size.y),
		Rect2(0, 0, map_size.x, 24),
	]
	for rect in bounds:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = rect.size
		shape.shape = box
		shape.position = rect.get_center()
		arena.add_child(shape)
	# Decorations (visual only, behind the players).
	var decor: Array = map["decor"]
	for d in decor:
		var tex: Texture2D = DECOR_TEX[d[0]]
		var spr := Sprite2D.new()
		spr.texture = tex
		spr.position = Vector2(float(d[1]), float(d[2]) - tex.get_height() * 0.5)
		spr.z_index = -1
		add_child(spr)
		# QA-030: solid decor gets real collision on layer 1 (same
		# layer as platforms/walls, so the bullet raycast and the
		# player both hit it). The rectangle matches the sprite's
		# visible size and is centred on the sprite, so it covers
		# exactly what the player sees. Non-solid dressing (trees,
		# palms, bushes, bridges, arches) gets no shape and stays
		# pass-through, as before.
		if String(d[0]) in SOLID_DECOR_KINDS:
			var shape := CollisionShape2D.new()
			var box := RectangleShape2D.new()
			var inset := float(DECOR_INSETS.get(String(d[0]), 6))
			# Sides and top are inset (transparent sprite edges);
			# the bottom sits ON the ground point. An inset bottom
			# floats 6-10 px above the floor and the capsule's
			# rounded bottom rides up over low cover (crate, etc).
			box.size = Vector2(maxf(8.0, tex.get_width() - inset * 2.0), maxf(8.0, tex.get_height() - inset))
			shape.shape = box
			shape.position = Vector2(spr.position.x, spr.position.y + inset * 0.5)
			arena.add_child(shape)
			if String(d[0]) == "barrels":
				# Explosive barrel (GAP-64): the art is already on
				# every map and already solid cover; this registers
				# it as damageable (100 HP, explodes on death).
				_barrels.append({"rect": Rect2(shape.position - box.size * 0.5, box.size),
					"sprite": spr, "shape": shape, "hp": PhysicsConfig.BARREL_HEALTH, "alive": true})
		elif String(d[0]) in BRIDGE_DECOR_KINDS:
			# Walkable-looking bridge/arch: thin top plank only.
			var shape2 := CollisionShape2D.new()
			var box2 := RectangleShape2D.new()
			box2.size = Vector2(tex.get_width(), 24.0)
			shape2.shape = box2
			shape2.position = Vector2(spr.position.x, spr.position.y - tex.get_height() * 0.5 + 12.0)
			arena.add_child(shape2)


func _build_ice_zone(map: Dictionary) -> void:
	# Ice zone visual (GAP-51): a pale-blue sheen over the frozen
	# floor so the low-friction area is readable in play.
	if map_id != 4:
		return
	var sheen := Polygon2D.new()
	sheen.polygon = PackedVector2Array([
		Vector2(450, 1352), Vector2(1750, 1352),
		Vector2(1750, 1400), Vector2(450, 1400)])
	sheen.color = Color(0.65, 0.85, 1.0, 0.35)
	sheen.z_index = -1
	add_child(sheen)


func _build_bounce_pads(map: Dictionary) -> void:
	# Bounce pads (GAP-66, spec §22.E): two per map on the floor,
	# velocity.y = -750 on touch, one launch per contact (0.3 s
	# per-player cooldown). Visual: a yellow spring pad.
	var floor_top := 1352.0
	var plats: Array = map["platforms"]
	if not plats.is_empty():
		floor_top = float((plats[0] as Rect2).position.y)
	for fx in [0.3, 0.7]:
		var cx: float = map_size.x * float(fx)
		var pad := Area2D.new()
		pad.name = "BouncePad_%d" % int(cx)
		pad.collision_layer = 8 # trigger (spec §24.D, GAP-71)
		pad.collision_mask = 2 # players only
		pad.position = Vector2(cx, floor_top - 8.0)
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(90, 16)
		shape.shape = rect
		pad.add_child(shape)
		var vis := Polygon2D.new()
		vis.polygon = PackedVector2Array([
			Vector2(-45, -8), Vector2(45, -8), Vector2(45, 8), Vector2(-45, 8)])
		vis.color = Color(1.0, 0.85, 0.2, 0.95)
		pad.add_child(vis)
		add_child(pad)
		_bounce_pads.append({"rect": Rect2(cx - 45, floor_top - 16, 90, 16),
			"area": pad, "cooldowns": {}})
		pad.body_entered.connect(_on_bounce_pad_body.bind(pad))


func _on_bounce_pad_body(body: Node2D, pad: Area2D) -> void:
	# One launch per contact: the per-player cooldown stops the pad
	# retriggering every physics frame while the player overlaps it.
	if not body.is_in_group("players"):
		return
	var p = body
	if not p.alive:
		return
	for entry in _bounce_pads:
		if entry["area"] == pad:
			var cds: Dictionary = entry["cooldowns"]
			var now := Time.get_ticks_msec() / 1000.0
			if float(cds.get(p.peer_id, -10.0)) + PhysicsConfig.BOUNCE_COOLDOWN > now:
				return
			cds[p.peer_id] = now
			p.velocity.y = PhysicsConfig.BOUNCE_VELOCITY
			if p.has_method("_play_sound"):
				p._play_sound("jump")
			return


func try_barrel_hit(hit_pos: Vector2, dmg: int, owner_id: int) -> bool:
	# Bullet vs explosive barrel (GAP-64). Host-authorised: only the
	# server damages barrels; clients return false (just the spark).
	# Returns true when a barrel was hit (bullet is consumed).
	if not multiplayer.is_server():
		return false
	for b in _barrels:
		if not bool(b["alive"]):
			continue
		var r: Rect2 = b["rect"]
		if r.grow(6.0).has_point(hit_pos):
			b["hp"] = float(b["hp"]) - dmg
			if float(b["hp"]) <= 0.0:
				b["alive"] = false
				(b["sprite"] as Node2D).visible = false
				(b["shape"] as CollisionShape2D).set_deferred("disabled", true)
				rpc("barrel_destroyed_remote", _barrels.find(b))
				request_explosion(r.get_center(), PhysicsConfig.BARREL_BLAST_RADIUS,
					int(PhysicsConfig.BARREL_BLAST_DAMAGE), owner_id)
			return true
	return false


@rpc("any_peer", "call_local")
func barrel_destroyed_remote(idx: int) -> void:
	if idx < 0 or idx >= _barrels.size():
		return
	var b: Dictionary = _barrels[idx]
	b["alive"] = false
	(b["sprite"] as Node2D).visible = false
	(b["shape"] as CollisionShape2D).set_deferred("disabled", true)


func _build_lava(map: Dictionary) -> void:
	# Volcanic Cavern: glowing lava pools in the gaps of the floor.
	# Clearly visible (bright orange top), avoidable (safe platforms on
	# both sides, pools only 300 px wide), and never under a spawn/pickup.
	var pools: Array = map.get("lava", [])
	for r in pools:
		var rect: Rect2 = r
		var base := Polygon2D.new()
		base.polygon = PackedVector2Array([
			rect.position, Vector2(rect.position.x + rect.size.x, rect.position.y),
			rect.position + rect.size, Vector2(rect.position.x, rect.position.y + rect.size.y)])
		base.color = Color(0.85, 0.22, 0.05, 0.95)
		base.z_index = -1
		add_child(base)
		var top := Polygon2D.new()
		top.polygon = PackedVector2Array([
			rect.position, Vector2(rect.position.x + rect.size.x, rect.position.y),
			Vector2(rect.position.x + rect.size.x, rect.position.y + 12),
			Vector2(rect.position.x, rect.position.y + 12)])
		top.color = Color(1.0, 0.62, 0.12, 1.0)
		top.z_index = -1
		add_child(top)


func _build_ambient_fx(map: Dictionary) -> void:
	# Per-theme ambient particles (snow, embers, dust, rain, sparks,
	# leaves). They sit BEHIND the players (z_index -2) and are faint
	# enough never to hide a player, a bullet or the HUD.
	var kind: String = str(map.get("fx", "none"))
	if kind == "none":
		return
	var p := CPUParticles2D.new()
	p.amount = 80
	p.lifetime = 5.0
	p.preprocess = 5.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = map_size * 0.5
	p.position = map_size * 0.5
	p.z_index = -2
	match kind:
		"snow":
			p.direction = Vector2(0, 1)
			p.spread = 20.0
			p.gravity = Vector2(0, 60)
			p.initial_velocity_min = 30.0
			p.initial_velocity_max = 50.0
			p.color = Color(0.95, 0.97, 1.0, 0.85)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
		"embers":
			p.amount = 40
			p.lifetime = 2.5
			p.direction = Vector2(0, -1)
			p.spread = 30.0
			p.gravity = Vector2(0, -30)
			p.initial_velocity_min = 40.0
			p.initial_velocity_max = 70.0
			p.color = Color(1.0, 0.55, 0.15, 0.9)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 3.0
		"dust":
			p.amount = 50
			p.lifetime = 6.0
			p.direction = Vector2(1, 0)
			p.spread = 30.0
			p.gravity = Vector2.ZERO
			p.initial_velocity_min = 10.0
			p.initial_velocity_max = 20.0
			p.color = Color(0.8, 0.75, 0.65, 0.30)
			p.scale_amount_min = 3.0
			p.scale_amount_max = 5.0
		"rain":
			p.amount = 100
			p.lifetime = 1.2
			p.direction = Vector2(0, 1)
			p.spread = 5.0
			p.gravity = Vector2(0, 300)
			p.initial_velocity_min = 400.0
			p.initial_velocity_max = 500.0
			p.color = Color(0.7, 0.8, 1.0, 0.45)
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.0
		"sparks":
			p.amount = 30
			p.lifetime = 1.5
			p.direction = Vector2(0, -1)
			p.spread = 45.0
			p.gravity = Vector2(0, 100)
			p.initial_velocity_min = 60.0
			p.initial_velocity_max = 100.0
			p.color = Color(1.0, 0.75, 0.2, 0.9)
			p.scale_amount_min = 1.0
			p.scale_amount_max = 2.0
		"leaves":
			p.amount = 40
			p.lifetime = 7.0
			p.direction = Vector2(0.5, 1)
			p.spread = 40.0
			p.gravity = Vector2(0, 25)
			p.initial_velocity_min = 20.0
			p.initial_velocity_max = 30.0
			p.color = Color(0.4, 0.7, 0.3, 0.7)
			p.scale_amount_min = 2.0
			p.scale_amount_max = 4.0
	add_child(p)


func _update_lava(delta: float) -> void:
	# Server-side only: standing in lava hurts (20 hp per second, no kill
	# credit). Spawn protection covers fresh spawns; pools are shallow and
	# flanked by safe platforms, so a player can always jetpack out.
	if not multiplayer.is_server() or match_over:
		return
	var pools: Array = MAPS[map_id].get("lava", [])
	if pools.is_empty():
		return
	for child in players_node.get_children():
		if not child.alive:
			continue
		var feet: Vector2 = child.position + Vector2(0, 20)
		var in_lava := false
		for r in pools:
			var rect: Rect2 = r
			if rect.has_point(feet):
				in_lava = true
				break
		if not in_lava:
			continue
		var cd: float = float(_lava_cd.get(child.peer_id, 0.0))
		cd -= delta
		if cd <= 0.0:
			_lava_cd[child.peer_id] = 0.5
			# v2.4 BUG FIX: lava damage used to call take_damage()
			# directly on the server's copy of a remote player — the
			# owner's synchronizer then overwrote the health, so lava
			# only ever hurt the host. Route it to the victim's owning
			# peer like bullet damage.
			if child.get_multiplayer_authority() == multiplayer.get_unique_id():
				child.take_damage(10, 0)
			elif multiplayer.get_peers().has(child.get_multiplayer_authority()):
				child.rpc_id(child.get_multiplayer_authority(), "take_damage", 10, 0)
		else:
			_lava_cd[child.peer_id] = cd


func _draw_tiles(map: Dictionary, platforms: Array) -> void:
	var tex: Texture2D = TILE_TEX[clampi(int(map["tile"]), 0, TILE_TEX.size() - 1)]
	var tile_w := float(tex.get_width())
	var tile_h := float(tex.get_height())
	for rect in platforms:
		var r: Rect2 = rect
		var x: float = r.position.x
		while x < r.position.x + r.size.x - 0.5:
			var w := minf(tile_w, r.position.x + r.size.x - x)
			var spr := Sprite2D.new()
			spr.texture = tex
			spr.centered = false
			spr.position = Vector2(x, r.position.y)
			if w < tile_w:
				spr.region_enabled = true
				spr.region_rect = Rect2(0, 0, w, tile_h)
			add_child(spr)
			x += tile_w


func _build_nodes() -> void:
	# The game root is PROCESS_MODE_ALWAYS (so Esc / HUD input works while
	# paused); these gameplay containers are explicitly pausable so the
	# match itself freezes on pause.
	players_node = Node2D.new()
	players_node.name = "Players"
	players_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(players_node)

	bullets_node = Node2D.new()
	bullets_node.name = "Bullets"
	bullets_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	bullets_node.add_to_group("bullets_container")
	add_child(bullets_node)

	pickups_node = Node2D.new()
	pickups_node.name = "Pickups"
	pickups_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(pickups_node)

	grenades_node = Node2D.new()
	grenades_node.name = "Grenades"
	grenades_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(grenades_node)

	fx_node = Node2D.new()
	fx_node.name = "FX"
	fx_node.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(fx_node)

	spawner = MultiplayerSpawner.new()
	spawner.spawn_path = NodePath("../Players")
	spawner.spawn_function = _spawn_player_node
	add_child(spawner)


func _spawn_player_node(data) -> Node:
	var p = PLAYER_SCENE.instantiate()
	var pid: int = int(data["id"])
	p.name = str(pid)
	p.peer_id = pid
	p.player_index = int(data["index"])
	p.player_name = str(data["name"])
	p.color_index = int(data["color"])
	p.player_color = PLAYER_COLORS[int(data["color"]) % PLAYER_COLORS.size()]
	p.helmet = int(data["helmet"])
	p.team = int(data["team"])
	return p


func _spawn_self() -> void:
	_do_spawn(multiplayer.get_unique_id(), GameData.player_name, GameData.color_index, GameData.helmet)


func _announce_ready() -> void:
	if _ready_announced:
		return
	_ready_announced = true
	if multiplayer.is_server():
		# The host spawned itself directly (_spawn_self). Asking
		# itself over RPC is not allowed (it only logs an error),
		# and request_spawn is idempotent anyway.
		return
	rpc_id(1, "request_spawn", multiplayer.get_unique_id(), GameData.player_name, GameData.color_index, GameData.helmet, GameData.BUILD_VERSION)
	# v3.2 QA-047: also ask for the full player list — if our spawn
	# RPC was the one that got lost, the list heals us (it includes
	# our own player and the host's player). The 2 s retry in
	# _retry_spawn_if_needed re-sends both requests.
	rpc_id(1, "request_player_list")


func _retry_spawn_if_needed(delta: float) -> void:
	# v2.4: one lost UDP packet must never strand a client. While we
	# are still unspawned, re-send the request every 2 s until the
	# join timeout fires. request_spawn is idempotent on the server.
	if multiplayer.is_server() or _join_failed or match_over:
		return
	if _get_local_player() != null:
		return
	_spawn_retry_timer += delta
	if _spawn_retry_timer >= 2.0:
		_spawn_retry_timer = 0.0
		_ready_announced = false
		_announce_ready()


func _do_spawn(pid: int, pname: String, color_idx: int, helmet_style: int) -> void:
	# v3.2 QA-047: a re-request means the client's first spawn never
	# landed (the v3.1 bug) — re-send it instead of silently assuming
	# the client already has the player. The old code returned here
	# and the single dropped spawn RPC was never re-sent.
	if _spawned.has(pid):
		if multiplayer.is_server():
			_send_all_players_to(pid)
		return
	print("SPAWN: spawning peer ", pid, " (", pname, ") on ", "server" if multiplayer.is_server() else "client", " players_before=", players_node.get_child_count())
	_spawned[pid] = true
	var team := -1
	if game_mode == 1:
		team = (_next_index - 1) % 2
	# Survival (2) and Last Man Standing (3) are free-for-all: team -1.
	var data := {"id": pid, "index": _next_index, "name": pname, "color": color_idx, "helmet": helmet_style, "team": team}
	_next_index += 1
	_spawn_data[pid] = data
	spawner.spawn(data)
	# v3.2 QA-047: explicit spawn broadcast. v3.1 relied ONLY on the
	# MultiplayerSpawner's internal spawn RPC; on real phones the
	# client never received it (host showed 2 players, client 0).
	# The handler is idempotent, so a double delivery (spawner +
	# this RPC) is harmless. Guarded to real peers so offline
	# harnesses (net test) stay silent.
	if multiplayer.is_server() and multiplayer.get_peers().size() > 0:
		rpc("spawn_player_remote", data)


# v3.2 QA-047: send one peer every spawned player + the full list.
# Used when a client re-requests its spawn (retry) and when a peer
# connects to the game scene (late joiner / host player catch-up).
func _send_all_players_to(peer_id: int) -> void:
	if _repl_sim_test:
		# Test hook: record what WOULD be sent — offline there are no
		# real peers, so the guard below would skip the RPCs. The sim
		# delivers the recorded payloads to the shadow client by hand.
		for pid in _spawn_data.keys():
			_repl_sim_sent.append({"kind": "spawn_player_remote", "to": peer_id, "data": (_spawn_data[pid] as Dictionary).duplicate()})
		_repl_sim_sent.append({"kind": "player_list_remote", "to": peer_id, "data": _player_list_data()})
		return
	if not multiplayer.get_peers().has(peer_id):
		return
	for pid in _spawn_data.keys():
		rpc_id(peer_id, "spawn_player_remote", _spawn_data[pid])
	rpc_id(peer_id, "player_list_remote", _player_list_data())


func _player_list_data() -> Array:
	var out: Array = []
	for k in _spawn_data.keys():
		out.append(_spawn_data[k])
	return out


@rpc("any_peer")
func spawn_player_remote(data: Dictionary) -> void:
	# v3.2 QA-047: explicit spawn broadcast from the server (see
	# _do_spawn). Idempotent: a player with this id already present
	# is left alone, so spawner + RPC double delivery is harmless.
	# The player's own _ready places it at a valid spawn point.
	var pid := int(data.get("id", 0))
	if pid <= 0:
		return
	if players_node.get_node_or_null(str(pid)) != null:
		return
	_server_answered = true
	_spawned[pid] = true
	var p := _spawn_player_node(data)
	players_node.add_child(p)


@rpc("any_peer")
func despawn_player_remote(pid: int) -> void:
	# v3.2 QA-047: explicit despawn to match the explicit spawn — the
	# spawner's despawn RPC is the same single channel that lost the
	# spawn in v3.1, so a disconnect is also announced directly.
	var node := players_node.get_node_or_null(str(pid))
	if node != null:
		node.queue_free()


@rpc("any_peer")
func request_player_list() -> void:
	# v3.2 QA-047: a client that missed its spawn asks for the whole
	# player list; the server answers with every spawned player.
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender > 0:
		rpc_id(sender, "player_list_remote", _player_list_data())


@rpc("any_peer")
func player_list_remote(players: Array) -> void:
	# v3.2 QA-047: self-healing sync — the server's player list is
	# the authority. Spawn anything missing locally (including our
	# own player and the host's player, both of which v3.1 could
	# lose), and drop any ghost the server no longer lists.
	_server_answered = true
	var seen := {}
	for item in players:
		var d := item as Dictionary
		if d.is_empty():
			continue
		seen[int(d.get("id", 0))] = true
		spawn_player_remote(d)
	for child in players_node.get_children():
		if not seen.has(int(child.get("peer_id"))):
			child.queue_free()


@rpc("any_peer")
func request_spawn(pid: int, pname: String, color_idx: int, helmet_style: int, version: String = "") -> void:
	# Server only, and only after the client signalled it is ready.
	if not multiplayer.is_server():
		return
	# Version handshake (GAP-61, spec §21.G): a mismatched build is
	# refused with a readable message instead of desyncing silently.
	# Empty version = an older test caller; accept it.
	if version != "" and version != GameData.BUILD_VERSION:
		print("VERSION MISMATCH: peer %d runs %s, host runs %s — spawn refused" % [pid, version, GameData.BUILD_VERSION])
		if multiplayer.get_peers().has(pid):
			rpc_id(pid, "version_mismatch_remote", "Version mismatch: host runs %s, you run %s. Update and rejoin." % [GameData.BUILD_VERSION, version])
		return
	# Validate: the sender must be the peer it claims to be, the room
	# must not be full, and the spawn index must be in range.
	var sender := multiplayer.get_remote_sender_id()
	print("SPAWN REQ: from sender=", sender, " claiming pid=", pid, " version='", version, "' players=", players_node.get_child_count(), "/", max_players)
	if sender != 0 and sender != pid:
		print("SPAWN REQ: REJECTED sender != pid")
		return
	if players_node.get_child_count() >= max_players:
		print("SPAWN REQ: REJECTED room full")
		return
	_do_spawn(pid, pname, color_idx, helmet_style)


func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	# v2: do NOT spawn here. The client sends request_spawn once its
	# game scene (with MultiplayerSpawner) is ready.
	# v3.2 QA-047: but DO re-send every already-spawned player to the
	# newcomer. The spawner's late-joiner catch-up only covers peers
	# that connect while the spawner is in the tree; our client
	# connected while the host was still in the menu, so without this
	# the host's own player never appears on the client.
	if multiplayer.is_server():
		_send_all_players_to(id)


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if multiplayer.is_server():
		_spawned.erase(id)
		_spawn_data.erase(id) # v3.2 QA-047: the list must forget them too
		_round_wins.erase(id)
		clear_kill_credit(id) # QA-031: a gone victim holds no lock
		if shooting_sync != null:
			shooting_sync.reset_peer(id)
		var node := players_node.get_node_or_null(str(id))
		if node != null:
			node.queue_free()
		# v3.2 QA-047: tell every remaining client directly (same
		# reason as the explicit spawn: do not rely on the spawner
		# alone for membership changes).
		if multiplayer.get_peers().size() > 0:
			rpc("despawn_player_remote", id)
		# v2.4: a disconnect mid-match can end a Survival round or a
		# Last Man Standing match — re-check immediately.
		if game_mode == 2:
			_check_round_end()
		elif game_mode == 3:
			_check_match_end()


func _on_server_disconnected() -> void:
	if match_over:
		return
	# Remember where we were, so the main menu can offer a reconnect.
	GameData.last_host_ip = GameData.host_ip
	_show_error("The host left the game.")


# v2.5: dark outline for HUD text so it stays readable over bright
# map skies (Desert, Pirate) as well as dark ones (Catacombs, Space).
func _outline_label(l: Label) -> void:
	# v3.2 NEON ARENA: HUD numbers in Rajdhani Bold ice, with a dark
	# outline so they stay readable over bright and dark maps alike.
	l.add_theme_font_override("font", FONT_BODY_BOLD)
	l.add_theme_color_override("font_color", UI_FONT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)

	# QA-057: the top bar is three anchored sections, not one HBox —
	# the right side is a real panel (its content is ~230 px tall,
	# far taller than a 52 px bar), and the timer must stay centred
	# on the screen, not centred in the space left over by the sides.
	var left := VBoxContainer.new()
	left.set_anchors_preset(Control.PRESET_TOP_LEFT)
	left.offset_left = 16
	left.offset_top = 12
	left.offset_right = 296
	left.offset_bottom = 72
	left.add_theme_constant_override("separation", 6)
	hud.add_child(left)

	# v3.2: health and jetpack fuel as gohud GoBars — the bar shows
	# its own label + number (readout VALUE, set explicitly so the
	# demo's "1 / 1" fraction can never appear), and the value is
	# set instantly (ease_seconds 0) so hits read at a glance.
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	left.add_child(hp_row)

	hp_bar = GoBar.new()
	hp_bar.label_text = "HP"
	hp_bar.readout = GoBar.Readout.VALUE
	hp_bar.thickness = 26
	hp_bar.ease_seconds = 0.0
	hp_bar.segments = 0
	hp_bar.label_size = 16
	hp_bar.ink = UI_SUCCESS
	hp_bar.custom_minimum_size = Vector2(220, 26)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.set_values(100, 100, false)
	hp_row.add_child(hp_bar)

	var fuel_row := HBoxContainer.new()
	fuel_row.add_theme_constant_override("separation", 8)
	left.add_child(fuel_row)

	fuel_bar = GoBar.new()
	fuel_bar.label_text = "FUEL"
	fuel_bar.readout = GoBar.Readout.VALUE
	fuel_bar.thickness = 18
	fuel_bar.ease_seconds = 0.0
	fuel_bar.segments = 0
	fuel_bar.label_size = 14
	fuel_bar.ink = UI_ACCENT
	fuel_bar.custom_minimum_size = Vector2(220, 18)
	fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_bar.set_values(100, 100, false)
	fuel_row.add_child(fuel_bar)

	var mid := VBoxContainer.new()
	mid.set_anchors_preset(Control.PRESET_CENTER_TOP)
	mid.offset_left = -200
	mid.offset_right = 200
	mid.offset_top = 12
	mid.offset_bottom = 120
	hud.add_child(mid)
	timer_label = Label.new()
	timer_label.text = "5:00"
	timer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	timer_label.add_theme_font_size_override("font_size", 32)
	_outline_label(timer_label)
	mid.add_child(timer_label)
	score_label = Label.new()
	score_label.text = ""
	score_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_label.add_theme_font_size_override("font_size", 20)
	_outline_label(score_label)
	mid.add_child(score_label)
	# Phase 5 — visible centre-weapon timer (pinned Sniper/Rocket).
	_centre_label = Label.new()
	_centre_label.text = ""
	_centre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centre_label.add_theme_font_size_override("font_size", 16)
	_outline_label(_centre_label)
	mid.add_child(_centre_label)

	# QA-057 — TOP-RIGHT MENU CARD: SCORE + pause buttons and the
	# match stats (Kills / Deaths / Players / weapon + ammo /
	# Grenades) in one designed Neon Arena panel — navy scrim with
	# the gohud cut-corner border, buttons on top, stats below.
	# Readable over every map (the panel's own fill, not bare text
	# on the sky). Bottom ~y280: clear of the RELOAD/GRENADE/WEAPON
	# column (y380+) and the aim stick (y480+); the centred message
	# label (y116) and kill feed (top-left) never reach this corner.
	var topright_panel := PanelContainer.new()
	topright_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	topright_panel.offset_left = -300
	topright_panel.offset_right = -16
	topright_panel.offset_top = 12
	topright_panel.offset_bottom = 280
	topright_panel.theme = GoUi.theme()
	var top_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if top_sb != null:
		var top_dup := top_sb.duplicate()
		if top_dup is GoStyleBoxCut:
			(top_dup as GoStyleBoxCut).bg_color = Color(0.03, 0.07, 0.13, 0.92)
			(top_dup as GoStyleBoxCut).content_margin_left = 16
			(top_dup as GoStyleBoxCut).content_margin_right = 16
			(top_dup as GoStyleBoxCut).content_margin_top = 12
			(top_dup as GoStyleBoxCut).content_margin_bottom = 12
		topright_panel.add_theme_stylebox_override("panel", top_dup)
	hud.add_child(topright_panel)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	topright_panel.add_child(right)

	# Button row: SCORE + pause land here from _build_touch_controls.
	_topright_btn_row = HBoxContainer.new()
	_topright_btn_row.alignment = BoxContainer.ALIGNMENT_END
	_topright_btn_row.add_theme_constant_override("separation", 8)
	right.add_child(_topright_btn_row)
	var top_sep := HSeparator.new()
	right.add_child(top_sep)

	kills_label = Label.new()
	kills_label.text = "Kills: 0"
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kills_label.add_theme_font_size_override("font_size", 24)
	_outline_label(kills_label)
	right.add_child(kills_label)

	deaths_label = Label.new()
	deaths_label.text = "Deaths: 0"
	deaths_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	deaths_label.add_theme_font_size_override("font_size", 18)
	_outline_label(deaths_label)
	right.add_child(deaths_label)

	players_label = Label.new()
	players_label.text = "Players: 1/%d" % max_players # v3.4: room max, not the 12-player cap — the HUD must agree with the lobby ("1/4" in a 4-player room, "2/8" in the default 8-player room)
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	players_label.add_theme_font_size_override("font_size", 20)
	_outline_label(players_label)
	right.add_child(players_label)

	var weapon_row := HBoxContainer.new()
	weapon_row.alignment = BoxContainer.ALIGNMENT_END
	weapon_row.add_theme_constant_override("separation", 8)
	right.add_child(weapon_row)
	weapon_icon = TextureRect.new()
	weapon_icon.custom_minimum_size = Vector2(64, 24)
	weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	weapon_row.add_child(weapon_icon)
	weapon_label = Label.new()
	weapon_label.text = "Rifle 30"
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.add_theme_font_size_override("font_size", 24)
	_outline_label(weapon_label)
	weapon_row.add_child(weapon_label)

	grenade_label = Label.new()
	grenade_label.text = "Grenades: 2"
	grenade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grenade_label.add_theme_font_size_override("font_size", 22)
	_outline_label(grenade_label)
	right.add_child(grenade_label)

	# Phase 4: FPS counter (settings toggle, off by default).
	fps_label = Label.new()
	fps_label.text = "FPS: --"
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 18)
	_outline_label(fps_label)
	fps_label.visible = GameData.show_fps
	right.add_child(fps_label)

	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# QA-034: offset_top was 96 — the centre-weapon label (3rd row
	# of the top bar, bottom ~y108) overlapped the 24 px message
	# ("Waiting for other players...") on every solo match start.
	# 116 clears it with room to spare; the kill feed lives at the
	# top-left, so the centred message never collides with it.
	message_label.offset_top = 116
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 24)
	_outline_label(message_label)
	hud.add_child(message_label)

	host_ip_label = Label.new()
	host_ip_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Bottom-anchored labels need BOTH offsets: offset_bottom alone
	# leaves a negative-height rect and the text draws off-screen
	# (the v3.2 HUD shot proved the hint was invisible this way).
	host_ip_label.offset_top = -32
	host_ip_label.offset_bottom = -8
	host_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_ip_label.add_theme_font_size_override("font_size", 20)
	_outline_label(host_ip_label)
	host_ip_label.visible = false
	hud.add_child(host_ip_label)

	# v3.2 controls: left stick moves (push up = jump/fly), right
	# stick aims and shoots. Say so for the first seconds.
	hint_label = Label.new()
	hint_label.text = "Left stick: move  •  Push up: jump / fly  •  Right stick: aim and shoot"
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# Both offsets (see host_ip_label above): offset_bottom alone
	# gives a negative-height rect and the text draws off-screen.
	hint_label.offset_top = -64
	hint_label.offset_bottom = -40
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_override("font", FONT_BODY_MEDIUM)
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(hint_label)

	# Phase 4 — kill feed: top-left, under the HP/fuel bars, newest
	# on top, 4 lines max, each line fades after 5 s.
	_kill_feed_list = VBoxContainer.new()
	_kill_feed_list.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_kill_feed_list.position = Vector2(16, 108)
	_kill_feed_list.add_theme_constant_override("separation", 2)
	hud.add_child(_kill_feed_list)

	# Phase 4 — match countdown: huge centre number, with the match
	# goal ("First to 10 kills") under it.
	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_label.position = Vector2(-80, -140)
	_countdown_label.size = Vector2(160, 140)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.add_theme_font_size_override("font_size", 96)
	_outline_label(_countdown_label)
	_countdown_label.visible = false
	hud.add_child(_countdown_label)
	_countdown_sub = Label.new()
	_countdown_sub.set_anchors_preset(Control.PRESET_CENTER)
	_countdown_sub.position = Vector2(-300, 10)
	_countdown_sub.size = Vector2(600, 40)
	_countdown_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_sub.add_theme_font_size_override("font_size", 26)
	_outline_label(_countdown_sub)
	_countdown_sub.visible = false
	hud.add_child(_countdown_sub)

	# Phase 4 — hitmarker: a cross at screen centre, shown briefly
	# on every confirmed hit (red when the hit was lethal).
	_hitmarker_label = Label.new()
	_hitmarker_label.text = "✕"
	_hitmarker_label.set_anchors_preset(Control.PRESET_CENTER)
	_hitmarker_label.position = Vector2(-30, -30)
	_hitmarker_label.size = Vector2(60, 60)
	_hitmarker_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hitmarker_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_hitmarker_label.add_theme_font_size_override("font_size", 44)
	_hitmarker_label.add_theme_color_override("font_color", Color(1, 1, 1))
	_outline_label(_hitmarker_label)
	_hitmarker_label.visible = false
	hud.add_child(_hitmarker_label)

	# Phase 4 — spectator mode (Survival/LMS): label + NEXT button,
	# only visible while spectating a living player.
	_spectate_label = Label.new()
	_spectate_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_spectate_label.offset_top = 140
	_spectate_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_spectate_label.add_theme_font_size_override("font_size", 24)
	_outline_label(_spectate_label)
	_spectate_label.visible = false
	hud.add_child(_spectate_label)
	_spectate_next_btn = Button.new()
	_spectate_next_btn.text = "NEXT PLAYER >"
	_style_hud_button(_spectate_next_btn)
	_spectate_next_btn.custom_minimum_size = Vector2(200, 56)
	_spectate_next_btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_spectate_next_btn.position = Vector2(-100, -90)
	_spectate_next_btn.visible = false
	_spectate_next_btn.pressed.connect(_on_spectate_next_pressed)
	hud.add_child(_spectate_next_btn)

	_build_scoreboard()
	_build_pause_menu()
	_build_end_screen()
	_build_error_panel()
	_build_weapon_panel()


# v2.3: dialogs are centred by a full-rect CenterContainer, not by manual
# offsets. The menu lobby had the same PRESET_CENTER pattern and it broke:
# a panel sized from a transiently wrong minimum (2877 px) was centred for
# that height and never shrank back, so every button sat off-screen. A
# CenterContainer centres from the live minimum size every frame, so the
# bug cannot recur. The wrapper ignores mouse input; the panel itself
# still receives clicks for its buttons.
func _dialog_wrap() -> CenterContainer:
	var w := CenterContainer.new()
	w.set_anchors_preset(Control.PRESET_FULL_RECT)
	w.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(w)
	return w


func _cut_accent_stylebox() -> GoStyleBoxCut:
	var sb := GoStyleBoxCut.new()
	sb.bg_color = UI_ACCENT
	sb.border_color = UI_ACCENT
	sb.border_width = 1.0
	sb.cut = 10.2
	sb.cut_corners = GoStyleBoxCut.ALL
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	return sb


func _panel_style() -> StyleBox:
	# v3.2 NEON ARENA: the dialog panel comes from the gohud theme
	# (cut corners, navy fill, steel border), duplicated so the
	# 0.92 alpha + content margins don't mutate the shared theme.
	var base := GoUi.theme().get_stylebox("panel", "PanelContainer")
	var s := base.duplicate() as StyleBox
	if s is StyleBoxFlat:
		var f := s as StyleBoxFlat
		var c := f.bg_color
		c.a = 0.92
		f.bg_color = c
		f.content_margin_left = 18
		f.content_margin_right = 18
		f.content_margin_top = 14
		f.content_margin_bottom = 14
	return s


# v3.2 NEON ARENA HUD/dialog button: the gohud theme drives the look
# (cut corners, navy fill, steel border, ice text); accent buttons
# (Resume, Rematch, Retry, Close) get the cyan fill + dark text.
# No manual green styleboxes any more — the old v3.1 green is gone.
func _style_hud_button(b: Button, accent: bool = false) -> void:
	for kind in ["normal", "hover", "pressed", "disabled"]:
		b.remove_theme_stylebox_override(kind)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", UI_FONT)
	b.add_theme_color_override("font_hover_color", UI_FONT)
	b.add_theme_color_override("font_pressed_color", UI_ACCENT)
	if accent:
		var sb := _cut_accent_stylebox()
		b.add_theme_stylebox_override("normal", sb)
		b.add_theme_stylebox_override("hover", sb)
		b.add_theme_color_override("font_color", UI_ACCENT_DARK)
		b.add_theme_color_override("font_hover_color", UI_ACCENT_DARK)
		b.add_theme_color_override("font_pressed_color", UI_ACCENT_DARK)


func _build_scoreboard() -> void:
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.theme = GoUi.theme()
	scoreboard_panel.custom_minimum_size = Vector2(420, 0)
	scoreboard_panel.add_theme_stylebox_override("panel", _panel_style())
	scoreboard_panel.visible = false
	_dialog_wrap().add_child(scoreboard_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	scoreboard_panel.add_child(box)
	var title := Label.new()
	title.text = "SCOREBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UI_FONT)
	box.add_child(title)
	scoreboard_list = VBoxContainer.new()
	scoreboard_list.add_theme_constant_override("separation", 4)
	box.add_child(scoreboard_list)
	var close_btn := Button.new()
	close_btn.text = "Close"
	_style_hud_button(close_btn)
	close_btn.pressed.connect(func() -> void: scoreboard_panel.visible = false)
	box.add_child(close_btn)


func _build_pause_menu() -> void:
	pause_panel = PanelContainer.new()
	pause_panel.theme = GoUi.theme()
	pause_panel.custom_minimum_size = Vector2(420, 0)
	pause_panel.add_theme_stylebox_override("panel", _panel_style())
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_dialog_wrap().add_child(pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	pause_panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UI_FONT)
	box.add_child(title)
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	_style_hud_button(resume_btn, true)
	resume_btn.custom_minimum_size = Vector2(0, 52)
	resume_btn.pressed.connect(_toggle_pause)
	box.add_child(resume_btn)
	# Phase 4: weapon info — damage / fire rate / magazine / reload
	# per weapon, straight from weapons.gd (read-only display).
	var weapons_btn := Button.new()
	weapons_btn.text = "Weapons"
	_style_hud_button(weapons_btn)
	weapons_btn.custom_minimum_size = Vector2(0, 52)
	weapons_btn.pressed.connect(func() -> void: _show_weapon_panel(true))
	box.add_child(weapons_btn)
	var sfx_row := HBoxContainer.new()
	box.add_child(sfx_row)
	var sfx_lbl := Label.new()
	sfx_lbl.text = "Sound"
	sfx_row.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = GameData.sfx_volume
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_row.add_child(sfx_slider)
	var mus_row := HBoxContainer.new()
	box.add_child(mus_row)
	var mus_lbl := Label.new()
	mus_lbl.text = "Music"
	mus_row.add_child(mus_lbl)
	var mus_slider := HSlider.new()
	mus_slider.min_value = 0.0
	mus_slider.max_value = 1.0
	mus_slider.step = 0.05
	mus_slider.value = GameData.music_volume
	mus_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mus_slider.value_changed.connect(_on_music_volume_changed)
	mus_row.add_child(mus_slider)
	var leave_btn := Button.new()
	leave_btn.text = "Leave Match"
	_style_hud_button(leave_btn)
	leave_btn.custom_minimum_size = Vector2(0, 52)
	leave_btn.pressed.connect(_on_leave_pressed)
	box.add_child(leave_btn)


func _build_end_screen() -> void:
	end_panel = PanelContainer.new()
	end_panel.theme = GoUi.theme()
	end_panel.custom_minimum_size = Vector2(480, 0)
	end_panel.add_theme_stylebox_override("panel", _panel_style())
	end_panel.visible = false
	_dialog_wrap().add_child(end_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	end_panel.add_child(box)
	_end_box = box
	end_title = Label.new()
	end_title.text = ""
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_override("font", FONT_TITLE)
	end_title.add_theme_font_size_override("font_size", 30)
	end_title.add_theme_color_override("font_color", UI_FONT)
	box.add_child(end_title)
	end_list = VBoxContainer.new()
	end_list.add_theme_constant_override("separation", 4)
	box.add_child(end_list)
	end_rematch_btn = Button.new()
	end_rematch_btn.text = "Rematch"
	_style_hud_button(end_rematch_btn, true)
	end_rematch_btn.custom_minimum_size = Vector2(0, 56)
	end_rematch_btn.pressed.connect(_on_rematch_pressed)
	box.add_child(end_rematch_btn)
	var back_btn := Button.new()
	back_btn.text = "Back to Lobby"
	_style_hud_button(back_btn)
	back_btn.custom_minimum_size = Vector2(0, 56)
	back_btn.pressed.connect(_on_leave_pressed)
	box.add_child(back_btn)


func _build_weapon_panel() -> void:
	_weapon_panel = PanelContainer.new()
	_weapon_panel.theme = GoUi.theme()
	_weapon_panel.custom_minimum_size = Vector2(520, 0)
	_weapon_panel.add_theme_stylebox_override("panel", _panel_style())
	_weapon_panel.visible = false
	_weapon_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_dialog_wrap().add_child(_weapon_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	_weapon_panel.add_child(box)
	var title := Label.new()
	title.text = "WEAPONS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", UI_FONT)
	box.add_child(title)
	var hint := Label.new()
	hint.text = "Damage is per hit. Rate is shots per second. Pick up weapons on the map — the pistol is your starting sidearm."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
	box.add_child(hint)
	_weapon_list = VBoxContainer.new()
	_weapon_list.add_theme_constant_override("separation", 4)
	box.add_child(_weapon_list)
	for id in WeaponData.TABLE.keys():
		var w: Dictionary = WeaponData.TABLE[id]
		var rate: float = 1.0 / float(w["rate"]) if float(w["rate"]) > 0.0 else 0.0
		var lbl := Label.new()
		lbl.text = "%s — DMG %d  •  %.1f/s  •  Mag %d  •  Reload %.1fs%s%s" % [
			String(w["name"]), int(w["damage"]), rate, int(w["mag"]),
			float(w["reload"]),
			"  •  Auto" if bool(w["auto"]) else "  •  Tap to fire",
			"  •  Explosive" if bool(w["explosive"]) else "",
		]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_weapon_list.add_child(lbl)
	var close_btn := Button.new()
	close_btn.text = "Close"
	_style_hud_button(close_btn, true)
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.pressed.connect(func() -> void: _show_weapon_panel(false))
	box.add_child(close_btn)


func _show_weapon_panel(show: bool) -> void:
	_weapon_panel.visible = show
	# The pause menu stays behind it; closing returns to pause.


func _build_error_panel() -> void:
	error_panel = PanelContainer.new()
	error_panel.theme = GoUi.theme()
	error_panel.custom_minimum_size = Vector2(520, 0)
	error_panel.add_theme_stylebox_override("panel", _panel_style())
	error_panel.visible = false
	_dialog_wrap().add_child(error_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	error_panel.add_child(box)
	error_label = Label.new()
	error_label.text = ""
	error_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	error_label.add_theme_font_override("font", FONT_BODY_MEDIUM)
	error_label.add_theme_font_size_override("font_size", 22)
	error_label.add_theme_color_override("font_color", UI_FONT)
	box.add_child(error_label)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var retry_btn := Button.new()
	retry_btn.text = "Retry"
	_style_hud_button(retry_btn, true)
	retry_btn.custom_minimum_size = Vector2(0, 56)
	retry_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	retry_btn.pressed.connect(_on_retry_pressed)
	row.add_child(retry_btn)
	var back_btn := Button.new()
	back_btn.text = "Back"
	_style_hud_button(back_btn)
	back_btn.custom_minimum_size = Vector2(0, 56)
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back_btn.pressed.connect(_on_leave_pressed)
	row.add_child(back_btn)


@rpc("any_peer")
func version_mismatch_remote(text: String) -> void:
	_show_error(text)


func _show_error(text: String) -> void:
	_join_failed = true
	error_label.text = text
	error_panel.visible = true
	audio.play("death")


func _on_retry_pressed() -> void:
	error_panel.visible = false
	_join_failed = false
	_join_timer = 0.0
	_spawn_retry_timer = 0.0
	# v3.2 QA-047: Retry re-attempts the whole join, not just the spawn
	# request. If the ENet link is still up, re-request spawn + player
	# list. If the link itself is gone, go back to the menu with the
	# host IP prefilled so the user can rejoin in one tap — a dropped
	# client cannot rejoin a running match from here, because the
	# host's lobby is gone once the match started.
	var peer = multiplayer.multiplayer_peer
	var connected := peer is ENetMultiplayerPeer and (peer as ENetMultiplayerPeer).get_connection_status() == MultiplayerPeer.CONNECTION_CONNECTED
	if connected:
		_ready_announced = false
		_announce_ready()
	else:
		GameData.last_host_ip = GameData.host_ip
		_on_leave_pressed()


func _on_leave_pressed() -> void:
	# The scene change is deferred to the end of the frame, but this
	# node's _process would still run once more with `multiplayer`
	# already torn down (script errors in the update tail). Stop it.
	_leaving = true
	get_tree().paused = false
	# Phase 6: stop the battle track here — the menu scene starts its
	# own menu track on load, so music never overlaps or keeps playing
	# after leaving a match.
	if audio != null:
		audio.stop_music()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file("res://main.tscn")


func _on_rematch_pressed() -> void:
	if multiplayer.is_server():
		rpc("rematch_remote")


@rpc("any_peer", "call_local")
func rematch_remote() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func _on_sfx_volume_changed(v: float) -> void:
	GameData.sfx_volume = v
	GameData.save_settings()
	if audio != null:
		audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _on_music_volume_changed(v: float) -> void:
	GameData.music_volume = v
	GameData.save_settings()
	if audio != null:
		audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _toggle_pause() -> void:
	if match_over:
		return
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	if get_tree().paused:
		# A finger held on the aim stick while pausing must not resume firing
		# on unpause from a stale touch (QA-016 rule).
		_reset_all_touch_state()
	# QA-035: the touch controls stay on top of the pause panel
	# otherwise (same overlap as the end screen) — hide while
	# paused, restore on resume.
	_set_touch_controls_visible(not get_tree().paused)


func _build_touch_controls() -> void:
	# v3.2 (CONTROLS_CHANGE.md): fixed layout, no left-handed mirror
	# any more — the FIRE button it mirrored with is gone. Move stick
	# bottom-left, aim stick bottom-right, RELOAD / GRENADE / WEAPON
	# column above the aim stick on the right.
	# v3.3 QA-052: sticks moved inward from the bottom corners —
	# move stick up/right, aim stick up/left, 50 px each way at
	# 1280x720 (anchor offsets, so it scales with the stretch).
	# Was move (40, -190), aim (-290, -190). Aim stick still clears
	# the RELOAD/GRENADE/WEAPON column (x 810-920) by 20 px.
	move_stick = JOYSTICK_SCRIPT.new()
	move_stick.name = "MoveStick"
	move_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	move_stick.position = Vector2(90, -240)
	move_stick.size = Vector2(150, 150)
	hud.add_child(move_stick)

	# v3.2: the aim stick is back at the bottom-right (it moved left in
	# v2.4 to make room for the FIRE button) — and it is also the fire
	# control now: pushing it aims and shoots (Mini Militia style).
	# is_aim draws the cyan ring + crosshair cue (joystick.gd).
	aim_stick = JOYSTICK_SCRIPT.new()
	aim_stick.name = "AimStick"
	aim_stick.is_aim = true
	aim_stick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	aim_stick.position = Vector2(-340, -240)
	aim_stick.size = Vector2(150, 150)
	hud.add_child(aim_stick)

	# v2.2: no JUMP button. Pushing the left stick up jumps; holding it up
	# while airborne is the jetpack (see player.gd). The hint label in the
	# HUD and the lobby explain the new control.
	grenade_button = Button.new()
	grenade_button.text = "GRENADE"
	_style_hud_button(grenade_button)
	grenade_button.custom_minimum_size = Vector2(110, 60)
	grenade_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grenade_button.position = Vector2(-470, -260)
	grenade_button.pressed.connect(_on_grenade_pressed)
	hud.add_child(grenade_button)

	switch_button = Button.new()
	switch_button.text = "WEAPON"
	_style_hud_button(switch_button)
	switch_button.custom_minimum_size = Vector2(110, 60)
	switch_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	switch_button.position = Vector2(-470, -180)
	switch_button.pressed.connect(_on_switch_pressed)
	hud.add_child(switch_button)

	# v2.4 RELOAD button: dedicated, above GRENADE in the same column.
	reload_button = Button.new()
	reload_button.text = "RELOAD"
	_style_hud_button(reload_button)
	reload_button.custom_minimum_size = Vector2(110, 60)
	reload_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	reload_button.position = Vector2(-470, -340)
	reload_button.pressed.connect(_on_reload_pressed)
	hud.add_child(reload_button)

	# QA-057: the buttons live in the top-right panel's button row
	# (created in _build_hud), not floating at y196 — 56 px targets
	# inside the designed card, beside the stats they control.
	# SCORE first, pause second (left to right, as before).
	score_button = Button.new()
	score_button.text = "SCORE"
	_style_hud_button(score_button)
	score_button.custom_minimum_size = Vector2(96, 56)
	score_button.pressed.connect(_on_score_pressed)
	_topright_btn_row.add_child(score_button)

	pause_button = Button.new()
	pause_button.text = "II"
	_style_hud_button(pause_button)
	pause_button.custom_minimum_size = Vector2(56, 56)
	pause_button.pressed.connect(_toggle_pause)
	_topright_btn_row.add_child(pause_button)


func _on_reload_pressed() -> void:
	var lp = _get_local_player()
	if lp != null:
		lp.start_reload()


func _on_score_pressed() -> void:
	_update_scoreboard_rows(scoreboard_list)
	scoreboard_panel.visible = not scoreboard_panel.visible
	# QA-035: same as pause/end — the sticks and buttons draw over
	# the scoreboard while it is open. Reset any held touch first so
	# a hidden aim stick cannot keep firing (QA-016 rule).
	if scoreboard_panel.visible:
		_reset_all_touch_state()
	_set_touch_controls_visible(not scoreboard_panel.visible)

func _on_grenade_pressed() -> void:
	var lp = _get_local_player()
	if lp != null:
		lp.throw_grenade()


func _on_switch_pressed() -> void:
	var lp = _get_local_player()
	if lp != null:
		lp.switch_weapon()


# v2.4 (QA-023): game touches go through _unhandled_input, NOT
# _input. GUI Buttons (GRENADE / WEAPON / RELOAD / pause / score, and
# the pause/scoreboard/end panels) consume their touches first, so a
# tap on one of them can never reach the sticks — the old _input path
# grabbed every touch before the GUI saw it, and the only protection
# was a rect check that compared the event's viewport-pixel position
# against canvas-space button rects (wrong under stretch mode), so a
# GRENADE/WEAPON tap fell through to the aim stick and the gun fired.
# The rect checks below are only a belt-and-braces fallback, and they
# compare in canvas space (see _to_canvas_pos).
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		# Touch events arrive in viewport-pixel coordinates; the HUD
		# rects are in canvas (logical) coordinates. Convert once,
		# here, at the boundary — everything downstream is canvas.
		var cpos := _to_canvas_pos(e.position)
		if e.pressed:
			_on_touch_press(e.index, cpos)
		else:
			_on_touch_release(e.index)
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		_on_touch_drag(e.index, _to_canvas_pos(e.position))
	elif event is InputEventKey:
		var k := event as InputEventKey
		if k.pressed and not k.echo and k.keycode == KEY_ESCAPE:
			_toggle_pause()


# QA-029: the viewport's canvas transform carries the CAMERA offset
# (the camera follows the player, so its origin is far from (0,0) once
# the player leaves the spawn), but the HUD CanvasLayer does NOT follow
# the camera. Converting a touch with get_canvas_transform() therefore
# shifted every touch by the camera displacement — a touch on a stick's
# exact centre landed ~680 px below it, so the knob slammed to the
# bottom and the vector pointed straight down on every touch, at every
# resolution (even 1280x720, scale 1). The HUD layer's own transform
# is the correct converter for HUD touches: it has no camera term.
func _to_canvas_pos(viewport_pos: Vector2) -> Vector2:
	return hud.get_final_transform().affine_inverse() * viewport_pos


# Canvas position -> viewport position (for tests that simulate a real
# touch at a control's on-screen location). Inverse of _to_canvas_pos.
func _to_viewport_pos(canvas_pos: Vector2) -> Vector2:
	return hud.get_final_transform() * canvas_pos


# True when a viewport point is on any HUD control. Uses each control's
# own global transform with canvas (the ground truth for its on-screen
# position), never a shared rect in a possibly different space.
# Used by the player's mouse fallback (desktop testing) and by the
# touch router.
func is_hud_control_pos(viewport_pos: Vector2) -> bool:
	for c in [grenade_button, switch_button, reload_button, pause_button, score_button]:
		if c == null:
			continue
		var ctrl := c as Control
		var local := ctrl.get_global_transform_with_canvas().affine_inverse() * viewport_pos
		if Rect2(Vector2.ZERO, ctrl.size).has_point(local):
			return true
	return false


func _notification(what: int) -> void:
	# QA-016: a touch interrupted by the OS (app switch, notification
	# shade, incoming call, gesture cancel) never delivers a release
	# event. If we did nothing, the last stick vector would stay live
	# forever and the gun would keep firing. Reset all touch state here.
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT or what == NOTIFICATION_APPLICATION_PAUSED:
		_reset_all_touch_state()


func _reset_all_touch_state() -> void:
	_move_touch_id = -1
	_aim_touch_id = -1
	_last_touch_msec = Time.get_ticks_msec()
	if move_stick != null:
		move_stick.reset_input()
	if aim_stick != null:
		aim_stick.reset_input()
	touch_move_vec = Vector2.ZERO
	touch_aim = Vector2.ZERO
	touch_aim_active = false
	touch_firing = false
	_aim_fire_pending = false
	_aim_vec_prev_nonzero = false


# QA-054: true while a stick is held, or within 500 ms of the last
# touch press/release. The player's mouse-aim fallback consults this
# so a touch can never be mistaken for a mouse click.
func touch_recently_used() -> bool:
	if _move_touch_id != -1 or _aim_touch_id != -1:
		return true
	return Time.get_ticks_msec() - _last_touch_msec < 500


# QA-035: hide/show the gameplay touch cluster (sticks,
# RELOAD / GRENADE / WEAPON) when a full-screen panel opens (pause,
# scoreboard, end screen) so the controls cannot draw over the
# panel's text and buttons. The top-right SCORE / pause buttons stay
# visible — they sit outside the centred panels. Callers reset the
# touch state first (see _reset_all_touch_state) so a hidden stick
# cannot keep firing. Rematch reloads the scene, so there is
# no end-screen restore path to maintain.
func _set_touch_controls_visible(v: bool) -> void:
	for c in [move_stick, aim_stick, reload_button, grenade_button, switch_button]:
		if c != null:
			c.visible = v


func _on_touch_press(index: int, pos: Vector2) -> void:
	# All positions here are canvas space (converted in _unhandled_input).
	# Order matters — check the controls first, sticks last:
	# 1. GUI buttons (belt-and-braces: _unhandled_input means the GUI
	#    already declined them, but a stray touch must never reach a
	#    stick — return without routing).
	# 2. Sticks by screen half (move left, aim right).
	_last_touch_msec = Time.get_ticks_msec() # QA-054: mouse-aim latch
	if is_hud_control_pos(pos):
		return
	var vp := get_viewport().get_visible_rect().size
	if pos.x < vp.x * 0.5:
		# press_touch() refuses if the stick already has a finger, so a
		# second finger can never hijack the move stick.
		if move_stick.press_touch(index, pos):
			_move_touch_id = index
	else:
		if aim_stick.press_touch(index, pos):
			_aim_touch_id = index
			# v3.2: a press that lands already deflected past the dead
			# zone arms the semi-auto shot NOW (synchronously) — a
			# flick pressed and released between two _process frames
			# would otherwise never be seen by _update_touch_state
			# and the shot would be lost (QA-027 carry-over).
			if aim_stick.get_vector() != Vector2.ZERO:
				_aim_fire_pending = true
				_aim_vec_prev_nonzero = true


func _on_touch_drag(index: int, pos: Vector2) -> void:
	if index == _move_touch_id:
		move_stick.drag_touch(index, pos)
	elif index == _aim_touch_id:
		aim_stick.drag_touch(index, pos)


func _on_touch_release(index: int) -> void:
	_last_touch_msec = Time.get_ticks_msec() # QA-054: mouse-aim latch
	if index == _move_touch_id:
		_move_touch_id = -1
		move_stick.release_touch(index)
	elif index == _aim_touch_id:
		_aim_touch_id = -1
		aim_stick.release_touch(index)


func _process(delta: float) -> void:
	if _leaving:
		return
	if _join_test_host or _join_test_client:
		_update_jointest(delta)
		if _join_test_done:
			return
	if _repl_sim_test:
		_update_replsimtest(delta)
		if _repl_sim_done:
			return
	if get_tree().paused:
		# Touch state must not stay stale while paused: zero it so the
		# player cannot resume firing from a finger lifted mid-pause.
		_update_touch_state()
		# The joystick test must still advance while paused (its pause
		# test waits on this timer).
		if _joystick_test:
			_update_joytest(delta)
		if _flow_test:
			_update_flowtest(delta)
		if _game_shots:
			_update_gameshots(delta)
		return
	if _smoke_test:
		_update_smoke_test(delta)
	elif _joystick_test:
		_update_touch_state()
		_update_joytest(delta)
	elif _fire_test:
		_update_touch_state()
		_update_firetest(delta)
	elif _net_test:
		_update_touch_state()
		_update_nettest(delta)
	elif _flow_test:
		_update_touch_state()
		_update_flowtest(delta)
	elif _scale_test:
		_update_touch_state()
		_update_scaletest(delta)
	elif _collision_test:
		_update_touch_state()
		_update_collisiontest(delta)
	elif _physics_test:
		_update_touch_state()
		_update_physicstest(delta)
	elif _perf_test:
		_update_touch_state()
		_update_perftest(delta)
	elif _features_test:
		_update_touch_state()
		_update_featurestest(delta)
	elif _game_shots:
		_update_touch_state()
		_update_gameshots(delta)
	else:
		_update_touch_state()
	# The flow test (or a button) may have started leaving mid-frame.
	if _leaving:
		return
	_update_countdown(delta)
	_update_kill_feed(delta)
	_update_hitmarker(delta)
	_update_death_watcher()
	_update_spectator(delta)
	_update_hud(delta)
	_update_broadcast(delta)
	_update_pickup_spawn(delta)
	_update_join_timeout(delta)
	_retry_spawn_if_needed(delta)
	_update_match_timer(delta)
	_update_lava(delta)


func _update_touch_state() -> void:
	if get_tree().paused:
		touch_move_vec = Vector2.ZERO
		touch_aim = Vector2.ZERO
		touch_aim_active = false
		touch_firing = false
		_aim_fire_pending = false
		_aim_vec_prev_nonzero = false
		return
	# v3.2 (CONTROLS_CHANGE.md §2): get_vector() is zero unless the
	# stick has an actively held touch, and firing is true ONLY while
	# the AIM stick is deflected past its 0.20 dead zone — never from
	# a stale knob position or any other control.
	touch_move_vec = move_stick.get_vector()
	var aim_vec = aim_stick.get_vector()
	# Phase 4: invert aim (settings) flips the aim stick vertically.
	if GameData.invert_aim:
		aim_vec.y = -aim_vec.y
	touch_aim = aim_vec
	# GAP-09: the dead zone is applied once, in joystick.gd (0.20).
	# Any non-zero aim vector counts as aiming here.
	touch_aim_active = aim_vec.length() > 0.0
	# Semi-auto edge (QA-027 carry-over): a fresh ZERO -> non-zero
	# transition arms one pending shot, so a quick flick fires even if
	# the finger is gone by the time the shooting step runs. Holding a
	# semi-auto weapon deflected does NOT re-arm (no auto-repeat).
	var aim_now: bool = aim_vec != Vector2.ZERO
	if aim_now and not _aim_vec_prev_nonzero:
		_aim_fire_pending = true
	_aim_vec_prev_nonzero = aim_now
	touch_firing = aim_now
	# Phase 4: during the match countdown nobody moves, aims or fires
	# — the fight starts on "FIGHT!".
	if _countdown_active:
		touch_move_vec = Vector2.ZERO
		touch_aim = Vector2.ZERO
		touch_aim_active = false
		touch_firing = false
		_aim_fire_pending = false
		_aim_vec_prev_nonzero = false


# v3.2: the pending semi-auto shot (see _update_touch_state). Peeked by
# the player in _read_input, consumed when the shot fires, discarded on
# reload / respawn / weapon switch.
func has_aim_fire_edge() -> bool:
	return _aim_fire_pending


func consume_aim_fire_edge() -> void:
	_aim_fire_pending = false


func _update_hud(delta: float) -> void:
	var lp = _get_local_player()
	var count := players_node.get_child_count()
	players_label.text = "Players: %d/%d" % [count, max_players] # v3.4: room max (was MAX_PLAYERS=12, so a default 8-player room wrongly showed "2/12")
	# Timer (THEME_SPEC.md §3): ice normally, amber under 30 s,
	# danger red under 10 s.
	var t := int(maxf(0.0, _time_left))
	timer_label.text = "%d:%02d" % [t / 60, t % 60]
	timer_label.add_theme_color_override("font_color", UI_DANGER if t < 10 else (UI_WARNING if t < 30 else UI_FONT))
	if game_mode == 1:
		var red := 0
		var blue := 0
		for child in players_node.get_children():
			if child.team == 0:
				red += child.kills
			elif child.team == 1:
				blue += child.kills
		score_label.text = "RED %d  -  %d BLUE" % [red, blue]
	else:
		score_label.text = "First to %d kills" % kill_limit
	# Phase 5 — centre weapon status: "SNIPER HERE" while the pinned
	# centre pickup is live, else a countdown to the next one.
	if _centre_label != null:
		var centre_active := false
		var centre_kind := 0
		for child in pickups_node.get_children():
			if int(child.get("spot_index")) == 3:
				centre_active = true
				centre_kind = int(child.get("kind"))
		if centre_active:
			var cname := "SNIPER" if centre_kind == 3 else "ROCKET" if centre_kind == 4 else "WEAPON"
			_centre_label.text = "CENTRE: %s HERE" % cname
		else:
			var next_name := "WEAPON"
			if multiplayer.is_server():
				next_name = "SNIPER" if _centre_kind_next == 3 else "ROCKET"
			var cdown := int(ceil(maxf(0.0, float(_pickup_spot_timers.get(3, 0.0)))))
			_centre_label.text = "CENTRE: %s in %ds" % [next_name, cdown]
	# v2.2 control hint: visible until 10 s after the local player spawns.
	if hint_label != null:
		if lp != null:
			_hint_timer -= delta
		hint_label.visible = _hint_timer > 0.0
	if lp == null:
		if not _join_failed:
			message_label.text = "Connecting..." if multiplayer.is_server() == false else "Starting..."
		return
	hp_bar.set_values(lp.health, 100, false)
	fuel_bar.set_values(lp.fuel, 100, false)
	kills_label.text = "Kills: %d" % lp.kills
	deaths_label.text = "Deaths: %d" % lp.deaths
	weapon_icon.texture = WEAPON_ICONS[lp.weapon]
	var wname: String = lp.WEAPONS[lp.weapon]["name"]
	var mag_total: int = int(lp.WEAPONS[lp.weapon]["mag"])
	var res: int = lp.ammo_reserve()
	var res_txt := "∞" if res < 0 else str(res)
	if lp.reloading:
		weapon_label.text = "%s - reloading %d%%" % [wname, int(lp.reload_progress() * 100.0)]
	else:
		weapon_label.text = "%s %d/%s" % [wname, lp.mag_ammo, res_txt]
	if reload_button != null:
		reload_button.disabled = lp.reloading or lp.mag_ammo >= mag_total
		reload_button.text = "RELOADING..." if lp.reloading else "RELOAD"
	grenade_label.text = "Grenades: %d" % lp.grenades
	# Phase 4: FPS counter (settings toggle).
	if fps_label != null:
		fps_label.visible = GameData.show_fps
		if GameData.show_fps:
			fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
	# Phase 4: hitmarker — the host confirmed a hit for the local player.
	if lp._hitmark_seq != _last_hitmark_seq:
		_last_hitmark_seq = lp._hitmark_seq
		_show_hitmarker(lp._hitmark_dmg, lp._hitmark_pos, lp._hitmark_lethal)
	if match_over:
		message_label.text = ""
	elif not lp.alive:
		message_label.text = "Eliminated! Respawning..."
	elif count < 2:
		if multiplayer.is_server():
			message_label.text = "Waiting for other players - share your IP!"
		else:
			message_label.text = "Waiting for other players..."
	else:
		message_label.text = ""


func _get_local_player():
	if _local_player != null and is_instance_valid(_local_player):
		return _local_player
	for child in players_node.get_children():
		if child.get_multiplayer_authority() == multiplayer.get_unique_id():
			_local_player = child
			return child
	return null


func _update_scoreboard_rows(list: VBoxContainer) -> void:
	for c in list.get_children():
		c.queue_free()
	var rows: Array = []
	for child in players_node.get_children():
		rows.append(child)
	rows.sort_custom(func(a, b) -> bool: return a.kills > b.kills)
	# Phase 4: team totals header in Team Deathmatch.
	if game_mode == 1:
		var red := 0
		var blue := 0
		for child in players_node.get_children():
			if child.team == 0:
				red += child.kills
			elif child.team == 1:
				blue += child.kills
		var totals := Label.new()
		totals.text = "RED %d  —  %d BLUE" % [red, blue]
		totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		totals.add_theme_font_size_override("font_size", 22)
		list.add_child(totals)
	var rank := 1
	var my_id := multiplayer.get_unique_id()
	for p in rows:
		var team_txt := ""
		if p.team == 0:
			team_txt = " [RED]"
		elif p.team == 1:
			team_txt = " [BLUE]"
		var st: Dictionary = GameData.compute_stats(p.kills, p.deaths, p._shots_fired, p._shots_hit)
		var is_self := int(p.peer_id) == my_id
		var lbl := Label.new()
		lbl.text = "%s%d. %s%s  —  K %d  D %d  K/D %.2f  ACC %d%%%s" % [
			"► " if is_self else "", rank, p.player_name, team_txt,
			p.kills, p.deaths, float(st["kd"]), int(st["accuracy"]),
			"  (YOU)" if is_self else "",
		]
		lbl.add_theme_font_size_override("font_size", 20)
		# Phase 4: highlight self in white; everyone else in their colour.
		lbl.add_theme_color_override("font_color", Color(1, 1, 1) if is_self else p.player_color)
		list.add_child(lbl)
		rank += 1


func _update_host_ip_label() -> void:
	if multiplayer.is_server():
		var ip := LanDiscovery.lan_ip()
		if ip == "":
			host_ip_label.text = "You are the HOST"
		else:
			host_ip_label.text = "You are the HOST. Your IP: " + ip
		host_ip_label.visible = true
	else:
		host_ip_label.visible = false


# ---------------------------------------------------------------------------
# Phase 4 — kill feed, countdown, hitmarkers, spectator, end stats.
# ---------------------------------------------------------------------------

func _match_goal_text() -> String:
	match game_mode:
		0:
			return "First to %d kills  •  %s" % [kill_limit, GameData.MAP_NAMES[map_id]]
		1:
			return "RED vs BLUE — first to %d kills  •  %s" % [kill_limit, GameData.MAP_NAMES[map_id]]
		2:
			return "Survival — last one standing wins the round  •  %s" % GameData.MAP_NAMES[map_id]
		_:
			return "Last Man Standing — one life, no respawns  •  %s" % GameData.MAP_NAMES[map_id]


func _update_countdown(delta: float) -> void:
	if _fight_timer > 0.0:
		_fight_timer -= delta
		if _fight_timer <= 0.0:
			_countdown_label.visible = false
			_countdown_sub.visible = false
	if not _countdown_active:
		return
	if multiplayer.is_server():
		_countdown_t -= delta
		var n := int(ceil(_countdown_t))
		if n != _countdown_last_shown:
			_countdown_last_shown = n
			rpc("sync_countdown", n)
		if _countdown_t <= 0.0:
			_countdown_active = false
			rpc("sync_countdown", 0)
	else:
		# Watchdog: a client that missed the host's sync (late join)
		# must never stay frozen — end the countdown locally.
		_countdown_t -= delta
		if _countdown_t <= 0.0:
			_countdown_active = false
			_fight_timer = 0.9
	_update_countdown_labels()


func _update_countdown_labels() -> void:
	if _countdown_active:
		var n := int(ceil(maxf(_countdown_t, 0.0)))
		_countdown_label.text = str(maxi(n, 1))
		_countdown_label.visible = true
		_countdown_sub.text = _match_goal_text()
		_countdown_sub.visible = true
	elif _fight_timer > 0.0:
		_countdown_label.text = "FIGHT!"
		_countdown_label.visible = true
		_countdown_sub.visible = false


@rpc("any_peer", "call_local")
func sync_countdown(n: int) -> void:
	# Only the host drives the countdown; a late joiner syncs to it.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if n > 0:
		_countdown_active = true
		_countdown_t = float(n)
		_countdown_last_shown = n
	else:
		# n == 0: the fight starts. Show FIGHT! even on the host
		# (its local call runs after _countdown_active was cleared).
		_fight_timer = 0.9
		_countdown_active = false
		_countdown_last_shown = 0
	_update_countdown_labels()


func _player_name(peer_id: int) -> String:
	var node = players_node.get_node_or_null(str(peer_id))
	if node != null:
		return String(node.player_name)
	return "Player"


func _kill_feed_weapon_text(weapon_id: int) -> String:
	if weapon_id >= 0:
		return String(WeaponData.get_weapon(weapon_id).get("name", "Rifle"))
	if weapon_id == -2:
		return "Grenade"
	return "Explosion"


# Host-side kill-credit lock (QA-031, T-56). Called by the host only,
# from bullet.gd _hit_player and request_explosion, when a hit is
# computed lethal. Returns true only for the FIRST credit for this
# victim inside the lock window: the kill is awarded to the killer
# (self-kills excluded, as before) and the kill feed is announced
# exactly once. A second lethal hit in the same window returns false
# and credits/announces nothing — no double kill, no double feed
# line. After the window expires a new credit is allowed again, so
# the victim's next life is unaffected.
func try_credit_kill(killer_id: int, victim_id: int, weapon_id: int) -> bool:
	if not multiplayer.is_server():
		return false
	var now := Time.get_ticks_msec()
	if _kill_credit_lock.has(victim_id):
		if now - int(_kill_credit_lock[victim_id]) < KILL_CREDIT_LOCK_MS:
			return false
	_kill_credit_lock[victim_id] = now
	if killer_id != victim_id:
		var killer = players_node.get_node_or_null(str(killer_id))
		if killer != null:
			if killer.get_multiplayer_authority() == multiplayer.get_unique_id():
				killer.add_kill()
			elif multiplayer.get_peers().has(killer.get_multiplayer_authority()):
				killer.rpc_id(killer.get_multiplayer_authority(), "add_kill")
	rpc("announce_kill", killer_id, victim_id, weapon_id)
	return true


func clear_kill_credit(peer_id: int) -> void:
	_kill_credit_lock.erase(peer_id)


@rpc("any_peer", "call_local")
func announce_kill(killer_id: int, victim_id: int, weapon_id: int) -> void:
	# Only the host announces kills (it decided the damage).
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	# Streaks: every peer tracks them from the same feed, so the end
	# screen agrees everywhere.
	if killer_id > 0 and killer_id != victim_id:
		var s := int(_kill_streaks.get(killer_id, 0)) + 1
		_kill_streaks[killer_id] = s
		_best_streaks[killer_id] = maxi(int(_best_streaks.get(killer_id, 0)), s)
	_kill_streaks[victim_id] = 0
	# Mark this death as fed so the host's death watcher (lava, falls,
	# anything without a killer) does not post a second line for it.
	_fed_deaths[victim_id] = true
	_add_kill_feed_entry(killer_id, victim_id, weapon_id)


func _add_kill_feed_entry(killer_id: int, victim_id: int, weapon_id: int) -> void:
	if _kill_feed_list == null:
		return
	var victim_name := _player_name(victim_id)
	var text := ""
	if killer_id == 0:
		text = "☠ %s died" % victim_name
	elif killer_id == victim_id:
		text = "%s blew themself up" % victim_name
	else:
		text = "%s  ☠  %s   —  %s" % [_player_name(killer_id), victim_name, _kill_feed_weapon_text(weapon_id)]
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", FONT_BODY_MEDIUM)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", UI_FONT)
	_outline_label(lbl)
	# v3.2 NEON ARENA: each feed line sits on its own dark
	# translucent chip (THEME_SPEC.md §3) so it reads over any map.
	var chip := PanelContainer.new()
	var chip_bg := StyleBoxFlat.new()
	chip_bg.bg_color = Color(0.02, 0.05, 0.09, 0.72)
	chip_bg.corner_radius_top_left = 4
	chip_bg.corner_radius_top_right = 4
	chip_bg.corner_radius_bottom_left = 4
	chip_bg.corner_radius_bottom_right = 4
	chip_bg.content_margin_left = 8
	chip_bg.content_margin_right = 8
	chip_bg.content_margin_top = 2
	chip_bg.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", chip_bg)
	chip.add_child(lbl)
	_kill_feed_list.add_child(chip)
	_kill_feed_entries.append({"label": lbl, "panel": chip, "expiry": 5.0})
	while _kill_feed_entries.size() > 4:
		var old: Dictionary = _kill_feed_entries.pop_front()
		(old["panel"] as PanelContainer).queue_free()


func _update_kill_feed(delta: float) -> void:
	if _kill_feed_entries.is_empty():
		return
	var kept: Array = []
	for e in _kill_feed_entries:
		var d: Dictionary = e
		d["expiry"] = float(d["expiry"]) - delta
		if float(d["expiry"]) <= 0.0:
			# Free the whole chip (the label goes with it).
			if d.has("panel"):
				(d["panel"] as PanelContainer).queue_free()
			else:
				(d["label"] as Label).queue_free()
		else:
			kept.append(d)
	_kill_feed_entries = kept


func _update_death_watcher() -> void:
	# Host only: a death with no killer (lava, barrel chain with no
	# shooter, anything the bullet/explosion paths did not announce)
	# still deserves one feed line — but never a second line for a
	# death announce_kill already covered (see _fed_deaths).
	if not multiplayer.is_server() or match_over:
		return
	for child in players_node.get_children():
		var pid: int = child.peer_id
		if child.alive:
			_alive_watch[pid] = true
			_fed_deaths.erase(pid)
		elif bool(_alive_watch.get(pid, true)):
			_alive_watch[pid] = false
			if not _fed_deaths.has(pid):
				rpc("announce_kill", 0, pid, -1)


func _show_hitmarker(dmg: int, pos: Vector2, lethal: bool) -> void:
	# Centre cross (red on a lethal hit) + a floating damage number
	# at the hit point in the world.
	if _hitmarker_label != null:
		_hitmarker_label.add_theme_color_override("font_color", Color(1.0, 0.25, 0.2) if lethal else Color(1, 1, 1))
		_hitmarker_label.visible = true
		_hitmark_timer = 0.18
	var num := Label.new()
	num.text = str(dmg)
	num.position = pos + Vector2(-14, -30)
	num.add_theme_font_size_override("font_size", 22)
	num.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2) if lethal else Color(1.0, 0.85, 0.3))
	num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	num.add_theme_constant_override("outline_size", 4)
	fx_node.add_child(num)
	var tw := create_tween()
	tw.tween_property(num, "position:y", num.position.y - 44.0, 0.7)
	tw.parallel().tween_property(num, "modulate:a", 0.0, 0.7)
	tw.tween_callback(num.queue_free)


func _update_hitmarker(delta: float) -> void:
	if _hitmark_timer > 0.0:
		_hitmark_timer -= delta
		if _hitmark_timer <= 0.0 and _hitmarker_label != null:
			_hitmarker_label.visible = false


func _spectate_targets() -> Array:
	var out: Array = []
	for child in players_node.get_children():
		if child.alive and child.get_multiplayer_authority() != multiplayer.get_unique_id():
			out.append(child)
	return out


func _update_spectator(delta: float) -> void:
	# Phase 4 (stretch) — Survival/LMS only: after death, watch a
	# living player instead of staring at your own corpse. The
	# spectate camera takes over; respawning hands it back.
	if game_mode != 2 and game_mode != 3:
		return
	var lp = _get_local_player()
	if lp == null or match_over:
		if _spectating:
			_stop_spectating()
		return
	if lp.alive:
		if _spectating:
			_stop_spectating()
		return
	var targets := _spectate_targets()
	if targets.is_empty():
		_spectate_label.text = "Eliminated! Waiting for the round to end..."
		_spectate_label.visible = true
		_spectate_next_btn.visible = false
		if _spectate_cam != null:
			_spectate_cam.enabled = false
		_spectating = false
		return
	_spectating = true
	if _spectate_target == null or not is_instance_valid(_spectate_target) or not _spectate_target.alive:
		_spectate_idx = 0
		_spectate_target = targets[0]
	_spectate_cam.enabled = true
	_spectate_cam.make_current()
	# Smooth-follow the target (no teleport snapping).
	_spectate_cam.global_position = _spectate_cam.global_position.lerp(_spectate_target.global_position, clampf(delta * 8.0, 0.0, 1.0))
	_spectate_label.text = "SPECTATING: %s  —  you are out" % String(_spectate_target.player_name)
	_spectate_label.visible = true
	_spectate_next_btn.visible = targets.size() > 1


func _on_spectate_next_pressed() -> void:
	var targets := _spectate_targets()
	if targets.is_empty():
		return
	_spectate_idx = (_spectate_idx + 1) % targets.size()
	_spectate_target = targets[_spectate_idx]
	if _spectate_cam != null and _spectate_target != null:
		_spectate_cam.global_position = _spectate_target.global_position


func _stop_spectating() -> void:
	_spectating = false
	_spectate_target = null
	if _spectate_cam != null:
		_spectate_cam.enabled = false
	if _spectate_label != null:
		_spectate_label.visible = false
	if _spectate_next_btn != null:
		_spectate_next_btn.visible = false
	var lp = _get_local_player()
	if lp != null and lp._camera != null:
		lp._camera.make_current()


func _start_broadcast() -> void:
	# Announce the room on every broadcast address (limited + subnet),
	# so clients find it on routers and hotspots that drop 255.255.255.255.
	_udp_broadcast = PacketPeerUDP.new()
	_udp_broadcast.set_broadcast_enabled(true)
	_udp_broadcast.set_dest_address("255.255.255.255", DISCOVERY_PORT)
	var subnets := LanDiscovery.broadcast_addresses()
	_udp_broadcast_sockets.clear()
	_udp_broadcast_sockets.append(_udp_broadcast)
	for addr in subnets:
		if addr == "255.255.255.255":
			continue
		var s := PacketPeerUDP.new()
		s.set_broadcast_enabled(true)
		s.set_dest_address(addr, DISCOVERY_PORT)
		_udp_broadcast_sockets.append(s)


func _room_card() -> Dictionary:
	return {
		"room_name": GameData.room_name,
		"host_name": GameData.player_name,
		"players": players_node.get_child_count(),
		"max_players": max_players,
		"map_id": map_id,
		"mode": game_mode,
		"status": "playing" if not match_over else "playing",
		"port": PORT,
		"private": GameData.room_private,
	}


func _update_broadcast(delta: float) -> void:
	if _udp_broadcast == null:
		return
	_broadcast_timer += delta
	if _broadcast_timer >= 1.0:
		_broadcast_timer = 0.0
		var pkt := LanDiscovery.build_room_packet(_room_card())
		for s in _udp_broadcast_sockets:
			s.put_packet(pkt)


func _spawn_initial_pickups() -> void:
	# 3 pickups present at match start (GAP-37: the map was empty
	# for the first 14 s), from distinct spots. Phase 4: a health
	# pack is always among them, so the new health pickup is visible
	# from the first seconds.
	if not multiplayer.is_server():
		return
	var spots: Array = MAPS[map_id]["pickups"]
	# [spot, kind]: SMG on the left, SNIPER pinned to the centre
	# spot (index 3), Health on the right.
	var init := [[0, 1], [3, 3], [4, 5]]
	for pair in init:
		_spawn_pickup_at(int(pair[0]), int(pair[1]))
	_centre_kind_next = 4 # the next centre weapon is the Rocket


func _spawn_pickup_at(spot_idx: int, kind: int) -> void:
	var spots: Array = MAPS[map_id]["pickups"]
	var pos: Vector2 = spots[spot_idx % spots.size()]
	var pname := "pickup_" + str(Time.get_ticks_msec()) + "_" + str(spot_idx)
	rpc("spawn_pickup_remote", pos, pname, kind, spot_idx)


func on_pickup_gone(spot_idx: int) -> void:
	# A pickup was collected or despawned: restart its per-spot
	# 14 s timer (GAP-37). Only the server tracks this.
	_pickup_spot_timers[spot_idx] = 14.0


func _update_pickup_spawn(delta: float) -> void:
	if not multiplayer.is_server() or match_over:
		return
	if not _initial_pickups_done:
		_initial_pickups_done = true
		_spawn_initial_pickups()
	# Per-spot timers (GAP-37): each spot respawns 14 s after its
	# pickup was collected/despawned; total active never exceeds the cap.
	var spots: Array = MAPS[map_id]["pickups"]
	var active_spots := {}
	for child in pickups_node.get_children():
		active_spots[int(child.get("spot_index"))] = true
	for i in spots.size():
		if active_spots.has(i):
			continue
		var t := float(_pickup_spot_timers.get(i, 0.0)) - delta
		_pickup_spot_timers[i] = t
		if t <= 0.0 and pickups_node.get_child_count() < 3:
			_pickup_spot_timers[i] = 14.0
			if i == 3:
				# Centre spot: pinned Sniper/Rocket, alternating.
				_spawn_pickup_at(i, _centre_kind_next)
				_centre_kind_next = 3 if _centre_kind_next == 4 else 4
			else:
				var kinds := [1, 1, 2, 2, 5, 6]
				_spawn_pickup_at(i, kinds[randi() % kinds.size()])


@rpc("any_peer", "call_local")
func spawn_pickup_remote(pos: Vector2, pname: String, kind: int, spot_idx: int = -1) -> void:
	if pickups_node.has_node(pname):
		return
	var p = PICKUP_SCENE.instantiate()
	p.name = pname
	p.position = pos
	p.kind = kind
	p.spot_index = spot_idx
	pickups_node.add_child(p)


func _update_join_timeout(delta: float) -> void:
	if multiplayer.is_server() or _join_failed or match_over:
		return
	if _get_local_player() != null:
		return
	_join_timer += delta
	# Spawn retries run every 2 s in _retry_spawn_if_needed; the
	# timeout below is the last resort.
	if _join_timer >= JOIN_TIMEOUT:
		# v3.2 QA-047: show the actual state instead of a generic
		# message, so a Wi-Fi/IP problem can be told apart from a
		# game bug: which IP was tried, whether ENet is up, whether
		# the server answered anything, and how many players were seen.
		var peer = multiplayer.multiplayer_peer
		var enet_state := "no network peer"
		if peer is ENetMultiplayerPeer:
			enet_state = "ENet: " + str((peer as ENetMultiplayerPeer).get_connection_status())
		_show_error("Could not connect to %s.\n%s. Server answered: %s. Players seen: %d/8.\nCheck the Wi-Fi and IP, then tap Retry." % [
			GameData.host_ip if GameData.host_ip != "" else "the host",
			enet_state,
			"yes" if _server_answered else "no",
			players_node.get_child_count()])


# v3.2 two-peer join regression test. Runs in the game scene on
# BOTH processes: the host auto-started the match, the client joined
# via Quick Play (or --auto-join). After 12 s each side prints its
# verdict and quits. The client also holds the move stick from t=2 s
# so the host can verify the client's player actually MOVES as seen
# on the host (the frozen-2nd-player symptom).
func _update_jointest(delta: float) -> void:
	if _join_test_done:
		return
	_join_test_timer += delta
	_join_test_status_t += delta
	if _join_test_client and _join_test_timer >= 2.0 and move_stick != null and not move_stick.is_active():
		_on_touch_press(930, move_stick.get_global_rect().get_center() + Vector2(60, 0))
	if _join_test_status_t >= 2.0:
		_join_test_status_t = 0.0
		var lp = _get_local_player()
		print("JOINTEST STATUS t=", int(_join_test_timer), "s role=", "host" if _join_test_host else "client",
			" players=", players_node.get_child_count(), " local=", lp != null,
			" peers=", multiplayer.get_peers(), " join_failed=", _join_failed,
			" spawned=", _spawned.keys())
	if _join_test_host and _join_test_timer >= 8.0 and _join_test_pos_snap.is_empty():
		for child in players_node.get_children():
			_join_test_pos_snap[int(child.peer_id)] = child.position
	if _join_test_timer < 12.0:
		return
	_join_test_done = true
	if _join_test_host:
		var n := players_node.get_child_count()
		var moved := false
		for child in players_node.get_children():
			var pid := int(child.peer_id)
			if pid == 1:
				continue
			var before: Vector2 = _join_test_pos_snap.get(pid, child.position)
			if child.position.distance_to(before) > 50.0:
				moved = true
		var ok: bool = n >= 2 and moved
		print("JOINTEST HOST: %s — players=%d spawned=%s moved_remote=%s (want players>=2 and the remote player moving)" % ["PASS" if ok else "FAIL", n, _spawned.keys(), moved])
	else:
		var lp2 = _get_local_player()
		var n2 := players_node.get_child_count()
		var conn := "?"
		var peer = multiplayer.multiplayer_peer
		if peer is ENetMultiplayerPeer:
			conn = str((peer as ENetMultiplayerPeer).get_connection_status())
		var ok2: bool = lp2 != null and n2 >= 2
		print("JOINTEST CLIENT: %s — local_spawned=%s players=%d connection=%s join_failed=%s join_timer=%.1f (want local player + players>=2)" % ["PASS" if ok2 else "FAIL", lp2 != null, n2, conn, _join_failed, _join_timer])
	get_tree().quit()


# =====================================================================
# v3.2 QA-047 — replication simulation (--repl-sim-test).
# One process plays BOTH roles: this instance is the server, a second
# Game instance (the shadow) is the client. The server's spawn/list
# payloads are delivered to the shadow by hand, simulating the wire.
# Steps: (0) server spawns host + client; (1) shadow starts at the
# v3.1 symptom state (0 players, "Connecting..."); (2) the first
# spawn is "lost", the client retries, the server re-sends, the
# shadow heals via the player list; (3) double delivery stays
# idempotent; (4) disconnect despawns on the client. Verdict + quit.
# Steps 8-11 (v3.4 QA-053): the RPC snapshot channel replaces the
# synchronizer — no MultiplayerSynchronizer on any copy, snapshots
# hand-delivered to the receiver's receive_move_snapshot (the same
# hand-delivery the spawn RPCs get), streamed at a steady +5 px/frame
# so smoothness can be asserted too (small forward steps, no
# snap-back). Steps 12-13 (v3.4 QA-055): the same rifle bullet fired
# on both instances must track the same path frame by frame.
# The sim can only hand-deliver payloads (no live ENet) — see the
# note in step 10 for the one-process limit (pid-1 is "local" on both
# instances) and its workaround.
# =====================================================================

func _repl_sim_check(label: String, ok: bool, detail: String = "") -> void:
	if ok:
		_repl_sim_passed += 1
		print("REPLSIM %s: PASS %s" % [label, detail])
	else:
		_repl_sim_failed += 1
		print("REPLSIM %s: FAIL %s" % [label, detail])


func _repl_sim_deliver_recorded() -> void:
	# Hand the recorded payloads to the shadow client, in order,
	# exactly as the network would deliver them.
	for item in _repl_sim_sent:
		var d := item as Dictionary
		if d.get("kind", "") == "spawn_player_remote":
			_repl_sim_shadow.spawn_player_remote(d.get("data", {}))
		elif d.get("kind", "") == "player_list_remote":
			_repl_sim_shadow.player_list_remote(d.get("data", []))
	_repl_sim_sent.clear()


func _repl_sim_snapshot(seq: int, pos: Vector2, vel: Vector2) -> Dictionary:
	# One QA-053 move snapshot, exactly as _send_move_snapshot builds
	# it (same keys the receiver reads).
	return {"seq": seq, "p": pos, "v": vel, "aim": 0.0, "face": 1,
		"wpn": 0, "hp": 100, "k": 0, "d": 0, "al": true, "fuel": 100.0,
		"ls": 0, "mag": 30, "gr": 2, "sf": 0, "sh": 0}


func _repl_sim_track_reset(pos: Vector2) -> void:
	_repl_sim_track_prev = pos
	_repl_sim_track_max_step = 0.0
	_repl_sim_track_max_back = 0.0
	_repl_sim_track_best_x = pos.x


func _repl_sim_track(pos: Vector2, frame_delta: float) -> void:
	# Smoothness tracker: biggest single-frame step RATE (px/s), and
	# biggest backward (snap-back) move from the furthest-forward x
	# reached. The rate is used, not the raw step, because the sim
	# runs at ~10 fps under llvmpipe: a healthy 300 px/s glide is a
	# 30 px step between _process frames there, but still 300 px/s.
	# A freeze-then-catch-up burst or a snap-back to an old position
	# shows up here as a multi-thousand px/s step or a backward jump.
	if _repl_sim_track_prev == Vector2.INF:
		_repl_sim_track_prev = pos
		_repl_sim_track_best_x = pos.x
		return
	var step_rate := pos.distance_to(_repl_sim_track_prev) / maxf(frame_delta, 0.001)
	if step_rate > _repl_sim_track_max_step:
		_repl_sim_track_max_step = step_rate
	if pos.x < _repl_sim_track_best_x:
		var back := _repl_sim_track_best_x - pos.x
		if back > _repl_sim_track_max_back:
			_repl_sim_track_max_back = back
	if pos.x > _repl_sim_track_best_x:
		_repl_sim_track_best_x = pos.x
	_repl_sim_track_prev = pos


func _repl_sim_has_sync(p) -> bool:
	if p == null:
		return false
	for c in p.get_children():
		if c is MultiplayerSynchronizer:
			return true
	return false


func _update_replsimtest(delta: float) -> void:
	if _repl_sim_done:
		return
	_repl_sim_timer += delta
	match _repl_sim_step:
		0:
			# Wait for the deferred self-spawn, then spawn the client.
			if _repl_sim_timer < 1.0:
				return
			_do_spawn(2, "SimClient", 1, 0)
			_repl_sim_check("SERVER-SPAWN", players_node.get_child_count() == 2 and _spawn_data.size() == 2,
				"server players=%d spawn_data=%d (want 2/2)" % [players_node.get_child_count(), _spawn_data.size()])
			_repl_sim_server_list = _player_list_data()
			# Shadow client: a second Game instance (same map).
			var shadow = load("res://game.tscn").instantiate()
			_repl_sim_shadow = shadow
			get_tree().root.add_child(shadow)
			shadow._repl_sim_test = false # this instance owns the sim
			shadow._repl_sim_done = true
			_repl_sim_step = 1
			_repl_sim_timer = 0.0
		1:
			# Wait for the shadow's own deferred self-spawn, then reset
			# it to the v3.1 symptom state: 0 players, no local player.
			if _repl_sim_timer < 1.5:
				return
			for child in _repl_sim_shadow.players_node.get_children():
				child.queue_free()
			# Freeing is deferred: wait a frame before counting.
			_repl_sim_step = 2
			_repl_sim_timer = 0.0
		2:
			if _repl_sim_timer < 0.3:
				return
			_repl_sim_shadow._spawned.clear()
			_repl_sim_shadow._spawn_data.clear()
			_repl_sim_shadow._local_player = null
			_repl_sim_shadow._server_answered = false
			_repl_sim_shadow._update_hud(0.0)
			_repl_sim_check("BUG-STATE", _repl_sim_shadow.players_node.get_child_count() == 0 and (_repl_sim_shadow.message_label.text == "Connecting..." or _repl_sim_shadow.message_label.text == "Starting..."),
				"shadow players=%d message='%s' (v3.1 symptom reproduced; a real ENet client shows 'Connecting...', the offline shadow shows 'Starting...')" % [_repl_sim_shadow.players_node.get_child_count(), _repl_sim_shadow.message_label.text])
			# The first spawn is "lost" (v3.1): deliver nothing. The
			# client retries -> server re-sends -> deliver by hand.
			_repl_sim_sent.clear()
			_do_spawn(2, "SimClient", 1, 0) # retry: already spawned
			_repl_sim_check("RETRY-RESEND", _repl_sim_sent.size() == 3 and players_node.get_child_count() == 2,
				"re-sent payloads=%d server players=%d (want 3 payloads, still 2 players)" % [_repl_sim_sent.size(), players_node.get_child_count()])
			_repl_sim_deliver_recorded()
			_repl_sim_step = 3
			_repl_sim_timer = 0.0
		3:
			if _repl_sim_timer < 0.3:
				return
			_repl_sim_shadow._update_hud(0.0)
			var lp = _repl_sim_shadow.players_node.get_node_or_null("2")
			_repl_sim_check("CLIENT-HEALED", _repl_sim_shadow.players_node.get_child_count() == 2 and lp != null,
				"shadow players=%d has_peer2=%s (want 2/true)" % [_repl_sim_shadow.players_node.get_child_count(), lp != null])
			_repl_sim_check("CONNECTING-CLEARS", _repl_sim_shadow.message_label.text != "Connecting..." and _repl_sim_shadow._get_local_player() != null,
				"message='%s' local=%s (want no 'Connecting...', local player found)" % [_repl_sim_shadow.message_label.text, _repl_sim_shadow._get_local_player() != null])
			_repl_sim_check("HOST-PLAYER-TOO", _repl_sim_shadow.players_node.get_node_or_null("1") != null,
				"host player visible on the client (v3.1 lost it as well)")
			# QA-053: there must be NO MultiplayerSynchronizer on the
			# player any more — the RPC snapshot channel is the only
			# channel (a leftover synchronizer would be a second
			# writer on the same position). Authority still 2.
			var sync_node = null
			if lp != null:
				for c in lp.get_children():
					if c is MultiplayerSynchronizer:
						sync_node = c
						break
			_repl_sim_check("RPC-CHANNEL", sync_node == null and lp != null and lp.get_multiplayer_authority() == 2,
				"client player has synchronizer=%s authority=%s (want none/2 — snapshots are the only channel)" % [sync_node != null, lp.get_multiplayer_authority() if lp != null else -1])
			# Double delivery must stay idempotent.
			_repl_sim_shadow.player_list_remote(_repl_sim_server_list)
			_repl_sim_step = 4
			_repl_sim_timer = 0.0
		4:
			if _repl_sim_timer < 0.3:
				return
			_repl_sim_check("IDEMPOTENT", _repl_sim_shadow.players_node.get_child_count() == 2,
				"shadow players=%d after the list arrived twice (want 2)" % [_repl_sim_shadow.players_node.get_child_count()])
			# Disconnect: server forgets peer 2, client must despawn it.
			_on_peer_disconnected(2)
			_repl_sim_shadow.despawn_player_remote(2)
			_repl_sim_step = 5
			_repl_sim_timer = 0.0
		5:
			if _repl_sim_timer < 0.3:
				return
			_repl_sim_check("DESPAWN", players_node.get_child_count() == 1 and _repl_sim_shadow.players_node.get_child_count() == 1,
				"server players=%d shadow players=%d (want 1/1)" % [players_node.get_child_count(), _repl_sim_shadow.players_node.get_child_count()])
			# Steps 6-8: the signal-path checks (QA-047 audit items).
			# Re-spawn peer 2 on the server, then reset the shadow to
			# 0 players and heal it ONLY via the peer_connected
			# signal handler — the path a late joiner takes.
			_do_spawn(2, "SimClient", 1, 0)
			for child in _repl_sim_shadow.players_node.get_children():
				child.queue_free()
			_repl_sim_shadow._spawned.clear()
			_repl_sim_shadow._spawn_data.clear()
			_repl_sim_shadow._local_player = null
			_repl_sim_shadow._server_answered = false
			_repl_sim_sent.clear()
			_on_peer_connected(2)
			_repl_sim_step = 6
			_repl_sim_timer = 0.0
		6:
			if _repl_sim_timer < 0.3:
				return
			# SIGNAL-ORDER: the handlers were connected in _ready,
			# before any event could fire (a connection made after
			# the event is the classic missed-signal race).
			_repl_sim_check("SIGNAL-ORDER", multiplayer.peer_connected.is_connected(_on_peer_connected) and multiplayer.peer_disconnected.is_connected(_on_peer_disconnected) and multiplayer.server_disconnected.is_connected(_on_server_disconnected) and _repl_sim_shadow.multiplayer.peer_connected.is_connected(_repl_sim_shadow._on_peer_connected),
				"peer_connected/disconnected + server_disconnected connected on server and shadow (want all true)")
			# SIGNAL-PEER-CONNECTED: the recorded payloads came from
			# the signal handler; delivering them must heal the shadow.
			_repl_sim_check("SIGNAL-PEER-CONNECTED", _repl_sim_sent.size() == 3,
				"payloads recorded by the signal handler=%d (want 3: spawn x2 + list)" % _repl_sim_sent.size())
			_repl_sim_deliver_recorded()
			_repl_sim_shadow._update_hud(0.0)
			_repl_sim_check("SIGNAL-HEALS", _repl_sim_shadow.players_node.get_child_count() == 2 and _repl_sim_shadow.players_node.get_node_or_null("2") != null and _repl_sim_shadow.message_label.text != "Connecting..." and _repl_sim_shadow.message_label.text != "Starting...",
				"shadow players=%d message='%s' (want 2, no waiting text)" % [_repl_sim_shadow.players_node.get_child_count(), _repl_sim_shadow.message_label.text])
			# SIGNAL-GUARD: _ready_announced blocks a double announce
			# (checked on the server branch, which returns before any
			# RPC — the guard logic is identical on the client).
			_ready_announced = false
			_announce_ready()
			var guard_set := _ready_announced
			_announce_ready()
			_repl_sim_check("SIGNAL-GUARD", guard_set and _ready_announced,
				"flag set after first announce=%s, still set after second (double announce is a no-op)=%s" % [guard_set, _ready_announced])
			# CONTROLS-ATTACH: hold the move stick and watch the
			# shadow's local player (pid 1) actually move. The press
			# goes to THIS instance's stick: a player finds its game
			# via get_first_node_in_group("game"), and in this one
			# process that is the server instance — so the shadow's
			# player reads the server instance's input state. (On a
			# real phone there is only one game instance, so the
			# client reads its own.) The shadow's own stick state is
			# verified by the debug print in step 7.
			var lp0 = _repl_sim_shadow.players_node.get_node_or_null("1")
			if lp0 != null:
				_repl_sim_move_start = lp0.position
				_on_touch_press(930, move_stick.get_global_rect().get_center() + Vector2(60, 0))
			_repl_sim_step = 7
			_repl_sim_timer = 0.0
		7:
			if _repl_sim_timer < 1.0:
				return
			var lp1 = _repl_sim_shadow.players_node.get_node_or_null("1")
			var moved := 0.0
			if lp1 != null:
				moved = lp1.position.distance_to(_repl_sim_move_start)
			_on_touch_release(930)
			_repl_sim_check("CONTROLS-ATTACH", moved > 50.0,
				"list-spawned local player moved %.0f px under the move stick (want >50)" % moved)
			_repl_sim_step = 8
			_repl_sim_timer = 0.0
		8:
			# Steps 8-11 (v3.4 QA-053): the RPC snapshot channel.
			# (a) NO MultiplayerSynchronizer on any of the 4 player
			# copies — one channel only. (b) Client->server: stream
			# snapshots of the shadow's pid-2 player moving steadily
			# right (+5 px/frame, as a 30/s snapshot flow would) and
			# hand-deliver each one to the server copy's
			# receive_move_snapshot — the same hand-delivery the
			# spawn RPCs get. Step 9 asserts the server copy follows
			# smoothly (moves, small steps, no snap-back).
			if _repl_sim_timer < 0.3:
				return
			var s_p1 = players_node.get_node_or_null("1")
			var s_p2 = players_node.get_node_or_null("2")
			var c_p1 = _repl_sim_shadow.players_node.get_node_or_null("1")
			var c_p2 = _repl_sim_shadow.players_node.get_node_or_null("2")
			var no_sync: bool = s_p1 != null and s_p2 != null and c_p1 != null and c_p2 != null \
				and not _repl_sim_has_sync(s_p1) and not _repl_sim_has_sync(s_p2) \
				and not _repl_sim_has_sync(c_p1) and not _repl_sim_has_sync(c_p2)
			_repl_sim_check("NO-SYNC", no_sync,
				"synchronizer present on server p1/p2=%s/%s shadow p1/p2=%s/%s (want none — snapshots are the only channel)" % [
					_repl_sim_has_sync(s_p1), _repl_sim_has_sync(s_p2),
					_repl_sim_has_sync(c_p1), _repl_sim_has_sync(c_p2)])
			if s_p2 != null and c_p2 != null:
				_repl_sim_c2s_start = s_p2.position
				_repl_sim_stream_x = c_p2.position.x
				_repl_sim_stream_y = c_p2.position.y
				_repl_sim_seq = 0
				_repl_sim_track_reset(s_p2.position)
				_repl_sim_seq += 1
				s_p2.receive_move_snapshot(_repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
			_repl_sim_check("RPC-C2S-DELIVER", s_p2 != null and s_p2.sync_position == Vector2(_repl_sim_stream_x, _repl_sim_stream_y) and s_p2._snapshots.size() >= 1,
				"server pid-2 last snapshot=%s buffered=%d (want the delivered pos, >=1 snapshot)" % [s_p2.sync_position if s_p2 != null else Vector2.INF, s_p2._snapshots.size() if s_p2 != null else -1])
			_repl_sim_step = 9
			_repl_sim_timer = 0.0
		9:
			# Stream one snapshot per frame (+5 px in x, 300 px/s)
			# and track the server copy's rendered position: it must
			# glide forward in small steps, never freeze and jump,
			# never snap back to an old position. The first 0.2 s is
			# warm-up (the interpolation buffer fills; the very first
			# snapshot pins the copy at the stream start, which is a
			# join-moment placement, not steady-state motion) — the
			# tracker starts after it so only steady motion is scored.
			var s_p2b = players_node.get_node_or_null("2")
			if s_p2b != null:
				# Stream by TIME (300 px/s), not per frame: the sim
				# runs ~10 fps under llvmpipe, so +5 px/frame was
				# only +30 px in 0.6 s.
				_repl_sim_stream_x += 300.0 * delta
				_repl_sim_seq += 1
				s_p2b.receive_move_snapshot(_repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
				if _repl_sim_timer < 0.2:
					pass
				elif not _repl_sim_warm_done:
					_repl_sim_warm_done = true
					_repl_sim_track_reset(s_p2b.position)
				else:
					_repl_sim_track(s_p2b.position, delta)
			if _repl_sim_timer < 0.6:
				return
			var moved_c2s := 0.0
			if s_p2b != null:
				moved_c2s = s_p2b.position.distance_to(_repl_sim_c2s_start)
			_repl_sim_check("RPC-C2S-MOVE", moved_c2s > 50.0,
				"server pid-2 copy moved %.0f px under the streamed snapshots (want >50)" % moved_c2s)
			_repl_sim_check("RPC-C2S-SMOOTH", _repl_sim_track_max_step < 600.0 and _repl_sim_track_max_back < 5.0,
				"max step rate=%.0f px/s, max snap-back=%.1f px (want <600 px/s / <5 px — steady 300 px/s glide, no jumps)" % [_repl_sim_track_max_step, _repl_sim_track_max_back])
			# (d) setup: the HOST's player (pid 1) now moves +300 px
			# on the server; its snapshots are what the client must
			# render. The shadow's pid-1 copy is "local" in this one
			# process (both instances share the offline peer, unique
			# id 1), so its local branch would swallow a delivered
			# snapshot and never run the interpolation path. A real
			# client has unique id 2, so pid-1 is remote there.
			# Emulate that here by overriding the shadow copy's ROOT
			# authority to 2, then stream its snapshots in step 11.
			var s_p1b = players_node.get_node_or_null("1")
			var c_p1s = _repl_sim_shadow.players_node.get_node_or_null("1")
			if s_p1b != null and c_p1s != null:
				_repl_sim_s2c_start = c_p1s.position
				_repl_sim_stream_x = s_p1b.position.x + 300.0
				_repl_sim_stream_y = s_p1b.position.y
				c_p1s.set_multiplayer_authority(2)
				_repl_sim_seq = 1000
				_repl_sim_track_reset(c_p1s.position)
				_repl_sim_seq += 1
				c_p1s.receive_move_snapshot(_repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
			_repl_sim_check("RPC-S2C-DELIVER", c_p1s != null and c_p1s.sync_position == Vector2(_repl_sim_stream_x, _repl_sim_stream_y) and c_p1s._snapshots.size() >= 1,
				"shadow pid-1 last snapshot=%s buffered=%d (want the delivered pos, >=1 snapshot)" % [c_p1s.sync_position if c_p1s != null else Vector2.INF, c_p1s._snapshots.size() if c_p1s != null else -1])
			_repl_sim_warm_done = false
			_repl_sim_step = 10
			_repl_sim_timer = 0.0
		10:
			# Same stream, server -> client: the shadow's pid-1 copy
			# (authority overridden to 2 in step 9, so it runs the
			# remote branch) receives one snapshot per frame, +5 px
			# in x. First 0.2 s warms the interpolation buffer up;
			# then the tracker scores steady motion only.
			var c_p1t = _repl_sim_shadow.players_node.get_node_or_null("1")
			if c_p1t != null:
				_repl_sim_stream_x += 300.0 * delta
				_repl_sim_seq += 1
				c_p1t.receive_move_snapshot(_repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
				if _repl_sim_timer < 0.2:
					pass
				elif not _repl_sim_warm_done:
					_repl_sim_warm_done = true
					_repl_sim_track_reset(c_p1t.position)
				else:
					_repl_sim_track(c_p1t.position, delta)
			if _repl_sim_timer < 0.6:
				return
			var c_p1c = _repl_sim_shadow.players_node.get_node_or_null("1")
			var moved_s2c := 0.0
			if c_p1c != null:
				moved_s2c = c_p1c.position.distance_to(_repl_sim_s2c_start)
			_repl_sim_check("RPC-S2C-MOVE", moved_s2c > 50.0,
				"shadow pid-1 copy moved %.0f px under the streamed snapshots (want >50)" % moved_s2c)
			_repl_sim_check("RPC-S2C-SMOOTH", _repl_sim_track_max_step < 600.0 and _repl_sim_track_max_back < 5.0,
				"max step rate=%.0f px/s, max snap-back=%.1f px (want <600 px/s / <5 px — steady 300 px/s glide, no jumps)" % [_repl_sim_track_max_step, _repl_sim_track_max_back])
			# (e) QA-055 bullet tracking: fire the SAME rifle bullet
			# on both instances (identical spawn params, direct
			# calls = the spawn RPC hand-delivered) from open air
			# (1700, 455) on map 0, and compare the two flights
			# frame by frame in steps 11-12.
			var s_p1f = players_node.get_node_or_null("1")
			var muzzle := Vector2(1700, 455)
			if s_p1f != null:
				s_p1f.spawn_bullet(muzzle, Vector2.RIGHT, 1100.0, 12, 0, 1, 999, Vector2(1100, 0))
			var b_bullet = _repl_sim_shadow.obtain_bullet()
			b_bullet.setup(muzzle, Vector2.RIGHT, 1100.0, 12, 0, 1, false, 0.0, 1.2, 999, Vector2(1100, 0), 0.0)
			if b_bullet.get_parent() == null:
				_repl_sim_shadow.bullets_node.add_child(b_bullet)
			_repl_sim_bullet_a = null
			_repl_sim_bullet_b = null
			for b in bullets_node.get_children():
				if b.active:
					_repl_sim_bullet_a = b
			for b in _repl_sim_shadow.bullets_node.get_children():
				if b.active:
					_repl_sim_bullet_b = b
			_repl_sim_bullet_max_err = 0.0
			_repl_sim_bullet_max_step = 0.0
			_repl_sim_bullet_prev_b = Vector2.INF
			_repl_sim_bullet_frames = 0
			_repl_sim_step = 11
			_repl_sim_timer = 0.0
		11:
			# Track both bullets every frame: their positions must
			# agree (same params, same fixed physics step) and the
			# shadow bullet must advance in small per-frame steps.
			if is_instance_valid(_repl_sim_bullet_a) and is_instance_valid(_repl_sim_bullet_b) \
					and _repl_sim_bullet_a.active and _repl_sim_bullet_b.active:
				var err: float = _repl_sim_bullet_a.position.distance_to(_repl_sim_bullet_b.position)
				if err > _repl_sim_bullet_max_err:
					_repl_sim_bullet_max_err = err
				if _repl_sim_bullet_prev_b != Vector2.INF:
					var st: float = _repl_sim_bullet_b.position.distance_to(_repl_sim_bullet_prev_b) / maxf(delta, 0.001)
					if st > _repl_sim_bullet_max_step:
						_repl_sim_bullet_max_step = st
				_repl_sim_bullet_prev_b = _repl_sim_bullet_b.position
				_repl_sim_bullet_frames += 1
			if _repl_sim_timer < 0.1:
				return
			var a_pos: Vector2 = _repl_sim_bullet_a.position if is_instance_valid(_repl_sim_bullet_a) else Vector2.INF
			var b_pos: Vector2 = _repl_sim_bullet_b.position if is_instance_valid(_repl_sim_bullet_b) else Vector2.INF
			_repl_sim_check("BULLET-SPAWN", is_instance_valid(_repl_sim_bullet_a) and is_instance_valid(_repl_sim_bullet_b) \
					and _repl_sim_bullet_a.active and _repl_sim_bullet_b.active and a_pos.distance_to(b_pos) < 5.0,
				"server bullet=%s shadow bullet=%s (want both active, <5 px apart at spawn)" % [a_pos, b_pos])
			_repl_sim_step = 12
			_repl_sim_timer = 0.0
		12:
			# Keep tracking the flight for 1.0 s (~1100 px at rifle
			# speed, still inside map 0 and clear of platforms; the
			# bullet lives 1.2 s, so it is still flying at the check.
			# 1.0 s is needed because the sim runs ~10 fps under
			# llvmpipe — 0.5 s was only ~5 tracked frames.
			if is_instance_valid(_repl_sim_bullet_a) and is_instance_valid(_repl_sim_bullet_b) \
					and _repl_sim_bullet_a.active and _repl_sim_bullet_b.active:
				var err: float = _repl_sim_bullet_a.position.distance_to(_repl_sim_bullet_b.position)
				if err > _repl_sim_bullet_max_err:
					_repl_sim_bullet_max_err = err
				if _repl_sim_bullet_prev_b != Vector2.INF:
					var st: float = _repl_sim_bullet_b.position.distance_to(_repl_sim_bullet_prev_b) / maxf(delta, 0.001)
					if st > _repl_sim_bullet_max_step:
						_repl_sim_bullet_max_step = st
				_repl_sim_bullet_prev_b = _repl_sim_bullet_b.position
				_repl_sim_bullet_frames += 1
			if _repl_sim_timer < 1.0:
				return
			_repl_sim_check("BULLET-TRACK", _repl_sim_bullet_frames >= 10 and _repl_sim_bullet_max_err < 10.0,
				"tracked %d frames, max position error=%.1f px (want >=10 frames, <10 px — same path, realtime)" % [_repl_sim_bullet_frames, _repl_sim_bullet_max_err])
			_repl_sim_check("BULLET-SMOOTH", _repl_sim_bullet_max_step < 2200.0,
				"max step rate of the shadow bullet=%.0f px/s (want <2200 — rifle is 1100 px/s; a freeze-then-jump would be far faster)" % _repl_sim_bullet_max_step)
			_repl_sim_done = true
			print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
			get_tree().quit()


func _update_match_timer(delta: float) -> void:
	if match_over:
		return
	# Phase 4: the clock only runs once the countdown has finished.
	if _countdown_active:
		return
	if multiplayer.is_server():
		_time_left -= delta
		_time_sync_timer += delta
		if _time_sync_timer >= 1.0:
			_time_sync_timer = 0.0
			rpc("sync_time_left", _time_left)
		_check_match_end()


@rpc("any_peer", "call_local")
func sync_time_left(t: float) -> void:
	# Only the host may set the match clock.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_time_left = t


func _check_match_end() -> void:
	if match_over:
		return
	# Survival (2) and Last Man Standing (3) end by elimination;
	# the round check (Survival) runs separately in _check_round_end.
	if game_mode == 2:
		_check_round_end()
		# A Survival match can also end on the timer: most rounds won.
		if _time_left <= 0.0:
			_end_survival_on_time()
		return
	if game_mode == 3:
		var alive_count := 0
		var last_alive: Node = null
		for child in players_node.get_children():
			if child.alive:
				alive_count += 1
				last_alive = child
		# At least 2 players must have joined before elimination can
		# end the match (otherwise the host alone would "win" instantly).
		if players_node.get_child_count() >= 2 and alive_count <= 1 and last_alive != null:
			_end_match(last_alive.player_name, "is the last one standing!")
			return
		if _time_left <= 0.0:
			_end_lms_on_time()
		return
	var winner := ""
	var reason := ""
	if game_mode == 0:
		for child in players_node.get_children():
			if child.kills >= kill_limit:
				winner = child.player_name
				reason = "reached %d kills!" % kill_limit
				break
	else:
		var red := 0
		var blue := 0
		for child in players_node.get_children():
			if child.team == 0:
				red += child.kills
			elif child.team == 1:
				blue += child.kills
		if red >= kill_limit:
			winner = "RED TEAM"
			reason = "reached %d kills!" % kill_limit
		elif blue >= kill_limit:
			winner = "BLUE TEAM"
			reason = "reached %d kills!" % kill_limit
	if winner == "" and _time_left <= 0.0:
		if game_mode == 0:
			var best_kills := -1
			for child in players_node.get_children():
				if child.kills > best_kills:
					best_kills = child.kills
					winner = child.player_name
			reason = "time up - most kills wins!"
		else:
			var red := 0
			var blue := 0
			for child in players_node.get_children():
				if child.team == 0:
					red += child.kills
				elif child.team == 1:
					blue += child.kills
			if red > blue:
				winner = "RED TEAM"
			elif blue > red:
				winner = "BLUE TEAM"
			else:
				winner = "DRAW"
			reason = "time up!"
	if winner == "":
		return
	_end_match(winner, reason)


func _check_round_end() -> void:
	# Survival: a round ends when one player is left alive. That
	# player wins the round; first to the kill limit (rounds) wins
	# the match. Needs at least 2 players, like LMS.
	if players_node.get_child_count() < 2:
		return
	var alive_count := 0
	var last_alive: Node = null
	for child in players_node.get_children():
		if child.alive:
			alive_count += 1
			last_alive = child
	if alive_count == 1 and last_alive != null:
		var pid: int = last_alive.peer_id
		_round_wins[pid] = int(_round_wins.get(pid, 0)) + 1
		if int(_round_wins[pid]) >= kill_limit:
			_end_match(last_alive.player_name, "won %d rounds!" % kill_limit)
			return
		_reset_round()


func _reset_round() -> void:
	# Next round: everyone respawns fresh (positions, health, weapons).
	_round_number += 1
	_kill_credit_lock.clear() # QA-031: fresh round, fresh locks
	rpc("reset_round_remote_all")


@rpc("any_peer", "call_local")
func reset_round_remote_all() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	for child in players_node.get_children():
		if child.get_multiplayer_authority() == multiplayer.get_unique_id():
			child.reset_round_remote()


func _end_survival_on_time() -> void:
	var best := -1
	var winner := "DRAW"
	for pid in _round_wins.keys():
		if int(_round_wins[pid]) > best:
			best = int(_round_wins[pid])
			var node := players_node.get_node_or_null(str(pid))
			winner = node.player_name if node != null else "DRAW"
	_end_match(winner, "time up - most rounds wins!")


func _end_lms_on_time() -> void:
	var best_kills := -1
	var winner := "DRAW"
	for child in players_node.get_children():
		if child.kills > best_kills:
			best_kills = child.kills
			winner = child.player_name
	_end_match(winner, "time up - most kills wins!")


func _end_match(winner: String, reason: String) -> void:
	match_over = true
	var rows: Array = []
	for child in players_node.get_children():
		# Phase 4: end stats carry shots/hits (accuracy) + best streak.
		rows.append({"name": child.player_name, "kills": child.kills, "deaths": child.deaths, "team": child.team, "color": child.player_color, "rounds": int(_round_wins.get(child.peer_id, 0)), "shots": child._shots_fired, "hits": child._shots_hit, "streak": int(_best_streaks.get(child.peer_id, 0))})
	rows.sort_custom(func(a, b) -> bool: return a["kills"] > b["kills"])
	rpc("show_end_screen", winner, reason, rows)


@rpc("any_peer", "call_local")
func show_end_screen(winner: String, reason: String, rows: Array) -> void:
	# Only the host may end the match for everyone.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	match_over = true
	_end_shown = true
	# Phase 6: the match is over — back to the calm menu track.
	if audio != null:
		audio.play_menu_music()
	# "You win!" not "You wins!" — winner is "You" for the local
	# player, a name for anyone else.
	var win_word := "You win!" if winner == "You" else "%s wins!" % winner
	end_title.text = "%s\n%s" % [win_word, reason] if winner != "DRAW" else "Draw!\n%s" % reason
	# Phase 4: MVP / match summary banner (most kills, best accuracy).
	# Rows arrive sorted by kills, so rows[0] is the MVP.
	for n in _mvp_nodes:
		if is_instance_valid(n):
			n.queue_free()
	_mvp_nodes.clear()
	if not rows.is_empty():
		var mvp: Dictionary = rows[0]
		var mvp_st: Dictionary = GameData.compute_stats(int(mvp["kills"]), int(mvp["deaths"]), int(mvp.get("shots", 0)), int(mvp.get("hits", 0)))
		var mvp_row := HBoxContainer.new()
		mvp_row.alignment = BoxContainer.ALIGNMENT_CENTER
		mvp_row.add_theme_constant_override("separation", 8)
		var star := TextureRect.new()
		star.texture = preload("res://assets/skybrawl/pickups/pickup_012.png")
		star.custom_minimum_size = Vector2(36, 36)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mvp_row.add_child(star)
		var mvp_lbl := Label.new()
		mvp_lbl.text = "MVP: %s — %d kills, %d%% accuracy, best streak %d" % [
			String(mvp["name"]), int(mvp["kills"]), int(mvp_st["accuracy"]), int(mvp.get("streak", 0)),
		]
		mvp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mvp_lbl.add_theme_font_size_override("font_size", 22)
		mvp_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		mvp_row.add_child(mvp_lbl)
		_end_box.add_child(mvp_row)
		_end_box.move_child(mvp_row, 1)
		_mvp_nodes.append(mvp_row)
		var best_acc := -1.0
		var best_acc_name := ""
		for r in rows:
			var st: Dictionary = GameData.compute_stats(int(r["kills"]), int(r["deaths"]), int(r.get("shots", 0)), int(r.get("hits", 0)))
			if int(r.get("shots", 0)) > 0 and float(st["accuracy"]) > best_acc:
				best_acc = float(st["accuracy"])
				best_acc_name = String(r["name"])
		if best_acc_name != "":
			var acc_lbl := Label.new()
			acc_lbl.text = "Best accuracy: %s (%d%%)" % [best_acc_name, int(best_acc)]
			acc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			acc_lbl.add_theme_font_size_override("font_size", 20)
			acc_lbl.add_theme_color_override("font_color", Color(0.78, 0.82, 0.88))
			_end_box.add_child(acc_lbl)
			_end_box.move_child(acc_lbl, 2)
			_mvp_nodes.append(acc_lbl)
	for c in end_list.get_children():
		c.queue_free()
	var rank := 1
	for r in rows:
		var team_txt := ""
		if int(r["team"]) == 0:
			team_txt = " [RED]"
		elif int(r["team"]) == 1:
			team_txt = " [BLUE]"
		var st2: Dictionary = GameData.compute_stats(int(r["kills"]), int(r["deaths"]), int(r.get("shots", 0)), int(r.get("hits", 0)))
		var lbl := Label.new()
		if game_mode == 2:
			lbl.text = "%d. %s%s  -  Rounds: %d  Kills: %d  Deaths: %d  K/D: %.2f  ACC: %d%%" % [rank, String(r["name"]), team_txt, int(r.get("rounds", 0)), int(r["kills"]), int(r["deaths"]), float(st2["kd"]), int(st2["accuracy"])]
		else:
			lbl.text = "%d. %s%s  -  Kills: %d  Deaths: %d  K/D: %.2f  ACC: %d%%  Streak: %d" % [rank, String(r["name"]), team_txt, int(r["kills"]), int(r["deaths"]), float(st2["kd"]), int(st2["accuracy"]), int(r.get("streak", 0))]
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", r["color"])
		end_list.add_child(lbl)
		rank += 1
	end_rematch_btn.visible = multiplayer.is_server()
	end_panel.visible = true
	# QA-035: hide the touch controls under the end panel — the
	# RELOAD/GRENADE/WEAPON column sat on top of the stats rows and
	# the Rematch button (the sticks are dead input
	# once the match is over, so hiding them loses nothing).
	_reset_all_touch_state()
	_set_touch_controls_visible(false)
	audio.play("win")


# --- FX (impact / explosion) ---

func spawn_impact_fx(pos: Vector2, small: bool = false) -> void:
	var spr := Sprite2D.new()
	# Phase 4: Sky Brawl hit spark (small) / explosion sunburst
	# (large) instead of the old smoke/explosion sprites.
	spr.texture = SB_HIT_TEX if small else SB_EXPLOSION_TEX
	spr.position = pos
	spr.scale = Vector2(0.5, 0.5) if small else Vector2(0.7, 0.7)
	spr.modulate = Color(1, 1, 1, 0.9)
	fx_node.add_child(spr)
	var tw := create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.6, 0.25)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.25)
	tw.tween_callback(spr.queue_free)
	if not small:
		audio.play("hit")


func request_explosion(pos: Vector2, radius: float, damage: int, from_id: int, weapon_id: int = -1) -> void:
	# FX on every peer; damage only on the server.
	# weapon_id: the weapon that caused it (4 = rocket), -2 = grenade,
	# -1 = barrel/other explosion (kill feed label).
	_spawn_explosion_fx(pos, radius)
	if multiplayer.is_server():
		var killer = players_node.get_node_or_null(str(from_id))
		var event_id := next_damage_event_id()
		for child in players_node.get_children():
			if child.alive:
				var dist: float = child.global_position.distance_to(pos)
				if dist > radius:
					continue
				# Line of sight (GAP-12): a wall/crate between the
				# blast and the player blocks damage AND knockback.
				if not has_line_of_sight(pos, child.global_position):
					continue
				# Lethal check (same smooth falloff as
				# take_explosion_damage): the host credits the kill
				# when its explosion kills.
				var u := dist / radius
				var amount := int(round(damage * pow(1.0 - u * u, 2.0)))
				var lethal := int(child.health) - amount <= 0
				# RPC to yourself is not allowed: call directly in that case.
				# A peer that disconnected mid-flight gets no RPC either.
				if child.get_multiplayer_authority() == multiplayer.get_unique_id():
					child.take_explosion_damage(pos, radius, damage, from_id, event_id)
				elif multiplayer.get_peers().has(child.get_multiplayer_authority()):
					child.rpc_id(child.get_multiplayer_authority(), "take_explosion_damage", pos, radius, damage, from_id, event_id)
				if lethal:
					# QA-031 (T-56): one credit per victim per lock
					# window — the credit + feed announce go through
					# the lock, not direct (as in bullet.gd).
					try_credit_kill(from_id, child.peer_id, weapon_id)
				# Phase 4: hitmarker for the shooter/thrower on every
				# victim actually hurt, kill feed on every lethal hit
				# (self-kills included — no hitmarker for hurting
				# yourself, but the feed shows it).
				if amount > 0 and killer != null and from_id != child.peer_id:
					if killer.get_multiplayer_authority() == multiplayer.get_unique_id():
						killer.hit_confirm(amount, child.global_position, lethal)
					elif multiplayer.get_peers().has(killer.get_multiplayer_authority()):
						killer.rpc_id(killer.get_multiplayer_authority(), "hit_confirm", amount, child.global_position, lethal)
		# Chain: barrels caught in the blast explode too (GAP-64).
		for b in _barrels:
			if not bool(b["alive"]):
				continue
			var r: Rect2 = b["rect"]
			if r.get_center().distance_to(pos) <= radius:
				if has_line_of_sight(pos, r.get_center()):
					b["alive"] = false
					(b["sprite"] as Node2D).visible = false
					(b["shape"] as CollisionShape2D).set_deferred("disabled", true)
					rpc("barrel_destroyed_remote", _barrels.find(b))
					request_explosion(r.get_center(), PhysicsConfig.BARREL_BLAST_RADIUS,
						int(PhysicsConfig.BARREL_BLAST_DAMAGE), from_id)


func _spawn_explosion_fx(pos: Vector2, radius: float) -> void:
	var spr := Sprite2D.new()
	spr.texture = FIREBALL_TEX
	spr.position = pos
	var target := radius * 2.0 / 70.0
	spr.scale = Vector2(0.4, 0.4)
	fx_node.add_child(spr)
	var tw := create_tween()
	tw.tween_property(spr, "scale", Vector2(target, target), 0.3)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.45)
	tw.tween_callback(spr.queue_free)
	var spr2 := Sprite2D.new()
	spr2.texture = SMOKE_TEX
	spr2.position = pos + Vector2(0, -20)
	spr2.scale = Vector2(1.2, 1.2)
	spr2.modulate = Color(1, 1, 1, 0.7)
	fx_node.add_child(spr2)
	var tw2 := create_tween()
	tw2.tween_property(spr2, "position:y", spr2.position.y - 60.0, 0.8)
	tw2.parallel().tween_property(spr2, "modulate:a", 0.0, 0.8)
	tw2.tween_callback(spr2.queue_free)
	# GAP-24: white flash + expanding shockwave ring + debris.
	# Visual-only; no damage code anywhere in this FX.
	var flash := Polygon2D.new()
	var fpts := PackedVector2Array()
	for i in 16:
		var a := TAU * float(i) / 16.0
		fpts.append(Vector2(cos(a), sin(a)) * radius * 0.5)
	flash.polygon = fpts
	flash.color = Color(1, 1, 1, 0.95)
	flash.position = pos
	fx_node.add_child(flash)
	var twf := create_tween()
	twf.tween_property(flash, "modulate:a", 0.0, 0.08)
	twf.tween_callback(flash.queue_free)
	var ring := Line2D.new()
	var rpts := PackedVector2Array()
	for i in 33:
		var a := TAU * float(i) / 32.0
		rpts.append(Vector2(cos(a), sin(a)) * 10.0)
	ring.points = rpts
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.8, 0.3, 0.9)
	ring.position = pos
	fx_node.add_child(ring)
	var twr := create_tween()
	twr.tween_property(ring, "scale", Vector2(radius / 10.0, radius / 10.0), 0.35)
	twr.parallel().tween_property(ring, "modulate:a", 0.0, 0.35)
	twr.tween_callback(ring.queue_free)
	for i in 8:
		var deb := Polygon2D.new()
		deb.polygon = PackedVector2Array([Vector2(-3, -3), Vector2(3, -3), Vector2(3, 3), Vector2(-3, 3)])
		deb.color = Color(0.9, 0.5, 0.15, 0.9)
		deb.position = pos
		fx_node.add_child(deb)
		var ang := randf() * TAU
		var dst := randf_range(40.0, radius)
		var twd := create_tween()
		twd.tween_property(deb, "position", pos + Vector2(cos(ang), sin(ang)) * dst, 0.4)
		twd.parallel().tween_property(deb, "modulate:a", 0.0, 0.4)
		twd.tween_callback(deb.queue_free)
	audio.play("explosion")


# --- Headless smoke test: drives the REAL joystick API with simulated
# touches (fake touch indices 950/951), so the test exercises the same
# press/drag/release path a phone uses. Verifies movement, facing,
# animation, stick-up jump/jetpack, aim and shooting follow the sticks.

func _smoke_set_move(offset) -> void:
	# offset: Vector2 from the move stick centre, or null to release.
	if offset == null:
		if _smoke_move_idx != -1:
			_on_touch_release(_smoke_move_idx)
			_smoke_move_idx = -1
		return
	var pos: Vector2 = move_stick.get_global_rect().get_center() + offset
	if _smoke_move_idx == -1:
		_smoke_move_idx = 950
		_on_touch_press(_smoke_move_idx, pos)
	else:
		_on_touch_drag(_smoke_move_idx, pos)


func _smoke_set_aim(offset) -> void:
	# offset: Vector2 from the aim stick centre, or null to release.
	if offset == null:
		if _smoke_aim_idx != -1:
			_on_touch_release(_smoke_aim_idx)
			_smoke_aim_idx = -1
		_smoke_fire_owns_aim = false
		return
	var pos: Vector2 = aim_stick.get_global_rect().get_center() + offset
	if _smoke_aim_idx == -1:
		_smoke_aim_idx = 951
		_on_touch_press(_smoke_aim_idx, pos)
	else:
		_on_touch_drag(_smoke_aim_idx, pos)


func _smoke_set_fire(held: bool) -> void:
	# v3.2: firing comes from the AIM stick — "fire" means holding the
	# aim stick deflected. If the aim stick is already held by
	# _smoke_set_aim, firing is already happening; otherwise hold it
	# at a fixed firing offset (60,0) so the perf test can churn
	# bullets without an aim driver. Ownership is tracked so a
	# release here never drops an aim press owned by _smoke_set_aim.
	if held:
		if _smoke_aim_idx == -1:
			_smoke_aim_idx = 951
			_smoke_fire_owns_aim = true
			_on_touch_press(_smoke_aim_idx, aim_stick.get_global_rect().get_center() + Vector2(60, 0))
	else:
		if _smoke_fire_owns_aim and _smoke_aim_idx != -1:
			_on_touch_release(_smoke_aim_idx)
			_smoke_aim_idx = -1
			_smoke_fire_owns_aim = false


func _update_smoke_test(delta: float) -> void:
	_smoke_elapsed += delta
	var phase := int(_smoke_elapsed / 1.0)
	# Phases (1s each): 0-1 idle, 2-3 move right, 4 small push, 5 move left,
	# 6 release, 7-8 stick-up jump+jetpack, 9 land, 10-11 aim up-right+fire,
	# 12 aim left+fire, 13 tiny push below the dead zone (no aim, no fire),
	# 14 grenade, 15 weapon switch, 16+ summary.
	if phase != _smoke_phase:
		_smoke_phase = phase
		_log_smoke_phase(phase)
	# Teleport to open sky before the jump test (no platform overhead).
	if _smoke_elapsed >= 6.5 and _smoke_elapsed < 7.0:
		var lp0 = _get_local_player()
		if lp0 != null and lp0.position.x < 2000.0:
			lp0.position = Vector2(2100, 1350)
			lp0.sync_position = lp0.position
			lp0.velocity = Vector2.ZERO
	# Drive the simulated sticks (real press/drag/release path).
	if _smoke_elapsed >= 2.0 and _smoke_elapsed < 4.0:
		_smoke_set_move(Vector2(60, 0))
	elif _smoke_elapsed >= 4.0 and _smoke_elapsed < 5.0:
		_smoke_set_move(Vector2(18, 0))
	elif _smoke_elapsed >= 5.0 and _smoke_elapsed < 6.0:
		_smoke_set_move(Vector2(-60, 0))
	elif _smoke_elapsed >= 7.0 and _smoke_elapsed < 9.0:
		_smoke_set_move(Vector2(0, -60))
	else:
		_smoke_set_move(null)
	if _smoke_elapsed >= 10.0 and _smoke_elapsed < 12.0:
		_smoke_set_aim(Vector2(42, -42))
		_smoke_set_fire(true)
	elif _smoke_elapsed >= 12.0 and _smoke_elapsed < 13.0:
		_smoke_set_aim(Vector2(-60, 0))
		_smoke_set_fire(true)
	elif _smoke_elapsed >= 13.0 and _smoke_elapsed < 14.0:
		# v3.2: there is no aim-without-fire any more — any deflection
		# past the dead zone fires. This phase now pushes (0,10),
		# BELOW the 0.20 dead zone, so the stick stays centred: no
		# aim, no fire (dead-zone check).
		_smoke_set_aim(Vector2(0, 10))
		_smoke_set_fire(false)
	else:
		_smoke_set_aim(null)
		_smoke_set_fire(false)
	# Propagate the stick vectors into touch_move_vec / touch_firing
	# (normally done by _update_touch_state in _process).
	_update_touch_state()
	if _smoke_elapsed >= 11.5 and not _smoke_shot_aim_done:
		_smoke_shot_aim_done = true
		_capture_shot("user://shot_aim.png")
	if _smoke_elapsed >= 16.05 and not _smoke_shot_boom_done:
		_smoke_shot_boom_done = true
		_capture_shot("user://shot_explosion.png")
	if _smoke_elapsed > 18.0:
		print("SMOKE: quitting after screenshots")
		get_tree().quit()
		return
	if _smoke_elapsed >= 14.0 and not _smoke_grenade_done:
		_smoke_grenade_done = true
		var lp = _get_local_player()
		if lp != null:
			lp.throw_grenade()
			print("SMOKE: grenade thrown, grenades now=", lp.grenades)
	if _smoke_elapsed >= 15.0 and not _smoke_switch_done:
		_smoke_switch_done = true
		var lp2 = _get_local_player()
		if lp2 != null:
			lp2.give_pickup(1)
			print("SMOKE: pickup gave weapon=", lp2.weapon, " (", lp2.WEAPONS[lp2.weapon]["name"], "), owned=", lp2.owned_weapons())
			lp2.switch_weapon()
			print("SMOKE: weapon switched to=", lp2.weapon, " (", lp2.WEAPONS[lp2.weapon]["name"], ")")
	if _smoke_elapsed > 17.0 and not _smoke_logged:
		_smoke_logged = true
		var lp3 = _get_local_player()
		print("SMOKE DONE: players=", players_node.get_child_count(),
			" local_alive=", lp3 != null and lp3.alive,
			" shots_fired=", lp3._shots_fired if lp3 != null else -1,
			" bullets=", bullets_node.get_child_count(),
			" grenades_node=", grenades_node.get_child_count(),
			" fuel=", lp3.fuel if lp3 != null else -1.0,
			" anim=", lp3._current_anim if lp3 != null else "none")


func _capture_shot(path: String) -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(path)
	print("SMOKE: screenshot ", path, " err=", err, " size=", img.get_size())


# v3.2 GAME-SCREENSHOT MODE (--game-shots): staged captures of the
# in-game screens for the visual review (THEME_SPEC.md §9) — the
# countdown, the HUD (with a kill-feed chip), pause, scoreboard and
# the end screen. Runs as auto-host; the countdown is NOT skipped
# (this flag is deliberately left out of _is_test_mode in _ready).
# Stages are 1 s apart so the async capture (2 frames) lands while
# the screen is still in the staged state.
func _update_gameshots(delta: float) -> void:
	_gs_timer += delta
	var stage := int(_gs_timer / 1.0)
	if stage == _gs_stage:
		return
	_gs_stage = stage
	match stage:
		0:
			pass # countdown "3" is showing
		1:
			_capture_shot("user://shot_countdown.png")
		4:
			# Countdown done — HUD + hint visible. Seed one kill-feed
			# entry so the chip renders in the HUD shot.
			_add_kill_feed_entry(1, 1, 0)
			_capture_shot("user://shot_hud.png")
		5:
			if not get_tree().paused:
				_toggle_pause()
			_capture_shot("user://shot_pause.png")
		6:
			if get_tree().paused:
				_toggle_pause()
			_on_score_pressed()
			_capture_shot("user://shot_scoreboard.png")
		7:
			if scoreboard_panel.visible:
				_on_score_pressed()
			_end_match("You", "screenshot — first to 10 kills")
			_capture_shot("user://shot_end.png")
		8:
			print("GAMESHOTS DONE")
			get_tree().quit()


func _log_smoke_phase(phase: int) -> void:
	var lp = _get_local_player()
	if lp == null:
		print("SMOKE phase ", phase, ": no local player yet")
		return
	var gun_rot := rad_to_deg(lp._gun.rotation) if lp._gun != null else -999.0
	print("SMOKE phase ", phase, ": anim=", lp._current_anim,
		" facing=", lp.facing,
		" aim_deg=", round(rad_to_deg(lp.aim_angle)),
		" gun_rot_deg=", round(gun_rot),
		" vel=", Vector2(round(lp.velocity.x), round(lp.velocity.y)),
		" pos=", Vector2(round(lp.position.x), round(lp.position.y)),
		" on_floor=", lp.is_on_floor(),
		" fuel=", round(lp.fuel),
		" alive=", lp.alive)


# --- Joystick acceptance tests (--joystick-test) ---
# Drives the REAL touch handlers with simulated touches (fake indices
# 900 = move, 901 = aim) and checks every acceptance criterion from the
# left-joystick spec plus the v2.2 fire-button fix (QA-016). Each step:
# setup runs once, then after `wait` seconds the check runs and the
# result is printed as "JOYTEST <name>: PASS/FAIL — <detail>".
# Run: xvfb-run -a godot --path . --auto-host --joystick-test

func _update_joytest(delta: float) -> void:
	if _joy_done:
		return
	var lp = _get_local_player()
	if lp == null:
		_joy_timer += delta
		if _joy_timer > 5.0:
			_joy_done = true
			print("JOYTEST DONE: 0/0 passed — no local player spawned")
			get_tree().quit()
		return
	if _joy_steps.is_empty():
		_joytest_build_steps()
		_joy_step = 0
		_joy_in_step = false
		_joy_timer = 0.0
	if _joy_step >= _joy_steps.size():
		_joy_done = true
		print("JOYTEST DONE: %d/%d passed" % [_joy_passed, _joy_passed + _joy_failed])
		get_tree().quit()
		return
	var step: Dictionary = _joy_steps[_joy_step]
	if not _joy_in_step:
		(step["setup"] as Callable).call()
		_joy_in_step = true
		_joy_timer = float(step["wait"])
	_joy_timer -= delta
	if _joy_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_joy_passed += 1
		else:
			_joy_failed += 1
		print("JOYTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_joy_step += 1
		_joy_in_step = false
		_joy_timer = 0.0


func _joytest_build_steps() -> void:
	_joy_steps = [
		{"name": "PRESS-LEFT", "wait": 0.6, "setup": _jt_s_press_left, "check": _jt_c_press_left},
		{"name": "PRESS-RIGHT", "wait": 0.6, "setup": _jt_s_press_right, "check": _jt_c_press_right},
		{"name": "PRESS-UP-JUMP", "wait": 0.4, "setup": _jt_s_press_up, "check": _jt_c_press_up},
		{"name": "RELEASE-STOPS", "wait": 0.5, "setup": _jt_s_release_move, "check": _jt_c_release_stops},
		{"name": "MOVE-RELEASE-NO-LEFT", "wait": 0.8, "setup": _jt_s_move_right_mouse, "check": _jt_c_move_release_no_left},
		{"name": "AIM-RELEASE-NO-LEFT", "wait": 0.8, "setup": _jt_s_aim_right_mouse, "check": _jt_c_aim_release_no_left},
		{"name": "FUEL-STABLE", "wait": 0.5, "setup": _jt_s_noop, "check": _jt_c_fuel_stable},
		{"name": "PRESS-DOWN-FAST-FALL", "wait": 0.4, "setup": _jt_s_press_down, "check": _jt_c_press_down},
		{"name": "DIAG-UP-RIGHT", "wait": 0.5, "setup": _jt_s_diag_up_right, "check": _jt_c_diag_up_right},
		{"name": "DIAG-SPEED", "wait": 0.3, "setup": _jt_s_noop, "check": _jt_c_diag_speed},
		{"name": "KNOB-CLAMP", "wait": 0.3, "setup": _jt_s_knob_clamp, "check": _jt_c_knob_clamp},
		{"name": "MULTI-TOUCH", "wait": 0.6, "setup": _jt_s_multi_touch, "check": _jt_c_multi_touch},
		{"name": "RELEASE-MOVE-ONLY", "wait": 0.4, "setup": _jt_s_release_move_only, "check": _jt_c_release_move_only},
		{"name": "RELEASE-FIRE-STOPS-FIRE", "wait": 0.6, "setup": _jt_s_release_fire, "check": _jt_c_release_fire_stops_fire},
		{"name": "FOCUS-OUT-SETUP", "wait": 0.5, "setup": _jt_s_press_aim_fire, "check": _jt_c_firing_on},
		{"name": "FOCUS-OUT-RESET", "wait": 0.4, "setup": _jt_s_focus_out, "check": _jt_c_focus_out_reset},
		{"name": "FIRE-AFTER-DEATH", "wait": 0.6, "setup": _jt_s_kill_and_aim_fire, "check": _jt_c_fire_after_death},
		{"name": "WAIT-RESPAWN", "wait": 3.5, "setup": _jt_s_noop, "check": _jt_c_respawned},
		{"name": "FIRE-WHILE-PAUSED-SETUP", "wait": 0.4, "setup": _jt_s_press_aim_fire, "check": _jt_c_firing_on},
		{"name": "FIRE-WHILE-PAUSED", "wait": 0.6, "setup": _jt_s_pause, "check": _jt_c_fire_while_paused},
		{"name": "FIRE-AFTER-MATCH-END", "wait": 0.6, "setup": _jt_s_match_end_aim_fire, "check": _jt_c_fire_after_match_end},
		{"name": "STICK-UP-NO-REJUMP", "wait": 4.0, "setup": _jt_s_hold_up_long, "check": _jt_c_no_rejump},
		{"name": "RESOLUTION-1920", "wait": 0.5, "setup": _jt_s_resize_1920, "check": _jt_c_resolution_1920},
		{"name": "RESOLUTION-2400", "wait": 0.5, "setup": _jt_s_resize_2400, "check": _jt_c_resolution_2400},
		{"name": "MOVE-RELEASE-NO-LEFT-2400", "wait": 0.5, "setup": _jt_s_noop, "check": _jt_c_move_release_no_left_2400},
	]


# --- Joystick-test helpers: simulated touches through the real handlers ---

func _jt_move_center() -> Vector2:
	return move_stick.get_global_rect().get_center()


func _jt_aim_center() -> Vector2:
	return aim_stick.get_global_rect().get_center()


func _jt_press_move(offset: Vector2) -> void:
	_on_touch_press(900, _jt_move_center() + offset)


func _jt_drag_move(offset: Vector2) -> void:
	_on_touch_drag(900, _jt_move_center() + offset)


func _jt_release_move() -> void:
	_on_touch_release(900)


func _jt_press_aim(offset: Vector2) -> void:
	_on_touch_press(901, _jt_aim_center() + offset)


func _jt_drag_aim(offset: Vector2) -> void:
	_on_touch_drag(901, _jt_aim_center() + offset)


func _jt_release_aim() -> void:
	_on_touch_release(901)


# v3.2: the FIRE button is gone — "fire" means deflecting the AIM
# stick (fake touch index 902). If the aim stick is already held by
# _jt_press_aim (901), pressing "fire" is a no-op (it already fires);
# otherwise the 902 press owns the aim stick until released.
var _jt_fire_owns_aim: bool = false


func _jt_press_fire() -> void:
	if not aim_stick.is_active():
		_jt_fire_owns_aim = true
		_on_touch_press(902, _jt_aim_center() + Vector2(60, 0))


func _jt_release_fire() -> void:
	if _jt_fire_owns_aim:
		_on_touch_release(902)
		_jt_fire_owns_aim = false


func _jt_press_aim_fire() -> void:
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_lp():
	return _get_local_player()


# --- Step setups / checks (each returns [passed: bool, detail: String]) ---

func _jt_s_noop() -> void:
	pass


func _jt_s_press_left() -> void:
	# Phase 5: spawn#0 has a solid cover crate ~90 px to its LEFT
	# (cover within 150 px of every spawn), so pressing left straight
	# from the spawn pins the player against it after ~58 px. The
	# stick itself is fine — give it a clear run first (see
	# _jt_teleport_clear_left).
	_jt_teleport_clear_left()
	_jt_press_move(Vector2(-50, 0))


# Phase 5 — joystick-test helper: stand 200 px right of spawn#0.
# The run-up rule keeps 360 px clear right of spawn#0 on every map,
# so from there the left run is ~258 px (cover face to the left is
# ~90 px left of the spawn) — enough for the 0.6 s press checks.
func _jt_teleport_clear_left() -> void:
	var lp = _jt_lp()
	if lp == null:
		return
	var s0: Vector2 = (MAPS[map_id]["spawns"] as Array)[0]
	var p := Vector2(s0.x + 200.0, s0.y)
	lp.position = p
	lp.sync_position = p
	lp.velocity = Vector2.ZERO


func _jt_c_press_left() -> Array:
	var lp = _jt_lp()
	var v := touch_move_vec
	var ok: bool = v.x < -0.5 and absf(v.y) < 0.15 and lp.velocity.x < -50.0 and lp.facing == -1
	return [ok, "vec=%s vel.x=%d facing=%d anim=%s" % [v, round(lp.velocity.x), lp.facing, lp._current_anim]]


func _jt_s_press_right() -> void:
	_jt_drag_move(Vector2(50, 0))


func _jt_c_press_right() -> Array:
	var lp = _jt_lp()
	var v := touch_move_vec
	var ok: bool = v.x > 0.5 and absf(v.y) < 0.15 and lp.velocity.x > 50.0 and lp.facing == 1
	return [ok, "vec=%s vel.x=%d facing=%d anim=%s" % [v, round(lp.velocity.x), lp.facing, lp._current_anim]]


func _jt_s_press_up() -> void:
	_joy_pos_before = _jt_lp().position
	_jt_drag_move(Vector2(0, -55))


func _jt_c_press_up() -> Array:
	var lp = _jt_lp()
	var v := touch_move_vec
	# Up past the threshold: jumped off the floor and is thrusting
	# (fuel drains only while the jetpack is actually thrusting).
	var ok: bool = v.y < -0.5 and not lp.is_on_floor() and lp.position.y < _joy_pos_before.y - 20.0 and lp.fuel < 98.0
	return [ok, "vec=%s on_floor=%s y=%d (was %d) fuel=%d jetpacking=%s" % [v, lp.is_on_floor(), round(lp.position.y), round(_joy_pos_before.y), round(lp.fuel), lp._jetpacking]]


func _jt_s_release_move() -> void:
	_jt_release_move()


func _jt_c_release_stops() -> Array:
	var lp = _jt_lp()
	_joy_fuel_before = lp.fuel
	var ok: bool = touch_move_vec == Vector2.ZERO and move_stick.get_knob_offset().length() < 2.0 and not lp._jetpacking and absf(lp.velocity.x) < 60.0
	return [ok, "vec=%s knob=%.1f jetpacking=%s vel.x=%d fuel=%d" % [touch_move_vec, move_stick.get_knob_offset().length(), lp._jetpacking, round(lp.velocity.x), round(lp.fuel)]]


# --- QA-054 regression: push RIGHT, release, player must NOT turn left.
# On a real phone Godot emulates a mouse from every touch, so a MOVE
# stick hold also read as a held left mouse button at the finger's
# position — and the mouse-aim fallback in player.gd aimed the gun at
# that left-half point (LEFT) while the player ran RIGHT. Facing
# follows the aim, so the player faced left for the whole move and
# stayed facing left after release. These steps reproduce the phone
# exactly: a real touch hold PLUS an injected emulated mouse press at
# the same point (Input.parse_input_event, the OS path), released
# together 0.3 s later; the check runs ~0.5 s after release (30
# frames) and asserts no leftward velocity and no facing flip. The
# check REQUIRES the mouse press to have been seen during the hold
# (_joy_mouse_seen) — without it the test would pass vacuously if
# the injection ever stopped working.
func _jt_inject_mouse_press(canvas_pos: Vector2) -> void:
	var vp := _to_viewport_pos(canvas_pos)
	# warp_mouse sets the viewport's mouse POSITION deterministically;
	# parse_input_event alone sets the button state but leaves
	# get_mouse_position() at its default (screen centre) in this
	# headless run, so the position assertion would read the centre.
	get_viewport().warp_mouse(vp)
	var btn := InputEventMouseButton.new()
	btn.button_index = MOUSE_BUTTON_LEFT
	btn.pressed = true
	btn.position = vp
	Input.parse_input_event(btn)


func _jt_inject_mouse_release() -> void:
	var btn := InputEventMouseButton.new()
	btn.button_index = MOUSE_BUTTON_LEFT
	btn.pressed = false
	btn.position = get_viewport().get_mouse_position()
	Input.parse_input_event(btn)


func _jt_release_move_mouse() -> void:
	# Record the emulated-mouse state BEFORE releasing it: the
	# check needs proof the mouse press was really down mid-hold.
	_joy_mouse_seen = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_joy_mouse_pos_seen = get_viewport().get_mouse_position()
	_jt_release_move()
	_jt_inject_mouse_release()


func _jt_release_aim_mouse() -> void:
	_joy_mouse_seen = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_joy_mouse_pos_seen = get_viewport().get_mouse_position()
	_jt_release_aim()
	_jt_inject_mouse_release()


func _jt_s_move_right_mouse() -> void:
	var lp = _jt_lp()
	lp.position = Vector2(2100, 1350)
	lp.velocity = Vector2.ZERO
	_joy_aim_before = lp.aim_angle
	_joy_mouse_seen = false
	_jt_press_move(Vector2(60, 0))
	_jt_inject_mouse_press(_jt_move_center() + Vector2(60, 0))
	get_tree().create_timer(0.3).timeout.connect(_jt_release_move_mouse)


func _jt_c_move_release_no_left() -> Array:
	var lp = _jt_lp()
	var centre_x := get_viewport().get_visible_rect().size.x * 0.5
	var ok: bool = _joy_mouse_seen and _joy_mouse_pos_seen.x < centre_x \
		and lp.facing == 1 and lp.velocity.x >= -1.0 \
		and touch_move_vec == Vector2.ZERO and move_stick.get_knob_offset().length() < 2.0 \
		and cos(lp.aim_angle) > 0.5
	return [ok, "mouse_seen=%s mouse_pos=%s (want left of centre %.0f) facing=%d vel.x=%d vec=%s knob=%.1f aim=%.2f (want facing 1, no leftward vel, vec 0, aim right)" % [_joy_mouse_seen, _joy_mouse_pos_seen, centre_x, lp.facing, round(lp.velocity.x), touch_move_vec, move_stick.get_knob_offset().length(), lp.aim_angle]]


func _jt_s_aim_right_mouse() -> void:
	var lp = _jt_lp()
	lp.position = Vector2(2100, 1350)
	lp.velocity = Vector2.ZERO
	_joy_aim_before = lp.aim_angle
	_joy_mouse_seen = false
	_jt_press_aim(Vector2(60, 0))
	_jt_inject_mouse_press(_jt_aim_center() + Vector2(60, 0))
	get_tree().create_timer(0.3).timeout.connect(_jt_release_aim_mouse)


func _jt_c_aim_release_no_left() -> Array:
	var lp = _jt_lp()
	var centre_x := get_viewport().get_visible_rect().size.x * 0.5
	var ok: bool = _joy_mouse_seen and _joy_mouse_pos_seen.x > centre_x \
		and lp.facing == 1 and lp.velocity.x >= -5.0 \
		and not touch_firing and touch_aim == Vector2.ZERO \
		and cos(lp.aim_angle) > 0.5
	return [ok, "mouse_seen=%s mouse_pos=%s (want right of centre %.0f) facing=%d vel.x=%d firing=%s aim_vec=%s aim=%.2f (want facing 1, not firing, aim right)" % [_joy_mouse_seen, _joy_mouse_pos_seen, centre_x, lp.facing, round(lp.velocity.x), touch_firing, touch_aim, lp.aim_angle]]


func _jt_s_resize_2400() -> void:
	# Same clear floor as the 1280 steps: (2100, 1350) has a clear
	# run right to the map edge on map 0.
	var lp = _jt_lp()
	lp.position = Vector2(2100, 1350)
	lp.velocity = Vector2.ZERO
	get_window().size = Vector2(2400, 1080)
	_joy_mouse_seen = false
	_jt_press_move(Vector2(60, 0))
	_jt_inject_mouse_press(_jt_move_center() + Vector2(60, 0))


func _jt_c_resolution_2400() -> Array:
	var lp = _jt_lp()
	var vp_size := get_viewport().get_visible_rect().size
	# Same stick math at phone aspect: rightward vector, moving right.
	# The resize reports the logical canvas size, which expands only
	# in aspect (1600x720 is the 2400x1080 aspect 2.22) — assert the
	# aspect, not raw window pixels. Release here (touch + emulated
	# mouse together); the next step observes the 30 frames after
	# release at this resolution.
	var ok: bool = absf(vp_size.x / vp_size.y - 2400.0 / 1080.0) < 0.05 and touch_move_vec.x > 0.5 and lp.velocity.x > 50.0
	_jt_release_move_mouse()
	return [ok, "viewport=%s vec=%s vel.x=%d" % [vp_size, touch_move_vec, round(lp.velocity.x)]]


func _jt_c_move_release_no_left_2400() -> Array:
	var lp = _jt_lp()
	var centre_x := get_viewport().get_visible_rect().size.x * 0.5
	var ok: bool = _joy_mouse_seen and _joy_mouse_pos_seen.x < centre_x \
		and lp.facing == 1 and lp.velocity.x >= -1.0 \
		and touch_move_vec == Vector2.ZERO and move_stick.get_knob_offset().length() < 2.0 \
		and cos(lp.aim_angle) > 0.5
	get_window().size = Vector2(1280, 720)
	return [ok, "mouse_seen=%s mouse_pos=%s (want left of centre %.0f) facing=%d vel.x=%d vec=%s knob=%.1f aim=%.2f at 2400x1080 (want facing 1, no leftward vel, vec 0, aim right)" % [_joy_mouse_seen, _joy_mouse_pos_seen, centre_x, lp.facing, round(lp.velocity.x), touch_move_vec, move_stick.get_knob_offset().length(), lp.aim_angle]]


func _jt_c_fuel_stable() -> Array:
	var lp = _jt_lp()
	# No thrust input: fuel must not decrease (it refills on the ground,
	# stays put in the air — either way it never goes down).
	var ok: bool = lp.fuel >= _joy_fuel_before - 0.5
	return [ok, "fuel=%d (was %d)" % [round(lp.fuel), round(_joy_fuel_before)]]


func _jt_s_press_down() -> void:
	var lp = _jt_lp()
	lp.position = Vector2(2100, 900)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_jt_press_move(Vector2(0, 55))


func _jt_c_press_down() -> Array:
	var lp = _jt_lp()
	var v := touch_move_vec
	# Down past the threshold while airborne: fast fall (vy well above
	# the normal-fall value of ~560 after 0.4 s).
	var ok: bool = v.y > 0.5 and lp.velocity.y > 700.0
	_jt_release_move()
	return [ok, "vec=%s vel.y=%d" % [v, round(lp.velocity.y)]]


func _jt_s_diag_up_right() -> void:
	var lp = _jt_lp()
	# Open sky above (2100, 1350): the platform at (300, 1180) sits
	# directly over (300, 1350), so a player teleported there pins
	# under it and vel.y reads 0 even though it is jetpacking.
	lp.position = Vector2(2100, 1350)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_jt_press_move(Vector2(42, -42))


func _jt_c_diag_up_right() -> Array:
	var lp = _jt_lp()
	var v := touch_move_vec
	var ok: bool = v.x > 0.55 and v.x < 0.85 and v.y < -0.55 and v.y > -0.85 and v.length() > 0.9 and v.length() <= 1.01 and lp.velocity.x > 50.0 and lp.velocity.y < 0.0
	return [ok, "vec=%s len=%.2f vel=(%d,%d)" % [v, v.length(), round(lp.velocity.x), round(lp.velocity.y)]]


func _jt_c_diag_speed() -> Array:
	var lp = _jt_lp()
	var v := touch_move_vec
	# Diagonal input is normalized: horizontal speed stays below the
	# full-run speed (330) instead of 330 * sqrt(2).
	var ok: bool = v.length() <= 1.01 and absf(lp.velocity.x) > 150.0 and absf(lp.velocity.x) < 300.0
	_jt_release_move()
	return [ok, "vec.len=%.2f vel.x=%d" % [v.length(), round(lp.velocity.x)]]


func _jt_s_knob_clamp() -> void:
	# Press far outside the stick: the knob must clamp to the base.
	# v3.3 QA-052: offset is 400, not 500 — touches are routed by
	# screen half, and the move stick's centre moved right to x=165,
	# so +500 would land at x=665, past the 640 half-line, and grab
	# the AIM stick instead. +400 (x=565) stays on the left half
	# while still being far outside the 60 px base radius.
	_jt_press_move(Vector2(400, 0))


func _jt_c_knob_clamp() -> Array:
	var v := touch_move_vec
	var ok: bool = move_stick.get_knob_offset().length() <= 60.5 and v.length() <= 1.01 and v.x > 0.9
	_jt_release_move()
	return [ok, "knob=%.1f vec=%s" % [move_stick.get_knob_offset().length(), v]]


func _jt_s_multi_touch() -> void:
	_joy_shots_before = _jt_lp()._shots_fired
	_jt_press_move(Vector2(60, 0))
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_c_multi_touch() -> Array:
	var lp = _jt_lp()
	# v3.2: move + aim are two independent fingers; deflecting the aim
	# stick fires (no separate FIRE finger any more).
	var ok: bool = move_stick.is_active() and aim_stick.is_active() and touch_firing and lp._shots_fired > _joy_shots_before
	return [ok, "move_active=%s aim_active=%s firing=%s shots=%d (was %d)" % [move_stick.is_active(), aim_stick.is_active(), touch_firing, lp._shots_fired, _joy_shots_before]]


func _jt_s_release_move_only() -> void:
	_jt_release_move()


func _jt_c_release_move_only() -> Array:
	# Releasing the move finger must NOT disturb the aim finger —
	# the aim stick stays held and keeps firing.
	var ok: bool = touch_move_vec == Vector2.ZERO and not move_stick.is_active() and aim_stick.is_active() and touch_firing
	return [ok, "move_vec=%s move_active=%s aim_active=%s firing=%s" % [touch_move_vec, move_stick.is_active(), aim_stick.is_active(), touch_firing]]


func _jt_s_release_fire() -> void:
	# v3.2: "release fire" means releasing the AIM stick — firing
	# stops the moment the stick returns to centre.
	_jt_release_aim()
	# QA-029: refresh the touch state NOW, then capture the baseline.
	# touch_firing only updates in _update_touch_state(), so without
	# this a physics step between the release and the next _process
	# could still see the stale "firing" value and fire one shot.
	_update_touch_state()
	_joy_shots_before = _jt_lp()._shots_fired


func _jt_c_release_fire_stops_fire() -> Array:
	# v3.2: releasing the aim stick stops the shooting (there is no
	# separate FIRE finger any more — the aim stick IS the fire control).
	var lp = _jt_lp()
	var ok: bool = not touch_firing and not aim_stick.is_active() and lp._shots_fired == _joy_shots_before
	return [ok, "firing=%s aim_active=%s shots=%d (was %d)" % [touch_firing, aim_stick.is_active(), lp._shots_fired, _joy_shots_before]]


func _jt_s_press_aim() -> void:
	_jt_press_aim(Vector2(42, -42))


func _jt_s_press_aim_fire() -> void:
	_jt_press_aim_fire()


func _jt_c_firing_on() -> Array:
	var lp = _jt_lp()
	_joy_shots_before = lp._shots_fired
	var ok: bool = touch_firing and aim_stick.is_active()
	return [ok, "firing=%s aim_active=%s shots=%d" % [touch_firing, aim_stick.is_active(), lp._shots_fired]]


func _jt_s_focus_out() -> void:
	# Simulate the OS interrupting the touch (app switch, notification
	# shade): the engine notifies every node; the game and the sticks
	# must all reset. No release event is ever delivered for this touch.
	_notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	move_stick._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	aim_stick._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	# QA-029: capture the shot baseline AFTER the reset, not in the
	# previous step's check — a shot can legitimately fire in the one
	# frame between that check and this reset (the finger is still
	# down until the OS notifies), which made the test flaky. Refresh
	# the touch state first so no physics step after this setup can
	# still see the stale "firing" value.
	_update_touch_state()
	_joy_shots_before = _jt_lp()._shots_fired


func _jt_c_focus_out_reset() -> Array:
	var lp = _jt_lp()
	# A stale drag with the old aim touch index must NOT re-activate it.
	_on_touch_drag(901, _jt_aim_center() + Vector2(42, -42))
	var ok: bool = not touch_firing and touch_move_vec == Vector2.ZERO and touch_aim == Vector2.ZERO and not move_stick.is_active() and not aim_stick.is_active() and lp._shots_fired == _joy_shots_before
	return [ok, "firing=%s move_vec=%s aim_vec=%s move_active=%s aim_active=%s shots=%d (was %d)" % [touch_firing, touch_move_vec, touch_aim, move_stick.is_active(), aim_stick.is_active(), lp._shots_fired, _joy_shots_before]]


func _jt_s_kill_and_aim_fire() -> void:
	var lp = _jt_lp()
	lp.take_damage(500, 1)
	_joy_shots_before = lp._shots_fired
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_c_fire_after_death() -> Array:
	var lp = _jt_lp()
	var ok: bool = not lp.alive and lp._shots_fired == _joy_shots_before
	_jt_release_aim()
	_jt_release_fire()
	return [ok, "alive=%s shots=%d (was %d)" % [lp.alive, lp._shots_fired, _joy_shots_before]]


func _jt_c_respawned() -> Array:
	var lp = _jt_lp()
	var ok: bool = lp.alive and lp.health == 100
	return [ok, "alive=%s health=%d" % [lp.alive, lp.health]]


func _jt_s_pause() -> void:
	_joy_shots_before = _jt_lp()._shots_fired
	get_tree().paused = true


func _jt_c_fire_while_paused() -> Array:
	var lp = _jt_lp()
	var ok: bool = lp._shots_fired == _joy_shots_before
	get_tree().paused = false
	_jt_release_aim()
	_jt_release_fire()
	return [ok, "shots=%d (was %d) paused_resumed_ok" % [lp._shots_fired, _joy_shots_before]]


func _jt_s_match_end_aim_fire() -> void:
	match_over = true
	_joy_shots_before = _jt_lp()._shots_fired
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_c_fire_after_match_end() -> Array:
	var lp = _jt_lp()
	var ok: bool = lp._shots_fired == _joy_shots_before
	match_over = false
	_jt_release_aim()
	_jt_release_fire()
	return [ok, "shots=%d (was %d)" % [lp._shots_fired, _joy_shots_before]]


func _jt_s_hold_up_long() -> void:
	var lp = _jt_lp()
	lp.position = Vector2(300, 1350)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	# Hold the stick up for the whole 4 s: jump, jetpack until the fuel
	# runs out, fall back down and land — still holding up.
	_jt_press_move(Vector2(0, -55))


func _jt_c_no_rejump() -> Array:
	var lp = _jt_lp()
	# Landed and standing still: holding up through the landing must NOT
	# trigger a second jump (the stick-up jump is edge-triggered + armed).
	var ok: bool = lp.is_on_floor() and absf(lp.velocity.y) < 50.0
	_jt_release_move()
	return [ok, "on_floor=%s vel.y=%d fuel=%d" % [lp.is_on_floor(), round(lp.velocity.y), round(lp.fuel)]]


func _jt_s_resize_1920() -> void:
	# Phase 5: same clear-left teleport as _jt_s_press_left — after
	# the earlier steps the player is back at spawn#0, pressed
	# against the cover crate on its left.
	_jt_teleport_clear_left()
	get_window().size = Vector2(1920, 1080)
	_jt_press_move(Vector2(-50, 0))


func _jt_c_resolution_1920() -> Array:
	var lp = _jt_lp()
	var vp_size := get_viewport().get_visible_rect().size
	# The stick math is rect-based, so it must work at any window size;
	# the check is the vector, the viewport size is logged for the record.
	var ok: bool = touch_move_vec.x < -0.5 and lp.velocity.x < -50.0
	get_window().size = Vector2(1280, 720)
	_jt_release_move()
	return [ok, "viewport=%s vec=%s vel.x=%d" % [vp_size, touch_move_vec, round(lp.velocity.x)]]


# =====================================================================
# QA-029 SCALE / COORDINATE TEST (--scale-test)
# Touches arrive as viewport pixels; the HUD lives in a CanvasLayer
# (no camera) under stretch mode canvas_items + expand. This harness
# drives the REAL _unhandled_input pipeline with viewport-pixel
# positions (computed from each control's on-screen transform) at
# several window sizes and checks the resulting vectors. A touch on a
# stick's centre must give a zero vector at EVERY resolution, and a
# touch above the centre must give an UP vector — never a downward
# bias. Run: xvfb-run -a godot --path . -- --auto-host --scale-test
# =====================================================================

var _scale_test: bool = false
var _scale_done: bool = false
var _scale_steps: Array = []
var _scale_step: int = 0
var _scale_in_step: bool = false
var _scale_timer: float = 0.0
var _scale_passed: int = 0
var _scale_failed: int = 0


func _update_scaletest(delta: float) -> void:
	if _scale_done:
		return
	var lp = _get_local_player()
	if lp == null:
		_scale_timer += delta
		if _scale_timer > 5.0:
			_scale_done = true
			print("SCALETEST DONE: 0/0 passed — no local player spawned")
			get_tree().quit()
		return
	if _scale_steps.is_empty():
		_scaletest_build_steps()
		_scale_step = 0
		_scale_in_step = false
		_scale_timer = 0.0
	if _scale_step >= _scale_steps.size():
		_scale_done = true
		get_window().size = Vector2(1280, 720)
		print("SCALETEST DONE: %d/%d passed" % [_scale_passed, _scale_passed + _scale_failed])
		get_tree().quit()
		return
	var step: Dictionary = _scale_steps[_scale_step]
	if not _scale_in_step:
		(step["setup"] as Callable).call()
		_scale_in_step = true
		_scale_timer = float(step["wait"])
	_scale_timer -= delta
	if _scale_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_scale_passed += 1
		else:
			_scale_failed += 1
		print("SCALETEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_scale_step += 1
		_scale_in_step = false
		_scale_timer = 0.0


func _scaletest_build_steps() -> void:
	_scale_steps = []
	var resolutions: Array = [Vector2(1280, 720), Vector2(2400, 1080), Vector2(1920, 1080), Vector2(800, 480), Vector2(2340, 1080)]
	for res in resolutions:
		var tag := "%dx%d" % [int(res.x), int(res.y)]
		_scale_steps.append({"name": tag + "-RESIZE", "wait": 0.8, "setup": _st_s_resize.bind(res), "check": _st_c_resize.bind(res)})
		_scale_steps.append({"name": tag + "-DIAG", "wait": 0.3, "setup": _st_s_diag, "check": _st_c_diag})
		_scale_steps.append({"name": tag + "-MOVE-CENTRE", "wait": 0.3, "setup": _st_s_press_move_centre, "check": _st_c_move_centre})
		_scale_steps.append({"name": tag + "-MOVE-UP", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(0, -60)), "check": _st_c_move_up})
		_scale_steps.append({"name": tag + "-MOVE-DOWN", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(0, 60)), "check": _st_c_move_down})
		_scale_steps.append({"name": tag + "-MOVE-LEFT", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(-60, 0)), "check": _st_c_move_left})
		_scale_steps.append({"name": tag + "-MOVE-RIGHT", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(60, 0)), "check": _st_c_move_right})
		_scale_steps.append({"name": tag + "-MOVE-DIAG", "wait": 0.3, "setup": _st_s_drag_move.bind(Vector2(42, -42)), "check": _st_c_move_diag})
		_scale_steps.append({"name": tag + "-MOVE-RELEASE", "wait": 0.3, "setup": _st_s_release_move, "check": _st_c_move_released})
		_scale_steps.append({"name": tag + "-AIM-CENTRE", "wait": 0.3, "setup": _st_s_press_aim_centre, "check": _st_c_aim_centre})
		_scale_steps.append({"name": tag + "-AIM-UP", "wait": 0.3, "setup": _st_s_drag_aim.bind(Vector2(0, -60)), "check": _st_c_aim_up})
		_scale_steps.append({"name": tag + "-AIM-RELEASE", "wait": 0.3, "setup": _st_s_release_aim, "check": _st_c_aim_released})
		_scale_steps.append({"name": tag + "-AIM-FIRE-CENTRE", "wait": 0.3, "setup": _st_s_press_fire_centre, "check": _st_c_fire_held})
		_scale_steps.append({"name": tag + "-AIM-FIRE-RELEASE", "wait": 0.3, "setup": _st_s_release_fire, "check": _st_c_fire_released})


# --- Scale-test touch drivers: real _unhandled_input with viewport pixels ---

func _st_screen_center(ctrl: Control) -> Vector2:
	return ctrl.get_global_transform_with_canvas() * (ctrl.size * 0.5)


func _st_press(idx: int, screen_pos: Vector2) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = screen_pos
	e.pressed = true
	_unhandled_input(e)


func _st_drag(idx: int, screen_pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx
	e.position = screen_pos
	_unhandled_input(e)


func _st_release(idx: int) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx
	e.position = Vector2.ZERO
	e.pressed = false
	_unhandled_input(e)


func _st_s_resize(res: Vector2) -> void:
	get_window().size = res


func _st_s_diag() -> void:
	var ct := get_viewport().get_canvas_transform()
	var cam := get_viewport().get_camera_2d()
	var cam_center := cam.get_screen_center_position() if cam != null else Vector2.ZERO
	var mrect: Rect2 = move_stick.get_global_rect()
	var mgt: Transform2D = move_stick.get_global_transform_with_canvas()
	var scenter := _st_screen_center(move_stick)
	var converted := _to_canvas_pos(scenter)
	var buggy := get_viewport().get_canvas_transform().affine_inverse() * scenter
	print("SCALETEST DIAG win=%s vis=%s canvas_t origin=%s x=%s y=%s hud_final=%s cam_center=%s move_rect=%s move_gt origin=%s x=%s y=%s screen_centre=%s converted=%s buggy_viewport_canvas=%s rect_centre=%s" % [get_window().size, get_viewport().get_visible_rect().size, ct.origin, ct.x, ct.y, hud.get_final_transform(), cam_center, mrect, mgt.origin, mgt.x, mgt.y, scenter, converted, buggy, mrect.get_center()])


func _st_s_press_move_centre() -> void:
	_st_press(920, _st_screen_center(move_stick))


func _st_s_drag_move(offset_px: Vector2) -> void:
	_st_drag(920, _st_screen_center(move_stick) + offset_px)


func _st_s_release_move() -> void:
	_st_release(920)


func _st_s_press_aim_centre() -> void:
	_st_press(921, _st_screen_center(aim_stick))


func _st_s_drag_aim(offset_px: Vector2) -> void:
	_st_drag(921, _st_screen_center(aim_stick) + offset_px)


func _st_s_release_aim() -> void:
	_st_release(921)


func _st_s_press_fire_centre() -> void:
	# v3.2: no FIRE button — the scale check now presses the AIM
	# stick's screen centre and drags it 60 px right: the deflection
	# must register as aiming AND firing at every resolution.
	_st_press(922, _st_screen_center(aim_stick))
	_st_drag(922, _st_screen_center(aim_stick) + Vector2(60, 0))


func _st_s_release_fire() -> void:
	_st_release(922)


# --- Scale-test checks ---

func _st_c_resize(res: Vector2) -> Array:
	var ok: bool = Vector2(get_window().size) == res
	return [ok, "win=%s" % get_window().size]


func _st_c_diag() -> Array:
	return [true, "see DIAG line above"]


func _st_c_move_centre() -> Array:
	var v := touch_move_vec
	var k: Vector2 = move_stick.get_knob_offset()
	var ok: bool = v.length() < 0.05 and k.length() < 3.0
	return [ok, "vec=%s knob=%s" % [v, k]]


func _st_c_move_up() -> Array:
	var v := touch_move_vec
	var k: Vector2 = move_stick.get_knob_offset()
	var ok: bool = v.y < -0.4 and absf(v.x) < 0.2 and k.y < -10.0
	return [ok, "vec=%s knob=%s" % [v, k]]


func _st_c_move_down() -> Array:
	var v := touch_move_vec
	var k: Vector2 = move_stick.get_knob_offset()
	var ok: bool = v.y > 0.4 and absf(v.x) < 0.2 and k.y > 10.0
	return [ok, "vec=%s knob=%s" % [v, k]]


func _st_c_move_left() -> Array:
	var v := touch_move_vec
	var ok: bool = v.x < -0.4 and absf(v.y) < 0.2
	return [ok, "vec=%s" % v]


func _st_c_move_right() -> Array:
	var v := touch_move_vec
	var ok: bool = v.x > 0.4 and absf(v.y) < 0.2
	return [ok, "vec=%s" % v]


func _st_c_move_diag() -> Array:
	var v := touch_move_vec
	var k: Vector2 = move_stick.get_knob_offset()
	var ok: bool = v.x > 0.25 and v.y < -0.25 and v.length() > 0.4 and v.length() < 1.05 and k.y < 0.0
	return [ok, "vec=%s knob=%s" % [v, k]]


func _st_c_move_released() -> Array:
	var ok: bool = touch_move_vec == Vector2.ZERO
	return [ok, "vec=%s" % touch_move_vec]


func _st_c_aim_centre() -> Array:
	var v := touch_aim
	var ok: bool = v.length() < 0.05
	return [ok, "aim=%s" % v]


func _st_c_aim_up() -> Array:
	var v := touch_aim
	var ok: bool = v.y < -0.4 and absf(v.x) < 0.2
	return [ok, "aim=%s" % v]


func _st_c_aim_released() -> Array:
	var ok: bool = touch_aim == Vector2.ZERO
	return [ok, "aim=%s" % touch_aim]


func _st_c_fire_held() -> Array:
	var ok: bool = touch_firing and aim_stick.is_active()
	return [ok, "firing=%s aim_active=%s" % [touch_firing, aim_stick.is_active()]]


func _st_c_fire_released() -> Array:
	var ok: bool = not touch_firing and touch_aim == Vector2.ZERO
	return [ok, "firing=%s aim=%s" % [touch_firing, touch_aim]]


# =====================================================================
# QA-030 SOLID-OBSTACLE COLLISION TEST (--collision-test)
# Proves crates/barrels/columns are real cover: bullets stop at them,
# players cannot walk through them, grenades bounce off them — while
# trees/bushes/bridges stay pass-through dressing. Also validates every
# map's data: no spawn or pickup sits inside a solid obstacle and every
# area stays reachable (no route sealed off).
# Run: xvfb-run -a godot --path . -- --auto-host --collision-test
#      (add --map=5 for the Jungle Ruins pass-through checks)
# =====================================================================

var _collision_test: bool = false
var _ct_done: bool = false
var _ct_steps: Array = []
var _ct_step: int = 0
var _ct_in_step: bool = false
var _ct_timer: float = 0.0
var _ct_passed: int = 0
var _ct_failed: int = 0
var _ct_walk_start_x: float = 0.0
var _ct_grenade: Node = null


func _update_collisiontest(delta: float) -> void:
	if _ct_done:
		return
	var lp = _get_local_player()
	if lp == null:
		_ct_timer += delta
		if _ct_timer > 5.0:
			_ct_done = true
			print("COLLISIONTEST DONE: 0/0 passed — no local player spawned")
			get_tree().quit()
		return
	if _ct_steps.is_empty():
		_ct_build_steps()
		_ct_step = 0
		_ct_in_step = false
		_ct_timer = 0.0
	if _ct_step >= _ct_steps.size():
		_ct_done = true
		print("COLLISIONTEST DONE: %d/%d passed (map: %s)" % [_ct_passed, _ct_passed + _ct_failed, String(MAPS[map_id]["name"])])
		get_tree().quit()
		return
	var step: Dictionary = _ct_steps[_ct_step]
	if not _ct_in_step:
		(step["setup"] as Callable).call()
		_ct_in_step = true
		_ct_timer = float(step["wait"])
	_ct_timer -= delta
	if _ct_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_ct_passed += 1
		else:
			_ct_failed += 1
		print("COLLISIONTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_ct_step += 1
		_ct_in_step = false
		_ct_timer = 0.0


func _ct_build_steps() -> void:
	_ct_steps = [
		{"name": "STATIC-ALL-MAPS", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_static_all_maps},
		{"name": "BULLET-STOPS-SOLID", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_bullet_stops},
		{"name": "BULLET-BLOCKS-TARGET", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_bullet_blocks_target},
		{"name": "WALK-BLOCKED", "wait": 1.0, "setup": _ct_s_walk_into_solid, "check": _ct_c_walk_blocked},
		{"name": "BULLET-STOPS-FLOOR", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_bullet_stops_floor},
		{"name": "GRENADE-BLOCKED", "wait": 1.2, "setup": _ct_s_throw_grenade, "check": _ct_c_grenade_blocked},
		{"name": "BULLET-PASSES-BUSH", "wait": 0.3, "setup": _ct_s_noop, "check": _ct_c_bullet_passes_bush},
		{"name": "WALK-PASSES-BUSH", "wait": 1.2, "setup": _ct_s_walk_into_bush, "check": _ct_c_walk_passes_bush},
	]


func _ct_s_noop() -> void:
	pass


# --- QA-030 helpers: solid / pass-through rects from the MAPS data ---

# Solid decor rectangles for a map — the same rectangles _build_arena
# turns into collision shapes: the texture rect shrunk by the
# per-kind DECOR_INSETS (GAP-14), centred on the decor entry.
# (The test used to expect the full-texture face; the inset face is
# the real collision, 6-10 px inside the sprite's transparent edge.)
func _ct_solid_rects(m: Dictionary) -> Array:
	var out: Array = []
	var decor: Array = m["decor"]
	for d in decor:
		if String(d[0]) in SOLID_DECOR_KINDS:
			var tex: Texture2D = DECOR_TEX[d[0]]
			var w := float(tex.get_width())
			var h := float(tex.get_height())
			var inset := float(DECOR_INSETS.get(String(d[0]), 6))
			var w2 := maxf(8.0, w - inset * 2.0)
			var h2 := maxf(8.0, h - inset)
			out.append(Rect2(float(d[1]) - w2 * 0.5, float(d[2]) - h + inset, w2, h2))
	return out


# First pass-through decor rect on the loaded map (bush / tree / palm /
# bridge / arch — kinds with no collision). Empty when the map has none.
func _ct_nonsolid_rect() -> Rect2:
	var m: Dictionary = MAPS[map_id]
	var decor: Array = m["decor"]
	for d in decor:
		if not (String(d[0]) in SOLID_DECOR_KINDS):
			var tex: Texture2D = DECOR_TEX[d[0]]
			var w := float(tex.get_width())
			var h := float(tex.get_height())
			return Rect2(float(d[1]) - w * 0.5, float(d[2]) - h, w, h)
	return Rect2()


# First low solid cover sitting on the floor (crate / barrels / rock /
# sandbags / jungle crate / jungle rock) — the cover the bullet and
# walk tests use. Empty when the map has none.
func _ct_floor_cover() -> Rect2:
	var m: Dictionary = MAPS[map_id]
	var plats: Array = m["platforms"]
	var floor_top := 0.0
	for p in plats:
		var r: Rect2 = p
		floor_top = maxf(floor_top, r.position.y)
	for rr in _ct_solid_rects(m):
		var r: Rect2 = rr
		if absf(r.end.y - floor_top) < 2.0 and r.size.y <= 100.0:
			return r
	return Rect2()


# The tallest solid decor on the loaded map (column / watchtower /
# statue) — the grenade test throws at it because a tall face cannot
# be arced over.
func _ct_tall_solid() -> Rect2:
	var best := Rect2()
	for rr in _ct_solid_rects(MAPS[map_id]):
		var r: Rect2 = rr
		if r.size.y > best.size.y:
			best = r
	return best


# A clear x on the floor (no solid decor over it) for the floor ray.
func _ct_floor_ray_x() -> float:
	var m: Dictionary = MAPS[map_id]
	var plats: Array = m["platforms"]
	var floor_top := 0.0
	var floor_x := 0.0
	var floor_w := 0.0
	for p in plats:
		var r: Rect2 = p
		if r.position.y > floor_top:
			floor_top = r.position.y
			floor_x = r.position.x
			floor_w = r.size.x
		elif r.position.y == floor_top and r.size.x > floor_w:
			floor_x = r.position.x
			floor_w = r.size.x
	var x := floor_x + floor_w * 0.5
	for rr in _ct_solid_rects(m):
		var r: Rect2 = rr
		if r.end.y >= floor_top - 1.0 and r.position.x - 40.0 < x and x < r.end.x + 40.0:
			x = r.end.x + 60.0
	return x


# Direct space raycast, same mask as the bullet's swept raycast
# (mask 3: world + players), excluding the local player.
func _ct_ray(from: Vector2, to: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, 3)
	var lp = _get_local_player()
	if lp != null:
		query.exclude = [lp.get_rid()]
	return space.intersect_ray(query)


# --- Static validation: every map's data ---

func _ct_c_static_all_maps() -> Array:
	var problems: Array = []
	var checked_spawns := 0
	var checked_pickups := 0
	var checked_rects := 0
	for mi in MAPS.size():
		var m: Dictionary = MAPS[mi]
		var rects := _ct_solid_rects(m)
		checked_rects += rects.size()
		var spawns: Array = m["spawns"]
		var pickups: Array = m["pickups"]
		var plats: Array = m["platforms"]
		# (f) spawns: the player capsule is 34 wide, 52 tall, centred
		# on the spawn point — it must not start inside a solid.
		for si in spawns.size():
			var sp: Vector2 = spawns[si]
			checked_spawns += 1
			var box := Rect2(sp - Vector2(17, 26), Vector2(34, 52))
			for rr in rects:
				if (rr as Rect2).intersects(box):
					problems.append("%s spawn#%d inside solid %s" % [m["name"], si, rr])
		# (f) pickups: the collection circle is radius 22 — its centre
		# must be reachable, i.e. the circle must not overlap a solid.
		for pi in pickups.size():
			var pp: Vector2 = pickups[pi]
			checked_pickups += 1
			for rr in rects:
				var r: Rect2 = rr
				var cx := clampf(pp.x, r.position.x, r.position.x + r.size.x)
				var cy := clampf(pp.y, r.position.y, r.position.y + r.size.y)
				if Vector2(cx, cy).distance_to(pp) < 22.0:
					problems.append("%s pickup#%d inside solid %s" % [m["name"], pi, rr])
		# (f) no solid may seal a platform: a solid that spans a
		# platform's full width with <100 px clearance above it would
		# block the only route across that platform.
		for rr in rects:
			var r: Rect2 = rr
			for p in plats:
				var pr: Rect2 = p
				if absf(r.end.y - pr.position.y) < 2.0 and r.position.x <= pr.position.x + 4.0 and r.end.x >= pr.end.x - 4.0:
					var top := r.position.y
					var above := 0.0
					for p2 in plats:
						var pr2: Rect2 = p2
						if pr2.end.y <= top + 1.0 and pr2.position.x <= r.get_center().x and pr2.end.x >= r.get_center().x:
							above = maxf(above, pr2.end.y)
					if top - above < 100.0:
						problems.append("%s solid %s seals platform %s" % [m["name"], r, pr])
		# (f) reachability: every spawn and pickup must attach to a
		# platform reachable from spawn#0 through jump/jetpack moves.
		if not _ct_map_reachable(m):
			problems.append("%s not fully reachable" % m["name"])
	var ok := problems.is_empty()
	return [ok, "%d maps, %d solid rects, %d spawns, %d pickups: %s" % [MAPS.size(), checked_rects, checked_spawns, checked_pickups, "all clear" if ok else "; ".join(problems)]]


# Platform graph: two platforms connect when the player can jump or
# jetpack between them (up to 320 px up, 340 px across) or drop down
# (up to 420 px). BFS from spawn#0's platform must reach every spawn
# and pickup platform.
func _ct_map_reachable(m: Dictionary) -> bool:
	var plats: Array = m["platforms"]
	var n := plats.size()
	var adj: Array = []
	for i in n:
		adj.append([])
	for i in n:
		var a: Rect2 = plats[i]
		for j in n:
			if i == j:
				continue
			var b: Rect2 = plats[j]
			var hgap := 0.0
			if a.end.x < b.position.x:
				hgap = b.position.x - a.end.x
			elif b.end.x < a.position.x:
				hgap = a.position.x - b.end.x
			var vgap := b.position.y - a.position.y
			if hgap <= 340.0 and vgap >= -320.0 and vgap <= 420.0:
				(adj[i] as Array).append(j)
	var spawns: Array = m["spawns"]
	var start := _ct_platform_below(plats, spawns[0])
	if start < 0:
		return false
	var seen := {start: true}
	var stack: Array = [start]
	while not stack.is_empty():
		var cur: int = stack.pop_back()
		for nb in adj[cur]:
			if not seen.has(nb):
				seen[nb] = true
				stack.append(nb)
	for sp in spawns:
		if not seen.has(_ct_platform_below(plats, sp)):
			return false
	for pp in m["pickups"]:
		if not seen.has(_ct_platform_below(plats, pp)):
			return false
	return true


# Platform whose top is just below a point (within 60 px), i.e. the
# platform the point stands on. -1 when there is none.
func _ct_platform_below(plats: Array, point: Vector2) -> int:
	var best := -1
	var best_top := -1.0
	for i in plats.size():
		var r: Rect2 = plats[i]
		if point.x >= r.position.x - 4.0 and point.x <= r.end.x + 4.0 and r.position.y >= point.y - 60.0 and r.position.y <= point.y + 60.0:
			if r.position.y > best_top:
				best_top = r.position.y
				best = i
	return best


# --- Dynamic checks on the loaded map ---

# (a) a ray at a solid cover's face stops there — the bullet never
# passes through it.
func _ct_c_bullet_stops() -> Array:
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return [true, "no low solid cover on this map — nothing to stop"]
	var cy := cover.get_center().y
	# QA-033: clamp the ray start inside the map — a cover near the
	# left edge (e.g. Frozen Fortress sandbags at x=120) puts
	# cover.x - 120 outside the arena, and the ray then hits the
	# boundary wall at x=0 instead of the cover face.
	var from := Vector2(maxf(cover.position.x - 120.0, 5.0), cy)
	var to := Vector2(cover.position.x + 120.0, cy)
	var hit := _ct_ray(from, to)
	if hit.is_empty():
		return [false, "ray %s -> %s passed through %s with no hit" % [from, to, cover]]
	var hp: Vector2 = hit["position"]
	var ok: bool = absf(hp.x - cover.position.x) <= 4.0
	return [ok, "ray hit at %s (cover face x=%.0f, cover %s)" % [hp, cover.position.x, cover]]


# (a) a ray aimed at a point behind the cover still stops at the cover
# — a target behind it takes no damage.
func _ct_c_bullet_blocks_target() -> Array:
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return [true, "no low solid cover on this map"]
	var cy := cover.get_center().y
	# QA-033: same clamp as _ct_c_bullet_stops — a near-edge cover
	# would otherwise let the boundary wall at x=0 stop the ray and
	# pass this check for the wrong reason.
	var from := Vector2(maxf(cover.position.x - 120.0, 5.0), cy)
	var to := Vector2(cover.end.x + 120.0, cy)
	var hit := _ct_ray(from, to)
	if hit.is_empty():
		return [false, "ray %s -> %s passed clean through %s" % [from, to, cover]]
	var hp: Vector2 = hit["position"]
	var ok: bool = hp.x <= cover.position.x + 4.0
	return [ok, "ray stopped at %s (cover %s); nothing behind it is reachable" % [hp, cover]]


var _ct_walk_dir: int = 1


func _ct_walk_path_has_pad(from_x: float, to_x: float) -> bool:
	for entry in _bounce_pads:
		var r: Rect2 = entry["rect"]
		if r.position.x - 17.0 < maxf(from_x, to_x) and r.end.x + 17.0 > minf(from_x, to_x):
			return true
	return false


func _ct_s_walk_into_solid() -> void:
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return
	var lp = _get_local_player()
	# Approach from the right (walk left) when the usual left
	# approach would cross a bounce pad and launch over the cover.
	var right_approach: bool = not _ct_walk_path_has_pad(cover.position.x - 60.0, cover.position.x - 17.0)
	if right_approach:
		_ct_walk_dir = 1
		lp.position = Vector2(cover.position.x - 60.0, cover.end.y - 26.0)
	else:
		_ct_walk_dir = -1
		lp.position = Vector2(cover.end.x + 60.0, cover.end.y - 26.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_ct_walk_start_x = lp.position.x
	_on_touch_press(930, move_stick.get_global_rect().get_center() + Vector2(60 * _ct_walk_dir, 0))


# (b) walking into a solid cover: the player is blocked and slides
# along it, never passing through.
func _ct_c_walk_blocked() -> Array:
	_on_touch_release(930)
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return [true, "no low solid cover on this map"]
	var lp = _get_local_player()
	if _ct_walk_dir > 0:
		var moved: bool = lp.position.x > _ct_walk_start_x + 20.0
		var stopped: bool = lp.position.x <= cover.position.x - 17.0 + 4.0
		return [moved and stopped, "player x=%.0f (started %.0f, cover face %.0f, capsule edge %.0f)" % [lp.position.x, _ct_walk_start_x, cover.position.x, cover.position.x - 17.0]]
	var moved2: bool = lp.position.x < _ct_walk_start_x - 20.0
	var stopped2: bool = lp.position.x >= cover.end.x + 17.0 - 4.0
	return [moved2 and stopped2, "player x=%.0f (started %.0f, cover face %.0f, capsule edge %.0f, walking left)" % [lp.position.x, _ct_walk_start_x, cover.end.x, cover.end.x + 17.0]]


# (c) a ray straight down stops at the floor top.
func _ct_c_bullet_stops_floor() -> Array:
	var x := _ct_floor_ray_x()
	var m: Dictionary = MAPS[map_id]
	var plats: Array = m["platforms"]
	var floor_top := 0.0
	for p in plats:
		var r: Rect2 = p
		if x >= r.position.x and x <= r.end.x:
			floor_top = maxf(floor_top, r.position.y)
	var hit := _ct_ray(Vector2(x, floor_top - 100.0), Vector2(x, floor_top + 100.0))
	if hit.is_empty():
		return [false, "downward ray at x=%.0f passed through the floor (top %.0f)" % [x, floor_top]]
	var hp: Vector2 = hit["position"]
	var ok: bool = absf(hp.y - floor_top) <= 4.0
	return [ok, "ray hit at %s (floor top %.0f at x=%.0f)" % [hp, floor_top, x]]


func _ct_s_throw_grenade() -> void:
	var tall := _ct_tall_solid()
	if tall == Rect2():
		return
	var lp = _get_local_player()
	lp.position = Vector2(tall.position.x - 150.0, tall.end.y - 26.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	lp.facing = 1
	_ct_grenade = null
	lp.throw_grenade()
	if not grenades_node.get_children().is_empty():
		_ct_grenade = grenades_node.get_children()[0]


# (g) a grenade thrown at a tall solid bounces off it and never
# crosses its face.
func _ct_c_grenade_blocked() -> Array:
	var tall := _ct_tall_solid()
	if tall == Rect2():
		return [true, "no tall solid on this map"]
	if _ct_grenade == null or not is_instance_valid(_ct_grenade):
		return [false, "grenade never spawned"]
	var g: Node2D = _ct_grenade
	var ok: bool = g.position.x < tall.position.x
	return [ok, "grenade x=%.0f after 1.2 s (solid face %.0f, solid %s)" % [g.position.x, tall.position.x, tall]]


# (d) a ray through a bush / tree / palm passes clean through — the
# dressing has no collision.
func _ct_c_bullet_passes_bush() -> Array:
	var bush := _ct_nonsolid_rect()
	if bush == Rect2():
		return [true, "no pass-through decor on this map — covered on Jungle Ruins"]
	var cy := bush.get_center().y
	# Start the ray just left of the decor, but never off the map
	# (the left wall would stop it first and the test would lie).
	var from := Vector2(maxf(bush.position.x - 120.0, 30.0), cy)
	var hit := _ct_ray(from, Vector2(bush.end.x + 120.0, cy))
	if hit.is_empty():
		return [true, "ray passed clean through %s (no hit)" % bush]
	var hp: Vector2 = hit["position"]
	return [false, "ray stopped at %s inside pass-through decor %s" % [hp, bush]]


func _ct_s_walk_into_bush() -> void:
	var bush := _ct_nonsolid_rect()
	if bush == Rect2():
		return
	var lp = _get_local_player()
	lp.position = Vector2(bush.position.x - 60.0, bush.end.y - 26.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_ct_walk_start_x = lp.position.x
	_on_touch_press(930, move_stick.get_global_rect().get_center() + Vector2(60, 0))


# (e) walking through a bush / tree: the player passes it, unblocked.
func _ct_c_walk_passes_bush() -> Array:
	_on_touch_release(930)
	var bush := _ct_nonsolid_rect()
	if bush == Rect2():
		return [true, "no pass-through decor on this map — covered on Jungle Ruins"]
	var lp = _get_local_player()
	var ok: bool = lp.position.x > bush.end.x + 17.0
	return [ok, "player x=%.0f (bush %s, must be past %.0f)" % [lp.position.x, bush, bush.end.x + 17.0]]


# =====================================================================
# v3.2 RIGHT-STICK-FIRE ACCEPTANCE TEST (--fire-test)
# Drives the REAL touch routing with simulated touches (fake indices
# 910 move / 911 aim), like the joystick test. Covers the
# CONTROLS_CHANGE.md §5 cases: untouched 0 shots, aim deflect fires +
# aim matches, release stops, move/grenade/weapon/reload/pause/score
# alone 0 shots, move+aim-fire together, semi-auto flick exactly 1 +
# hold exactly 1, auto hold continuous at table rate, no fire dead /
# paused / match-end, focus-out reset — plus the QA-023 glitch
# regressions (move/grenade/weapon must never fire the gun).
# =====================================================================

func _update_firetest(delta: float) -> void:
	if _fire_done:
		return
	var lp = _get_local_player()
	if lp == null:
		_fire_timer += delta
		if _fire_timer > 5.0:
			_fire_done = true
			print("FIRETEST DONE: 0/0 passed — no local player spawned")
			get_tree().quit()
		return
	if _fire_steps.is_empty():
		_firetest_build_steps()
		_fire_step = 0
		_fire_in_step = false
		_fire_timer = 0.0
	if _fire_step >= _fire_steps.size():
		_fire_done = true
		print("FIRETEST DONE: %d/%d passed" % [_fire_passed, _fire_passed + _fire_failed])
		get_tree().quit()
		return
	var step: Dictionary = _fire_steps[_fire_step]
	if not _fire_in_step:
		(step["setup"] as Callable).call()
		_fire_in_step = true
		_fire_timer = float(step["wait"])
	# T-33 rapid-tap driver: performs press/release pairs on a
	# schedule (0.10 s hold, 0.25 s gap — press-to-press 0.35 s,
	# comfortably above the pistol rate of 0.22 s).
	if _ft_tap_left > 0:
		_ft_tap_timer -= delta
		if _ft_tap_timer <= 0.0:
			if _ft_tap_phase == 0:
				_ft_press_fire()
				_ft_tap_phase = 1
				_ft_tap_timer = 0.10
			else:
				_ft_release_fire()
				_ft_tap_phase = 0
				_ft_tap_left -= 1
				_ft_tap_timer = 0.25
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_fire_passed += 1
		else:
			_fire_failed += 1
		print("FIRETEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		# QA-047: the T-33 rapid-tap driver must not leak into the
		# next step. Under load its last tap can still be pending
		# when this step ends (physics runs behind real time, so
		# the 10th shot lands late) — the driver would then release
		# the next step's FIRE press, and FIRE-HOLD-CONTINUOUS read
		# 0 shots in the full regression. Stop the driver here.
		if _ft_tap_left > 0:
			_ft_tap_left = 0
			_ft_tap_phase = 0
			_ft_release_fire()
		_fire_step += 1
		_fire_in_step = false
		_fire_timer = 0.0


func _firetest_build_steps() -> void:
	_fire_steps = [
		{"name": "MOVE-ALONE-NO-FIRE", "wait": 1.0, "setup": _ft_s_move_alone, "check": _ft_c_move_alone},
		{"name": "AIM-ALONE-FIRES", "wait": 1.0, "setup": _ft_s_aim_alone, "check": _ft_c_aim_alone},
		{"name": "GRENADE-ALONE-NO-FIRE", "wait": 0.4, "setup": _ft_s_grenade_alone, "check": _ft_c_grenade_alone},
		{"name": "WEAPON-ALONE-NO-FIRE", "wait": 0.4, "setup": _ft_s_weapon_alone, "check": _ft_c_weapon_alone},
		{"name": "PISTOL-TAP-ONE-SHOT", "wait": 0.4, "setup": _ft_s_pistol_tap, "check": _ft_c_pistol_tap},
		{"name": "PISTOL-TEN-RAPID-TAPS", "wait": 4.5, "setup": _ft_s_ten_taps, "check": _ft_c_ten_taps},
		{"name": "FIRE-HOLD-CONTINUOUS", "wait": 2.5, "setup": _ft_s_fire_hold, "check": _ft_c_fire_hold},
		{"name": "FIRE-WHILE-MOVING", "wait": 1.0, "setup": _ft_s_fire_moving, "check": _ft_c_fire_moving},
		{"name": "FIRE-DIAGONAL-AIM", "wait": 1.0, "setup": _ft_s_fire_diagonal, "check": _ft_c_fire_diagonal},
		{"name": "FIRE-WHILE-JETPACK", "wait": 1.0, "setup": _ft_s_fire_jetpack, "check": _ft_c_fire_jetpack},
		{"name": "FIRE-WHILE-JUMPING", "wait": 0.5, "setup": _ft_s_fire_jump, "check": _ft_c_fire_jump},
		{"name": "SWITCH-SETUP", "wait": 0.5, "setup": _ft_s_switch_setup, "check": _ft_c_switch_setup},
		{"name": "SWITCH-WHILE-FIRING", "wait": 0.6, "setup": _ft_s_switch_mid, "check": _ft_c_switch_mid},
		{"name": "EMPTY-MAG-BLOCKED", "wait": 0.6, "setup": _ft_s_empty_mag, "check": _ft_c_empty_mag},
		{"name": "RELOAD-COMPLETES", "wait": 1.5, "setup": _ft_s_noop, "check": _ft_c_reload_done},
		{"name": "RELOAD-WHILE-MOVING", "wait": 0.6, "setup": _ft_s_reload_moving, "check": _ft_c_reload_moving},
		{"name": "THREE-FINGERS", "wait": 1.0, "setup": _ft_s_three_fingers, "check": _ft_c_three_fingers},
		{"name": "GRENADE-WHILE-FIRING-SETUP", "wait": 0.5, "setup": _ft_s_grenade_firing_a, "check": _ft_c_grenade_firing_a},
		{"name": "GRENADE-WHILE-FIRING", "wait": 0.6, "setup": _ft_s_grenade_firing_b, "check": _ft_c_grenade_firing_b},
		{"name": "SLIDE-OFF-SETUP", "wait": 0.5, "setup": _ft_s_slide_off_a, "check": _ft_c_slide_off_a},
		{"name": "SLIDE-OFF-STOPS-FIRE", "wait": 0.5, "setup": _ft_s_slide_off_b, "check": _ft_c_slide_off_b},
		{"name": "LAYOUT-1280", "wait": 0.3, "setup": _ft_s_noop, "check": _ft_c_layout_1280},
		{"name": "LAYOUT-1920-AND-TRANSFORM", "wait": 0.5, "setup": _ft_s_layout_1920, "check": _ft_c_layout_1920},
		{"name": "MP-SYNC-VALIDATION", "wait": 0.3, "setup": _ft_s_noop, "check": _ft_c_mp_sync},
		{"name": "MP-SINGLE-SHOT-ONE-BULLET", "wait": 0.15, "setup": _ft_s_single_bullet, "check": _ft_c_single_bullet},
		{"name": "MP-SHOTGUN-SEVEN-PELLETS", "wait": 0.15, "setup": _ft_s_pellets, "check": _ft_c_pellets},
	]


# --- Fire-test helpers (fake touch indices 910 move / 911 aim) ---
# v3.2: there is no FIRE button — "press fire" means deflecting the
# AIM stick. If the aim stick is already held by _ft_press_aim, the
# press is a no-op (it already fires); otherwise the 911 press owns
# the aim stick until _ft_release_fire.

func _ft_lp():
	return _get_local_player()


func _ft_move_center() -> Vector2:
	return move_stick.get_global_rect().get_center()


func _ft_aim_center() -> Vector2:
	return aim_stick.get_global_rect().get_center()


func _ft_press_move(offset: Vector2) -> void:
	_on_touch_press(910, _ft_move_center() + offset)


func _ft_release_move() -> void:
	_on_touch_release(910)


func _ft_press_aim(offset: Vector2) -> void:
	_on_touch_press(911, _ft_aim_center() + offset)


func _ft_release_aim() -> void:
	_on_touch_release(911)
	_ft_fire_owns_aim = false


func _ft_press_fire() -> void:
	if not aim_stick.is_active():
		_ft_fire_owns_aim = true
		_on_touch_press(911, _ft_aim_center() + Vector2(60, 0))


func _ft_release_fire() -> void:
	if _ft_fire_owns_aim:
		_on_touch_release(911)
		_ft_fire_owns_aim = false


func _ft_set_weapon(id: int) -> void:
	var lp = _ft_lp()
	lp.weapon = id
	lp.mag_ammo = int(lp.WEAPONS[id]["mag"])
	lp.reloading = false
	lp._update_gun_texture()


func _ft_teleport(pos: Vector2) -> void:
	var lp = _ft_lp()
	lp.position = pos
	lp.sync_position = pos
	lp.velocity = Vector2.ZERO


func _ft_count_bullets(owner_id: int, kind: int = -1) -> int:
	var n := 0
	for b in bullets_node.get_children():
		if b.active and int(b.owner_id) == owner_id and (kind < 0 or int(b.kind) == kind):
			n += 1
	return n


func _ft_s_noop() -> void:
	pass


func _ft_s_move_alone() -> void:
	_fire_shots_before = _ft_lp()._shots_fired
	_fire_pos_before = _ft_lp().position
	_ft_press_move(Vector2(60, 0))


func _ft_c_move_alone() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired == _fire_shots_before and not touch_firing and lp.position.x > _fire_pos_before.x + 100.0
	_ft_release_move()
	return [ok, "shots=%d (was %d) firing=%s x=%d (was %d)" % [lp._shots_fired, _fire_shots_before, touch_firing, round(lp.position.x), round(_fire_pos_before.x)]]


func _ft_s_aim_alone() -> void:
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_aim(Vector2(42, -42))


func _ft_c_aim_alone() -> Array:
	# v3.2: the aim stick IS the fire control — deflecting it fires.
	# A (42,-42) push must aim up-right AND shoot.
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and touch_firing and absf(lp.aim_angle + PI * 0.25) < 0.35
	_ft_release_aim()
	return [ok, "shots=%d (was %d) firing=%s aim_angle=%.2f" % [lp._shots_fired, _fire_shots_before, touch_firing, lp.aim_angle]]


func _ft_s_grenade_alone() -> void:
	_fire_shots_before = _ft_lp()._shots_fired
	_fire_grenades_before = _ft_lp().grenades
	# Tap the GRENADE button's centre through the touch router.
	_on_touch_press(913, grenade_button.get_global_rect().get_center())


func _ft_c_grenade_alone() -> Array:
	var lp = _ft_lp()
	# QA-023: a GRENADE tap must never grab a stick or fire the gun.
	var ok: bool = lp._shots_fired == _fire_shots_before and not touch_firing and not move_stick.is_active() and not aim_stick.is_active()
	_on_touch_release(913)
	# The button handler itself still works: one grenade thrown.
	_on_grenade_pressed()
	ok = ok and lp.grenades == _fire_grenades_before - 1
	return [ok, "shots=%d (was %d) firing=%s sticks_active=%s/%s grenades=%d (was %d)" % [lp._shots_fired, _fire_shots_before, touch_firing, move_stick.is_active(), aim_stick.is_active(), lp.grenades, _fire_grenades_before]]


func _ft_s_weapon_alone() -> void:
	var lp = _ft_lp()
	lp.give_pickup(1) # own the SMG so switching does something
	_fire_shots_before = lp._shots_fired
	_fire_weapon_before = lp.weapon
	_on_touch_press(914, switch_button.get_global_rect().get_center())


func _ft_c_weapon_alone() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired == _fire_shots_before and not touch_firing and not move_stick.is_active() and not aim_stick.is_active()
	_on_touch_release(914)
	_on_switch_pressed()
	ok = ok and lp.weapon != _fire_weapon_before
	return [ok, "shots=%d (was %d) firing=%s weapon=%d (was %d)" % [lp._shots_fired, _fire_shots_before, touch_firing, lp.weapon, _fire_weapon_before]]


func _ft_s_pistol_tap() -> void:
	_ft_set_weapon(5)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_pistol_tap() -> Array:
	var lp = _ft_lp()
	# Semi-auto: one press = exactly one shot, even held for 0.4 s.
	var ok: bool = lp._shots_fired == _fire_shots_before + 1
	_ft_release_fire()
	return [ok, "shots=%d (was %d, want +1)" % [lp._shots_fired, _fire_shots_before]]


func _ft_s_ten_taps() -> void:
	# T-33: 10 rapid taps. The tap driver (in _update_firetest)
	# performs the press/release pairs; the pistol's 0.22 s rate is
	# respected by the 0.35 s press-to-press spacing, so every tap
	# is a separate trigger pull. Mag refilled by _ft_set_weapon.
	_ft_set_weapon(5)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_tap_left = 10
	_ft_tap_phase = 0
	_ft_tap_timer = 0.0


func _ft_c_ten_taps() -> Array:
	var lp = _ft_lp()
	var n: int = lp._shots_fired - _fire_shots_before
	var ok: bool = n == 10
	return [ok, "shots fired for 10 rapid taps: %d (want 10)" % n]


func _ft_s_fire_hold() -> void:
	_ft_set_weapon(0)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_fire_hold() -> Array:
	var lp = _ft_lp()
	var n: int = lp._shots_fired - _fire_shots_before
	# Rifle rate 0.13 s: 2.5 s of holding should fire ~19 shots.
	var ok: bool = n >= 14 and n <= 22
	_ft_release_fire()
	return [ok, "shots fired in 2.5 s hold: %d (want 14-22)" % n]


func _ft_s_fire_moving() -> void:
	_ft_set_weapon(0)
	# QA-030: the floor now has solid cover — teleport to a clear
	# stretch (spawn, with 300 px of open floor ahead) so the movement
	# check measures running, not being blocked by a column.
	var lp = _ft_lp()
	lp.position = Vector2(300, 1320)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_fire_shots_before = _ft_lp()._shots_fired
	_fire_pos_before = _ft_lp().position
	_ft_press_move(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_fire_moving() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.position.x > _fire_pos_before.x + 100.0
	_ft_release_move()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) x=%d (was %d)" % [lp._shots_fired, _fire_shots_before, round(lp.position.x), round(_fire_pos_before.x)]]


func _ft_s_fire_diagonal() -> void:
	_ft_set_weapon(0)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_aim(Vector2(42, -42))
	_ft_press_fire()


func _ft_c_fire_diagonal() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and absf(lp.aim_angle + PI * 0.25) < 0.35
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) aim_angle=%.2f (want ~-0.79)" % [lp._shots_fired, _fire_shots_before, lp.aim_angle]]


func _ft_s_fire_jetpack() -> void:
	_ft_set_weapon(0)
	_ft_teleport(Vector2(2100, 1350))
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_move(Vector2(0, -60))
	_ft_press_fire()


func _ft_c_fire_jetpack() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.fuel < 99.0
	_ft_release_move()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) fuel=%d jetpacking=%s" % [lp._shots_fired, _fire_shots_before, round(lp.fuel), lp._jetpacking]]


func _ft_s_fire_jump() -> void:
	_ft_set_weapon(0)
	# Open sky above (2100, 1350) — see _jt_s_diag_up_right.
	_ft_teleport(Vector2(2100, 1350))
	_fire_shots_before = _ft_lp()._shots_fired
	# The previous step released the move stick; the release and this
	# press can land in two _process calls with no physics frame
	# between them, so the player would never see the stick drop and
	# the jump edge would not arm. Re-arm it here (test-only).
	var lp = _ft_lp()
	lp._stick_up_armed = true
	lp._stick_up_prev = false
	_ft_press_move(Vector2(0, -55))
	_ft_press_fire()


func _ft_c_fire_jump() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and not lp.is_on_floor()
	_ft_release_move()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) on_floor=%s y=%d" % [lp._shots_fired, _fire_shots_before, lp.is_on_floor(), round(lp.position.y)]]


func _ft_s_switch_setup() -> void:
	# Start on the pistol (semi-auto): switching while FIRE is held
	# lands on the SMG (automatic), which must keep firing. Switching
	# onto a semi-auto weapon would correctly need a fresh tap.
	_ft_set_weapon(5)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_switch_setup() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before
	return [ok, "shots=%d (was %d) firing while held" % [lp._shots_fired, _fire_shots_before]]


func _ft_s_switch_mid() -> void:
	var lp = _ft_lp()
	_fire_shots_before = lp._shots_fired
	_fire_weapon_before = lp.weapon
	lp.switch_weapon()


func _ft_c_switch_mid() -> Array:
	var lp = _ft_lp()
	# Still holding FIRE: the new weapon keeps shooting.
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.weapon != _fire_weapon_before
	_ft_release_fire()
	return [ok, "shots=%d (was %d) weapon=%d (was %d)" % [lp._shots_fired, _fire_shots_before, lp.weapon, _fire_weapon_before]]


func _ft_s_empty_mag() -> void:
	var lp = _ft_lp()
	lp.mag_ammo = 0
	lp.reloading = false
	_fire_shots_before = lp._shots_fired
	_ft_press_fire()


func _ft_c_empty_mag() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired == _fire_shots_before and lp.reloading
	_ft_release_fire()
	return [ok, "shots=%d (was %d) reloading=%s mag=%d" % [lp._shots_fired, _fire_shots_before, lp.reloading, lp.mag_ammo]]


func _ft_c_reload_done() -> Array:
	var lp = _ft_lp()
	var ok: bool = not lp.reloading and lp.mag_ammo == int(lp.WEAPONS[lp.weapon]["mag"])
	return [ok, "reloading=%s mag=%d (want %d)" % [lp.reloading, lp.mag_ammo, int(lp.WEAPONS[lp.weapon]["mag"])]]


func _ft_s_reload_moving() -> void:
	var lp = _ft_lp()
	lp.mag_ammo = 10
	lp.reloading = false
	_fire_pos_before = lp.position
	_ft_press_move(Vector2(60, 0))
	_on_reload_pressed()


func _ft_c_reload_moving() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp.position.x > _fire_pos_before.x + 50.0 and lp.reloading
	_ft_release_move()
	return [ok, "x=%d (was %d) reloading=%s progress=%d%%" % [round(lp.position.x), round(_fire_pos_before.x), lp.reloading, int(lp.reload_progress() * 100.0)]]


func _ft_s_three_fingers() -> void:
	_ft_set_weapon(0)
	# QA-030: same as FIRE-WHILE-MOVING — clear stretch of floor so
	# the movement check is not blocked by solid cover.
	var lp = _ft_lp()
	lp.position = Vector2(300, 1320)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_fire_shots_before = _ft_lp()._shots_fired
	_fire_pos_before = _ft_lp().position
	_ft_press_move(Vector2(60, 0))
	_ft_press_aim(Vector2(42, -42))
	_ft_press_fire()


func _ft_c_three_fingers() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.position.x > _fire_pos_before.x + 100.0 and absf(lp.aim_angle + PI * 0.25) < 0.35
	_ft_release_move()
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) x=%d (was %d) aim=%.2f" % [lp._shots_fired, _fire_shots_before, round(lp.position.x), round(_fire_pos_before.x), lp.aim_angle]]


func _ft_s_grenade_firing_a() -> void:
	_ft_set_weapon(0)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_grenade_firing_a() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and touch_firing
	return [ok, "shots=%d (was %d) firing=%s" % [lp._shots_fired, _fire_shots_before, touch_firing]]


func _ft_s_grenade_firing_b() -> void:
	var lp = _ft_lp()
	_fire_shots_before = lp._shots_fired
	_fire_grenades_before = lp.grenades
	_on_grenade_pressed()


func _ft_c_grenade_firing_b() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp.grenades == _fire_grenades_before - 1 and lp._shots_fired > _fire_shots_before and touch_firing
	_ft_release_fire()
	return [ok, "grenades=%d (was %d) shots=%d (was %d) still firing=%s" % [lp.grenades, _fire_grenades_before, lp._shots_fired, _fire_shots_before, touch_firing]]


func _ft_s_slide_off_a() -> void:
	_ft_set_weapon(0)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_slide_off_a() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and touch_firing
	return [ok, "shots=%d (was %d) firing=%s" % [lp._shots_fired, _fire_shots_before, touch_firing]]


func _ft_s_slide_off_b() -> void:
	# v3.2: unlike the old FIRE button, sliding the aim finger off
	# the stick base does NOT stop firing — the knob clamps at the
	# radius and the deflection persists (Mini Militia behaviour).
	# Only releasing the stick stops the shooting.
	_on_touch_drag(911, _ft_aim_center() + Vector2(300, 0))
	# QA-029: refresh the touch state NOW, then capture the baseline,
	# so no physics step after the drag can see a stale value.
	_update_touch_state()
	_fire_shots_before = _ft_lp()._shots_fired


func _ft_c_slide_off_b() -> Array:
	var lp = _ft_lp()
	var ok: bool = touch_firing and aim_stick.is_active() and lp._shots_fired > _fire_shots_before
	_on_touch_release(911)
	_ft_fire_owns_aim = false
	return [ok, "firing=%s aim_active=%s shots=%d (was %d)" % [touch_firing, aim_stick.is_active(), lp._shots_fired, _fire_shots_before]]


func _ft_layout_ok() -> Array:
	# No two HUD controls may overlap, and all must be inside the viewport.
	var ctrls: Array = [move_stick, aim_stick, grenade_button, switch_button, reload_button, pause_button, score_button]
	var vp := get_viewport().get_visible_rect().size
	for i in ctrls.size():
		var r1: Rect2 = (ctrls[i] as Control).get_global_rect()
		if not Rect2(Vector2.ZERO, vp).encloses(r1):
			return [false, "%s rect %s outside viewport %s" % [(ctrls[i] as Control).name, r1, vp]]
		for j in range(i + 1, ctrls.size()):
			var r2: Rect2 = (ctrls[j] as Control).get_global_rect()
			if r1.intersects(r2):
				return [false, "%s overlaps %s (%s vs %s)" % [(ctrls[i] as Control).name, (ctrls[j] as Control).name, r1, r2]]
	return [true, "7 controls, no overlaps, all inside %s" % vp]


func _ft_c_layout_1280() -> Array:
	return _ft_layout_ok()


func _ft_s_layout_1920() -> void:
	get_window().size = Vector2(1920, 1080)


func _ft_c_layout_1920() -> Array:
	var res: Array = _ft_layout_ok()
	if not bool(res[0]):
		get_window().size = Vector2(1280, 720)
		return res
	# QA-023 regression at a non-identity stretch transform: a real
	# touch at the GRENADE button's PHYSICAL position (viewport pixels)
	# must not grab a stick or fire — the router converts it to canvas
	# space first, so the fallback rect check hits.
	var phys := _to_viewport_pos(grenade_button.get_global_rect().get_center())
	var ev := InputEventScreenTouch.new()
	ev.index = 915
	ev.pressed = true
	ev.position = phys
	_unhandled_input(ev)
	var shots_before: int = _ft_lp()._shots_fired
	var ok: bool = not move_stick.is_active() and not aim_stick.is_active() and not touch_firing and _ft_lp()._shots_fired == shots_before
	ev = InputEventScreenTouch.new()
	ev.index = 915
	ev.pressed = false
	ev.position = phys
	_unhandled_input(ev)
	get_window().size = Vector2(1280, 720)
	return [ok, "layout ok at 1920x1080; physical grenade tap: sticks=%s/%s fire=%s shots stable — %s" % [move_stick.is_active(), aim_stick.is_active(), touch_firing, res[1]]]


func _ft_c_mp_sync() -> Array:
	# Server-side validation (host = this process): a first shot is
	# accepted, an immediate second is too fast, an empty magazine
	# is rejected.
	var v1: bool = shooting_sync.validate_shot(99, 0, 30)
	var v2: bool = shooting_sync.validate_shot(99, 0, 30)
	var v3: bool = shooting_sync.validate_shot(98, 0, 0)
	var ok: bool = v1 and not v2 and not v3
	shooting_sync.reset_peer(99)
	shooting_sync.reset_peer(98)
	return [ok, "validate: first=%s second-too-fast=%s empty-mag=%s" % [v1, v2, v3]]


func _ft_s_single_bullet() -> void:
	# One pistol shot (semi-auto) must create exactly one bullet.
	# QA-030: the player's own grenades (thrown earlier in this test)
	# now bounce off solid cover and can explode at point-blank range,
	# so the player may be dead or nearly dead here — revive + heal so
	# the bullet count measures shooting, not grenade damage.
	var lp0 = _ft_lp()
	if not lp0.alive:
		lp0._respawn()
	lp0.health = 100
	_ft_set_weapon(5)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(0, -60))
	_ft_press_fire()


func _ft_c_single_bullet() -> Array:
	var lp = _ft_lp()
	var n := _ft_count_bullets(lp.peer_id, 5)
	var any_n := _ft_count_bullets(lp.peer_id)
	var ok: bool = n == 1
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "active pistol bullets: %d (want 1), any-kind active: %d, shots=%d mag=%d reloading=%s" % [n, any_n, lp._shots_fired, lp.mag_ammo, lp.reloading]]


func _ft_s_pellets() -> void:
	# One shotgun shot must create exactly six pellets.
	# QA-030: same revive + heal as the single-bullet test — the
	# player must be alive and healthy to shoot.
	var lp0 = _ft_lp()
	if not lp0.alive:
		lp0._respawn()
	lp0.health = 100
	_ft_set_weapon(2)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(0, -60))
	_ft_press_fire()


func _ft_c_pellets() -> Array:
	var lp = _ft_lp()
	var n := _ft_count_bullets(lp.peer_id, 2)
	var ok: bool = n == 7 # GAP-20: shotgun is 7 pellets (spec §9), was 6
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "active shotgun pellets from one shot: %d (want 7, GAP-20 spec §9)" % n]


# =====================================================================
# v2.4 MULTIPLAYER TEST (--net-test)
# Host-side checks that run in one process (auto-host). Real two-peer
# traffic cannot run in this sandbox (UDP blocked), so the tests cover
# what one process can prove: packet build/parse, broadcast addresses,
# discovery bind, spawn idempotency, bullet trajectory + hit detection,
# local damage/death/respawn, Survival + Last Man Standing end
# conditions, disconnect cleanup, and the host-left safe exit. The
# two-device part is covered by the README testing guide instead.
# =====================================================================

func _update_nettest(delta: float) -> void:
	if _net_done:
		return
	var lp = _get_local_player()
	if lp == null:
		_net_timer += delta
		if _net_timer > 5.0:
			_net_done = true
			print("NETTEST DONE: 0/0 passed — no local player spawned")
			get_tree().quit()
		return
	if _net_steps.is_empty():
		_nettest_build_steps()
		_net_step = 0
		_net_in_step = false
		_net_timer = 0.0
	if _net_step >= _net_steps.size():
		_net_done = true
		print("NETTEST DONE: %d/%d passed" % [_net_passed, _net_passed + _net_failed])
		get_tree().quit()
		return
	var step: Dictionary = _net_steps[_net_step]
	if not _net_in_step:
		(step["setup"] as Callable).call()
		_net_in_step = true
		_net_timer = float(step["wait"])
	_net_timer -= delta
	if _net_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_net_passed += 1
		else:
			_net_failed += 1
		print("NETTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_net_step += 1
		_net_in_step = false
		_net_timer = 0.0


func _nettest_build_steps() -> void:
	_net_steps = [
		{"name": "PAYLOAD-ROUNDTRIP", "wait": 0.3, "setup": _nt_s_noop, "check": _nt_c_payload},
		{"name": "SUBNET-BROADCAST", "wait": 0.3, "setup": _nt_s_noop, "check": _nt_c_subnet},
		{"name": "DISCOVERY-BIND", "wait": 0.3, "setup": _nt_s_noop, "check": _nt_c_discovery_bind},
		{"name": "SPAWN-IDEMPOTENT", "wait": 0.3, "setup": _nt_s_spawn_idem, "check": _nt_c_spawn_idem},
		{"name": "COMBAT-HIT", "wait": 0.6, "setup": _nt_s_combat_hit, "check": _nt_c_combat_hit},
		{"name": "DOUBLE-CREDIT-SHOT1", "wait": 0.6, "setup": _nt_s_dc_shot1, "check": _nt_c_dc_shot1},
		{"name": "DOUBLE-CREDIT-SHOT2", "wait": 0.6, "setup": _nt_s_dc_shot2, "check": _nt_c_dc_shot2},
		{"name": "DAMAGE-DEATH-RESPAWN", "wait": 0.3, "setup": _nt_s_damage, "check": _nt_c_damage},
		{"name": "DAMAGE-RESPAWNED", "wait": 3.5, "setup": _nt_s_noop, "check": _nt_c_respawned},
		{"name": "MODE-SURVIVAL", "wait": 0.8, "setup": _nt_s_survival, "check": _nt_c_survival},
		{"name": "MODE-LMS", "wait": 0.8, "setup": _nt_s_lms, "check": _nt_c_lms},
		{"name": "DISCONNECT-CLEANUP", "wait": 0.5, "setup": _nt_s_disconnect, "check": _nt_c_disconnect},
		{"name": "HOST-LEFT-SAFE-EXIT", "wait": 0.3, "setup": _nt_s_host_left, "check": _nt_c_host_left},
		{"name": "DOUBLE-CREDIT", "wait": 0.3, "setup": _nt_s_double_credit, "check": _nt_c_double_credit},
		{"name": "DOUBLE-CREDIT-EXPIRE", "wait": 1.2, "setup": _nt_s_double_credit_expire, "check": _nt_c_double_credit_expire},
	]


func _nt_s_noop() -> void:
	pass


func _nt_lp():
	return _get_local_player()


func _nt_bot():
	return players_node.get_node_or_null("99")


func _nt_spawn_bot() -> Node:
	if _nt_bot() == null:
		_do_spawn(99, "TestBot", 0, 0)
	var b = _nt_bot()
	if b != null:
		b._spawn_protect_timer = 0.0
	return b


func _nt_c_payload() -> Array:
	var room := {"room_name": "Test Room", "host_name": "Host", "players": 2, "max_players": 8, "map_id": 5, "mode": 1, "status": "lobby", "port": 7777, "private": true}
	var pkt := LanDiscovery.build_room_packet(room)
	var back := LanDiscovery.parse_room_packet(pkt.get_string_from_utf8(), "192.168.1.7")
	var ok: bool = back["room_name"] == "Test Room" and back["host_name"] == "Host" and int(back["players"]) == 2 and int(back["max_players"]) == 8 and int(back["map_id"]) == 5 and int(back["mode"]) == 1 and back["status"] == "lobby" and int(back["port"]) == 7777 and bool(back["private"]) and back["ip"] == "192.168.1.7"
	# Malformed packets must be rejected, not crash.
	var bad := LanDiscovery.parse_room_packet("LANARENA|1|only", "1.2.3.4")
	var bad2 := LanDiscovery.parse_room_packet("GARBAGE|1|a|b|1|8|0|0|lobby|7777|0", "1.2.3.4")
	ok = ok and bad.is_empty() and bad2.is_empty()
	return [ok, "round-trip fields match, malformed rejected: %s" % ok]


func _nt_c_subnet() -> Array:
	var addrs := LanDiscovery.broadcast_addresses()
	var ok: bool = addrs.has("255.255.255.255")
	var lan := LanDiscovery.lan_ip()
	if lan != "":
		var parts := lan.split(".")
		var expect := "%s.%s.%s.255" % [parts[0], parts[1], parts[2]]
		ok = ok and addrs.has(expect)
	return [ok, "broadcast addrs=%s lan_ip=%s" % [addrs, lan]]


func _nt_c_discovery_bind() -> Array:
	var d := LanDiscovery.new()
	add_child(d)
	var bound: bool = d.start_listening()
	d.broadcast_room({"room_name": "T", "host_name": "H", "players": 1, "max_players": 8, "map_id": 0, "mode": 0, "status": "lobby", "port": 7777, "private": false})
	d.stop()
	d.queue_free()
	return [bound, "listener bound=%s (false means UDP is blocked in this sandbox)" % bound]


func _nt_s_spawn_idem() -> void:
	# request_spawn is idempotent on the server: three identical
	# requests must still leave exactly one local player. (The
	# host's _announce_ready is a no-op — it spawned via
	# _spawn_self — so the handler is exercised directly here.)
	request_spawn(1, "Host", 0, 0)
	request_spawn(1, "Host", 0, 0)
	request_spawn(1, "Host", 0, 0)


func _nt_c_spawn_idem() -> Array:
	var n := players_node.get_child_count()
	var ok: bool = n == 1 and _get_local_player() != null
	return [ok, "players after 3x announce: %d (want 1)" % n]


func _nt_s_combat_hit() -> void:
	var lp = _nt_lp()
	_ft_set_weapon(5)
	lp.position = Vector2(300, 1320)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = _nt_spawn_bot()
	if b != null:
		b.position = Vector2(600, 1320)
		b.sync_position = b.position
		b.velocity = Vector2.ZERO
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _nt_c_combat_hit() -> Array:
	var lp = _nt_lp()
	# One pistol shot at a player 300 px away: the bullet must have
	# hit (despawned on impact) instead of flying on (0.9 s life).
	var n := _ft_count_bullets(lp.peer_id, 5)
	var ok: bool = lp._shots_fired >= 1 and n == 0
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "shots=%d active pistol bullets after 0.6 s: %d (want 0 = hit)" % [lp._shots_fired, n]]


func _nt_s_dc_shot1() -> void:
	# QA-031 end-to-end: the victim bot sits at 5 HP and the local
	# player fires one lethal pistol shot at it. The host's copy of
	# the bot's health never drops in this harness (take_hit goes to
	# the fake peer 99, which is not connected), so this reproduces
	# the stale-health condition that used to double-credit kills.
	var lp = _nt_lp()
	_ft_set_weapon(5)
	lp.position = Vector2(300, 1320)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = _nt_bot()
	if b != null:
		b.position = Vector2(600, 1320)
		b.sync_position = b.position
		b.velocity = Vector2.ZERO
		b._spawn_protect_timer = 0.0
		b.health = 5
	_nt_dc_kills_a = lp.kills
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _nt_c_dc_shot1() -> Array:
	var lp = _nt_lp()
	var ok: bool = lp.kills == _nt_dc_kills_a + 1
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "kills %d->%d after first lethal bullet (want +1)" % [_nt_dc_kills_a, lp.kills]]


func _nt_s_dc_shot2() -> void:
	# Second lethal bullet at the same 5 HP victim, inside the 1 s
	# lock window: the host must deny the second credit.
	var lp = _nt_lp()
	_nt_dc_kills_a = lp.kills
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _nt_c_dc_shot2() -> Array:
	var lp = _nt_lp()
	var ok: bool = lp.kills == _nt_dc_kills_a
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "kills %d->%d after second lethal bullet (want +0)" % [_nt_dc_kills_a, lp.kills]]


func _nt_s_damage() -> void:
	var lp = _nt_lp()
	# Spawn protection (2 s) would swallow the damage: clear it.
	lp._spawn_protect_timer = 0.0
	lp.take_damage(30, 1)


func _nt_c_damage() -> Array:
	var lp = _nt_lp()
	var health_after_30: int = lp.health
	var ok: bool = health_after_30 == 70 and lp.alive
	if ok:
		lp.take_damage(500, 1)
		ok = not lp.alive and lp.deaths == 1
	return [ok, "health after 30 dmg: %d, dead after lethal: %s" % [health_after_30, not lp.alive]]


func _nt_c_respawned() -> Array:
	var lp = _nt_lp()
	var ok: bool = lp.alive and lp.health == 100
	game_mode = 0
	return [ok, "respawned alive=%s health=%d" % [lp.alive, lp.health]]


func _nt_s_survival() -> void:
	# Survival, first to 1 round: kill the only other player and the
	# local player must win the round and the match.
	game_mode = 2
	kill_limit = 1
	match_over = false
	_round_wins.clear()
	var b = _nt_spawn_bot()
	if b != null and not b.alive:
		b._respawn()
		b._spawn_protect_timer = 0.0
	if b != null:
		b.take_damage(500, 1)


func _nt_c_survival() -> Array:
	var over: bool = match_over
	var ok: bool = over and int(_round_wins.get(1, 0)) == 1
	match_over = false
	end_panel.visible = false
	return [ok, "match_over=%s rounds won by host=%d (want 1)" % [over, int(_round_wins.get(1, 0))]]


func _nt_s_lms() -> void:
	# Last Man Standing: kill the only other player; the local
	# player must be the last one standing and the match must end.
	game_mode = 3
	match_over = false
	var b = _nt_spawn_bot()
	if b != null and not b.alive:
		b._respawn()
		b._spawn_protect_timer = 0.0
	if b != null:
		b.take_damage(500, 1)


func _nt_c_lms() -> Array:
	var over: bool = match_over
	var ok: bool = over
	match_over = false
	end_panel.visible = false
	game_mode = 0
	# QA-031: MODE-SURVIVAL left kill_limit = 1 behind; with the
	# DOUBLE-CREDIT-SHOT steps crediting the local player a kill,
	# the per-frame FFA check would end the match instantly once
	# FFA resumes (1 kill >= limit 1) and break HOST-LEFT-SAFE-EXIT.
	kill_limit = GameData.kill_limit
	return [ok, "match_over=%s (want true, local player last standing)" % over]


func _nt_s_disconnect() -> void:
	_nt_spawn_bot()
	_on_peer_disconnected(99)


func _nt_c_disconnect() -> Array:
	var ok: bool = players_node.get_node_or_null("99") == null and not _spawned.has(99)
	return [ok, "bot node gone=%s spawned erased=%s" % [players_node.get_node_or_null("99") == null, not _spawned.has(99)]]


func _nt_s_host_left() -> void:
	GameData.host_ip = "192.168.1.5"
	_on_server_disconnected()


func _nt_c_host_left() -> Array:
	var vis: bool = error_panel.visible
	var ok: bool = vis and GameData.last_host_ip == "192.168.1.5"
	error_panel.visible = false
	_join_failed = false
	return [ok, "error panel visible=%s last_host_ip=%s (want 192.168.1.5)" % [vis, GameData.last_host_ip]]


func _nt_s_double_credit() -> void:
	# QA-031 (T-56): two shooters land lethal hits on the same victim
	# in the same tick. The host must credit exactly ONE kill (to the
	# first shooter) and deny the second.
	# No fake nodes are spawned: try_credit_kill only needs the
	# killer node (peer 1, the local player) — the victim and the
	# second shooter are bare ids, and a shooter with no node simply
	# gets no add_kill, exactly as in production when the shooter
	# has disconnected mid-flight.
	var lp = _nt_lp()
	_nt_dc_kills_a = lp.kills
	_nt_dc_first = try_credit_kill(1, 99, 5)
	_nt_dc_second = try_credit_kill(98, 99, 5)


func _nt_c_double_credit() -> Array:
	var lp = _nt_lp()
	var ok: bool = _nt_dc_first and not _nt_dc_second
	ok = ok and lp.kills == _nt_dc_kills_a + 1
	return [ok, "first=%s second=%s kills A %d->%d (want +1)" % [_nt_dc_first, _nt_dc_second, _nt_dc_kills_a, lp.kills]]


func _nt_s_double_credit_expire() -> void:
	# The lock must expire: record the local player's kills now;
	# the check runs 1.2 s later, past the 1 s lock, and a fresh
	# credit must succeed (the victim's next life is never blocked).
	# The credit goes through the local player because a fake remote
	# peer can never receive its add_kill RPC in this harness.
	var lp = _nt_lp()
	_nt_dc_kills_a = lp.kills


func _nt_c_double_credit_expire() -> Array:
	var lp = _nt_lp()
	var third: bool = try_credit_kill(1, 99, 5)
	var ok: bool = third and lp.kills == _nt_dc_kills_a + 1
	return [ok, "third credit after 1.2 s=%s kills A %d->%d (want +1)" % [third, _nt_dc_kills_a, lp.kills]]


# =====================================================================
# v2.4 FULL-FLOW CHECK (game side, --flow-test)
# The menu side (main.gd) already verified menu -> create room ->
# lobby with the host IP shown, then started the match and handed
# over via GameData.flow_phase. This side verifies: match loaded ->
# play (fire) -> pause -> resume -> scoreboard -> end screen ->
# back to the main menu. The menu prints the final result.
# =====================================================================

func _update_flowtest(delta: float) -> void:
	if _flow_done:
		return
	var lp = _get_local_player()
	if lp == null:
		_flow_timer += delta
		if _flow_timer > 5.0:
			_flow_done = true
			print("FLOWTEST DONE: 0/0 passed — no local player spawned")
			get_tree().quit()
		return
	if _flow_steps.is_empty():
		_flowtest_build_steps()
		_flow_step = 0
		_flow_in_step = false
		_flow_timer = 0.0
	if _flow_step >= _flow_steps.size():
		_flow_done = true
		print("FLOWTEST GAME: %d/%d passed" % [_flow_passed, _flow_passed + _flow_failed])
		return
	var step: Dictionary = _flow_steps[_flow_step]
	if not _flow_in_step:
		(step["setup"] as Callable).call()
		_flow_in_step = true
		_flow_timer = float(step["wait"])
	_flow_timer -= delta
	if _flow_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_flow_passed += 1
		else:
			_flow_failed += 1
		print("FLOWTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_flow_step += 1
		_flow_in_step = false
		_flow_timer = 0.0


func _flowtest_build_steps() -> void:
	_flow_steps = [
		{"name": "MATCH-LOADED", "wait": 0.5, "setup": _fl_s_noop, "check": _fl_c_loaded},
		{"name": "PLAY-FIRE", "wait": 0.5, "setup": _fl_s_fire, "check": _fl_c_fire},
		{"name": "PAUSE", "wait": 0.3, "setup": _fl_s_pause, "check": _fl_c_paused},
		{"name": "RESUME", "wait": 0.3, "setup": _fl_s_resume, "check": _fl_c_resumed},
		{"name": "SCOREBOARD", "wait": 0.3, "setup": _fl_s_score, "check": _fl_c_score},
		{"name": "END-MATCH", "wait": 0.5, "setup": _fl_s_end, "check": _fl_c_end},
		{"name": "BACK-TO-MENU", "wait": 0.3, "setup": _fl_s_back, "check": _fl_c_back},
	]


func _fl_s_noop() -> void:
	pass


func _fl_c_loaded() -> Array:
	var lp = _get_local_player()
	var ok: bool = lp != null and lp.alive and not match_over
	return [ok, "local player alive=%s match_over=%s" % [lp != null and lp.alive, match_over]]


func _fl_s_fire() -> void:
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _fl_c_fire() -> Array:
	var lp = _get_local_player()
	var ok: bool = lp._shots_fired > 0
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "shots fired in the match: %d" % lp._shots_fired]


func _fl_s_pause() -> void:
	_toggle_pause()


func _fl_c_paused() -> Array:
	var ok: bool = get_tree().paused and pause_panel.visible
	# LOOP 5: synchronous capture — the async _capture_shot lands
	# after the RESUME step and shows the unpaused game instead.
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://shot_pause.png")
	print("FLOW SHOT NOW: user://shot_pause.png err=", err, " size=", img.get_size())
	return [ok, "paused=%s pause panel visible=%s" % [get_tree().paused, pause_panel.visible]]


func _fl_s_resume() -> void:
	_toggle_pause()


func _fl_c_resumed() -> Array:
	var ok: bool = not get_tree().paused and not pause_panel.visible
	return [ok, "paused=%s pause panel visible=%s" % [get_tree().paused, pause_panel.visible]]


func _fl_s_score() -> void:
	_on_score_pressed()


func _fl_c_score() -> Array:
	var shown: bool = scoreboard_panel.visible
	# LOOP 5: synchronous capture before closing — the async version
	# landed after the END-MATCH step and showed the end screen.
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://shot_scoreboard.png")
	print("FLOW SHOT NOW: user://shot_scoreboard.png err=", err, " size=", img.get_size())
	_on_score_pressed()
	var ok: bool = shown and not scoreboard_panel.visible
	return [ok, "scoreboard opened=%s closed again=%s" % [shown, not scoreboard_panel.visible]]


func _fl_s_end() -> void:
	_end_match("FlowTest", "flow check")


func _fl_c_end() -> Array:
	var ok: bool = match_over and end_panel.visible
	# LOOP 5: synchronous capture — the next step changes scene, so
	# the async _capture_shot would die before saving.
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("user://shot_end.png")
	print("FLOW SHOT NOW: user://shot_end.png err=", err, " size=", img.get_size())
	return [ok, "match_over=%s end panel visible=%s" % [match_over, end_panel.visible]]


func _fl_s_back() -> void:
	# Hand the check back to the menu: it prints the final result
	# when the main scene loads again.
	GameData.flow_phase = 2
	_on_leave_pressed()


func _fl_c_back() -> Array:
	# The scene change happens in _on_leave_pressed; this check is
	# only reached if the change did not happen.
	return [false, "still in the game scene after Back"]


# =====================================================================
# Phase 3B PHYSICS TEST (--physics-test, GAP-73/T-01..T-75 support)
# Headless harness driving the REAL player + touch path. Each step is
# {name, wait, setup, check}; check returns [passed, detail]. Run:
#   xvfb-run -a godot --path . -- --auto-host --physics-test
#   xvfb-run -a godot --path . -- --auto-host --map=4 --physics-test
# (map 4 = Frozen Fortress, for the live ice-slide step).
# =====================================================================

func _phys_lp():
	return _get_local_player()


func _phys_teleport(pos: Vector2) -> void:
	var lp = _phys_lp()
	lp.position = pos
	lp.sync_position = pos
	lp.velocity = Vector2.ZERO


func _update_physicstest(delta: float) -> void:
	if _phys_done:
		return
	var lp = _get_local_player()
	if lp == null:
		_phys_timer += delta
		if _phys_timer > 5.0:
			_phys_done = true
			print("PHYSICSTEST DONE: 0/0 passed — no local player spawned")
			get_tree().quit()
		return
	# Live tracking for in-flight steps (apex, grenade bounce/rest).
	if bool(_phys_data.get("track_min_y", false)):
		_phys_data["min_y"] = minf(float(_phys_data.get("min_y", 1e9)), lp.position.y)
	if bool(_phys_data.get("track_t300", false)) and not _phys_data.has("t300"):
		if lp.velocity.x >= 300.0:
			_phys_data["t300"] = Time.get_ticks_msec() / 1000.0 - float(_phys_data.get("t0", 0.0))
	if bool(_phys_data.get("track_max_vy", false)):
		_phys_data["max_vy"] = maxf(float(_phys_data.get("max_vy", 0.0)), lp.velocity.y)
	var g = _phys_data.get("grenade", null)
	if g != null and is_instance_valid(g):
		_phys_data["g_bounced"] = bool(g.get("bounced"))
		_phys_data["g_resting"] = bool(g.get("_resting"))
	if _phys_steps.is_empty():
		_physicstest_build_steps()
		_phys_step = 0
		_phys_in_step = false
		_phys_timer = 0.0
	if _phys_step >= _phys_steps.size():
		_phys_done = true
		print("PHYSICSTEST DONE: %d/%d passed" % [_phys_passed, _phys_passed + _phys_failed])
		get_tree().quit()
		return
	var step: Dictionary = _phys_steps[_phys_step]
	if int(step.get("skip_map", -1)) == map_id:
		print("PHYSICSTEST %s: SKIP — not applicable on map %d (%s)" % [String(step["name"]), map_id, String(step.get("skip_reason", ""))])
		_phys_step += 1
		_phys_in_step = false
		_phys_timer = 0.0
		return
	# Phase 5: "only_map" — a step that only applies on one map
	# (P18b ice slide needs Frozen Fortress's ice).
	if step.has("only_map") and int(step["only_map"]) != map_id:
		print("PHYSICSTEST %s: SKIP — only applicable on map %d (%s)" % [String(step["name"]), int(step["only_map"]), String(step.get("skip_reason", ""))])
		_phys_step += 1
		_phys_in_step = false
		_phys_timer = 0.0
		return
	if not _phys_in_step:
		(step["setup"] as Callable).call()
		_phys_in_step = true
		_phys_timer = float(step["wait"])
	_phys_timer -= delta
	if _phys_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_phys_passed += 1
		else:
			_phys_failed += 1
		print("PHYSICSTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_phys_step += 1
		_phys_in_step = false
		_phys_timer = 0.0


func _physicstest_build_steps() -> void:
	_phys_steps = [
		{"name": "P00-pickups-at-start", "wait": 0.5, "setup": _phys_s_noop, "check": _phys_c_pickups_start},
		{"name": "P01-ground-accel", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 2.0, "setup": _phys_s_ground_run, "check": _phys_c_ground_accel},
		{"name": "P02-air-accel", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 2.0, "setup": _phys_s_air_run, "check": _phys_c_air_accel},
		{"name": "P03-analog-half", "wait": 0.8, "setup": _phys_s_analog, "check": _phys_c_analog},
		{"name": "P04a-ground-run", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 0.6, "setup": _phys_s_ground_stop_run, "check": _phys_c_ground_run},
		{"name": "P04b-ground-stop", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 0.5, "setup": _phys_s_ground_stop_release, "check": _phys_c_ground_stop},
		{"name": "P05a-air-run", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 0.1, "setup": _phys_s_air_slide, "check": _phys_c_air_run},
		{"name": "P05b-air-slide", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 0.9, "setup": _phys_s_air_slide_release, "check": _phys_c_air_slide},
		{"name": "P06-terminal-velocity", "wait": 2.0, "setup": _phys_s_fall, "check": _phys_c_terminal},
		{"name": "P07a-jump-hold-apex", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 0.7, "setup": _phys_s_jump_hold, "check": _phys_c_jump_hold},
		{"name": "P07b-jump-tap-apex", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 0.7, "setup": _phys_s_jump_tap, "check": _phys_c_jump_tap},
		{"name": "P08-fuel-regen-delay", "wait": 0.3, "setup": _phys_s_fuel_drain, "check": _phys_c_fuel_delay},
		{"name": "P08b-fuel-regen-after", "wait": 1.2, "setup": _phys_s_noop, "check": _phys_c_fuel_after},
		{"name": "P09a-aim-hold-setup", "wait": 0.5, "setup": _phys_s_aim_hold, "check": _phys_c_aim_hold_setup},
		{"name": "P09b-aim-hold", "wait": 0.4, "setup": _phys_s_noop, "check": _phys_c_aim_hold},
		{"name": "P10-aim-deadzone", "wait": 0.3, "setup": _phys_s_aim_deadzone, "check": _phys_c_aim_deadzone},
		{"name": "P11-shotgun-table", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_shotgun_table},
		{"name": "P12-damage-calc", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_damage_calc},
		{"name": "P13-explosion-falloff", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_explosion_falloff},
		{"name": "P14-respawn-validation", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_respawn_valid},
		{"name": "P15-grenade-bounce", "wait": 1.8, "setup": _phys_s_grenade, "check": _phys_c_grenade},
		{"name": "P16-velocity-inheritance", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_inheritance},
		{"name": "P17-recoil-accum", "wait": 0.1, "setup": _phys_s_recoil_fire, "check": _phys_c_recoil},
		{"name": "P17b-recoil-decay", "wait": 2.0, "setup": _phys_s_noop, "check": _phys_c_recoil_decay},
		{"name": "P18a-ice-run", "wait": 0.5, "setup": _phys_s_ice, "check": _phys_c_ice},
		{"name": "P18b-ice-slide", "wait": 1.5, "setup": _phys_s_noop, "check": _phys_c_ice_slide, "only_map": 4, "skip_reason": "ice slide needs Frozen Fortress"},
		{"name": "P19-camera", "wait": 0.4, "setup": _phys_s_camera, "check": _phys_c_camera},
		{"name": "P20-pool-budget", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_pool},
		{"name": "P21-version-handshake", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_version},
		{"name": "P22-barrel", "skip_map": 4, "skip_reason": "placement tuned for Catacombs (map 0)", "wait": 0.1, "setup": _phys_s_barrel, "check": _phys_c_barrel},
		{"name": "P23-bounce-pad", "wait": 0.12, "setup": _phys_s_pad, "check": _phys_c_pad},
		{"name": "P24-stuck-recovery", "wait": 0.1, "setup": _phys_s_stuck, "check": _phys_c_stuck},
	]


func _phys_s_noop() -> void:
	pass


func _phys_c_pickups_start() -> Array:
	var n := pickups_node.get_child_count()
	return [n == 3, "pickups at match start: %d (want 3)" % n]


func _phys_s_ground_run() -> void:
	# Time-to-300 tracking: physics ticks lag real time in xvfb, so a
	# fixed 0.15 s window under-measures. Ground (2600) must reach
	# 300 px/s clearly faster than air (1500); lag scales both.
	# Phase 5: start on the map's own spawn#0 (on the floor on every
	# map) — the old fixed (300, 1320) is mid-air on taller maps
	# (e.g. Neon City), so the "ground" time was measured in the air.
	_phys_teleport((MAPS[map_id]["spawns"] as Array)[0])
	_phys_data["t0"] = Time.get_ticks_msec() / 1000.0
	_phys_data.erase("t300")
	_phys_data["track_t300"] = true
	_jt_press_move(Vector2(60, 0))


func _phys_c_ground_accel() -> Array:
	_phys_data["track_t300"] = false
	_jt_release_move()
	var t: float = float(_phys_data.get("t300", -1.0))
	_phys_data["t300_ground"] = t
	var ok: bool = t > 0.0 and t < 0.8
	return [ok, "ground time to 300 px/s: %.2f s (want <0.8, accel 2600)" % t]


func _phys_s_air_run() -> void:
	_phys_teleport(Vector2(2100, 700))
	_phys_data["t0"] = Time.get_ticks_msec() / 1000.0
	_phys_data.erase("t300")
	_phys_data["track_t300"] = true
	_jt_press_move(Vector2(60, 0))


func _phys_c_air_accel() -> Array:
	_phys_data["track_t300"] = false
	_jt_release_move()
	var t: float = float(_phys_data.get("t300", -1.0))
	var tg: float = float(_phys_data.get("t300_ground", 0.2))
	var ok: bool = t > 0.0 and t > tg * 1.3
	return [ok, "air time to 300 px/s: %.2f s vs ground %.2f s (want air >1.3x ground, accel 1500 < 2600)" % [t, tg]]


func _phys_s_analog() -> void:
	_phys_teleport(Vector2(300, 1320))
	_jt_press_move(Vector2(30, 0))


func _phys_c_analog() -> Array:
	var lp = _phys_lp()
	# 50% deflection -> (0.5-0.2)/0.8 = 0.375 magnitude -> ~131 px/s.
	var ok: bool = lp.velocity.x > 100.0 and lp.velocity.x < 165.0
	_jt_release_move()
	return [ok, "half-stick vel.x: %d (want ~131, dead-zone-rescaled 0.375 x 350)" % round(lp.velocity.x)]


func _phys_s_ground_stop_run() -> void:
	# Phase 5: spawn#0, as in _phys_s_ground_run (the fixed
	# (300, 1320) is mid-air on taller maps).
	_phys_teleport((MAPS[map_id]["spawns"] as Array)[0])
	_jt_press_move(Vector2(60, 0))
	_phys_data["stop_x0"] = 300.0


func _phys_c_ground_run() -> Array:
	var lp = _phys_lp()
	_phys_data["stop_x0"] = lp.position.x
	_jt_release_move()
	return [lp.velocity.x > 300.0, "ground run vel.x=%d (want >300 before release)" % round(lp.velocity.x)]


func _phys_s_ground_stop_release() -> void:
	pass


func _phys_c_ground_stop() -> Array:
	var lp = _phys_lp()
	var dist: float = lp.position.x - float(_phys_data.get("stop_x0", 0.0))
	return [absf(lp.velocity.x) < 60.0 and dist < 120.0,
		"ground stop: vel.x=%d dist=%.0f px after 0.5 s (want <60 and <120 px)" % [round(lp.velocity.x), dist]]


func _phys_s_air_slide() -> void:
	# Air slide, drag-only model (GAP-03): start airborne at 350 px/s
	# with no input. Open sky at x=1000 (no platform below until the
	# floor) so the player stays airborne for the whole second.
	_phys_teleport(Vector2(1000, 200))
	_jt_release_move()
	var lp = _phys_lp()
	lp.velocity = Vector2(350, 0)
	_phys_data["slide_x0"] = 1000.0


func _phys_c_air_run() -> Array:
	# Not used as a separate check any more; kept for step ordering.
	return [true, "air slide setup done"]


func _phys_s_air_slide_release() -> void:
	pass


func _phys_c_air_slide() -> Array:
	var lp = _phys_lp()
	var dist: float = lp.position.x - float(_phys_data.get("slide_x0", 0.0))
	# Drag 1.2: vx(1 s) ~= 105, dist ~= 204 px — many times the
	# ~21-36 px ground stop (T-05/T-06: air slide >= 2x ground stop).
	var ground_stop: float = 36.0
	return [dist > 120.0 and absf(lp.velocity.x) > 60.0 and dist > 2.0 * ground_stop,
		"air slide: dist=%.0f px in 1 s, vel.x=%d (want >120 px, >60, >2x ground stop)" % [dist, round(lp.velocity.x)]]


func _phys_s_fall() -> void:
	# x=1000 falls to the y=1010 platform; max vy is tracked so the
	# check does not depend on sampling the exact landing frame.
	# QA-033: on the rebuilt Frozen Fortress (map 4) the Perch at
	# (950,500) cuts the x=1000 fall to 182 px (max vy 677, want
	# 950-1050). Use x=400 instead: a clear fall to the Top L
	# platform (670), 452 px — enough to hit the 1000 cap.
	if map_id == 4:
		_phys_teleport(Vector2(400, 200))
	else:
		_phys_teleport(Vector2(1000, 300))
	_phys_data["max_vy"] = 0.0
	_phys_data["track_max_vy"] = true


func _phys_c_terminal() -> Array:
	_phys_data["track_max_vy"] = false
	var m: float = float(_phys_data.get("max_vy", 0.0))
	var ok: bool = m >= 950.0 and m <= 1050.0
	return [ok, "max fall vel.y=%.0f (want 950-1050, cap 1000)" % m]


# Phase 5 — physics harness helper: the ground (lowest platform top)
# at map x, so jump/grenade/respawn setups land on a floor on every
# map instead of a Catacombs-tuned coordinate.
func _phys_ground_at(x: float) -> Vector2:
	var best_top := -1.0
	for p in (MAPS[map_id]["platforms"] as Array):
		var r: Rect2 = p
		if r.position.x <= x and x <= r.end.x and r.position.y > best_top:
			best_top = r.position.y
	if best_top < 0.0:
		best_top = float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	return Vector2(x, best_top - 26.0)


func _phys_s_jump_hold() -> void:
	# Open sky at x=2100 (the old x=300 spot has a platform at y=1180
	# directly overhead — the player bonked it at 66 px, not 155).
	# fuel=0: holding stick-up must NOT jetpack, or the "hold" apex
	# measures jump+jetpack (~300 px) instead of the jump (~155 px).
	# The 999 s regen delay stops air regen re-enabling the jetpack
	# mid-rise (which also used to clamp the jump via the rise cap).
	# Phase 5: stand on the ground at x=2100 (the fixed (2100, 1320)
	# is mid-air on taller maps, so the tap's 0.15 s release fired
	# before the player had even landed).
	var gp := _phys_ground_at(2100.0)
	_phys_teleport(gp)
	var lp = _phys_lp()
	lp.fuel = 0.0
	lp._fuel_delay_timer = 999.0
	_phys_data["track_min_y"] = true
	_phys_data["min_y"] = gp.y + 6.0
	_phys_data["jump_y0"] = gp.y + 6.0
	_jt_press_move(Vector2(0, -60))


func _phys_c_jump_hold() -> Array:
	_jt_release_move()
	_phys_data["track_min_y"] = false
	_phys_lp().fuel = 100.0
	_phys_lp()._fuel_delay_timer = 0.0
	var apex := float(_phys_data.get("jump_y0", 1326.0)) - float(_phys_data.get("min_y", 1326.0))
	_phys_data["hold_apex"] = apex
	return [apex > 130.0 and apex < 185.0, "hold jump apex: %d px (want ~155)" % round(apex)]


func _phys_s_jump_tap() -> void:
	# Phase 5: same ground-at-x fix as _phys_s_jump_hold — the fixed
	# (2100, 1320) is mid-air on taller maps.
	var gp := _phys_ground_at(2100.0)
	_phys_teleport(gp)
	var lp = _phys_lp()
	lp.fuel = 0.0
	lp._fuel_delay_timer = 999.0
	_phys_data["track_min_y"] = true
	_phys_data["min_y"] = gp.y + 6.0
	_phys_data["jump_y0"] = gp.y + 6.0
	_jt_press_move(Vector2(0, -60))
	# Tap: release after a short hold via a timer.
	# QA-047: 0.15 s was the load-flake — under a loaded machine
	# the timer fires late in physics time and the tap apex crept
	# to 124 px (cap 120). 0.12 s leaves the same margin on a fast
	# machine (apex still >50 px) with less exposure to late firing.
	get_tree().create_timer(0.12).timeout.connect(_jt_release_move)


func _phys_c_jump_tap() -> Array:
	_phys_data["track_min_y"] = false
	_phys_lp().fuel = 100.0
	_phys_lp()._fuel_delay_timer = 0.0
	var apex := float(_phys_data.get("jump_y0", 1326.0)) - float(_phys_data.get("min_y", 1326.0))
	var hold_apex: float = float(_phys_data.get("hold_apex", 155.0))
	return [apex > 50.0 and apex < 120.0 and apex < hold_apex - 40.0,
		"tap jump apex: %d px vs hold %d px (want tap 50-120, clearly lower)" % [round(apex), round(hold_apex)]]


func _phys_s_fuel_drain() -> void:
	var lp = _phys_lp()
	_phys_teleport(Vector2(300, 1320))
	lp.fuel = 0.0
	lp._fuel_delay_timer = 0.6


func _phys_c_fuel_delay() -> Array:
	var lp = _phys_lp()
	return [lp.fuel < 2.0, "fuel 0.3 s after empty: %.1f (want <2, regen delay 0.6 s)" % lp.fuel]


func _phys_c_fuel_after() -> Array:
	var lp = _phys_lp()
	return [lp.fuel > 20.0, "fuel 1.5 s after empty: %.1f (want >20, regen 70/s on ground)" % lp.fuel]


func _phys_s_aim_hold() -> void:
	_phys_teleport(Vector2(1600, 1320))
	_jt_press_aim(Vector2(42, -42))
	_phys_data["aim_before"] = 0.0


func _phys_c_aim_hold_setup() -> Array:
	var lp = _phys_lp()
	_phys_data["aim_before"] = lp.aim_angle
	# Release the aim stick, keep moving right; the hold is verified
	# in the next step, after physics frames have run.
	_jt_release_aim()
	_jt_press_move(Vector2(60, 0))
	return [absf(lp.aim_angle - (-PI / 4.0)) < 0.1, "aim while aiming: %.2f rad (want -0.79)" % lp.aim_angle]


func _phys_c_aim_hold() -> Array:
	var lp = _phys_lp()
	_jt_release_move()
	var ok: bool = absf(lp.aim_angle - float(_phys_data.get("aim_before", -PI / 4.0))) < 0.05
	return [ok, "aim after release+move: %.2f rad (want -0.79, no snap to facing)" % lp.aim_angle]


func _phys_s_aim_deadzone() -> void:
	var lp = _phys_lp()
	_phys_data["aim_before"] = lp.aim_angle
	_jt_press_aim(Vector2(8, 0)) # 13% deflection, below the 0.20 dead zone


func _phys_c_aim_deadzone() -> Array:
	var lp = _phys_lp()
	var ok: bool = touch_aim == Vector2.ZERO and absf(lp.aim_angle - float(_phys_data.get("aim_before", 0.0))) < 0.05
	_jt_release_aim()
	return [ok, "small aim deflection: touch_aim=%s aim unchanged (want zero vector)" % str(touch_aim)]


func _phys_c_shotgun_table() -> Array:
	var w: Dictionary = WeaponData.TABLE[2]
	var ok: bool = int(w["pellets"]) == 7 and absf(float(WeaponData.TABLE[0]["rate"]) - 0.125) < 0.001 and absf(float(WeaponData.TABLE[4]["speed"]) - 450.0) < 0.01 and absf(float(WeaponData.TABLE[4]["gravity"]) - 500.0) < 0.01
	return [ok, "shotgun pellets=%d rifle rate=%.3f rocket speed=%d gravity=%d (want 7 / 0.125 / 450 / 500)" % [int(w["pellets"]), float(WeaponData.TABLE[0]["rate"]), int(WeaponData.TABLE[4]["speed"]), int(WeaponData.TABLE[4]["gravity"])]]


func _phys_c_damage_calc() -> Array:
	var lp = _phys_lp()
	var head: int = lp.calculate_damage(12, "head", 100.0, 0)
	var torso: int = lp.calculate_damage(12, "torso", 100.0, 0)
	var legs: int = lp.calculate_damage(12, "legs", 100.0, 0)
	var ok: bool = head == 18 and torso == 12 and legs == 9
	return [ok, "rifle 12 dmg: head=%d torso=%d legs=%d (want 18/12/9)" % [head, torso, legs]]


func _phys_c_explosion_falloff() -> Array:
	# Smooth curve D = Dmax*(1-u^2)^2: centre 55, mid (u=0.5) ~31, edge ~0.
	var c := int(round(55.0 * pow(1.0 - 0.0, 2.0)))
	var m := int(round(55.0 * pow(1.0 - 0.25, 2.0)))
	var e := int(round(55.0 * pow(1.0 - pow(165.0 / 170.0, 2.0), 2.0)))
	var ok: bool = c == 55 and m == 31 and e <= 5
	return [ok, "grenade 55 dmg radius 170: centre=%d mid=%d edge=%d (want 55/31/0-5)" % [c, m, e]]


func _phys_c_respawn_valid() -> Array:
	# Phase 5: the "inside the floor" point is map-relative (the old
	# fixed (1600, 1370) is open air above the skybridge on Neon
	# City). plats[0] is the lowest floor/deck on every map.
	var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	var bad := is_spawn_valid(Vector2(map_size.x * 0.5, floor_top + 18.0), 1) # inside the floor slab
	var good := get_valid_spawn_point(1, 1) != Vector2.INF
	return [not bad and good, "spawn inside floor valid=%s, valid spawn found=%s (want false/true)" % [str(bad), str(good)]]


func _phys_s_grenade() -> void:
	_phys_teleport(Vector2(300, 1320))
	var g = load("res://grenade.tscn").instantiate()
	g.name = "phys_grenade"
	# Open sky: the old (1600,1000) spot is INSIDE the solid crate
	# at (1600,1010) — the grenade wedged there and never fell.
	# Phase 5: throw from 250 px above the map's floor, so the fall
	# distance (and the 1.8 s settle window) is the same on every map.
	var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	g.position = Vector2(2100, floor_top - 250.0)
	# Phase 5: straight down — the old (0.2, 0.3) drift rolled the
	# grenade off Space Station's deck B and Airship Fleet's net
	# before it could rest (want a bounce + rest on the platform
	# below the throw point, on every map).
	g.throw_dir = Vector2(0, 1)
	g.owner_id = 1
	grenades_node.add_child(g)
	_phys_data["grenade"] = g
	_phys_data["g_bounced"] = false
	_phys_data["g_max_vy"] = 0.0
	_phys_data["g_resting"] = false


func _phys_c_grenade() -> Array:
	var g = _phys_data.get("grenade", null)
	var bounced := bool(_phys_data.get("g_bounced", false))
	var resting := bool(_phys_data.get("g_resting", false))
	var gone := g == null or not is_instance_valid(g)
	return [bounced and resting and not gone, "grenade bounced=%s resting=%s exploded-early=%s (want true/true/false)" % [str(bounced), str(resting), str(gone)]]


func _phys_c_inheritance() -> Array:
	var b = obtain_bullet()
	var want := Vector2(1, 0) * 1100.0 + Vector2(330, 0) * 0.15
	b.setup(Vector2(100, 100), Vector2(1, 0), 1100.0, 12, 0, 1, false, 0.0, 1.2, 1, want, 0.0)
	var ok: bool = absf(b.velocity.x - 1149.5) < 1.0
	return_bullet(b)
	return [ok, "bullet velocity.x=%.1f with sprint 330 (want 1149.5 = 1100 + 330*0.15)" % b.velocity.x]


func _phys_s_recoil_fire() -> void:
	var lp = _phys_lp()
	lp.weapon = 0
	lp.mag_ammo = 30
	lp._recoil_accum = 0.0
	for i in 5:
		lp._fire_cooldown = 0.0
		lp._fire()


func _phys_c_recoil() -> Array:
	var lp = _phys_lp()
	var ok: bool = lp._recoil_accum > 0.15 and lp._recoil_accum < 0.35
	return [ok, "recoil accum after 5 rifle shots: %.2f (want ~0.30 = 5 x 0.06, decayed a little before the check)" % lp._recoil_accum]


func _phys_c_recoil_decay() -> Array:
	var lp = _phys_lp()
	return [lp._recoil_accum < 0.05, "recoil accum 2 s after firing: %.3f (want <0.05)" % lp._recoil_accum]


func _phys_s_ice() -> void:
	_phys_data["ice_map"] = map_id == 4
	if map_id == 4:
		# QA-033: the duel rebuild moved the floor to 1352 and the
		# slide lane to x450-1750. Start the run at x=900: clear
		# floor to the 0.7-width bounce pad at x1540 (640 px of
		# clean ice — the old x=500 start would hit the 0.3-width
		# pad at x660 after 160 px).
		_phys_teleport(Vector2(900, 1320))
		_jt_press_move(Vector2(60, 0))


func _phys_c_ice() -> Array:
	_jt_release_move()
	if map_id != 4:
		var ok: bool = not is_on_ice(Vector2(1400, 1420)) and absf(PhysicsConfig.ICE_FRICTION - 100.0) < 0.01 and absf(PhysicsConfig.ICE_ACCEL - 500.0) < 0.01
		return [ok, "not Frozen Fortress (map %d): is_on_ice=false, ice friction=100 accel=500 — rerun with --map=4 for the live slide" % map_id]
	var lp = _phys_lp()
	_phys_data["ice_slide_x0"] = lp.position.x
	_phys_data["ice_slide_vx0"] = lp.velocity.x
	var ok: bool = lp.velocity.x > 150.0
	return [ok, "ice run vel.x=%d (want >150 with ice accel 500)" % round(lp.velocity.x)]


func _phys_c_ice_slide() -> Array:
	# T-58: stop distance on ice >= 3x the ground stop (~46 px).
	var lp = _phys_lp()
	var dist: float = lp.position.x - float(_phys_data.get("ice_slide_x0", 0.0))
	var ok: bool = dist > 135.0 and absf(lp.velocity.x) > 40.0
	return [ok, "ice slide: dist=%.0f px in 1.5 s, vel.x=%d (want >135 px, >40 — vs 46 px ground stop)" % [dist, round(lp.velocity.x)]]


func _phys_s_camera() -> void:
	var lp = _phys_lp()
	_phys_data["cam_anchor0"] = lp._cam_anchor
	# Phase 5: stand on the highest platform at x=1600 — the fixed
	# (1600, 1320) is INSIDE a platform on Space Station
	# ((1450,1280,300,48)), so the player wedged and look-ahead read 0.
	_phys_teleport(_phys_top_at(1600.0))
	_jt_press_move(Vector2(60, 0))


# Phase 5 — physics harness helper: the highest platform top at map x
# (the platform the player lands on when falling from above).
func _phys_top_at(x: float) -> Vector2:
	var best_top := 1e9
	for p in (MAPS[map_id]["platforms"] as Array):
		var r: Rect2 = p
		if r.position.x <= x and x <= r.end.x and r.position.y < best_top:
			best_top = r.position.y
	if best_top >= 1e9:
		best_top = float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	return Vector2(x, best_top - 26.0)


func _phys_c_camera() -> Array:
	var lp = _phys_lp()
	_jt_release_move()
	var ok: bool = lp._camera != null and absf(lp._camera.position_smoothing_speed - 8.0) < 0.01 and absf(lp._cam_look) > 40.0
	return [ok, "camera smoothing=%.1f look-ahead=%.0f (want 8.0 / >40 while sprinting)" % [lp._camera.position_smoothing_speed if lp._camera != null else -1.0, lp._cam_look]]


func _phys_c_pool() -> Array:
	var ok: bool = bullet_pool.pool_size() == 160 and bullet_pool.active_count() == 0
	return [ok, "bullet pool size=%d active=%d (want 160 / 0)" % [bullet_pool.pool_size(), bullet_pool.active_count()]]


func _phys_c_version() -> Array:
	# A mismatched build must be refused at join (GAP-61).
	request_spawn(999, "BadBuild", 0, 0, "0.0-wrong")
	var ok: bool = not _spawned.has(999)
	return [ok, "spawn with version 0.0-wrong refused=%s (want true)" % str(ok)]


func _phys_s_barrel() -> void:
	_phys_teleport(Vector2(300, 1320))
	for b in _barrels:
		if bool(b["alive"]):
			_phys_data["barrel_idx"] = _barrels.find(b)
			_phys_data["barrel_hit"] = try_barrel_hit((b["rect"] as Rect2).get_center(), 100, 1)
			return
	_phys_data["barrel_idx"] = -1


func _phys_c_barrel() -> Array:
	var idx := int(_phys_data.get("barrel_idx", -1))
	if idx < 0:
		return [false, "no live barrel found on this map"]
	var alive := bool(_barrels[idx]["alive"])
	return [bool(_phys_data.get("barrel_hit", false)) and not alive, "barrel hit=%s alive after 100 dmg=%s (want true/false)" % [str(_phys_data.get("barrel_hit", false)), str(alive)]]


func _phys_s_pad() -> void:
	var floor_top := 1352.0
	var plats: Array = MAPS[map_id]["platforms"]
	if not plats.is_empty():
		floor_top = float((plats[0] as Rect2).position.y)
	_phys_teleport(Vector2(map_size.x * 0.3, floor_top - 40.0))


func _phys_c_pad() -> Array:
	var lp = _phys_lp()
	var ok: bool = lp.velocity.y < -400.0
	return [ok, "bounce pad launch vel.y=%d (want < -400, pad sets -750)" % round(lp.velocity.y)]


func _phys_s_stuck() -> void:
	var lp = _phys_lp()
	lp.position = Vector2(1600, 1370) # inside the floor slab
	lp._stuck_check_timer = 1.0
	lp._check_stuck(0.016)


func _phys_c_stuck() -> Array:
	var lp = _phys_lp()
	var ok: bool = is_spawn_valid(lp.position, 1)
	return [ok, "stuck player moved to %s (want a valid spawn)" % str(lp.position)]


# =====================================================================
# --perf-test (GAP-73): 60 s headless soak — full-auto fire + grenades,
# sampling memory every 10 s. Pass: no script errors (checked by the
# runner grepping output), memory growth < 50 MB, bullet pool drains
# to 0 after firing stops. FPS is not measurable headless; the runner
# records that honestly.
# =====================================================================

func _update_perftest(delta: float) -> void:
	if _perf_done:
		return
	var lp = _get_local_player()
	if lp == null:
		return
	if _perf_elapsed == 0.0:
		_perf_mem0 = OS.get_static_memory_usage()
		print("PERFTEST start: mem=%d bytes" % _perf_mem0)
		# T-73: soak on the rifle with a topped-up reserve — the rifle
		# is full-auto, so holding FIRE churns bullets continuously.
		# (The pistol has infinite reserve but is semi-auto: holding
		# FIRE fires exactly once. The rifle's 90 reserve + 30 mag
		# runs dry after ~20 s, so the reserve is refilled here and
		# again every 10 s below.)
		lp._reserve[0] = 90
		if _perf_bots > 0 and not _perf_bots_spawned:
			# T-73: idle bot players, instantiated directly (NOT via
			# the MultiplayerSpawner — a fake never-connected peer id
			# makes the spawner log an engine RPC error; direct
			# instantiation is clean, proven by the QA-031 probes).
			# They stand idle; the local player provides the churn
			# (full-auto fire + grenades). Honest limit: only 1 of
			# the 8 players shoots.
			_perf_bots_spawned = true
			var spawns: Array = MAPS[map_id]["spawns"]
			for i in _perf_bots:
				var pid := 100 + i
				var p = PLAYER_SCENE.instantiate()
				p.name = str(pid)
				p.peer_id = pid
				p.player_index = (i + 2) % 12
				p.player_name = "SoakBot%d" % pid
				p.color_index = i % PLAYER_COLORS.size()
				p.player_color = PLAYER_COLORS[i % PLAYER_COLORS.size()]
				p.helmet = 0
				p.team = -1
				players_node.add_child(p)
				var spot: Vector2 = spawns[(i + 2) % spawns.size()]
				p.position = spot
				p.sync_position = spot
			print("PERFTEST bots: %d idle bot players added (total %d)" % [_perf_bots, players_node.get_child_count()])
	_perf_elapsed += delta
	# Hold FIRE + wiggle the move stick; throw a grenade every 5 s.
	_smoke_set_fire(true)
	if int(_perf_elapsed) % 4 < 2:
		_smoke_set_move(Vector2(60, 0))
	else:
		_smoke_set_move(Vector2(-60, 0))
	if lp != null and lp.grenades > 0 and int(_perf_elapsed) % 5 == 0 and int((_perf_elapsed - delta)) % 5 != 0:
		lp.throw_grenade()
	if int(_perf_elapsed) % 10 == 0 and int((_perf_elapsed - delta)) % 10 != 0:
		# T-73: keep the rifle fed so the soak churns the whole run.
		if lp != null:
			lp._reserve[0] = 90
		print("PERFTEST t=%ds mem=%d bytes active_bullets=%d players=%d shots=%d" % [int(_perf_elapsed), OS.get_static_memory_usage(), bullet_pool.active_count(), players_node.get_child_count(), lp._shots_fired if lp != null else -1])
	if _perf_elapsed >= _perf_seconds:
		_smoke_set_fire(false)
		_smoke_set_move(null)
		_perf_done = true
		var growth := OS.get_static_memory_usage() - _perf_mem0
		print("PERFTEST DONE: %d s soak (%d players), mem growth=%d bytes (limit 50 MB), active_bullets=%d (drains to 0 within 2 s of stopping)" % [int(_perf_seconds), players_node.get_child_count(), growth, bullet_pool.active_count()])
		get_tree().quit()


# =====================================================================
# Phase 4/6 — features test harness (--features-test).
# One step per new feature, same setup/check shape as the other
# harnesses. Prints FEATTEST <name>: PASS/FAIL lines + a DONE line.
# =====================================================================

func _update_featurestest(delta: float) -> void:
	if _feat_done:
		return
	var lp = _get_local_player()
	if lp == null:
		_feat_timer += delta
		if _feat_timer > 5.0:
			_feat_done = true
			print("FEATTEST DONE: 0/0 passed — no local player spawned")
			get_tree().quit()
		return
	if _feat_steps.is_empty():
		_featurestest_build_steps()
		_feat_step = 0
		_feat_in_step = false
		_feat_timer = 0.0
	if _feat_step >= _feat_steps.size():
		_feat_done = true
		print("FEATTEST DONE: %d/%d passed" % [_feat_passed, _feat_passed + _feat_failed])
		get_tree().quit()
		return
	var step: Dictionary = _feat_steps[_feat_step]
	if not _feat_in_step:
		(step["setup"] as Callable).call()
		_feat_in_step = true
		_feat_timer = float(step["wait"])
	_feat_timer -= delta
	if _feat_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_feat_passed += 1
		else:
			_feat_failed += 1
		print("FEATTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_feat_step += 1
		_feat_in_step = false
		_feat_timer = 0.0


func _featurestest_build_steps() -> void:
	_feat_steps = [
		{"name": "COUNTDOWN-FREEZE", "wait": 0.6, "setup": _ft_s_countdown, "check": _ft_c_countdown},
		{"name": "COUNTDOWN-END", "wait": 3.0, "setup": _ft_s_release_all, "check": _ft_c_countdown_end},
		{"name": "KILLFEED-HITMARKER", "wait": 0.9, "setup": _ft_s_killfeed, "check": _ft_c_killfeed},
		{"name": "END-STATS-MVP", "wait": 0.3, "setup": _ft_s_endstats, "check": _ft_c_endstats},
		{"name": "SETTINGS-PERSIST", "wait": 0.3, "setup": _ft_s_settings, "check": _ft_c_settings},
		{"name": "MAP-VOTE", "wait": 0.2, "setup": _ft_s_noop, "check": _ft_c_mapvote},
		{"name": "PICKUPS-HEALTH-GRENADE", "wait": 0.3, "setup": _ft_s_pickups, "check": _ft_c_pickups},
		{"name": "MUSIC", "wait": 0.5, "setup": _ft_s_music, "check": _ft_c_music},
		{"name": "SPECTATOR", "wait": 0.6, "setup": _ft_s_spectator, "check": _ft_c_spectator},
		{"name": "SCOREBOARD", "wait": 0.2, "setup": _ft_s_scoreboard, "check": _ft_c_scoreboard},
		{"name": "FIRE-LAYOUT", "wait": 0.2, "setup": _ft_s_firelayout, "check": _ft_c_firelayout},
	]


func _ft_s_release_all() -> void:
	_ft_release_move()
	_ft_release_aim()
	_ft_release_fire()


func _ft_s_countdown() -> void:
	# Drive the countdown ourselves (it is off in test modes).
	_countdown_active = true
	_countdown_t = 3.0
	_countdown_last_shown = -1
	# Hold every control: nothing may move, aim or fire until FIGHT.
	_ft_press_move(Vector2(60, 0))
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_countdown() -> Array:
	var frozen: bool = touch_move_vec == Vector2.ZERO and touch_aim == Vector2.ZERO and not touch_firing
	var shown: bool = _countdown_label.visible and _countdown_label.text == "3"
	var sub: bool = _countdown_sub.visible and _countdown_sub.text.contains("First to")
	var ok: bool = frozen and shown and sub
	return [ok, "frozen=%s label=%s/%s sub=%s" % [frozen, _countdown_label.text, _countdown_label.visible, _countdown_sub.text]]


func _ft_c_countdown_end() -> Array:
	var ok: bool = not _countdown_active and _countdown_label.visible and _countdown_label.text == "FIGHT!"
	return [ok, "countdown_active=%s label=%s" % [_countdown_active, _countdown_label.text]]


func _ft_s_killfeed() -> void:
	var lp = _get_local_player()
	_ft_s_release_all()
	_ft_set_weapon(5) # pistol: 10 dmg, one lethal shot vs 5 HP
	lp.position = Vector2(300, 1320)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = players_node.get_node_or_null("99")
	if b == null:
		_do_spawn(99, "TestBot", 0, 0)
		b = players_node.get_node_or_null("99")
	_feat_bot = b
	if b != null:
		b.position = Vector2(600, 1320)
		b.sync_position = b.position
		b.velocity = Vector2.ZERO
		b.health = 5
		b._spawn_protect_timer = 0.0
	lp._spawn_protect_timer = 0.0
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_killfeed() -> Array:
	var lp = _get_local_player()
	_ft_release_aim()
	_ft_release_fire()
	var feed_text := ""
	for e in _kill_feed_entries:
		feed_text += String((e["label"] as Label).text) + "|"
	var feed_ok: bool = feed_text.contains("TestBot") and feed_text.contains("Pistol")
	var hit_ok: bool = lp._hitmark_seq >= 1 and lp._shots_hit >= 1
	var kill_ok: bool = lp.kills >= 1
	var streak_ok: bool = int(_best_streaks.get(1, 0)) >= 1
	var ok: bool = feed_ok and hit_ok and kill_ok and streak_ok
	return [ok, "feed='%s' hitmark_seq=%d shots_hit=%d kills=%d best_streak=%d" % [feed_text, lp._hitmark_seq, lp._shots_hit, lp.kills, int(_best_streaks.get(1, 0))]]


func _ft_s_endstats() -> void:
	# Fake final rows: Player 5/2 with 20 shots 12 hits (K/D 2.50,
	# 60% accuracy), TestBot 3/5 with 10 shots 2 hits (K/D 0.60, 20%).
	var rows := [
		{"name": "Player", "kills": 5, "deaths": 2, "team": -1, "color": Color(1, 0, 0), "rounds": 0, "shots": 20, "hits": 12, "streak": 3},
		{"name": "TestBot", "kills": 3, "deaths": 5, "team": -1, "color": Color(0, 0, 1), "rounds": 0, "shots": 10, "hits": 2, "streak": 1},
	]
	show_end_screen("Player", "reached 10 kills!", rows)


func _ft_c_endstats() -> Array:
	var mvp_ok := false
	for n in _mvp_nodes:
		if n is HBoxContainer:
			for c in n.get_children():
				if c is Label and String(c.text).contains("MVP: Player") and String(c.text).contains("60%"):
					mvp_ok = true
	var row_ok := false
	for c in end_list.get_children():
		if c is Label and String(c.text).contains("K/D: 2.50") and String(c.text).contains("ACC: 60%"):
			row_ok = true
	var stats_ok := false
	var st: Dictionary = GameData.compute_stats(10, 4, 20, 12)
	stats_ok = absf(float(st["kd"]) - 2.5) < 0.01 and absf(float(st["accuracy"]) - 60.0) < 0.01
	var st2: Dictionary = GameData.compute_stats(7, 0, 0, 0)
	stats_ok = stats_ok and absf(float(st2["kd"]) - 7.0) < 0.01 and float(st2["accuracy"]) == 0.0
	var ok: bool = end_panel.visible and mvp_ok and row_ok and stats_ok
	# The match is not really over: put the panel away and resume.
	var was_visible: bool = end_panel.visible
	end_panel.visible = false
	match_over = false
	return [ok, "end_visible=%s mvp=%s row=%s stats=%s" % [was_visible, mvp_ok, row_ok, stats_ok]]


func _ft_s_settings() -> void:
	# Stash the real settings, then write distinctive test values.
	_feat_data = {
		"sfx": GameData.sfx_volume, "music": GameData.music_volume,
		"enabled": GameData.music_enabled, "sens": GameData.sensitivity,
		"fps": GameData.show_fps, "invert": GameData.invert_aim,
	}
	GameData.sfx_volume = 0.44
	GameData.music_volume = 0.33
	GameData.music_enabled = false
	GameData.sensitivity = 1.5
	GameData.show_fps = true
	GameData.invert_aim = true
	GameData.save_settings()


func _ft_c_settings() -> Array:
	# Wipe the values in memory, reload from disk, compare.
	GameData.sfx_volume = 0.9
	GameData.music_volume = 0.9
	GameData.music_enabled = true
	GameData.sensitivity = 0.9
	GameData.show_fps = false
	GameData.invert_aim = false
	GameData.load_settings()
	var ok: bool = absf(GameData.sfx_volume - 0.44) < 0.01 and absf(GameData.music_volume - 0.33) < 0.01 and GameData.music_enabled == false and absf(GameData.sensitivity - 1.5) < 0.01 and GameData.show_fps == true and GameData.invert_aim == true
	var fps_ok: bool = fps_label.visible
	# Restore the player's real settings.
	GameData.sfx_volume = float(_feat_data["sfx"])
	GameData.music_volume = float(_feat_data["music"])
	GameData.music_enabled = bool(_feat_data["enabled"])
	GameData.sensitivity = float(_feat_data["sens"])
	GameData.show_fps = bool(_feat_data["fps"])
	GameData.invert_aim = bool(_feat_data["invert"])
	GameData.save_settings()
	ok = ok and fps_ok
	return [ok, "persist_ok=%s fps_label_visible=%s (restored real settings)" % [ok, fps_ok]]


func _ft_c_mapvote() -> Array:
	var cands := [0, 1, 2]
	var w1: int = GameData.tally_map_vote({2: 0, 3: 1, 4: 1}, cands, 0)
	var w2: int = GameData.tally_map_vote({2: 0, 3: 1}, cands, 0)
	var w3: int = GameData.tally_map_vote({}, cands, 2)
	var w4: int = GameData.tally_map_vote({2: 5}, cands, 0) # vote for a map not on the ballot: ignored
	var map_ok: bool = MAPS[w1].has("size") and MAPS[w1].has("spawns") and int(MAPS[w1]["spawns"].size()) == 12
	var ok: bool = w1 == 1 and w2 == 0 and w3 == 2 and w4 == 0 and map_ok
	return [ok, "tally 2-1=%d tie=%d none=%d off-ballot=%d voted_map=%s spawns=%d" % [w1, w2, w3, w4, GameData.MAP_NAMES[w1], int(MAPS[w1]["spawns"].size())]]


func _ft_s_pickups() -> void:
	var lp = _get_local_player()
	lp.health = 40
	lp.grenades = 0
	# A real health pickup on a real spot (kind 5, Sky Brawl icon).
	_spawn_pickup_at(0, 5)


func _ft_c_pickups() -> Array:
	var lp = _get_local_player()
	lp.give_pickup(5)
	var health_ok: bool = lp.health == 90
	lp.give_pickup(6)
	var gren_ok: bool = lp.grenades == 2
	var node_ok := false
	var icon_ok := false
	for c in pickups_node.get_children():
		if int(c.kind) == 5:
			node_ok = true
			for sub in c.get_children():
				if sub is Sprite2D and (sub as Sprite2D).texture != null:
					icon_ok = true
			c.queue_free()
	var ok: bool = health_ok and gren_ok and node_ok and icon_ok
	return [ok, "health 40->%d grenades 0->%d pickup_node=%s icon=%s" % [lp.health, lp.grenades, node_ok, icon_ok]]


func _ft_s_music() -> void:
	audio.play_battle_music()


func _ft_c_music() -> Array:
	var battle_ok: bool = audio.current_track() == "battle" and audio.is_music_playing()
	var battle_stream_ok: bool = audio._music_player.stream == audio.BATTLE_TRACK
	var menu_loop_ok: bool = audio.MENU_TRACK.loop == true
	audio.play_menu_music()
	var menu_ok: bool = audio.current_track() == "menu" and audio.is_music_playing()
	audio.set_music_enabled(false)
	var off_ok: bool = not audio.is_music_playing()
	audio.set_music_enabled(true)
	var back_ok: bool = audio.current_track() == "menu" and audio.is_music_playing()
	var credits_ok: bool = GameData.MUSIC_CREDITS.contains("\"At Rest\"") and GameData.MUSIC_CREDITS.contains("\"Five Armies\"") and GameData.MUSIC_CREDITS.contains("creativecommons.org/licenses/by/4.0")
	audio.stop_music()
	var stop_ok: bool = not audio.is_music_playing() and audio.current_track() == ""
	# Leave the match music playing again for the steps after this one.
	audio.play_battle_music()
	var ok: bool = battle_ok and battle_stream_ok and menu_loop_ok and menu_ok and off_ok and back_ok and credits_ok and stop_ok
	return [ok, "battle=%s stream=%s menu_loop=%s menu=%s off=%s back=%s credits=%s stop=%s" % [battle_ok, battle_stream_ok, menu_loop_ok, menu_ok, off_ok, back_ok, credits_ok, stop_ok]]


func _ft_s_spectator() -> void:
	game_mode = 3 # Last Man Standing: no respawn, spectator applies
	var b = _feat_bot
	if b == null or not is_instance_valid(b):
		b = players_node.get_node_or_null("99")
	if b != null and not b.alive:
		b._respawn()
		b.position = Vector2(600, 1320)
		b.sync_position = b.position
	# A second living player: with only one alive, LMS would end the
	# match the moment the local player "dies" (alive_count <= 1),
	# which is exactly what spectator mode must outlive.
	var b2 = players_node.get_node_or_null("98")
	if b2 == null:
		_do_spawn(98, "TestBot2", 1, 0)
		b2 = players_node.get_node_or_null("98")
	if b2 != null and not b2.alive:
		b2._respawn()
		b2.position = Vector2(900, 1320)
		b2.sync_position = b2.position
	var lp = _get_local_player()
	lp.alive = false
	lp._respawn_timer = 30.0 # do not auto-respawn during the check


func _ft_c_spectator() -> Array:
	var ok: bool = _spectating and _spectate_cam.enabled and _spectate_label.visible and _spectate_target != null and String(_spectate_target.player_name) == "TestBot"
	# Capture the diagnostic BEFORE cleanup clears it all.
	var detail := "spectating=%s cam=%s target=%s label=%s" % [_spectating, _spectate_cam.enabled, String(_spectate_target.player_name) if _spectate_target != null else "none", _spectate_label.visible]
	var lp = _get_local_player()
	lp._respawn()
	game_mode = 0
	_stop_spectating()
	# Remove the second bot again (it only existed to keep LMS alive).
	var b2 = players_node.get_node_or_null("98")
	if b2 != null:
		b2.queue_free()
		_spawned.erase(98)
	return [ok, detail]


func _ft_s_scoreboard() -> void:
	_update_scoreboard_rows(scoreboard_list)
	scoreboard_panel.visible = true


func _ft_c_scoreboard() -> Array:
	var kd_ok := false
	var self_ok := false
	var team_ok := false # TDM totals header: must be found below
	for c in scoreboard_list.get_children():
		if c is Label:
			if String(c.text).contains("K/D") and String(c.text).contains("ACC"):
				kd_ok = true
			if String(c.text).contains("(YOU)"):
				self_ok = true
	# TDM totals header: flip the mode, rebuild, check, restore.
	game_mode = 1
	_update_scoreboard_rows(scoreboard_list)
	for c in scoreboard_list.get_children():
		if c is Label and String(c.text).contains("RED") and String(c.text).contains("BLUE"):
			team_ok = true
	game_mode = 0
	_update_scoreboard_rows(scoreboard_list)
	scoreboard_panel.visible = false
	var ok: bool = kd_ok and self_ok and team_ok
	return [ok, "kd_col=%s self=%s tdm_totals=%s" % [kd_ok, self_ok, team_ok]]


func _ft_s_firelayout() -> void:
	# v3.2: the layout is fixed (move left, aim right, no mirror) —
	# presses must still land on the stick whose half they fall in.
	_on_touch_press(920, _ft_move_center())
	_on_touch_press(921, _ft_aim_center())


func _ft_c_firelayout() -> Array:
	var move_ok: bool = move_stick.is_active()
	var aim_ok: bool = aim_stick.is_active()
	_on_touch_release(920)
	_on_touch_release(921)
	var ok: bool = move_ok and aim_ok
	return [ok, "move_stick=%s aim_stick=%s (fixed layout, no FIRE button)" % [move_ok, aim_ok]]


var _feat_data: Dictionary = {}
