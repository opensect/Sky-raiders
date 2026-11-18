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
const FIRE_BUTTON_SCRIPT: Script = preload("res://fire_button.gd")
const AUDIO_SCRIPT: Script = preload("res://audio.gd")

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

const MAPS := [
	{
		"name": "Catacombs", "size": Vector2(3200, 1400), "tile": 0,
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
		"spawns": [Vector2(300, 1320), Vector2(900, 1320), Vector2(1500, 1320), Vector2(2100, 1320), Vector2(2600, 1320), Vector2(1600, 1148), Vector2(1200, 978), Vector2(2400, 978), Vector2(600, 1320), Vector2(1200, 1320), Vector2(1800, 1320), Vector2(2400, 1320)],
		"pickups": [Vector2(500, 1150), Vector2(1400, 1150), Vector2(2700, 1150), Vector2(1600, 810), Vector2(400, 640), Vector2(1600, 470)],
		"decor": [["column", 650, 1352], ["column", 2550, 1352], ["crate", 1000, 1352], ["barrels", 2200, 1352], ["rock", 100, 1352], ["crate", 1600, 1010]],
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
		"spawns": [Vector2(300, 1360), Vector2(900, 1360), Vector2(1500, 1360), Vector2(2100, 1360), Vector2(2600, 1360), Vector2(1300, 1188), Vector2(850, 1018), Vector2(2650, 1018), Vector2(600, 1360), Vector2(1200, 1360), Vector2(1800, 1360), Vector2(2400, 1360)],
		"pickups": [Vector2(400, 1190), Vector2(1350, 1190), Vector2(2400, 1190), Vector2(1200, 680), Vector2(1600, 510), Vector2(1450, 340)],
		"decor": [["sandbags", 750, 1392], ["barrels", 1950, 1392], ["crate", 2450, 1392], ["rock", 100, 1392], ["column", 250, 710], ["crate", 1350, 710]],
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
		"spawns": [Vector2(300, 1420), Vector2(900, 1420), Vector2(1500, 1420), Vector2(2100, 1420), Vector2(2600, 1420), Vector2(1500, 1248), Vector2(850, 1078), Vector2(2000, 1078), Vector2(600, 1420), Vector2(1200, 1420), Vector2(1800, 1420), Vector2(2400, 1420)],
		"pickups": [Vector2(450, 1250), Vector2(1500, 1250), Vector2(2600, 1250), Vector2(1400, 910), Vector2(950, 740), Vector2(1400, 570)],
		"decor": [["palms", 150, 1452], ["palms", 2850, 1452], ["rock", 1000, 1452], ["crate", 2000, 1452], ["sandbags", 2250, 1452], ["column", 350, 600]],
	},
	{
		"name": "Industrial Factory", "size": Vector2(3200, 1600), "tile": 3,
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
		"spawns": [Vector2(300, 1520), Vector2(900, 1520), Vector2(1500, 1520), Vector2(2100, 1520), Vector2(2700, 1520), Vector2(1600, 1348), Vector2(950, 1178), Vector2(2150, 1178), Vector2(600, 1520), Vector2(1200, 1520), Vector2(1800, 1520), Vector2(2400, 1520)],
		"pickups": [Vector2(500, 1350), Vector2(1600, 1350), Vector2(2700, 1350), Vector2(1500, 1010), Vector2(1050, 840), Vector2(1650, 500)],
		"decor": [["barrels", 750, 1552], ["crate", 2200, 1552], ["rock", 150, 1552], ["column", 1450, 1380], ["barrels", 2600, 1380], ["bridge", 1300, 1040]],
	},
	{
		"name": "Frozen Fortress", "size": Vector2(2800, 1500), "tile": 4,
		"sky_top": Color(0.55, 0.70, 0.90), "sky_bottom": Color(0.85, 0.90, 0.97),
		"hill": Color(0.60, 0.70, 0.85), "sun": Color(0.95, 0.95, 1.00), "fx": "snow",
		"platforms": [
			Rect2(0, 1452, 2800, 48),
			Rect2(250, 1280, 400, 48),
			Rect2(1200, 1280, 440, 48),
			Rect2(2200, 1280, 400, 48),
			Rect2(100, 1110, 240, 48),
			Rect2(650, 1110, 340, 48),
			Rect2(1700, 1110, 340, 48),
			Rect2(2500, 1110, 240, 48),
			Rect2(400, 940, 320, 48),
			Rect2(1150, 940, 400, 48),
			Rect2(1950, 940, 320, 48),
			Rect2(750, 770, 320, 48),
			Rect2(1800, 770, 320, 48),
			Rect2(250, 600, 260, 48),
			Rect2(1100, 600, 360, 48),
			Rect2(2400, 600, 260, 48),
		],
		"spawns": [Vector2(300, 1420), Vector2(900, 1420), Vector2(1400, 1420), Vector2(1900, 1420), Vector2(2500, 1420), Vector2(1400, 1248), Vector2(800, 1078), Vector2(1900, 1078), Vector2(600, 1420), Vector2(1150, 1420), Vector2(1650, 1420), Vector2(2150, 1420)],
		"pickups": [Vector2(450, 1250), Vector2(1400, 1250), Vector2(2400, 1250), Vector2(1300, 910), Vector2(900, 740), Vector2(1250, 570)],
		"decor": [["rock", 200, 1452], ["rock", 2600, 1452], ["crate", 1000, 1452], ["column", 1350, 1280], ["crate", 2000, 1452], ["rock", 1500, 1452]],
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
		"spawns": [Vector2(300, 1320), Vector2(900, 1320), Vector2(1500, 1320), Vector2(2100, 1320), Vector2(2900, 1320), Vector2(1300, 1148), Vector2(1200, 978), Vector2(2200, 978), Vector2(600, 1320), Vector2(1200, 1320), Vector2(1800, 1320), Vector2(2400, 1320)],
		"pickups": [Vector2(300, 1150), Vector2(1400, 1150), Vector2(2700, 1150), Vector2(1450, 640), Vector2(2300, 810), Vector2(2600, 640)],
		"decor": [["jtree", 130, 1352], ["jpalm", 3000, 1352], ["jstatue", 1400, 1010], ["jpillar", 1100, 1010], ["jpillar", 1700, 1010], ["jtower", 2400, 840], ["jcrate", 900, 1180], ["jrock", 2500, 1352], ["jbush", 600, 1352], ["jbridge", 1875, 1010], ["jarch", 2100, 1010], ["jtree", 2300, 840]],
	},
	{
		"name": "Space Station", "size": Vector2(3000, 1500), "tile": 6,
		"sky_top": Color(0.02, 0.03, 0.08), "sky_bottom": Color(0.08, 0.10, 0.22),
		"hill": Color(0.05, 0.07, 0.16), "sun": Color(0.90, 0.95, 1.00), "fx": "none",
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
		"spawns": [Vector2(300, 1420), Vector2(900, 1420), Vector2(1500, 1420), Vector2(2100, 1420), Vector2(2600, 1420), Vector2(1500, 1248), Vector2(850, 1078), Vector2(2000, 1078), Vector2(600, 1420), Vector2(1200, 1420), Vector2(1800, 1420), Vector2(2400, 1420)],
		"pickups": [Vector2(450, 1250), Vector2(1500, 1250), Vector2(2600, 1250), Vector2(1400, 910), Vector2(950, 740), Vector2(1400, 570)],
		"decor": [["column", 500, 1452], ["crate", 2000, 1452], ["barrels", 2450, 1452], ["rock", 150, 1452], ["bridge", 1250, 940], ["column", 2250, 1452]],
	},
	{
		"name": "City Underground", "size": Vector2(3200, 1600), "tile": 7,
		"sky_top": Color(0.03, 0.04, 0.10), "sky_bottom": Color(0.10, 0.12, 0.25),
		"hill": Color(0.08, 0.08, 0.14), "sun": Color(0.95, 0.95, 0.90), "fx": "rain",
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
		"spawns": [Vector2(300, 1520), Vector2(900, 1520), Vector2(1500, 1520), Vector2(2100, 1520), Vector2(2700, 1520), Vector2(1600, 1348), Vector2(950, 1178), Vector2(2150, 1178), Vector2(600, 1520), Vector2(1200, 1520), Vector2(1800, 1520), Vector2(2400, 1520)],
		"pickups": [Vector2(500, 1350), Vector2(1600, 1350), Vector2(2700, 1350), Vector2(1500, 1010), Vector2(1050, 840), Vector2(1650, 500)],
		"decor": [["crate", 750, 1552], ["barrels", 2200, 1552], ["rock", 150, 1552], ["column", 1450, 1380], ["bridge", 1300, 1040], ["sandbags", 2600, 1552]],
	},
	{
		"name": "Volcanic Cavern", "size": Vector2(3000, 1500), "tile": 8,
		"sky_top": Color(0.12, 0.05, 0.05), "sky_bottom": Color(0.30, 0.10, 0.08),
		"hill": Color(0.15, 0.06, 0.06), "sun": Color(1.00, 0.55, 0.20), "fx": "embers",
		"lava": [Rect2(700, 1400, 300, 100), Rect2(2000, 1400, 300, 100)],
		"platforms": [
			Rect2(0, 1452, 700, 48),
			Rect2(1000, 1452, 1000, 48),
			Rect2(2300, 1452, 700, 48),
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
		"spawns": [Vector2(300, 1420), Vector2(1300, 1420), Vector2(1600, 1420), Vector2(2600, 1420), Vector2(500, 1420), Vector2(1500, 1248), Vector2(850, 1078), Vector2(2000, 1078), Vector2(1050, 1420), Vector2(1900, 1420), Vector2(2400, 1420), Vector2(2750, 1420)],
		"pickups": [Vector2(450, 1250), Vector2(1500, 1250), Vector2(2600, 1250), Vector2(1400, 910), Vector2(950, 740), Vector2(1400, 570)],
		"decor": [["rock", 200, 1452], ["rock", 1500, 1452], ["rock", 2800, 1452], ["column", 1350, 1280], ["crate", 2250, 1452], ["barrels", 600, 1452]],
	},
	{
		"name": "Pirate Island", "size": Vector2(3000, 1500), "tile": 9,
		"sky_top": Color(0.45, 0.75, 0.95), "sky_bottom": Color(0.85, 0.93, 0.97),
		"hill": Color(0.30, 0.50, 0.35), "sun": Color(1.00, 0.95, 0.60), "fx": "none",
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
		"spawns": [Vector2(300, 1420), Vector2(900, 1420), Vector2(1500, 1420), Vector2(2100, 1420), Vector2(2600, 1420), Vector2(1500, 1248), Vector2(850, 1078), Vector2(2000, 1078), Vector2(600, 1420), Vector2(1200, 1420), Vector2(1800, 1420), Vector2(2400, 1420)],
		"pickups": [Vector2(450, 1250), Vector2(1500, 1250), Vector2(2600, 1250), Vector2(1400, 910), Vector2(950, 740), Vector2(1400, 570)],
		"decor": [["palms", 150, 1452], ["palms", 2850, 1452], ["crate", 1000, 1452], ["barrels", 2000, 1452], ["rock", 2250, 1452], ["column", 1350, 1280]],
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
var hp_bar: ProgressBar
var fuel_bar: ProgressBar
var hp_value_label: Label
var fuel_value_label: Label
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
var end_rematch_btn: Button
var error_panel: PanelContainer
var error_label: Label
var move_stick
var aim_stick
var fire_button # FireButtonController (v2.4)
var grenade_button: Button
var switch_button: Button
var reload_button: Button # v2.4
var pause_button: Button
var score_button: Button
var hint_label: Label
var bullet_pool: BulletPool # v2.4: pooled bullets
var shooting_sync: ShootingSync # v2.4: host-side fire-rate/ammo validation
var max_players: int = 8 # room setting (GameData); MAX_PLAYERS is the cap

# Touch input state, read by the local player.
# v2.2: the left stick is a full 2D vector now (x = move, y = jump/fly).
# There is no JUMP button any more — pushing the left stick up jumps,
# holding it up while airborne is the jetpack.
# v2.4: firing comes ONLY from the FIRE button (fire_button.is_held()).
# The aim stick is aim-only and never fires (QA-023).
var touch_move_vec: Vector2 = Vector2.ZERO
var touch_aim: Vector2 = Vector2.ZERO
var touch_aim_active: bool = false
var touch_firing: bool = false

var _move_touch_id: int = -1
var _aim_touch_id: int = -1
var _fire_touch_id: int = -1 # v2.4: the finger holding the FIRE button
var _next_index: int = 1
var _spawned: Dictionary = {}
var _udp_broadcast: PacketPeerUDP
var _udp_broadcast_sockets: Array[PacketPeerUDP] = [] # v2.4: one socket per broadcast address
var _broadcast_timer: float = 0.0
var _pickup_timer: float = 0.0
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
var _smoke_fire_idx: int = -1 # v2.4: fake FIRE-button touch index
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
var _lava_cd: Dictionary = {} # peer id -> seconds until next lava damage tick
var _round_wins: Dictionary = {} # v2.4 Survival: peer id -> rounds won
var _round_number: int = 1 # v2.4 Survival: current round
var _spawn_retry_timer: float = 0.0 # v2.4: request_spawn retry clock
var _fire_test: bool = false # v2.4: --fire-test harness
var _fire_steps: Array = []
var _fire_step: int = 0
var _fire_in_step: bool = false
var _fire_timer: float = 0.0
var _fire_passed: int = 0
var _fire_failed: int = 0
var _fire_done: bool = false
var _fire_shots_before: int = 0
var _fire_pos_before: Vector2 = Vector2.ZERO
var _fire_grenades_before: int = 0
var _fire_weapon_before: int = 0
var _net_test: bool = false # v2.4: --net-test harness
var _net_steps: Array = []
var _net_step: int = 0
var _net_in_step: bool = false
var _net_timer: float = 0.0
var _net_passed: int = 0
var _net_failed: int = 0
var _net_done: bool = false
# v2.4 full-flow check: handed over from the menu via GameData
# (flow_phase 1 = in the match). The menu prints the final result
# when we return (phase 2).
var _flow_test: bool = false
var _flow_steps: Array = []
var _flow_step: int = 0
var _flow_in_step: bool = false
var _flow_timer: float = 0.0
var _flow_passed: int = 0
var _flow_failed: int = 0
var _flow_done: bool = false


func _ready() -> void:
	add_to_group("game")
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
	# Test-only map override: --map=N loads that map (the collision
	# test uses it to run its pass-through checks on Jungle Ruins).
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--map="):
			map_id = clampi(int(a.trim_prefix("--map=")), 0, MAPS.size() - 1)
	audio = AUDIO_SCRIPT.new()
	add_child(audio)
	audio.set_volumes(GameData.sfx_volume, GameData.music_volume)
	var map: Dictionary = MAPS[map_id]
	map_size = map["size"]
	_build_background(map)
	_build_arena(map)
	_build_lava(map)
	_build_ambient_fx(map)
	_build_nodes()
	# v2.4: bullet pool + host-side shooting validation live on the game.
	bullet_pool = BulletPool.new(BULLET_SCENE, bullets_node, 96)
	shooting_sync = ShootingSync.new()
	_build_hud()
	_build_touch_controls()
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
	"jpillar", "jstatue", "jtower", "jcrate", "jrock"]


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
			box.size = Vector2(tex.get_width(), tex.get_height())
			shape.shape = box
			shape.position = spr.position
			arena.add_child(shape)


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
			_lava_cd[child.peer_id] = 1.0
			# v2.4 BUG FIX: lava damage used to call take_damage()
			# directly on the server's copy of a remote player — the
			# owner's synchronizer then overwrote the health, so lava
			# only ever hurt the host. Route it to the victim's owning
			# peer like bullet damage.
			if child.get_multiplayer_authority() == multiplayer.get_unique_id():
				child.take_damage(20, 0)
			elif multiplayer.get_peers().has(child.get_multiplayer_authority()):
				child.rpc_id(child.get_multiplayer_authority(), "take_damage", 20, 0)
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
	rpc_id(1, "request_spawn", multiplayer.get_unique_id(), GameData.player_name, GameData.color_index, GameData.helmet)


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
	if _spawned.has(pid):
		return
	_spawned[pid] = true
	var team := -1
	if game_mode == 1:
		team = (_next_index - 1) % 2
	# Survival (2) and Last Man Standing (3) are free-for-all: team -1.
	var data := {"id": pid, "index": _next_index, "name": pname, "color": color_idx, "helmet": helmet_style, "team": team}
	_next_index += 1
	spawner.spawn(data)


@rpc("any_peer")
func request_spawn(pid: int, pname: String, color_idx: int, helmet_style: int) -> void:
	# Server only, and only after the client signalled it is ready.
	if not multiplayer.is_server():
		return
	# Validate: the sender must be the peer it claims to be, the room
	# must not be full, and the spawn index must be in range.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != pid:
		return
	if players_node.get_child_count() >= max_players:
		return
	_do_spawn(pid, pname, color_idx, helmet_style)


func _on_peer_connected(id: int) -> void:
	print("Peer connected: ", id)
	# v2: do NOT spawn here. The client sends request_spawn once its
	# game scene (with MultiplayerSpawner) is ready.


func _on_peer_disconnected(id: int) -> void:
	print("Peer disconnected: ", id)
	if multiplayer.is_server():
		_spawned.erase(id)
		_round_wins.erase(id)
		if shooting_sync != null:
			shooting_sync.reset_peer(id)
		var node := players_node.get_node_or_null(str(id))
		if node != null:
			node.queue_free()
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
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 10
	hud.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(hud)

	var top := HBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_left = 16
	top.offset_right = -16
	top.offset_top = 12
	top.offset_bottom = 64
	top.add_theme_constant_override("separation", 16)
	hud.add_child(top)

	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 6)
	top.add_child(left)

	# v2.5: health and jetpack fuel as a bar PLUS a number, so both read
	# at a glance mid-fight.
	var hp_row := HBoxContainer.new()
	hp_row.add_theme_constant_override("separation", 8)
	left.add_child(hp_row)

	hp_bar = ProgressBar.new()
	hp_bar.min_value = 0
	hp_bar.max_value = 100
	hp_bar.value = 100
	hp_bar.custom_minimum_size = Vector2(220, 26)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.show_percentage = false
	var hp_bg := StyleBoxFlat.new()
	hp_bg.bg_color = Color(0, 0, 0, 0.65)
	hp_bg.corner_radius_top_left = 4
	hp_bg.corner_radius_top_right = 4
	hp_bg.corner_radius_bottom_left = 4
	hp_bg.corner_radius_bottom_right = 4
	hp_bar.add_theme_stylebox_override("background", hp_bg)
	var hp_fill := StyleBoxFlat.new()
	hp_fill.bg_color = Color(0.25, 0.85, 0.3)
	hp_fill.corner_radius_top_left = 4
	hp_fill.corner_radius_top_right = 4
	hp_fill.corner_radius_bottom_left = 4
	hp_fill.corner_radius_bottom_right = 4
	hp_bar.add_theme_stylebox_override("fill", hp_fill)
	hp_row.add_child(hp_bar)
	hp_value_label = Label.new()
	hp_value_label.text = "100"
	hp_value_label.add_theme_font_size_override("font_size", 22)
	_outline_label(hp_value_label)
	hp_row.add_child(hp_value_label)

	var fuel_row := HBoxContainer.new()
	fuel_row.add_theme_constant_override("separation", 8)
	left.add_child(fuel_row)

	fuel_bar = ProgressBar.new()
	fuel_bar.min_value = 0
	fuel_bar.max_value = 100
	fuel_bar.value = 100
	fuel_bar.custom_minimum_size = Vector2(220, 18)
	fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_bar.show_percentage = false
	var fuel_bg := StyleBoxFlat.new()
	fuel_bg.bg_color = Color(0, 0, 0, 0.65)
	fuel_bg.corner_radius_top_left = 4
	fuel_bg.corner_radius_top_right = 4
	fuel_bg.corner_radius_bottom_left = 4
	fuel_bg.corner_radius_bottom_right = 4
	fuel_bar.add_theme_stylebox_override("background", fuel_bg)
	var fuel_fill := StyleBoxFlat.new()
	fuel_fill.bg_color = Color(0.25, 0.6, 0.95)
	fuel_fill.corner_radius_top_left = 4
	fuel_fill.corner_radius_top_right = 4
	fuel_fill.corner_radius_bottom_left = 4
	fuel_fill.corner_radius_bottom_right = 4
	fuel_bar.add_theme_stylebox_override("fill", fuel_fill)
	fuel_row.add_child(fuel_bar)
	fuel_value_label = Label.new()
	fuel_value_label.text = "100"
	fuel_value_label.add_theme_font_size_override("font_size", 18)
	_outline_label(fuel_value_label)
	fuel_row.add_child(fuel_value_label)

	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(mid)
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

	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 4)
	top.add_child(right)

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
	players_label.text = "Players: 1/4"
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

	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	message_label.offset_top = 96
	message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	message_label.add_theme_font_size_override("font_size", 24)
	_outline_label(message_label)
	hud.add_child(message_label)

	host_ip_label = Label.new()
	host_ip_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	host_ip_label.offset_bottom = -8
	host_ip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	host_ip_label.add_theme_font_size_override("font_size", 20)
	host_ip_label.visible = false
	hud.add_child(host_ip_label)

	# v2.4 controls: left stick moves (push up = jump/fly), right
	# stick aims, FIRE button shoots. Say so for the first seconds.
	hint_label = Label.new()
	hint_label.text = "Left stick: move  •  Push up: jump / fly  •  Right stick: aim  •  FIRE button: hold to shoot"
	hint_label.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_bottom = -40
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint_label.add_theme_font_size_override("font_size", 18)
	hint_label.add_theme_color_override("font_color", Color(1, 1, 1, 0.9))
	hint_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint_label.add_theme_constant_override("outline_size", 4)
	hud.add_child(hint_label)

	_build_scoreboard()
	_build_pause_menu()
	_build_end_screen()
	_build_error_panel()


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


func _panel_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.07, 0.12, 0.92)
	s.corner_radius_top_left = 12
	s.corner_radius_top_right = 12
	s.corner_radius_bottom_left = 12
	s.corner_radius_bottom_right = 12
	s.content_margin_left = 18
	s.content_margin_right = 18
	s.content_margin_top = 14
	s.content_margin_bottom = 14
	return s


# Modern HUD/dialog button: dark translucent, rounded, white text.
func _style_hud_button(b: Button, accent: bool = false) -> void:
	var bg := Color(0.13, 0.65, 0.32, 0.92) if accent else Color(0.10, 0.13, 0.19, 0.85)
	var hover := Color(0.16, 0.75, 0.38, 0.95) if accent else Color(0.16, 0.21, 0.29, 0.92)
	var pressed := Color(0.10, 0.52, 0.25, 0.95) if accent else Color(0.07, 0.09, 0.13, 0.92)
	for kind in ["normal", "hover", "pressed"]:
		var s := StyleBoxFlat.new()
		s.bg_color = bg if kind == "normal" else (hover if kind == "hover" else pressed)
		s.corner_radius_top_left = 10
		s.corner_radius_top_right = 10
		s.corner_radius_bottom_left = 10
		s.corner_radius_bottom_right = 10
		s.content_margin_left = 10
		s.content_margin_right = 10
		s.content_margin_top = 6
		s.content_margin_bottom = 6
		b.add_theme_stylebox_override(kind, s)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_font_size_override("font_size", 20)


func _build_scoreboard() -> void:
	scoreboard_panel = PanelContainer.new()
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
	title.add_theme_font_size_override("font_size", 26)
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
	title.add_theme_font_size_override("font_size", 30)
	box.add_child(title)
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	_style_hud_button(resume_btn, true)
	resume_btn.custom_minimum_size = Vector2(0, 52)
	resume_btn.pressed.connect(_toggle_pause)
	box.add_child(resume_btn)
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
	end_panel.custom_minimum_size = Vector2(480, 0)
	end_panel.add_theme_stylebox_override("panel", _panel_style())
	end_panel.visible = false
	_dialog_wrap().add_child(end_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	end_panel.add_child(box)
	end_title = Label.new()
	end_title.text = ""
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_size_override("font_size", 30)
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


func _build_error_panel() -> void:
	error_panel = PanelContainer.new()
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
	error_label.add_theme_font_size_override("font_size", 22)
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


func _show_error(text: String) -> void:
	_join_failed = true
	error_label.text = text
	error_panel.visible = true
	audio.play("death")


func _on_retry_pressed() -> void:
	error_panel.visible = false
	_join_failed = false
	_join_timer = 0.0
	# Re-announce readiness: the server will spawn us if we are missing.
	_ready_announced = false
	_announce_ready()


func _on_leave_pressed() -> void:
	# The scene change is deferred to the end of the frame, but this
	# node's _process would still run once more with `multiplayer`
	# already torn down (script errors in the update tail). Stop it.
	_leaving = true
	get_tree().paused = false
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
		# A finger held on FIRE while pausing must not resume firing
		# on unpause from a stale touch (QA-016 rule).
		_reset_all_touch_state()


func _build_touch_controls() -> void:
	move_stick = JOYSTICK_SCRIPT.new()
	move_stick.name = "MoveStick"
	move_stick.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	move_stick.position = Vector2(40, -190)
	move_stick.size = Vector2(150, 150)
	hud.add_child(move_stick)

	# v2.4: the aim stick moved left to make room for the FIRE button
	# at the far bottom-right corner. Aim stick centre is ~215 px from
	# the right edge; the FIRE button centre is ~57 px from the corner,
	# so a right thumb can hold the aim stick and tap FIRE without
	# the two ever overlapping.
	aim_stick = JOYSTICK_SCRIPT.new()
	aim_stick.name = "AimStick"
	aim_stick.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	aim_stick.position = Vector2(-290, -190)
	aim_stick.size = Vector2(150, 150)
	hud.add_child(aim_stick)

	# v2.4 FIRE button: circular, bottom-right corner, screen space
	# (HUD CanvasLayer, so it never moves with the camera). 90 px
	# diameter on the 1280x720 reference — inside the 75-90 px spec.
	fire_button = FIRE_BUTTON_SCRIPT.new()
	fire_button.name = "FireButton"
	fire_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	fire_button.position = Vector2(-102, -102)
	fire_button.size = Vector2(90, 90)
	hud.add_child(fire_button)

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

	pause_button = Button.new()
	pause_button.text = "II"
	_style_hud_button(pause_button)
	pause_button.custom_minimum_size = Vector2(56, 56)
	pause_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_button.position = Vector2(-72, 196)
	pause_button.pressed.connect(_toggle_pause)
	hud.add_child(pause_button)

	score_button = Button.new()
	score_button.text = "SCORE"
	_style_hud_button(score_button)
	score_button.custom_minimum_size = Vector2(90, 56)
	score_button.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	score_button.position = Vector2(-178, 196)
	score_button.pressed.connect(_on_score_pressed)
	hud.add_child(score_button)


func _on_reload_pressed() -> void:
	var lp = _get_local_player()
	if lp != null:
		lp.start_reload()


func _on_score_pressed() -> void:
	_update_scoreboard_rows(scoreboard_list)
	scoreboard_panel.visible = not scoreboard_panel.visible

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
	for c in [fire_button, grenade_button, switch_button, reload_button, pause_button, score_button]:
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
	_fire_touch_id = -1
	if move_stick != null:
		move_stick.reset_input()
	if aim_stick != null:
		aim_stick.reset_input()
	if fire_button != null:
		fire_button.reset_input()
	touch_move_vec = Vector2.ZERO
	touch_aim = Vector2.ZERO
	touch_aim_active = false
	touch_firing = false


func _on_touch_press(index: int, pos: Vector2) -> void:
	# All positions here are canvas space (converted in _unhandled_input).
	# Order matters — check the controls first, sticks last:
	# 1. FIRE button owns its touch (firing comes only from this id).
	# 2. GUI buttons (belt-and-braces: _unhandled_input means the GUI
	#    already declined them, but a stray touch must never reach a
	#    stick — return without routing).
	# 3. Sticks by screen half.
	if fire_button != null and fire_button.press_touch(index, pos):
		_fire_touch_id = index
		return
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


func _on_touch_drag(index: int, pos: Vector2) -> void:
	if index == _move_touch_id:
		move_stick.drag_touch(index, pos)
	elif index == _aim_touch_id:
		aim_stick.drag_touch(index, pos)
	elif index == _fire_touch_id:
		if fire_button != null:
			fire_button.drag_touch(index, pos)
			if not fire_button.is_held():
				_fire_touch_id = -1


func _on_touch_release(index: int) -> void:
	if index == _move_touch_id:
		_move_touch_id = -1
		move_stick.release_touch(index)
	elif index == _aim_touch_id:
		_aim_touch_id = -1
		aim_stick.release_touch(index)
	elif index == _fire_touch_id:
		_fire_touch_id = -1
		if fire_button != null:
			fire_button.release_touch(index)


func _process(delta: float) -> void:
	if _leaving:
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
	else:
		_update_touch_state()
	# The flow test (or a button) may have started leaving mid-frame.
	if _leaving:
		return
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
		return
	# QA-023: get_vector() is zero unless the stick has an actively held
	# touch, and firing is true ONLY while the FIRE button has an
	# actively held touch — never from a stick, a stale knob position,
	# or any other control.
	touch_move_vec = move_stick.get_vector()
	var aim_vec = aim_stick.get_vector()
	touch_aim = aim_vec
	touch_aim_active = aim_vec.length() > 0.25
	touch_firing = fire_button != null and fire_button.is_held()


func _update_hud(delta: float) -> void:
	var lp = _get_local_player()
	var count := players_node.get_child_count()
	players_label.text = "Players: %d/%d" % [count, MAX_PLAYERS]
	# Timer.
	var t := int(maxf(0.0, _time_left))
	timer_label.text = "%d:%02d" % [t / 60, t % 60]
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
	# v2.2 control hint: visible until 10 s after the local player spawns.
	if hint_label != null:
		if lp != null:
			_hint_timer -= delta
		hint_label.visible = _hint_timer > 0.0
	if lp == null:
		if not _join_failed:
			message_label.text = "Connecting..." if multiplayer.is_server() == false else "Starting..."
		return
	hp_bar.value = lp.health
	hp_value_label.text = str(lp.health)
	fuel_bar.value = lp.fuel
	fuel_value_label.text = str(int(lp.fuel))
	kills_label.text = "Kills: %d" % lp.kills
	deaths_label.text = "Deaths: %d" % lp.deaths
	weapon_icon.texture = WEAPON_ICONS[lp.weapon]
	var wname: String = lp.WEAPONS[lp.weapon]["name"]
	var mag_total: int = int(lp.WEAPONS[lp.weapon]["mag"])
	if lp.reloading:
		weapon_label.text = "%s - reloading %d%%" % [wname, int(lp.reload_progress() * 100.0)]
	else:
		weapon_label.text = "%s %d/%d" % [wname, lp.mag_ammo, mag_total]
	if reload_button != null:
		reload_button.disabled = lp.reloading or lp.mag_ammo >= mag_total
		reload_button.text = "RELOADING..." if lp.reloading else "RELOAD"
	grenade_label.text = "Grenades: %d" % lp.grenades
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
	var rank := 1
	for p in rows:
		var team_txt := ""
		if p.team == 0:
			team_txt = " [RED]"
		elif p.team == 1:
			team_txt = " [BLUE]"
		var lbl := Label.new()
		lbl.text = "%d. %s%s  -  Kills: %d  Deaths: %d" % [rank, p.player_name, team_txt, p.kills, p.deaths]
		lbl.add_theme_font_size_override("font_size", 20)
		lbl.add_theme_color_override("font_color", p.player_color)
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


func _update_pickup_spawn(delta: float) -> void:
	if not multiplayer.is_server() or match_over:
		return
	_pickup_timer += delta
	if _pickup_timer >= 14.0:
		_pickup_timer = 0.0
		if pickups_node.get_child_count() >= 3:
			return
		var spots: Array = MAPS[map_id]["pickups"]
		var pos: Vector2 = spots[randi() % spots.size()]
		var kinds := [1, 1, 2, 2, 3, 4, 5, 6]
		var kind: int = kinds[randi() % kinds.size()]
		var pname := "pickup_" + str(Time.get_ticks_msec())
		rpc("spawn_pickup_remote", pos, pname, kind)


@rpc("any_peer", "call_local")
func spawn_pickup_remote(pos: Vector2, pname: String, kind: int) -> void:
	if pickups_node.has_node(pname):
		return
	var p = PICKUP_SCENE.instantiate()
	p.name = pname
	p.position = pos
	p.kind = kind
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
		_show_error("Could not connect - check the Wi-Fi and IP, then try again.")


func _update_match_timer(delta: float) -> void:
	if match_over:
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
		rows.append({"name": child.player_name, "kills": child.kills, "deaths": child.deaths, "team": child.team, "color": child.player_color, "rounds": int(_round_wins.get(child.peer_id, 0))})
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
	end_title.text = "%s wins!\n%s" % [winner, reason] if winner != "DRAW" else "Draw!\n%s" % reason
	for c in end_list.get_children():
		c.queue_free()
	var rank := 1
	for r in rows:
		var team_txt := ""
		if int(r["team"]) == 0:
			team_txt = " [RED]"
		elif int(r["team"]) == 1:
			team_txt = " [BLUE]"
		var lbl := Label.new()
		if game_mode == 2:
			lbl.text = "%d. %s%s  -  Rounds: %d  Kills: %d  Deaths: %d" % [rank, String(r["name"]), team_txt, int(r.get("rounds", 0)), int(r["kills"]), int(r["deaths"])]
		else:
			lbl.text = "%d. %s%s  -  Kills: %d  Deaths: %d" % [rank, String(r["name"]), team_txt, int(r["kills"]), int(r["deaths"])]
		lbl.add_theme_font_size_override("font_size", 22)
		lbl.add_theme_color_override("font_color", r["color"])
		end_list.add_child(lbl)
		rank += 1
	end_rematch_btn.visible = multiplayer.is_server()
	end_panel.visible = true
	audio.play("win")


# --- FX (impact / explosion) ---

func spawn_impact_fx(pos: Vector2, small: bool = false) -> void:
	var spr := Sprite2D.new()
	spr.texture = SMOKE_TEX if small else EXPLOSION_TEX
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


func request_explosion(pos: Vector2, radius: float, damage: int, from_id: int) -> void:
	# FX on every peer; damage only on the server.
	_spawn_explosion_fx(pos, radius)
	if multiplayer.is_server():
		var killer = players_node.get_node_or_null(str(from_id))
		for child in players_node.get_children():
			if child.alive:
				var dist: float = child.global_position.distance_to(pos)
				if dist > radius:
					continue
				# Lethal check (same falloff as take_explosion_damage):
				# the host credits the kill when its explosion kills.
				var falloff: float = 1.0 - dist / radius
				var amount := int(round(damage * (0.4 + 0.6 * falloff)))
				var lethal := int(child.health) - amount <= 0
				# RPC to yourself is not allowed: call directly in that case.
				# A peer that disconnected mid-flight gets no RPC either.
				if child.get_multiplayer_authority() == multiplayer.get_unique_id():
					child.take_explosion_damage(pos, radius, damage, from_id)
				elif multiplayer.get_peers().has(child.get_multiplayer_authority()):
					child.rpc_id(child.get_multiplayer_authority(), "take_explosion_damage", pos, radius, damage, from_id)
				if lethal and killer != null and from_id != child.peer_id:
					if killer.get_multiplayer_authority() == multiplayer.get_unique_id():
						killer.add_kill()
					elif multiplayer.get_peers().has(killer.get_multiplayer_authority()):
						killer.rpc_id(killer.get_multiplayer_authority(), "add_kill")


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
		return
	var pos: Vector2 = aim_stick.get_global_rect().get_center() + offset
	if _smoke_aim_idx == -1:
		_smoke_aim_idx = 951
		_on_touch_press(_smoke_aim_idx, pos)
	else:
		_on_touch_drag(_smoke_aim_idx, pos)


func _smoke_set_fire(held: bool) -> void:
	# v2.4: firing comes from the FIRE button, not the aim stick.
	# Drives the real touch routing (fake index 952) like a thumb.
	if held:
		if _smoke_fire_idx == -1:
			_smoke_fire_idx = 952
			_on_touch_press(_smoke_fire_idx, fire_button.get_global_rect().get_center())
	else:
		if _smoke_fire_idx != -1:
			_on_touch_release(_smoke_fire_idx)
			_smoke_fire_idx = -1


func _update_smoke_test(delta: float) -> void:
	_smoke_elapsed += delta
	var phase := int(_smoke_elapsed / 1.0)
	# Phases (1s each): 0-1 idle, 2-3 move right, 4 small push, 5 move left,
	# 6 release, 7-8 stick-up jump+jetpack, 9 land, 10-11 aim up-right+fire,
	# 12 aim left+fire, 13 aim down (below fire threshold), 14 grenade,
	# 15 weapon switch, 16+ summary.
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
		# Small down push: aims (0.32 > 0.25) but the FIRE button is
		# released, so this phase aims without firing (aim-only check).
		_smoke_set_aim(Vector2(0, 24))
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


# v2.4: FIRE-button helpers (fake touch index 902) for the tests.
func _jt_fire_center() -> Vector2:
	return fire_button.get_global_rect().get_center()


func _jt_press_fire() -> void:
	_on_touch_press(902, _jt_fire_center())


func _jt_release_fire() -> void:
	_on_touch_release(902)


func _jt_press_aim_fire() -> void:
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_lp():
	return _get_local_player()


# --- Step setups / checks (each returns [passed: bool, detail: String]) ---

func _jt_s_noop() -> void:
	pass


func _jt_s_press_left() -> void:
	_jt_press_move(Vector2(-50, 0))


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
	_jt_press_move(Vector2(500, 0))


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
	# v2.4: move + aim + FIRE are three independent fingers; firing
	# comes only from the FIRE button.
	var ok: bool = move_stick.is_active() and aim_stick.is_active() and fire_button.is_held() and touch_firing and lp._shots_fired > _joy_shots_before
	return [ok, "move_active=%s aim_active=%s fire_held=%s firing=%s shots=%d (was %d)" % [move_stick.is_active(), aim_stick.is_active(), fire_button.is_held(), touch_firing, lp._shots_fired, _joy_shots_before]]


func _jt_s_release_move_only() -> void:
	_jt_release_move()


func _jt_c_release_move_only() -> Array:
	# Releasing the move finger must NOT disturb the aim finger or
	# the FIRE finger.
	var ok: bool = touch_move_vec == Vector2.ZERO and not move_stick.is_active() and aim_stick.is_active() and fire_button.is_held() and touch_firing
	return [ok, "move_vec=%s move_active=%s aim_active=%s fire_held=%s firing=%s" % [touch_move_vec, move_stick.is_active(), aim_stick.is_active(), fire_button.is_held(), touch_firing]]


func _jt_s_release_fire() -> void:
	_jt_release_fire()
	# QA-029: refresh the touch state NOW, then capture the baseline.
	# touch_firing only updates in _update_touch_state(), so without
	# this a physics step between the release and the next _process
	# could still see the stale "firing" value and fire one shot.
	_update_touch_state()
	_joy_shots_before = _jt_lp()._shots_fired


func _jt_c_release_fire_stops_fire() -> Array:
	# v2.4: releasing FIRE stops the shooting, while the aim stick
	# stays held — proving the aim stick alone never fires.
	var lp = _jt_lp()
	var ok: bool = not touch_firing and not fire_button.is_held() and aim_stick.is_active() and lp._shots_fired == _joy_shots_before
	return [ok, "firing=%s fire_held=%s aim_active=%s shots=%d (was %d)" % [touch_firing, fire_button.is_held(), aim_stick.is_active(), lp._shots_fired, _joy_shots_before]]


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
	fire_button._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)
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
	var ok: bool = not touch_firing and touch_move_vec == Vector2.ZERO and touch_aim == Vector2.ZERO and not move_stick.is_active() and not aim_stick.is_active() and not fire_button.is_held() and lp._shots_fired == _joy_shots_before
	return [ok, "firing=%s move_vec=%s aim_vec=%s move_active=%s aim_active=%s fire_held=%s shots=%d (was %d)" % [touch_firing, touch_move_vec, touch_aim, move_stick.is_active(), aim_stick.is_active(), fire_button.is_held(), lp._shots_fired, _joy_shots_before]]


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
		_scale_steps.append({"name": tag + "-FIRE-CENTRE", "wait": 0.3, "setup": _st_s_press_fire_centre, "check": _st_c_fire_held})
		_scale_steps.append({"name": tag + "-FIRE-RELEASE", "wait": 0.3, "setup": _st_s_release_fire, "check": _st_c_fire_released})


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
	_st_press(922, _st_screen_center(fire_button))


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
	var ok: bool = fire_button.is_held()
	return [ok, "held=%s" % fire_button.is_held()]


func _st_c_fire_released() -> Array:
	var ok: bool = not fire_button.is_held()
	return [ok, "held=%s" % fire_button.is_held()]


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
# turns into collision shapes (texture size, centred on the decor
# entry's ground position).
func _ct_solid_rects(m: Dictionary) -> Array:
	var out: Array = []
	var decor: Array = m["decor"]
	for d in decor:
		if String(d[0]) in SOLID_DECOR_KINDS:
			var tex: Texture2D = DECOR_TEX[d[0]]
			var w := float(tex.get_width())
			var h := float(tex.get_height())
			out.append(Rect2(float(d[1]) - w * 0.5, float(d[2]) - h, w, h))
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
	var from := Vector2(cover.position.x - 120.0, cy)
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
	var from := Vector2(cover.position.x - 120.0, cy)
	var to := Vector2(cover.end.x + 120.0, cy)
	var hit := _ct_ray(from, to)
	if hit.is_empty():
		return [false, "ray %s -> %s passed clean through %s" % [from, to, cover]]
	var hp: Vector2 = hit["position"]
	var ok: bool = hp.x <= cover.position.x + 4.0
	return [ok, "ray stopped at %s (cover %s); nothing behind it is reachable" % [hp, cover]]


func _ct_s_walk_into_solid() -> void:
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return
	var lp = _get_local_player()
	lp.position = Vector2(cover.position.x - 60.0, cover.end.y - 26.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_ct_walk_start_x = lp.position.x
	_on_touch_press(930, move_stick.get_global_rect().get_center() + Vector2(60, 0))


# (b) walking into a solid cover: the player is blocked and slides
# along it, never passing through.
func _ct_c_walk_blocked() -> Array:
	_on_touch_release(930)
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return [true, "no low solid cover on this map"]
	var lp = _get_local_player()
	var moved: bool = lp.position.x > _ct_walk_start_x + 20.0
	var stopped: bool = lp.position.x <= cover.position.x - 17.0 + 4.0
	return [moved and stopped, "player x=%.0f (started %.0f, cover face %.0f, capsule edge %.0f)" % [lp.position.x, _ct_walk_start_x, cover.position.x, cover.position.x - 17.0]]


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
# v2.4 FIRE-BUTTON ACCEPTANCE TEST (--fire-test)
# Drives the REAL touch routing with simulated touches (fake indices
# 910/911/912), like the joystick test. Covers the spec's 12 scenarios
# plus the QA-023 glitch regressions (move/aim/grenade/weapon must
# never fire the gun).
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
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_fire_passed += 1
		else:
			_fire_failed += 1
		print("FIRETEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_fire_step += 1
		_fire_in_step = false
		_fire_timer = 0.0


func _firetest_build_steps() -> void:
	_fire_steps = [
		{"name": "MOVE-ALONE-NO-FIRE", "wait": 1.0, "setup": _ft_s_move_alone, "check": _ft_c_move_alone},
		{"name": "AIM-ALONE-NO-FIRE", "wait": 1.0, "setup": _ft_s_aim_alone, "check": _ft_c_aim_alone},
		{"name": "GRENADE-ALONE-NO-FIRE", "wait": 0.4, "setup": _ft_s_grenade_alone, "check": _ft_c_grenade_alone},
		{"name": "WEAPON-ALONE-NO-FIRE", "wait": 0.4, "setup": _ft_s_weapon_alone, "check": _ft_c_weapon_alone},
		{"name": "PISTOL-TAP-ONE-SHOT", "wait": 0.4, "setup": _ft_s_pistol_tap, "check": _ft_c_pistol_tap},
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
		{"name": "MP-SHOTGUN-SIX-PELLETS", "wait": 0.15, "setup": _ft_s_pellets, "check": _ft_c_pellets},
	]


# --- Fire-test helpers (fake touch indices 910 move / 911 aim / 912 fire) ---

func _ft_lp():
	return _get_local_player()


func _ft_move_center() -> Vector2:
	return move_stick.get_global_rect().get_center()


func _ft_aim_center() -> Vector2:
	return aim_stick.get_global_rect().get_center()


func _ft_fire_center() -> Vector2:
	return fire_button.get_global_rect().get_center()


func _ft_press_move(offset: Vector2) -> void:
	_on_touch_press(910, _ft_move_center() + offset)


func _ft_release_move() -> void:
	_on_touch_release(910)


func _ft_press_aim(offset: Vector2) -> void:
	_on_touch_press(911, _ft_aim_center() + offset)


func _ft_release_aim() -> void:
	_on_touch_release(911)


func _ft_press_fire() -> void:
	_on_touch_press(912, _ft_fire_center())


func _ft_release_fire() -> void:
	_on_touch_release(912)


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
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired == _fire_shots_before and not touch_firing and absf(lp.aim_angle + PI * 0.25) < 0.35
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
	var ok: bool = lp._shots_fired == _fire_shots_before and not touch_firing and not move_stick.is_active() and not aim_stick.is_active() and not fire_button.is_held()
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
	var ok: bool = lp._shots_fired == _fire_shots_before and not touch_firing and not move_stick.is_active() and not aim_stick.is_active() and not fire_button.is_held()
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
	# Drag the FIRE finger far off the button (300 px right).
	_on_touch_drag(912, _ft_fire_center() + Vector2(300, 0))
	# QA-029: refresh the touch state NOW, then capture the baseline,
	# so no physics step after the drag can see the stale "firing"
	# value and fire one extra shot.
	_update_touch_state()
	_fire_shots_before = _ft_lp()._shots_fired


func _ft_c_slide_off_b() -> Array:
	var lp = _ft_lp()
	var ok: bool = not touch_firing and not fire_button.is_held() and lp._shots_fired == _fire_shots_before
	_on_touch_release(912)
	return [ok, "firing=%s fire_held=%s shots=%d (was %d)" % [touch_firing, fire_button.is_held(), lp._shots_fired, _fire_shots_before]]


func _ft_layout_ok() -> Array:
	# No two HUD controls may overlap, and all must be inside the viewport.
	var ctrls: Array = [move_stick, aim_stick, fire_button, grenade_button, switch_button, reload_button, pause_button, score_button]
	var vp := get_viewport().get_visible_rect().size
	for i in ctrls.size():
		var r1: Rect2 = (ctrls[i] as Control).get_global_rect()
		if not Rect2(Vector2.ZERO, vp).encloses(r1):
			return [false, "%s rect %s outside viewport %s" % [(ctrls[i] as Control).name, r1, vp]]
		for j in range(i + 1, ctrls.size()):
			var r2: Rect2 = (ctrls[j] as Control).get_global_rect()
			if r1.intersects(r2):
				return [false, "%s overlaps %s (%s vs %s)" % [(ctrls[i] as Control).name, (ctrls[j] as Control).name, r1, r2]]
	return [true, "8 controls, no overlaps, all inside %s" % vp]


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
	var ok: bool = not move_stick.is_active() and not aim_stick.is_active() and not fire_button.is_held() and not touch_firing and _ft_lp()._shots_fired == shots_before
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
	var ok: bool = n == 6
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "active shotgun pellets from one shot: %d (want 6)" % n]


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
		{"name": "DAMAGE-DEATH-RESPAWN", "wait": 0.3, "setup": _nt_s_damage, "check": _nt_c_damage},
		{"name": "DAMAGE-RESPAWNED", "wait": 3.5, "setup": _nt_s_noop, "check": _nt_c_respawned},
		{"name": "MODE-SURVIVAL", "wait": 0.8, "setup": _nt_s_survival, "check": _nt_c_survival},
		{"name": "MODE-LMS", "wait": 0.8, "setup": _nt_s_lms, "check": _nt_c_lms},
		{"name": "DISCONNECT-CLEANUP", "wait": 0.5, "setup": _nt_s_disconnect, "check": _nt_c_disconnect},
		{"name": "HOST-LEFT-SAFE-EXIT", "wait": 0.3, "setup": _nt_s_host_left, "check": _nt_c_host_left},
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
	_on_score_pressed()
	var ok: bool = shown and not scoreboard_panel.visible
	return [ok, "scoreboard opened=%s closed again=%s" % [shown, not scoreboard_panel.visible]]


func _fl_s_end() -> void:
	_end_match("FlowTest", "flow check")


func _fl_c_end() -> Array:
	var ok: bool = match_over and end_panel.visible
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
