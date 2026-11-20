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
	# QA-095 (v3.7): 5 maps only — 0 Ironfall (new, code-drawn iron
	# plate), 1 Jungle Ruins, 2 Neon City (Sky Brawl), 3 Volcanic
	# Cavern, 4 Pirate Island. The 8 deleted maps' tiles are gone
	# (their tile files are deleted — nothing references them).
	# QA-112 (v3.9): 5 Skyfall — the top 48 px of the pack's
	# platform_solid.png (512 px wide = the seamless period, so
	# _draw_tiles repeats it without a visible seam), sliced by
	# hand into assets/tiles/tile_skyfall.png.
	preload("res://assets/tiles/tile_ironfall.png"),
	preload("res://assets/tiles/tile_jungle.png"),
	preload("res://assets/skybrawl/tiles/tile_neon.png"),
	preload("res://assets/tiles/tile_volcanic.png"),
	preload("res://assets/tiles/tile_pirate.png"),
	preload("res://assets/tiles/tile_skyfall.png"),
]
# Phase 5 — Sky Brawl arena backgrounds as a FAR parallax layer
# (viewport scale ~1.3x, parallax 0.25, never stretched over a map).
# QA-095 (v3.7): 3 left — Index matches the map's "bg" key:
# 0 Ironfall (new, code-drawn dusk factory skyline), 1 Volcanic
# Cavern, 2 Neon City. Jungle Ruins and Pirate Island keep the
# procedural gradient (no "bg" key), as before.
# QA-112 (v3.9): 3 Skyfall dusk sky (pack's bg_sky_dusk.png,
# 1920x1080 landscape — used as the far parallax layer only,
# never stretched over the 10800 px world).
const BG_TEX: Array[Texture2D] = [
	preload("res://assets/skybrawl/maps/bg_ironfall.png"),
	preload("res://assets/skybrawl/maps/bg_volcanic.png"),
	preload("res://assets/skybrawl/maps/bg_neon.png"),
	preload("res://assets/skyfall/SKYFALL_assets/map/bg_sky_dusk.png"),
]
# QA-112 (v3.9): Skyfall pack art (assets/skyfall/ASSET_AUDIT.md —
# every file below verified clean, real transparency, no dark box).
const SF_TEX_TOWER: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/sniper_tower.png")
const SF_TEX_LADDER: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/emergency_ladder.png")
const SF_TEX_BRIDGE: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/rope_bridge.png")
const SF_TEX_GATE: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/summit_gate_closed.png")
const SF_TEX_SWITCH: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/summit_control_switch.png")
const SF_TEX_BARRICADE: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/destructible_barricade.png")
const SF_TEX_WIND: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/wind_zone.png")
const SF_TEX_ELEVATOR: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/platform_moving_elevator.png")
const SF_TEX_COLLAPSING: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/platform_collapsing.png")
const SF_TEX_TRAPDOOR_CLOSED: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/trapdoor_closed.png")
const SF_TEX_TRAPDOOR_OPEN: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/trapdoor_open.png")
const SF_TEX_FLAG_RED: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/flags/flag_red.png")
const SF_TEX_FLAG_BLUE: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/flags/flag_blue.png")
const SF_TEX_FLAG_RED_DROPPED: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/flags/flag_red_dropped.png")
const SF_TEX_FLAG_BLUE_DROPPED: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/flags/flag_blue_dropped.png")
const SF_TEX_ZONE_RED: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/flags/extraction_zone_red.png")
const SF_TEX_ZONE_BLUE: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/flags/extraction_zone_blue.png")
const SF_TEX_ROCK: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/hazards/falling_rock.png")
const SF_TEX_LIGHTNING: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/hazards/summit_storm_lightning.png")
const SF_TEX_WALL: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/tiles/wall_block.png")
# QA-124 (v3.11): per-level backdrops — the pack's 8 level images
# (1800x450 each; drawn at 2x = 3600x900 per half-level band).
# Merged levels use BOTH their images (cliffs over camp, last
# stand under summit).
const SF_TEX_LVL_1: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_1_twin_base_camp.png")
const SF_TEX_LVL_2: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_2_broken_cliffs.png")
const SF_TEX_LVL_3: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_3_underground_tunnels.png")
const SF_TEX_LVL_4: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_4_hanging_bridge.png")
const SF_TEX_LVL_5: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_5_sniper_territory.png")
const SF_TEX_LVL_6: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_6_mechanical_ascent.png")
const SF_TEX_LVL_7: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_7_the_last_stand.png")
const SF_TEX_LVL_8: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_8_flag_summit.png")
# QA-125/126/129 (v3.11): dynamic-effect overlays (50-pack, static
# 512x512 PNGs, animated in-engine). Only the ones below are
# preloaded — import only what is used (see BUGS.md QA-125).
# QA-132: thunder/storm cloud, snow, smoke, whirl, portal,
# portal sparks and arc are un-preloaded with the items that used
# them (clean-up); the textures stay in assets/ for later use.
const FX_TEX_BOLT: Texture2D = preload("res://assets/dynamic_effects/04_lightning_bolt.png")
const FX_TEX_FORKED: Texture2D = preload("res://assets/dynamic_effects/05_forked_lightning.png")
const FX_TEX_RAIN: Texture2D = preload("res://assets/dynamic_effects/29_rain_streaks.png")
const FX_TEX_DUST: Texture2D = preload("res://assets/dynamic_effects/27_dust_cloud.png")
const FX_TEX_FIRE_PILLAR: Texture2D = preload("res://assets/dynamic_effects/08_fire_pillar.png")
const FX_TEX_LAVA: Texture2D = preload("res://assets/dynamic_effects/10_lava_splash.png")
const FX_TEX_MAGMA: Texture2D = preload("res://assets/dynamic_effects/48_magma_burst.png")
const FX_TEX_GUST_L: Texture2D = preload("res://assets/dynamic_effects/19_wind_gust_left.png")
const FX_TEX_GUST_R: Texture2D = preload("res://assets/dynamic_effects/20_wind_gust_right.png")
const FX_TEX_CRACK: Texture2D = preload("res://assets/dynamic_effects/33_ground_crack_energy.png")
const FX_TEX_SHOCKWAVE: Texture2D = preload("res://assets/dynamic_effects/34_ground_shockwave.png")
# QA-119 (v3.11): Thunder Strike bolt art (user's power-up effects pack).
const FX_TEX_THUNDER: Texture2D = preload("res://assets/powerups_effects/06_thunder_strike_lightning_impact_effect.png")
# QA-114 (v3.9): colour-coded climbing routes — WEST (left third),
# CENTRE (middle third), EAST (right third). Same colours on the
# map platforms, the HUD height bar, and the legend.
const SF_ROUTE_COLORS: Array[Color] = [Color(0.2, 0.8, 0.9), Color(0.95, 0.75, 0.2), Color(0.3, 0.85, 0.4)]
const SF_ROUTE_NAMES: Array[String] = ["WEST", "CENTRE", "EAST"]


static func skyfall_route_of(x: float) -> int:
	if x < 1200.0:
		return 0
	if x <= 2400.0:
		return 1
	return 2
# QA-112 (v3.9): power-up HUD — the 3 slot backgrounds + the 64 px
# icons for the 7 power-ups (user rule: every player has 3 slots).
const SF_TEX_SLOT: Array[Texture2D] = [
	preload("res://assets/skyfall/SKYFALL_assets/ui/powerup_slot_1.png"),
	preload("res://assets/skyfall/SKYFALL_assets/ui/powerup_slot_2.png"),
	preload("res://assets/skyfall/SKYFALL_assets/ui/powerup_slot_3.png"),
]
const SF_TEX_PU64 := {
	7: preload("res://assets/powerups_new/03_health_potion_powerup.png"),
	8: preload("res://assets/powerups_new/01_shield_powerup.png"),
	9: preload("res://assets/powerups_new/02_speed_boost_powerup.png"),
	10: preload("res://assets/skyfall/SKYFALL_assets/powerups/powerup_6_jetpack_boost_64.png"),
	11: preload("res://assets/powerups_new/05_wind_blast_powerup.png"),
	12: preload("res://assets/powerups_new/06_thunder_strike_powerup.png"),
	13: preload("res://assets/powerups_new/07_invisibility_powerup.png"),
}
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
# QA-096 (v3.7) — Operation Ironfall slices (assets/ironfall_sliced/):
# the user's 10-sheet pack, hand-boxed, background flood-filled
# from the crop border, verified on magenta/dark-green (no dark
# box in-game). See assets/ASSET_MANIFEST.md Part 5.
const DECOR_IF_TOWER: Texture2D = preload("res://assets/ironfall_sliced/if_tower.png")
const DECOR_IF_GANTRY: Texture2D = preload("res://assets/ironfall_sliced/if_gantry.png")
const DECOR_IF_DERRICK: Texture2D = preload("res://assets/ironfall_sliced/if_derrick.png")
const DECOR_IF_BRIDGE: Texture2D = preload("res://assets/ironfall_sliced/if_bridge.png")
const DECOR_IF_BRIDGE_METAL: Texture2D = preload("res://assets/ironfall_sliced/if_bridge_metal.png")
const DECOR_IF_PLANK: Texture2D = preload("res://assets/ironfall_sliced/if_plank.png")
const DECOR_IF_CAVE: Texture2D = preload("res://assets/ironfall_sliced/if_cave.png")
const DECOR_IF_CAVE2: Texture2D = preload("res://assets/ironfall_sliced/if_cave2.png")
const DECOR_IF_CAVERN: Texture2D = preload("res://assets/ironfall_sliced/if_cavern.png")
const DECOR_IF_ROCKLEDGE: Texture2D = preload("res://assets/ironfall_sliced/if_rockledge.png")
const DECOR_IF_WATER: Texture2D = preload("res://assets/ironfall_sliced/if_water.png")
const DECOR_IF_FALL: Texture2D = preload("res://assets/ironfall_sliced/if_fall.png")
const DECOR_IF_SPIKES: Texture2D = preload("res://assets/ironfall_sliced/if_spikes.png")
const DECOR_IF_VENT: Texture2D = preload("res://assets/ironfall_sliced/if_vent.png")
const DECOR_IF_DOOR: Texture2D = preload("res://assets/ironfall_sliced/if_door.png")
const DECOR_IF_CRATE: Texture2D = preload("res://assets/ironfall_sliced/if_crate.png")
const DECOR_IF_BARREL: Texture2D = preload("res://assets/ironfall_sliced/if_barrel.png")
const DECOR_IF_SANDBAGS: Texture2D = preload("res://assets/ironfall_sliced/if_sandbags.png")
const DECOR_IF_LAMP: Texture2D = preload("res://assets/ironfall_sliced/if_lamp.png")
const DECOR_IF_PALM: Texture2D = preload("res://assets/ironfall_sliced/if_palm.png")
const DECOR_IF_VINES: Texture2D = preload("res://assets/ironfall_sliced/if_vines.png")
const DECOR_IF_ROCK: Texture2D = preload("res://assets/ironfall_sliced/if_rock.png")
const DECOR_IF_TREE: Texture2D = preload("res://assets/ironfall_sliced/if_tree.png")
const DECOR_IF_BUNKER: Texture2D = preload("res://assets/ironfall_sliced/if_bunker.png")
const DECOR_IF_ARCH: Texture2D = preload("res://assets/ironfall_sliced/if_arch.png")
const DECOR_IF_COMMS: Texture2D = preload("res://assets/ironfall_sliced/if_comms.png")
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
# QA-095 (v3.7): 5 maps only, in this order — Ironfall,
# Jungle Ruins, Neon City, Volcanic Cavern, Pirate Island.
# The other 8 maps are deleted (map data, tiles, thumbs,
# backgrounds, lobby entries — nothing references them).
	{
		# QA-096 (v3.7) — Operation Ironfall (user-shared design,
		# OPERATION_IRONFALL.md). Medium 3200x1400, 5 zones:
		# A Northern Watchtower (left, sniper perches y500/y670 +
		# if_tower on the y670 perch, if_comms on the right floor),
		# B Broken Bridges (bridge decor on the y1180/y1010
		# platforms, gaps between levels), C Underground Tunnels
		# (tunnel = floor under the y1180 roof platform x1150-1850,
		# cave-arch entrances at both ends, lamps + concealed
		# pickup inside), D Ironfall Central Base (if_bunker on the
		# floor at the centre, perches y500/y670/y840), E Waterfall
		# Cavern (right, if_fall + if_water pool, if_spikes).
		# Jump rise 170 px between levels, like the other maps.
		# QA-111 (v3.8): reworked to match the concept art
		# (assets/ironfall/concept.jpg, layout reference
		# 00_map_layout_reference.png) — the user confirmed the map
		# must look like the TOP part of the concept:
		# * Central PEAK: new y330 platform (1400-1800) above the
		#   y500 centre perch — the highest point on the map.
		#   The bunker moved OFF the floor onto the peak, with the
		#   comms/dish tower beside it and a red flag on the
		#   bunker roof (code-drawn in _build_arena) — the
		#   fortress + satellite dish + red flag from the concept.
		# * Waterfall moved from the right side to the BOTTOM
		#   CENTRE (if_fall + if_water at x1600 on the floor),
		#   flowing from under the y1180 tunnel roof into its pool.
		# * Second watchtower on the RIGHT y670 perch (3030,670),
		#   mirroring the left one — the concept has two towers.
		# * Rope bridges at the UPPER tiers: if_bridge over the
		#   y840 gap (1070) and if_bridge_metal over the y670 gap
		#   (2730), linking the tower tiers toward the centre.
		# * Palms on the tiers (620,670 and 2800,1010) + a third
		#   cave arch under the left tier (450,1352).
		# * The sun is now a pale full moon (top right) + a
		#   helicopter silhouette in the dusk sky (both drawn in
		#   _build_background for Ironfall only).
		# Platforms 23 -> 24. No tier heights changed (still 170 px
		# rises), no spawns/pickups moved — the suite's platform,
		# spawn and pickup checks are unaffected.
		"name": "Ironfall", "size": Vector2(3200, 1400), "tile": 0,
		"bg": 0,
		"sky_top": Color(0.13, 0.16, 0.28), "sky_bottom": Color(0.45, 0.30, 0.22),
		"hill": Color(0.10, 0.12, 0.20), "sun": Color(1.00, 0.95, 0.80), "fx": "dust",
		"platforms": [
			Rect2(0, 1352, 3200, 48),
			Rect2(150, 1180, 300, 48),
			Rect2(700, 1180, 350, 48),
			Rect2(1150, 1180, 700, 48),
			Rect2(2000, 1180, 300, 48),
			Rect2(2550, 1180, 350, 48),
			Rect2(100, 1010, 240, 48),
			Rect2(450, 1010, 600, 48),
			Rect2(1350, 1010, 500, 48),
			Rect2(2150, 1010, 400, 48),
			Rect2(2750, 1010, 260, 48),
			Rect2(650, 840, 340, 48),
			Rect2(1150, 840, 260, 48),
			Rect2(1500, 840, 260, 48),
			Rect2(2150, 840, 340, 48),
			Rect2(2800, 840, 376, 48),
			Rect2(350, 670, 320, 48),
			Rect2(1350, 670, 260, 48),
			Rect2(2200, 670, 360, 48),
			Rect2(2900, 670, 260, 48),
			Rect2(200, 500, 320, 48),
			Rect2(1450, 500, 300, 48),
			Rect2(2100, 500, 300, 48),
			Rect2(1400, 330, 400, 48),
		],
		"spawns": [Vector2(300, 1318), Vector2(900, 1318), Vector2(1300, 1146), Vector2(850, 976), Vector2(800, 806), Vector2(500, 636), Vector2(2100, 1318), Vector2(2900, 1318), Vector2(2200, 1146), Vector2(2300, 976), Vector2(2300, 806), Vector2(2350, 636)],
		"pickups": [Vector2(300, 1150), Vector2(2700, 1150), Vector2(1500, 1320), Vector2(1600, 810), Vector2(400, 640), Vector2(2250, 470)],
		"decor": [["if_palm", 150, 1352], ["if_derrick", 420, 1352], ["crate", 750, 1352], ["if_vent", 700, 1352], ["if_sandbags", 800, 1180], ["barrels", 950, 1352], ["if_door", 1050, 1352], ["if_cave", 1150, 1352], ["if_lamp", 1300, 1352], ["if_bridge_metal", 1600, 1180], ["crate", 1500, 1010], ["if_lamp", 1700, 1352], ["if_cave2", 1850, 1352], ["column", 2000, 1352], ["if_plank", 2150, 1180], ["if_tower", 500, 670], ["if_gantry", 900, 1180], ["if_rockledge", 600, 1010], ["if_bridge", 2300, 1010], ["barrels", 2400, 1010], ["if_barrel", 2300, 1352], ["if_rock", 2400, 1352], ["if_spikes", 2500, 1352], ["if_crate", 2600, 1352], ["if_fall", 1600, 1352], ["if_water", 1600, 1352], ["if_bunker", 1500, 330], ["if_comms", 1680, 330], ["if_tower", 3030, 670], ["if_bridge", 1070, 840], ["if_bridge_metal", 2730, 670], ["if_palm", 600, 670], ["if_palm", 2800, 1010], ["if_cave", 450, 1352]],
	},
	{
		"name": "Jungle Ruins", "size": Vector2(3200, 1400), "tile": 1,
		"sky_top": Color(0.35, 0.65, 0.85), "sky_bottom": Color(0.80, 0.92, 0.75),
		"hill": Color(0.20, 0.40, 0.20), "sun": Color(1.00, 0.95, 0.60), "fx": "leaves",
		"platforms": [
			Rect2(0, 1352, 3200, 48),
			Rect2(150, 1180, 300, 48),
			Rect2(700, 1180, 400, 48),
			Rect2(450, 1180, 250, 48),
			Rect2(1100, 1180, 600, 48),
			Rect2(1700, 1180, 300, 48),
			Rect2(2000, 1180, 350, 48),
			Rect2(2350, 1180, 250, 48),
			Rect2(2600, 1180, 300, 48),
			Rect2(450, 1010, 600, 48),
			Rect2(800, 840, 280, 48),
			Rect2(1050, 1010, 700, 48),
			Rect2(1150, 840, 260, 48),
			Rect2(1500, 840, 260, 48),
			Rect2(1350, 670, 200, 48),
			Rect2(1750, 1010, 250, 48),
			Rect2(2000, 1010, 400, 48),
			Rect2(2400, 1010, 350, 48),
			Rect2(2150, 840, 300, 48),
			Rect2(2750, 1010, 260, 48),
			Rect2(2500, 670, 260, 48),
			Rect2(2900, 840, 276, 48),
			Rect2(300, 670, 260, 48),
			Rect2(2100, 500, 300, 48),
		],
		"spawns": [Vector2(300, 1318), Vector2(900, 1318), Vector2(1300, 1146), Vector2(1200, 976), Vector2(950, 806), Vector2(450, 636), Vector2(2100, 1318), Vector2(2900, 1318), Vector2(2200, 1146), Vector2(2200, 976), Vector2(2300, 806), Vector2(2600, 636)],
		"pickups": [Vector2(300, 1150), Vector2(2700, 1150), Vector2(1400, 1150), Vector2(1600, 810), Vector2(2300, 810), Vector2(2600, 640)],
		"decor": [["jtree", 130, 1352], ["jpalm", 3000, 1352], ["jstatue", 1400, 1010], ["jpillar", 1100, 1010], ["jpillar", 1700, 1010], ["jtower", 2400, 840], ["jbridge", 1875, 1010], ["jarch", 2100, 1010], ["jtree", 2300, 840], ["jbush", 600, 1352], ["jcrate", 720, 1352], ["jpillar", 1320, 1352], ["jcrate", 1620, 1352], ["jcrate", 1860, 1352], ["jpillar", 2520, 1352], ["jcrate", 3040, 1352], ["jcrate", 210, 1352], ["jcrate", 1260, 1352], ["jpillar", 950, 1352], ["jcrate", 1500, 1180], ["jcrate", 1040, 840], ["jcrate", 360, 670], ["jcrate", 2030, 1352], ["jcrate", 2990, 1352], ["jcrate", 2290, 1180], ["jcrate", 2290, 1010], ["jcrate", 2690, 670], ["barrels", 1100, 1352]],
	},
	{
		"name": "Neon City", "size": Vector2(3400, 1800), "tile": 2,
		"bg": 2,
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
		],
		"spawns": [Vector2(300, 1718), Vector2(900, 1718), Vector2(350, 1546), Vector2(1000, 1246), Vector2(500, 1066), Vector2(580, 766), Vector2(2550, 1718), Vector2(3100, 1718), Vector2(3000, 1546), Vector2(2330, 1216), Vector2(2900, 1066), Vector2(2800, 766)],
		"pickups": [Vector2(600, 1722), Vector2(2800, 1722), Vector2(500, 1550), Vector2(1700, 1370), Vector2(3000, 1550), Vector2(1700, 1550)],
		"decor": [["sb_vent", 720, 1752], ["crate", 1320, 1752], ["barrels", 2070, 1752], ["sb_vent", 2670, 1752], ["crate", 2970, 1752], ["barrels", 3220, 1752], ["sb_vent", 210, 1752], ["sb_vent", 1090, 1280], ["crate", 1200, 1580], ["barrels", 2400, 1752], ["sb_vent", 590, 1100], ["sb_vent", 670, 800], ["sb_vent", 3090, 1580], ["sb_vent", 2420, 1250], ["sb_vent", 2990, 1100], ["sb_vent", 2890, 800]],
	},
	{
		"name": "Volcanic Cavern", "size": Vector2(3000, 1500), "tile": 3,
		"bg": 1,
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
		# 5 maps keep FFA/TDM/Survival/LMS. Level strips in the pack
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
		# across the heights (kinds 7-13, see pickup.gd — kinds
		# UNCHANGED by the rebuild, only positions moved). QA-132:
		# every spot re-anchored to a platform top (y = top - 34)
		# and OUT of the hazard rects — the old shield spot sat
		# INSIDE the lava and the old invisibility spot floated
		# 304 px above the nearest platform.
		"skyfall_pickups": [[1000, 10378, 7], [2600, 10378, 10], [1350, 9358, 11], [1400, 2470, 8], [1200, 5830, 12], [1800, 6110, 13], [2600, 1678, 9]],
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
		"wind": [{"rect": Rect2(1400, 4000, 800, 1400), "dir": Vector2(-1, 0), "strength": 150.0}, {"rect": Rect2(600, 6000, 2400, 800), "dir": Vector2(1, 0), "strength": 120.0}, {"rect": Rect2(900, 9500, 1800, 400), "dir": Vector2(-1, 0), "strength": 100.0}, {"rect": Rect2(1400, 5400, 800, 600), "dir": Vector2(-1, 0), "strength": 150.0}],
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
	"sb_hut_green": DECOR_SB_HUT_GREEN, "sb_crate": DECOR_SB_CRATE, "sb_vent_orange": DECOR_SB_VENT_ORANGE,
	# QA-096: Ironfall slices (visual dressing, except if_crate /
	# if_barrel / if_sandbags which are SOLID cover — see below).
	"if_tower": DECOR_IF_TOWER, "if_gantry": DECOR_IF_GANTRY,
	"if_derrick": DECOR_IF_DERRICK, "if_bridge": DECOR_IF_BRIDGE,
	"if_bridge_metal": DECOR_IF_BRIDGE_METAL, "if_plank": DECOR_IF_PLANK,
	"if_cave": DECOR_IF_CAVE, "if_cave2": DECOR_IF_CAVE2,
	"if_cavern": DECOR_IF_CAVERN, "if_rockledge": DECOR_IF_ROCKLEDGE,
	"if_water": DECOR_IF_WATER, "if_fall": DECOR_IF_FALL,
	"if_spikes": DECOR_IF_SPIKES, "if_vent": DECOR_IF_VENT,
	"if_door": DECOR_IF_DOOR, "if_crate": DECOR_IF_CRATE,
	"if_barrel": DECOR_IF_BARREL, "if_sandbags": DECOR_IF_SANDBAGS,
	"if_lamp": DECOR_IF_LAMP, "if_palm": DECOR_IF_PALM,
	"if_vines": DECOR_IF_VINES, "if_rock": DECOR_IF_ROCK,
	"if_tree": DECOR_IF_TREE, "if_bunker": DECOR_IF_BUNKER,
	"if_arch": DECOR_IF_ARCH, "if_comms": DECOR_IF_COMMS,
	# QA-112 (v3.9): Skyfall decor — tower is SOLID cover (see
	# SOLID_DECOR_KINDS); ladder / rope bridge are pass-through
	# dressing (the bridge's walkable surface is its platform
	# rect; ladders climb through skyfall_ladder_at).
	"sf_tower": SF_TEX_TOWER, "sf_ladder": SF_TEX_LADDER,
	"sf_bridge": SF_TEX_BRIDGE,
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
# QA-085 (v3.7): drawn dust puff. The dust texture is a soft
# white puff drawn over the landing spot.
const DUST_TEX: Texture2D = preload("res://assets/effects/dust.png")
# QA-091 (v3.7): soft dot for the GPUParticles2D blast burst.
const PARTICLE_DOT_TEX: Texture2D = preload("res://assets/effects/particle_dot.png")
# QA-092 (v3.7): Stylized 2D VFX Lite (REEBOO Labs, MIT, v1.0.0,
# Godot 4.4) — shader + GPUParticles2D effects, self-freeing.
# hit_spark = bullet impacts, explosion_small = blast core,
# coin_pickup = pickup grab. slash_arc is NOT used: the game has
# no melee attack, so there is nothing to slash.
const HIT_SPARK_SCENE: PackedScene = preload("res://addons/reeboo_fx2d/effects/hit_spark.tscn")
const EXPLOSION_SMALL_SCENE: PackedScene = preload("res://addons/reeboo_fx2d/effects/explosion_small.tscn")
const COIN_PICKUP_SCENE: PackedScene = preload("res://addons/reeboo_fx2d/effects/coin_pickup.tscn")

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
var _leaving: bool = false # set when leaving for the menu or rematching: _process must stop (multiplayer is torn down / the instance is detached before the scene change lands)

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
var scope_button: Button # QA-105 (v3.8): SCOPE toggle, sniper/rifle only
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
var _ctf_flag_labels: Array = [] # QA-112 (v3.9): RED/BLUE flag status lines (CTF only)
var _sf_slot_buttons: Array = [] # QA-119 (v3.11): 3 tappable power-up slot Buttons (top-right)
var _sf_slot_panel: PanelContainer # QA-119 (v3.11): top-right slot panel (visibility toggle)
var _sf_active_boost_label: Label # QA-112 (v3.9): active boost + time left
var _sf_slot_row: HBoxContainer # QA-112 (v3.9): the 3-slot row (inside the top-right panel)
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
# ---------------------------------------------------------------------------
# QA-112 (v3.9) — SKYFALL: Vertical CTF (mode 4, Skyfall-only) + the
# climbing mechanics. Restored from the v3.6 CTF (QA-080, git
# e972393) and adapted: both flags live at the SUMMIT, captures
# score at the base EXTRACTION ZONES, grabbing takes a 1.5 s hold,
# a dropped flag returns after 15 s, the carrier is 15% slower
# with no jetpack (player.gd reads carrying_flag). Clients never
# decide flag state — the host syncs it on ctf_sync (0.5 s
# heartbeat + on change), exactly like v3.6.
# ---------------------------------------------------------------------------
var _ctf_flags: Array = [] # {team, home, pos, carrier, dropped, node, sprite}
var _ctf_scores: Dictionary = {0: 0, 1: 0} # captures per team
var _ctf_captures: Dictionary = {} # peer id -> captures (scoreboard)
var _ctf_sync_timer: float = 0.0
var _ctf_grab: Dictionary = {} # peer id -> seconds held on a flag
var _ctf_dropped_timer: Dictionary = {} # flag team -> seconds dropped
var _ctf_checkpoints: Dictionary = {0: 0, 1: 0} # team -> highest level 0-3
var _ctf_hold_grace: Dictionary = {0: 0.0, 1: 0.0} # QA-114 (v3.9): 5 s freeze before a wiped team's checkpoint drops
var _ctf_extract_nodes: Array = [] # extraction-zone sprites (pulse)
var _ctf_hud_labels: Array = [] # flag-status labels (rebuilt in _build_hud)
# Skyfall mechanics state (all host-driven, rendered on every peer).
var _sf_elevators: Array = [] # {body, sprite, cfg, phase}
var _sf_rotator: Dictionary = {} # {body, sprite, cfg, angle}
var _sf_summit_elevator: Dictionary = {} # {body, sprite, cfg, state, timer}
var _sf_collapsing: Array = [] # {idx, shape, sprite, state, timer}
var _sf_trapdoors: Array = [] # {idx, shape, spr_closed, spr_open, state, timer}
var _sf_gate_shape: CollisionShape2D = null # summit gate (removed on open)
var _sf_gate_sprite: Sprite2D = null
var _sf_gate_open: bool = false
var _sf_gate_timer: float = 0.0 # opens 45 s after match start
var _sf_switch_on: bool = false # control switch pressed (visual)
var _sf_switch_timer: float = 0.0 # 1 s stand-on channel
var _sf_summit_timer: float = 0.0 # summit elevator active time left
var _sf_comeback_team: int = -1 # QA-114 (v3.9): team trailing by >= 2 pts — gets catch-up help
var _sf_comeback_pu_timer: float = 0.0 # QA-114: bonus power-up timer for the trailing team (25 s)
var _sf_event_timer: float = 0.0 # QA-114 (v3.9): countdown to the next RANDOM event (45-90 s)
var _sf_event_active: String = "" # QA-114: current random event ("" = none)
var _sf_event_time_left: float = 0.0 # QA-114: seconds left on the current event
var _sf_event_wind_flip: bool = false # QA-114: route-shift flips the wind for 20 s
var _sf_event_collapse_idx: int = -1 # QA-114: platform collapsed by the random event
var _sf_scenery: Dictionary = {} # QA-115 (v3.9): dynamic scenery nodes (clouds, waterfall, heli, gears, steam, flash)
var _sf_pings: Array = [] # QA-114 (v3.9): active team pings {node, label, pos, timer}
var _sf_ping_cooldown: float = 0.0 # QA-114: 3 s between pings
var ping_button: Button # QA-114 (v3.9): PING button (Skyfall only)


static func _sf_level_of(y: float) -> int:
	# World y -> level 1-6 (each level is 1800 px tall; y grows
	# downward, so level 1 is the bottom). Used by pings and the
	# height bar labels.
	return clampi(6 - int(y / 1800.0), 1, 6)


# QA-135 (v3.13): Wind Blast / Thunder Strike targeting — the
# target enemy must be (1) standing on the SAME PLATFORM as the
# activator AND (2) at the SAME HEIGHT (within
# SF_POWERUP_HEIGHT_TOL px — both stand on the same platform
# surface, so this excludes an enemy jetpacking high above the
# platform or hanging below it).
const SF_POWERUP_HEIGHT_TOL := 60.0
# _sf_platform_under returns the platform index under a player's
# feet, or -1 when they are not standing on any static platform
# (airborne, on an elevator, on a mover). _sf_find_powerup_target
# returns the nearest valid living enemy, or null. The host
# re-validates the named target with _sf_validate_powerup_target
# before executing (positions may have moved since the tap).
func _sf_platform_under(pos: Vector2) -> int:
	var feet := pos + Vector2(0, 31)
	var plats: Array = MAPS[map_id].get("platforms", [])
	for i in plats.size():
		var r: Rect2 = plats[i]
		if feet.x >= r.position.x - 4.0 and feet.x <= r.end.x + 4.0 and absf(feet.y - r.position.y) <= 10.0:
			return i
	return -1


func _sf_find_powerup_target(activator: Node2D) -> Node2D:
	if map_id != GameData.SKYFALL_MAP_ID:
		return null
	var my_plat := _sf_platform_under(activator.position)
	if my_plat < 0:
		return null
	var best: Node2D = null
	var best_d := 1e9
	for other in players_node.get_children():
		if other == activator or not other.alive:
			continue
		if int(other.team) == int(activator.team):
			continue
		if _sf_platform_under(other.position) != my_plat:
			continue
		if absf(other.position.y - activator.position.y) > SF_POWERUP_HEIGHT_TOL:
			continue
		var d: float = other.position.distance_to(activator.position)
		if d < best_d:
			best_d = d
			best = other
	return best


func _sf_validate_powerup_target(activator: Node2D, target: Node2D) -> bool:
	if target == null or not is_instance_valid(target):
		return false
	if not target.alive:
		return false
	if int(target.team) == int(activator.team):
		return false
	var my_plat := _sf_platform_under(activator.position)
	if my_plat < 0:
		return false
	if _sf_platform_under(target.position) != my_plat:
		return false
	if absf(target.position.y - activator.position.y) > SF_POWERUP_HEIGHT_TOL:
		return false
	return true
var _sf_barricades: Array = [] # {rect, sprite, shape, hp, alive, timer}
var _sf_rocks: Array = [] # {node, vel} falling rocks (host spawns)
var _sf_rock_timer: float = 0.0
var _sf_storm_timer: float = 90.0 # Summit Storm every 90 s
var _sf_storm_active: bool = false
var _sf_storm_time_left: float = 0.0
var _sf_storm_nodes: Array = [] # lightning sprites shown during a storm
var _sf_pickup_timers: Dictionary = {} # skyfall power-up spot -> seconds
# QA-126 (v3.11): hazard damage state. Host-only damage ticks;
# visuals are pure functions of the match clock so all peers agree.
var _sf_hazard_tick: Dictionary = {} # peer id -> seconds until next hazard tick
var _sf_strike_timer: float = 3.0 # seconds until the next storm lightning strike
var _sf_strike: Dictionary = {} # pending strike {peer, pos, node, ring, timer}
# QA-135 (v3.13): L4 is the storm-lightning level — its own strike
# system, independent of the Summit Storm: a bolt every 6 s at a
# random living player in L4 (y 3600-5400), same 0.6 s telegraph
# and 15 HP as the storm strikes (QA-126).
var _sf_strike_l4_timer: float = 6.0 # seconds until the next L4 lightning strike
var _sf_strike_l4: Dictionary = {} # pending L4 strike {peer, pos, ring, bolt, timer}
var _wind_tornado_node: Node2D = null # QA-135: the active Wind Blast tornado (tests read it)
var _sf_hazard_fx: Array = [] # {kind, rect, flame, lava, magma} hazard visuals
# QA-129 (v3.11): bridge wind gusts — every 15 s the bridge wind
# doubles for 3 s (pure function of the match clock, so every peer
# agrees; see skyfall_wind_at).
var _sf_gust_fx: Array = [] # sweeping gust sprites (bridge wind zone)
var _sf_initial_powerups_done: bool = false
var _sf_match_time: float = 0.0 # seconds since countdown ended
var _sf_boost_slots: Array = [] # HUD power-up slot icons (3)
# QA-112 (v3.9): spawn counters for the FT-SF-RARITY test (power-ups
# must spawn less often than weapons). Read by the features test
# only; they cost nothing in normal play.
var _test_weapon_spawns: int = 0
var _test_powerup_spawns: int = 0
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
var _invis_warning_chip: PanelContainer = null # QA-121 (v3.11): red "Enemy is invisible!" chip (top of the feed)
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
var _kd_label: Label # QA-079: slim "K 3 • D 1" line under the score, always visible
var _pause_info_label: Label # QA-113 (v3.9): map • mode • time left line in the pause menu
var _sfx_value_label: Label # QA-113 (v3.9): "75%" next to the Sound slider
var _music_value_label: Label # QA-113 (v3.9): "75%" next to the Music slider
var _stats_recorded: bool = false # QA-078: record_match runs once per match
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
var _ft_rifle_dev_start: int = 0 # QA-061: shot_devs size when the rifle-straight step starts
var _ft_smg_dev_start: int = 0 # QA-104: shot_devs size when the SMG-spread step starts
var _ft_inside_shots0: int = 0 # QA-055: _shots_fired when the inside-geometry step starts
var _ft_inside_old: Array = [] # QA-055: instance ids of bullets already flying at step start
var _fire_weapon_before: int = 0
var _fire_flashes_before: int = 0 # QA-075: _muzzle_flashes when the muzzle-flash step starts
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
var _repl_sim_kill_k0: int = 0 # QA-069: killer kills before the kill-chain steps
var _repl_sim_kill_d0: int = 0 # QA-069: victim deaths before the kill-chain steps
var _repl_sim_kill_feed0: int = 0 # QA-069: kill-feed entries before a kill-chain step
var _repl_sim_kill_lock_wait: bool = false # QA-069: step 15/16 is waiting out the 1 s QA-031 lock
var _repl_sim_kill_snaps_done: bool = false # QA-069: step 16 score snapshots already delivered to the shadow
var _repl_sim_burst_pending: Array = [] # QA-068: step 17 snapshots held back, then delivered in bursts (Wi-Fi jitter)
var _repl_sim_delayed: Array = [] # QA-073: step 18 snapshots held back 300 ms (delayed delivery)
var _repl_sim_last_snap: Dictionary = {} # QA-073: step 18 last snapshot actually delivered (duplicate probe)
# QA-073: dev-only network-stats display (spec §7). Hidden by
# default — never visible in normal play. Enabled with the
# --net-stats flag or the F3 key (desktop/dev). Shows ping/RTT,
# packet loss, updates/s, buffer size, interpolation delay,
# extrapolation time, local vs authoritative position, FPS.
var _net_stats_label: Label = null
var _net_stats_visible: bool = false
var _net_stats_timer: float = 0.0
# QA-073: host-side divergence guard (spec §4). Per-peer seconds
# the host's rendered copy has sat >300 px from the newest snapshot
# while the stream stayed fresh; _diverge_corr_seq numbers the
# corrections so a stale one is ignored on the client.
var _diverge_time: Dictionary = {}
var _diverge_timer: float = 0.0
var _diverge_corr_seq: int = 0
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
var _v37_shots: bool = false # v3.7: --v37-shots captures jetpack flame + muzzle flash, pickups, hit flash to user://shot_v37_*.png
var _v37_timer: float = 0.0
var _v37_stage: int = -1
var _v38_shots: bool = false # v3.8 QA-105: --v38-shots captures sniper scope + sight line (clear/blocked), rifle scope, SMG no-scope to user://shot_v38_*.png
var _v38_timer: float = 0.0
var _v38_stage: int = -1
var _glitch_shots: bool = false # v3.8 QA-108: --glitch-shots captures gun hold (6 weapons) + headgear (7) in every state to user://shot_glitch_*.png
var _glitch_timer: float = 0.0
var _glitch_stage: int = -1
var _glitch_steps: Array = []
var _map_shots: bool = false # v3.8 QA-111: --map-shot captures the Ironfall map in 4 views (left, centre peak, centre floor/waterfall, right) to user://shot_map_*.png
var _map_timer: float = 0.0
var _map_stage: int = -1
var _sf_shot_timer: float = 0.0 # QA-112 (v3.9): --skyfall-shots stage clock
var _sf_shot_stage: int = -1 # QA-112 (v3.9): --skyfall-shots stage
var _land_shots: bool = false # v3.8 QA-110: --land-shot drops the player from high and captures the landing frame + 0.15 s later to user://shot_land_*.png
var _skyfall_shots: bool = false # QA-112 (v3.9): --skyfall-shots captures the 6 Skyfall levels to user://shot_sf_*.png
var _land_timer: float = 0.0
var _land_stage: int = -1
var _land_armed: bool = false
var _land_t0: float = 0.0
var _land_maxfall: float = 0.0
var _gs_timer: float = 0.0
var _gs_stage: int = -1
var _flow_steps: Array = []
var _flow_step: int = 0
var _flow_in_step: bool = false
var _flow_timer: float = 0.0
var _flow_passed: int = 0
var _flow_failed: int = 0
var _flow_done: bool = false
# v3.5 restart check (--restart-test, QA-060): start a match, leave
# it, start a SECOND match from the menu, end it, rematch (scene
# reload) and play again. Counts live in GameData so they survive
# the scene changes; the phase does too (see game_data.gd).
var _restart_test: bool = false
var _restart_steps: Array = []
var _restart_step: int = 0
var _restart_in_step: bool = false
var _restart_timer: float = 0.0
var _restart_done: bool = false


func _ready() -> void:
	add_to_group("game")
	# v3.2 NEON ARENA: wire the gohud theme once, early, so the HUD
	# and dialogs inherit it (same preset as the menu in main.gd).
	GoUi.config = preload("res://ui/gohud_config.tres")
	GoUi.use_preset(GoThemePresets.SCIFI_DARK)
	process_mode = Node.PROCESS_MODE_ALWAYS
	map_id = clampi(GameData.map_id, 0, MAPS.size() - 1)
	game_mode = GameData.game_mode
	# QA-112 (v3.9): CTF (mode 4) exists ONLY on Skyfall. A stale
	# mode 4 from another map (or an old lobby) falls back to FFA
	# here, so CTF can never start on the wrong map — the same
	# guard the lobby applies in main.gd.
	if game_mode == 4 and map_id != GameData.SKYFALL_MAP_ID:
		game_mode = 0
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
	_v37_shots = "--v37-shots" in OS.get_cmdline_user_args()
	_v38_shots = "--v38-shots" in OS.get_cmdline_user_args()
	_glitch_shots = "--glitch-shots" in OS.get_cmdline_user_args()
	_map_shots = "--map-shot" in OS.get_cmdline_user_args()
	_land_shots = "--land-shot" in OS.get_cmdline_user_args()
	_skyfall_shots = "--skyfall-shots" in OS.get_cmdline_user_args() # QA-112 (v3.9): --skyfall-shots captures the 6 Skyfall levels
	_join_test_host = "--join-test-host" in OS.get_cmdline_user_args()
	_join_test_client = "--join-test-client" in OS.get_cmdline_user_args() or "--join-test-client-quick" in OS.get_cmdline_user_args()
	_repl_sim_test = "--repl-sim-test" in OS.get_cmdline_user_args()
	_restart_test = "--restart-test" in OS.get_cmdline_user_args()
	# QA-073: dev-only net-stats panel (spec §7). Off by default;
	# --net-stats turns it on for a dev session, F3 toggles it live.
	_net_stats_visible = "--net-stats" in OS.get_cmdline_user_args()
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
	audio.set_sfx_enabled(GameData.sfx_enabled)
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
	var _is_test_mode := _smoke_test or _joystick_test or _fire_test or _net_test or _flow_test or _scale_test or _collision_test or _physics_test or _perf_test or _features_test or _repl_sim_test or _restart_test or _v37_shots or _v38_shots or _glitch_shots or _map_shots or _land_shots or _skyfall_shots
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
	# QA-112 (v3.9): Skyfall mechanics + CTF flags (no-op on other maps).
	_build_skyfall(map)
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
	cap.radius = 20.0 # QA-071b: 1.20x player capsule (was 17)
	cap.height = 62.0 # QA-071b: 1.20x player capsule (was 52)
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cap
	q.transform = Transform2D(0.0, pos)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var space := get_world_2d().direct_space_state
	return space.intersect_shape(q, 1).is_empty()


func get_valid_spawn_point(player_index: int, exclude_peer: int, avoid_pos: Vector2 = Vector2.INF) -> Vector2:
	# Try the player's own spawn first, then every other spawn in
	# order; if none is valid, return INF and the caller retries
	# (0.5 s) instead of teleporting into a wall or a camper.
	# Phase 5 (TDM): spawns[0:6] are the left half (team 0) and
	# spawns[6:12] the right half (team 1) — a team tries its own
	# half first, then the other half, so teams never spawn
	# interleaved. FFA keeps the old round-robin order.
	# QA-063: avoid_pos (a stuck player's current spot) — a
	# recovery must never drop the player back into the same trap.
	# First pass skips spawns within 150 px of avoid_pos; if that
	# leaves nothing, fall back to the old behaviour.
	var spawns: Array = MAPS[map_id]["spawns"]
	var n := spawns.size()
	var start := (player_index - 1) % n
	var order: Array = []
	# QA-112 (v3.9): CTF respawns at the team's highest checkpoint
	# (L1 base / L3 tunnel / L5 top / L7 arena), so a dead carrier
	# does not climb the whole tower again. The checkpoint is tried
	# first; if it is not valid (enemy camping it), the normal
	# team-half order below runs instead.
	if game_mode == 4:
		var node := players_node.get_node_or_null(str(exclude_peer))
		var team := (player_index - 1) % 2
		if node != null and int(node.team) in [0, 1]:
			team = int(node.team)
		var cps: Array = MAPS[map_id].get("checkpoints", [])
		var lvl := int(_ctf_checkpoints.get(team, 0))
		if lvl > 0 and lvl < cps.size():
			var cp: Vector2 = (cps[lvl] as Array)[team]
			if (avoid_pos == Vector2.INF or cp.distance_to(avoid_pos) >= 150.0) and is_spawn_valid(cp, exclude_peer):
				return cp
	if game_mode == 1 or game_mode == 4:
		# QA-078: use the player's REAL team, not index parity —
		# a lobby team pick can put a player on the other half
		# from what their spawn index would suggest. Fall back to
		# parity only when the node is not there yet (first spawn).
		var team := (player_index - 1) % 2
		var node := players_node.get_node_or_null(str(exclude_peer))
		if node != null and int(node.team) in [0, 1]:
			team = int(node.team)
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
		if avoid_pos != Vector2.INF and cand.distance_to(avoid_pos) < 150.0:
			continue
		if is_spawn_valid(cand, exclude_peer):
			return cand
	if avoid_pos != Vector2.INF:
		for idx in order:
			var cand2: Vector2 = spawns[int(idx)]
			if is_spawn_valid(cand2, exclude_peer):
				return cand2
	return Vector2.INF


func is_on_ice(pos: Vector2) -> bool:
	# Ice zone (GAP-51, spec §18.A): the old ice map only — that
	# map is deleted in v3.7 (QA-095), so no map has ice any more.
	# Kept as a query (player.gd calls it) that always answers
	# false; the friction/accel constants in physics_config.gd
	# stay for reference. Do NOT re-add a map-id check here.
	return false


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
	# QA-111 (v3.8): Ironfall's helicopter silhouette in the dusk
	# sky, top right near the moon — the concept shows one flying
	# past the full moon. Code-drawn dark silhouette (no heli sprite
	# in the sliced pack), same depth as the sun, behind the hills.
	if map_id == 0:
		var heli := Node2D.new()
		heli.position = Vector2(map_size.x * 0.7, 130)
		heli.z_index = -9
		add_child(heli)
		var hcol := Color(0.08, 0.10, 0.18, 0.85)
		var hbody := Polygon2D.new()
		hbody.polygon = PackedVector2Array([Vector2(-32, -4), Vector2(-22, -10), Vector2(8, -10), Vector2(24, -4), Vector2(30, 0), Vector2(24, 6), Vector2(0, 9), Vector2(-24, 8), Vector2(-32, 2)])
		hbody.color = hcol
		heli.add_child(hbody)
		var htail := Polygon2D.new()
		htail.polygon = PackedVector2Array([Vector2(24, -3), Vector2(56, -5), Vector2(56, 1), Vector2(24, 3)])
		htail.color = hcol
		heli.add_child(htail)
		var hrotor := Polygon2D.new()
		hrotor.polygon = PackedVector2Array([Vector2(-46, -17), Vector2(46, -17), Vector2(46, -14), Vector2(-46, -14)])
		hrotor.color = hcol
		heli.add_child(hrotor)
		var hmast := Polygon2D.new()
		hmast.polygon = PackedVector2Array([Vector2(-2, -14), Vector2(2, -14), Vector2(2, -8), Vector2(-2, -8)])
		hmast.color = hcol
		heli.add_child(hmast)
		var htailrotor := Polygon2D.new()
		htailrotor.polygon = PackedVector2Array([Vector2(54, -12), Vector2(57, -12), Vector2(57, 2), Vector2(54, 2)])
		htailrotor.color = hcol
		heli.add_child(htailrotor)
		var hskid := Polygon2D.new()
		hskid.polygon = PackedVector2Array([Vector2(-24, 13), Vector2(24, 13), Vector2(24, 15), Vector2(-24, 15)])
		hskid.color = hcol
		heli.add_child(hskid)
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
	# QA-072 (map artwork): midground silhouette layer — a stepped
	# skyline of distant buildings / pillars / dunes in the map's own
	# hill colour (darkened), seeded by map_id so every map's skyline
	# differs. Purely visual (z -7, behind platforms and players);
	# the gradient + parallax image + 2 hill ridges stay as they were.
	var sil := Polygon2D.new()
	var sp := PackedVector2Array()
	var sil_base := map_size.y - 60.0
	sp.append(Vector2(0, map_size.y))
	var seed := 12345 + map_id * 7919
	var sx := 0.0
	while sx < map_size.x:
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var sw := 120.0 + float(seed % 140)
		seed = (seed * 1103515245 + 12345) & 0x7fffffff
		var sh := 60.0 + float(seed % 200)
		sp.append(Vector2(sx, sil_base - sh))
		sp.append(Vector2(minf(sx + sw, map_size.x), sil_base - sh))
		sx += sw + 30.0 + float(seed % 60)
	sp.append(Vector2(map_size.x, map_size.y))
	sil.polygon = sp
	var hc: Color = map["hill"]
	sil.color = Color(hc.r * 0.6, hc.g * 0.6, hc.b * 0.6, 0.55)
	sil.z_index = -7
	add_child(sil)


# QA-030: solid decor kinds — these are real cover. They get a
# collision rectangle on layer 1 (the same layer the bullet raycast
# and the player use), so bullets stop at them and players cannot walk
# through them. Everything else (trees, palms, bushes, bridges,
# arches) stays visual dressing with no collision, exactly as before.
const SOLID_DECOR_KINDS := ["crate", "barrels", "sandbags", "rock", "column",
	"jpillar", "jstatue", "jtower", "jcrate", "jrock",
	# Phase 5 — Sky Brawl solid structures (huts/blocks/vents/crate).
	"sb_hut", "sb_hut_pink", "sb_hut_blue", "sb_vent", "sb_vent_orange",
	"sb_shrine", "sb_block", "sb_hut_green", "sb_crate",
	# QA-096: Ironfall solid props (crate / barrel / sandbags).
	"if_crate", "if_barrel", "if_sandbags",
	# QA-112 (v3.9): Skyfall sniper tower — solid cover (256x384).
	"sf_tower"]
# GAP-13: bridges/arches look walkable — they now get a thin top plank
# (24 px at the sprite's top edge), not the full texture.
const BRIDGE_DECOR_KINDS := ["bridge", "jbridge", "jarch"]
# GAP-14: per-kind inset (px trimmed per side) so the solid rect
# matches the visible sprite, not the transparent padding.
const DECOR_INSETS := {"crate": 6, "barrels": 8, "sandbags": 6, "rock": 10,
	"column": 10, "jpillar": 10, "jstatue": 8, "jtower": 10, "jcrate": 6, "jrock": 10,
	"sb_hut": 10, "sb_hut_pink": 10, "sb_hut_blue": 10, "sb_vent": 10,
	"sb_vent_orange": 10, "sb_shrine": 10, "sb_block": 10, "sb_hut_green": 10,
	"sb_crate": 10, "if_crate": 6, "if_barrel": 8, "if_sandbags": 6,
	"sf_tower": 12}


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
	# QA-111 (v3.8): Ironfall's red flag on the bunker roof — the
	# concept's central fortress flies a red flag beside the dish.
	# Code-drawn (no flag sprite in the sliced pack): a thin dark
	# pole + red pennant, placed above the if_bunker decor entry.
	# The pole starts 6 px below the sprite's top edge so it sits
	# into the roof instead of floating on transparent padding.
	if map_id == 0:
		for d in decor:
			if String(d[0]) == "if_bunker":
				var bx := float(d[1])
				var btop := float(d[2]) - float(DECOR_IF_BUNKER.get_height())
				var pole := Polygon2D.new()
				pole.polygon = PackedVector2Array([Vector2(bx - 2, btop + 6), Vector2(bx + 2, btop + 6), Vector2(bx + 2, btop - 32), Vector2(bx - 2, btop - 32)])
				pole.color = Color(0.15, 0.15, 0.18)
				pole.z_index = -1
				add_child(pole)
				var flag := Polygon2D.new()
				flag.polygon = PackedVector2Array([Vector2(bx + 2, btop - 32), Vector2(bx + 30, btop - 25), Vector2(bx + 2, btop - 18)])
				flag.color = Color(0.85, 0.12, 0.12)
				flag.z_index = -1
				add_child(flag)
				break


func _build_ice_zone(map: Dictionary) -> void:
	# Ice zone visual (GAP-51): the old ice map is deleted in v3.7
	# (QA-095), so there is no ice floor to draw a sheen on.
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
		var feet: Vector2 = child.position + Vector2(0, 24) # QA-071b: was 20, taller player (24 = 20 * 1.20)
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


func _update_skyfall(delta: float) -> void:
	if map_id != GameData.SKYFALL_MAP_ID:
		return
	# Match clock (drives the gate + storm + movers). Counts only
	# after the countdown, so every peer agrees on the schedule.
	if not _countdown_active and not match_over:
		_sf_match_time += delta
	# --- Summit gate: opens 45 s into the match. The side ledges
	# are always open, so it never blocks the climb. ---
	if not _sf_gate_open and not match_over and _sf_match_time >= 45.0:
		_sf_gate_open = true
		if _sf_gate_shape != null:
			_sf_gate_shape.set_deferred("disabled", true)
		if _sf_gate_sprite != null:
			_sf_gate_sprite.visible = false
		_ctf_feed("The summit gate is open!", Color(0.9, 0.9, 0.9))
	# --- Wind: push every player inside a wind zone (player.gd
	# applies wind_force as extra acceleration). ---
	for child in players_node.get_children():
		if "wind_force" in child:
			child.set("wind_force", skyfall_wind_at(child.position))
	# --- Moving elevators + rotating platform: pure functions of
	# the match clock, so every peer agrees with no RPC. ---
	for e in _sf_elevators:
		var cfg: Dictionary = e["cfg"]
		var period := 6.0
		var t := fmod(_sf_match_time + float(e.get("phase", 0.0)) * period, period)
		var y: float
		if t < period * 0.5:
			y = lerpf(float(cfg["y_bottom"]), float(cfg["y_top"]), t / (period * 0.5))
		else:
			y = lerpf(float(cfg["y_top"]), float(cfg["y_bottom"]), (t - period * 0.5) / (period * 0.5))
		(e["body"] as AnimatableBody2D).position = Vector2(float(cfg["x"]) + float(cfg["w"]) * 0.5, y + 24.0)
	if not _sf_rotator.is_empty():
		var rcfg: Dictionary = _sf_rotator["cfg"]
		var ang := _sf_match_time * float(rcfg.get("speed", 0.5))
		var centre: Vector2 = rcfg["center"]
		(_sf_rotator["body"] as AnimatableBody2D).position = centre + Vector2(cos(ang), sin(ang)) * float(rcfg.get("radius", 120.0))
	# --- Control switch: stand within 90 px for 1 s (any player).
	# Activates the summit elevator for 30 s. Detected locally on
	# every peer (the 1 s channel is long enough that all agree). ---
	if not _sf_summit_elevator.is_empty():
		var sw: Dictionary = MAPS[map_id].get("switch", {})
		var spos: Vector2 = sw.get("pos", Vector2(1800, 1712))
		var near := false
		for child in players_node.get_children():
			if child.alive and child.position.distance_to(spos) < 90.0:
				near = true
				break
		if near and _sf_summit_timer <= 0.0:
			_sf_switch_timer += delta
			if _sf_switch_timer >= 1.0:
				_sf_switch_timer = 0.0
				_sf_summit_timer = 30.0
				_sf_switch_on = true
				_ctf_feed("Summit elevator activated for 30 s!", Color(0.5, 1.0, 0.5))
		else:
			_sf_switch_timer = 0.0
		if _sf_summit_timer > 0.0:
			_sf_summit_timer -= delta
			_sf_update_summit_elevator(delta)
	# --- Collapsing platforms + trapdoors: local state machines
	# (every peer sees the same player positions, so they agree). ---
	_sf_update_collapsing(delta)
	_sf_update_trapdoors(delta)
	# --- Falling rocks (host spawns, all peers simulate the fall). ---
	_sf_update_rocks(delta)
	# --- Summit Storm every 90 s: lightning strikes the summit. ---
	_sf_update_storm(delta)
	# --- QA-135 (v3.13): L4 storm lightning — its own strike
	# cadence (every 6 s) at a random living player in L4. ---
	_sf_update_strike_l4(delta)
	# --- QA-126 (v3.11): lava / fire hazard damage ticks. ---
	_sf_update_hazards(delta)
	# --- Dynamic scenery (QA-115): clouds, waterfall, helicopter,
	# gears, steam, storm lightning — scenery only. ---
	_update_skyfall_scenery(delta)
	# --- Barricade respawn (host only; clients get the RPC). ---
	if multiplayer.is_server():
		for b in _sf_barricades:
			if not bool(b["alive"]):
				b["timer"] = float(b["timer"]) - delta
				if float(b["timer"]) <= 0.0:
					b["alive"] = true
					b["hp"] = 100.0
					(b["sprite"] as Node2D).visible = true
					if b["shape"] != null:
						(b["shape"] as CollisionShape2D).set_deferred("disabled", false)
					rpc("sf_barricade_remote", _sf_barricades.find(b), true)
	# --- CTF checkpoints (QA-114, v3.9): a team's checkpoint is the
	# HIGHEST level any living member currently stands at or above
	# (levels 2, 4, 6 — QA-123 rebuild). It is
	# recomputed live every frame, so it ADVANCES as the team climbs
	# and DROPS BACK DOWN when the team loses the level (everyone
	# dead or fallen below it) — dying on level 7 no longer sends a
	# player back to the bottom while the team still holds 7, and
	# losing 7 drops the respawn back to 5 (or 3, or base). The
	# thresholds come from the checkpoint spots themselves (their
	# y), so the list stays configurable in one place (map data
	# "checkpoints" + GameData.SF_CHECKPOINT_LEVELS). Host tracks,
	# ctf_sync carries it to clients.
	# GRACE (QA-114): when a team has NO living members at all, the
	# checkpoint FREEZES for 5 s instead of dropping instantly —
	# a single death (respawn 3 s) must not drop the respawn to the
	# bottom while the team still held the level. Only a full wipe
	# that lasts 5 s drops it. A living member walking down drops
	# it immediately (no grace — the team is alive and below).
	if game_mode == 4 and multiplayer.is_server() and not match_over:
		var cps: Array = MAPS[map_id].get("checkpoints", [])
		if cps.size() >= 4:
			var held := {0: 0, 1: 0}
			var any_alive := {0: false, 1: false}
			for child in players_node.get_children():
				if not child.alive:
					continue
				var team := int(child.team)
				if team < 0 or team > 1:
					continue
				any_alive[team] = true
				var y: float = child.position.y
				# Checkpoint spots sit ~34 px above the platform
				# top (the player's centre stands 31 px above it)
				# — allow a 40 px tolerance or a standing player
				# never counts as "at" the level (the L6 spot is
				# 1678 but a standing player is at y 1681).
				var lvl := 0
				if y <= float((cps[3] as Array)[team].y) + 40.0:
					lvl = 3
				elif y <= float((cps[2] as Array)[team].y) + 40.0:
					lvl = 2
				elif y <= float((cps[1] as Array)[team].y) + 40.0:
					lvl = 1
				held[team] = maxi(int(held[team]), lvl)
			for team in [0, 1]:
				var prev := int(_ctf_checkpoints.get(team, 0))
				var now := int(held[team])
				if bool(any_alive[team]):
					_ctf_hold_grace[team] = 0.0
					if now != prev:
						_ctf_checkpoints[team] = now
						if now > prev:
							_ctf_feed("⚑ %s holds Level %d — respawn moved up!" % ["RED" if team == 0 else "BLUE", GameData.SF_CHECKPOINT_LEVELS[now]], _ctf_team_color(team))
						else:
							_ctf_feed("⚑ %s lost Level %d — respawn moved back down." % ["RED" if team == 0 else "BLUE", GameData.SF_CHECKPOINT_LEVELS[prev]], _ctf_team_color(team))
				elif prev > 0:
					# Whole team dead: freeze the checkpoint for 5 s.
					var g := float(_ctf_hold_grace.get(team, 0.0)) + delta
					_ctf_hold_grace[team] = g
					if g >= 5.0:
						_ctf_hold_grace[team] = 0.0
						_ctf_checkpoints[team] = 0
						_ctf_feed("⚑ %s lost Level %d — respawn moved back down." % ["RED" if team == 0 else "BLUE", GameData.SF_CHECKPOINT_LEVELS[prev]], _ctf_team_color(team))
	# --- Power-up spawning (host only; rarer than weapons — see
	# _update_skyfall_powerups). ---
	_update_skyfall_powerups(delta)
	# --- Comeback help + random events (QA-114, host only). ---
	_sf_update_comeback(delta)
	_sf_update_random_events(delta)
	# --- Extraction-zone pulse. ---
	var pulse := 0.9 + 0.1 * sin(_sf_match_time * 3.0)
	for z in _ctf_extract_nodes:
		(z as Sprite2D).scale = Vector2(pulse, pulse)
	# --- Team pings (QA-114): 5 s lifetime, 3 s cooldown. ---
	if _sf_ping_cooldown > 0.0:
		_sf_ping_cooldown -= delta
	for i in range(_sf_pings.size() - 1, -1, -1):
		var pg: Dictionary = _sf_pings[i]
		pg["timer"] = float(pg.get("timer", 0.0)) - delta
		if float(pg.get("timer", 0.0)) <= 0.0:
			if is_instance_valid(pg.get("node")):
				(pg["node"] as Node).queue_free()
			if is_instance_valid(pg.get("label")):
				(pg["label"] as Node).queue_free()
			_sf_pings.remove_at(i)
	# --- CTF (flags, grabs, captures). ---
	_update_ctf(delta)


func _sf_trailing_team() -> int:
	# QA-114 (v3.9): the team behind by >= 2 points is the trailing
	# team (-1 when the scores are level or within 1). Pure — from
	# _ctf_scores only, so every peer computes the same answer and
	# the HUD agrees on all phones. CTF only.
	if game_mode != 4:
		return -1
	var red := int(_ctf_scores.get(0, 0))
	var blue := int(_ctf_scores.get(1, 0))
	if red - blue >= 2:
		return 1
	if blue - red >= 2:
		return 0
	return -1


func _sf_update_comeback(delta: float) -> void:
	# QA-114 (v3.9): COMEBACK HELP — the trailing team gets a modest
	# advantage, never a guaranteed win: (1) the summit elevator
	# runs continuously while they trail (the switch normally gives
	# 30 s; the comeback tops the timer up so it never docks), and
	# (2) a bonus power-up spawns near their base every 25 s.
	# Both teams see it in the HUD, so it is never a hidden buff.
	# The leading team KEEPS its checkpoint — comeback help and
	# checkpoints do not cancel each other (opposite-feature rule).
	var trail := _sf_trailing_team()
	if trail != _sf_comeback_team:
		if trail >= 0:
			_ctf_feed("COMEBACK: %s is behind — summit elevator running + extra power-ups at their base!" % ("RED" if trail == 0 else "BLUE"), Color(1.0, 0.8, 0.2))
			_sf_comeback_pu_timer = 5.0 # first bonus arrives fast
		_sf_comeback_team = trail
	if not multiplayer.is_server() or match_over or trail < 0:
		return
	# (1) Elevator: keep the timer topped up so it never docks
	# while the comeback is active. Runs after the switch block's
	# decrement, so the top-up wins every frame.
	_sf_summit_timer = maxf(_sf_summit_timer, 5.0)
	# (2) Bonus power-up near the trailing team's base (their own
	# side only — never on a level the other team holds).
	_sf_comeback_pu_timer -= delta
	if _sf_comeback_pu_timer > 0.0:
		return
	_sf_comeback_pu_timer = 25.0
	var spot := 200 + trail
	var active := false
	for child in pickups_node.get_children():
		if int(child.get("spot_index")) == spot:
			active = true
			break
	if active:
		return
	var kind := randi_range(7, 13)
	var pos := Vector2(700, 10548) if trail == 0 else Vector2(2900, 10548)
	var pname := "sfcomeback_" + str(Time.get_ticks_msec()) + "_" + str(trail)
	rpc("spawn_pickup_remote", pos, pname, kind, spot)


func _sf_update_random_events(delta: float) -> void:
	# QA-114 (v3.9): RANDOM mid-match events — the fixed 90 s Summit
	# Storm alone is too predictable, so events fire at RANDOM times
	# (45-90 s apart) with a RANDOM type: supply drop, collapsing
	# level, or route shift. Announced to both teams in the feed.
	# Independent of the storm timer, so an event CAN coincide with
	# a storm — that combination is tested, not prevented.
	if not multiplayer.is_server() or match_over or _countdown_active:
		return
	if _sf_event_active != "":
		_sf_event_time_left -= delta
		if _sf_event_time_left <= 0.0:
			if _sf_event_active == "route_shift":
				_sf_event_wind_flip = false
				_ctf_feed("EVENT over: the wind is back to normal.", Color(0.9, 0.9, 0.9))
			_sf_event_active = ""
			_sf_event_timer = randf_range(45.0, 90.0)
		return
	if _sf_event_timer <= 0.0:
		_sf_event_timer = randf_range(45.0, 90.0)
		return
	_sf_event_timer -= delta
	if _sf_event_timer > 0.0:
		return
	match randi() % 3:
		0:
			_sf_event_supply_drop()
			_sf_event_active = "supply_drop"
			_sf_event_time_left = 1.0 # instant effect; ends next frame
		1:
			_sf_event_collapse()
			_sf_event_active = "collapse"
			_sf_event_time_left = 1.0 # the collapse runs its own 8 s cycle
		2:
			_sf_event_wind_flip = true
			_sf_event_active = "route_shift"
			_sf_event_time_left = 20.0
			_ctf_feed("EVENT: ROUTE SHIFT! The wind has reversed for 20 s!", Color(0.6, 0.9, 1.0))


func _sf_event_supply_drop() -> void:
	# A weapon or power-up drops on a random reachable platform.
	var plats: Array = MAPS[map_id].get("platforms", [])
	if plats.is_empty():
		return
	var r: Rect2 = plats[randi() % plats.size()]
	var pos := r.get_center() + Vector2(0, -60)
	var kind := randi_range(1, 6) if randi() % 2 == 0 else randi_range(7, 13)
	var pname := "sfsupply_" + str(Time.get_ticks_msec())
	# Event drops do NOT count toward the FT-SF-RARITY test — that
	# test measures the regular spawn loop only.
	rpc("spawn_pickup_remote", pos, pname, kind, -1)
	_ctf_feed("EVENT: SUPPLY DROP! Something landed on the tower — go get it!", Color(0.6, 1.0, 0.6))


func _sf_event_collapse() -> void:
	# A random bridge-level platform collapses (same 0.8 s shake ->
	# fall -> 8 s gone -> back cycle as the built-in collapsing
	# platform). Never a spawn, checkpoint, relay, extraction, or
	# summit platform — those are protected, so the event can never
	# remove a route home or a respawn.
	var plats: Array = MAPS[map_id].get("platforms", [])
	var protected: Array = []
	for sp in MAPS[map_id].get("spawns", []):
		protected.append(sp)
	for cps in MAPS[map_id].get("checkpoints", []):
		for cp in cps:
			protected.append(cp)
	for rp in MAPS[map_id].get("relay", []):
		protected.append(rp)
	var ctf: Dictionary = MAPS[map_id].get("ctf", {})
	protected.append(ctf.get("extract_red", Vector2.ZERO))
	protected.append(ctf.get("extract_blue", Vector2.ZERO))
	var candidates: Array = []
	for i in plats.size():
		var r: Rect2 = plats[i]
		if int(i) in (MAPS[map_id].get("collapsing", []) as Array): # already a built-in collapsing platform
			continue
		var safe := true
		for pp in protected:
			if absf(float(pp.y) - float(r.position.y)) < 120.0 and float(pp.x) >= float(r.position.x) - 100.0 and float(pp.x) <= float(r.end.x) + 100.0:
				safe = false
				break
		if safe:
			candidates.append(i)
	if candidates.is_empty():
		return
	var idx: int = candidates[randi() % candidates.size()]
	var rect: Rect2 = plats[idx]
	for c in _sf_collapsing:
		if int(c.get("idx", -1)) == idx:
			c["state"] = "shaking"
			c["timer"] = 0.8
			_sf_event_collapse_idx = idx
			_ctf_feed("EVENT: A LEVEL IS COLLAPSING! Watch your step!", Color(1.0, 0.6, 0.2))
			return
	_sf_collapsing.append({"idx": idx, "rect": rect, "shape": _sf_arena_shape_at(rect.get_center()), "sprites": _sf_tile_sprites_at(rect), "state": "shaking", "timer": 0.8})
	_sf_event_collapse_idx = idx
	_ctf_feed("EVENT: A LEVEL IS COLLAPSING! Watch your step!", Color(1.0, 0.6, 0.2))


func _sf_update_summit_elevator(delta: float) -> void:
	# Shuttles arena <-> summit while active: up 4 s, wait 6 s at
	# the top, down 4 s, wait 6 s at the bottom, repeat. Docked at
	# the arena when the timer runs out.
	var se: Dictionary = _sf_summit_elevator
	var body := se["body"] as AnimatableBody2D
	var cfg: Dictionary = se["cfg"]
	var y_top := float(cfg["y_top"])
	var y_bot := float(cfg["y_bottom"])
	var state: String = str(se.get("state", "docked"))
	var timer := float(se.get("timer", 0.0)) + delta
	se["timer"] = timer
	var x := float(cfg["x"]) + float(cfg.get("w", 300)) * 0.5
	match state:
		"docked":
			body.position = Vector2(x, y_bot + 24.0)
			if _sf_summit_timer > 0.0:
				se["state"] = "up"
				se["timer"] = 0.0
		"up":
			var k := clampf(timer / 4.0, 0.0, 1.0)
			body.position = Vector2(x, lerpf(y_bot, y_top, k) + 24.0)
			if timer >= 4.0:
				se["state"] = "top"
				se["timer"] = 0.0
		"top":
			body.position = Vector2(x, y_top + 24.0)
			if timer >= 6.0 or _sf_summit_timer <= 0.0:
				se["state"] = "down"
				se["timer"] = 0.0
		"down":
			var k := clampf(timer / 4.0, 0.0, 1.0)
			body.position = Vector2(x, lerpf(y_top, y_bot, k) + 24.0)
			if timer >= 4.0:
				se["state"] = "bottom"
				se["timer"] = 0.0
		"bottom":
			body.position = Vector2(x, y_bot + 24.0)
			if timer >= 6.0 or _sf_summit_timer <= 0.0:
				se["state"] = "docked" if _sf_summit_timer <= 0.0 else "up"
				se["timer"] = 0.0


func _sf_player_standing_on(rect: Rect2) -> bool:
	# Any alive player whose feet are on this platform (within
	# 8 px of its top, inside its x-range).
	for child in players_node.get_children():
		if not child.alive:
			continue
		var feet: Vector2 = child.position + Vector2(0, 31)
		if feet.x >= rect.position.x - 4.0 and feet.x <= rect.end.x + 4.0 and absf(feet.y - rect.position.y) <= 8.0:
			return true
	return false


func _sf_update_collapsing(delta: float) -> void:
	for c in _sf_collapsing:
		var state: String = str(c.get("state", "idle"))
		var rect: Rect2 = c["rect"]
		if state == "idle":
			if _sf_player_standing_on(rect):
				c["state"] = "shaking"
				c["timer"] = 0.8
		elif state == "shaking":
			# Shake the tile sprites; the shape stays solid.
			var t := float(c.get("timer", 0.0)) - delta
			c["timer"] = t
			var off := sin(t * 40.0) * 3.0
			for s in c["sprites"]:
				(s as Sprite2D).offset = Vector2(off, 0)
			if t <= 0.0:
				c["state"] = "falling"
				c["timer"] = 0.6
				if c["shape"] != null:
					(c["shape"] as CollisionShape2D).set_deferred("disabled", true)
		elif state == "falling":
			var t := float(c.get("timer", 0.0)) - delta
			c["timer"] = t
			for s in c["sprites"]:
				(s as Sprite2D).modulate.a = maxf(0.0, t / 0.6)
				(s as Sprite2D).offset = Vector2(0, (0.6 - t) * 120.0)
			if t <= 0.0:
				c["state"] = "gone"
				c["timer"] = 8.0
				for s in c["sprites"]:
					(s as Sprite2D).visible = false
		elif state == "gone":
			var t := float(c.get("timer", 0.0)) - delta
			c["timer"] = t
			if t <= 0.0:
				c["state"] = "idle"
				if c["shape"] != null:
					(c["shape"] as CollisionShape2D).set_deferred("disabled", false)
				for s in c["sprites"]:
					(s as Sprite2D).visible = true
					(s as Sprite2D).modulate.a = 1.0
					(s as Sprite2D).offset = Vector2.ZERO


func _sf_update_trapdoors(delta: float) -> void:
	for td in _sf_trapdoors:
		var state: String = str(td.get("state", "closed"))
		var rect: Rect2 = td["rect"]
		if state == "closed":
			if _sf_player_standing_on(rect):
				var t := float(td.get("timer", 0.0)) + delta
				td["timer"] = t
				if t >= 1.0:
					td["state"] = "open"
					td["timer"] = 5.0
					if td["shape"] != null:
						(td["shape"] as CollisionShape2D).set_deferred("disabled", true)
					for s in td["sprites"]:
						(s as Sprite2D).texture = SF_TEX_TRAPDOOR_OPEN
			else:
				td["timer"] = 0.0
		elif state == "open":
			var t := float(td.get("timer", 0.0)) - delta
			td["timer"] = t
			if t <= 0.0:
				td["state"] = "closed"
				td["timer"] = 0.0
				if td["shape"] != null:
					(td["shape"] as CollisionShape2D).set_deferred("disabled", false)
				for s in td["sprites"]:
					(s as Sprite2D).texture = SF_TEX_TRAPDOOR_CLOSED


func _sf_update_rocks(delta: float) -> void:
	# Host spawns a rock every 4 s (max 3 falling); every peer
	# simulates the same fall (gravity + land on the first
	# platform below). Host-only damage on impact with a player.
	if multiplayer.is_server() and not match_over and not _countdown_active:
		_sf_rock_timer -= delta
		if _sf_rock_timer <= 0.0:
			_sf_rock_timer = float(MAPS[map_id].get("rocks", {}).get("interval", 4.0))
			var active := 0
			for r in _sf_rocks:
				if not bool(r.get("landed", false)):
					active += 1
			var rocks: Dictionary = MAPS[map_id].get("rocks", {})
			if active < int(rocks.get("max", 3)):
				var rx := randf_range(float(rocks.get("x_min", 1000)), float(rocks.get("x_max", 2600)))
				rpc("sf_rock_remote", rx)
	for i in range(_sf_rocks.size() - 1, -1, -1):
		var r: Dictionary = _sf_rocks[i]
		var node: Node2D = r["node"]
		if node == null or not is_instance_valid(node):
			_sf_rocks.remove_at(i)
			continue
		if bool(r.get("landed", false)):
			var ft := float(r.get("fade", 0.0)) - delta
			r["fade"] = ft
			(node as Sprite2D).modulate.a = maxf(0.0, ft)
			if ft <= 0.0:
				node.queue_free()
				_sf_rocks.remove_at(i)
			continue
		var vel := float(r.get("vel", 0.0)) + 1400.0 * delta
		r["vel"] = vel
		var prev_y: float = node.position.y
		node.position.y += vel * delta
		node.rotation += 3.0 * delta
		# Land on the first platform top crossed this frame.
		var landed := false
		for p in MAPS[map_id]["platforms"]:
			var pr: Rect2 = p
			if node.position.x >= pr.position.x and node.position.x <= pr.end.x and prev_y + 30.0 <= pr.position.y and node.position.y + 30.0 >= pr.position.y:
				node.position.y = pr.position.y - 30.0
				node.rotation = 0.0
				r["landed"] = true
				r["fade"] = 1.0
				landed = true
				break
		if landed:
			_sf_free_rock_marker(r)
			_sf_play_hazard_sound("rock_impact", node.position, 1100.0)
			continue
		# Host-only: 25 damage + knockback on a player hit mid-fall.
		if multiplayer.is_server() and not match_over:
			for child in players_node.get_children():
				if not child.alive:
					continue
				var box := Rect2(child.position - Vector2(20, 31), Vector2(40, 62))
				var rock_box := Rect2(node.position - Vector2(30, 30), Vector2(60, 60))
				if box.intersects(rock_box):
					if child.get_multiplayer_authority() == multiplayer.get_unique_id():
						child.take_damage(25, 0)
					elif multiplayer.get_peers().has(child.get_multiplayer_authority()):
						child.rpc_id(child.get_multiplayer_authority(), "take_damage", 25, 0)
					_sf_free_rock_marker(r)
					_sf_play_hazard_sound("rock_impact", node.position, 1100.0)
					node.queue_free()
					_sf_rocks.remove_at(i)
					break


func _sf_free_rock_marker(r: Dictionary) -> void:
	var m: Node = r.get("marker")
	if m != null and is_instance_valid(m):
		m.queue_free()
	r["marker"] = null


@rpc("any_peer", "call_local")
func sf_rock_remote(x: float) -> void:
	var rocks: Dictionary = MAPS[map_id].get("rocks", {})
	var node := Sprite2D.new()
	node.texture = SF_TEX_ROCK
	node.scale = Vector2(0.6, 0.6)
	node.position = Vector2(x, float(rocks.get("y_top", 9050)))
	node.z_index = 3
	add_child(node)
	# QA-129 (v3.11): landing warning — a ground-crack marker on
	# the first platform below the spawn x, so the impact point is
	# telegraphed from the moment the rock appears (0.5-1.5 s of
	# warning depending on the drop). Freed when the rock lands.
	var marker: Sprite2D = null
	var land_y := -1.0
	for p in MAPS[map_id]["platforms"]:
		var pr: Rect2 = p
		# Nearest platform below the spawn (smallest top y above
		# y_top) — the array runs bottom-to-top, so take the min.
		if x >= pr.position.x and x <= pr.end.x and pr.position.y > float(rocks.get("y_top", 9050)) and (land_y < 0.0 or pr.position.y < land_y):
			land_y = pr.position.y
	if land_y > 0.0:
		marker = Sprite2D.new()
		marker.texture = FX_TEX_CRACK
		marker.position = Vector2(x, land_y - 6)
		marker.scale = Vector2(0.5, 0.5)
		marker.modulate = Color(1, 0.5, 0.3, 0.85)
		marker.z_index = 2
		add_child(marker)
	_sf_rocks.append({"node": node, "vel": 0.0, "landed": false, "fade": 0.0, "marker": marker})


func _sf_update_storm(delta: float) -> void:
	# Summit Storm every 90 s: lightning strikes the summit for
	# 10 s (telegraphs + damage + rumble). Driven by the match
	# clock, so every peer agrees with no RPC.
	# QA-132: the storm NO LONGER disables platforms — the two
	# L6 side perches went visible-but-unlandable for 10 s every
	# storm (user report), so the disable mechanic is deleted;
	# the perches stay landable through every storm.
	if match_over or _countdown_active:
		return
	if _sf_storm_active:
		_sf_storm_time_left -= delta
		# Lightning flicker while the storm runs.
		for n in _sf_storm_nodes:
			(n as Sprite2D).modulate.a = 0.5 + 0.5 * sin(_sf_match_time * 9.0 + float((n as Sprite2D).position.x))
		# QA-126 (v3.11): LIGHTNING STRIKES — every 3 s a bolt is
		# telegraphed (ground ring + bolt sprite, 0.6 s warning) at
		# a random player in the top two levels (L5/L6, y < 3600),
		# then hits for 15 damage if they are still within 200 px
		# of the marker — step away and it misses. Host picks the
		# target; the marker is local (every peer sees the same
		# match clock, so the strike schedule agrees).
		_sf_update_strike(delta)
		if _sf_storm_time_left <= 0.0:
			_sf_storm_active = false
			_sf_storm_timer = 90.0
			_sf_clear_strike_marker() # never leave a telegraph hanging
			_sf_strike_timer = 3.0
			for n in _sf_storm_nodes:
				(n as Sprite2D).visible = false
			_ctf_feed("The storm has passed.", Color(0.8, 0.85, 1.0))
		return
	_sf_storm_timer -= delta
	if _sf_storm_timer <= 0.0:
		_sf_storm_active = true
		_sf_storm_time_left = 10.0
		if _sf_storm_nodes.is_empty():
			for lx in [900, 1800, 2700]:
				var bolt := Sprite2D.new()
				bolt.texture = SF_TEX_LIGHTNING
				bolt.position = Vector2(lx, 500)
				bolt.z_index = 4
				add_child(bolt)
				_sf_storm_nodes.append(bolt)
		for n in _sf_storm_nodes:
			(n as Sprite2D).visible = true
		_ctf_feed("SUMMIT STORM! Lightning strikes the summit!", Color(0.65, 0.8, 1.0))
		# QA-126 (v3.11): storm rumble once per storm (map-wide event).
		if audio != null:
			audio.play("storm")


func _sf_update_strike(delta: float) -> void:
	# QA-126 (v3.11): one lightning strike every 3 s while the storm
	# runs. Two phases: TELEGRAPH (0.6 s — red ground ring + bolt
	# sprite at the target's feet) then HIT (15 damage if the target
	# is still within 200 px, else a miss). The shield absorbs the
	# hit (take_damage), the victim flashes + shakes, and a
	# shockwave ring blooms at the strike point.
	if not _sf_strike.is_empty():
		var t := float(_sf_strike.get("timer", 0.0)) - delta
		_sf_strike["timer"] = t
		if t <= 0.0:
			var pos: Vector2 = _sf_strike["pos"]
			var peer: int = int(_sf_strike.get("peer", -1))
			_sf_clear_strike_marker()
			if multiplayer.is_server() and peer >= 0:
				for child in players_node.get_children():
					if not child.alive:
						continue
					if int(child.get_multiplayer_authority()) != peer:
						continue
					if child.position.distance_to(pos) <= 200.0:
						_sf_damage_player(child, 15)
					break
			_sf_spawn_shockwave(pos)
			_sf_play_hazard_sound("thunder", pos, 1400.0)
			if _sf_scenery.get("flash") != null:
				_sf_scenery["flash_alpha"] = 0.15
		return
	_sf_strike_timer -= delta
	if _sf_strike_timer > 0.0:
		return
	_sf_strike_timer = 3.0
	var cands: Array = []
	for child in players_node.get_children():
		if child.alive and child.position.y < 3600.0:
			cands.append(child)
	var pos := Vector2.ZERO
	var peer := -1
	if not cands.is_empty():
		var target: Node = cands[randi() % cands.size()]
		pos = target.position + Vector2(0, 31)
		peer = int(target.get_multiplayer_authority())
	else:
		# Nobody up top: strike a random summit platform (visual only).
		var plats: Array = MAPS[map_id].get("platforms", [])
		var r: Rect2 = plats[randi() % plats.size()]
		if r.position.y > 1800.0:
			r = plats[52] # QA-132: summit floor (was plats[67] in the 98-list)
		pos = r.get_center() + Vector2(0, -24)
	var ring := Line2D.new()
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.25, 0.2, 0.9)
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(pos + Vector2(cos(a), sin(a)) * 60.0)
	pts.append(pos + Vector2(60.0, 0))
	ring.points = pts
	ring.z_index = 4
	add_child(ring)
	var bolt := Sprite2D.new()
	bolt.texture = FX_TEX_BOLT if randi() % 2 == 0 else FX_TEX_FORKED
	bolt.position = pos + Vector2(0, -120)
	bolt.scale = Vector2(0.7, 0.7)
	bolt.modulate = Color(1, 1, 1, 0.9)
	bolt.z_index = 4
	add_child(bolt)
	_sf_strike = {"peer": peer, "pos": pos, "ring": ring, "bolt": bolt, "timer": 0.6}


func _sf_clear_strike_marker() -> void:
	if _sf_strike.is_empty():
		return
	for k in ["ring", "bolt"]:
		var n: Node = _sf_strike.get(k)
		if n != null and is_instance_valid(n):
			n.queue_free()
	_sf_strike = {}


func _sf_update_strike_l4(delta: float) -> void:
	# QA-135 (v3.13): L4 storm lightning — same strike shape as
	# the Summit Storm (0.6 s telegraph: red ground ring + bolt
	# sprite, then 15 damage if the target is still within 200 px
	# — step away and it misses; shield absorbs it), but its own
	# cadence (one bolt every 6 s) and its own zone (a random
	# living player in L4, y 3600-5400). Runs all match, not only
	# during a storm. Host picks the target; the marker is local
	# (every peer sees the same match clock, so the strike
	# schedule agrees). No player in L4: no strike that cycle.
	if match_over or _countdown_active:
		return
	if not _sf_strike_l4.is_empty():
		var t := float(_sf_strike_l4.get("timer", 0.0)) - delta
		_sf_strike_l4["timer"] = t
		if t <= 0.0:
			var pos: Vector2 = _sf_strike_l4["pos"]
			var peer: int = int(_sf_strike_l4.get("peer", -1))
			_sf_clear_strike_l4_marker()
			if multiplayer.is_server() and peer >= 0:
				for child in players_node.get_children():
					if not child.alive:
						continue
					if int(child.get_multiplayer_authority()) != peer:
						continue
					if child.position.distance_to(pos) <= 200.0:
						_sf_damage_player(child, 15)
					break
			_sf_spawn_shockwave(pos)
			_sf_play_hazard_sound("thunder", pos, 1400.0)
			if _sf_scenery.get("flash") != null:
				_sf_scenery["flash_alpha"] = 0.15
		return
	_sf_strike_l4_timer -= delta
	if _sf_strike_l4_timer > 0.0:
		return
	_sf_strike_l4_timer = 6.0
	var cands: Array = []
	for child in players_node.get_children():
		if child.alive and child.position.y >= 3600.0 and child.position.y < 5400.0:
			cands.append(child)
	if cands.is_empty():
		return
	var target: Node = cands[randi() % cands.size()]
	var pos: Vector2 = target.position + Vector2(0, 31)
	var peer := int(target.get_multiplayer_authority())
	var ring := Line2D.new()
	ring.width = 5.0
	ring.default_color = Color(1.0, 0.25, 0.2, 0.9)
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(pos + Vector2(cos(a), sin(a)) * 60.0)
	pts.append(pos + Vector2(60.0, 0))
	ring.points = pts
	ring.z_index = 4
	add_child(ring)
	var bolt := Sprite2D.new()
	bolt.texture = FX_TEX_BOLT if randi() % 2 == 0 else FX_TEX_FORKED
	bolt.position = pos + Vector2(0, -120)
	bolt.scale = Vector2(0.7, 0.7)
	bolt.modulate = Color(1, 1, 1, 0.9)
	bolt.z_index = 4
	add_child(bolt)
	_sf_strike_l4 = {"peer": peer, "pos": pos, "ring": ring, "bolt": bolt, "timer": 0.6}


func _sf_clear_strike_l4_marker() -> void:
	if _sf_strike_l4.is_empty():
		return
	for k in ["ring", "bolt"]:
		var n: Node = _sf_strike_l4.get(k)
		if n != null and is_instance_valid(n):
			n.queue_free()
	_sf_strike_l4 = {}


@rpc("any_peer", "call_local")
func show_wind_tornado_fx(pos: Vector2) -> void:
	# QA-135 (v3.13): Wind Blast tornado — a code-drawn funnel
	# (stacked ellipses, wide top -> narrow base) + a dust ring
	# at the base. Spins for ~1 s (the 0.7 s sweep + the throw),
	# then fades. The host RPCs it, so every peer sees the same
	# tornado at the same spot. Sender guard: only the host
	# (id 1, or 0 in a local sim) may trigger it.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	audio.play("wind")
	if _wind_tornado_node != null and is_instance_valid(_wind_tornado_node):
		_wind_tornado_node.queue_free()
	var n := Node2D.new()
	n.position = pos + Vector2(0, -20)
	n.z_index = 6
	add_child(n)
	var radii := [70.0, 55.0, 38.0, 22.0]
	var offs := [-95.0, -55.0, -15.0, 25.0]
	for i in radii.size():
		var e := Polygon2D.new()
		var pts := PackedVector2Array()
		for k in 20:
			var a := TAU * float(k) / 20.0
			pts.append(Vector2(cos(a) * radii[i], sin(a) * radii[i] * 0.45))
		e.polygon = pts
		e.color = Color(0.92, 0.93, 0.96, 0.5)
		e.position = Vector2(0, offs[i])
		n.add_child(e)
	var dust := Sprite2D.new()
	dust.texture = FX_TEX_DUST
	dust.position = Vector2(0, 30)
	dust.scale = Vector2(0.9, 0.9)
	dust.modulate = Color(1, 1, 1, 0.55)
	n.add_child(dust)
	_wind_tornado_node = n
	var tw := create_tween()
	tw.tween_property(n, "rotation", TAU, 0.55)
	tw.tween_property(n, "rotation", TAU * 2.0, 0.45)
	tw.tween_property(n, "modulate:a", 0.0, 0.2)
	tw.tween_callback(n.queue_free)
	tw.tween_callback(_clear_wind_tornado_node.bind(n))


func _clear_wind_tornado_node(n: Node2D) -> void:
	# QA-135: the tornado frees itself after the fade — clear the
	# reference, or it dangles and any later typed read of it
	# errors ("Trying to assign invalid previously freed
	# instance"). Only clears if it still points at THIS tornado
	# (a newer tornado may have replaced it).
	if _wind_tornado_node == n:
		_wind_tornado_node = null


@rpc("any_peer", "call_local")
func show_thunder_strike_fx(pos: Vector2) -> void:
	# QA-119 (v3.11): Thunder Strike bolt — the host RPCs it, so
	# every peer sees the same strike at the same spot and hears
	# the crack once. Sender guard: only the host (id 1, or 0 in a
	# local sim) may trigger it.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	audio.play("thunder")
	var bolt := Sprite2D.new()
	bolt.texture = FX_TEX_THUNDER
	bolt.position = pos
	bolt.scale = Vector2(0.55, 0.55)
	bolt.z_index = 6
	add_child(bolt)
	var tw := create_tween()
	tw.tween_property(bolt, "scale", Vector2(0.75, 0.75), 0.15)
	tw.tween_property(bolt, "modulate:a", 0.0, 0.45)
	tw.tween_callback(bolt.queue_free)


func _sf_spawn_shockwave(pos: Vector2) -> void:
	# One-shot expanding ring (fades in _update_skyfall_scenery).
	var sw := Sprite2D.new()
	sw.texture = FX_TEX_SHOCKWAVE
	sw.position = pos
	sw.scale = Vector2(0.3, 0.3)
	sw.modulate = Color(1, 1, 1, 0.9)
	sw.z_index = 4
	add_child(sw)
	var shots: Array = _sf_scenery.get("one_shots", [])
	shots.append({"node": sw, "t": 0.0})
	_sf_scenery["one_shots"] = shots


func _sf_update_hazards(delta: float) -> void:
	# QA-126 (v3.11): lava / fire hazard zones deal damage — 10 HP
	# per 1 s tick while a player stands in the zone, and ONLY while
	# the jets are HOT (2 s on / 2 s off per 4 s cycle — the flame
	# sprite shows the phase, so the danger is always telegraphed).
	# Fair: no one-hit kills (10 HP/tick, walk out between ticks),
	# the shield blocks it (take_damage), and the health regen
	# restarts from the hit. Host-only damage; visuals are pure
	# functions of the match clock so every peer agrees.
	for h in _sf_hazard_fx:
		var hd: Dictionary = h
		var cycle := float(hd.get("cycle", 4.0))
		var hot := fmod(_sf_match_time, cycle) < cycle * 0.5
		var flame: Sprite2D = hd["flame"]
		if flame != null:
			flame.visible = hot
			if hot:
				var pulse := 0.55 + 0.15 * sin(_sf_match_time * 9.0)
				flame.scale.y = pulse
		var magma: Sprite2D = hd.get("magma")
		if magma != null:
			magma.visible = hot
			if hot:
				var k := fmod(_sf_match_time, cycle) / (cycle * 0.5)
				magma.scale = Vector2(0.5 + k * 0.7, 0.5 + k * 0.7)
				magma.modulate.a = 0.85 * (1.0 - k * 0.6)
		if not hot:
			continue
		if not multiplayer.is_server() or match_over:
			continue
		var r: Rect2 = hd["rect"]
		for child in players_node.get_children():
			if not child.alive:
				continue
			var box := Rect2(child.position - Vector2(20, 31), Vector2(40, 62))
			if not box.intersects(r):
				continue
			var pid := int(child.get_multiplayer_authority())
			var tick := float(_sf_hazard_tick.get(pid, 0.0)) - delta
			_sf_hazard_tick[pid] = tick
			if tick <= 0.0:
				_sf_hazard_tick[pid] = 1.0
				_sf_damage_player(child, 10)
				_sf_play_hazard_sound("fire_burn", child.position, 900.0)


# --- Skyfall power-ups: RARER than weapons (user rule, 2026-11-20).
# Weapons: 6 spots, 14 s respawn, max 3 active, 3 at match start.
# Power-ups (QA-132): 7 spots (one per kind), 30 s respawn, max 4
# active (was 2), 3 at match start spread across the heights (was
# 1 random spot) — low L1, mid L3, high L6 — and a 30 s pickup
# lifetime (was 20 s, see pickup.gd). The respawn was 15 s in the
# first QA-132 pass, but the FT-SF-RARITY sim then counted MORE
# power-ups than weapons in 300 s (106 vs 93) — the loop spawns
# one per frame up to the active cap, so a 15 s cooldown refills
# the cap every clear-window. At 30 s the spots re-arm staggered
# (~60 in the sim) while a real match still keeps up to 4 on the
# tower at once — a climbing player still meets a power-up about
# every level instead of almost never seeing one.
# ---------------------------------------------------------------------------
const SF_POWERUP_COOLDOWN := 30.0
const SF_POWERUP_MAX_ACTIVE := 4
# Match-start spread: one low (spot 0, Health, L1), one mid
# (spot 4, Thunder, L3), one high (spot 6, Speed, L6).
const SF_POWERUP_INITIAL_SPOTS: Array[int] = [0, 4, 6]

func _update_skyfall_powerups(delta: float) -> void:
	if map_id != GameData.SKYFALL_MAP_ID:
		return
	if not multiplayer.is_server() or match_over:
		return
	var spots: Array = MAPS[map_id].get("skyfall_pickups", [])
	if spots.is_empty():
		return
	if not _sf_initial_powerups_done:
		_sf_initial_powerups_done = true
		for si in SF_POWERUP_INITIAL_SPOTS:
			_spawn_skyfall_powerup(si)
		for i in spots.size():
			_sf_pickup_timers[i] = SF_POWERUP_COOLDOWN
		return
	var active := 0
	for child in pickups_node.get_children():
		if int(child.get("kind")) >= 7:
			active += 1
	if active >= SF_POWERUP_MAX_ACTIVE:
		return
	for i in spots.size():
		var t := float(_sf_pickup_timers.get(i, 0.0)) - delta
		_sf_pickup_timers[i] = t
		if t <= 0.0:
			_sf_pickup_timers[i] = SF_POWERUP_COOLDOWN
			_spawn_skyfall_powerup(i)
			return # one spawn per frame at most


func _spawn_skyfall_powerup(spot_idx: int) -> void:
	var spots: Array = MAPS[map_id].get("skyfall_pickups", [])
	if spot_idx < 0 or spot_idx >= spots.size():
		return
	var spot: Array = spots[spot_idx]
	var pos := Vector2(float(spot[0]), float(spot[1]))
	var kind := int(spot[2])
	var pname := "sfpowerup_" + str(Time.get_ticks_msec()) + "_" + str(spot_idx)
	# Spot index 100+ keeps power-ups out of the standard weapon
	# spot timers (on_pickup_gone routes 100+ to the power-up timer).
	_test_powerup_spawns += 1
	rpc("spawn_pickup_remote", pos, pname, kind, 100 + spot_idx)


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
		# QA-072 (terrain depth): a dark 16 px skirt under each
		# platform so the battlefield reads as solid ground, not a
		# floating dash. 16 px is far less than the >=122 px level
		# clearance, so it never touches anything below.
		var skirt := Polygon2D.new()
		skirt.polygon = PackedVector2Array([
			Vector2(r.position.x, r.position.y + r.size.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y),
			Vector2(r.position.x + r.size.x, r.position.y + r.size.y + 16.0),
			Vector2(r.position.x, r.position.y + r.size.y + 16.0)])
		skirt.color = Color(0, 0, 0, 0.25)
		add_child(skirt)


# ---------------------------------------------------------------------------
# QA-112 (v3.9) — SKYFALL builders + Vertical CTF + mechanics.
# Everything here is a no-op unless the loaded map has "skyfall".
# Moving platforms use AnimatableBody2D (sync_to_physics carries
# players standing on them); static platform shapes are found by
# position in the Arena body so _build_arena stays untouched.
# ---------------------------------------------------------------------------

func _build_skyfall(map: Dictionary) -> void:
	if not bool(map.get("skyfall", false)):
		return
	# QA-123 (v3.11): L2 Underground Tunnels: a dark band over the
	# tunnel level (y 7200-9000) so the corridor reads as a tunnel,
	# not open sky. Drawn here (behind the players, z -2).
	# QA-134 (v3.13): the lamp dots (small warm circles along the
	# tunnel floors) are REMOVED — the user asked for no yellow
	# circles. The dark tunnel band stays.
	var band := Polygon2D.new()
	band.polygon = PackedVector2Array([Vector2(0, 7200), Vector2(map_size.x, 7200), Vector2(map_size.x, 9000), Vector2(0, 9000)])
	band.color = Color(0.02, 0.02, 0.04, 0.45)
	band.z_index = -2
	add_child(band)
	# Summit roof: a red triangle over the gate + two dark pillars
	# flanking it, so the summit reads as a gatehouse. The pack has
	# no standalone summit building (ASSET_AUDIT.md §9) — this is
	# code-drawn from the gate + wall art, not a pasted strip.
	var roof := Polygon2D.new()
	roof.polygon = PackedVector2Array([Vector2(1660, 478), Vector2(1940, 478), Vector2(1800, 380)])
	roof.color = Color(0.62, 0.12, 0.12)
	roof.z_index = -1
	add_child(roof)
	for px in [1690, 1890]:
		var pillar := Polygon2D.new()
		pillar.polygon = PackedVector2Array([Vector2(px, 478), Vector2(px + 20, 478), Vector2(px + 20, 862), Vector2(px, 862)])
		pillar.color = Color(0.16, 0.16, 0.20)
		pillar.z_index = -1
		add_child(pillar)
	# Wind-zone overlays (faint, so the square edge barely shows).
	for w in map.get("wind", []):
		var wr: Rect2 = w["rect"]
		var ov := Sprite2D.new()
		ov.texture = SF_TEX_WIND
		ov.position = wr.get_center()
		ov.scale = Vector2(wr.size.x / 384.0, wr.size.y / 384.0)
		ov.modulate = Color(1, 1, 1, 0.55)
		ov.z_index = -1
		add_child(ov)
	# Extraction-zone rings at the bases (pulse in _update_skyfall).
	var ctf: Dictionary = map.get("ctf", {})
	for team in [0, 1]:
		var zpos: Vector2 = ctf.get("extract_red" if team == 0 else "extract_blue", Vector2.ZERO)
		var zspr := Sprite2D.new()
		zspr.texture = SF_TEX_ZONE_RED if team == 0 else SF_TEX_ZONE_BLUE
		zspr.position = zpos + Vector2(0, -10)
		zspr.scale = Vector2(0.9, 0.9)
		zspr.z_index = 1
		add_child(zspr)
		_ctf_extract_nodes.append(zspr)
	# QA-114 (v3.9): relay stations — gold rings (radius = the 140 px
	# bank radius, so the zone is exactly what you see) + a label.
	for ri in (map.get("relay", []) as Array).size():
		var rp: Vector2 = (map.get("relay", []) as Array)[ri]
		var ring := Line2D.new()
		ring.width = 6.0
		ring.default_color = Color(1.0, 0.8, 0.2)
		var pts := PackedVector2Array()
		for i in 32:
			var a := TAU * float(i) / 32.0
			pts.append(rp + Vector2(cos(a), sin(a)) * 140.0)
		pts.append(rp + Vector2(140.0, 0))
		ring.points = pts
		ring.z_index = 1
		add_child(ring)
		var rlbl := Label.new()
		rlbl.text = "RELAY L%d  •  +1 pt" % [3 if ri == 0 else 6]
		# QA-114: below the ring, not above — above puts the label
		# in the top UI band (it collided with the "Waiting for
		# other players" message in the L4 screenshot).
		rlbl.position = rp + Vector2(-80, 60)
		rlbl.add_theme_font_size_override("font_size", 24)
		rlbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		rlbl.z_index = 1
		add_child(rlbl)
	# QA-114 (v3.9): grapple points — gold ring, so a player can
	# spot them while climbing. QA-134 (v3.13): the solid yellow
	# centre dot is REMOVED (user: no yellow circles) — the thin
	# gold ring stays so the spot is still findable, and the
	# grapple mechanic itself is unchanged.
	for gp in map.get("grapple", []):
		var gpos: Vector2 = gp
		var gring := Line2D.new()
		gring.width = 4.0
		gring.default_color = Color(1.0, 0.85, 0.3)
		var gpts := PackedVector2Array()
		for i in 20:
			var a := TAU * float(i) / 20.0
			gpts.append(gpos + Vector2(cos(a), sin(a)) * 26.0)
		gpts.append(gpos + Vector2(26.0, 0))
		gring.points = gpts
		gring.z_index = 1
		add_child(gring)
	# QA-114 (v3.9): jetpack lines — QA-134 (v3.13): the bright
	# cyan guide lines through the wind zones and their
	# up-chevrons are REMOVED entirely (user: no blue lines or
	# arrows). The wind zones and the jetpack stay working, just
	# unmarked. The map data "jetpack_lines" is KEPT (FT-SF-MAP
	# asserts size == 2); only the drawing is deleted.
	# QA-114 (v3.9): colour-coded routes — every platform gets a
	# small strip in its route colour (WEST cyan / CENTRE gold /
	# EAST green, by x-centre). Same colours on the HUD height bar.
	var plats: Array = map.get("platforms", [])
	for pr in plats:
		var prect: Rect2 = pr
		var route := skyfall_route_of(prect.get_center().x)
		var strip := Polygon2D.new()
		var sx := prect.position.x
		var sy := prect.position.y
		strip.polygon = PackedVector2Array([Vector2(sx, sy - 6), Vector2(sx + 60, sy - 6), Vector2(sx + 60, sy), Vector2(sx, sy)])
		strip.color = SF_ROUTE_COLORS[route]
		strip.z_index = 1
		add_child(strip)
	# QA-115 (v3.9): dynamic scenery — the map must feel alive, not
	# a still picture. Scenery only, no gameplay effect.
	_build_skyfall_scenery(map)
	# QA-124 (v3.11): per-level themes — backdrop image + lighting +
	# mid silhouette + platform tint, one distinct look per level.
	_build_skyfall_themes(map)
	# QA-129 (v3.11): per-level weather/mood + ambient life.
	_build_skyfall_weather(map)
	# QA-126 (v3.11): hazard visuals (lava pool, fire jets) — the
	# damage itself runs in _sf_update_hazards.
	_build_skyfall_hazards(map)
	_build_skyfall_movers(map)
	_build_skyfall_gate(map)
	_build_skyfall_switch(map)
	_build_skyfall_barricades(map)
	_build_skyfall_platform_refs(map)
	_build_ctf_flags()


func _sf_arena_shape_at(center: Vector2) -> CollisionShape2D:
	# The Arena StaticBody2D's shapes are positioned at their rect
	# centres — find one by position (within 1 px).
	var arena := get_node_or_null("Arena")
	if arena == null:
		return null
	for child in arena.get_children():
		if child is CollisionShape2D and (child as CollisionShape2D).position.distance_to(center) < 1.0:
			return child as CollisionShape2D
	return null


func _sf_tile_sprites_at(rect: Rect2) -> Array:
	# _draw_tiles adds one sprite per 512 px of platform, as a child
	# of the game, at (rect.x + k*512, rect.y). Collect them.
	var out: Array = []
	for child in get_children():
		if child is Sprite2D and absf((child as Sprite2D).position.y - rect.position.y) < 0.5 and (child as Sprite2D).position.x >= rect.position.x - 0.5 and (child as Sprite2D).position.x < rect.end.x:
			out.append(child)
	return out


func _build_skyfall_scenery(map: Dictionary) -> void:
	# QA-115 (v3.9): DYNAMIC SCENERY — drifting clouds, a flowing
	# waterfall, a helicopter crossing the sky, and distant
	# lightning flashes during the storm. All code-drawn (the pack
	# has no art for these) and all scenery-only: no collision, no
	# gameplay effect, ~20 nodes of cheap transforms (no per-frame
	# allocations), so phones are unaffected. The colours stay muted
	# so the routes stay readable. QA-132: the gears and steam
	# puffs are deleted (they read as solid platforms/circles).
	var clouds: Array = []
	for ci in 5:
		var cloud := Node2D.new()
		cloud.position = Vector2(float(ci) * 700.0 + 200.0, 600.0 + float(ci) * 1900.0)
		cloud.z_index = -2
		add_child(cloud)
		for bi in 3:
			var blob := Polygon2D.new()
			var pts := PackedVector2Array()
			for i in 16:
				var a := TAU * float(i) / 16.0
				pts.append(Vector2(cos(a) * (90.0 + float(bi) * 30.0), sin(a) * 28.0))
			blob.polygon = pts
			blob.color = Color(0.85, 0.88, 0.95, 0.10)
			blob.position = Vector2(float(bi) * 110.0 - 110.0, float(bi % 2) * 14.0)
			cloud.add_child(blob)
		clouds.append({"node": cloud, "speed": 12.0 + float(ci) * 4.0})
	# Waterfall on the left cliff face (Broken Cliffs, new L1,
	# y 9300-10500): a translucent sheet + 5 white streaks that
	# scroll downward.
	var fall := Polygon2D.new()
	fall.polygon = PackedVector2Array([Vector2(250, 9300), Vector2(330, 9300), Vector2(330, 10500), Vector2(250, 10500)])
	fall.color = Color(0.55, 0.75, 0.95, 0.30)
	fall.z_index = -1
	add_child(fall)
	var streaks: Array = []
	for si in 5:
		var st := Line2D.new()
		st.width = 3.0
		st.default_color = Color(1, 1, 1, 0.55)
		st.points = PackedVector2Array([Vector2(258 + float(si) * 14.0, 9350), Vector2(258 + float(si) * 14.0, 9450)])
		st.z_index = -1
		add_child(st)
		streaks.append(st)
	# Helicopter silhouette crossing the sky above the summit.
	var heli := Node2D.new()
	heli.position = Vector2(-200, 520)
	heli.z_index = -2
	add_child(heli)
	var hbody := Polygon2D.new()
	hbody.polygon = PackedVector2Array([Vector2(-40, 0), Vector2(30, -12), Vector2(60, 0), Vector2(30, 12), Vector2(-40, 10)])
	hbody.color = Color(0.08, 0.08, 0.10, 0.85)
	heli.add_child(hbody)
	var htail := Polygon2D.new()
	htail.polygon = PackedVector2Array([Vector2(-40, -4), Vector2(-95, -14), Vector2(-95, -6), Vector2(-40, 4)])
	htail.color = Color(0.08, 0.08, 0.10, 0.85)
	heli.add_child(htail)
	var hrotor := Line2D.new()
	hrotor.width = 3.0
	hrotor.default_color = Color(0.08, 0.08, 0.10, 0.85)
	hrotor.points = PackedVector2Array([Vector2(-70, -18), Vector2(70, -18)])
	heli.add_child(hrotor)
	# QA-132: the rotating gears are GONE (user report — toothed
	# circles that looked solid but had no collision) and the
	# steam puffs are GONE (same reason — circles you cannot land
	# on). The waterfall, helicopter and lightning flash stay.
	# Distant lightning flash: a full-map white sheet, invisible
	# until a storm flash fires (see _update_skyfall_scenery).
	var flash := Polygon2D.new()
	flash.polygon = PackedVector2Array([Vector2(0, 0), Vector2(3400, 0), Vector2(3400, 10800), Vector2(0, 10800)])
	flash.color = Color(1, 1, 1, 0.0)
	flash.z_index = -2
	add_child(flash)
	_sf_scenery = {"clouds": clouds, "streaks": streaks, "heli": heli, "flash": flash, "flash_timer": 3.0, "flash_alpha": 0.0}


func _update_skyfall_scenery(delta: float) -> void:
	# QA-115 (v3.9): animate the scenery — all cheap transforms,
	# no allocations, no gameplay reads. Runs on every peer (pure
	# functions of _sf_match_time + delta), so all phones agree.
	if _sf_scenery.is_empty():
		return
	for c in _sf_scenery.get("clouds", []):
		var node: Node2D = c["node"]
		node.position.x += float(c["speed"]) * delta
		if node.position.x > 3800.0:
			node.position.x = -400.0
	for st in _sf_scenery.get("streaks", []):
		var line := st as Line2D
		var pts: PackedVector2Array = line.points
		pts[0].y += 140.0 * delta
		pts[1].y += 140.0 * delta
		if pts[0].y > 10480.0:
			pts[0].y = 9320.0
			pts[1].y = 9420.0
		line.points = pts
	var heli: Node2D = _sf_scenery.get("heli")
	if heli != null:
		heli.position.x += 55.0 * delta
		if heli.position.x > 3800.0:
			heli.position.x = -200.0
			heli.position.y = 420.0 + randf() * 300.0
	# Distant lightning: only during the Summit Storm, at random
	# 2-5 s gaps — a brief pale flash over the sky.
	if _sf_storm_active:
		_sf_scenery["flash_timer"] = float(_sf_scenery.get("flash_timer", 3.0)) - delta
		if float(_sf_scenery.get("flash_timer", 0.0)) <= 0.0:
			_sf_scenery["flash_timer"] = randf_range(2.0, 5.0)
			_sf_scenery["flash_alpha"] = 0.10
		var fa := float(_sf_scenery.get("flash_alpha", 0.0))
		if fa > 0.0:
			fa = maxf(0.0, fa - delta * 0.8)
			_sf_scenery["flash_alpha"] = fa
		var flash: Polygon2D = _sf_scenery.get("flash")
		if flash != null:
			var fcol: Color = flash.color
			fcol.a = fa
			flash.color = fcol
	elif _sf_scenery.get("flash") != null:
		var flash2: Polygon2D = _sf_scenery.get("flash")
		var fcol2: Color = flash2.color
		fcol2.a = 0.0
		flash2.color = fcol2
	# QA-126 (v3.11): one-shot shockwave rings (lightning strikes) —
	# expand + fade over 0.5 s, then free.
	var shots: Array = _sf_scenery.get("one_shots", [])
	for i in range(shots.size() - 1, -1, -1):
		var sd: Dictionary = shots[i]
		var node: Sprite2D = sd["node"]
		if node == null or not is_instance_valid(node):
			shots.remove_at(i)
			continue
		var t := float(sd.get("t", 0.0)) + delta
		sd["t"] = t
		node.scale = Vector2(0.3 + t * 3.0, 0.3 + t * 3.0)
		node.modulate.a = maxf(0.0, 0.9 * (1.0 - t / 0.5))
		if t >= 0.5:
			node.queue_free()
			shots.remove_at(i)
	# QA-129 (v3.11): per-level weather + ambient life animation.
	_update_skyfall_weather(delta)


# QA-124 (v3.11) — PER-LEVEL THEMES: each of the 6 levels gets its
# OWN different visual theme — the ENTIRE background AND platforms
# change per level, not just a tint. Three depth layers per level:
# FAR = the pack's level image (z -6), MID = a level-specific
# silhouette (z -4), NEAR = decor + tinted platform tiles (z -1/0).
# Merged levels use BOTH their images (top half / bottom half).
# Level bands (y grows downward): L1 9000-10800, L2 7200-9000,
# L3 5400-7200, L4 3600-5400, L5 1800-3600, L6 0-1800.
func _build_skyfall_themes(map: Dictionary) -> void:
	# [top image, bottom image, platform tint, light overlay, name]
	var themes := [
		[SF_TEX_LVL_2, SF_TEX_LVL_1, Color(0.95, 0.85, 0.70), Color(1.0, 0.90, 0.70, 0.06), "Twin Base Camp + Broken Cliffs"],
		[SF_TEX_LVL_3, SF_TEX_LVL_3, Color(0.55, 0.55, 0.65), Color(0.0, 0.0, 0.10, 0.30), "Underground Tunnels"],
		[SF_TEX_LVL_4, SF_TEX_LVL_4, Color(1.0, 0.80, 0.55), Color(0.10, 0.10, 0.15, 0.08), "Hanging Bridge"],
		[SF_TEX_LVL_5, SF_TEX_LVL_5, Color(0.70, 0.85, 0.70), Color(0.05, 0.10, 0.20, 0.10), "Sniper Territory"],
		[SF_TEX_LVL_6, SF_TEX_LVL_6, Color(0.75, 0.80, 0.90), Color(1.0, 0.60, 0.30, 0.07), "Mechanical Ascent"],
		[SF_TEX_LVL_8, SF_TEX_LVL_7, Color(0.90, 0.95, 1.0), Color(0.10, 0.15, 0.35, 0.16), "The Last Stand + Flag Summit"],
	]
	for li in 6:
		var lvl := li + 1
		var y_top := 10800.0 - float(lvl) * 1800.0
		var th: Array = themes[li]
		# FAR: one image per 900 px half-band (2x scale, uniform —
		# the 1800x450 image covers 3600x900 with no distortion).
		for half in 2:
			var spr := Sprite2D.new()
			spr.texture = th[half]
			spr.position = Vector2(1800, y_top + 450.0 + float(half) * 900.0)
			spr.scale = Vector2(2.0, 2.0)
			spr.z_index = -6
			add_child(spr)
		# LIGHTING: a translucent mood wash over the whole level —
		# tunnels darkest, summit storm-blue, base warm. Day-to-dusk
		# as you climb: the wash darkens and cools with height.
		var wash := Polygon2D.new()
		wash.polygon = PackedVector2Array([Vector2(0, y_top), Vector2(3400, y_top), Vector2(3400, y_top + 1800), Vector2(0, y_top + 1800)])
		wash.color = th[3]
		wash.z_index = -5
		add_child(wash)
		# MID: a level-specific silhouette (z -4) + the platform
		# tint below. Silhouettes are code-drawn, muted, and never
		# touch the routes.
		_sf_build_level_silhouette(lvl, y_top)
	# NEAR: tint every platform's tile sprites in the level's colour.
	for pr in map.get("platforms", []):
		var prect: Rect2 = pr
		var tint: Color = (themes[_sf_level_of(prect.position.y + 24.0) - 1] as Array)[2]
		for s in _sf_tile_sprites_at(prect):
			(s as Sprite2D).modulate = tint


func _sf_build_level_silhouette(lvl: int, y_top: float) -> void:
	# One muted mid-ground shape per level, drawn in the level band.
	# QA-132: only L1 keeps its silhouette (the cliff ridge — L1
	# is untouched). L2-L6 silhouettes are DELETED (user: clean
	# everything unnecessary): stalactites hung over the routes,
	# rope curves and watchtowers read as structures, the L5 pipes
	# were full-width bars that read as floors, and the L6 storm
	# peaks crowded the summit. The per-level FAR backdrops +
	# lighting wash stay (QA-124 themes), so each level still has
	# its own look.
	match lvl:
		1: # Broken Cliffs: a jagged cliff ridge across the top half.
			var ridge := Polygon2D.new()
			var pts := PackedVector2Array([Vector2(0, y_top + 900)])
			var seed := 777
			var x := 0.0
			while x < 3400.0: # QA-132: right boundary is 3400 now, not 3600
				seed = (seed * 1103515245 + 12345) & 0x7fffffff
				var w := 200.0 + float(seed % 260)
				seed = (seed * 1103515245 + 12345) & 0x7fffffff
				var h := 120.0 + float(seed % 220)
				pts.append(Vector2(x, y_top + 900.0 - h))
				pts.append(Vector2(minf(x + w, 3400.0), y_top + 900.0 - h))
				x += w + 60.0
			pts.append(Vector2(3400, y_top + 900))
			ridge.polygon = pts
			ridge.color = Color(0.32, 0.26, 0.20, 0.55)
			ridge.z_index = -4
			add_child(ridge)
		_: # L2-L6: no mid silhouette (QA-132 clean-up).
			pass


# QA-129 (v3.11) — PER-LEVEL WEATHER / MOOD + AMBIENT LIFE. All
# sprites are cheap transforms (no particles nodes, no shaders):
# dust in Base Camp, drips in the Tunnels, the base-camp waving
# flag, and storm rain + dark overlay (hidden until a storm).
# QA-132: leaves, steam, snow, storm/mid clouds, birds, portals,
# whirlpool and arcs are deleted (clean-up). Gust streaks stay
# (storm telegraphs). Counts are capped so phones stay safe.
func _build_skyfall_weather(map: Dictionary) -> void:
	var w: Dictionary = {}
	var dust: Array = []
	for i in 4:
		var d := Sprite2D.new()
		d.texture = FX_TEX_DUST
		d.position = Vector2(400.0 + float(i) * 800.0, 9900.0 + float(i % 2) * 500.0)
		d.scale = Vector2(0.5, 0.5)
		d.modulate = Color(1, 1, 1, 0.35)
		d.z_index = -3
		add_child(d)
		dust.append({"node": d, "speed": 14.0 + float(i) * 5.0})
	w["dust"] = dust
	var drips: Array = []
	for i in 4:
		var d := Sprite2D.new()
		d.texture = FX_TEX_RAIN
		d.position = Vector2(500.0 + float(i) * 800.0, 7400.0 + float(i % 2) * 600.0)
		d.scale = Vector2(0.35, 0.35)
		d.modulate = Color(1, 1, 1, 0.4)
		d.z_index = -3
		add_child(d)
		drips.append(d)
	w["drips"] = drips
	# QA-132: leaves (L3), steam (L5), snow (L6), storm clouds
	# (L6) and mid clouds (L5) are DELETED (user: clean everything
	# unnecessary). Dust (L1) and drips (L2) stay.
	# Storm rain over the top two levels — hidden until a storm.
	var rain: Array = []
	for i in 8:
		var r := Sprite2D.new()
		r.texture = FX_TEX_RAIN
		r.position = Vector2(200.0 + float(i) * 420.0, 200.0 + float(i % 4) * 500.0)
		r.scale = Vector2(0.8, 0.8)
		r.modulate = Color(1, 1, 1, 0.6)
		r.z_index = 3
		r.visible = false
		add_child(r)
		rain.append(r)
	w["rain"] = rain
	# Storm dark overlay over the top two levels (fades in with the storm).
	var dark := Polygon2D.new()
	dark.polygon = PackedVector2Array([Vector2(0, 0), Vector2(3400, 0), Vector2(3400, 3600), Vector2(0, 3600)])
	dark.color = Color(0.05, 0.08, 0.20, 0.0)
	dark.z_index = -5
	add_child(dark)
	w["storm_dark"] = dark
	# Waving flag: base camp only (pennant skews with sin).
	# QA-132: the L4 flag at (3000,3664) is DELETED (clean-up).
	var flags: Array = []
	for fp in [Vector2(400, 10752)]:
		var pole := Polygon2D.new()
		pole.polygon = PackedVector2Array([Vector2(fp.x - 2, fp.y), Vector2(fp.x + 2, fp.y), Vector2(fp.x + 2, fp.y - 90), Vector2(fp.x - 2, fp.y - 90)])
		pole.color = Color(0.15, 0.15, 0.18)
		pole.z_index = -1
		add_child(pole)
		var pen := Polygon2D.new()
		pen.polygon = PackedVector2Array([Vector2(0, 0), Vector2(64, 10), Vector2(0, 22)])
		pen.color = Color(0.85, 0.12, 0.12)
		pen.position = Vector2(fp.x + 2, fp.y - 90)
		pen.z_index = -1
		add_child(pen)
		flags.append(pen)
	w["flags"] = flags
	# QA-132: the portal markers (1800,6100) + (1800,2050) are
	# DELETED — big rotating discs with no collision and no
	# teleport, they read as platforms you cannot land on. The
	# grapple points at those exact spots STAY (gold ring + dot,
	# drawn in _build_skyfall). The wind whirlpool (1800,6400)
	# and the electric arcs by the gears are DELETED too.
	# Gust streaks for the bridge wind gusts (hidden until a gust).
	# QA-135 (v3.13): 5 streaks now — the first 3 cover the old
	# L3 wind zone (y 6000-6800), the last 2 the new upper L3 zone
	# (y 5400-6000).
	var gusts: Array = []
	var gust_pos := [Vector2(600, 6200), Vector2(1500, 6500), Vector2(2400, 6200), Vector2(1500, 5600), Vector2(2100, 5750)]
	for i in gust_pos.size():
		var g := Sprite2D.new()
		g.texture = FX_TEX_GUST_R if i % 2 == 0 else FX_TEX_GUST_L
		g.position = gust_pos[i]
		g.scale = Vector2(0.9, 0.9)
		g.modulate = Color(1, 1, 1, 0.0)
		g.z_index = 2
		add_child(g)
		gusts.append(g)
	w["gusts"] = gusts
	_sf_scenery["weather"] = w


func _update_skyfall_weather(delta: float) -> void:
	# Animate the QA-129 weather + ambient life. Pure functions of
	# the match clock + delta (no gameplay reads), so all peers agree.
	# QA-132: the leaves / steam / snow / storm-cloud / mid-cloud /
	# bird / portal / whirl / arc loops are gone with the items.
	var w: Dictionary = _sf_scenery.get("weather", {})
	if w.is_empty():
		return
	for d in w.get("dust", []):
		var n: Node2D = d["node"]
		n.position.x += float(d["speed"]) * delta
		if n.position.x > 3400.0:
			n.position.x = 0.0
	for dr in w.get("drips", []):
		var n2: Node2D = dr
		n2.position.y += 55.0 * delta
		if n2.position.y > 8900.0:
			n2.position.y = 7300.0
	for r in w.get("rain", []):
		var n8: Node2D = r
		n8.visible = _sf_storm_active
		if _sf_storm_active:
			n8.position.y += 700.0 * delta
			if n8.position.y > 3500.0:
				n8.position.y = 0.0
	var dark: Polygon2D = w.get("storm_dark")
	if dark != null:
		var dc: Color = dark.color
		dc.a = lerpf(dc.a, 0.25 if _sf_storm_active else 0.0, clampf(delta * 2.0, 0.0, 1.0))
		dark.color = dc
	for fi in (w.get("flags", []) as Array).size():
		var pen: Polygon2D = (w.get("flags", []) as Array)[fi]
		var skew := sin(_sf_match_time * 3.0 + float(fi) * 2.0) * 6.0
		pen.polygon = PackedVector2Array([Vector2(0, 0), Vector2(64, 10 + skew), Vector2(0, 22)])
	var gust_on := _sf_gust_active()
	for gi in (w.get("gusts", []) as Array).size():
		var g: Sprite2D = (w.get("gusts", []) as Array)[gi]
		if gust_on:
			g.modulate.a = 0.7
			g.position.x += 500.0 * delta
			if g.position.x > 3100.0:
				g.position.x = 500.0
		else:
			g.modulate.a = 0.0


# QA-126 (v3.11) — HAZARD VISUALS: lava pool + fire jet sprites on
# the Mechanical Ascent hazard rects. The flames are pure functions
# of the match clock (2 s hot / 2 s safe per 4 s cycle) so every peer
# sees the same telegraph; the damage tick itself is host-only in
# _sf_update_hazards.
func _build_skyfall_hazards(map: Dictionary) -> void:
	for hz in map.get("hazards", []):
		var r: Rect2 = hz["rect"]
		var kind: String = str(hz.get("kind", "lava"))
		var flame := Sprite2D.new()
		flame.texture = FX_TEX_LAVA if kind == "lava" else FX_TEX_FIRE_PILLAR
		flame.position = r.get_center()
		flame.scale = Vector2(r.size.x / 512.0, 0.6)
		flame.modulate = Color(1, 1, 1, 0.85)
		flame.z_index = 1
		add_child(flame)
		var magma: Sprite2D = null
		if kind == "lava":
			magma = Sprite2D.new()
			magma.texture = FX_TEX_MAGMA
			magma.position = r.get_center() + Vector2(0, -30)
			magma.scale = Vector2(0.5, 0.5)
			magma.modulate = Color(1, 1, 1, 0.0)
			magma.z_index = 1
			add_child(magma)
		_sf_hazard_fx.append({"kind": kind, "rect": r, "flame": flame, "magma": magma, "cycle": float(hz.get("cycle", 4.0))})


func _build_skyfall_movers(map: Dictionary) -> void:
	# Moving elevators (L6): AnimatableBody2D, ping-pong between
	# y_top and y_bottom. sync_to_physics carries riders.
	for cfg in map.get("elevators", []):
		var body := AnimatableBody2D.new()
		body.name = "Elevator_%d" % int(cfg["x"])
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = true
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(float(cfg["w"]), 48.0)
		shape.shape = box
		body.add_child(shape)
		var spr := Sprite2D.new()
		spr.texture = SF_TEX_ELEVATOR
		spr.position = Vector2(0, 24) # slab art is 96 tall; top aligns with the collision top
		body.add_child(spr)
		var y_mid := (float(cfg["y_top"]) + float(cfg["y_bottom"])) * 0.5
		body.position = Vector2(float(cfg["x"]) + float(cfg["w"]) * 0.5, y_mid + 24.0)
		add_child(body)
		_sf_elevators.append({"body": body, "sprite": spr, "cfg": cfg, "phase": float(cfg.get("phase", 0.0))})
	# Rotating platform (L6): orbits its centre.
	var rot: Dictionary = map.get("rotator", {})
	if not rot.is_empty():
		var body := AnimatableBody2D.new()
		body.name = "Rotator"
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = true
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(float(rot.get("w", 400)), 48.0)
		shape.shape = box
		body.add_child(shape)
		var spr := Sprite2D.new()
		spr.texture = SF_TEX_ELEVATOR
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, float(rot.get("w", 400)), 96)
		spr.position = Vector2(0, 24)
		body.add_child(spr)
		body.position = (rot["center"] as Vector2) + Vector2(float(rot.get("radius", 120.0)), 0)
		add_child(body)
		_sf_rotator = {"body": body, "sprite": spr, "cfg": rot, "angle": 0.0}
	# Summit elevator: docked at the arena until the control switch
	# activates it (then it shuttles arena <-> summit for 30 s).
	var se: Dictionary = map.get("summit_elevator", {})
	if not se.is_empty():
		var body := AnimatableBody2D.new()
		body.name = "SummitElevator"
		body.collision_layer = 1
		body.collision_mask = 0
		body.sync_to_physics = true
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(float(se.get("w", 300)), 48.0)
		shape.shape = box
		body.add_child(shape)
		var spr := Sprite2D.new()
		spr.texture = SF_TEX_ELEVATOR
		spr.region_enabled = true
		spr.region_rect = Rect2(0, 0, float(se.get("w", 300)), 96)
		spr.position = Vector2(0, 24)
		body.add_child(spr)
		body.position = Vector2(float(se["x"]) + float(se.get("w", 300)) * 0.5, float(se["y_bottom"]) + 24.0)
		add_child(body)
		_sf_summit_elevator = {"body": body, "sprite": spr, "cfg": se, "state": "docked", "timer": 0.0, "dir": -1.0}


func _build_skyfall_gate(map: Dictionary) -> void:
	# Summit gate: stands on the summit floor, bars vertical, gaps
	# transparent (the pack's gate art). Blocks the middle of the
	# summit floor until it opens 45 s into the match; the side
	# ledges are always open, so it never blocks the climb.
	var g: Dictionary = map.get("gate", {})
	if g.is_empty():
		return
	var gx := float(g.get("x", 1800))
	var gy := float(g.get("y", 862))
	var spr := Sprite2D.new()
	spr.texture = SF_TEX_GATE
	spr.position = Vector2(gx, gy - 192)
	spr.z_index = 2
	add_child(spr)
	_sf_gate_sprite = spr
	var arena := get_node_or_null("Arena")
	if arena != null:
		var shape := CollisionShape2D.new()
		var box := RectangleShape2D.new()
		box.size = Vector2(116, 378)
		shape.shape = box
		shape.position = Vector2(gx, gy - 189)
		arena.add_child(shape)
		_sf_gate_shape = shape
	_sf_gate_open = false
	_sf_gate_timer = 45.0


func _build_skyfall_switch(map: Dictionary) -> void:
	# Summit Control Switch on the arena floor: stand next to it
	# for 1 s to activate the summit elevator for 30 s.
	var sw: Dictionary = map.get("switch", {})
	if sw.is_empty():
		return
	var pos: Vector2 = sw.get("pos", Vector2(1800, 1712))
	var spr := Sprite2D.new()
	spr.texture = SF_TEX_SWITCH
	spr.position = pos + Vector2(0, -128)
	spr.z_index = 2
	add_child(spr)
	# The 1 s channel is checked by distance in _update_skyfall
	# (any alive player within 90 px of the switch) — no Area2D
	# needed, and distance is simpler to test.
	_sf_switch_on = false
	_sf_switch_timer = 0.0


func _build_skyfall_barricades(map: Dictionary) -> void:
	# Destructible wooden barricades on the arena floor: solid
	# cover, 100 HP, break when shot (try_barricade_hit, same
	# pattern as barrels) or caught in a blast, respawn in 30 s.
	var arena := get_node_or_null("Arena")
	for b in map.get("barricades", []):
		var pos: Vector2 = b.get("pos", Vector2.ZERO)
		var spr := Sprite2D.new()
		spr.texture = SF_TEX_BARRICADE
		spr.position = pos + Vector2(0, -96)
		spr.z_index = 2
		add_child(spr)
		var shape: CollisionShape2D = null
		if arena != null:
			shape = CollisionShape2D.new()
			var box := RectangleShape2D.new()
			box.size = Vector2(148, 180)
			shape.shape = box
			shape.position = pos + Vector2(0, -90)
			arena.add_child(shape)
		_sf_barricades.append({"rect": Rect2(pos + Vector2(-74, -180), Vector2(148, 180)), "sprite": spr, "shape": shape, "hp": 100.0, "alive": true, "timer": 0.0})


func try_barricade_hit(hit_pos: Vector2, dmg: int) -> bool:
	# Bullet vs destructible barricade (QA-112). Host-authorised:
	# only the server damages barricades; clients return false
	# (just the spark). Returns true when a barricade was hit.
	if not multiplayer.is_server():
		return false
	for b in _sf_barricades:
		if not bool(b["alive"]):
			continue
		var r: Rect2 = b["rect"]
		if r.grow(6.0).has_point(hit_pos):
			b["hp"] = float(b["hp"]) - dmg
			if float(b["hp"]) <= 0.0:
				_sf_break_barricade(b)
			return true
	return false


func _sf_break_barricade(b: Dictionary) -> void:
	b["alive"] = false
	b["timer"] = 30.0
	(b["sprite"] as Node2D).visible = false
	if b["shape"] != null:
		(b["shape"] as CollisionShape2D).set_deferred("disabled", true)
	rpc("sf_barricade_remote", _sf_barricades.find(b), false)


@rpc("any_peer", "call_local")
func sf_barricade_remote(idx: int, alive: bool) -> void:
	if idx < 0 or idx >= _sf_barricades.size():
		return
	var b: Dictionary = _sf_barricades[idx]
	b["alive"] = alive
	(b["sprite"] as Node2D).visible = alive
	if b["shape"] != null:
		(b["shape"] as CollisionShape2D).set_deferred("disabled", not alive)
	if not alive:
		b["timer"] = 30.0


func _build_skyfall_platform_refs(map: Dictionary) -> void:
	# Collapsing bridge middle + trapdoors: find their Arena shapes
	# + tile sprites by position (see _sf_arena_shape_at /
	# _sf_tile_sprites_at). QA-132: the storm-perch loop is gone
	# with the disable mechanic — the perches stay landable.
	var plats: Array = map["platforms"]
	for idx in map.get("collapsing", []):
		var r: Rect2 = plats[int(idx)]
		_sf_collapsing.append({"idx": int(idx), "rect": r, "shape": _sf_arena_shape_at(r.get_center()), "sprites": _sf_tile_sprites_at(r), "state": "idle", "timer": 0.0})
	for idx in map.get("trapdoors", []):
		var r: Rect2 = plats[int(idx)]
		var sprs: Array = _sf_tile_sprites_at(r)
		for s in sprs:
			(s as Sprite2D).texture = SF_TEX_TRAPDOOR_CLOSED
			(s as Sprite2D).region_enabled = true
			(s as Sprite2D).region_rect = Rect2(0, 0, minf(512.0, r.size.x), 48)
		_sf_trapdoors.append({"idx": int(idx), "rect": r, "shape": _sf_arena_shape_at(r.get_center()), "sprites": sprs, "state": "closed", "timer": 0.0})


# ---------------------------------------------------------------------------
# QA-112 (v3.9) — Vertical CTF (mode 4, SKYFALL ONLY). Restored from
# the v3.6 CTF (QA-080) and adapted: BOTH flags live at the SUMMIT,
# captures score at the base EXTRACTION ZONES, grabbing takes a
# 1.5 s hold, a dropped flag returns after 15 s, the carrier is
# 15% slower with no jetpack (player.gd reads carrying_flag).
# Host-authoritative; clients only render what ctf_sync sends.
# ---------------------------------------------------------------------------

func _ctf_team_color(team: int) -> Color:
	return Color(0.95, 0.3, 0.25) if team == 0 else Color(0.25, 0.55, 0.95)


func _ctf_flag_visual(team: int) -> Node2D:
	# Pack art (flag_red/blue.png, 256 px, real transparency) at
	# half scale, with a small team tag underneath. The dropped
	# variant swaps in when the flag is on the ground.
	var node := Node2D.new()
	node.name = "Flag%d" % team
	node.z_index = 5
	var spr := Sprite2D.new()
	spr.texture = SF_TEX_FLAG_RED if team == 0 else SF_TEX_FLAG_BLUE
	spr.scale = Vector2(0.5, 0.5)
	spr.position = Vector2(0, -64)
	node.add_child(spr)
	var tag := Label.new()
	tag.text = "RED FLAG" if team == 0 else "BLUE FLAG"
	tag.position = Vector2(-40, 6)
	tag.size = Vector2(80, 20)
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_font_size_override("font_size", 16)
	tag.add_theme_color_override("font_color", _ctf_team_color(team))
	tag.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	tag.add_theme_constant_override("outline_size", 4)
	node.add_child(tag)
	node.set_meta("sprite", spr)
	return node


func _build_ctf_flags() -> void:
	# One flag per team, both at the summit (map["ctf"] homes).
	# Idempotent: the features test rebuilds CTF mid-run and must
	# not stack flags.
	for f in _ctf_flags:
		var old_node: Node = (f as Dictionary).get("node")
		if old_node != null and is_instance_valid(old_node):
			old_node.queue_free()
	_ctf_flags.clear()
	_ctf_scores = {0: 0, 1: 0}
	_ctf_captures.clear()
	_ctf_grab.clear()
	_ctf_dropped_timer.clear()
	_ctf_checkpoints = {0: 0, 1: 0}
	if game_mode != 4:
		return
	var ctf: Dictionary = MAPS[map_id].get("ctf", {})
	if ctf.is_empty():
		return
	for team in [0, 1]:
		var home: Vector2 = ctf.get("flag_red" if team == 0 else "flag_blue", Vector2(1400 + team * 800, 862))
		var node := _ctf_flag_visual(team)
		node.position = home
		add_child(node)
		_ctf_flags.append({"team": team, "home": home, "pos": home, "carrier": -1, "dropped": false, "node": node, "sprite": node.get_meta("sprite")})


func _ctf_carrier_of(pid: int) -> int:
	# QA-133 (v3.12): the carrier flag MUST use player.gd's enum —
	# 0 none, 1 RED flag, 2 BLUE flag. The old code returned the
	# flag's team (0 RED / 1 BLUE) for a carrier and -1 for a
	# non-carrier, which every reader (player.gd: speed, jetpack,
	# activate_slot) treats as "carrying" when != 0. So after the
	# first 0.5 s ctf_sync, EVERY non-carrier in CTF was 15% slow,
	# jetpack-less and unable to activate ANY timed power-up — and
	# a RED-flag carrier (0) was treated as free. That is the deep
	# root cause of the user's "power-ups have no use": in a real
	# CTF match every timed tap was refused (silently, before the
	# QA-132 feed messages). The v3.11 tests never caught it —
	# they all activate synchronously in setup, before the first
	# sync rewrites the flag; the QA-132 PATH tests activate in the
	# check (after a 1 s wait) and exposed it.
	for f in _ctf_flags:
		if int((f as Dictionary).get("carrier", -1)) == pid:
			return int((f as Dictionary).get("team", -1)) + 1 # team 0 RED -> 1, team 1 BLUE -> 2
	return 0 # not carrying


func _ctf_state() -> Array:
	var out: Array = []
	for f in _ctf_flags:
		var d: Dictionary = f
		out.append({"team": int(d.get("team", 0)), "pos": d.get("pos"), "carrier": int(d.get("carrier", -1)), "dropped": bool(d.get("dropped", false))})
	return out


func _ctf_send_sync() -> void:
	if _ctf_flags.is_empty():
		return
	rpc("ctf_sync", _ctf_state(), _ctf_scores.duplicate(), _ctf_checkpoints.duplicate())


@rpc("any_peer", "call_local")
func ctf_sync(state: Array, scores: Dictionary, checkpoints: Dictionary = {0: 0, 1: 0}) -> void:
	# Only the host may set flag state.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_ctf_scores = scores.duplicate()
	_ctf_checkpoints = checkpoints.duplicate()
	for i in mini(state.size(), _ctf_flags.size()):
		var s: Dictionary = state[i]
		var f: Dictionary = _ctf_flags[i]
		f["pos"] = s.get("pos", f.get("pos"))
		f["carrier"] = int(s.get("carrier", -1))
		f["dropped"] = bool(s.get("dropped", false))
	_ctf_update_carrying_flags()


func _ctf_update_carrying_flags() -> void:
	# Every player node carries its flag state (player.gd reads
	# carrying_flag for the 15% slowdown + no jetpack). The host
	# sets it from the flag state; clients get it from ctf_sync.
	if players_node == null:
		return
	for child in players_node.get_children():
		child.set("carrying_flag", _ctf_carrier_of(int(child.peer_id)))


func _on_slot_pressed(idx: int) -> void:
	# QA-119 (v3.11): tap a HUD slot button to activate the stored
	# power-up. activate_slot() enforces the rules (timed needs no
	# active boost and no flag carried); a refused tap just does
	# nothing. "tap" sound only on a real activation.
	# QA-132: a refused tap now SAYS why in the feed (it used to
	# fail silently — the player could not tell a rule from a bug).
	var lp = _get_local_player()
	if lp == null:
		return
	if bool(lp.call("activate_slot", idx)):
		audio.play("tap")
		return
	var stored: Array = lp.get("stored_boosts")
	if idx < 0 or idx >= stored.size():
		return
	if int(stored[idx]) in [8, 9, 10, 13]:
		if int(lp.get("active_boost_kind")) != 0:
			_ctf_feed("Boost already active", Color(1.0, 0.8, 0.2))
		elif int(lp.get("carrying_flag")) != 0:
			_ctf_feed("Cannot use while carrying the flag", Color(1.0, 0.8, 0.2))


func _update_invis_warning(lp) -> void:
	# QA-121 (v3.11): while any living ENEMY is invisible, a red
	# chip sits at the top of the top-left message area; it clears
	# the moment the invisibility ends. Teammates are not warned
	# (they see the faint outline). Runs every frame from
	# _update_hud; the chip is NOT a feed entry (no 5 s expiry, no
	# place in the 4-entry cap).
	if _kill_feed_list == null:
		return
	var warn := false
	var my_team := int(lp.team)
	for child in players_node.get_children():
		if int(child.peer_id) == int(lp.peer_id) or not child.alive:
			continue
		var enemy := my_team < 0 or int(child.team) != my_team
		if enemy and float(child.get("invisibility_timer")) > 0.0:
			warn = true
			break
	if not warn:
		if _invis_warning_chip != null:
			_invis_warning_chip.visible = false
		return
	if _invis_warning_chip == null:
		var lbl := Label.new()
		lbl.text = "Enemy is invisible!"
		lbl.add_theme_font_override("font", FONT_BODY_MEDIUM)
		lbl.add_theme_font_size_override("font_size", 18)
		lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.3))
		_outline_label(lbl)
		var chip := PanelContainer.new()
		var chip_bg := StyleBoxFlat.new()
		chip_bg.bg_color = Color(0.35, 0.05, 0.08, 0.88)
		chip_bg.set_corner_radius_all(8)
		chip_bg.content_margin_left = 10
		chip_bg.content_margin_right = 10
		chip_bg.content_margin_top = 4
		chip_bg.content_margin_bottom = 4
		chip.add_theme_stylebox_override("panel", chip_bg)
		chip.add_child(lbl)
		_invis_warning_chip = chip
		_kill_feed_list.add_child(chip)
	_kill_feed_list.move_child(_invis_warning_chip, 0)
	_invis_warning_chip.visible = true


func _ctf_feed(text: String, color: Color) -> void:
	# Plain-text line on the kill feed (same chip + 5 s expiry as
	# a kill line — _add_kill_feed_entry is kill-shaped, so CTF
	# gets its own small builder instead of bending that one).
	if _kill_feed_list == null:
		return
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_override("font", FONT_BODY_MEDIUM)
	lbl.add_theme_font_size_override("font_size", 18)
	lbl.add_theme_color_override("font_color", color)
	_outline_label(lbl)
	var chip := PanelContainer.new()
	var chip_bg := StyleBoxFlat.new()
	chip_bg.bg_color = Color(0.03, 0.07, 0.13, 0.88)
	chip_bg.set_corner_radius_all(8)
	chip_bg.content_margin_left = 10
	chip_bg.content_margin_right = 10
	chip_bg.content_margin_top = 4
	chip_bg.content_margin_bottom = 4
	chip.add_theme_stylebox_override("panel", chip_bg)
	chip.add_child(lbl)
	_kill_feed_list.add_child(chip)
	_kill_feed_entries.append({"label": lbl, "panel": chip, "expiry": 5.0})
	while _kill_feed_entries.size() > 4:
		var old: Dictionary = _kill_feed_entries.pop_front()
		(old["panel"] as PanelContainer).queue_free()


func _update_ctf(delta: float) -> void:
	if game_mode != 4 or _ctf_flags.is_empty():
		return
	# Render (every peer, every frame): a carried flag rides above
	# its carrier's head; a dropped flag lies where it fell (fallen
	# art); a home flag stands at the summit.
	for f in _ctf_flags:
		var d: Dictionary = f
		var node: Node = d.get("node")
		if node == null or not is_instance_valid(node):
			continue
		var spr: Sprite2D = d.get("sprite")
		var carrier: int = int(d.get("carrier", -1))
		if spr != null:
			if bool(d.get("dropped", false)):
				spr.texture = SF_TEX_FLAG_RED_DROPPED if int(d.get("team", 0)) == 0 else SF_TEX_FLAG_BLUE_DROPPED
			else:
				spr.texture = SF_TEX_FLAG_RED if int(d.get("team", 0)) == 0 else SF_TEX_FLAG_BLUE
		if carrier >= 0:
			var cp := players_node.get_node_or_null(str(carrier))
			if cp != null:
				(node as Node2D).position = cp.position + Vector2(0, -80)
				continue
		(node as Node2D).position = d.get("pos", d.get("home"))
	# Host logic only — clients never move a flag.
	if not multiplayer.is_server() or match_over or _countdown_active:
		return
	var changed := false
	var ctf: Dictionary = MAPS[map_id].get("ctf", {})
	for f in _ctf_flags:
		var d: Dictionary = f
		var team: int = int(d.get("team", 0))
		var carrier: int = int(d.get("carrier", -1))
		if carrier >= 0:
			var cp := players_node.get_node_or_null(str(carrier))
			if cp == null or not cp.alive:
				# Carrier died (or left): the flag drops where
				# they fell. Either team can recover it from here.
				d["pos"] = cp.position if cp != null else d.get("pos")
				d["carrier"] = -1
				d["dropped"] = true
				_ctf_dropped_timer[team] = 0.0
				_ctf_feed("⚑ %s dropped the %s flag!" % [_player_name(carrier), "RED" if team == 0 else "BLUE"], _ctf_team_color(team))
				changed = true
				continue
			# Capture: the carrier reached their OWN extraction
			# zone while their own flag is home (no capture while
			# your flag is away). The carrier stole flag `team`,
			# so their own flag is the other one (1 - team), and
			# their own extraction zone is the other side's.
			var own: Dictionary = _ctf_flags[1 - team]
			var own_home: bool = int(own.get("carrier", -1)) == -1 and not bool(own.get("dropped", false))
			var zone: Vector2 = ctf.get("extract_red" if int(cp.team) == 0 else "extract_blue", Vector2.ZERO)
			if own_home and cp.position.distance_to(zone) < 120.0:
				var ct: int = int(cp.team)
				_ctf_scores[ct] = int(_ctf_scores.get(ct, 0)) + GameData.CTF_CAPTURE_POINTS
				_ctf_captures[carrier] = int(_ctf_captures.get(carrier, 0)) + 1
				d["pos"] = d.get("home")
				d["carrier"] = -1
				d["dropped"] = false
				_ctf_feed("⚑ %s captured the flag! +%d pts  RED %d — %d BLUE" % [_player_name(carrier), GameData.CTF_CAPTURE_POINTS, int(_ctf_scores.get(0, 0)), int(_ctf_scores.get(1, 0))], _ctf_team_color(ct))
				changed = true
				_check_match_end()
			else:
				# QA-114 (v3.9): PARTIAL SCORING — the carrier banks
				# the flag at a relay station (levels 4 / 7) for +1
				# point. The flag returns to the summit, so the run
				# ends here (no double-banking the same run); the
				# team must steal it again for the next bank or the
				# full +3 capture. This breaks stalemates: a team
				# that cannot finish the long run down still scores
				# for getting halfway.
				var relays: Array = MAPS[map_id].get("relay", [])
				for ri in relays.size():
					var rp: Vector2 = relays[ri]
					if cp.position.distance_to(rp) < 140.0:
						var ct2: int = int(cp.team)
						_ctf_scores[ct2] = int(_ctf_scores.get(ct2, 0)) + GameData.CTF_RELAY_POINTS
						d["pos"] = d.get("home")
						d["carrier"] = -1
						d["dropped"] = false
						var lvl := 4 if ri == 0 else 7
						_ctf_feed("⚑ %s banked the flag at the Level %d relay! +%d pt  RED %d — %d BLUE" % [_player_name(carrier), lvl, GameData.CTF_RELAY_POINTS, int(_ctf_scores.get(0, 0)), int(_ctf_scores.get(1, 0))], _ctf_team_color(ct2))
						changed = true
						_check_match_end()
						break
			continue
		# Dropped flag: 15 s unretrieved and it returns to the summit.
		if bool(d.get("dropped", false)):
			var dt := float(_ctf_dropped_timer.get(team, 0.0)) + delta
			_ctf_dropped_timer[team] = dt
			if dt >= 15.0:
				d["pos"] = d.get("home")
				d["dropped"] = false
				_ctf_dropped_timer[team] = 0.0
				_ctf_feed("⚑ The %s flag returned to the summit!" % ("RED" if team == 0 else "BLUE"), _ctf_team_color(team))
				changed = true
		# Free flag: an enemy steals it with a 1.5 s hold; a
		# teammate returns a dropped flag by walking over it.
		# QA-114 (v3.9): the hold is keyed by (peer, flag) — the
		# old peer-only key was wiped every frame by the OTHER
		# flag's distance check (the player is always > 80 px from
		# one flag), so the hold never reached 1.5 s and a flag
		# could never be grabbed. The features test caught it.
		for child in players_node.get_children():
			if not child.alive:
				continue
			var ppos: Vector2 = child.position
			var fpos: Vector2 = d.get("pos")
			var gkey := int(child.peer_id) * 10 + team
			if ppos.distance_to(fpos) > 80.0:
				_ctf_grab.erase(gkey)
				continue
			if bool(d.get("dropped", false)) and int(child.team) == team:
				d["pos"] = d.get("home")
				d["dropped"] = false
				_ctf_dropped_timer[team] = 0.0
				_ctf_feed("⚑ %s returned the %s flag!" % [_player_name(child.peer_id), "RED" if team == 0 else "BLUE"], _ctf_team_color(team))
				changed = true
				break
			if int(child.team) != team:
				# Hold 1.5 s on the flag to grab it. Moving away
				# resets the hold (the erase above, on distance).
				var held := float(_ctf_grab.get(gkey, 0.0)) + delta
				_ctf_grab[gkey] = held
				if held >= 1.5:
					d["carrier"] = int(child.peer_id)
					_ctf_grab.erase(gkey)
					_ctf_feed("⚑ %s took the %s flag!" % [_player_name(child.peer_id), "RED" if team == 0 else "BLUE"], _ctf_team_color(team))
					changed = true
				break
	if changed:
		_ctf_update_carrying_flags()
	_ctf_sync_timer += delta
	if changed or _ctf_sync_timer >= 0.5:
		_ctf_sync_timer = 0.0
		_ctf_send_sync()


func skyfall_ladder_at(pos: Vector2) -> Rect2:
	# Ladder rect containing pos (player.gd calls this every
	# physics frame; empty rect = no ladder / not Skyfall).
	if map_id != GameData.SKYFALL_MAP_ID:
		return Rect2()
	for r in MAPS[map_id].get("ladders", []):
		if (r as Rect2).has_point(pos):
			return r
	return Rect2()


func skyfall_wind_at(pos: Vector2) -> Vector2:
	# Wind push at a position (player.gd applies it as extra
	# acceleration). Zero outside the wind zones / off Skyfall.
	if map_id != GameData.SKYFALL_MAP_ID:
		return Vector2.ZERO
	for w in MAPS[map_id].get("wind", []):
		if (w["rect"] as Rect2).has_point(pos):
			var wind: Vector2 = (w["dir"] as Vector2) * float(w.get("strength", 120.0))
			# QA-114 (v3.9): a ROUTE SHIFT event reverses the wind
			# for 20 s. Jetpack lines still shield the rider (the
			# line wins over the wind — opposite-feature rule).
			if _sf_event_wind_flip:
				wind = -wind
			# QA-129 (v3.11): bridge gusts — every 15 s the bridge
			# wind (y 6000-6800) doubles for 3 s. The gust streaks
			# show it coming; the jetpack line still shields.
			if _sf_gust_active() and pos.y >= 6000.0 and pos.y < 6800.0:
				wind *= 2.0
			return wind
	return Vector2.ZERO


func _sf_gust_active() -> bool:
	# Bridge wind gust: 3 s of doubled wind every 15 s of match
	# time. A pure function of the match clock, so host and clients
	# agree with no RPC.
	return not match_over and not _countdown_active and fmod(_sf_match_time, 15.0) < 3.0


func _sf_play_hazard_sound(sound_name: String, pos: Vector2, max_dist: float) -> void:
	# QA-126 (v3.11): hazard SFX, only when the local player can
	# plausibly hear it (within max_dist of the event) — a strike
	# at the far end of the tower stays silent. The AudioStreamPlayer
	# pool caps overlap (6 players); hazard events are already
	# throttled (strikes 3 s, ticks 1 s, rocks 4 s), so no spam.
	if audio == null:
		return
	var lp = _get_local_player()
	if lp == null:
		return
	if lp.position.distance_to(pos) <= max_dist:
		audio.play(sound_name)


func _sf_damage_player(child: Node, amount: int) -> void:	# Host-authoritative damage to one player (same routing as the
	# falling rocks): direct when the host owns the victim, RPC to
	# the owning peer otherwise. The victim's take_damage applies
	# the shield (blocks ALL damage) + hit flash + shake, and the
	# health-regen timer restarts from the hit.
	if child.get_multiplayer_authority() == multiplayer.get_unique_id():
		child.take_damage(amount, 0)
	elif multiplayer.get_peers().has(child.get_multiplayer_authority()):
		child.rpc_id(child.get_multiplayer_authority(), "take_damage", amount, 0)


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
	_do_spawn(multiplayer.get_unique_id(), GameData.player_name, GameData.color_index, GameData.helmet, GameData.team_pref)


func _announce_ready() -> void:
	if _ready_announced:
		return
	_ready_announced = true
	if multiplayer.is_server():
		# The host spawned itself directly (_spawn_self). Asking
		# itself over RPC is not allowed (it only logs an error),
		# and request_spawn is idempotent anyway.
		return
	rpc_id(1, "request_spawn", multiplayer.get_unique_id(), GameData.player_name, GameData.color_index, GameData.helmet, GameData.BUILD_VERSION, GameData.team_pref)
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


func _do_spawn(pid: int, pname: String, color_idx: int, helmet_style: int, team_pref: int = -1) -> void:
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
	if game_mode == 1 or game_mode == 4:
		# QA-078: honour the lobby team pick when that team still
		# has room (max 6 per team); otherwise fall back to the
		# old alternating assignment. QA-112 (v3.9): CTF (mode 4)
		# needs teams too — the old code only assigned them for
		# TDM, so CTF players spawned team -1 and the flag logic
		# (which checks child.team) never saw a RED or BLUE.
		if team_pref == 0 or team_pref == 1:
			var picked_count := 0
			for child in players_node.get_children():
				if child.team == team_pref:
					picked_count += 1
			if picked_count < 6:
				team = team_pref
		if team == -1:
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
func request_spawn(pid: int, pname: String, color_idx: int, helmet_style: int, version: String = "", team_pref: int = -1) -> void:
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
	_do_spawn(pid, pname, color_idx, helmet_style, team_pref)


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
# map skies (bright day ones as well as dark ones).
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
	# QA-122 (v3.11): health + jetpack bars redesigned — one clean
	# dark panel behind both bars (same gohud pill style as the
	# top-right), thicker bars, bigger numbers, so they read at a
	# glance and never fight the message area.
	var bars_panel := PanelContainer.new()
	bars_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	bars_panel.offset_left = 12
	bars_panel.offset_right = 300
	bars_panel.offset_top = 8
	bars_panel.offset_bottom = 80
	bars_panel.theme = GoUi.theme()
	var bars_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if bars_sb != null:
		var bars_dup := bars_sb.duplicate()
		if bars_dup is GoStyleBoxCut:
			(bars_dup as GoStyleBoxCut).bg_color = Color(0.03, 0.07, 0.13, 0.88)
			(bars_dup as GoStyleBoxCut).content_margin_left = 8
			(bars_dup as GoStyleBoxCut).content_margin_right = 8
			(bars_dup as GoStyleBoxCut).content_margin_top = 6
			(bars_dup as GoStyleBoxCut).content_margin_bottom = 6
		bars_panel.add_theme_stylebox_override("panel", bars_dup)
	hud.add_child(bars_panel)

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
	hp_bar.thickness = 28
	hp_bar.ease_seconds = 0.0
	hp_bar.segments = 0
	hp_bar.label_size = 18
	hp_bar.ink = UI_SUCCESS
	hp_bar.custom_minimum_size = Vector2(220, 26)
	hp_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hp_bar.set_values(100, 100, false)
	hp_row.add_child(hp_bar)

	var fuel_row := HBoxContainer.new()
	fuel_row.add_theme_constant_override("separation", 8)
	left.add_child(fuel_row)

	fuel_bar = GoBar.new()
	fuel_bar.label_text = "JETPACK"
	fuel_bar.readout = GoBar.Readout.VALUE
	fuel_bar.thickness = 20
	fuel_bar.ease_seconds = 0.0
	fuel_bar.segments = 0
	fuel_bar.label_size = 16
	fuel_bar.ink = UI_ACCENT
	fuel_bar.custom_minimum_size = Vector2(220, 18)
	fuel_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fuel_bar.set_values(PhysicsConfig.FUEL_MAX, PhysicsConfig.FUEL_MAX, false) # QA-132: full 405 tank
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
	# QA-079: slim K/D line, always visible under the score — the
	# v3.6 compact corner hid kills/deaths behind SCORE, so a
	# player could not glance at them mid-fight. One short line,
	# centred, no panel, no extra footprint.
	_kd_label = Label.new()
	_kd_label.text = "K 0 • D 0"
	_kd_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_kd_label.add_theme_font_size_override("font_size", 18)
	_outline_label(_kd_label)
	mid.add_child(_kd_label)
	# Phase 5 — visible centre-weapon timer (pinned Sniper/Rocket).
	_centre_label = Label.new()
	_centre_label.text = ""
	_centre_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_centre_label.add_theme_font_size_override("font_size", 16)
	_outline_label(_centre_label)
	mid.add_child(_centre_label)
	# QA-112 (v3.9): CTF flag status lines (Skyfall only — hidden
	# on every other map/mode). "⚑ RED: home / carried / dropped".
	for team in [0, 1]:
		var fl := Label.new()
		fl.text = ""
		fl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		fl.add_theme_font_size_override("font_size", 16)
		fl.add_theme_color_override("font_color", Color(0.95, 0.3, 0.25) if team == 0 else Color(0.25, 0.55, 0.95))
		_outline_label(fl)
		fl.visible = false
		mid.add_child(fl)
		_ctf_flag_labels.append(fl)
	# QA-119 (v3.11): power-up slots live in the TOP-RIGHT panel
	# (built below, under the ammo chip) — not in the centre-top
	# mid column any more. Tap a filled slot to activate it; the
	# active boost + time left shows under the row.
	# QA-114 (v3.9): comeback + random-event lines (Skyfall CTF).
	# Both teams see the same lines, so the catch-up help is never
	# a hidden buff and an event is never a surprise.
	_sf_comeback_label = Label.new()
	_sf_comeback_label.text = ""
	_sf_comeback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sf_comeback_label.add_theme_font_size_override("font_size", 16)
	_sf_comeback_label.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_outline_label(_sf_comeback_label)
	_sf_comeback_label.visible = false
	mid.add_child(_sf_comeback_label)
	_sf_event_label = Label.new()
	_sf_event_label.text = ""
	_sf_event_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sf_event_label.add_theme_font_size_override("font_size", 16)
	_sf_event_label.add_theme_color_override("font_color", Color(0.6, 0.9, 1.0))
	_outline_label(_sf_event_label)
	_sf_event_label.visible = false
	mid.add_child(_sf_event_label)

	# QA-067 (v3.6) — COMPACT TOP-RIGHT. The v3.5 QA-057 panel was
	# 284x268 px of always-on stats and the user said it BLOCKS THE
	# SCREEN during play. Now only two 56 px icon buttons live in
	# this corner (SCORE + pause, gohud GoIconButtons in a slim
	# pill), and the stats hide behind SCORE: Kills / Deaths /
	# Players are NOT on screen any more — tap SCORE and the
	# scoreboard shows them (same rows as before, sorted by kills).
	# Weapon + ammo and grenades stay visible as ONE slim line
	# under the pill: they are live combat info, not stats (the
	# reload state — "Rifle - reloading 47%" — only ever showed
	# there, and the simple reload button (QA-070) has no other
	# readout). Total top-right footprint is now ~348x94 px
	# (pill 184x56 + one 30 px ammo line) instead of 284x268 —
	# the centre of the screen and the kill-feed area stay clear.
	# Both buttons work exactly as before (SCORE toggles the
	# scoreboard, pause toggles the pause menu); _topright_btn_row
	# still holds them, so _build_touch_controls and
	# is_hud_control_pos need no changes.
	var topright_pill := PanelContainer.new()
	topright_pill.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	topright_pill.offset_left = -196
	topright_pill.offset_right = -12
	topright_pill.offset_top = 12
	topright_pill.offset_bottom = 68
	topright_pill.theme = GoUi.theme()
	var pill_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if pill_sb != null:
		var pill_dup := pill_sb.duplicate()
		if pill_dup is GoStyleBoxCut:
			(pill_dup as GoStyleBoxCut).bg_color = Color(0.03, 0.07, 0.13, 0.88)
			(pill_dup as GoStyleBoxCut).content_margin_left = 8
			(pill_dup as GoStyleBoxCut).content_margin_right = 8
			(pill_dup as GoStyleBoxCut).content_margin_top = 0
			(pill_dup as GoStyleBoxCut).content_margin_bottom = 0
		topright_pill.add_theme_stylebox_override("panel", pill_dup)
	hud.add_child(topright_pill)

	# Button row: SCORE + pause land here from _build_touch_controls.
	_topright_btn_row = HBoxContainer.new()
	_topright_btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_topright_btn_row.add_theme_constant_override("separation", 8)
	topright_pill.add_child(_topright_btn_row)

	# Slim ammo line under the pill: weapon icon + "Rifle 30/90"
	# + grenades. One row, ~30 px tall, translucent so the map
	# reads through faintly but the text stays readable.
	var ammo_chip := PanelContainer.new()
	ammo_chip.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	ammo_chip.offset_left = -360
	ammo_chip.offset_right = -12
	ammo_chip.offset_top = 76
	ammo_chip.offset_bottom = 106
	var ammo_sb := StyleBoxFlat.new()
	ammo_sb.bg_color = Color(0.03, 0.07, 0.13, 0.75)
	ammo_sb.set_corner_radius_all(8)
	ammo_sb.content_margin_left = 10
	ammo_sb.content_margin_right = 10
	ammo_sb.content_margin_top = 2
	ammo_sb.content_margin_bottom = 2
	ammo_chip.add_theme_stylebox_override("panel", ammo_sb)
	hud.add_child(ammo_chip)
	var ammo_row := HBoxContainer.new()
	ammo_row.alignment = BoxContainer.ALIGNMENT_END
	ammo_row.add_theme_constant_override("separation", 8)
	ammo_chip.add_child(ammo_row)

	# QA-119 (v3.11) + QA-130: power-up slots — TOP-RIGHT, a bit
	# down from the top edge (below the ammo chip, y114), so they
	# clear the SCORE/pause pill, the ammo chip, the message area,
	# the health/jetpack bars and the height bar at both
	# resolutions. Same gohud pill style as the top-right pill:
	# dark navy, rounded, translucent. 3 plain 56 px buttons —
	# empty shows the numbered slot background, filled shows the
	# power-up icon; tap to activate. The active boost + time left
	# shows under the row.
	_sf_slot_panel = PanelContainer.new()
	_sf_slot_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_sf_slot_panel.offset_left = -360
	_sf_slot_panel.offset_right = -12
	_sf_slot_panel.offset_top = 114
	_sf_slot_panel.offset_bottom = 206
	_sf_slot_panel.theme = GoUi.theme()
	var slot_sb := GoUi.theme().get_stylebox("panel", "PanelContainer")
	if slot_sb != null:
		var slot_dup := slot_sb.duplicate()
		if slot_dup is GoStyleBoxCut:
			(slot_dup as GoStyleBoxCut).bg_color = Color(0.03, 0.07, 0.13, 0.88)
			(slot_dup as GoStyleBoxCut).content_margin_left = 8
			(slot_dup as GoStyleBoxCut).content_margin_right = 8
			(slot_dup as GoStyleBoxCut).content_margin_top = 6
			(slot_dup as GoStyleBoxCut).content_margin_bottom = 6
		_sf_slot_panel.add_theme_stylebox_override("panel", slot_dup)
	_sf_slot_panel.visible = false
	hud.add_child(_sf_slot_panel)
	var slot_box := VBoxContainer.new()
	slot_box.add_theme_constant_override("separation", 4)
	_sf_slot_panel.add_child(slot_box)
	var slot_row := HBoxContainer.new()
	slot_row.alignment = BoxContainer.ALIGNMENT_CENTER
	slot_row.add_theme_constant_override("separation", 8)
	slot_box.add_child(slot_row)
	_sf_slot_row = slot_row
	for i in 3:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(56, 56)
		btn.expand_icon = true
		btn.icon = SF_TEX_SLOT[i]
		_style_hud_button(btn)
		btn.pressed.connect(_on_slot_pressed.bind(i))
		slot_row.add_child(btn)
		_sf_slot_buttons.append(btn)
	_sf_active_boost_label = Label.new()
	_sf_active_boost_label.text = ""
	_sf_active_boost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sf_active_boost_label.add_theme_font_size_override("font_size", 16)
	_sf_active_boost_label.add_theme_color_override("font_color", Color(0.55, 0.9, 1.0))
	_outline_label(_sf_active_boost_label)
	_sf_active_boost_label.visible = false
	slot_box.add_child(_sf_active_boost_label)

	# Kills / Deaths / Players are HIDDEN behind SCORE in v3.6 —
	# the labels stay alive (_update_hud still writes them every
	# frame, and the scoreboard reads the same player data) but
	# their container is invisible, so nothing draws on screen.
	var hidden_stats := VBoxContainer.new()
	hidden_stats.visible = false
	hud.add_child(hidden_stats)

	kills_label = Label.new()
	kills_label.text = "Kills: 0"
	kills_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	kills_label.add_theme_font_size_override("font_size", 24)
	_outline_label(kills_label)
	hidden_stats.add_child(kills_label)

	deaths_label = Label.new()
	deaths_label.text = "Deaths: 0"
	deaths_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	deaths_label.add_theme_font_size_override("font_size", 18)
	_outline_label(deaths_label)
	hidden_stats.add_child(deaths_label)

	players_label = Label.new()
	players_label.text = "Players: 1/%d" % max_players # v3.4: room max, not the 12-player cap — the HUD must agree with the lobby ("1/4" in a 4-player room, "2/8" in the default 8-player room)
	players_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	players_label.add_theme_font_size_override("font_size", 20)
	_outline_label(players_label)
	hidden_stats.add_child(players_label)

	weapon_icon = TextureRect.new()
	weapon_icon.custom_minimum_size = Vector2(48, 20)
	weapon_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	weapon_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ammo_row.add_child(weapon_icon)
	weapon_label = Label.new()
	weapon_label.text = "Rifle 30"
	weapon_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	weapon_label.add_theme_font_size_override("font_size", 18)
	_outline_label(weapon_label)
	ammo_row.add_child(weapon_label)

	var ammo_sep := Label.new()
	ammo_sep.text = "•"
	ammo_sep.add_theme_font_size_override("font_size", 18)
	_outline_label(ammo_sep)
	ammo_row.add_child(ammo_sep)

	grenade_label = Label.new()
	grenade_label.text = "Grenades: 2"
	grenade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	grenade_label.add_theme_font_size_override("font_size", 18)
	_outline_label(grenade_label)
	ammo_row.add_child(grenade_label)

	# Phase 4: FPS counter (settings toggle, off by default) —
	# v3.6: it sits under the ammo line, not inside a panel, and
	# _update_hud still turns it on/off from GameData.show_fps.
	fps_label = Label.new()
	fps_label.text = "FPS: --"
	fps_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	fps_label.offset_left = -212
	fps_label.offset_right = -12
	fps_label.offset_top = 112
	fps_label.offset_bottom = 136
	fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	fps_label.add_theme_font_size_override("font_size", 16)
	_outline_label(fps_label)
	fps_label.visible = GameData.show_fps
	hud.add_child(fps_label)

	# QA-073: dev-only network-stats panel (spec §7). Hidden by
	# default — _update_net_stats fills it 4x/s only while visible,
	# and nothing in normal play ever turns it on. Top-left under
	# the kill feed (y 208), small text, no panel, no touch target.
	_net_stats_label = Label.new()
	_net_stats_label.text = "NET (dev)"
	_net_stats_label.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_net_stats_label.position = Vector2(16, 208)
	_net_stats_label.size = Vector2(460, 120)
	_net_stats_label.add_theme_font_size_override("font_size", 14)
	_outline_label(_net_stats_label)
	_net_stats_label.visible = _net_stats_visible
	hud.add_child(_net_stats_label)

	message_label = Label.new()
	message_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	# QA-034: offset_top was 96 — the centre-weapon label (3rd row
	# of the top bar, bottom ~y108) overlapped the 24 px message
	# ("Waiting for other players...") on every solo match start.
	# 116 clears it with room to spare; the kill feed lives at the
	# top-left, so the centred message never collides with it.
	# QA-079: the top bar grew a 4th row (the K/D line), so the
	# centre label's bottom is now ~y130 — 116 would overlap it
	# again. 140 clears the taller stack.
	# QA-114 (v3.9): the top bar grew a 5th row on Skyfall (the
	# 3 power-up slots, bottom ~y175) — 140 now overlaps the
	# slots. 185 clears the full 5-row stack.
	message_label.offset_top = 185
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
	_kill_feed_list.position = Vector2(16, 132)
	_kill_feed_list.add_theme_constant_override("separation", 4)
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

	# QA-114 (v3.9): vertical HUD — the height bar (Skyfall only).
	# A live tower map on the left edge: every player's height as
	# a dot, team pings as gold diamonds, level ticks, route legend.
	_build_height_bar()
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


var _sf_height_bar: Control # QA-114 (v3.9): vertical HUD height bar (Skyfall only)
var _sf_height_dots: Array = [] # QA-114: 12 player dots on the height bar
var _sf_height_ping_dots: Array = [] # QA-114: 4 ping dots on the height bar
var _sf_comeback_label: Label # QA-114 (v3.9): comeback-help line under the score
var _sf_event_label: Label # QA-114 (v3.9): random-event / storm line under the score


func _build_height_bar() -> void:
	# QA-114 (v3.9): VERTICAL HUD — a live tower map on the left
	# edge (Skyfall only, hidden elsewhere). 360 px tall for the
	# 10800 px tower (QA-123): bar y = 360 * world_y / 10800
	# (summit at the top, base at the bottom). Dots: white = you,
	# red/blue = teams, gold diamonds = team pings. Level ticks
	# L1-L6 + the colour-coded route legend underneath.
	# Top-anchored BELOW the kill feed (the feed sits at y108 and
	# stacks up to 4 chips, bottom ~y228) — the old centre anchor
	# put the bar at y~100 at 720p, so feed chips drew over it.
	_sf_height_bar = Control.new()
	_sf_height_bar.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sf_height_bar.position = Vector2(12, 264)
	_sf_height_bar.size = Vector2(100, 444)
	_sf_height_bar.visible = false
	# QA-118 (v3.9 fix round): the bar is THINNER — the bg panel
	# was 56 px wide, now 34 px (~60%), the user asked for it.
	# Dots re-centred (34/2 - 6 = 11), level ticks moved to x40.
	hud.add_child(_sf_height_bar)
	var title := Label.new()
	title.text = "HEIGHT"
	title.position = Vector2(0, -24)
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	_sf_height_bar.add_child(title)
	var bg := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.07, 0.12, 0.75)
	sb.border_color = Color(0.35, 0.4, 0.5, 0.8)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(6)
	bg.add_theme_stylebox_override("panel", sb)
	bg.position = Vector2(0, 0)
	bg.size = Vector2(34, 360)
	_sf_height_bar.add_child(bg)
	# Level ticks: L1-L6 at their level centres (QA-123: 1800 px levels).
	for lvl in [1, 2, 3, 4, 5, 6]:
		var cy := 10800.0 - (float(lvl) - 0.5) * 1800.0 # centre y of the level
		var tl := Label.new()
		tl.text = "L%d" % lvl
		tl.position = Vector2(40, 360.0 * cy / 10800.0 - 10.0)
		tl.add_theme_font_size_override("font_size", 16)
		tl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
		_sf_height_bar.add_child(tl)
	# Player dots (12 = room max) + ping dots (4).
	for i in 12:
		var dot := ColorRect.new()
		dot.size = Vector2(12, 12)
		dot.position = Vector2(11, 0)
		dot.visible = false
		_sf_height_bar.add_child(dot)
		_sf_height_dots.append(dot)
	for i in 4:
		var pdot := ColorRect.new()
		pdot.size = Vector2(12, 12)
		pdot.position = Vector2(11, 0)
		pdot.pivot_offset = Vector2(6, 6)
		pdot.rotation = PI / 4.0
		pdot.color = Color(1.0, 0.8, 0.2)
		pdot.visible = false
		_sf_height_bar.add_child(pdot)
		_sf_height_ping_dots.append(pdot)
	# Route legend: same colours as the platform strips.
	var legend := VBoxContainer.new()
	legend.position = Vector2(0, 372) # below the 360 px bar
	legend.add_theme_constant_override("separation", 4)
	_sf_height_bar.add_child(legend)
	for ri in 3:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var sw := ColorRect.new()
		sw.color = SF_ROUTE_COLORS[ri]
		sw.custom_minimum_size = Vector2(14, 14)
		row.add_child(sw)
		var rl := Label.new()
		rl.text = SF_ROUTE_NAMES[ri]
		rl.add_theme_font_size_override("font_size", 15)
		rl.add_theme_color_override("font_color", SF_ROUTE_COLORS[ri])
		row.add_child(rl)
		legend.add_child(row)
	# QA-117 (v3.9 fix round): the bar is display-only — it must
	# NEVER eat touches. Its old 170 px-wide rect overlapped the
	# move stick (x90-240) and swallowed every press on the stick's
	# left/centre, so pushing LEFT on Skyfall did nothing on a real
	# phone (the sim calls _on_touch_press directly and never saw
	# it). A parent's IGNORE does NOT cascade to children — every
	# Control in the subtree (Panel, Labels, ColorRects, legend
	# containers) defaults to STOP, so set IGNORE on all of them.
	var _hb_stack: Array = [_sf_height_bar]
	while not _hb_stack.is_empty():
		var _hb_n: Node = _hb_stack.pop_back()
		if _hb_n is Control:
			(_hb_n as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		for _hb_ch in _hb_n.get_children():
			_hb_stack.append(_hb_ch)


func _build_scoreboard() -> void:
	# QA-113 (v3.9): wider panel, bigger title, breathing room —
	# the old 420 px panel with 30 px title cramped 10-player rows.
	scoreboard_panel = PanelContainer.new()
	scoreboard_panel.theme = GoUi.theme()
	scoreboard_panel.custom_minimum_size = Vector2(560, 0)
	scoreboard_panel.add_theme_stylebox_override("panel", _panel_style())
	scoreboard_panel.visible = false
	_dialog_wrap().add_child(scoreboard_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	scoreboard_panel.add_child(box)
	var title := Label.new()
	title.text = "SCOREBOARD"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UI_FONT)
	box.add_child(title)
	var sub := Label.new()
	sub.text = "%s  •  %s" % [GameData.MODE_NAMES[game_mode], GameData.MAP_NAMES[map_id]]
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(sub)
	scoreboard_list = VBoxContainer.new()
	scoreboard_list.add_theme_constant_override("separation", 6)
	box.add_child(scoreboard_list)
	var close_btn := Button.new()
	close_btn.text = "Close"
	_style_hud_button(close_btn)
	close_btn.custom_minimum_size = Vector2(0, 56)
	close_btn.pressed.connect(func() -> void: scoreboard_panel.visible = false)
	box.add_child(close_btn)


func _build_pause_menu() -> void:
	# QA-113 (v3.9): same clean, spacious layout as the scoreboard —
	# wider panel, section labels, slider value labels, match info
	# line, 56 px buttons. Layout only, no logic changes.
	pause_panel = PanelContainer.new()
	pause_panel.theme = GoUi.theme()
	pause_panel.custom_minimum_size = Vector2(520, 0)
	pause_panel.add_theme_stylebox_override("panel", _panel_style())
	pause_panel.visible = false
	pause_panel.process_mode = Node.PROCESS_MODE_ALWAYS
	_dialog_wrap().add_child(pause_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	pause_panel.add_child(box)
	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", FONT_TITLE)
	title.add_theme_font_size_override("font_size", 36)
	title.add_theme_color_override("font_color", UI_FONT)
	box.add_child(title)
	_pause_info_label = Label.new()
	_pause_info_label.text = ""
	_pause_info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_info_label.add_theme_font_size_override("font_size", 18)
	_pause_info_label.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	_pause_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_pause_info_label)
	var resume_btn := Button.new()
	resume_btn.text = "Resume"
	_style_hud_button(resume_btn, true)
	resume_btn.custom_minimum_size = Vector2(0, 56)
	resume_btn.pressed.connect(_toggle_pause)
	box.add_child(resume_btn)
	# Phase 4: weapon info — damage / fire rate / magazine / reload
	# per weapon, straight from weapons.gd (read-only display).
	var weapons_btn := Button.new()
	weapons_btn.text = "Weapons"
	_style_hud_button(weapons_btn)
	weapons_btn.custom_minimum_size = Vector2(0, 56)
	weapons_btn.pressed.connect(func() -> void: _show_weapon_panel(true))
	box.add_child(weapons_btn)
	var sound_lbl := Label.new()
	sound_lbl.text = "SOUND"
	sound_lbl.add_theme_font_size_override("font_size", 18)
	sound_lbl.add_theme_color_override("font_color", Color(0.62, 0.66, 0.72))
	box.add_child(sound_lbl)
	var sfx_row := HBoxContainer.new()
	sfx_row.add_theme_constant_override("separation", 8)
	box.add_child(sfx_row)
	var sfx_lbl := Label.new()
	sfx_lbl.text = "Sound"
	sfx_lbl.custom_minimum_size = Vector2(70, 0)
	sfx_row.add_child(sfx_lbl)
	var sfx_slider := HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	sfx_slider.value = GameData.sfx_volume
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	sfx_row.add_child(sfx_slider)
	_sfx_value_label = Label.new()
	_sfx_value_label.text = "%d%%" % int(GameData.sfx_volume * 100.0)
	_sfx_value_label.custom_minimum_size = Vector2(52, 0)
	_sfx_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_row.add_child(_sfx_value_label)
	var mus_row := HBoxContainer.new()
	mus_row.add_theme_constant_override("separation", 8)
	box.add_child(mus_row)
	var mus_lbl := Label.new()
	mus_lbl.text = "Music"
	mus_lbl.custom_minimum_size = Vector2(70, 0)
	mus_row.add_child(mus_lbl)
	var mus_slider := HSlider.new()
	mus_slider.min_value = 0.0
	mus_slider.max_value = 1.0
	mus_slider.step = 0.05
	mus_slider.value = GameData.music_volume
	mus_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mus_slider.value_changed.connect(_on_music_volume_changed)
	mus_row.add_child(mus_slider)
	_music_value_label = Label.new()
	_music_value_label.text = "%d%%" % int(GameData.music_volume * 100.0)
	_music_value_label.custom_minimum_size = Vector2(52, 0)
	_music_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	mus_row.add_child(_music_value_label)
	var leave_btn := Button.new()
	leave_btn.text = "Leave Match"
	_style_hud_button(leave_btn)
	leave_btn.custom_minimum_size = Vector2(0, 56)
	leave_btn.pressed.connect(_on_leave_pressed)
	box.add_child(leave_btn)


func _build_end_screen() -> void:
	# QA-113 (v3.9): wider panel, bigger title, more breathing room.
	end_panel = PanelContainer.new()
	end_panel.theme = GoUi.theme()
	end_panel.custom_minimum_size = Vector2(560, 0)
	end_panel.add_theme_stylebox_override("panel", _panel_style())
	end_panel.visible = false
	_dialog_wrap().add_child(end_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	end_panel.add_child(box)
	_end_box = box
	end_title = Label.new()
	end_title.text = ""
	end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	end_title.add_theme_font_override("font", FONT_TITLE)
	end_title.add_theme_font_size_override("font_size", 34)
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
	# QA-060: this used to say "Back to Lobby" but it goes to the
	# main menu (_on_leave_pressed changes scene to main.tscn).
	back_btn.text = "Back to Menu"
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
	# QA-060: close the network resources explicitly instead of
	# relying on the old peer's refcount to drop. A dropped-but-open
	# ENet peer can keep UDP 7777 bound, so the next host attempt in
	# the same process fails with "Couldn't create an ENet host".
	_stop_broadcast()
	var old_peer := multiplayer.multiplayer_peer
	if old_peer is ENetMultiplayerPeer:
		(old_peer as ENetMultiplayerPeer).close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	get_tree().change_scene_to_file("res://main.tscn")


func _on_rematch_pressed() -> void:
	if multiplayer.is_server():
		rpc("rematch_remote")


@rpc("any_peer", "call_local")
func rematch_remote() -> void:
	get_tree().paused = false
	# QA-060: the reload is synchronous — the rest of THIS frame's
	# _process would otherwise keep running on this (now tree-less)
	# instance, where `multiplayer` is null and every is_server()
	# call in the update tail throws a script error (5 of them, at
	# the rematch boundary). Same guard as _on_leave_pressed.
	_leaving = true
	get_tree().reload_current_scene()


func _on_sfx_volume_changed(v: float) -> void:
	GameData.sfx_volume = v
	GameData.save_settings()
	if _sfx_value_label != null:
		_sfx_value_label.text = "%d%%" % int(v * 100.0)
	if audio != null:
		audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _on_music_volume_changed(v: float) -> void:
	GameData.music_volume = v
	GameData.save_settings()
	if _music_value_label != null:
		_music_value_label.text = "%d%%" % int(v * 100.0)
	if audio != null:
		audio.set_volumes(GameData.sfx_volume, GameData.music_volume)


func _toggle_pause() -> void:
	if match_over:
		return
	get_tree().paused = not get_tree().paused
	pause_panel.visible = get_tree().paused
	if get_tree().paused:
		# QA-113 (v3.9): match info line — map, mode, time left.
		if _pause_info_label != null:
			var t := int(maxf(0.0, _time_left))
			_pause_info_label.text = "%s  •  %s  •  %d:%02d left" % [GameData.MAP_NAMES[map_id], GameData.MODE_NAMES[game_mode], t / 60, t % 60]
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
	# QA-070 (v3.6): SIMPLE buttons, not fancy (user, 2026-11-19
	# ~18:13 — extends the v3.5 "just have plain buttons" rule from
	# grenade/reload to the weapon-switch button too). Plain flat
	# buttons with a clear text label, no gohud styling, no rings,
	# no badges, no icons, no effects, no decorations. Same column,
	# same positions, same 72 px touch targets, same handlers —
	# only the look changed. Throw behaviour unchanged.
	grenade_button = Button.new()
	grenade_button.text = "GRENADE"
	_style_simple_button(grenade_button)
	grenade_button.custom_minimum_size = Vector2(72, 72)
	grenade_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	grenade_button.position = Vector2(-451, -260)
	grenade_button.pressed.connect(_on_grenade_pressed)
	hud.add_child(grenade_button)

	switch_button = Button.new()
	# QA-070: simple like the others — text label, no icon. The
	# current weapon already shows (icon + name) in the top-right
	# HUD panel. Behaviour unchanged.
	switch_button.text = "WEAPON"
	_style_simple_button(switch_button)
	switch_button.custom_minimum_size = Vector2(72, 72)
	switch_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	switch_button.position = Vector2(-451, -180)
	switch_button.pressed.connect(_on_switch_pressed)
	hud.add_child(switch_button)

	# QA-070: simple reload button — text label, no icon, no ring.
	# Ammo count stays in the weapon label. Behaviour unchanged.
	reload_button = Button.new()
	reload_button.text = "RELOAD"
	_style_simple_button(reload_button)
	reload_button.custom_minimum_size = Vector2(72, 72)
	reload_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	reload_button.position = Vector2(-451, -340)
	reload_button.pressed.connect(_on_reload_pressed)
	hud.add_child(reload_button)

	# QA-105 (v3.8): SCOPE button — plain and simple like the other
	# three, same column, directly above RELOAD. Only visible with
	# the sniper or rifle equipped (see _update_scope_button).
	# It toggles the scope zoom on the local player; it never
	# touches the right stick, so aim + fire (QA-049) is
	# unaffected. 72 px touch target like the others.
	scope_button = Button.new()
	scope_button.text = "SCOPE"
	_style_simple_button(scope_button)
	scope_button.custom_minimum_size = Vector2(72, 72)
	scope_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	scope_button.position = Vector2(-451, -420)
	scope_button.pressed.connect(_on_scope_pressed)
	hud.add_child(scope_button)

	# QA-114 (v3.9): PING button — plain and simple like the other
	# four, same column, directly above SCOPE. Pings the local
	# player's position for their TEAM (a gold diamond marker in
	# the world + a dot on the height bar + a feed line), 3 s
	# cooldown so it cannot be spammed. Skyfall only — hidden on
	# other maps (see _update_scope_button's neighbour, updated in
	# _update_hud).
	ping_button = Button.new()
	ping_button.text = "PING"
	_style_simple_button(ping_button)
	ping_button.custom_minimum_size = Vector2(72, 72)
	ping_button.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	ping_button.position = Vector2(-451, -500)
	ping_button.pressed.connect(_on_ping_pressed)
	hud.add_child(ping_button)

	# QA-067 (v3.6): the buttons are gohud GoIconButtons now —
	# icon-only (chart = scoreboard, pause = pause), 56x56 px each,
	# sitting in the slim top-right pill from _build_hud. The old
	# text buttons ("SCORE" 96 px + "II") needed the big QA-057
	# panel around them; the icons are the whole point of the
	# compact corner. touch_peers links the two side by side, so
	# one's widened hit area never swallows the other's tap
	# (GoIconButton doc). keyboard_focus is OFF: a clicked HUD
	# button must not keep keyboard focus, or Space/Enter would
	# re-press it mid-match instead of reaching the game.
	# Handlers unchanged (_on_score_pressed / _toggle_pause).
	score_button = GoIconButton.new()
	(score_button as GoIconButton).visual_size = 56
	(score_button as GoIconButton).icon_name = GoIconSet.CHART
	(score_button as GoIconButton).keyboard_focus = false
	score_button.focus_mode = Control.FOCUS_NONE
	score_button.tooltip_text = "Scoreboard"
	score_button.pressed.connect(_on_score_pressed)
	_topright_btn_row.add_child(score_button)

	pause_button = GoIconButton.new()
	(pause_button as GoIconButton).visual_size = 56
	(pause_button as GoIconButton).icon_name = GoIconSet.PAUSE
	(pause_button as GoIconButton).keyboard_focus = false
	pause_button.focus_mode = Control.FOCUS_NONE
	pause_button.tooltip_text = "Pause"
	pause_button.pressed.connect(_toggle_pause)
	_topright_btn_row.add_child(pause_button)
	(score_button as GoIconButton).touch_peers = [pause_button]
	(pause_button as GoIconButton).touch_peers = [score_button]


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


# QA-070 (v3.6): SIMPLE button style — plain flat buttons, not
# fancy. One flat dark fill, no border, no accent colour, no
# hover glow, no pressed effect beyond a slightly lighter fill,
# no focus ring. The label (set at creation) is the whole button:
# clear text, readable at a glance. Replaces the v3.5 round style
# (_style_round_button, deleted with its code-drawn icons) at the
# user's 2026-11-19 ~18:13 request.
func _style_simple_button(b: Button) -> void:
	for kind in ["normal", "hover", "pressed", "disabled"]:
		b.remove_theme_stylebox_override(kind)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.add_theme_font_override("font", FONT_BODY_SEMIBOLD)
	b.add_theme_font_size_override("font_size", 15)
	b.add_theme_color_override("font_color", UI_FONT)
	b.add_theme_color_override("font_hover_color", UI_FONT)
	b.add_theme_color_override("font_pressed_color", UI_FONT)
	b.add_theme_color_override("font_disabled_color", Color(0.55, 0.6, 0.68))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.12, 0.18)
	normal.set_corner_radius_all(6)
	b.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.13, 0.17, 0.24)
	hover.set_corner_radius_all(6)
	b.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(0.16, 0.21, 0.29)
	pressed.set_corner_radius_all(6)
	b.add_theme_stylebox_override("pressed", pressed)
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.09, 0.12, 0.18, 0.55)
	disabled.set_corner_radius_all(6)
	b.add_theme_stylebox_override("disabled", disabled)


# QA-070: grenade button state, refreshed every HUD frame from the
# local player. Simple button, no loading visuals — disabled only
# when the count is 0 (standard Button disabled look). The count is
# the plain "Grenades: N" text in the top-right HUD. Throw
# behaviour is untouched — player.gd still owns the 0.5 s cooldown
# and the count.
func _update_grenade_button(lp) -> void:
	if grenade_button == null or lp == null:
		return
	grenade_button.disabled = int(lp.grenades) <= 0
	# QA-079: the count rides on the button itself, so the thumb
	# sees it without looking at the top-right ammo line. Two
	# lines — "GRENADE (2)" on one line is wider than the 72 px
	# button and would clip.
	grenade_button.text = "GRENADE\n(%d)" % int(lp.grenades)


# QA-070 (v3.6): simple button, no loading visuals. Disabled
# while reloading or when the mag is already full — same rule as
# the old rectangular button.
func _update_reload_button(lp) -> void:
	if reload_button == null or lp == null:
		return
	var mag_total: int = int(lp.WEAPONS[lp.weapon]["mag"])
	reload_button.disabled = lp.reloading or lp.mag_ammo >= mag_total


# QA-105 (v3.8): SCOPE button state, refreshed every HUD frame.
# Only the sniper (zoom 2.0x) and rifle (zoom 1.5x) have scopes —
# the button hides for SMG / shotgun / pistol / rocket. A check
# mark shows when the scope is on.
func _update_scope_button(lp) -> void:
	if scope_button == null:
		return
	# QA-113 (v3.9): never over a dialog — the button drew over the
	# pause/scoreboard/end panels. _set_touch_controls_visible
	# hides it, but this runs every frame and would show it again.
	var dialog_open := get_tree().paused or (scoreboard_panel != null and scoreboard_panel.visible) or (end_panel != null and end_panel.visible)
	if lp == null or not lp.alive or dialog_open:
		scope_button.visible = false
	else:
		var can_scope: bool = int(lp.weapon) == 0 or int(lp.weapon) == 3
		scope_button.visible = can_scope
		if can_scope:
			scope_button.text = "✓ SCOPE" if bool(lp.scoped) else "SCOPE"
	# QA-114 (v3.9): PING is Skyfall-only, and only for a living
	# local player.
	if ping_button != null:
		ping_button.visible = map_id == GameData.SKYFALL_MAP_ID and lp != null and lp.alive and not match_over and not dialog_open


func _on_switch_pressed() -> void:
	var lp = _get_local_player()
	if lp != null:
		lp.switch_weapon()


func _on_scope_pressed() -> void:
	# QA-105 (v3.8): toggle the scope on the local player. Only the
	# sniper (2.0x) and rifle (1.5x) have scopes; the button hides
	# for other weapons, so this guard is belt-and-braces.
	var lp = _get_local_player()
	if lp == null or not lp.alive:
		return
	if lp.weapon != 0 and lp.weapon != 3:
		return
	lp.scoped = not lp.scoped


func _on_ping_pressed() -> void:
	# QA-114 (v3.9): ping the local player's position for their
	# team. Skyfall only, 3 s cooldown, dead players cannot ping.
	if map_id != GameData.SKYFALL_MAP_ID or match_over or _countdown_active:
		return
	var lp = _get_local_player()
	if lp == null or not lp.alive:
		return
	if _sf_ping_cooldown > 0.0:
		return
	_sf_ping_cooldown = 3.0
	var team := int(lp.team) if "team" in lp else -1
	rpc("ping_remote", lp.position, team, lp.player_name)


@rpc("any_peer", "call_local")
func ping_remote(pos: Vector2, team: int, pname: String) -> void:
	# A teammate's ping: a gold diamond in the world + a dot on the
	# height bar + a feed line, for 5 s. Enemy pings are never
	# shown (a ping only ever reaches its own team).
	if map_id != GameData.SKYFALL_MAP_ID:
		return
	var lp = _get_local_player()
	if lp == null:
		return
	var my_team := int(lp.team) if "team" in lp else -1
	if team != my_team:
		return
	var lvl := _sf_level_of(pos.y)
	var diamond := Polygon2D.new()
	diamond.polygon = PackedVector2Array([Vector2(0, -22), Vector2(16, 0), Vector2(0, 22), Vector2(-16, 0)])
	diamond.color = Color(1.0, 0.8, 0.2)
	diamond.position = pos + Vector2(0, -90)
	diamond.z_index = 50
	add_child(diamond)
	var plbl := Label.new()
	plbl.text = "⚑ %s (L%d)" % [pname, lvl]
	plbl.position = pos + Vector2(-60, -130)
	plbl.add_theme_font_size_override("font_size", 20)
	plbl.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	plbl.z_index = 50
	add_child(plbl)
	_sf_pings.append({"node": diamond, "label": plbl, "pos": pos, "timer": 5.0})
	_ctf_feed("⚑ %s pinged Level %d!" % [pname, lvl], Color(1.0, 0.8, 0.2))


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
		# QA-073: F3 toggles the dev-only net-stats panel (spec §7).
		# No other key touches it, and it is hidden by default.
		elif k.pressed and not k.echo and k.keycode == KEY_F3:
			toggle_net_stats()


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
	# QA-060: leaving by any path (leave, rematch reload, error
	# retry) must close the announcement sockets now, not when the
	# RefCounted sockets happen to drop.
	if what == NOTIFICATION_EXIT_TREE:
		_stop_broadcast()


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
	# QA-113 (v3.9): SCOPE (added v3.8) and PING (added v3.9) were
	# never in this list, so they drew over the pause/scoreboard
	# panels (the SCOPE button covered the K/D + ACC headers).
	# Hide them too — but never show them here: _update_hud owns
	# their visibility (scope only for sniper/rifle, ping
	# Skyfall-only) and restores them on the next frame.
	if not v:
		for c in [scope_button, ping_button]:
			if c != null:
				c.visible = false


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


func _physics_process(_delta: float) -> void:
	# QA-071b: a physics-time clock (seconds of physics, not wall
	# time) — the P01/P02 accel times are wall-clock measurements,
	# and the physics/wall ratio drifts between the two steps under
	# xvfb load (P02 read 0.31 vs 0.27 s, want >1.3x, although the
	# physics times are 0.20 vs 0.115 s = 1.74x). Measuring in
	# physics time makes the ratio load-independent.
	_phys_data["phys_clock"] = float(_phys_data.get("phys_clock", 0.0)) + _delta
	# QA-071b: t300 tracking at physics rate. Sampling it in
	# _update_physicstest (idle _process, ~5 Hz under llvmpipe)
	# quantizes the ground/air times to the idle frame period
	# (~0.2 s), hiding the 0.085 s physics difference between ground
	# (2600) and air (1500) accel — P02 read 0.30 vs 0.27 s (want
	# >1.3x) on map 10. Physics-rate sampling resolves the crossing
	# to one physics step. Test-only: it only reads velocity while
	# tracking is enabled, and changes no gameplay.
	if bool(_phys_data.get("track_t300", false)) and not _phys_data.has("t300"):
		var lp = _get_local_player()
		if lp != null and lp.velocity.x >= 300.0:
			_phys_data["t300"] = float(_phys_data.get("phys_clock", 0.0)) - float(_phys_data.get("t0_phys", 0.0))
	# QA-071b: min_y at physics rate too — the idle-rate sample missed the
	# brief tap-jump apex by a few px (P07b read 114 vs the hold-40 bound
	# of 113, a 1 px miss on a real 39 px cut).
	if bool(_phys_data.get("track_min_y", false)):
		var lp2 = _get_local_player()
		if lp2 != null:
			_phys_data["min_y"] = minf(float(_phys_data.get("min_y", 1e9)), lp2.position.y)
	# QA-074b: fastest vy sampled WHILE the jetpack is thrusting —
	# the jump's own -660 must not count, so samples are gated on
	# lp._jetpacking. Sampled here, at physics rate, not in
	# _update_physicstest: the ~5 Hz idle sample can miss a short
	# climb window entirely (same lesson as track_min_y above).
	if bool(_phys_data.get("track_min_vy_jet", false)):
		var lp3 = _get_local_player()
		if lp3 != null and lp3._jetpacking:
			_phys_data["min_vy_jet"] = minf(float(_phys_data.get("min_vy_jet", 0.0)), lp3.velocity.y)
	# QA-099 (v3.7): pad launch, ungated — the only upward force in
	# the pad step is the pad (no jump input), so a min vy below
	# -600 can only mean the pad fired.
	if bool(_phys_data.get("track_min_vy_pad", false)):
		var lp4 = _get_local_player()
		if lp4 != null:
			_phys_data["pad_min_vy"] = minf(float(_phys_data.get("pad_min_vy", 0.0)), lp4.velocity.y)


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
	elif _restart_test:
		_update_touch_state()
		_update_restarttest(delta)
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
	elif _v37_shots:
		_update_touch_state()
		_update_v37shots(delta)
	elif _v38_shots:
		_update_touch_state()
		_update_v38shots(delta)
	elif _glitch_shots:
		_update_touch_state()
		_update_glitchshots(delta)
	elif _map_shots:
		_update_touch_state()
		_update_mapshots(delta)
	elif _land_shots:
		_update_touch_state()
		_update_landshots(delta)
	elif _skyfall_shots:
		_update_touch_state()
		_update_skyfallshots(delta)
	else:
		_update_touch_state()
	# The flow test (or a button) may have started leaving mid-frame
	# — or a rematch reload may have detached this instance from the
	# tree (QA-060). Either way the update tail must not run: on a
	# detached instance `multiplayer` is null.
	if _leaving:
		return
	_update_countdown(delta)
	_update_kill_feed(delta)
	_update_hitmarker(delta)
	_update_death_watcher()
	_update_spectator(delta)
	_update_hud(delta)
	_update_net_stats(delta) # QA-073: dev-only panel, no-op while hidden
	_update_divergence_check(delta) # QA-073: host-only, no-op solo/offline
	_update_broadcast(delta)
	_update_pickup_spawn(delta)
	_update_join_timeout(delta)
	_retry_spawn_if_needed(delta)
	_update_match_timer(delta)
	_update_lava(delta)
	_update_skyfall(delta) # QA-112 (v3.9): CTF + mechanics, no-op off Skyfall


# QA-073: dev-only network-stats display (spec §7). Hidden by
# default; enabled with --net-stats or F3. The text refreshes 4x/s
# while visible and the function returns at once while hidden, so
# normal play pays nothing for it. RTT / packet loss come from the
# live ENet peer statistics (PEER_ROUND_TRIP_TIME is ms;
# PEER_PACKET_LOSS is scaled by PACKET_LOSS_SCALE = 65536); offline
# or solo they read "--". The rest comes from the first remote
# player's snapshot counters (player.gd get_net_stats): updates/s,
# buffer size, adaptive interpolation delay, extrapolation time,
# and the authoritative snapshot position vs the rendered position.
func set_net_stats_visible(v: bool) -> void:
	_net_stats_visible = v
	if _net_stats_label != null:
		_net_stats_label.visible = v
	if v:
		_net_stats_timer = 99.0 # refresh at once on show


func toggle_net_stats() -> void:
	set_net_stats_visible(not _net_stats_visible)


func _update_net_stats(delta: float) -> void:
	if _net_stats_label == null or not _net_stats_visible:
		return
	_net_stats_timer += delta
	if _net_stats_timer < 0.25:
		return
	_net_stats_timer = 0.0
	var fps := Engine.get_frames_per_second()
	var lp = _get_local_player()
	var local_txt := "(--, --)"
	if lp != null:
		local_txt = "(%d, %d)" % [int(lp.position.x), int(lp.position.y)]
	# ENet RTT / loss for the first connected peer, if any.
	var rtt_txt := "--"
	var loss_txt := "--"
	var mp = multiplayer.multiplayer_peer
	if mp is ENetMultiplayerPeer and not multiplayer.get_peers().is_empty():
		var first_peer: int = multiplayer.get_peers()[0]
		var epeer = (mp as ENetMultiplayerPeer).get_peer(first_peer)
		if epeer != null:
			rtt_txt = "%d ms" % int(epeer.get_statistic(ENetPacketPeer.PEER_ROUND_TRIP_TIME))
			loss_txt = "%.1f%%" % (float(epeer.get_statistic(ENetPacketPeer.PEER_PACKET_LOSS)) * 100.0 / 65536.0)
	var remote = null
	for child in players_node.get_children():
		if not child.is_local_player():
			remote = child
			break
	if remote == null:
		_net_stats_label.text = "NET (dev) — solo, no remote players\nFPS %d | RTT %s | loss %s\nlocal %s" % [fps, rtt_txt, loss_txt, local_txt]
		return
	var st: Dictionary = remote.get_net_stats()
	var auth_pos: Vector2 = st.get("auth_pos", Vector2.ZERO)
	_net_stats_label.text = "NET (dev) — peer %d\nFPS %d | RTT %s | loss %s\nsnap %.0f/s | lost %d dup %d ooo %d | recv %d\nbuf %d | delay %.0f ms | jitter %.0f ms | extrap %.0f ms | gap %.0f ms\nlocal %s | auth (%d, %d) | shown (%d, %d)" % [
		remote.peer_id, fps, rtt_txt, loss_txt,
		float(st.get("ups", 0.0)), int(st.get("lost", 0)), int(st.get("dup", 0)), int(st.get("ooo", 0)), int(st.get("recv", 0)),
		int(st.get("buf", 0)), float(st.get("delay_ms", 0.0)), float(st.get("jitter_ms", 0.0)),
		float(st.get("extrap_ms", 0.0)), float(st.get("gap_ms", 0.0)),
		local_txt, int(auth_pos.x), int(auth_pos.y),
		int(remote.position.x), int(remote.position.y)]


# QA-073: host-side divergence guard (spec §4, last resort). The
# host compares its rendered copy of each remote player against
# that player's newest snapshot: normal interpolation lag stays
# under ~60 px (100 ms delay x 350 px/s + clamp glide), so a gap
# over 300 px means the copy genuinely lost the client (e.g. a
# missed teleport snapshot). Only when the gap holds for 1 s AND
# the snapshot stream is still fresh (<0.2 s since the last one —
# a stale stream means the copy is dead-reckoning by design and a
# correction to an old snapshot would drag the client backwards)
# does the host RPC a correction to the client's own newest
# snapshot position. The client reconciles it (small = blend,
# large = snap) and ignores stale corrections by sequence.
func _update_divergence_check(delta: float) -> void:
	if not multiplayer.is_server():
		return
	if multiplayer.get_peers().is_empty():
		return
	_diverge_timer += delta
	if _diverge_timer < 0.5:
		return
	_diverge_timer = 0.0
	var now := Time.get_ticks_msec() / 1000.0
	for child in players_node.get_children():
		if child.is_local_player():
			continue
		var pid: int = child.peer_id
		var gap: float = child.position.distance_to(child.sync_position)
		if gap > 300.0:
			var t: float = float(_diverge_time.get(pid, 0.0)) + 0.5
			_diverge_time[pid] = t
			var last_gap: float = now - child._last_snap_receipt
			if t >= 1.0 and last_gap < 0.2:
				_diverge_corr_seq += 1
				child.rpc_id(pid, "apply_authoritative_correction", child.sync_position, child.sync_velocity, _diverge_corr_seq)
				_diverge_time[pid] = 0.0
		else:
			_diverge_time[pid] = 0.0


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
	elif game_mode == 4:
		# QA-112 (v3.9): CTF scores captures, not kills.
		score_label.text = "⚑ RED %d  -  %d BLUE" % [int(_ctf_scores.get(0, 0)), int(_ctf_scores.get(1, 0))]
	else:
		score_label.text = "First to %d kills" % kill_limit
	# QA-112 (v3.9): flag status + power-up slots (Skyfall only).
	_update_skyfall_hud()
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
	fuel_bar.set_values(lp.fuel, PhysicsConfig.FUEL_MAX, false) # QA-132: max is 405, not 100
	# QA-079: the bars change colour with the value, so a glance
	# reads the state without reading the number — HP green >
	# amber > red, fuel cyan > amber when nearly empty.
	hp_bar.ink = UI_SUCCESS if lp.health >= 50 else (UI_WARNING if lp.health >= 25 else UI_DANGER)
	fuel_bar.ink = UI_ACCENT if lp.fuel >= PhysicsConfig.FUEL_MAX * 0.3 else UI_WARNING # QA-132: 30% of the 405 tank
	kills_label.text = "Kills: %d" % lp.kills
	deaths_label.text = "Deaths: %d" % lp.deaths
	if _kd_label != null:
		_kd_label.text = "K %d • D %d" % [lp.kills, lp.deaths]
	weapon_icon.texture = WEAPON_ICONS[lp.weapon]
	var wname: String = lp.WEAPONS[lp.weapon]["name"]
	var mag_total: int = int(lp.WEAPONS[lp.weapon]["mag"])
	var res: int = lp.ammo_reserve()
	var res_txt := "∞" if res < 0 else str(res)
	if lp.reloading:
		weapon_label.text = "%s - reloading %d%%" % [wname, int(lp.reload_progress() * 100.0)]
	else:
		weapon_label.text = "%s %d/%s" % [wname, lp.mag_ammo, res_txt]
	# QA-079: the ammo line turns red when the magazine is nearly
	# empty, so a low mag reads at a glance mid-fight.
	weapon_label.add_theme_color_override("font_color", UI_DANGER if lp.mag_ammo <= maxi(1, mag_total / 4) else UI_FONT)
	_update_reload_button(lp) # QA-070: simple reload button (text label, no ring)
	_update_scope_button(lp) # QA-105: SCOPE toggle, sniper/rifle only
	grenade_label.text = "Grenades: %d" % lp.grenades
	_update_grenade_button(lp) # QA-070: simple grenade button (text label, no ring/badge)
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


func _update_skyfall_hud() -> void:
	# QA-112 (v3.9): CTF flag status + power-up slots. Everything
	# here hides itself off Skyfall / outside CTF.
	var is_sf := map_id == GameData.SKYFALL_MAP_ID
	var is_ctf := game_mode == 4 and not _ctf_flags.is_empty()
	for i in _ctf_flag_labels.size():
		var fl: Label = _ctf_flag_labels[i]
		fl.visible = is_ctf
		if is_ctf and i < _ctf_flags.size():
			var d: Dictionary = _ctf_flags[i]
			var team_name := "RED" if i == 0 else "BLUE"
			var carrier := int(d.get("carrier", -1))
			if carrier >= 0:
				fl.text = "⚑ %s: carried by %s" % [team_name, _player_name(carrier)]
			elif bool(d.get("dropped", false)):
				fl.text = "⚑ %s: DROPPED" % team_name
			else:
				fl.text = "⚑ %s: at summit" % team_name
	if _sf_slot_panel != null:
		_sf_slot_panel.visible = is_sf
	if _sf_active_boost_label != null:
		_sf_active_boost_label.visible = false
	if _invis_warning_chip != null:
		_invis_warning_chip.visible = false
	if not is_sf:
		return
	var lp = _get_local_player()
	if lp == null:
		return
	# 3 slots: a filled slot shows the stored power-up's icon,
	# an empty one its numbered background. A slot button is
	# tappable only when it holds a power-up the player CAN use
	# right now: timed kinds stay greyed out while another boost
	# is active or while carrying the flag (carrier rule wins);
	# instant kinds (health, wind, thunder) are always tappable.
	var stored: Array = lp.get("stored_boosts")
	var ab0 := int(lp.get("active_boost_kind"))
	var carrying := int(lp.get("carrying_flag")) != 0
	for i in _sf_slot_buttons.size():
		var btn: Button = _sf_slot_buttons[i]
		if i < stored.size():
			var kind := int(stored[i])
			btn.icon = SF_TEX_PU64.get(kind, SF_TEX_SLOT[i])
			var timed := kind in [8, 9, 10, 13]
			btn.disabled = timed and (ab0 != 0 or carrying)
		else:
			btn.icon = SF_TEX_SLOT[i]
			btn.disabled = true
	# Active boost: name + seconds left (one active at a time).
	var ab := ab0
	if ab != 0:
		var t := 0.0
		var nm := ""
		match ab:
			8:
				t = float(lp.get("shield_timer"))
				nm = "Shield"
			9:
				t = float(lp.get("speed_timer"))
				nm = "Speed"
			10:
				t = float(lp.get("jetpack_boost_timer"))
				nm = "Jetpack Boost"
			13:
				t = float(lp.get("invisibility_timer"))
				nm = "Invisible"
		if t > 0.0 and _sf_active_boost_label != null:
			_sf_active_boost_label.text = "%s %ds" % [nm, int(ceil(t))]
			_sf_active_boost_label.visible = true
	# QA-121 (v3.11): red invisibility warning — while ANY living
	# enemy is invisible, a red chip sits at the top of the
	# top-left message area; it clears the moment the 10 s ends.
	_update_invis_warning(lp)
	# QA-114 (v3.9): comeback + event lines (CTF, both teams see them).
	if _sf_comeback_label != null:
		var trail := _sf_trailing_team()
		_sf_comeback_label.visible = is_sf and game_mode == 4 and trail >= 0
		if _sf_comeback_label.visible:
			_sf_comeback_label.text = "COMEBACK: %s gets help — elevator + extra power-ups" % ("RED" if trail == 0 else "BLUE")
	if _sf_event_label != null:
		var ev_txt := ""
		if _sf_event_active == "route_shift":
			ev_txt = "EVENT: ROUTE SHIFT — wind reversed! %ds" % int(ceil(_sf_event_time_left))
		elif _sf_event_active != "":
			ev_txt = "EVENT: %s!" % _sf_event_active.to_upper().replace("_", " ")
		elif _sf_storm_active:
			ev_txt = "SUMMIT STORM! %ds" % int(ceil(_sf_storm_time_left))
		_sf_event_label.visible = is_sf and ev_txt != ""
		_sf_event_label.text = ev_txt
	# QA-114 (v3.9): height bar — live dots for every living player
	# (white = you, red/blue = teams) + gold diamonds for pings.
	if _sf_height_bar != null:
		_sf_height_bar.visible = is_sf and not match_over
		if _sf_height_bar.visible:
			var my_id := multiplayer.get_unique_id()
			var di := 0
			for child in players_node.get_children():
				if di >= _sf_height_dots.size():
					break
				var dot: ColorRect = _sf_height_dots[di]
				if child.alive:
					dot.visible = true
					dot.position = Vector2(11, 360.0 * clampf(child.position.y, 0.0, 10800.0) / 10800.0 - 6.0)
					if int(child.peer_id) == my_id:
						dot.color = Color(1, 1, 1)
					elif int(child.team) == 0:
						dot.color = Color(0.95, 0.3, 0.25)
					elif int(child.team) == 1:
						dot.color = Color(0.25, 0.55, 0.95)
					else:
						dot.color = Color(0.85, 0.85, 0.85)
					# QA-121: an invisible ENEMY's dot is faint
					# (10% visible, like the player) — teammates
					# keep full colour, and you always see yourself.
					if int(child.peer_id) != my_id and float(child.get("invisibility_timer")) > 0.0 and (int(lp.team) < 0 or int(child.team) != int(lp.team)):
						var faint: Color = dot.color
						faint.a = 0.25
						dot.color = faint
				else:
					dot.visible = false
				di += 1
			for j in range(di, _sf_height_dots.size()):
				(_sf_height_dots[j] as ColorRect).visible = false
			for pi in _sf_height_ping_dots.size():
				var pdot: ColorRect = _sf_height_ping_dots[pi]
				if pi < _sf_pings.size():
					var ppos: Vector2 = (_sf_pings[pi] as Dictionary).get("pos", Vector2.ZERO)
					pdot.visible = true
					pdot.position = Vector2(11, 360.0 * clampf(ppos.y, 0.0, 10800.0) / 10800.0 - 6.0)
				else:
					pdot.visible = false


# QA-113 (v3.9): statistics / pause redesign — clean, spacious
# gohud style (same as the v3.7/v3.8 lobby). Stats rows are aligned
# columns (rank / name / K / D / K-D / ACC) instead of one long
# string, so nothing wraps or clips at 1280x720 or 2400x1080.
# Layout only — no logic changes.
func _stats_cell(text: String, width: float, align: HorizontalAlignment, font_size: int, color: Color) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.custom_minimum_size = Vector2(width, 0)
	lbl.horizontal_alignment = align
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.clip_text = true
	return lbl


func _stats_header_row(extra: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var muted := Color(0.62, 0.66, 0.72)
	row.add_child(_stats_cell("#", 40, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	row.add_child(_stats_cell("PLAYER", 0, HORIZONTAL_ALIGNMENT_LEFT, 18, muted))
	row.get_child(1).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_stats_cell("K", 48, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	row.add_child(_stats_cell("D", 48, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	row.add_child(_stats_cell("K/D", 64, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	row.add_child(_stats_cell("ACC", 56, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	if extra != "":
		row.add_child(_stats_cell(extra, 72, HORIZONTAL_ALIGNMENT_CENTER, 18, muted))
	return row


func _stats_row(rank: int, name_txt: String, team_txt: String, kills: int, deaths: int, kd: float, acc: int, is_self: bool, color: Color, extra: String = "") -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	var name_color := Color(1, 1, 1) if is_self else color
	row.add_child(_stats_cell(("► " if is_self else "") + str(rank), 40, HORIZONTAL_ALIGNMENT_CENTER, 20, name_color))
	var nm := Label.new()
	nm.text = name_txt + team_txt + ("  (YOU)" if is_self else "")
	nm.add_theme_font_size_override("font_size", 20)
	nm.add_theme_color_override("font_color", name_color)
	nm.clip_text = true
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(nm)
	row.add_child(_stats_cell(str(kills), 48, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	row.add_child(_stats_cell(str(deaths), 48, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	row.add_child(_stats_cell("%.2f" % kd, 64, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	row.add_child(_stats_cell("%d%%" % acc, 56, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	if extra != "":
		row.add_child(_stats_cell(extra, 72, HORIZONTAL_ALIGNMENT_CENTER, 20, Color(0.92, 0.94, 0.96)))
	return row


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
	# QA-112 (v3.9): CTF totals are captures (points), not kills.
	if game_mode == 4:
		var totals := Label.new()
		totals.text = "⚑ RED %d  —  %d BLUE" % [int(_ctf_scores.get(0, 0)), int(_ctf_scores.get(1, 0))]
		totals.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		totals.add_theme_font_size_override("font_size", 22)
		list.add_child(totals)
	list.add_child(_stats_header_row())
	list.add_child(HSeparator.new())
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
		list.add_child(_stats_row(rank, p.player_name, team_txt, p.kills, p.deaths, float(st["kd"]), int(st["accuracy"]), is_self, p.player_color))
		rank += 1
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
		3:
			return "Last Man Standing — one life, no respawns  •  %s" % GameData.MAP_NAMES[map_id]
		4:
			return "Capture the Flag — steal the flag from the summit, first to %d points (capture 3, relay bank 1)  •  %s" % [GameData.CTF_POINTS_LIMIT, GameData.MAP_NAMES[map_id]]
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
	# QA-130 (v3.11): feed chips restyled to the gohud pill look
	# (same dark navy + rounded corners as the top-right pill and
	# the slot panel) so the message area reads as one clean unit.
	var chip := PanelContainer.new()
	var chip_bg := StyleBoxFlat.new()
	chip_bg.bg_color = Color(0.03, 0.07, 0.13, 0.88)
	chip_bg.corner_radius_top_left = 8
	chip_bg.corner_radius_top_right = 8
	chip_bg.corner_radius_bottom_left = 8
	chip_bg.corner_radius_bottom_right = 8
	chip_bg.content_margin_left = 10
	chip_bg.content_margin_right = 10
	chip_bg.content_margin_top = 4
	chip_bg.content_margin_bottom = 4
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
				# QA-069: an uncredited death (lava, barrel chain
				# with no shooter) still locks the victim for the
				# QA-031 window. Without this, a stale in-flight
				# bullet could credit a kill for a corpse while
				# the host's copy still showed them alive — the
				# shooter gains a kill for a lava death.
				_kill_credit_lock[pid] = Time.get_ticks_msec()
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


func _stop_broadcast() -> void:
	# QA-060: close the room-announcement sockets explicitly (leave
	# / scene change). PacketPeerUDP is RefCounted so the sockets
	# close when the last reference drops, but an explicit close
	# means a re-host in the same process never finds the port busy.
	for s in _udp_broadcast_sockets:
		if s != null:
			s.close()
	_udp_broadcast_sockets.clear()
	_udp_broadcast = null


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
	_test_weapon_spawns += 1
	rpc("spawn_pickup_remote", pos, pname, kind, spot_idx)


func on_pickup_gone(spot_idx: int) -> void:
	# A pickup was collected or despawned: restart its per-spot
	# 14 s timer (GAP-37). Only the server tracks this.
	# QA-112: power-up spots (100+) restart the 30 s power-up
	# timer instead — they must stay rarer than weapons.
	if spot_idx >= 200:
		# QA-114: comeback bonus (200+team) — the next bonus comes
		# 25 s after this one is collected, via the comeback timer.
		_sf_comeback_pu_timer = 25.0
		return
	if spot_idx >= 100:
		_sf_pickup_timers[spot_idx - 100] = SF_POWERUP_COOLDOWN
		return
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
	var weapon_active := 0
	for child in pickups_node.get_children():
		active_spots[int(child.get("spot_index"))] = true
		if int(child.get("kind")) <= 6:
			weapon_active += 1
	for i in spots.size():
		if active_spots.has(i):
			continue
		var t := float(_pickup_spot_timers.get(i, 0.0)) - delta
		_pickup_spot_timers[i] = t
		# QA-112: the 3-active cap counts WEAPONS only — Skyfall
		# power-ups (kind 7+) have their own cap (max 2), so a
		# power-up on the field must never block a weapon spawn.
		if t <= 0.0 and weapon_active < 3:
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


func _repl_sim_snapshot(seq: int, pos: Vector2, vel: Vector2, k: int = 0, d: int = 0, al: bool = true, ls: int = 0) -> Dictionary:
	# One QA-053 move snapshot, exactly as _send_move_snapshot builds
	# it (same keys the receiver reads). QA-068: "st" advances at a
	# steady 33 ms per sequence step — the sender's clock, which is
	# what the receiver interpolates on now; "prot" is 0 (no spawn
	# protection in the movement stream). QA-073: "id" is 0 here
	# ("unspecified" — the receiver accepts it; a real sender puts
	# its peer id in) and the gameplay-state flags default to
	# ground / not firing / not jetpacking / not reloading.
	return {"seq": seq, "st": float(seq) * 0.033, "prot": 0,
		"id": 0, "jet": 0, "fire": 0, "rel": 0, "air": 0,
		"p": pos, "v": vel, "aim": 0.0, "face": 1,
		"wpn": 0, "hp": 100, "k": k, "d": d, "al": al, "fuel": 100.0,
		"ls": ls, "mag": 30, "gr": 2, "sf": 0, "sh": 0}


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
	if step_rate > 900.0:
		# QA-073 diagnostic: a step over the chaos bar — log the
		# sample so the cause (resync snap? fast frame? catch-up
		# chase?) is visible instead of guessed. Test-only print.
		print("REPLSIM SPIKE step_rate=%.0f px/s step=%.1f px frame_delta=%.3f s pos=%s" % [step_rate, pos.distance_to(_repl_sim_track_prev), frame_delta, pos])
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
			# Stream three snapshots per frame (30/s, +10 px each
			# in x, 300 px/s) and track the server copy's rendered
			# position: it must glide forward in small steps, never
			# freeze and jump, never snap back to an old position. The first 0.2 s is
			# warm-up (the interpolation buffer fills; the very first
			# snapshot pins the copy at the stream start, which is a
			# join-moment placement, not steady-state motion) — the
			# tracker starts after it so only steady motion is scored.
			var s_p2b = players_node.get_node_or_null("2")
			if s_p2b != null:
				# Stream at the sender's TRUE rate: 3 snapshots per
				# sim frame, 33 ms apart on the sender's clock
				# (30/s — the rate _send_move_snapshot actually
				# emits at). One snapshot per frame would stamp the
				# sender's clock 3x slower than wall time, which
				# no real sender does.
				for n9 in 3:
					_repl_sim_stream_x += 300.0 * 0.033
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
			# remote branch) receives three snapshots per frame, as
			# in step 9. First 0.2 s warms the interpolation buffer
			# up; then the tracker scores steady motion only.
			var c_p1t = _repl_sim_shadow.players_node.get_node_or_null("1")
			if c_p1t != null:
				# Same true-rate stream as step 9 (3 snapshots per
				# frame, 33 ms apart on the sender's clock).
				for n10 in 3:
					_repl_sim_stream_x += 300.0 * 0.033
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
			# (f) QA-061 rifle straightness, remote: the server's
			# pid-1 player fires the rifle 5 times with aim dead
			# right and _recoil_accum forced to 1.5 (far past a
			# 2 s hold — pre-fix that is ±46° of spray). The shot
			# directions are recorded in shot_devs (the LOCAL
			# check). The last shot's direction is then fired
			# again from open air (1700, 455) on BOTH instances
			# with identical params — the spawn RPC hand-delivered
			# — and step 13 tracks the pair for straightness.
			var s_p1r = players_node.get_node_or_null("1")
			var twin_dir := Vector2.RIGHT
			if s_p1r != null:
				s_p1r.weapon = 0
				s_p1r.mag_ammo = 30
				s_p1r.aim_angle = 0.0
				s_p1r.velocity = Vector2.ZERO
				s_p1r._recoil_accum = 1.5
				s_p1r.shot_devs.clear()
				for i in 5:
					s_p1r._fire()
				if not s_p1r.shot_devs.is_empty():
					twin_dir = Vector2.RIGHT.rotated(float(s_p1r.shot_devs[s_p1r.shot_devs.size() - 1]))
			var muzzle_r := Vector2(1700, 455)
			var b_a = obtain_bullet()
			b_a.setup(muzzle_r, twin_dir, 1100.0, 12, 0, 1, false, 0.0, 1.2, 997, twin_dir * 1100.0, 0.0)
			if b_a.get_parent() == null:
				bullets_node.add_child(b_a)
			var b_b = _repl_sim_shadow.obtain_bullet()
			b_b.setup(muzzle_r, twin_dir, 1100.0, 12, 0, 1, false, 0.0, 1.2, 997, twin_dir * 1100.0, 0.0)
			if b_b.get_parent() == null:
				_repl_sim_shadow.bullets_node.add_child(b_b)
			_repl_sim_bullet_a = b_a
			_repl_sim_bullet_b = b_b
			_repl_sim_bullet_max_err = 0.0
			_repl_sim_bullet_max_step = 0.0
			_repl_sim_bullet_prev_b = Vector2.INF
			_repl_sim_bullet_frames = 0
			_repl_sim_step = 13
			_repl_sim_timer = 0.0
		13:
			# Track the rifle twin flight for 0.5 s and score
			# straightness on both sides: each bullet must hold
			# its line (travel angle ~0°) and the pair must agree.
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
			if _repl_sim_timer < 0.5:
				return
			var s_p1s = players_node.get_node_or_null("1")
			var max_dev := 0.0
			var n_dev := 0
			if s_p1s != null:
				for d in s_p1s.shot_devs:
					max_dev = maxf(max_dev, absf(float(d)))
					n_dev += 1
			_repl_sim_check("RIFLE-STRAIGHT-LOCAL", n_dev >= 5 and rad_to_deg(max_dev) < 0.5,
				"server rifle shots=%d max deviation=%.2f° at recoil 1.5 (want >=5 shots, <0.5° — pre-fix this was ±46°)" % [n_dev, rad_to_deg(max_dev)])
			var a_ok: bool = is_instance_valid(_repl_sim_bullet_a) and _repl_sim_bullet_a.active
			var b_ok: bool = is_instance_valid(_repl_sim_bullet_b) and _repl_sim_bullet_b.active
			var a_travel := 0.0
			var b_travel := 0.0
			if a_ok:
				a_travel = absf(rad_to_deg(_repl_sim_bullet_a.direction.angle()))
			if b_ok:
				b_travel = absf(rad_to_deg(_repl_sim_bullet_b.direction.angle()))
			_repl_sim_check("RIFLE-STRAIGHT-REMOTE", a_ok and b_ok and _repl_sim_bullet_frames >= 4 and a_travel < 1.0 and b_travel < 1.0 and _repl_sim_bullet_max_err < 10.0,
				"tracked %d frames, server travel angle=%.2f° shadow travel angle=%.2f° max pair error=%.1f px (want >=4 frames, both alive, <1.0° each, <10 px)" % [_repl_sim_bullet_frames, a_travel, b_travel, _repl_sim_bullet_max_err])
			# Steps 14-16 (v3.6 QA-069): the full kill → respawn →
			# scoreboard chain on two simulated peers. The server
			# instance is peer 1 (killer) + peer 2 (victim); the
			# shadow is the second peer that must end with
			# IDENTICAL scores. Baselines are recorded here so any
			# stray damage from the rifle steps above cannot skew
			# the counts.
			var k_p1 = players_node.get_node_or_null("1")
			var k_p2 = players_node.get_node_or_null("2")
			if k_p1 != null:
				_repl_sim_kill_k0 = k_p1.kills
			if k_p2 != null:
				_repl_sim_kill_d0 = k_p2.deaths
				# Fresh life for the chain, whatever the rifle steps did.
				k_p2.health = 10
				k_p2.alive = true
				k_p2.life_state = 0
				k_p2._spawn_protect_timer = 0.0
			_repl_sim_kill_feed0 = _kill_feed_entries.size()
			_repl_sim_step = 14
			_repl_sim_timer = 0.0
		14:
			# KILL-ONCE: one lethal hit = one death, one kill, one
			# feed line. A duplicate lethal hit in the same life
			# (new event id, victim already DYING) and a duplicate
			# credit attempt must change nothing — the LifeState
			# guard in _apply_damage and the QA-031 lock in
			# try_credit_kill.
			if _repl_sim_timer < 0.3:
				return
			var v14 = players_node.get_node_or_null("2")
			var k14 = players_node.get_node_or_null("1")
			var ok14 := false
			var det14 := ""
			if v14 != null and k14 != null:
				v14.take_hit(50, 1, Vector2.ZERO, 0.0, next_damage_event_id())
				var died_once: bool = v14.deaths == _repl_sim_kill_d0 + 1 and not v14.alive
				var credited: bool = try_credit_kill(1, 2, 0)
				var kill_once: bool = credited and k14.kills == _repl_sim_kill_k0 + 1
				v14.take_hit(50, 1, Vector2.ZERO, 0.0, next_damage_event_id())
				var dup_hit_ok: bool = v14.deaths == _repl_sim_kill_d0 + 1
				var credited2: bool = try_credit_kill(1, 2, 0)
				var dup_credit_ok: bool = not credited2 and k14.kills == _repl_sim_kill_k0 + 1
				var feed_once: bool = _kill_feed_entries.size() == _repl_sim_kill_feed0 + 1
				ok14 = died_once and kill_once and dup_hit_ok and dup_credit_ok and feed_once
				det14 = "deaths=%d (want %d) kills=%d (want %d) dup_hit_deaths=%d dup_credit=%s feed=%d (want %d)" % [
					v14.deaths, _repl_sim_kill_d0 + 1, k14.kills, _repl_sim_kill_k0 + 1,
					v14.deaths, credited2, _kill_feed_entries.size(), _repl_sim_kill_feed0 + 1]
			_repl_sim_check("KILL-ONCE", ok14, det14)
			_repl_sim_kill_lock_wait = false
			_repl_sim_step = 15
			_repl_sim_timer = 0.0
		15:
			# KILL-SECOND-LIFE: after the 1 s QA-031 lock expires,
			# the victim respawns (fresh life, deaths kept) and a
			# second lethal hit credits a SECOND kill — the lock
			# must not block a genuine kill in the next life. The
			# feed must grow by exactly one more line (the death
			# watcher must not have added a second line for the
			# step-14 death in the meantime).
			if _repl_sim_timer < 1.2:
				return
			var v15 = players_node.get_node_or_null("2")
			var k15 = players_node.get_node_or_null("1")
			var ok15 := false
			var det15 := ""
			if v15 != null and k15 != null:
				v15._respawn()
				v15._spawn_protect_timer = 0.0 # protection expired (test only — real play waits it out)
				var respawned: bool = v15.alive and v15.health == 100 and v15.deaths == _repl_sim_kill_d0 + 1
				v15.health = 10
				v15.take_hit(50, 1, Vector2.ZERO, 0.0, next_damage_event_id())
				var died2: bool = v15.deaths == _repl_sim_kill_d0 + 2 and not v15.alive
				var credited15: bool = try_credit_kill(1, 2, 0)
				var kill2: bool = credited15 and k15.kills == _repl_sim_kill_k0 + 2
				var feed2: bool = _kill_feed_entries.size() == _repl_sim_kill_feed0 + 2
				ok15 = respawned and died2 and kill2 and feed2
				det15 = "respawned=%s deaths=%d (want %d) kills=%d (want %d) feed=%d (want %d)" % [
					respawned, v15.deaths, _repl_sim_kill_d0 + 2, k15.kills, _repl_sim_kill_k0 + 2,
					_kill_feed_entries.size(), _repl_sim_kill_feed0 + 2]
			_repl_sim_check("KILL-SECOND-LIFE", ok15, det15)
			_repl_sim_kill_lock_wait = false
			_repl_sim_kill_snaps_done = false
			_repl_sim_step = 16
			_repl_sim_timer = 0.0
		16:
			# SCORE-SYNC + LAVA + REMOTE-DEATH: (a) the victim dies
			# to lava — no killer, no credit; the death watcher
			# announces it once AND sets the QA-031 lock, so a
			# stale in-flight bullet afterwards credits nothing;
			# (b) the final scores are hand-delivered to the shadow
			# as snapshots, and both peers must agree exactly;
			# (c) the shadow's copy of the dead victim must play
			# the death pose (QA-069 remote-die fix).
			if _repl_sim_timer < 1.2:
				return
			var v16 = players_node.get_node_or_null("2")
			var k16 = players_node.get_node_or_null("1")
			if v16 == null or k16 == null:
				_repl_sim_check("SCORE-SYNC", false, "killer or victim missing")
				_repl_sim_done = true
				print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
				get_tree().quit()
				return
			if not _repl_sim_kill_lock_wait:
				# Respawn first and let the death watcher OBSERVE
				# alive frames (as in real play, where 2 s of spawn
				# protection guarantees them) before the lava kill
				# below — respawning and dying in the same frame
				# would leave the watcher's per-life "already fed"
				# flag stale from the previous life.
				v16._respawn()
				v16._spawn_protect_timer = 0.0
				_repl_sim_kill_feed0 = _kill_feed_entries.size()
				_repl_sim_kill_lock_wait = true
				return
			if _repl_sim_timer < 1.6:
				return # watcher observes the fresh life
			if _repl_sim_timer < 2.0:
				# Lava kill, once: take_damage only fires while the
				# victim is still alive, so this branch is a no-op
				# on later frames. The watcher then has 0.4 s to
				# observe the death, lock, and announce before the
				# check at 2.0.
				if v16.alive:
					v16.take_damage(200, 0) # lava: from_id 0, no kill credit
				return
			if not _repl_sim_kill_snaps_done:
				var lava_ok: bool = v16.deaths == _repl_sim_kill_d0 + 3 and not v16.alive
				var stale_credit: bool = try_credit_kill(1, 2, 0)
				var lava_feed_ok: bool = _kill_feed_entries.size() == _repl_sim_kill_feed0 + 1
				var lava_credit_ok: bool = not stale_credit and k16.kills == _repl_sim_kill_k0 + 2
				_repl_sim_check("LAVA-NO-CREDIT", lava_ok and lava_feed_ok and lava_credit_ok,
					"deaths=%d (want %d) feed=%d (want %d) stale_credit=%s kills=%d (want %d — a lava death credits nobody)" % [
						v16.deaths, _repl_sim_kill_d0 + 3, _kill_feed_entries.size(), _repl_sim_kill_feed0 + 1,
						stale_credit, k16.kills, _repl_sim_kill_k0 + 2])
				# Deliver the final scores to the shadow as
				# snapshots, exactly as the wire would.
				var c_p1 = _repl_sim_shadow.players_node.get_node_or_null("1")
				var c_p2 = _repl_sim_shadow.players_node.get_node_or_null("2")
				if c_p1 != null:
					_repl_sim_seq += 1
					c_p1.receive_move_snapshot(_repl_sim_snapshot(_repl_sim_seq, k16.position, Vector2.ZERO, k16.kills, k16.deaths, true, 0))
				if c_p2 != null:
					_repl_sim_seq += 1
					c_p2.receive_move_snapshot(_repl_sim_snapshot(_repl_sim_seq, v16.position, Vector2.ZERO, v16.kills, v16.deaths, false, 1))
				_repl_sim_kill_snaps_done = true
				return
			if _repl_sim_timer < 1.9:
				return # let the shadow run a physics frame (remote death pose)
			var c_p1f = _repl_sim_shadow.players_node.get_node_or_null("1")
			var c_p2f = _repl_sim_shadow.players_node.get_node_or_null("2")
			var sync_ok: bool = c_p1f != null and c_p2f != null \
				and c_p1f.kills == k16.kills and c_p1f.deaths == k16.deaths \
				and c_p2f.kills == v16.kills and c_p2f.deaths == v16.deaths
			_repl_sim_check("SCORE-SYNC", sync_ok,
				"server killer K/D=%d/%d shadow K/D=%d/%d; server victim K/D=%d/%d shadow K/D=%d/%d (want identical on both peers)" % [
					k16.kills, k16.deaths, c_p1f.kills if c_p1f != null else -1, c_p1f.deaths if c_p1f != null else -1,
					v16.kills, v16.deaths, c_p2f.kills if c_p2f != null else -1, c_p2f.deaths if c_p2f != null else -1])
			var die_ok: bool = c_p2f != null and c_p2f._current_anim == "die"
			_repl_sim_check("REMOTE-DEATH-POSE", die_ok,
				"shadow victim anim='%s' (want 'die' — pre-fix the remote copy kept its run/idle loop)" % [c_p2f._current_anim if c_p2f != null else "?"])
			# Step 17 (QA-068): sustained burst-jitter smoothness.
			_repl_sim_kill_snaps_done = false # reused as the step-17 setup flag
			_repl_sim_warm_done = false
			_repl_sim_step = 17
			_repl_sim_timer = 0.0
		17:
			# SUSTAINED BURST-JITTER: stream the server pid-2 copy
			# for 2 s (1 s at 300 px/s, then 1 s at 150 px/s), but
			# deliver the snapshots in BURSTS of 9 at a time, the
			# way Wi-Fi actually delivers them — nine packets
			# landing in the same frame after ~300 ms of silence.
			# The sender still emits at 30/s (3 snapshots per sim
			# frame, 33 ms apart on the sender's clock); only the
			# DELIVERY is bursty. With the old receipt-time stamps
			# all nine would share one timestamp, the lerp between
			# them would collapse, and the copy would jump; with
			# the sender's stamps (QA-068) the spacing stays a
			# steady 33 ms and the copy must glide. The step bar
			# here is 900 px/s, not the 600 of steps 9/10: the sim
			# samples at ~10 fps, so one sample can hold a whole
			# burst's catch-up (90 px in 0.1 s = 900 px/s) while
			# the same motion on a 60 fps phone is 5 px per
			# physics frame; a true freeze-then-teleport would
			# read several thousand px/s. Snap-back stays <5 px —
			# that is the real jump detector, and it reads 0.0.
			var s17 = players_node.get_node_or_null("2")
			if s17 == null:
				_repl_sim_check("BURST-SMOOTH", false, "server pid-2 missing")
				_repl_sim_done = true
				print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
				get_tree().quit()
				return
			if not _repl_sim_kill_snaps_done:
				s17._respawn() # live again after the step-16 lava death
				s17._spawn_protect_timer = 0.0
				s17.position = Vector2(500, 455)
				s17._snapshots.clear()
				s17._last_snap_seq = -1
				_repl_sim_stream_x = 500.0
				_repl_sim_stream_y = 455.0
				_repl_sim_seq = 5000
				_repl_sim_burst_pending.clear()
				_repl_sim_track_reset(s17.position)
				_repl_sim_kill_snaps_done = true
				_repl_sim_seq += 1
				s17.receive_move_snapshot(_repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0)))
				return
			var speed17 := 300.0 if _repl_sim_timer < 1.0 else 150.0
			# The sender emits 3 snapshots per sim frame (30/s):
			# each advances the sender clock 33 ms and the position
			# by speed x 33 ms. Delivery is bursty (9 at a time).
			for n17 in 3:
				_repl_sim_stream_x += speed17 * 0.033
				_repl_sim_seq += 1
				_repl_sim_burst_pending.append(_repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(speed17, 0)))
			if _repl_sim_burst_pending.size() >= 9:
				for snap17 in _repl_sim_burst_pending:
					s17.receive_move_snapshot(snap17)
				_repl_sim_burst_pending.clear()
			if _repl_sim_timer < 0.5:
				pass # warm-up: buffer fills, tracker off
			elif not _repl_sim_warm_done:
				_repl_sim_warm_done = true
				_repl_sim_track_reset(s17.position)
			else:
				_repl_sim_track(s17.position, delta)
			if _repl_sim_timer < 2.3:
				return
			var moved17: float = s17.position.distance_to(Vector2(500, 455))
			_repl_sim_check("BURST-SMOOTH", _repl_sim_track_max_step < 900.0 and _repl_sim_track_max_back < 5.0,
				"max step rate=%.0f px/s, max snap-back=%.1f px over 2 s of burst delivery (want <900 px/s / <5 px — steady glide, no jumps; 900 not 600 because one ~10 fps sample can hold a whole burst's catch-up, see the step comment)" % [_repl_sim_track_max_step, _repl_sim_track_max_back])
			_repl_sim_check("BURST-MOVE", moved17 > 300.0,
				"server pid-2 copy moved %.0f px in 2 s of burst delivery (want >300 — 1 s at 300 px/s + 1 s at 150 px/s, minus the 100 ms buffer lag)" % moved17)
			# Step 18 (QA-073): chaos delivery — loss + delay +
			# duplicate + out-of-order, the Wi-Fi shapes steps 9/10/17
			# never produced. _repl_sim_kill_snaps_done is reused as
			# the step-18 setup flag, as in step 17.
			_repl_sim_kill_snaps_done = false
			_repl_sim_warm_done = false
			_repl_sim_step = 18
			_repl_sim_timer = 0.0
		18:
			# CHAOS DELIVERY: stream the server pid-2 copy for 2 s
			# at 300 px/s, but corrupt the delivery the way bad Wi-Fi
			# does — every 7th snapshot is DROPPED (never arrives),
			# every 11th is delivered TWICE, every 5th is DELAYED
			# 300 ms (so it lands after newer snapshots and must be
			# dropped as out-of-order), the rest arrive in bursts of
			# 9. The copy must still glide (no teleport, no snap-back)
			# and the receiver must COUNT each fault (lost / dup /
			# ooo) instead of silently swallowing it. The step bar
			# here is 2000 px/s, derived from the step clamp, not
			# fitted to a run: after a loss gap the copy legitimately
			# chases at the designed clamp (700 px/s + 20 px slack
			# = 31.7 px per physics frame), and one ~10 fps sample
			# can hold 6 physics frames of that chase (6 x 31.7 =
			# 190 px in 0.1 s = 1900 px/s — runs read 780, 922,
			# 1879, 930). A genuine teleport — a 600 px snap in one
			# sample — reads 6000 px/s and still fails the bar.
			# Snap-back stays <5 px — that is the real jump
			# detector, and it reads 0.0 in every run.
			var s18 = players_node.get_node_or_null("2")
			if s18 == null:
				_repl_sim_check("CHAOS-SMOOTH", false, "server pid-2 missing")
				_repl_sim_done = true
				print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
				get_tree().quit()
				return
			if not _repl_sim_kill_snaps_done:
				s18._respawn() # live again after the step-16 lava death
				s18._spawn_protect_timer = 0.0
				s18.position = Vector2(500, 455)
				s18._snapshots.clear()
				s18._last_snap_seq = -1
				# Fresh counters + fresh adaptive delay, so step 18
				# measures its own delivery faults from zero.
				s18._net_lost_count = 0
				s18._net_dup_count = 0
				s18._net_ooo_count = 0
				s18._net_recv_count = 0
				s18._interp_delay = PhysicsConfig.INTERP_BUFFER
				s18._jitter_ewma = 0.0
				s18._prev_snap_sender_t = -1.0
				_repl_sim_stream_x = 500.0
				_repl_sim_stream_y = 455.0
				_repl_sim_seq = 8000
				_repl_sim_burst_pending.clear()
				_repl_sim_delayed.clear()
				_repl_sim_last_snap = {}
				_repl_sim_track_reset(s18.position)
				_repl_sim_kill_snaps_done = true
				_repl_sim_seq += 1
				var seed18 := _repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0))
				s18.receive_move_snapshot(seed18)
				_repl_sim_last_snap = seed18
				return
			for n18 in 3:
				_repl_sim_stream_x += 300.0 * 0.033
				_repl_sim_seq += 1
				var snap18 := _repl_sim_snapshot(_repl_sim_seq,
					Vector2(_repl_sim_stream_x, _repl_sim_stream_y), Vector2(300, 0))
				if _repl_sim_seq % 7 == 0:
					pass # DROPPED — packet loss (never delivered)
				elif _repl_sim_seq % 11 == 0:
					_repl_sim_burst_pending.append(snap18)
					_repl_sim_burst_pending.append(snap18) # DUPLICATE
				elif _repl_sim_seq % 5 == 0:
					_repl_sim_delayed.append({"at": _repl_sim_timer + 0.3, "snap": snap18}) # DELAYED 300 ms
				else:
					_repl_sim_burst_pending.append(snap18)
			# Delayed snapshots whose time came: they land AFTER
			# newer ones, so the sequence guard must drop them as
			# out-of-order (counted in _net_ooo_count). _last_snap
			# tracks the last ACCEPTED snapshot (seq == the
			# receiver's newest) — a dropped delayed one must NOT
			# become the duplicate probe's target, or the probe
			# would count an out-of-order instead of a duplicate.
			var still_delayed18: Array = []
			for d18 in _repl_sim_delayed:
				if float(d18["at"]) <= _repl_sim_timer:
					s18.receive_move_snapshot(d18["snap"])
					if int((d18["snap"] as Dictionary).get("seq", -1)) == s18._last_snap_seq:
						_repl_sim_last_snap = d18["snap"]
				else:
					still_delayed18.append(d18)
			_repl_sim_delayed = still_delayed18
			if _repl_sim_burst_pending.size() >= 9:
				for snap18b in _repl_sim_burst_pending:
					s18.receive_move_snapshot(snap18b)
					if int((snap18b as Dictionary).get("seq", -1)) == s18._last_snap_seq:
						_repl_sim_last_snap = snap18b
				_repl_sim_burst_pending.clear()
			if _repl_sim_timer < 0.5:
				pass # warm-up: buffer fills, tracker off
			elif not _repl_sim_warm_done:
				_repl_sim_warm_done = true
				_repl_sim_track_reset(s18.position)
			else:
				_repl_sim_track(s18.position, delta)
			if _repl_sim_timer < 2.3:
				return
			var moved18: float = s18.position.distance_to(Vector2(500, 455))
			_repl_sim_check("CHAOS-SMOOTH", _repl_sim_track_max_step < 2000.0 and _repl_sim_track_max_back < 5.0,
				"max step rate=%.0f px/s, max snap-back=%.1f px over 2 s of chaos delivery (want <2000 px/s / <5 px — loss + delay + duplicates must not teleport the copy; 2000 is the clamp-derived bound, see the step comment)" % [_repl_sim_track_max_step, _repl_sim_track_max_back])
			_repl_sim_check("CHAOS-MOVE", moved18 > 200.0,
				"server pid-2 copy moved %.0f px in 2 s of chaos delivery (want >200 — the stream still gets through)" % moved18)
			_repl_sim_check("CHAOS-LOSS-DUP-OOO", s18._net_lost_count > 0 and s18._net_dup_count > 0 and s18._net_ooo_count > 0,
				"lost=%d dup=%d ooo=%d recv=%d (want all >0 — the chaos actually happened and the receiver counted every fault)" % [s18._net_lost_count, s18._net_dup_count, s18._net_ooo_count, s18._net_recv_count])
			# Explicit duplicate probe: re-deliver the last snapshot
			# that actually arrived — same seq, so it must be counted
			# and ignored, and the copy must not move backwards.
			var dup_before: int = s18._net_dup_count
			s18.receive_move_snapshot(_repl_sim_last_snap)
			_repl_sim_check("CHAOS-DUP-IGNORED", s18._net_dup_count == dup_before + 1,
				"dup=%d (want %d — the re-delivered snapshot was counted and ignored)" % [s18._net_dup_count, dup_before + 1])
			# Explicit out-of-order probe: an older snapshot (2 seqs
			# back, 100 px behind) must be counted and ignored.
			var ooo_before: int = s18._net_ooo_count
			s18.receive_move_snapshot(_repl_sim_snapshot(s18._last_snap_seq - 2, s18.position - Vector2(100, 0), Vector2(300, 0)))
			_repl_sim_check("CHAOS-OOO-IGNORED", s18._net_ooo_count == ooo_before + 1,
				"ooo=%d (want %d — the stale snapshot was counted and ignored, no snap-back)" % [s18._net_ooo_count, ooo_before + 1])
			# Step 19 (QA-073): prediction + reconciliation on the
			# LOCAL player. _repl_sim_kill_snaps_done is reused as
			# the step-19 setup flag; _repl_sim_warm_done as the
			# "small correction applied" phase flag.
			_repl_sim_kill_snaps_done = false
			_repl_sim_warm_done = false
			_repl_sim_step = 19
			_repl_sim_timer = 0.0
		19:
			# PREDICTION + RECONCILIATION: the server pid-1 player
			# is local here, so it predicts (moves with no network
			# wait) and must reconcile against an authoritative
			# correction. (a) A small 40 px correction must NOT snap
			# the player in the correction frame — it blends in.
			# (b) Half a second later the player must have arrived
			# within 10 px of the corrected position. (c) A large
			# 500 px correction DOES snap at once (teleport-class).
			# (d) A stale correction (older corr_seq) is ignored.
			# (e) The prediction ring must hold recent frames.
			var lp19 = players_node.get_node_or_null("1")
			if lp19 == null:
				_repl_sim_check("RECONCILE-NO-SNAP", false, "local player missing")
				_repl_sim_done = true
				print("REPLSIM DONE: %d passed, %d failed (simulated wire only — live two-phone ENet still needs real phones, see BUGS.md QA-047/QA-053)" % [_repl_sim_passed, _repl_sim_failed])
				get_tree().quit()
				return
			if not _repl_sim_kill_snaps_done:
				# Start on open floor: the step-7 move left the
				# player against a wall, and a +40 px correction
				# from there would stop at the wall instead of
				# arriving. A fresh validated spawn is clear.
				var game19 = get_tree().get_first_node_in_group("game")
				if game19 != null:
					lp19.position = game19.get_valid_spawn_point(lp19.player_index, lp19.peer_id)
					lp19.velocity = Vector2.ZERO
				_repl_sim_move_start = lp19.position
				_repl_sim_kill_snaps_done = true
				return
			if _repl_sim_timer < 0.3:
				return
			if not _repl_sim_warm_done:
				var before19: Vector2 = lp19.position
				lp19.apply_authoritative_correction(before19 + Vector2(40, 0), Vector2.ZERO, 9001)
				_repl_sim_check("RECONCILE-NO-SNAP", lp19.position.distance_to(before19) < 1.0,
					"pos moved %.1f px in the correction frame (want <1 — a 40 px correction blends, it does not snap)" % lp19.position.distance_to(before19))
				_repl_sim_move_start = before19 + Vector2(40, 0)
				_repl_sim_warm_done = true
				return
			if _repl_sim_timer < 0.8:
				return
			# Horizontal distance only: the blend moves the player
			# toward the corrected position, but gravity still owns
			# the vertical — if the +40 px nudge carries the player
			# off a platform edge it falls while it blends, and a
			# full 2D distance would blame the blend for the fall.
			var arrived19: float = absf(lp19.position.x - _repl_sim_move_start.x)
			_repl_sim_check("RECONCILE-BLEND", arrived19 < 10.0,
				"horizontal distance to the corrected position=%.1f px after 0.5 s (want <10 — the blend arrived; pos=%s vel=%s on_floor=%s)" % [arrived19, lp19.position, lp19.velocity, lp19.is_on_floor()])
			var big_before: Vector2 = lp19.position
			lp19.apply_authoritative_correction(big_before + Vector2(500, 0), Vector2.ZERO, 9002)
			_repl_sim_check("RECONCILE-BIG-SNAP", lp19.position.distance_to(big_before + Vector2(500, 0)) < 1.0,
				"pos=%s (want %s — a 500 px correction snaps at once, it does not glide across the map)" % [lp19.position, big_before + Vector2(500, 0)])
			var stale_before: Vector2 = lp19.position
			lp19.apply_authoritative_correction(stale_before + Vector2(40, 0), Vector2.ZERO, 9001)
			_repl_sim_check("RECONCILE-STALE", lp19.position.distance_to(stale_before) < 1.0,
				"pos moved %.1f px on a stale correction (want <1 — corr_seq 9001 after 9002 is ignored)" % lp19.position.distance_to(stale_before))
			_repl_sim_check("PREDICT-HISTORY", lp19._pred_pos.size() >= 10,
				"prediction ring holds %d frames (want >=10 — the local simulation records what it predicted)" % lp19._pred_pos.size())
			# Step 20 (QA-073): the net-stats display. The sim runs
			# without --net-stats, so the panel must start hidden.
			_repl_sim_kill_snaps_done = false
			_repl_sim_step = 20
			_repl_sim_timer = 0.0
		20:
			# NET-STATS DISPLAY: hidden by default, shows on toggle
			# with the spec §7 fields (RTT, FPS, delay), hides again
			# on the next toggle. The sim has no live ENet peer, so
			# RTT reads "--" — the check is that the panel and its
			# fields render, not that a real RTT exists.
			if not _repl_sim_kill_snaps_done:
				_repl_sim_check("NETSTATS-HIDDEN-DEFAULT", _net_stats_label != null and not _net_stats_label.visible,
					"label visible=%s (want false — dev-only, hidden by default, never in normal play)" % [_net_stats_label.visible if _net_stats_label != null else "?"])
				toggle_net_stats()
				_update_net_stats(1.0) # force a refresh past the 0.25 s throttle
				_repl_sim_kill_snaps_done = true
				_repl_sim_timer = 0.0
				return
			if _repl_sim_timer < 0.3:
				return
			var txt20 := _net_stats_label.text if _net_stats_label != null else ""
			_repl_sim_check("NETSTATS-SHOWS", _net_stats_label != null and _net_stats_label.visible and "RTT" in txt20 and "FPS" in txt20 and "delay" in txt20,
				"visible=%s text='%s' (want visible with RTT/FPS/delay fields)" % [_net_stats_label.visible if _net_stats_label != null else false, txt20.replace("\n", " | ")])
			toggle_net_stats()
			_repl_sim_check("NETSTATS-HIDES", _net_stats_label != null and not _net_stats_label.visible,
				"visible=%s after toggle off (want false)" % [_net_stats_label.visible if _net_stats_label != null else "?"])
			# Step 21 (QA-075): the remote muzzle flash — the
			# shadow's pid-1 copy must show its flash while a
			# firing snapshot stream runs, and the flash must end
			# by itself when the stream stops.
			_repl_sim_warm_done = false
			_repl_sim_step = 21
			_repl_sim_timer = 0.0
		21:
			# REMOTE-MUZZLE: stream firing snapshots to the
			# shadow's pid-1 copy (authority 2 since step 9, so it
			# runs the remote branch) for 0.3 s, then stop and
			# watch the flash end. The remote flash timer is
			# 0.25 s: long enough to bridge the ~0.1 s frames of
			# the sim (a per-weapon 0.05 s flash would expire
			# between frames here), short enough to be gone 0.4 s
			# after the stream stops. Kills/deaths are passed
			# through so the stream does not reset the scores
			# step 16 set on the shadow.
			var c_p1m = _repl_sim_shadow.players_node.get_node_or_null("1")
			if c_p1m != null:
				# QA-075b: the stream runs ONLY before the SHOWS
				# check (the `not _repl_sim_warm_done` gate). The
				# first version of this step re-entered the stream
				# after SHOWS reset the timer (timer < 0.3 again),
				# so the muzzle timer kept refreshing and HIDES
				# read visible=true 0.4 s after the "stop" — the
				# stream had in fact stopped only ~0.1 s earlier.
				# With the gate, the 0.4 s wait is a real silence.
				if _repl_sim_timer < 0.3 and not _repl_sim_warm_done:
					_repl_sim_seq += 1
					var snap21 := _repl_sim_snapshot(_repl_sim_seq, c_p1m.position, Vector2.ZERO, c_p1m.kills, c_p1m.deaths, true, 0)
					snap21["fire"] = 1
					c_p1m.receive_move_snapshot(snap21)
					return
				if not _repl_sim_warm_done:
					_repl_sim_check("REMOTE-MUZZLE-SHOWS", c_p1m._muzzle.visible and c_p1m._muzzle_timer > 0.0 and c_p1m.alive,
						"remote muzzle visible=%s timer=%.2f alive=%s (want true/>0/true while the firing stream runs)" % [c_p1m._muzzle.visible, c_p1m._muzzle_timer, c_p1m.alive])
					_repl_sim_warm_done = true
					_repl_sim_timer = 0.0
					return
				if _repl_sim_timer < 0.4:
					return
				_repl_sim_check("REMOTE-MUZZLE-HIDES", not c_p1m._muzzle.visible,
					"remote muzzle visible=%s 0.4 s after the firing stream stopped (want false — a flash, not stuck on)" % c_p1m._muzzle.visible)
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
	# QA-112 (v3.9): Capture the Flag ends on POINTS (first to
	# CTF_POINTS_LIMIT = 9), or on the timer — most points wins.
	# QA-114: full capture = 3 pts, relay bank = 1 pt, so 3 full
	# captures still win (3 x 3 = 9), but relay banks count too.
	if game_mode == 4:
		var red_pts: int = int(_ctf_scores.get(0, 0))
		var blue_pts: int = int(_ctf_scores.get(1, 0))
		if red_pts >= GameData.CTF_POINTS_LIMIT:
			_end_match("RED TEAM", "reached %d points!" % GameData.CTF_POINTS_LIMIT)
			return
		if blue_pts >= GameData.CTF_POINTS_LIMIT:
			_end_match("BLUE TEAM", "reached %d points!" % GameData.CTF_POINTS_LIMIT)
			return
		if _time_left <= 0.0:
			if red_pts > blue_pts:
				_end_match("RED TEAM", "time up - most points wins!")
			elif blue_pts > red_pts:
				_end_match("BLUE TEAM", "time up - most points wins!")
			else:
				_end_match("DRAW", "time up - tied on points!")
			return
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
		# QA-078: "id" lets the end screen record THIS phone's stats.
		rows.append({"id": child.peer_id, "name": child.player_name, "kills": child.kills, "deaths": child.deaths, "team": child.team, "color": child.player_color, "rounds": int(_round_wins.get(child.peer_id, 0)), "shots": child._shots_fired, "hits": child._shots_hit, "streak": int(_best_streaks.get(child.peer_id, 0))})
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
		star.custom_minimum_size = Vector2(44, 44)
		star.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		star.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mvp_row.add_child(star)
		var mvp_lbl := Label.new()
		# QA-113 (v3.9): the old text ("... best streak N") ran
		# past the 560 px panel — the streak is already a column
		# in the table below, so the banner keeps kills + accuracy
		# only. clip_text is a safety net for very long names.
		mvp_lbl.text = "MVP: %s — %d kills, %d%% accuracy" % [
			String(mvp["name"]), int(mvp["kills"]), int(mvp_st["accuracy"]),
		]
		mvp_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mvp_lbl.add_theme_font_size_override("font_size", 24)
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
	# QA-113 (v3.9): end-of-match rows use the same aligned columns
	# as the scoreboard (Survival shows Rounds, other modes Streak).
	end_list.add_child(_stats_header_row("ROUNDS" if game_mode == 2 else "STREAK"))
	end_list.add_child(HSeparator.new())
	var rank := 1
	for r in rows:
		var team_txt := ""
		if int(r["team"]) == 0:
			team_txt = " [RED]"
		elif int(r["team"]) == 1:
			team_txt = " [BLUE]"
		var st2: Dictionary = GameData.compute_stats(int(r["kills"]), int(r["deaths"]), int(r.get("shots", 0)), int(r.get("hits", 0)))
		var extra := str(int(r.get("rounds", 0))) if game_mode == 2 else str(int(r.get("streak", 0)))
		end_list.add_child(_stats_row(rank, String(r["name"]), team_txt, int(r["kills"]), int(r["deaths"]), float(st2["kd"]), int(st2["accuracy"]), false, r["color"], extra))
		rank += 1
	# QA-078: record this match in the local lifetime stats, once
	# per match. The rows carry the peer id now, so each phone
	# finds its own row. Fake rows (features test) carry no id and
	# record nothing. A draw is not a win.
	if not _stats_recorded:
		var my_id := multiplayer.get_unique_id()
		for r in rows:
			if int(r.get("id", -1)) == my_id:
				var won := false
				if winner != "DRAW":
					if game_mode == 1:
						var me := players_node.get_node_or_null(str(my_id))
						var my_team := int(me.team) if me != null else -1
						won = (winner == "RED TEAM" and my_team == 0) or (winner == "BLUE TEAM" and my_team == 1)
					else:
						won = winner == String(r["name"]) or winner == "You"
				GameData.record_match(int(r["kills"]), int(r["deaths"]), won)
				_stats_recorded = true
				break
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
	if small:
		# QA-092 (v3.7): bullet impacts + hard landings use the
		# library hit spark (white-gold flash + twinkle + ring +
		# fast sparks) instead of the old static Sky Brawl spark
		# sprite. Same call sites, same timing, better look.
		ReebooFx2D.spawn(HIT_SPARK_SCENE, fx_node, pos)
		return
	var spr := Sprite2D.new()
	# Phase 4: Sky Brawl hit spark (small) / explosion sunburst
	# (large) instead of the old smoke/explosion sprites.
	spr.texture = SB_EXPLOSION_TEX
	spr.position = pos
	spr.scale = Vector2(0.7, 0.7)
	spr.modulate = Color(1, 1, 1, 0.9)
	fx_node.add_child(spr)
	var tw := create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.6, 0.25)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.25)
	tw.tween_callback(spr.queue_free)
	audio.play("hit")


# QA-092 (v3.7): pickup grab sparkle — the library coin-pickup
# effect (gold ring + twinkle + rising glints) at the spot where a
# pickup was taken. Called from pickup.gd despawn(grabbed=true),
# which runs on every peer, so everyone sees the grab.
func spawn_pickup_fx(pos: Vector2) -> void:
	ReebooFx2D.spawn(COIN_PICKUP_SCENE, fx_node, pos)


# QA-085 (v3.7): landing dust — a soft tan dust puff at the feet.
# Purely visual, same tween-and-free pattern as spawn_impact_fx.
func spawn_dust_fx(pos: Vector2) -> void:
	var spr := Sprite2D.new()
	spr.texture = DUST_TEX
	spr.position = pos
	spr.scale = Vector2(0.8, 0.8)
	spr.rotation = randf() * TAU
	spr.modulate = Color(1, 1, 1, 0.85)
	fx_node.add_child(spr)
	var tw := create_tween()
	tw.tween_property(spr, "scale", spr.scale * 1.6, 0.35)
	tw.parallel().tween_property(spr, "modulate:a", 0.0, 0.35)
	tw.tween_callback(spr.queue_free)


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
				# when its explosion kills. QA-069: same guard as
				# bullet.gd — only if the host's copy still shows
				# the victim alive and unprotected, or a refused
				# hit (spawn protection / already dead) becomes a
				# phantom kill in the feed and on the scoreboard.
				var u := dist / radius
				var amount := int(round(damage * pow(1.0 - u * u, 2.0)))
				var lethal: bool = int(child.health) - amount <= 0 and child.alive and child._spawn_protect_timer <= 0.0
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
	# QA-092 (v3.7): the blast core is the library explosion_small
	# (toon fireball + smoke + shockwave + embers, shader-driven)
	# instead of the old static fireball/smoke sprites. The base
	# effect is ~125 px wide, so it scales by radius / 62.5.
	# The white flash, debris, GPUParticles2D burst (QA-091) and
	# distance-scaled shake stay — the library's own shockwave ring
	# replaces the old Line2D ring, so the ring is not drawn twice.
	var boom := ReebooFx2D.spawn(EXPLOSION_SMALL_SCENE, fx_node, pos)
	boom.scale = Vector2(radius / 62.5, radius / 62.5)
	# GAP-24: white flash + debris. Visual-only; no damage code
	# anywhere in this FX.
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
	# QA-091 (v3.7, GRENADE_SPEC §4): GPUParticles2D blast burst —
	# orange sparks that fly out, slow under gravity and fade — plus
	# camera shake for the LOCAL player scaled by distance (full at
	# the blast, none past 3x the blast radius). The short white
	# flash on detonation already existed (GAP-24, above), and the
	# wall ray-check already existed in request_explosion (GAP-12),
	# so neither is added here. Purely visual: no damage code.
	var parts := GPUParticles2D.new()
	parts.texture = PARTICLE_DOT_TEX
	parts.amount = 28
	parts.lifetime = 0.55
	parts.one_shot = true
	parts.explosiveness = 0.9
	parts.position = pos
	var pmat := ParticleProcessMaterial.new()
	pmat.direction = Vector3(0, -1, 0)
	pmat.spread = 180.0
	# QA-101 (v3.8): particle speed scales with the blast radius, so
	# the smaller grenade burst (120) reads smaller. QA-109: rockets
	# are 120 too now; only barrels (still 170) are unchanged. The
	# boom core, flash and debris above already scale with radius.
	pmat.initial_velocity_min = 120.0 * radius / 170.0
	pmat.initial_velocity_max = 420.0 * radius / 170.0
	pmat.gravity = Vector3(0, 500, 0)
	pmat.damping_min = 50.0
	pmat.damping_max = 120.0
	pmat.scale_min = 0.5
	pmat.scale_max = 1.2
	pmat.color = Color(1.0, 0.6, 0.2)
	parts.process_material = pmat
	fx_node.add_child(parts)
	parts.emitting = true
	var twp := create_tween()
	twp.tween_interval(1.2)
	twp.tween_callback(parts.queue_free)
	var lp = _get_local_player()
	if lp != null:
		var d: float = lp.global_position.distance_to(pos)
		var k := clampf(1.0 - d / (radius * 3.0), 0.0, 1.0)
		if k > 0.0:
			lp.add_shake(0.6 * k)
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
			# entry so the chip renders in the HUD shot. On Skyfall
			# also seed the 3 slots (QA-119) + an invisible enemy
			# (QA-121 red warning) so the HUD shot proves the new
			# top-left / top-right design.
			_add_kill_feed_entry(1, 1, 0)
			var lp4 = _get_local_player()
			if lp4 != null and map_id == GameData.SKYFALL_MAP_ID:
				lp4.apply_powerup(8)
				lp4.apply_powerup(10)
				lp4.apply_powerup(7)
				_do_spawn(201, "InvisBot", 1, 0, -1)
				var bot4 = players_node.get_node_or_null("201")
				if bot4 != null:
					bot4.set("invisibility_timer", 30.0)
			# QA-122 (v3.11): low-bar proof — the HUD capture shows
			# health 35 (amber) + fuel 20 (amber) so the redesigned
			# bars are verified at low values too; the level shots
			# already prove the full (100/100) state.
			if lp4 != null:
				lp4.health = 35
				lp4.fuel = 20.0
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


# v3.7 VISUALS-SCREENSHOT MODE (--v37-shots): staged captures of
# the new v3.7 visuals for the proof shots. Runs as auto-host; the
# countdown is skipped (this flag is in _is_test_mode). The sticks
# are driven through the same real touch handlers as the smoke
# test. Stage 1 holds the move stick up (jetpack) and the aim
# stick up-right (firing the rifle); stage 2 captures the flame +
# muzzle flash; stage 3 stops, spawns a health + a weapon pickup
# in front of the player and captures them; stage 4 forces the
# shader hit flash and captures it; stage 5 quits.
func _update_v37shots(delta: float) -> void:
	_v37_timer += delta
	var stage := int(_v37_timer / 1.0)
	if stage == _v37_stage:
		return
	_v37_stage = stage
	var lp = _get_local_player()
	match stage:
		1:
			if lp != null:
				lp.fuel = PhysicsConfig.FUEL_MAX
				lp.position = Vector2(2100, 1350)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
			_smoke_set_move(Vector2(0, -60))
			_smoke_set_aim(Vector2(42, -42))
			_smoke_set_fire(true)
		2:
			_capture_shot("user://shot_v37_flame.png")
		3:
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
			if lp != null:
				spawn_pickup_remote(lp.position + Vector2(150, -20), "v37_health", 5)
				spawn_pickup_remote(lp.position + Vector2(280, -20), "v37_smg", 1)
			_capture_shot("user://shot_v37_pickup.png")
		4:
			if lp != null:
				lp._hit_flash_timer = 0.09
			_capture_shot("user://shot_v37_hitflash.png")
		5:
			print("V37SHOTS DONE")
			get_tree().quit()


# v3.8 SCOPE-SCREENSHOT MODE (--v38-shots, QA-105): staged captures
# of the sniper scope + sight line and the rifle scope. Runs as
# auto-host; the countdown is skipped. Stage 1: sniper, open sky,
# aim LEFT from the right y670 tower tier, scoped — the sight line
# is GREEN (clear). Stage 3: same sniper, aim straight down at
# the platform below — the line is RED (blocked). Stage 5: rifle
# scoped (1.5x, no sight line). Stage 7: SMG — the SCOPE button
# hides (no scope). Each capture waits a full second so the camera
# zoom eases in. QA-111: stage 1 used to stand at (1500,300)
# aiming right, but the Ironfall peak (y330 platform + bunker +
# comms tower) now blocks that path, so the "clear" line came out
# red — moved to (2950,639) aiming left, where the y645 band is
# clear for the full 2560 px sight range.
func _update_v38shots(delta: float) -> void:
	_v38_timer += delta
	var stage := int(_v38_timer / 1.0)
	if stage == _v38_stage:
		return
	_v38_stage = stage
	var lp = _get_local_player()
	match stage:
		1:
			if lp != null:
				lp.weapon = 3
				lp.mag_ammo = int(lp.WEAPONS[3]["mag"])
				lp._update_gun_texture()
				lp.position = Vector2(2950, 639)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				lp.scoped = true
			_smoke_set_move(null)
			_smoke_set_aim(Vector2(-60, 0))
			_smoke_set_fire(true)
		2:
			_capture_shot("user://shot_v38_scope_clear.png")
		3:
			if lp != null:
				lp.position = Vector2(1500, 700)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				lp.scoped = true
			_smoke_set_aim(Vector2(0, 60))
			_smoke_set_fire(true)
		4:
			_capture_shot("user://shot_v38_scope_blocked.png")
		5:
			if lp != null:
				lp.weapon = 0
				lp.mag_ammo = int(lp.WEAPONS[0]["mag"])
				lp._update_gun_texture()
				lp.position = Vector2(1500, 300)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				lp.scoped = true
			_smoke_set_aim(Vector2(60, 0))
			_smoke_set_fire(true)
		6:
			_capture_shot("user://shot_v38_rifle_scope.png")
		7:
			if lp != null:
				lp.weapon = 1
				lp.mag_ammo = int(lp.WEAPONS[1]["mag"])
				lp._update_gun_texture()
				lp.scoped = false
			_smoke_set_aim(Vector2(60, 0))
			_smoke_set_fire(true)
		8:
			_capture_shot("user://shot_v38_smg_noscope.png")
		9:
			print("V38SHOTS DONE")
			get_tree().quit()


# v3.8 QA-108 GLITCH-SCREENSHOT MODE (--glitch-shots): staged
# captures of the gun hold (all 6 weapons: aim right / up / down /
# firing) and the headgear (all 7: idle / jetpack / landed after
# jetpack / run / fall) to user://shot_glitch_*.png. Runs as
# auto-host; the countdown is skipped (this flag is in
# _is_test_mode). Each step is two 1 s stages: setup, then capture.
# The capture stage also prints the helmet sprite position and the
# gun's barrel-tip vs muzzle-flash positions, so a misalignment is
# visible in the log as well as in the picture.
func _update_glitchshots(delta: float) -> void:
	_glitch_timer += delta
	var stage := int(_glitch_timer / 1.0)
	if stage == _glitch_stage:
		return
	_glitch_stage = stage
	if _glitch_steps.is_empty():
		_glitch_build_steps()
	var step_idx := stage / 2
	if stage % 2 == 0:
		if step_idx >= _glitch_steps.size():
			print("GLITCHSHOTS DONE")
			get_tree().quit()
			return
		_glitch_setup(_glitch_steps[step_idx])
	else:
		if step_idx >= _glitch_steps.size():
			return
		var step: Dictionary = _glitch_steps[step_idx]
		var lp = _get_local_player()
		if lp != null and String(step.get("repos", "")) == "air":
			var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
			lp.position = Vector2(1500, floor_top - 300.0)
			lp.sync_position = lp.position
			lp.velocity = Vector2.ZERO
		if lp != null and bool(step.get("fire_flash", false)):
			lp._muzzle_timer = 1.0
		if lp != null:
			var hp := Vector2.ZERO
			if lp._helmet_sprite != null:
				hp = lp._helmet_sprite.position
			var gp := Vector2.ZERO
			var grot := 0.0
			if lp._gun != null:
				gp = lp._gun.position
				grot = lp._gun.rotation
			var dir := Vector2(cos(grot), sin(grot))
			var tip: Vector2 = gp + dir * 27.5
			# QA-108: read the REAL muzzle-flash node, not a hardcoded
			# 55 px — the flash used to sit 27.5 px past the barrel tip.
			var flash: Vector2 = gp + dir * 55.0
			if lp._muzzle != null:
				flash = lp.to_local(lp._muzzle.global_position)
			print("GLITCH %s helmet_pos=%s gun_pos=%s rot=%.2f tip=%s flash=%s anim=%s" % [String(step["name"]), str(hp), str(gp), grot, str(tip), str(flash), String(lp._current_anim)])
		_capture_shot("user://" + String(step["file"]))


func _glitch_build_steps() -> void:
	_glitch_steps = []
	# Gun hold: every weapon, aim right + aim up + firing flash.
	for w in range(6):
		_glitch_steps.append({"name": "G%d_RIGHT" % w, "file": "shot_glitch_gun%d_right.png" % w, "w": w, "h": 0, "pos": "floor", "aim": Vector2(60, 0)})
		_glitch_steps.append({"name": "G%d_UP" % w, "file": "shot_glitch_gun%d_up.png" % w, "w": w, "h": 0, "pos": "floor", "aim": Vector2(0, -60)})
		_glitch_steps.append({"name": "G%d_FIRE" % w, "file": "shot_glitch_gun%d_fire.png" % w, "w": w, "h": 0, "pos": "floor", "aim": Vector2(60, 0), "fire_flash": true})
	# Aim down (rifle + sniper) and running with the rifle.
	_glitch_steps.append({"name": "G0_DOWN", "file": "shot_glitch_gun0_down.png", "w": 0, "h": 0, "pos": "floor", "aim": Vector2(0, 60)})
	_glitch_steps.append({"name": "G3_DOWN", "file": "shot_glitch_gun3_down.png", "w": 3, "h": 0, "pos": "floor", "aim": Vector2(0, 60)})
	_glitch_steps.append({"name": "G0_RUN", "file": "shot_glitch_gun0_run.png", "w": 0, "h": 0, "pos": "floor", "pos_x": 900.0, "aim": Vector2(60, 0), "move": Vector2(60, 0)})
	# Headgear: every piece, idle / mid-jetpack / landed after jetpack.
	for h in range(7):
		_glitch_steps.append({"name": "H%d_IDLE" % h, "file": "shot_glitch_cap%d_idle.png" % h, "w": 0, "h": h, "pos": "floor", "aim": Vector2(60, 0)})
		_glitch_steps.append({"name": "H%d_JET" % h, "file": "shot_glitch_cap%d_jet.png" % h, "w": 0, "h": h, "pos": "floor", "move": Vector2(0, -55)})
		_glitch_steps.append({"name": "H%d_LAND" % h, "file": "shot_glitch_cap%d_land.png" % h, "w": -1, "h": -1, "pos": "floor", "aim": Vector2(60, 0)})
	# Cap (2) while running and while falling.
	_glitch_steps.append({"name": "H2_RUN", "file": "shot_glitch_cap2_run.png", "w": 0, "h": 2, "pos": "floor", "pos_x": 900.0, "aim": Vector2(60, 0), "move": Vector2(60, 0)})
	_glitch_steps.append({"name": "H2_FALL", "file": "shot_glitch_cap2_fall.png", "w": 0, "h": 2, "pos": "air", "repos": "air"})


func _glitch_setup(step: Dictionary) -> void:
	var lp = _get_local_player()
	_smoke_set_aim(null)
	_smoke_set_fire(false)
	_smoke_set_move(null)
	if lp == null:
		return
	if int(step.get("w", -1)) >= 0:
		lp.weapon = int(step["w"])
		lp.mag_ammo = int(lp.WEAPONS[int(step["w"])]["mag"])
		lp._update_gun_texture()
	# NOTE: the LAND steps pass h = -1 on purpose — _update_helmet
	# resets the helmet position to (1, _helmet_y), which would
	# hide the stuck-after-jetpack X offset this probe is looking
	# for. The helmet is set in the JET step and left alone here.
	if int(step.get("h", -1)) >= 0:
		lp.helmet = int(step["h"])
		lp._update_helmet()
	var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	# QA-127 (v3.11): default x1400, NOT 1500 — Ironfall has a live
	# weapon pickup spawn at (1500, 1320) and the player teleports
	# onto it, so a shotgun spawned mid-run once auto-switched the
	# weapon (G3_UP captured "Shotgun 6/18" instead of the Sniper).
	# Picking it up is correct game behaviour; the teleport spot
	# was the bug. 1400 is 100 px clear of that spawn.
	var px := float(step.get("pos_x", 1400.0))
	var pos_kind := String(step.get("pos", "floor"))
	if pos_kind == "floor":
		lp.position = Vector2(px, floor_top - 43.0)
	elif pos_kind == "air":
		lp.position = Vector2(px, floor_top - 300.0)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	lp.health = 100
	if not lp.alive:
		lp._respawn()
	var aim = step.get("aim", null)
	if aim != null:
		_smoke_set_aim(aim)
	var move = step.get("move", null)
	if move != null:
		_smoke_set_move(move)


# v3.8 QA-111 MAP-SCREENSHOT MODE (--map-shot): staged captures
# of the Ironfall map in 5 views — left tower, centre peak
# (bunker + dish + red flag + helicopter), centre floor
# (waterfall + pool + tunnel), right tower, and the full moon —
# to user://shot_map_*.png. Runs as auto-host; the countdown is
# skipped. Each view is two 1 s stages (setup, then capture); the
# camera smoothing is reset on teleport so the view is settled
# by the capture. The tower views stand the player on the y840
# perches so the y670 towers are in frame.
func _update_mapshots(delta: float) -> void:
	_map_timer += delta
	var stage := int(_map_timer / 1.0)
	if stage == _map_stage:
		return
	_map_stage = stage
	var lp = _get_local_player()
	var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	match stage:
		1:
			if lp != null:
				lp.position = Vector2(800, 800)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		2:
			_capture_shot("user://shot_map_left.png")
		3:
			if lp != null:
				lp.position = Vector2(1750, 287)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		4:
			_capture_shot("user://shot_map_peak.png")
		5:
			if lp != null:
				lp.position = Vector2(1600, floor_top - 43.0)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		6:
			_capture_shot("user://shot_map_waterfall.png")
		7:
			if lp != null:
				# QA-111: stand on the (2800,840) perch — the camera
				# sits ~190 px left of the player, so standing on the
				# (2150,840) perch put the (3030,670) tower off-frame.
				lp.position = Vector2(2950, 800)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		8:
			_capture_shot("user://shot_map_right.png")
		9:
			if lp != null:
				lp.position = Vector2(2250, 467)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
		10:
			_capture_shot("user://shot_map_moon.png")
		11:
			print("MAPSHOTS DONE")
			get_tree().quit()


# QA-112 (v3.9) SKYFALL-SCREENSHOT MODE (--skyfall-shots): one
# capture per level (6 levels, centre x1800), to
# user://shot_sf_L1.png ... shot_sf_L6.png. Runs as auto-host
# on map 5; the countdown is skipped. Odd stages move the player
# to the level, even stages capture (1 s apart, so the camera
# smoothing settles).
func _update_skyfallshots(delta: float) -> void:
	_sf_shot_timer += delta
	var stage := int(_sf_shot_timer / 1.0)
	if stage == _sf_shot_stage:
		return
	_sf_shot_stage = stage
	var lp = _get_local_player()
	if stage >= 1 and stage <= 12:
		var lvl := (stage + 1) / 2 # 1-6
		if stage % 2 == 1:
			if lp != null:
				var cy := 10800.0 - (float(lvl) - 0.5) * 1800.0
				# QA-123: L6's centre x1800 is INSIDE the summit
				# gate (box x1742-1858, y484-862) and embedded in
				# the summit platform, so the stuck-recovery fires
				# and moves the player to the base spawn before
				# the capture — the L6 shot showed the base, not
				# the summit. Stand left of the gate instead, on
				# the same (1200, 862) summit platform, with open
				# sky above; the gate and flag stay in frame.
				var cx := 1400.0 if lvl == 6 else 1800.0
				lp.position = Vector2(cx, cy - 40.0)
				lp.sync_position = lp.position
				lp.velocity = Vector2.ZERO
				if lp._camera != null:
					lp._camera.reset_smoothing()
			_smoke_set_move(null)
			_smoke_set_aim(null)
			_smoke_set_fire(false)
			# QA-119/121/130 (v3.11): seed the HUD proof — filled
			# slots + an invisible enemy (red warning) at stage 1,
			# feed messages refreshed at stage 7 (5 s expiry).
			if stage == 1 and lp != null:
				lp.apply_powerup(8)
				lp.apply_powerup(10)
				lp.apply_powerup(7)
				# QA-132: activate the shield (slot 0) so the L1
				# shot shows a live effect (shield ring + active
				# boost label), not just filled slots.
				lp.activate_slot(0)
				_do_spawn(201, "InvisBot", 1, 0, 1)
				var sf_bot = players_node.get_node_or_null("201")
				if sf_bot != null:
					sf_bot.set("invisibility_timer", 30.0)
			if stage == 1 or stage == 7:
				_ctf_feed("Player  ☠  TestBot   —  Rifle", UI_FONT)
				_ctf_feed("⚑ BLUE: at summit", Color(0.25, 0.55, 0.95))
		else:
			_capture_shot("user://shot_sf_L%d.png" % lvl)
	elif stage >= 13:
		print("SKYFALLSHOTS DONE")
		get_tree().quit()


# v3.8 QA-110 LAND-SCREENSHOT MODE (--land-shot): drops the
# player from high (600 px, x1100 — a clean gap through every
# tier to the floor) and captures the exact landing frame plus
# one 0.15 s later, to user://shot_land_*.png. Runs as auto-host;
# the countdown is skipped. The hard-landing FX (fall speed
# > 550) used to be a white-gold hit spark at the legs plus a
# dust puff; the spark call is removed, so the shots must show
# dust only and no sparkle.
func _update_landshots(delta: float) -> void:
	_land_timer += delta
	var lp = _get_local_player()
	if _land_stage == -1 and lp != null:
		var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
		lp.position = Vector2(1100, floor_top - 600.0)
		lp.sync_position = lp.position
		lp.velocity = Vector2.ZERO
		if lp._camera != null:
			lp._camera.reset_smoothing()
		_smoke_set_move(null)
		_smoke_set_aim(null)
		_smoke_set_fire(false)
		_land_stage = 0
		_land_armed = true
		return
	if _land_stage == 0 and _land_armed and lp != null:
		if not lp.is_on_floor():
			# Sample the falling speed while airborne: reading
			# _fall_speed after landing is one physics frame too
			# late (it resets to a single frame of gravity, ~23).
			_land_maxfall = maxf(_land_maxfall, lp._fall_speed)
		elif lp.is_on_floor():
			print("LAND impact_speed=%.0f" % _land_maxfall)
			_capture_shot("user://shot_land_at.png")
			_land_t0 = _land_timer
			_land_stage = 1
	elif _land_stage == 1 and _land_timer - _land_t0 >= 0.15:
		_capture_shot("user://shot_land_after.png")
		_land_stage = 2
	elif _land_stage == 2 and _land_timer - _land_t0 >= 0.5:
		# Quit a full stage after the last capture: _capture_shot
		# awaits 2 frames before saving, and quitting in the same
		# stage kills the save (that lost shot_land_after.png once).
		print("LANDSHOTS DONE")
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
		{"name": "PRESS-UP-JUMP", "wait": 0.6, "setup": _jt_s_press_up, "check": _jt_c_press_up},
		# QA-117 (v3.9 fix round): wait 0.6 s, not 0.4 s. The jetpack
		# only thrusts once the jump's velocity decays above -320
		# (from -660, ~0.24 s of physics), so at 0.4 s of wall time
		# the fuel has barely drained — and under xvfb load the
		# physics lags wall time, so the 0.4 s check caught fuel
		# exactly at max (jetpack not yet engaged) in 2 of 3 map-0 runs.
		# 0.6 s gives the thrust time to engage and drain fuel even
		# with the lag. The check is unchanged (fuel < FUEL_MAX, risen
		# > 20 px, not on floor).
		# QA-099 (v3.7): wait 1.5 s, not 0.5 s. This step follows
		# PRESS-UP-JUMP, and the jump's air time is ~1.0 s (155 px apex
		# + brief jetpack thrust) — at 0.5 s the player is still
		# airborne, so the check measured air-drag decay (vel.x 91),
		# not the ground stop. It only passed before because the player
		# was pinned against Ironfall's floor crate (vel.x 0 from the
		# start — a vacuous pass). 1.5 s lands the player (~1.05 s) and
		# stops it (~0.1 s of ground friction) before the check.
		{"name": "RELEASE-STOPS", "wait": 1.5, "setup": _jt_s_release_move, "check": _jt_c_release_stops},
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
		{"name": "AIM-RELEASE-NO-LEFT-2400", "wait": 0.8, "setup": _jt_s_aim_right_mouse_2400, "check": _jt_c_aim_release_no_left_2400},
		# QA-117 (v3.9 fix round): the Skyfall height bar's 170 px-wide
		# rect overlapped the move stick and swallowed real touches
		# on it (the sim calls _on_touch_press directly, so the old
		# steps never saw it). These two steps reproduce it through
		# the real GUI/input pipeline.
		{"name": "GUI-STICK-CLEAR", "wait": 0.3, "setup": _jt_s_noop, "check": _jt_c_gui_stick_clear},
		{"name": "GUI-PRESS-LEFT", "wait": 0.6, "setup": _jt_s_gui_press_left, "check": _jt_c_gui_press_left},
		# QA-117: left push through the real GUI pipeline on a
		# middle level (L4 bridge) and the summit, not just the base.
		{"name": "GUI-PRESS-LEFT-MID", "wait": 0.6, "setup": _jt_s_gui_press_left_mid, "check": _jt_c_gui_press_left},
		{"name": "GUI-PRESS-LEFT-TOP", "wait": 0.6, "setup": _jt_s_gui_press_left_top, "check": _jt_c_gui_press_left},
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
	# QA-099 (v3.7): fuel < FUEL_MAX, not < MAX-2 — any drain proves
	# the thrust ran; < MAX-2 needs >= 2 units in 0.4 s, which
	# load-starved physics frames don't deliver (one suite run read
	# fuel 1 under max with jetpacking=true and 128 px of rise).
	var ok: bool = v.y < -0.5 and not lp.is_on_floor() and lp.position.y < _joy_pos_before.y - 20.0 and lp.fuel < PhysicsConfig.FUEL_MAX
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
	lp.position = Vector2(2100, 1318) # QA-071b: was 1350 — embedded 29 px into the floor with the 62-tall capsule; the solver could push the player DOWN through the 48 px slab (DIAG-UP-RIGHT vel.y=0, RESOLUTION-2400 vel.x=0)
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
	lp.position = Vector2(2100, 1318) # QA-071b: was 1350 — embedded 29 px into the floor with the 62-tall capsule; the solver could push the player DOWN through the 48 px slab (DIAG-UP-RIGHT vel.y=0, RESOLUTION-2400 vel.x=0)
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
	# Clear floor at (1600, 1318): the old (2100, 1350) spot's "clear
	# run right" is blocked 13 px on by the barrels at 2150 (QA-072
	# decor, solid 2133..2166) — the player runs into them and vel.x
	# reads 0. From 1600 the next solid is the barrels at 1920,
	# 283 px away, so the player is still running at the 0.5 s check.
	var lp = _jt_lp()
	lp.position = Vector2(1600, 1318)
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


# QA-054 (double-check): the 1280 AIM no-left check exists, but there
# was NO AIM no-left check at the tall resolution — only the MOVE one.
# Same sequence as _jt_s_aim_right_mouse, re-run at 2400x1080.
func _jt_s_aim_right_mouse_2400() -> void:
	var lp = _jt_lp()
	lp.position = Vector2(2100, 1318) # QA-071b: was 1350 — embedded 29 px into the floor with the 62-tall capsule; the solver could push the player DOWN through the 48 px slab (DIAG-UP-RIGHT vel.y=0, RESOLUTION-2400 vel.x=0)
	lp.velocity = Vector2.ZERO
	get_window().size = Vector2(2400, 1080)
	_joy_aim_before = lp.aim_angle
	_joy_mouse_seen = false
	_jt_press_aim(Vector2(60, 0))
	_jt_inject_mouse_press(_jt_aim_center() + Vector2(60, 0))
	get_tree().create_timer(0.3).timeout.connect(_jt_release_aim_mouse)


func _jt_c_aim_release_no_left_2400() -> Array:
	var lp = _jt_lp()
	var centre_x := get_viewport().get_visible_rect().size.x * 0.5
	var ok: bool = _joy_mouse_seen and _joy_mouse_pos_seen.x > centre_x \
		and lp.facing == 1 and lp.velocity.x >= -5.0 \
		and not touch_firing and touch_aim == Vector2.ZERO \
		and cos(lp.aim_angle) > 0.5
	get_window().size = Vector2(1280, 720)
	return [ok, "mouse_seen=%s mouse_pos=%s (want right of centre %.0f) facing=%d vel.x=%d firing=%s aim_vec=%s aim=%.2f at 2400x1080 (want facing 1, not firing, aim right)" % [_joy_mouse_seen, _joy_mouse_pos_seen, centre_x, lp.facing, round(lp.velocity.x), touch_firing, touch_aim, lp.aim_angle]]


# --- QA-117: the Skyfall height bar ate real touches on the move stick ---
# A Control with mouse_filter STOP consumes any touch landing in its
# rect before _unhandled_input ever sees it. The height bar's rect
# (x12-182, y264-708) covered the move stick's left 61% including its
# centre (165, 555), so a real left-push press on Skyfall was eaten
# by the bar and the player never moved. The old steps call
# _on_touch_press directly, so they never saw it.

func _jt_gui_blockers() -> Array:
	# Every visible STOP control whose rect covers a point on the
	# move stick where a real thumb press can land (centre, and
	# 40 px left of centre — a left-push press point). The sticks
	# themselves are MOUSE_FILTER_IGNORE, and the intended buttons
	# (reload/grenade/switch/pause/score) sit far from the stick.
	var pts: Array = [move_stick.get_global_rect().get_center(), move_stick.get_global_rect().get_center() + Vector2(-40, 0)]
	var bad: Array = []
	var stack: Array = [hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c := n as Control
			if c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP:
				var r := c.get_global_rect()
				for p in pts:
					if r.has_point(p):
						bad.append("%s rect=%s covers %s" % [c.name, str(r), str(p)])
						break
		for ch in n.get_children():
			stack.append(ch)
	return bad


func _jt_c_gui_stick_clear() -> Array:
	var bad := _jt_gui_blockers()
	var ok: bool = bad.is_empty()
	return [ok, "blockers=%s" % ["none" if ok else "; ".join(bad)]]


func _jt_gui_press_left() -> void:
	# A REAL touch through the viewport input pipeline (GUI first,
	# then _unhandled_input) — the exact path a phone finger takes.
	# Press on the stick centre, drag 50 px left, index 903.
	var centre: Vector2 = move_stick.get_global_rect().get_center()
	var to_vp: Vector2 = hud.get_final_transform() * centre
	var press := InputEventScreenTouch.new()
	press.index = 903
	press.pressed = true
	press.position = to_vp
	get_viewport().push_input(press)
	var drag := InputEventScreenDrag.new()
	drag.index = 903
	drag.position = hud.get_final_transform() * (centre + Vector2(-50, 0))
	get_viewport().push_input(drag)


func _jt_s_gui_press_left() -> void:
	_jt_teleport_clear_left()
	_jt_gui_press_left()


func _jt_s_gui_press_left_mid() -> void:
	# QA-132: L3 left row is now (900,6984,600) — stand at (1400,
	# 6950) with 500 px of clear run left. Same real-GUI press.
	var lp = _jt_lp()
	lp.position = Vector2(1400, 6950)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_jt_gui_press_left()


func _jt_s_gui_press_left_top() -> void:
	# Summit platform (top y862, x1200-2400): stand at (1600, 831)
	# with 400 px of clear run left, gate (x1800) to the right.
	var lp = _jt_lp()
	lp.position = Vector2(1600, 831)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_jt_gui_press_left()


func _jt_c_gui_press_left() -> Array:
	var lp = _jt_lp()
	var v := touch_move_vec
	var ok: bool = v.x < -0.5 and absf(v.y) < 0.15 and lp.velocity.x < -50.0 and lp.facing == -1
	# Release the real touch through the same pipeline.
	var rel := InputEventScreenTouch.new()
	rel.index = 903
	rel.pressed = false
	rel.position = hud.get_final_transform() * move_stick.get_global_rect().get_center()
	get_viewport().push_input(rel)
	return [ok, "vec=%s vel.x=%d facing=%d stick_active=%s" % [v, round(lp.velocity.x), lp.facing, str(move_stick.is_active())]]


func _jt_c_fuel_stable() -> Array:
	var lp = _jt_lp()
	# No thrust input: fuel must not decrease (it refills on the ground,
	# stays put in the air — either way it never goes down).
	var ok: bool = lp.fuel >= _joy_fuel_before - 0.5
	return [ok, "fuel=%d (was %d)" % [round(lp.fuel), round(_joy_fuel_before)]]


func _jt_s_press_down() -> void:
	var lp = _jt_lp()
	if map_id == GameData.SKYFALL_MAP_ID:
		# Skyfall: (2100, 900) lands ON the summit platform, so the
		# player is on the floor and vel.y stays 0. x100 is a clear
		# shaft to the base floor (352 px of fall, no platform under
		# it until y10752).
		lp.position = Vector2(100, 10400)
	else:
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
	if map_id == GameData.SKYFALL_MAP_ID:
		# Skyfall: (900, 1318) is mid-air here (no platform under it),
		# so the up-press fires the jetpack instead of a jump and
		# vel.y reads +81 at the check. Stand on the wide y1712
		# platform instead (top y1712, x600-3000): centre y1681.
		# QA-132: the old (900,1542) platform above is gone — the
		# nearest overhead now is the (1500,1424) summit step,
		# far right of x700, and the (700,690) perch is ~990 px
		# above, so the diagonal jump can actually rise; drifting
		# right for 0.5 s only reaches ~x823, still clear of it.
		lp.position = Vector2(700, 1681)
		lp.sync_position = lp.position
		lp.velocity = Vector2.ZERO
		_jt_press_move(Vector2(42, -42))
		return
	# Open sky above (900, 1318): (2100, 1350) sat under the 1180
	# walkway (bottom 1228) — the 62-tall player's head bonks it at
	# 59 px of rise, so vel.y reads 0 even though it is jetpacking;
	# (1600, 1318) bonks the same walkway (the 1180 level is
	# continuous 1350..2900), and (1400, 1318) drifts right into it
	# while rising (pinned at 1259.065). At x=900 the overhead is the
	# 840 platform (650..990, bottom 888) then the 1010 platform
	# (950..1850, bottom 1058) after drifting right — both clear for
	# the ~160 px rise in the 0.5 s check; the floor run right is
	# clear to the column at 1100.
	lp.position = Vector2(900, 1318)
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
	if map_id == GameData.SKYFALL_MAP_ID:
		# Skyfall: (300, 1350) falls ~3900 px down the L1 shaft to
		# the y8764 walkway — 4 s is not enough to land. Use the
		# base floor with a clear shaft above (x100, no platform
		# overhead): jump, jetpack, fall back to the floor.
		lp.position = Vector2(100, 10718)
	else:
		lp.position = Vector2(300, 1350)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	# QA-132: seed 90 fuel (2 s of thrust at drain 45/s) — the tank
	# is 405 now (9.0 s), so a full tank would still be thrusting
	# at the end of the 4 s window and the player would not have
	# landed yet. 2 s of thrust + the fall back still lands inside
	# 4 s, so the window and the no-rejump check are unchanged;
	# the full-tank drain is covered by P08 (fuel-regen) instead.
	lp.fuel = 90.0
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
		# (f) spawns: the player capsule is 40 wide, 62 tall, centred
		# on the spawn point — it must not start inside a solid.
		for si in spawns.size():
			var sp: Vector2 = spawns[si]
			checked_spawns += 1
			var box := Rect2(sp - Vector2(20, 31), Vector2(40, 62)) # QA-071b: 40x62 capsule
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
	# left edge (e.g. sandbags at x=120) puts
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
		if r.position.x - 20.0 < maxf(from_x, to_x) and r.end.x + 20.0 > minf(from_x, to_x):
			return true
	return false


func _ct_s_walk_into_solid() -> void:
	var cover := _ct_floor_cover()
	if cover == Rect2():
		return
	var lp = _get_local_player()
	# Approach from the right (walk left) when the usual left
	# approach would cross a bounce pad and launch over the cover.
	var right_approach: bool = not _ct_walk_path_has_pad(cover.position.x - 60.0, cover.position.x - 20.0)
	if right_approach:
		_ct_walk_dir = 1
		lp.position = Vector2(cover.position.x - 60.0, cover.end.y - 34.0)
	else:
		_ct_walk_dir = -1
		lp.position = Vector2(cover.end.x + 60.0, cover.end.y - 34.0)
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
		var stopped: bool = lp.position.x <= cover.position.x - 20.0 + 4.0
		return [moved and stopped, "player x=%.0f (started %.0f, cover face %.0f, capsule edge %.0f)" % [lp.position.x, _ct_walk_start_x, cover.position.x, cover.position.x - 20.0]]
	var moved2: bool = lp.position.x < _ct_walk_start_x - 20.0
	var stopped2: bool = lp.position.x >= cover.end.x + 20.0 - 4.0
	return [moved2 and stopped2, "player x=%.0f (started %.0f, cover face %.0f, capsule edge %.0f, walking left)" % [lp.position.x, _ct_walk_start_x, cover.end.x, cover.end.x + 20.0]]


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
	# QA-071b: throw from 60 px, not 150 px — at 150 px the grenade's
	# arc (init vel (575, -490)) cleared the 108-tall column by 5 px
	# once the throw origin rose 10 px with the bigger player; the
	# 60 px throw tests the same property (grenade bounces off a tall
	# solid) with 30+ px of margin on every map.
	lp.position = Vector2(tall.position.x - 60.0, tall.end.y - 34.0)
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
	# QA-132: Skyfall's decor is L1-only now (user: clean everything
	# unnecessary) and its tallest solid is 40 px — a grenade thrown
	# with init vel (575, -490) rises ~86 px and clears it, so there
	# is nothing tall enough to bounce off. The bounce itself is
	# covered on the other maps; a short solid is not a failure.
	if tall.size.y < 90.0:
		return [true, "tallest solid only %.0f px tall — too short to block a grenade arc (covered on Ironfall)" % tall.size.y]
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
	lp.position = Vector2(bush.position.x - 60.0, bush.end.y - 34.0)
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
	var ok: bool = lp.position.x > bush.end.x + 20.0
	return [ok, "player x=%.0f (bush %s, must be past %.0f)" % [lp.position.x, bush, bush.end.x + 20.0]]


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
		{"name": "RIFLE-STRAIGHT-2S-HOLD", "wait": 2.5, "setup": _ft_s_rifle_straight, "check": _ft_c_rifle_straight},
		{"name": "SMG-SPREAD-TIGHT", "wait": 0.7, "setup": _ft_s_smg_spread, "check": _ft_c_smg_spread},
		{"name": "ROCKET-STRAIGHT", "wait": 0.5, "setup": _ft_s_rocket_straight, "check": _ft_c_rocket_straight},
		{"name": "SNIPER-SCOPE-ZOOM", "wait": 0.8, "setup": _ft_s_sniper_scope, "check": _ft_c_sniper_scope},
		{"name": "BULLET-INSIDE-GEOMETRY", "wait": 0.3, "setup": _ft_s_bullet_inside, "check": _ft_c_bullet_inside},
		{"name": "BULLET-SIZE-80PCT", "wait": 0.15, "setup": _ft_s_bullet_size, "check": _ft_c_bullet_size},
		{"name": "MAG-MEMORY", "wait": 0.3, "setup": _ft_s_mag_memory, "check": _ft_c_mag_memory},
		{"name": "RELOAD-REFUND", "wait": 0.6, "setup": _ft_s_reload_refund, "check": _ft_c_reload_refund},
		{"name": "MUZZLE-FLASH", "wait": 0.3, "setup": _ft_s_muzzle_flash, "check": _ft_c_muzzle_flash},
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
	# QA-104/105/106 (v3.8): the fake press lands inside _process
	# (the runner), AFTER _update_touch_state already read the
	# sticks that frame — so the next physics tick would fire a
	# semi-auto weapon with the STALE aim angle (BULLET-INSIDE
	# fired right, the sniper step's angle, instead of left).
	# Refresh the touch state synchronously so the aim direction
	# is visible before any physics tick runs — same reason the
	# press already arms _aim_fire_pending synchronously (QA-027).
	_update_touch_state()


func _ft_release_aim() -> void:
	_on_touch_release(911)
	_ft_fire_owns_aim = false


func _ft_press_fire() -> void:
	if not aim_stick.is_active():
		_ft_fire_owns_aim = true
		_on_touch_press(911, _ft_aim_center() + Vector2(60, 0))
		_update_touch_state()


func _ft_release_fire() -> void:
	if _ft_fire_owns_aim:
		_on_touch_release(911)
		_ft_fire_owns_aim = false


func _ft_set_weapon(id: int) -> void:
	var lp = _ft_lp()
	lp.weapon = id
	lp.mag_ammo = int(lp.WEAPONS[id]["mag"])
	lp.reloading = false
	# QA-104/105/106 (v3.8): each fire-test step runs its own
	# weapon in isolation, so the trigger must start ready. The
	# shared _fire_cooldown survives this direct assignment, and
	# the new slow weapons before BULLET-INSIDE (rocket 1.0 s,
	# sniper 0.9 s) left it running — the pistol was still on
	# cooldown at the 0.3 s check and never fired (33/35 in the
	# first v3.8 suite run). The real switch path
	# (player.switch_weapon) keeps its own cooldown; only the
	# harness resets it here.
	lp._fire_cooldown = 0.0
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
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
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
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.fuel < PhysicsConfig.FUEL_MAX
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
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
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


# QA-061: the Assault Rifle must fire STRAIGHT — hold the trigger
# for a full 2.5 s (20 shots at the 0.125 s rate) and every bullet's
# recorded direction deviation from the aim must be ~0°. Before the
# fix the accumulated recoil spread grew to ~±20-30° by the end of
# the hold. The step runs last so _recoil_accum is already high
# from the earlier firing steps — the worst case, not a fresh gun.
func _ft_s_rifle_straight() -> void:
	var lp = _ft_lp()
	_ft_set_weapon(0)
	_ft_rifle_dev_start = lp.shot_devs.size()
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_rifle_straight() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var total: int = int(lp.shot_devs.size())
	var start: int = mini(_ft_rifle_dev_start, total)
	var n: int = total - start
	var max_dev := 0.0
	for i in range(start, total):
		max_dev = maxf(max_dev, absf(float(lp.shot_devs[i])))
	var max_deg := rad_to_deg(max_dev)
	var ok: bool = n >= 10 and max_deg < 0.5
	return [ok, "rifle shots in hold=%d max deviation=%.2f° (want >=10 shots, <0.5°)" % [n, max_deg]]


# QA-104 (v3.8): the SMG must group tightly — base spread 0.035
# rad + recoil_k 0.015 (was 0.09 + 0.04, "bullets spray
# everywhere"). Fire a ~0.7 s burst from a reset recoil state and
# every bullet's deviation from the aim must stay under 0.15 rad
# (the old values would reach ~0.25 rad in the same burst).
func _ft_s_smg_spread() -> void:
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(1)
	lp._recoil_accum = 0.0
	_ft_smg_dev_start = lp.shot_devs.size()
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_smg_spread() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var total: int = int(lp.shot_devs.size())
	var start: int = mini(_ft_smg_dev_start, total)
	var n: int = total - start
	var max_dev := 0.0
	for i in range(start, total):
		max_dev = maxf(max_dev, absf(float(lp.shot_devs[i])))
	var ok: bool = n >= 5 and max_dev < 0.15
	return [ok, "smg burst shots=%d max deviation=%.3f rad (want >=5 shots, <0.15 rad)" % [n, max_dev]]


# QA-106 (v3.8): the rocket must fly straight along the aim
# direction — gravity 0, no velocity inheritance. Fire it
# horizontally and after 0.5 s its velocity must still point
# exactly right with no downward component (with the old gravity
# 500 the rocket would have vy = +250 by then).
func _ft_s_rocket_straight() -> void:
	var lp0 = _ft_lp()
	if not lp0.alive:
		lp0._respawn()
	lp0.health = 100
	_ft_set_weapon(4)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_rocket_straight() -> Array:
	var lp = _ft_lp()
	var rocket = null
	for b in bullets_node.get_children():
		if b.active and int(b.owner_id) == lp.peer_id and int(b.kind) == 4:
			rocket = b
			break
	var ok := false
	var detail := "no active rocket found"
	if rocket != null:
		var ang := absf(float(rocket.velocity.angle()))
		var vy := absf(float(rocket.velocity.y))
		ok = ang < 0.02 and vy < 5.0 and float(rocket.grav) == 0.0
		detail = "rocket angle=%.3f rad vy=%.1f grav=%.0f (want ~0 / ~0 / 0)" % [ang, vy, float(rocket.grav)]
	_ft_release_aim()
	_ft_release_fire()
	return [ok, detail]


# QA-105 (v3.8): scoping the sniper zooms the camera to 2.0x and
# shows the sight line while aiming. Set scoped directly (the same
# flag the HUD SCOPE button toggles) and check the eased zoom and
# the line after 0.8 s.
func _ft_s_sniper_scope() -> void:
	var lp0 = _ft_lp()
	if not lp0.alive:
		lp0._respawn()
	lp0.health = 100
	_ft_set_weapon(3)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(60, 0))
	lp0.scoped = true


func _ft_c_sniper_scope() -> Array:
	var lp = _ft_lp()
	var zoom := float(lp._camera.zoom.x) if lp._camera != null else 0.0
	var line_ok := lp._sight_line != null and bool(lp._sight_line.visible)
	var ok := zoom > 1.8 and line_ok
	lp.scoped = false
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "sniper scoped zoom=%.2f sight line visible=%s (want >1.8 / true)" % [zoom, str(line_ok)]]


func _ft_s_bullet_inside() -> void:
	# QA-055: a bullet whose muzzle starts INSIDE solid geometry
	# (player flush against a wall, aiming into it) must impact at
	# once, not fly through the wall. The muzzle sits 60 px ahead
	# of the player centre, so standing at x=72 aiming left puts
	# it at x=12 — 12 px inside the 24 px left boundary wall.
	# The left wall is used because the right wall has sandbags at
	# x=3120 on the fire-test map (map 0).
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(5) # pistol: semi-auto, exactly one bullet
	var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	_ft_teleport(Vector2(72.0, floor_top - 43.0))
	_ft_inside_shots0 = lp._shots_fired
	# Bullets from earlier steps may still be flying: remember them
	# so the check counts only the bullet fired in this step. (The
	# pool never reuses a node that is active, so the new bullet's
	# node cannot be in this set.)
	_ft_inside_old = []
	for b in bullets_node.get_children():
		if b.active:
			_ft_inside_old.append(b.get_instance_id())
	_ft_press_aim(Vector2(-60, 0))


func _ft_c_bullet_inside() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var fired: int = int(lp._shots_fired) - _ft_inside_shots0
	# Only bullets spawned in this step count: earlier steps leave
	# strays flying. A bullet that flew through the wall would
	# still be alive at 0.3 s (lifetime ~1.5 s) and past x=0.
	var active := 0
	var past_wall := false
	for b in bullets_node.get_children():
		if b.active and not _ft_inside_old.has(b.get_instance_id()):
			active += 1
			if b.global_position.x < 0.0:
				past_wall = true
	var ok: bool = fired == 1 and active == 0 and not past_wall
	return [ok, "fired=%d (want 1), new active bullets=%d (want 0), past wall=%s" % [fired, active, str(past_wall)]]


func _ft_s_bullet_size() -> void:
	# QA-056: bullets are 20% smaller (visual 80% of v3.3) — assert
	# the polygon extents in the test, not just in code. One pistol
	# shot into open sky (1500, 300), aim right; the bullet is still
	# flying at the 0.15 s check.
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(5)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(60, 0))


func _ft_c_bullet_size() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var half_len := -1.0
	var half_w := -1.0
	var trail_w := -1.0
	for b in bullets_node.get_children():
		if b.active and int(b.owner_id) == lp.peer_id and int(b.kind) == 5:
			var poly: PackedVector2Array = b._visual.polygon
			for p in poly:
				half_len = maxf(half_len, absf(p.x))
				half_w = maxf(half_w, absf(p.y))
			trail_w = b._trail.width
			break
	# v3.3 was 14.0 x 3.0 (trail 3.0); v3.5 QA-056 is 80%: 11.2 x 2.4.
	var ok: bool = half_len > 0.0 and absf(half_len - 11.2) < 0.15 and absf(half_w - 2.4) < 0.15 and absf(trail_w - 2.4) < 0.05
	return [ok, "pistol bullet half-length=%.2f (want 11.2), half-width=%.2f (want 2.4), trail=%.2f (want 2.4)" % [half_len, half_w, trail_w]]


# QA-075: switching weapons must remember each weapon's magazine
# (the old code refilled the mag on every switch, so switching
# away and back refilled the rifle for free). Fire the rifle down
# to 17, then switch through every owned weapon until the rifle
# comes round again: it must still hold 17, not a fresh 30. The
# loop (not two fixed switches) is deliberate: earlier fire steps
# may have picked up extra weapons on the map, so the cycle length
# is not always 2 — the owned list is [rifle, pistol] plus any
# pickups, in that order.
func _ft_s_mag_memory() -> void:
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(0)
	lp.mag_ammo = 17
	for i in 6:
		_on_switch_pressed()
		if lp.weapon == 0 and i > 0:
			break


func _ft_c_mag_memory() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp.weapon == 0 and lp.mag_ammo == 17
	return [ok, "weapon=%d mag=%d after cycling back to the rifle (want weapon 0, mag 17 — the remembered mag, not a refill to 30)" % [lp.weapon, lp.mag_ammo]]


# QA-075: switching mid-reload must not eat the ammo. Start a rifle
# reload with 10 in the mag (20 move from the reserve into the
# pending transfer), then switch before it finishes: the 20 must
# come back to the reserve (90 again), the rifle must remember its
# 10, and the player must not be stuck reloading.
func _ft_s_reload_refund() -> void:
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(0)
	lp._reserve[0] = 90
	lp.mag_ammo = 10
	lp.reloading = false
	_on_reload_pressed() # transfer 20, reserve 90 -> 70
	_on_switch_pressed() # -> pistol: refund 20, reserve back to 90


func _ft_c_reload_refund() -> Array:
	var lp = _ft_lp()
	var res: int = int(lp._reserve.get(0, -1))
	var mem: int = int(lp._mag_memory.get(0, -1))
	var ok: bool = lp.weapon == 5 and not lp.reloading and res == 90 and mem == 10
	return [ok, "weapon=%d reloading=%s rifle reserve=%d (want 90, refunded) rifle remembered mag=%d (want 10)" % [lp.weapon, lp.reloading, res, mem]]


# QA-075: the muzzle flash must fire on every shot, bigger on heavy
# weapons. Hold the rifle trigger for 0.3 s (2+ shots at the 0.125 s
# rate): the flash counter must grow, and the flash sprite scale
# must be the rifle's 1.2x (with the +/-10% per-shot jitter).
func _ft_s_muzzle_flash() -> void:
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(0)
	_fire_flashes_before = lp._muzzle_flashes
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_muzzle_flash() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var scale: float = lp._muzzle.scale.x if lp._muzzle != null else -1.0
	var ok: bool = lp._muzzle_flashes > _fire_flashes_before and scale > 1.05 and scale < 1.35
	return [ok, "muzzle flashes=%d (was %d) scale=%.2f (want rifle 1.2x, 1.05-1.35 with jitter)" % [lp._muzzle_flashes, _fire_flashes_before, scale]]


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
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = _nt_spawn_bot()
	if b != null:
		b.position = Vector2(600, 1318) # QA-071: floor 1352, centre top-34
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
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = _nt_bot()
	if b != null:
		b.position = Vector2(600, 1318) # QA-071: floor 1352, centre top-34
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
# v3.5 RESTART CHECK (game side, --restart-test, QA-060)
# The user reported the game crashing "after starting the game
# once". The flow test never started a SECOND match, so this check
# covers exactly that gap: match 1 (spawn + move + fire) -> leave
# to the menu -> match 2 from a fresh room (spawn + move + fire) ->
# end match 2 -> rematch (reload_current_scene) -> match 2 reloaded
# (spawn + move + fire again). A phase that never spawns fails its
# steps instead of hanging, and the final DONE line prints the
# accumulated counts (menu-side SECOND-LOBBY included). Any script
# error along the way also shows in the runner's error count.
# =====================================================================

func _update_restarttest(delta: float) -> void:
	if _restart_done:
		return
	var phase := GameData.restart_phase
	if phase != 1 and phase != 3 and phase != 4:
		_restart_done = true
		GameData.restart_failed += 1
		print("RESTARTTEST FAIL: unexpected restart_phase=%d in the game scene (want 1, 3 or 4)" % phase)
		print("RESTARTTEST DONE: %d/%d passed" % [GameData.restart_passed, GameData.restart_passed + GameData.restart_failed])
		get_tree().quit()
		return
	if _restart_steps.is_empty():
		_restarttest_build_steps(phase)
		_restart_step = 0
		_restart_in_step = false
		_restart_timer = 0.0
	if _restart_step >= _restart_steps.size():
		_restart_done = true
		print("RESTARTTEST DONE: %d/%d passed" % [GameData.restart_passed, GameData.restart_passed + GameData.restart_failed])
		get_tree().quit()
		return
	var step: Dictionary = _restart_steps[_restart_step]
	if not _restart_in_step:
		(step["setup"] as Callable).call()
		_restart_in_step = true
		_restart_timer = float(step["wait"])
	_restart_timer -= delta
	if _restart_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			GameData.restart_passed += 1
		else:
			GameData.restart_failed += 1
		print("RESTARTTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_restart_step += 1
		_restart_in_step = false
		_restart_timer = 0.0


func _restarttest_build_steps(phase: int) -> void:
	if phase == 1:
		_restart_steps = [
			{"name": "SPAWN-1", "wait": 0.5, "setup": _rs_s_noop, "check": _rs_c_spawn},
			{"name": "PLAY-1", "wait": 0.8, "setup": _rs_s_play, "check": _rs_c_play},
			{"name": "LEAVE-1", "wait": 0.3, "setup": _rs_s_leave, "check": _rs_c_left},
		]
	elif phase == 3:
		_restart_steps = [
			{"name": "SPAWN-2", "wait": 0.5, "setup": _rs_s_noop, "check": _rs_c_spawn},
			{"name": "PLAY-2", "wait": 0.8, "setup": _rs_s_play, "check": _rs_c_play},
			{"name": "END-2", "wait": 0.5, "setup": _rs_s_end, "check": _rs_c_end},
			{"name": "REMATCH-2", "wait": 0.3, "setup": _rs_s_rematch, "check": _rs_c_left},
		]
	else: # phase 4 — the scene reloaded by rematch
		_restart_steps = [
			{"name": "SPAWN-3", "wait": 0.5, "setup": _rs_s_noop, "check": _rs_c_spawn},
			{"name": "PLAY-3", "wait": 0.8, "setup": _rs_s_play, "check": _rs_c_play},
		]


func _rs_s_noop() -> void:
	pass


func _rs_c_spawn() -> Array:
	var lp = _get_local_player()
	var ok: bool = lp != null and lp.alive and not match_over
	return [ok, "local player spawned+alive=%s match_over=%s (phase %d)" % [lp != null and lp.alive, match_over, GameData.restart_phase]]


func _rs_s_play() -> void:
	# Move right and fire, like a real first few seconds of play.
	_ft_press_move(Vector2(60, 0))
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _rs_c_play() -> Array:
	var lp = _get_local_player()
	_ft_release_move()
	_ft_release_aim()
	_ft_release_fire()
	if lp == null:
		return [false, "no local player to play with (phase %d)" % GameData.restart_phase]
	var ok: bool = lp._shots_fired > 0 and lp.alive
	return [ok, "shots fired=%d alive=%s (phase %d)" % [lp._shots_fired, lp.alive, GameData.restart_phase]]


func _rs_s_leave() -> void:
	# Hand back to the menu: it starts match 2 from a fresh room.
	GameData.restart_phase = 2
	_on_leave_pressed()


func _rs_c_left() -> Array:
	# The scene change happens in _on_leave_pressed / rematch; this
	# check is only reached if the change did not happen.
	return [false, "still in the game scene after leave/rematch (phase %d)" % GameData.restart_phase]


func _rs_s_end() -> void:
	_end_match("RestartTest", "second match over")


func _rs_c_end() -> Array:
	var ok: bool = match_over and end_panel.visible
	return [ok, "match_over=%s end panel visible=%s" % [match_over, end_panel.visible]]


func _rs_s_rematch() -> void:
	# Rematch reloads this scene; the reloaded scene runs phase 4.
	GameData.restart_phase = 4
	_on_rematch_pressed()


# =====================================================================
# Phase 3B PHYSICS TEST (--physics-test, GAP-73/T-01..T-75 support)
# Headless harness driving the REAL player + touch path. Each step is
# {name, wait, setup, check}; check returns [passed, detail]. Run:
#   xvfb-run -a godot --path . -- --auto-host --physics-test
#   xvfb-run -a godot --path . -- --auto-host --map=4 --physics-test
# (map ids are 0-4 in v3.7; the old ice-slide step is gone).
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
	# Phase 5: "only_map" — a step that only applies on one map.
	# (No step uses it in v3.7 — kept for future map-specific steps.)
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
		{"name": "P01-ground-accel", "wait": 2.0, "setup": _phys_s_ground_run, "check": _phys_c_ground_accel},
		{"name": "P02-air-accel", "wait": 2.0, "setup": _phys_s_air_run, "check": _phys_c_air_accel},
		{"name": "P03-analog-half", "wait": 0.8, "setup": _phys_s_analog, "check": _phys_c_analog},
		{"name": "P04a-ground-run", "wait": 0.6, "setup": _phys_s_ground_stop_run, "check": _phys_c_ground_run},
		{"name": "P04b-ground-stop", "wait": 0.5, "setup": _phys_s_ground_stop_release, "check": _phys_c_ground_stop},
		{"name": "P05a-air-run", "wait": 0.1, "setup": _phys_s_air_slide, "check": _phys_c_air_run},
		{"name": "P05b-air-slide", "wait": 0.9, "setup": _phys_s_air_slide_release, "check": _phys_c_air_slide},
		{"name": "P06-terminal-velocity", "wait": 2.0, "setup": _phys_s_fall, "check": _phys_c_terminal},
		{"name": "P07a-jump-hold-apex", "wait": 0.7, "setup": _phys_s_jump_hold, "check": _phys_c_jump_hold},
		{"name": "P07b-jump-tap-apex", "wait": 0.7, "setup": _phys_s_jump_tap, "check": _phys_c_jump_tap},
		{"name": "P08-fuel-regen-delay", "wait": 0.3, "setup": _phys_s_fuel_drain, "check": _phys_c_fuel_delay},
		{"name": "P08b-fuel-regen-after", "wait": 1.2, "setup": _phys_s_noop, "check": _phys_c_fuel_after},
		{"name": "P09a-aim-hold-setup", "wait": 0.5, "setup": _phys_s_aim_hold, "check": _phys_c_aim_hold_setup},
		{"name": "P09b-aim-hold", "wait": 0.4, "setup": _phys_s_noop, "check": _phys_c_aim_hold},
		{"name": "P10-aim-deadzone", "wait": 0.3, "setup": _phys_s_aim_deadzone, "check": _phys_c_aim_deadzone},
		{"name": "P11-shotgun-table", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_shotgun_table},
		{"name": "P12-damage-calc", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_damage_calc},
		{"name": "P13-explosion-falloff", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_explosion_falloff},
		{"name": "P14-respawn-validation", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_respawn_valid},
		{"name": "P15-grenade-bounce", "wait": 1.8, "setup": _phys_s_grenade, "check": _phys_c_grenade},
		{"name": "P16-velocity-inheritance", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_inheritance},
		{"name": "P17-recoil-accum", "wait": 0.1, "setup": _phys_s_recoil_fire, "check": _phys_c_recoil},
		{"name": "P17b-recoil-decay", "wait": 2.0, "setup": _phys_s_noop, "check": _phys_c_recoil_decay},
		{"name": "P18a-ice-run", "wait": 0.5, "setup": _phys_s_ice, "check": _phys_c_ice},
		{"name": "P19-camera", "wait": 0.9 if map_id == GameData.SKYFALL_MAP_ID else 0.4, "setup": _phys_s_camera, "check": _phys_c_camera}, # v3.11 QA-131: Skyfall's 0.4 s window is load-marginal — _cam_look builds at 240 px/s toward a target set by sprint velocity, and under xvfb load physics dilates so the player is still ramping at 0.4 s (look-ahead read 24-32, want >40; isolated runs read 50). 0.9 s gives the same check room to build; the player is still mid-run on the L7 perch staircase at 0.9 s (gate at x1742 is ~740 px away), so nothing else changes. Flat maps keep 0.4 s.
		{"name": "P20-pool-budget", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_pool},
		{"name": "P21-version-handshake", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_version},
		{"name": "P22-barrel", "wait": 0.1, "setup": _phys_s_barrel, "check": _phys_c_barrel},
		{"name": "P23-bounce-pad", "wait": 1.5, "setup": _phys_s_pad, "check": _phys_c_pad}, # QA-071b: was 0.12 — under xvfb load ~1 physics frame elapses in 0.2 s wall, so the launch may not have fired yet; 1.5 s gives it frames on any load, and the check accepts a fast rise OR having risen
		{"name": "P24-stuck-recovery", "wait": 0.1, "setup": _phys_s_stuck, "check": _phys_c_stuck},
		{"name": "P24b-wedge-recovery", "wait": 3.5, "setup": _phys_s_wedge, "check": _phys_c_wedge},
		{"name": "P25a-jetpack-cap", "wait": 1.0, "setup": _phys_s_jetpack_cap, "check": _phys_c_jetpack_cap},
		{"name": "P25b-jetpack-release", "wait": 0.5, "setup": _phys_s_jetpack_release, "check": _phys_c_jetpack_release},
	]


func _phys_s_noop() -> void:
	pass


func _phys_c_pickups_start() -> Array:
	# Skyfall starts with 3 weapon pickups AND 3 power-ups (QA-132:
	# one low, one mid, one high — was 1 random power-up).
	# Every other map starts with exactly 3 weapons.
	if map_id == GameData.SKYFALL_MAP_ID:
		var w := 0
		var p := 0
		for child in pickups_node.get_children():
			if int(child.get("kind")) >= 7:
				p += 1
			else:
				w += 1
		return [w == 3 and p == 3, "pickups at match start: %d weapons + %d power-ups (want 3 + 3)" % [w, p]]
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
	_phys_data["t0_phys"] = float(_phys_data.get("phys_clock", 0.0))
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
	# QA-099 (v3.7): drop from a column with a long clear fall (see
	# _phys_clear_fall_x) — the old fixed (2100, 700) lands the
	# player against Volcanic's solid crate at (2140, 770) on the
	# platform below, so the player pinned after ~5 px and never
	# reached 300 px/s in the air. Air accel itself is unchanged.
	_phys_teleport(Vector2(_phys_clear_fall_x(), 200))
	_phys_data["t0"] = Time.get_ticks_msec() / 1000.0
	_phys_data["t0_phys"] = float(_phys_data.get("phys_clock", 0.0))
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
	_phys_teleport(Vector2(300, 1318))
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
	# with no input. QA-099 (v3.7): drop from a column with a long
	# clear fall (see _phys_clear_fall_x) — the old fixed x=1000
	# drops the player onto Pirate Island's y600 platform at ~0.76 s,
	# so ground friction had already killed vel.x by the 1.0 s check.
	var _slide_x := _phys_clear_fall_x()
	_phys_teleport(Vector2(_slide_x, 200))
	_jt_release_move()
	var lp = _phys_lp()
	lp.velocity = Vector2(350, 0)
	_phys_data["slide_x0"] = _slide_x


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
	# QA-095 (v3.7): the old ice map's x=400 branch is gone
	# with that map — every kept map has a clear fall at x=1000.
	# v3.11: Skyfall is the exception — at x=1000 the first
	# platform below y=300 is (700,690), only ~340 px of fall,
	# so the true landing speed (~976) sits just above the 950
	# floor and the per-render-frame max_vy sample reads 863-933
	# under xvfb load (two 32/34 runs, P19 passed on re-run);
	# x=1800 is worse, it lands on the summit gate box (top
	# y=484, ~130 px fall, reads 513-583). Scan for the longest
	# clear drop from y=300 instead (platforms + solid decor +
	# gate box); the other five maps keep x=1000.
	var fall_x := 1000.0
	if map_id == 5:
		fall_x = _phys_longest_drop_x(300.0)
	_phys_teleport(Vector2(fall_x, 300))
	_phys_data["max_vy"] = 0.0
	_phys_data["track_max_vy"] = true


# Longest clear vertical drop from from_y on the current map:
# for each candidate column, the first solid top below from_y
# (platform rects + solid decor + the Skyfall summit gate box).
# Falls back to x=1000 if nothing is found.
func _phys_longest_drop_x(from_y: float) -> float:
	var solids: Array = []
	for p in (MAPS[map_id]["platforms"] as Array):
		solids.append(p as Rect2)
	solids.append_array(_ct_solid_rects(MAPS[map_id]))
	if map_id == 5:
		solids.append(Rect2(1742, 484, 116, 378)) # summit gate box (see _build_skyfall_gate)
	var best_x := 1000.0
	var best_drop := -1.0
	var x := 60.0
	while x <= map_size.x - 60.0:
		var land_y := map_size.y
		for r in solids:
			var rr: Rect2 = r
			if rr.end.x < x - 30.0 or rr.position.x > x + 30.0:
				continue
			if rr.position.y <= from_y:
				continue
			if rr.position.y < land_y:
				land_y = rr.position.y
		var drop := land_y - from_y
		if drop > best_drop:
			best_drop = drop
			best_x = x
		x += 40.0
	return best_x


func _phys_c_terminal() -> Array:
	_phys_data["track_max_vy"] = false
	var m: float = float(_phys_data.get("max_vy", 0.0))
	var ok: bool = m >= 950.0 and m <= 1050.0
	return [ok, "max fall vel.y=%.0f (want 950-1050, cap 1000)" % m]


# QA-099 (v3.7): the fixed x=800 jump/jetpack column sits under a
# y1180/y1280 platform on Ironfall, Jungle and Volcanic (only 124 px
# of sky) — the jump bonked at ~65 px instead of ~155 and the jetpack
# never reached its cap there, on three different maps with the same
# numbers. The old "x=800 has >=294 px of sky on all five maps"
# comment was wrong: it only counted the y1110 row and missed the
# lower y1180/y1280 row. Scan every column and return the one with
# the most open sky above the floor; a column blocked at floor level
# by solid decor is skipped. The best column wins even if no column
# reaches clear_px (Volcanic's best is 294 px — still enough for the
# cap, which needs ~40 px of free rise at full thrust).
func _phys_clear_sky_x(clear_px: float) -> float:
	var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	var solids: Array = _ct_solid_rects(MAPS[map_id])
	var best_x := 800.0
	var best_clear := -1.0
	var x := 100.0
	while x <= map_size.x - 100.0:
		var lowest_bottom := 0.0
		for p in (MAPS[map_id]["platforms"] as Array):
			var r: Rect2 = p
			if r.end.x < x - 20.0 or r.position.x > x + 20.0:
				continue
			if r.position.y >= floor_top:
				continue
			lowest_bottom = maxf(lowest_bottom, r.end.y)
		var clear := floor_top - lowest_bottom
		var blocked := false
		for sr in solids:
			var srr: Rect2 = sr
			if srr.end.x < x - 45.0 or srr.position.x > x + 45.0:
				continue
			if srr.position.y < floor_top and srr.end.y > floor_top - 60.0:
				blocked = true
				break
		if not blocked and clear > best_clear:
			best_clear = clear
			best_x = x
		x += 50.0
	return best_x


# QA-099 (v3.7): a column with a long clear fall from y=200 — no
# platform top in the 200..950 band anywhere on the player's drift
# path (x-20 .. x+230, ~204 px at 350 px/s with drag 1.2), so the
# player stays airborne for the whole 1.0 s step (a 750 px fall takes
# ~1.03 s). The old fixed (1000, 200) drops the player onto Pirate
# Island's y600 platform at ~0.76 s (P05b landed early, vel.x killed
# by ground friction) and the old fixed (2100, 700) air-run drop
# lands the player against Volcanic's solid crate at (2140, 770)
# after ~5 px (P02 never reached 300 px/s). Physics untouched.
func _phys_clear_fall_x() -> float:
	var plats: Array = MAPS[map_id]["platforms"]
	var x := 200.0
	while x <= map_size.x - 300.0:
		var ok := true
		for i in range(1, plats.size()):
			var r: Rect2 = plats[i]
			if r.end.x < x - 20.0 or r.position.x > x + 230.0:
				continue
			if r.position.y >= 200.0 and r.position.y <= 950.0:
				ok = false
				break
		if ok:
			return x
		x += 50.0
	return 1000.0


# Phase 5 — physics harness helper: the ground (lowest platform top)
# at map x, so jump/grenade/respawn setups land on a floor on every
# map instead of a map-0-tuned coordinate.
func _phys_ground_at(x: float) -> Vector2:
	var best_top := -1.0
	for p in (MAPS[map_id]["platforms"] as Array):
		var r: Rect2 = p
		if r.position.x <= x and x <= r.end.x and r.position.y > best_top:
			best_top = r.position.y
	if best_top < 0.0:
		best_top = float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	return Vector2(x, best_top - 34.0) # QA-071b: 3 px clear of the floor (capsule half-height 31)


func _phys_s_jump_hold() -> void:
	# QA-099 (v3.7): stand on the ground at the clearest-sky column
	# (see _phys_clear_sky_x) — the old x=800 sits under a y1180
	# platform on Ironfall/Jungle and a y1280 platform on Volcanic,
	# so the jump bonked at ~65 px instead of ~155. (The even older
	# x=2100 spot sat exactly on a bounce pad at 0.7 * W and x=300 has a
	# platform at y=1180 directly overhead — same bonk.) Physics
	# untouched.
	# fuel=0: holding stick-up must NOT jetpack, or the "hold" apex
	# measures jump+jetpack (~300 px) instead of the jump (~155 px).
	# The 999 s regen delay stops air regen re-enabling the jetpack
	# mid-rise (which also used to clamp the jump via the rise cap).
	var gp := _phys_ground_at(_phys_clear_sky_x(200.0))
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
	_phys_lp().fuel = PhysicsConfig.FUEL_MAX
	_phys_lp()._fuel_delay_timer = 0.0
	var apex := float(_phys_data.get("jump_y0", 1326.0)) - float(_phys_data.get("min_y", 1326.0))
	_phys_data["hold_apex"] = apex
	return [apex > 130.0 and apex < 185.0, "hold jump apex: %d px (want ~155)" % round(apex)]


# QA-099 (v3.7): fire-and-forget release after N physics frames
# (see _phys_s_jump_tap) — calling a coroutine without awaiting it
# runs it until the first await, then resumes it on later frames.
func _phys_release_move_after_frames(n: int) -> void:
	for i in n:
		await get_tree().physics_frame
	_jt_release_move()


func _phys_s_jump_tap() -> void:
	# QA-099 (v3.7): same clear-sky column as _phys_s_jump_hold, so
	# the tap apex is measured against the same sky as the hold apex.
	var gp := _phys_ground_at(_phys_clear_sky_x(200.0))
	_phys_teleport(gp)
	var lp = _phys_lp()
	lp.fuel = 0.0
	lp._fuel_delay_timer = 999.0
	_phys_data["track_min_y"] = true
	_phys_data["min_y"] = gp.y + 6.0
	_phys_data["jump_y0"] = gp.y + 6.0
	_jt_press_move(Vector2(0, -60))
	# Tap: release after a short hold counted in physics frames.
	# QA-099 (v3.7): the old 0.12 s wall-clock timer was load-flaky
	# both ways — QA-047 fixed its late firing (apex crept to
	# 124 px, cap 120), but under a loaded machine it can also fire
	# after fewer physics frames and the tap apex fell to 32 px
	# (want 50-120). 7 physics frames is the same ~0.12 s in
	# physics time, whatever the wall clock does (same lesson as
	# the pad fix: awaiting the physics frame is exact).
	_phys_release_move_after_frames(7)


func _phys_c_jump_tap() -> Array:
	_phys_data["track_min_y"] = false
	_phys_lp().fuel = PhysicsConfig.FUEL_MAX
	_phys_lp()._fuel_delay_timer = 0.0
	var apex := float(_phys_data.get("jump_y0", 1326.0)) - float(_phys_data.get("min_y", 1326.0))
	var hold_apex: float = float(_phys_data.get("hold_apex", 155.0))
	return [apex > 50.0 and apex < 120.0 and apex < hold_apex - 40.0,
		"tap jump apex: %d px vs hold %d px (want tap 50-120, clearly lower)" % [round(apex), round(hold_apex)]]


func _phys_s_fuel_drain() -> void:
	var lp = _phys_lp()
	_phys_teleport(Vector2(300, 1318))
	lp.fuel = 0.0
	lp._fuel_delay_timer = 0.6


func _phys_c_fuel_delay() -> Array:
	var lp = _phys_lp()
	return [lp.fuel < 2.0, "fuel 0.3 s after empty: %.1f (want <2, regen delay 0.6 s)" % lp.fuel]


func _phys_c_fuel_after() -> Array:
	var lp = _phys_lp()
	return [lp.fuel > 20.0, "fuel 1.5 s after empty: %.1f (want >20, regen 50/s on ground, QA-074 was 70/s)" % lp.fuel]


func _phys_s_aim_hold() -> void:
	_phys_teleport(Vector2(1600, 1318))
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
	var ok: bool = int(w["pellets"]) == 7 and absf(float(WeaponData.TABLE[0]["rate"]) - 0.125) < 0.001 and absf(float(WeaponData.TABLE[4]["speed"]) - 450.0) < 0.01 and absf(float(WeaponData.TABLE[4]["gravity"]) - 0.0) < 0.01
	return [ok, "shotgun pellets=%d rifle rate=%.3f rocket speed=%d gravity=%d (want 7 / 0.125 / 450 / 0 — QA-106: rocket flies straight)" % [int(w["pellets"]), float(WeaponData.TABLE[0]["rate"]), int(WeaponData.TABLE[4]["speed"]), int(WeaponData.TABLE[4]["gravity"])]]


func _phys_c_damage_calc() -> Array:
	var lp = _phys_lp()
	var head: int = lp.calculate_damage(12, "head", 100.0, 0)
	var torso: int = lp.calculate_damage(12, "torso", 100.0, 0)
	var legs: int = lp.calculate_damage(12, "legs", 100.0, 0)
	# QA-075: long-range damage is per-weapon now (was a flat 0.7x
	# floor for every gun). Sniper 60 at 1500 px: max range
	# 1600*1.6=2560, f=(1500-400)/2160=0.509, floor 0.9 -> 57
	# (was 51). Shotgun 9 at 450 px: max range 900*0.55=495,
	# f=50/95=0.526, floor 0.5 -> 7 (was 8). Close-range numbers
	# above are unchanged (falloff only starts past 400 px).
	var sniper_far: int = lp.calculate_damage(60, "torso", 1500.0, 3)
	var shotgun_far: int = lp.calculate_damage(9, "torso", 450.0, 2)
	var ok: bool = head == 18 and torso == 12 and legs == 9 and sniper_far == 57 and shotgun_far == 7
	return [ok, "rifle 12 dmg: head=%d torso=%d legs=%d (want 18/12/9); sniper 60 @1500px=%d (want 57, floor 0.9); shotgun 9 @450px=%d (want 7, floor 0.5)" % [head, torso, legs, sniper_far, shotgun_far]]


func _phys_c_explosion_falloff() -> Array:
	# Smooth curve D = Dmax*(1-u^2)^2: centre 55, mid (u=0.5) ~31, edge ~0.
	var c := int(round(55.0 * pow(1.0 - 0.0, 2.0)))
	var m := int(round(55.0 * pow(1.0 - 0.25, 2.0)))
	var e := int(round(55.0 * pow(1.0 - pow(115.0 / 120.0, 2.0), 2.0)))
	var ok: bool = c == 55 and m == 31 and e <= 5
	return [ok, "grenade 55 dmg radius 120: centre=%d mid=%d edge=%d (want 55/31/0-5)" % [c, m, e]]


func _phys_c_respawn_valid() -> Array:
	# Phase 5: the "inside the floor" point is map-relative (the old
	# fixed (1600, 1370) is open air above the skybridge on Neon
	# City). plats[0] is the lowest floor/deck on every map.
	var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	var bad := is_spawn_valid(Vector2(map_size.x * 0.5, floor_top + 18.0), 1) # inside the floor slab
	var good := get_valid_spawn_point(1, 1) != Vector2.INF
	return [not bad and good, "spawn inside floor valid=%s, valid spawn found=%s (want false/true)" % [str(bad), str(good)]]


func _phys_s_grenade() -> void:
	_phys_teleport(Vector2(300, 1318))
	var g = load("res://grenade.tscn").instantiate()
	g.name = "phys_grenade"
	# Open sky: the old (1600,1000) spot is INSIDE the solid crate
	# at (1600,1010) — the grenade wedged there and never fell.
	# Phase 5: throw from 250 px above the map's floor, so the fall
	# distance (and the 1.8 s settle window) is the same on every map.
	var floor_top := float((MAPS[map_id]["platforms"] as Array)[0].position.y)
	g.position = Vector2(2100, floor_top - 250.0)
	# Phase 5: straight down — the old (0.2, 0.3) drift rolled the
	# grenade off a segmented deck
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
	# QA-095 (v3.7): the old ice map is deleted, so there is no
	# live ice slide any more — the step records that and the
	# check below passes on the constants only.
	_phys_data["ice_map"] = false


func _phys_c_ice() -> Array:
	_jt_release_move()
	# QA-095 (v3.7): no map has ice now — the check proves the
	# query is off everywhere and the constants are intact.
	var ok: bool = not is_on_ice(Vector2(1400, 1420)) and absf(PhysicsConfig.ICE_FRICTION - 100.0) < 0.01 and absf(PhysicsConfig.ICE_ACCEL - 500.0) < 0.01
	return [ok, "no ice map in v3.7 (map %d): is_on_ice=false, ice friction=100 accel=500" % map_id]


func _phys_s_camera() -> void:
	var lp = _phys_lp()
	_phys_data["cam_anchor0"] = lp._cam_anchor
	# Phase 5: stand on the highest platform at x=1600 — the fixed
	# (1600, 1320) is INSIDE a platform on some maps
	# ((1450,1280,300,48)), so the player wedged and look-ahead read 0.
	# QA-112 (v3.9): on Skyfall x=1600 is the summit, and the summit
	# gate (x 1742-1858) blocks the rightward run after ~120 px, so
	# the player stops and look-ahead never builds. Use x=1000 there
	# (the L7 left perch, a clear run right).
	var cx := 1000.0 if map_id == GameData.SKYFALL_MAP_ID else 1600.0
	_phys_teleport(_phys_top_at(cx))
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
	return Vector2(x, best_top - 34.0) # QA-071b: 3 px clear of the floor (capsule half-height 31)


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
	_phys_teleport(Vector2(300, 1318))
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
	var pad_x := map_size.x * 0.3
	# QA-071b: the player can arrive here already overlapping a pad
	# (the P18b ice slide ends over the 0.3 pad) or inside its 0.3 s
	# cooldown, so a plain teleport onto the pad fires no fresh
	# body_entered and the launch never happens (map 4: vel.y=47,
	# map 10: vel.y=0/93/117). Two-phase: phase 1 moves the player
	# clear of the pads and clears the cooldowns; after one physics
	# frame (await physics_frame) phase 2 puts the player on the pad,
	# so the area sees a FRESH entry and fires body_entered. A wall
	# timer was tried first and proved racy (it fired up to 1.45 s
	# late under xvfb load); awaiting the physics frame is exact.
	for entry in _bounce_pads:
		(entry["cooldowns"] as Dictionary).clear()
	# QA-099 (v3.7): track the launch itself — the pad sets vel.y
	# -750 on entry, so the fastest upward velocity proves the pad
	# fired even when a platform overhead caps the rise (Volcanic's
	# 0.3 pad sits under its y1280 platform: the launch bonks after
	# ~53 px and the old endpoint check read a falling player).
	_phys_data["pad_min_vy"] = 0.0
	_phys_data["track_min_vy_pad"] = true
	_phys_teleport(Vector2(map_size.x * 0.1, floor_top - 40.0))
	await get_tree().physics_frame
	_phys_teleport(Vector2(pad_x, floor_top - 40.0))


func _phys_c_pad() -> Array:
	_phys_data["track_min_vy_pad"] = false
	var lp = _phys_lp()
	var floor_top := 1352.0
	var plats: Array = MAPS[map_id]["platforms"]
	if not plats.is_empty():
		floor_top = float((plats[0] as Rect2).position.y)
	# QA-071b: a launched player is either still rising fast (vel.y < -400)
	# or has risen and is falling back from a bounce (the pad relaunches on
	# every landing, so a launched player is never standing still on the pad).
	# A player who never launched stands at floor_top - 34 with vel.y = 0,
	# so neither condition can pass by accident — the only upward force here
	# is the pad (no jump input in this step).
	# QA-099 (v3.7): or the launch was tracked at physics rate
	# (pad_min_vy < -600) — on Volcanic the pad sits under the y1280
	# platform, so the launch bonks after ~53 px and the endpoint
	# state alone reads as "never launched".
	var pad_min_vy: float = float(_phys_data.get("pad_min_vy", 0.0))
	var ok: bool = lp.velocity.y < -400.0 or lp.position.y < floor_top - 60.0 or pad_min_vy < -600.0
	return [ok, "bounce pad launch vel.y=%d pos.y=%.0f pad_min_vy=%d (want vel.y < -400 or risen above %.0f or pad_min_vy < -600, pad sets -750)" % [round(lp.velocity.y), lp.position.y, round(pad_min_vy), floor_top - 60.0]]


func _phys_s_stuck() -> void:
	var lp = _phys_lp()
	lp.position = Vector2(1600, 1380) # inside the floor slab (QA-071b: was 1370 — with the 62-tall capsule that is only 1 px into Neon's 1400 platform, so the smaller query capsule missed it and no recovery fired; 1380 embeds 11 px on every physics map)
	lp._stuck_check_timer = 1.0
	lp._check_stuck(0.016)


func _phys_c_stuck() -> Array:
	var lp = _phys_lp()
	var ok: bool = is_spawn_valid(lp.position, 1)
	return [ok, "stuck player moved to %s (want a valid spawn)" % str(lp.position)]


func _phys_s_wedge() -> void:
	# QA-063 wedge recovery: pin the local player between two
	# temporary solid walls (a synthetic slot, like the old Jungle
	# jcrate trap) and hold move-right. The detector must teleport
	# the player to a DIFFERENT valid spawn within the step's wait.
	var lp = _phys_lp()
	_phys_teleport((MAPS[map_id]["spawns"] as Array)[0])
	_phys_data["wedge_spot"] = lp.position
	var walls: Array = []
	for dir in [-1.0, 1.0]:
		var wall := StaticBody2D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(20, 200)
		shape.shape = rect
		wall.add_child(shape)
		wall.position = lp.position + Vector2(37.0 * dir, 0.0)
		add_child(wall)
		walls.append(wall)
	_phys_data["wedge_walls"] = walls
	_jt_press_move(Vector2(60, 0))


func _phys_c_wedge() -> Array:
	var lp = _phys_lp()
	_jt_release_move()
	for wall in (_phys_data.get("wedge_walls", []) as Array):
		if is_instance_valid(wall):
			wall.queue_free()
	_phys_data.erase("wedge_walls")
	var spot: Vector2 = _phys_data.get("wedge_spot", Vector2.INF)
	var moved: bool = lp.position.distance_to(spot) > 100.0
	# The recovery only teleports to a spawn point, so the player
	# must be near one. is_spawn_valid is NOT used here: after the
	# teleport the test joystick is still held, so the player keeps
	# walking and can be mid-push against a crate (the solver leaves
	# the capsule transiently penetrating the floor), which fails
	# the strict full-capsule shape query even though the recovery
	# destination was valid.
	var nearest := 1e9
	for s in (MAPS[map_id]["spawns"] as Array):
		nearest = minf(nearest, lp.position.distance_to(s))
	var near_spawn: bool = nearest < 300.0
	var free: bool = not lp._both_sides_blocked()
	return [moved and near_spawn and free, "wedge player at %s (spot was %s, moved=%s, nearest spawn %.0f px, wedged=%s)" % [str(lp.position), str(spot), str(moved), nearest, str(not free)]]


# QA-074: jetpack balance. P25a measures the climb itself (fastest
# vy while thrusting must be the new 320 cap, not the old 450, and
# the fuel must actually drain); P25b measures the release (half a
# second after letting go the player must be falling again, not
# hanging). Setup is the open sky P07 uses (x=800, >=294 px on the
# four non-ice physics-test maps); map 4 uses x=2100 instead — see
# _phys_s_jetpack_cap, the 1180 level leaves only 59 px of sky at
# x=800 there. P25b's setup runs right after P25a's check, while
# the stick is still held up — it only releases it.
func _phys_s_jetpack_cap() -> void:
	# QA-099 (v3.7): the clearest-sky column (see
	# _phys_clear_sky_x) — the old x=800 sits under a y1180/y1280
	# platform on Ironfall/Jungle/Volcanic, so the climb bonked
	# after ~53 px and never reached the 320 cap (fastest vy -23).
	var x := _phys_clear_sky_x(300.0)
	var gp := _phys_ground_at(x)
	_phys_teleport(gp)
	var lp = _phys_lp()
	lp.fuel = PhysicsConfig.FUEL_MAX
	lp._fuel_delay_timer = 0.0
	_phys_data["min_vy_jet"] = 0.0
	_phys_data["track_min_vy_jet"] = true
	_jt_press_move(Vector2(0, -60))


func _phys_c_jetpack_cap() -> Array:
	_phys_data["track_min_vy_jet"] = false
	var lp = _phys_lp()
	var min_vy: float = float(_phys_data.get("min_vy_jet", 0.0))
	# The jump's own -660 is gated out of the tracker (it only
	# samples while _jetpacking), so this is the thrust climb: it
	# must reach a real climb (faster than -200) but never the old
	# 450 cap (allow 25 px/s of physics slack over the 320 cap).
	# QA-132: fuel drains 45/s from ~0.24 s in, so after a 1.0 s
	# hold it sits near 371 (405 tank) — the 330..400 band only
	# fails if thrust never started (fuel ~405) or ran dry (~0).
	var ok: bool = min_vy < -200.0 and min_vy >= -345.0 and lp.fuel < 400.0 and lp.fuel > 330.0
	return [ok, "jetpack climb: fastest thrust vy=%d px/s (want -345..-200, cap 320), fuel=%d (want 330-400, draining from 405)" % [round(min_vy), round(lp.fuel)]]


func _phys_s_jetpack_release() -> void:
	_jt_release_move()


func _phys_c_jetpack_release() -> Array:
	var lp = _phys_lp()
	lp.fuel = PhysicsConfig.FUEL_MAX
	lp._fuel_delay_timer = 0.0
	# 0.5 s after release, gravity (1400 px/s^2) has taken vy from
	# the -320 cap to about +380 (falling). The bar is -100, so the
	# check passes even if physics ran at half rate in the window
	# (vy ~+30 then) — it only fails if the player is still rising
	# at speed, i.e. hanging on thrust after release.
	var ok: bool = not lp._jetpacking and lp.velocity.y > -100.0
	return [ok, "0.5 s after release: jetpacking=%s vel.y=%d (want false, >-100 — falling again, not hanging)" % [lp._jetpacking, round(lp.velocity.y)]]


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
		{"name": "HUD-READOUTS", "wait": 0.3, "setup": _ft_s_noop, "check": _ft_c_hud},
	]
	# QA-112/114/115 (v3.9): Skyfall steps — only on map 5. The
	# base steps above run first (countdown done, match running).
	# Order matters: grab -> capture -> relay -> checkpoints ->
	# death/respawn -> power-ups -> comeback -> events -> storm ->
	# combos -> HUD -> routes -> scenery -> rarity -> 5v5 (last:
	# it spawns 9 fake players, test-only, never in the real game).
	if map_id == GameData.SKYFALL_MAP_ID:
		_feat_steps += [
			{"name": "FT-SF-MODE", "wait": 0.3, "setup": _ft_sf_s_mode, "check": _ft_sf_c_mode},
			{"name": "FT-SF-MAP", "wait": 0.2, "setup": _ft_s_noop, "check": _ft_sf_c_map},
			{"name": "FT-SF-GRAB", "wait": 2.0, "setup": _ft_sf_s_grab, "check": _ft_sf_c_grab},
			{"name": "FT-SF-CAPTURE", "wait": 0.5, "setup": _ft_sf_s_capture, "check": _ft_sf_c_capture},
			{"name": "FT-SF-RELAY-GRAB", "wait": 0.3, "setup": _ft_sf_s_relay_grab, "check": _ft_sf_c_relay_grab},
			{"name": "FT-SF-RELAY-BANK", "wait": 0.5, "setup": _ft_sf_s_relay_bank, "check": _ft_sf_c_relay_bank},
			{"name": "FT-SF-CHECKPOINT-UP", "wait": 0.5, "setup": _ft_sf_s_cp_up, "check": _ft_sf_c_cp_up},
			{"name": "FT-SF-CHECKPOINT-DOWN", "wait": 0.5, "setup": _ft_sf_s_cp_down, "check": _ft_sf_c_cp_down},
			{"name": "FT-SF-DIE-L6-SETUP", "wait": 0.5, "setup": _ft_sf_s_die_l6_setup, "check": _ft_sf_c_die_l6_setup},
			{"name": "FT-SF-DIE-L6", "wait": 4.5, "setup": _ft_sf_s_die_l6, "check": _ft_sf_c_die_l6},
			{"name": "FT-SF-POWERUP-SLOTS", "wait": 0.3, "setup": _ft_sf_s_slots, "check": _ft_sf_c_slots},
			{"name": "FT-SF-POWERUP-ACTIVE", "wait": 0.3, "setup": _ft_sf_s_active, "check": _ft_sf_c_active},
			{"name": "FT-SF-SLOT-BTNS", "wait": 0.3, "setup": _ft_sf_s_slot_btns, "check": _ft_sf_c_slot_btns},
			{"name": "FT-SF-SLOT-GREY-ACTIVE", "wait": 0.3, "setup": _ft_sf_s_slot_grey_active, "check": _ft_sf_c_slot_grey_active},
			{"name": "FT-SF-SLOT-GREY-CARRIER", "wait": 0.3, "setup": _ft_sf_s_slot_grey_carrier, "check": _ft_sf_c_slot_grey_carrier},
			{"name": "FT-SF-OPP-CARRIER-CTRL", "wait": 0.3, "setup": _ft_sf_s_carrier_ctrl, "check": _ft_sf_c_carrier_ctrl},
			{"name": "FT-SF-OPP-CARRIER", "wait": 0.3, "setup": _ft_sf_s_carrier, "check": _ft_sf_c_carrier},
			{"name": "FT-SF-SLOT-TAP", "wait": 0.3, "setup": _ft_sf_s_slot_tap, "check": _ft_sf_c_slot_tap},
			{"name": "FT-SF-PATH-7", "wait": 1.0, "setup": _ft_sf_s_path7, "check": _ft_sf_c_path},
			{"name": "FT-SF-PATH-8", "wait": 1.0, "setup": _ft_sf_s_path8, "check": _ft_sf_c_path},
			{"name": "FT-SF-PATH-9", "wait": 1.0, "setup": _ft_sf_s_path9, "check": _ft_sf_c_path},
			{"name": "FT-SF-PATH-10", "wait": 1.0, "setup": _ft_sf_s_path10, "check": _ft_sf_c_path},
			{"name": "FT-SF-PATH-11", "wait": 1.0, "setup": _ft_sf_s_path11, "check": _ft_sf_c_path},
			{"name": "FT-SF-PATH-12", "wait": 1.0, "setup": _ft_sf_s_path12, "check": _ft_sf_c_path},
			{"name": "FT-SF-PATH-13", "wait": 1.0, "setup": _ft_sf_s_path13, "check": _ft_sf_c_path},
			{"name": "FT-SF-OPP-SHIELD-STORM", "wait": 1.0, "setup": _ft_sf_s_shield_storm, "check": _ft_sf_c_shield_storm},
			{"name": "FT-SF-COMEBACK", "wait": 6.0, "setup": _ft_sf_s_comeback, "check": _ft_sf_c_comeback},
			{"name": "FT-SF-EVENT", "wait": 1.0, "setup": _ft_sf_s_event, "check": _ft_sf_c_event},
			{"name": "FT-SF-STORM", "wait": 1.0, "setup": _ft_sf_s_storm, "check": _ft_sf_c_storm},
			{"name": "FT-SF-COMBO-EVENT-STORM", "wait": 1.0, "setup": _ft_sf_s_combo_event_storm, "check": _ft_sf_c_combo_event_storm},
			{"name": "FT-SF-COMBO-TRAP", "wait": 2.0, "setup": _ft_sf_s_combo_trap, "check": _ft_sf_c_combo_trap},
			{"name": "FT-SF-LEVELS", "wait": 0.2, "setup": _ft_s_noop, "check": _ft_sf_c_levels},
			{"name": "FT-SF-HAZARD-LAVA", "wait": 2.0, "setup": _ft_sf_s_hazard_lava, "check": _ft_sf_c_hazard_lava},
			{"name": "FT-SF-LIGHTNING", "wait": 2.0, "setup": _ft_sf_s_lightning, "check": _ft_sf_c_lightning},
			{"name": "FT-SF-HEIGHTBAR", "wait": 0.3, "setup": _ft_sf_s_heightbar, "check": _ft_sf_c_heightbar},
			{"name": "FT-SF-INVIS-WARN", "wait": 0.3, "setup": _ft_sf_s_invis_warn, "check": _ft_sf_c_invis_warn},
			{"name": "FT-SF-INVIS-CLEAR", "wait": 0.3, "setup": _ft_sf_s_invis_clear, "check": _ft_sf_c_invis_clear},
			{"name": "FT-SF-PING", "wait": 0.3, "setup": _ft_sf_s_ping, "check": _ft_sf_c_ping},
			{"name": "FT-SF-ROUTES", "wait": 0.2, "setup": _ft_s_noop, "check": _ft_sf_c_routes},
			{"name": "FT-SF-SCENERY", "wait": 1.0, "setup": _ft_sf_s_scenery, "check": _ft_sf_c_scenery},
			{"name": "FT-SF-RARITY", "wait": 0.2, "setup": _ft_sf_s_rarity, "check": _ft_sf_c_rarity},
			{"name": "FT-SF-5V5", "wait": 0.5, "setup": _ft_sf_s_5v5, "check": _ft_sf_c_5v5},
			{"name": "FT-SF-MOVER-CLEAR", "wait": 0.5, "setup": _ft_sf_s_noop, "check": _ft_sf_c_mover_clear},
			{"name": "FT-SF-WIND-NO-TARGET", "wait": 1.0, "setup": _ft_sf_s_wind_no_target, "check": _ft_sf_c_wind_no_target},
			{"name": "FT-SF-WIND-THROW", "wait": 1.5, "setup": _ft_sf_s_wind_throw, "check": _ft_sf_c_wind_throw},
			{"name": "FT-SF-THUNDER-NO-TARGET", "wait": 1.0, "setup": _ft_sf_s_thunder_no_target, "check": _ft_sf_c_thunder_no_target},
			{"name": "FT-SF-THUNDER-SHIELD", "wait": 1.0, "setup": _ft_sf_s_thunder_shield, "check": _ft_sf_c_thunder_shield},
			{"name": "FT-SF-WIND-HEIGHT", "wait": 1.0, "setup": _ft_sf_s_wind_height, "check": _ft_sf_c_wind_height},
			{"name": "FT-SF-THUNDER-HEIGHT", "wait": 1.0, "setup": _ft_sf_s_thunder_height, "check": _ft_sf_c_thunder_height},
			{"name": "FT-SF-TRAP-ROCKS", "wait": 1.0, "setup": _ft_sf_s_trap_rocks, "check": _ft_sf_c_trap_rocks},
			{"name": "FT-SF-TRAP-TRAPDOOR-L2", "wait": 1.5, "setup": _ft_sf_s_trap_trapdoor_l2, "check": _ft_sf_c_trap_trapdoor_l2},
			{"name": "FT-SF-TRAP-LAVA2", "wait": 1.0, "setup": _ft_sf_s_trap_lava2, "check": _ft_sf_c_trap_lava2},
			{"name": "FT-SF-TRAP-LIGHTNING-L4", "wait": 1.5, "setup": _ft_sf_s_trap_lightning_l4, "check": _ft_sf_c_trap_lightning_l4},
			{"name": "FT-SF-TRAP-COLLAPSE-L6", "wait": 1.0, "setup": _ft_sf_s_trap_collapse_l6, "check": _ft_sf_c_trap_collapse_l6},
			{"name": "FT-SF-TRAP-WIND-L3", "wait": 1.0, "setup": _ft_sf_s_trap_wind_l3, "check": _ft_sf_c_trap_wind_l3},
		]


var _ft_sf_hp0: float = 0.0 # FT-SF-OPP-SHIELD-STORM: health before the storm
var _ft_sf_heli_x0: float = 0.0 # FT-SF-SCENERY: helicopter x before the wait
var _ft_sf_wind_x0: float = 0.0 # FT-SF-TRAP-WIND-L3: player x before the wait


func _ft_sf_s_mode() -> void:
	# The features test starts in FFA (mode 0); Skyfall CTF needs
	# mode 4 + a real team. Switch the scene var (not just
	# GameData) and rebuild the flags (idempotent).
	game_mode = 4
	var lp = _ft_lp()
	lp.team = 0
	_build_ctf_flags()


func _ft_sf_c_mode() -> Array:
	var lp = _ft_lp()
	var ok := game_mode == 4 and _ctf_flags.size() == 2 and int(lp.team) == 0
	return [ok, "mode=%d flags=%d team=%d" % [game_mode, _ctf_flags.size(), int(lp.team)]]


func _ft_sf_c_map() -> Array:
	var m: Dictionary = MAPS[map_id]
	var ok := int(m.get("size", Vector2.ZERO).x) == 3400 and int(m.get("size", Vector2.ZERO).y) == 10800
	ok = ok and (m.get("platforms", []) as Array).size() == 55
	ok = ok and (m.get("spawns", []) as Array).size() == 12
	ok = ok and (m.get("grapple", []) as Array).size() == 8
	ok = ok and (m.get("jetpack_lines", []) as Array).size() == 2
	ok = ok and (m.get("relay", []) as Array).size() == 2
	ok = ok and (m.get("checkpoints", []) as Array).size() == 4
	ok = ok and (m.get("pickups", []) as Array).size() == 6
	ok = ok and (m.get("skyfall_pickups", []) as Array).size() == 7
	return [ok, "size=%s platforms=%d spawns=%d grapple=%d lines=%d relay=%d cps=%d weapons=%d powerups=%d" % [str(m.get("size")), (m.get("platforms", []) as Array).size(), (m.get("spawns", []) as Array).size(), (m.get("grapple", []) as Array).size(), (m.get("jetpack_lines", []) as Array).size(), (m.get("relay", []) as Array).size(), (m.get("checkpoints", []) as Array).size(), (m.get("pickups", []) as Array).size(), (m.get("skyfall_pickups", []) as Array).size()]]


func _ft_sf_s_grab() -> void:
	_ft_teleport(Vector2(2200, 820)) # above the BLUE flag (2200,862)


func _ft_sf_c_grab() -> Array:
	var carrier := int((_ctf_flags[1] as Dictionary).get("carrier", -1))
	var ok := carrier == multiplayer.get_unique_id()
	return [ok, "blue flag carrier=%d (me=%d)" % [carrier, multiplayer.get_unique_id()]]


func _ft_sf_s_capture() -> void:
	_ft_teleport(Vector2(450, 10710)) # above RED extraction (450,10752)


func _ft_sf_c_capture() -> Array:
	var ok := int(_ctf_scores.get(0, 0)) == GameData.CTF_CAPTURE_POINTS and int((_ctf_flags[1] as Dictionary).get("carrier", -1)) == -1
	return [ok, "RED=%d pts (capture=%d), blue flag carrier=%d" % [int(_ctf_scores.get(0, 0)), GameData.CTF_CAPTURE_POINTS, int((_ctf_flags[1] as Dictionary).get("carrier", -1))]]


func _ft_sf_s_relay_grab() -> void:
	_ft_teleport(Vector2(2200, 820))
	# QA-114: the grab key is (peer, flag team) — BLUE flag is team 1.
	_ctf_grab[multiplayer.get_unique_id() * 10 + 1] = 1.4 # nearly held — grabs on the next frame


func _ft_sf_c_relay_grab() -> Array:
	var carrier := int((_ctf_flags[1] as Dictionary).get("carrier", -1))
	var ok := carrier == multiplayer.get_unique_id()
	return [ok, "blue flag carrier=%d (me=%d)" % [carrier, multiplayer.get_unique_id()]]


func _ft_sf_s_relay_bank() -> void:
	_ft_teleport(Vector2(1800, 6620)) # above the Level 3 relay (1800,6670)


func _ft_sf_c_relay_bank() -> Array:
	var ok := int(_ctf_scores.get(0, 0)) == GameData.CTF_CAPTURE_POINTS + GameData.CTF_RELAY_POINTS
	ok = ok and int((_ctf_flags[1] as Dictionary).get("carrier", -1)) == -1
	ok = ok and not bool((_ctf_flags[1] as Dictionary).get("dropped", false))
	return [ok, "RED=%d pts (3 capture + 1 relay), flag home=%s" % [int(_ctf_scores.get(0, 0)), str(not bool((_ctf_flags[1] as Dictionary).get("dropped", false)))]]


func _ft_sf_s_cp_up() -> void:
	_ft_teleport(Vector2(1800, 1640)) # Level 6 arena


func _ft_sf_c_cp_up() -> Array:
	var ok := int(_ctf_checkpoints.get(0, -1)) == 3
	return [ok, "RED checkpoint=%d (want 3 = Level 6)" % int(_ctf_checkpoints.get(0, -1))]


func _ft_sf_s_cp_down() -> void:
	_ft_teleport(Vector2(1800, 10700)) # back to the base (new L1 floor y 10752)


func _ft_sf_c_cp_down() -> Array:
	var ok := int(_ctf_checkpoints.get(0, -1)) == 0
	return [ok, "RED checkpoint=%d (want 0 = base)" % int(_ctf_checkpoints.get(0, -1))]


func _ft_sf_s_die_l6_setup() -> void:
	_ft_teleport(Vector2(1800, 1640)) # Level 6 arena — checkpoint must advance first


func _ft_sf_c_die_l6_setup() -> Array:
	var ok := int(_ctf_checkpoints.get(0, -1)) == 3
	return [ok, "RED checkpoint=%d before dying (want 3)" % int(_ctf_checkpoints.get(0, -1))]


func _ft_sf_s_die_l6() -> void:
	var lp = _ft_lp()
	lp._apply_damage(999, 1, Vector2.ZERO, 0.0, 0) # lethal — respawn takes 3 s


func _ft_sf_c_die_l6() -> Array:
	var lp = _ft_lp()
	var ok := bool(lp.alive) and absf(lp.position.y - 1678.0) < 300.0
	return [ok, "alive=%s y=%.0f (want alive near L6 y=1678)" % [str(bool(lp.alive)), lp.position.y]]


func _ft_sf_s_slots() -> void:
	# QA-119 slot rule (user 2026-11-20 ~21:00): pickup NEVER
	# activates — every kind goes to a free slot and waits for a
	# tap, INCLUDING Health (7). So all three are stored, none active.
	var lp = _ft_lp()
	lp.apply_powerup(9) # speed (timed)
	lp.apply_powerup(8) # shield (timed)
	lp.apply_powerup(7) # health — takes a slot too, no instant heal


func _ft_sf_c_slots() -> Array:
	var lp = _ft_lp()
	var stored: Array = lp.get("stored_boosts")
	var ab := int(lp.get("active_boost_kind"))
	var total := stored.size() + (1 if ab != 0 else 0)
	var ok := total == 3 and stored.size() == 3 and ab == 0
	return [ok, "held=%d (want 3: speed+shield+health, all stored), slots used=%d (max 3), active=%d (want 0)" % [total, stored.size(), ab]]


func _ft_sf_s_active() -> void:
	# OPPOSITE: one active boost at a time, via the real tap path.
	# Speed (9) is active; Jetpack (10) is stored, then the player
	# taps its slot — the tap must do nothing and the boost stays
	# stored (kind 12 is instant Thunder in the new set, not a timed
	# boost, so the old "apply 12" setup no longer tests this rule).
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 9)
	lp.set("speed_timer", 30.0)
	lp.apply_powerup(10) # jetpack boost (timed) — goes to a slot
	lp.call("activate_slot", 0) # tap the slot: must be refused


func _ft_sf_c_active() -> Array:
	var lp = _ft_lp()
	var stored: Array = lp.get("stored_boosts")
	var ab := int(lp.get("active_boost_kind"))
	var ok := ab == 9 and 10 in stored
	lp.set("active_boost_kind", 0)
	lp.set("speed_timer", 0.0)
	return [ok, "active=%d (want 9 speed), jetpack stored=%s (want [10])" % [ab, str(stored)]]


func _ft_sf_s_carrier_ctrl() -> void:
	# CONTROL: a free player (not carrying) activates a timed boost
	# by tapping its slot. Kind 10 Jetpack is timed; kind 12 is
	# instant Thunder in the new set, so it cannot test this rule.
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.apply_powerup(10) # jetpack boost — stored, not active yet
	lp.call("activate_slot", 0) # tap: must activate


func _ft_sf_c_carrier_ctrl() -> Array:
	var lp = _ft_lp()
	var ab := int(lp.get("active_boost_kind"))
	lp.set("active_boost_kind", 0)
	lp.set("jetpack_boost_timer", 0.0)
	var ok := ab == 10
	return [ok, "free player jetpack boost active=%d (want 10)" % ab]


func _ft_sf_s_carrier() -> void:
	# OPPOSITE: the flag carrier must NOT activate a timed boost —
	# it stays stored until the flag is dropped/delivered. Timed
	# kind 10 Jetpack (kind 12 is instant Thunder in the new set).
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 1)
	lp.apply_powerup(10)
	lp.call("activate_slot", 0) # tap: must be refused (carrier rule)


func _ft_sf_c_carrier() -> Array:
	var lp = _ft_lp()
	var stored: Array = lp.get("stored_boosts")
	var ab := int(lp.get("active_boost_kind"))
	lp.set("carrying_flag", 0)
	var ok := ab == 0 and 10 in stored
	return [ok, "carrier jetpack boost active=%d (want 0), stored=%s (want [10])" % [ab, str(stored)]]


func _ft_sf_s_slot_btns() -> void:
	# QA-119 (v3.11): the 3 HUD slot buttons show the stored
	# power-up's icon and are tappable when the player CAN use it.
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.apply_powerup(8) # shield (timed) — slot 0
	lp.apply_powerup(10) # jetpack boost (timed) — slot 1


func _ft_sf_c_slot_btns() -> Array:
	var b0: Button = _sf_slot_buttons[0]
	var b1: Button = _sf_slot_buttons[1]
	var b2: Button = _sf_slot_buttons[2]
	var icons_ok := b0.icon == SF_TEX_PU64[8] and b1.icon == SF_TEX_PU64[10] and b2.icon == SF_TEX_SLOT[2]
	var ok := icons_ok and not b0.disabled and not b1.disabled and b2.disabled
	return [ok, "icons shield/jetpack/empty=%s, disabled=%s/%s/%s (want false/false/true)" % [str(icons_ok), str(b0.disabled), str(b1.disabled), str(b2.disabled)]]


var _ft_sf_path_kind: int = 0 # FT-SF-PATH-*: the kind under test (7-13)


func _ft_sf_path_spot(kind: int) -> int:
	var spots: Array = MAPS[map_id].get("skyfall_pickups", [])
	for i in spots.size():
		if int((spots[i] as Array)[2]) == kind:
			return i
	return -1


# QA-132: FT-SF-SLOT-TAP setup — tap a FILLED slot button through
# the REAL viewport input pipeline, at the button's screen position
# (QA-117 lesson: a tap swallowed by another control must fail
# this test, not pass on a direct activate_slot call). Shield is
# the timed kind used: it needs no target and no flag.
func _ft_sf_s_slot_tap() -> void:
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.apply_powerup(8) # shield -> slot 0
	var b0: Button = _sf_slot_buttons[0]
	var centre: Vector2 = b0.get_global_rect().get_center()
	var to_vp: Vector2 = hud.get_final_transform() * centre
	var press := InputEventScreenTouch.new()
	press.index = 904
	press.pressed = true
	press.position = to_vp
	get_viewport().push_input(press)
	var rel := InputEventScreenTouch.new()
	rel.index = 904
	rel.pressed = false
	rel.position = to_vp
	get_viewport().push_input(rel)


func _ft_sf_c_slot_tap() -> Array:
	var lp = _ft_lp()
	var ab := int(lp.get("active_boost_kind"))
	var st := float(lp.get("shield_timer"))
	var ok := ab == 8 and st > 0.0
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	return [ok, "real-touch tap on slot 0: active=%d shield=%.1fs (want 8 / >0)" % [ab, st]]


# QA-132: shared FT-SF-PATH-<kind> setup (7-13) — clean slate,
# spawn the kind's own power-up on its spot, teleport the player
# onto it. Wind/thunder need a live enemy in range to prove the
# effect, so a BLUE bot stands 300 px to the right of the spot
# (inside wind 520 / thunder 800). Wait 1.0 s covers the physical
# Area2D collection; the shared check then taps the slot and
# verifies the effect.
func _ft_sf_s_path(kind: int) -> void:
	_ft_sf_path_kind = kind
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.set("health", 50.0) # kind 7 must heal visibly; harmless for the rest
	lp.set("fuel", PhysicsConfig.FUEL_MAX)
	for child in pickups_node.get_children():
		if int(child.get("kind")) >= 7:
			child.free() # leftover power-ups from earlier steps
	for pid in [201, 202]:
		var old = players_node.get_node_or_null(str(pid))
		if old != null:
			old.queue_free() # leftover test bots from earlier steps
		# QA-132 fix: _do_spawn early-returns when _spawned still
		# has the pid (it never clears on free) — without this the
		# PATH-12 bot never spawns at all (PATH-11 already used 202).
		_spawned.erase(pid)
	var si := _ft_sf_path_spot(kind)
	_spawn_skyfall_powerup(si)
	var spot: Array = (MAPS[map_id].get("skyfall_pickups", []) as Array)[si]
	if kind == 11 or kind == 12:
		_do_spawn(202, "PathBot", 1, 0, 1)
		var b = players_node.get_node_or_null("202")
		if b != null:
			# QA-132 fix: +150 px, NOT +300 — +300 put the bot on
			# a platform seam (thunder spot x1200 + 300 = x1500,
			# the exact edge of two rows) and it fell out of the
			# 800 px thunder range. +150 lands on the SAME platform
			# as the player, 150 px away.
			b.position = Vector2(float(spot[0]) + 150.0, float(spot[1]))
			b.sync_position = b.position
			b.velocity = Vector2.ZERO
			b.health = 100
			b.set("_spawn_protect_timer", 0.0) # else take_hit ignores the blast
	_ft_teleport(Vector2(float(spot[0]), float(spot[1]) - 40.0))


func _ft_sf_s_path7() -> void: _ft_sf_s_path(7)
func _ft_sf_s_path8() -> void: _ft_sf_s_path(8)
func _ft_sf_s_path9() -> void: _ft_sf_s_path(9)
func _ft_sf_s_path10() -> void: _ft_sf_s_path(10)
func _ft_sf_s_path11() -> void: _ft_sf_s_path(11)
func _ft_sf_s_path12() -> void: _ft_sf_s_path(12)
func _ft_sf_s_path13() -> void: _ft_sf_s_path(13)


func _ft_sf_c_path() -> Array:
	var lp = _ft_lp()
	var kind := _ft_sf_path_kind
	var stored: Array = lp.get("stored_boosts")
	if kind not in stored:
		return [false, "kind %d never reached a slot (stored=%s)" % [kind, str(stored)]]
	var idx := stored.find(kind)
	var ok := false
	var detail := ""
	var ab0 := int(lp.get("active_boost_kind"))
	var cf0 := int(lp.get("carrying_flag"))
	match kind:
		7:
			var tapped7 := bool(lp.call("activate_slot", idx))
			ok = float(lp.health) >= 99.0
			detail = "tap=%s health=%.0f (want 100 after +50 from 50)" % [str(tapped7), float(lp.health)]
		8:
			var tapped8 := bool(lp.call("activate_slot", idx))
			ok = int(lp.get("active_boost_kind")) == 8 and float(lp.get("shield_timer")) > 0.0
			detail = "tap=%s pre_active=%d pre_flag=%d active=%d shield=%.1fs" % [str(tapped8), ab0, cf0, int(lp.get("active_boost_kind")), float(lp.get("shield_timer"))]
		9:
			var tapped9 := bool(lp.call("activate_slot", idx))
			ok = int(lp.get("active_boost_kind")) == 9 and float(lp.get("speed_timer")) > 0.0
			detail = "tap=%s pre_active=%d pre_flag=%d active=%d speed=%.1fs" % [str(tapped9), ab0, cf0, int(lp.get("active_boost_kind")), float(lp.get("speed_timer"))]
		10:
			var tapped10 := bool(lp.call("activate_slot", idx))
			var ab := int(lp.get("active_boost_kind"))
			var fuel_ok := absf(float(lp.fuel) - PhysicsConfig.FUEL_MAX) < 1.0
			# 1.5x jetpack flame while the boost runs (v3.11
			# fallback): force one visual update at full thrust
			# and read the flame — 1.5x gives scale.y ~0.82,
			# plain thrust tops out at ~0.54.
			lp.set("_jetpacking", true)
			lp.velocity = Vector2(0, -320)
			lp.set("_jet_thrust_factor", 1.0)
			lp.call("_update_visuals", 0.016)
			var flame = lp.get("_flame")
			var fscale := 0.0
			var fvis := false
			if flame != null:
				fscale = float((flame as Sprite2D).scale.y)
				fvis = bool((flame as Sprite2D).visible)
			lp.set("_jetpacking", false)
			ok = ab == 10 and float(lp.get("jetpack_boost_timer")) > 0.0 and fuel_ok and fvis and fscale > 0.7
			detail = "tap=%s pre_active=%d pre_flag=%d active=%d timer=%.1fs fuel=%.0f flame visible=%s scale.y=%.2f (want >0.7)" % [str(tapped10), ab0, cf0, ab, float(lp.get("jetpack_boost_timer")), float(lp.fuel), str(fvis), fscale]
		11:
			var bot = players_node.get_node_or_null("202")
			var tapped11 := bool(lp.call("activate_slot", idx))
			# QA-135: Wind Blast is a tornado now, not a shove — the
			# tap must spawn the tornado at the bot and start the
			# sweep on it (velocity is set by the victim's own
			# physics next frame, so the sweep timer + tornado node
			# are the synchronous proof; the throw-down is covered
			# by FT-SF-WIND-THROW with a longer wait).
			var torn_raw = get("_wind_tornado_node")
			var torn_ok := torn_raw != null and is_instance_valid(torn_raw)
			var sweep_t := 0.0
			if bot != null:
				sweep_t = float(bot.get("_wind_sweep_timer"))
			ok = int(lp.get("_fx_flash_kind")) == 11 and kind not in lp.get("stored_boosts") and torn_ok and sweep_t > 0.0
			detail = "tap=%s flash=%d tornado=%s sweep=%.2fs (want tornado + sweep > 0)" % [str(tapped11), int(lp.get("_fx_flash_kind")), str(torn_ok), sweep_t]
			if bot != null:
				bot.queue_free()
		12:
			var bot12 = players_node.get_node_or_null("202")
			var bp := Vector2(-1, -1)
			if bot12 != null:
				bp = bot12.position
			var tapped12 := bool(lp.call("activate_slot", idx))
			var hp1 := 100.0
			if bot12 != null:
				hp1 = float(bot12.health)
			# QA-135: Thunder Strike halves the target's CURRENT
			# health (100 -> 50), single target, no area damage.
			ok = int(lp.get("_fx_flash_kind")) == 12 and hp1 == 50.0
			detail = "tap=%s flash=%d bot pos=%s player pos=%s dist=%.0f bot health=%.0f (want 50 after halving 100)" % [str(tapped12), int(lp.get("_fx_flash_kind")), str(bp), str(lp.position), lp.position.distance_to(bp) if bp.x >= 0.0 else -1.0, hp1]
			if bot12 != null:
				bot12.queue_free()
		13:
			var tapped13 := bool(lp.call("activate_slot", idx))
			ok = int(lp.get("active_boost_kind")) == 13 and float(lp.get("invisibility_timer")) > 0.0
			detail = "tap=%s pre_active=%d pre_flag=%d active=%d invis=%.1fs" % [str(tapped13), ab0, cf0, int(lp.get("active_boost_kind")), float(lp.get("invisibility_timer"))]
	# Tidy up: end any timed boost so the next step starts clean.
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	return [ok, "kind %d path spawn->pickup->slot->tap->effect: %s" % [kind, detail]]


func _ft_sf_s_slot_grey_active() -> void:
	# Timed slots grey out while a boost is active; an instant
	# kind stays tappable even then.
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 9)
	lp.set("speed_timer", 30.0)
	lp.set("shield_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.apply_powerup(8) # shield (timed) — must grey out
	lp.apply_powerup(7) # health (instant) — must stay tappable


func _ft_sf_c_slot_grey_active() -> Array:
	var b0: Button = _sf_slot_buttons[0]
	var b1: Button = _sf_slot_buttons[1]
	var ok := b0.disabled and not b1.disabled
	var lp = _ft_lp()
	lp.set("active_boost_kind", 0)
	lp.set("speed_timer", 0.0)
	return [ok, "shield disabled=%s (want true), health disabled=%s (want false) while Speed active" % [str(b0.disabled), str(b1.disabled)]]


func _ft_sf_s_slot_grey_carrier() -> void:
	# Same split while carrying the flag: timed greys out
	# (carrier rule wins), instant stays tappable.
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 1)
	# QA-133: make the GAME state agree — the 0.5 s ctf_sync
	# rewrites carrying_flag from _ctf_carrier_of every 0.5 s, so
	# a manually-set flag would be wiped mid-wait and the button
	# would enable. The RED player carries the BLUE flag:
	# _ctf_flags[1] carrier = local peer -> carrying_flag 2.
	if _ctf_flags.size() > 1:
		(_ctf_flags[1] as Dictionary)["carrier"] = int(lp.peer_id)
	lp.apply_powerup(8) # shield (timed) — must grey out
	lp.apply_powerup(7) # health (instant) — must stay tappable


func _ft_sf_c_slot_grey_carrier() -> Array:
	var b0: Button = _sf_slot_buttons[0]
	var b1: Button = _sf_slot_buttons[1]
	var ok := b0.disabled and not b1.disabled
	var lp = _ft_lp()
	lp.set("carrying_flag", 0)
	if _ctf_flags.size() > 1:
		(_ctf_flags[1] as Dictionary)["carrier"] = -1 # QA-133: give the flag back
	return [ok, "shield disabled=%s (want true), health disabled=%s (want false) while carrying" % [str(b0.disabled), str(b1.disabled)]]


func _ft_sf_s_invis_warn() -> void:
	# QA-121 (v3.11): a living invisible ENEMY puts the red chip
	# at the top of the top-left message area.
	_do_spawn(201, "InvisBot", 1, 0, 1) # BLUE enemy
	var bot = players_node.get_node_or_null("201")
	if bot != null:
		bot.set("invisibility_timer", 10.0)


func _ft_sf_c_invis_warn() -> Array:
	var chip_ok := _invis_warning_chip != null and _invis_warning_chip.visible
	var txt := ""
	if _invis_warning_chip != null:
		txt = (_invis_warning_chip.get_child(0) as Label).text
	var ok := chip_ok and txt == "Enemy is invisible!"
	return [ok, "warning chip visible=%s text='%s' (want true / 'Enemy is invisible!')" % [str(chip_ok), txt]]


func _ft_sf_s_invis_clear() -> void:
	var bot = players_node.get_node_or_null("201")
	if bot != null:
		bot.set("invisibility_timer", 0.0)


func _ft_sf_c_invis_clear() -> Array:
	var ok := _invis_warning_chip == null or not _invis_warning_chip.visible
	var bot = players_node.get_node_or_null("201")
	if bot != null:
		bot.queue_free()
	return [ok, "warning chip hidden=%s after the invisibility ends" % str(ok)]


func _ft_sf_s_shield_storm() -> void:
	# OPPOSITE: shield active while the Summit Storm fires — the
	# storm must not damage the player or break the shield.
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	_ft_sf_hp0 = float(lp.health)
	lp.apply_powerup(8) # shield
	_sf_storm_timer = 0.01 # fire the storm now


func _ft_sf_c_shield_storm() -> Array:
	var lp = _ft_lp()
	var stored: Array = lp.get("stored_boosts")
	var ab := int(lp.get("active_boost_kind"))
	var shield_held := ab == 8 or 8 in stored
	var ok := bool(_sf_storm_active) and shield_held and float(lp.health) >= _ft_sf_hp0
	return [ok, "storm=%s shield held=%s health=%.0f (was %.0f)" % [str(bool(_sf_storm_active)), str(shield_held), float(lp.health), _ft_sf_hp0]]


func _ft_sf_s_comeback() -> void:
	var lp = _ft_lp()
	lp.set("carrying_flag", 0)
	# QA-132 fix: RED already led 4-0 from RELAY-BANK, so the trail
	# never CHANGED in this setup and the 5 s bonus timer never
	# re-armed — the earlier bonus (spawned mid-test) was freed by
	# the PATH setups' pickup cleanup, and the 25 s cycle did not
	# fire again inside the 6 s wait. Force the trail-change branch
	# and clear any stale bonus pickup so a fresh one spawns at 5 s.
	for child in pickups_node.get_children():
		if int(child.get("spot_index")) == 201:
			child.free()
	_sf_comeback_team = -1
	_ctf_scores = {0: 4, 1: 0} # RED leads by 4 — BLUE trails


func _ft_sf_c_comeback() -> Array:
	var bonus := false
	for child in pickups_node.get_children():
		if int(child.get("spot_index")) == 201: # BLUE's comeback bonus spot
			bonus = true
			break
	var ok := _sf_comeback_team == 1 and _sf_summit_timer > 0.0 and bool(_sf_comeback_label.visible) and bonus
	return [ok, "trailing=%d (want 1=BLUE) elevator timer=%.1fs label=%s bonus pickup=%s comeback_pu_timer=%.1fs scores=%s" % [_sf_comeback_team, _sf_summit_timer, str(bool(_sf_comeback_label.visible)), str(bonus), _sf_comeback_pu_timer, str(_ctf_scores)]]


func _ft_sf_s_event() -> void:
	_sf_event_timer = 0.01 # fire a random event now


func _ft_sf_c_event() -> Array:
	var ok := _sf_event_active != "" or _sf_event_timer >= 45.0
	return [ok, "event=%s timer=%.1fs (an event fired at a random time)" % [_sf_event_active, _sf_event_timer]]


func _ft_sf_s_storm() -> void:
	_sf_storm_timer = 0.01 # fire the storm now


func _ft_sf_c_storm() -> Array:
	var ok := bool(_sf_storm_active)
	return [ok, "storm active=%s" % str(bool(_sf_storm_active))]


func _ft_sf_s_combo_event_storm() -> void:
	# COINCIDENCE: a random event fires WHILE the storm is active.
	# If the storm is already running, refresh its duration — the
	# timer alone does nothing while it is active (and the storm's
	# end resets the timer to 90, which would swallow a fresh 0.01).
	_sf_storm_timer = 0.01
	if _sf_storm_active:
		_sf_storm_time_left = 10.0
	_sf_event_timer = 0.01


func _ft_sf_c_combo_event_storm() -> Array:
	var ok := bool(_sf_storm_active) and (_sf_event_active != "" or _sf_event_timer >= 45.0) and _ctf_flags.size() == 2
	return [ok, "storm=%s event=%s flags=%d (both systems live, no crash)" % [str(bool(_sf_storm_active)), _sf_event_active, _ctf_flags.size()]]


func _ft_sf_s_combo_trap() -> void:
	# COINCIDENCE: falling onto a trap door — it must open under
	# the player after 1 s standing.
	var rect: Rect2 = (MAPS[map_id].get("platforms", []) as Array)[20]
	_ft_teleport(rect.get_center() + Vector2(0, -40))


func _ft_sf_c_combo_trap() -> Array:
	var lp = _ft_lp()
	var td: Dictionary = _sf_trapdoors[0]
	var rect: Rect2 = td["rect"]
	var py: float = lp.position.y
	var ok: bool = str(td.get("state", "")) == "open" and py > rect.position.y + 50.0
	return [ok, "trapdoor=%s player y=%.0f (platform y=%.0f, want player below it)" % [str(td.get("state", "")), py, rect.position.y]]


func _ft_sf_c_levels() -> Array:
	# QA-123: the rebuilt tower is 6 levels x 1800 px (L1 bottom,
	# L6 summit). Check the level function at one sample per level,
	# the relay levels (3 and 6), the checkpoint levels, and the
	# bridge gust schedule (3 s on / 12 s off per 15 s).
	var got := [_sf_level_of(10000.0), _sf_level_of(8000.0), _sf_level_of(6300.0), _sf_level_of(4500.0), _sf_level_of(2700.0), _sf_level_of(900.0)]
	var ok := got == [1, 2, 3, 4, 5, 6]
	ok = ok and _sf_level_of(6384.0) == 3 and _sf_level_of(1678.0) == 6
	ok = ok and GameData.SF_CHECKPOINT_LEVELS == [0, 2, 4, 6]
	_sf_match_time = 1.0
	var gust_on := _sf_gust_active()
	_sf_match_time = 5.0
	var gust_off := not _sf_gust_active()
	ok = ok and gust_on and gust_off
	return [ok, "levels=%s (want [1,2,3,4,5,6]) relay L%d/L%d cps=%s gust 1s=%s 5s=%s" % [str(got), _sf_level_of(6384.0), _sf_level_of(1678.0), str(GameData.SF_CHECKPOINT_LEVELS), str(gust_on), str(not gust_off)]]


func _ft_sf_s_hazard_lava() -> void:
	# QA-126: stand in the L5 lava pool while the jets are HOT —
	# health must drop by 10 per 1 s tick. Clear the shield first
	# (an earlier step may have left one up) and force the hot
	# phase (match clock 0.5 s into the 4 s cycle).
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("health", 100.0) # full health, so the -10/tick is measurable
	_ft_sf_hp0 = float(lp.health)
	_sf_match_time = 0.5
	_ft_teleport(Vector2(1100, 2460)) # on the lava pool (950,2420,300,84)


func _ft_sf_c_hazard_lava() -> Array:
	var lp = _ft_lp()
	var ok := float(lp.health) <= _ft_sf_hp0 - 10.0
	return [ok, "health=%.0f (was %.0f, want <= -10 from the lava ticks)" % [float(lp.health), _ft_sf_hp0]]


func _ft_sf_s_lightning() -> void:
	# QA-126: force the Summit Storm + a strike on the local player
	# (teleported to the summit, y < 3600). The 0.6 s telegraph
	# runs, then the bolt hits for 15 — unless the shield is up
	# (that case is covered by FT-SF-OPP-SHIELD-STORM).
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("health", 100.0) # full health, so the -15 strike is measurable
	_ft_sf_hp0 = float(lp.health)
	# QA-132 fix: a leftover TestBot (peer 99, from the base
	# KILLFEED step) stands at the summit, so the strike picked a
	# RANDOM candidate (50/50) — free every other player NOW
	# (free() is immediate; queue_free would leave the bot alive
	# for the first strike schedule) so the local player is the
	# only strike target. Later steps spawn their own bots.
	for child in players_node.get_children():
		if child != lp:
			_spawned.erase(int(child.peer_id))
			child.free()
	_ft_teleport(Vector2(1800, 1000)) # summit, inside the strike zone
	_sf_storm_active = true
	_sf_storm_time_left = 10.0
	# A strike may already be pending from the earlier forced storm
	# (its 3 s cadence is longer than this step's 2 s wait, and it
	# could be a visual-only strike on an empty platform) — clear
	# it so a fresh strike is scheduled on the local player at once.
	_sf_clear_strike_marker()
	_sf_strike_timer = 0.01


func _ft_sf_c_lightning() -> Array:
	var lp = _ft_lp()
	var ok := float(lp.health) <= _ft_sf_hp0 - 15.0
	# Tidy up: end the forced storm so later steps run in clear air.
	_sf_storm_active = false
	_sf_storm_time_left = 0.0
	_sf_storm_timer = 90.0
	_sf_clear_strike_marker()
	return [ok, "health=%.0f (was %.0f, want <= -15 from the strike)" % [float(lp.health), _ft_sf_hp0]]


func _ft_sf_s_heightbar() -> void:
	_ft_teleport(Vector2(1800, 2660)) # Level 5


func _ft_sf_c_heightbar() -> Array:
	var want_y := 360.0 * 2660.0 / 10800.0 - 6.0
	var dot: ColorRect = _sf_height_dots[0]
	var ok := bool(_sf_height_bar.visible) and dot.visible and absf(dot.position.y - want_y) < 15.0
	return [ok, "height bar=%s dot0 y=%.1f (want %.1f)" % [str(bool(_sf_height_bar.visible)), dot.position.y, want_y]]


func _ft_sf_s_ping() -> void:
	_on_ping_pressed()


func _ft_sf_c_ping() -> Array:
	var bar_dot := false
	for pd in _sf_height_ping_dots:
		if (pd as ColorRect).visible:
			bar_dot = true
			break
	var ok := _sf_pings.size() >= 1 and bar_dot
	return [ok, "pings=%d height-bar ping dot=%s" % [_sf_pings.size(), str(bar_dot)]]


func _ft_sf_c_routes() -> Array:
	var ok := skyfall_route_of(500.0) == 0 and skyfall_route_of(1800.0) == 1 and skyfall_route_of(3000.0) == 2
	var legend_n := 0
	for c in _sf_height_bar.get_children():
		if c is VBoxContainer:
			legend_n = c.get_child_count()
			break
	ok = ok and legend_n == 3
	return [ok, "routes WEST/CENTRE/EAST=%d/%d/%d legend rows=%d" % [skyfall_route_of(500.0), skyfall_route_of(1800.0), skyfall_route_of(3000.0), legend_n]]


func _ft_sf_s_scenery() -> void:
	_ft_sf_heli_x0 = float((_sf_scenery.get("heli") as Node2D).position.x)


func _ft_sf_c_scenery() -> Array:
	var heli: Node2D = _sf_scenery.get("heli")
	var ok := heli != null and heli.position.x > _ft_sf_heli_x0
	ok = ok and (_sf_scenery.get("clouds", []) as Array).size() == 5
	ok = ok and not _sf_scenery.has("gears") # QA-132: gears deleted
	ok = ok and not _sf_scenery.has("puffs") # QA-132: steam puffs deleted
	ok = ok and (_sf_scenery.get("streaks", []) as Array).size() == 5
	ok = ok and _sf_scenery.get("flash") != null
	return [ok, "heli moved %.0f -> %.0f, clouds=%d gears=%s puffs=%s streaks=%d flash=%s" % [_ft_sf_heli_x0, heli.position.x if heli != null else -1.0, (_sf_scenery.get("clouds", []) as Array).size(), str(not _sf_scenery.has("gears")), str(not _sf_scenery.has("puffs")), (_sf_scenery.get("streaks", []) as Array).size(), str(_sf_scenery.get("flash") != null)]]


# QA-134 (v3.13): no mover's travel path may pass under, through,
# or overlap any static platform rect. Swept rect = x..x+w,
# y_top..y_bottom+48 (the body is 48 tall, top = y). The summit
# elevator the same. Rotator: the body (400x48) orbits a 120 px
# circle — sample 36 angles and check the body rect at each.
# Rect2.intersects excludes edge-touching, so docking flush
# against a platform top is fine. Collapsing platforms only drop
# 120 px then fade (no travel path); trapdoors only swap texture.
func _ft_sf_s_noop() -> void:
	pass


func _ft_sf_c_mover_clear() -> Array:
	var plats: Array = MAPS[map_id].get("platforms", [])
	var bad: Array = []
	for e in MAPS[map_id].get("elevators", []):
		var r := Rect2(float(e["x"]), float(e["y_top"]), float(e["w"]), float(e["y_bottom"]) - float(e["y_top"]) + 48.0)
		for i in plats.size():
			if r.intersects(plats[i]):
				bad.append("elev x%d plat %d" % [int(e["x"]), i])
	var se: Dictionary = MAPS[map_id].get("summit_elevator", {})
	if not se.is_empty():
		var sr := Rect2(float(se["x"]), float(se["y_top"]), float(se.get("w", 300)), float(se["y_bottom"]) - float(se["y_top"]) + 48.0)
		for i in plats.size():
			if sr.intersects(plats[i]):
				bad.append("summit plat %d" % i)
	var rc: Dictionary = MAPS[map_id].get("rotator", {})
	if not rc.is_empty():
		var c: Vector2 = rc["center"]
		var rad := float(rc.get("radius", 120.0))
		var hw := float(rc.get("w", 400)) * 0.5
		for a in 36:
			var ang := TAU * float(a) / 36.0
			var bc: Vector2 = c + Vector2(cos(ang), sin(ang)) * rad
			var br := Rect2(bc - Vector2(hw, 24.0), Vector2(hw * 2.0, 48.0))
			for i in plats.size():
				if br.intersects(plats[i]):
					bad.append("rotator a%d plat %d" % [a, i])
					break
	var ok := bad.is_empty()
	return [ok, "mover overlaps=%s (want none)" % str(bad)]


# QA-135 (v3.13): Wind Blast / Thunder Strike targeting — the
# target must be on the SAME PLATFORM at the SAME HEIGHT (within
# 60 px). Shared setup for the no-target / height tests: clean
# slate, the kind in a slot, the player on the wind/thunder spot
# (row 14), no other players. `bot_y` places a bot 150 px away
# on the same spot with a vertical offset (0 = same platform,
# -150 = hovering above it); -999 = no bot at all.
func _ft_sf_s_pu_target(kind: int, bot_y: float) -> void:
	var lp = _ft_lp()
	lp.get("stored_boosts").clear()
	lp.set("active_boost_kind", 0)
	lp.set("shield_timer", 0.0)
	lp.set("speed_timer", 0.0)
	lp.set("jetpack_boost_timer", 0.0)
	lp.set("invisibility_timer", 0.0)
	lp.set("carrying_flag", 0)
	lp.set("health", 100.0)
	lp.set("fuel", PhysicsConfig.FUEL_MAX)
	for child in pickups_node.get_children():
		if int(child.get("kind")) >= 7:
			child.free()
	for pid in [201, 202]:
		var old = players_node.get_node_or_null(str(pid))
		if old != null:
			old.queue_free()
		_spawned.erase(pid)
	var si := _ft_sf_path_spot(11)
	var spot: Array = (MAPS[map_id].get("skyfall_pickups", []) as Array)[si]
	lp.position = Vector2(float(spot[0]), float(spot[1]))
	lp.velocity = Vector2.ZERO
	lp.sync_position = lp.position
	lp.call("apply_powerup", kind)
	if bot_y > -900.0:
		_do_spawn(202, "PathBot", 1, 0, 1)
		var b = players_node.get_node_or_null("202")
		if b != null:
			b.position = Vector2(float(spot[0]) + 150.0, float(spot[1]) + bot_y)
			b.sync_position = b.position
			b.velocity = Vector2.ZERO
			b.health = 100
			b.set("_spawn_protect_timer", 0.0)


func _ft_sf_s_wind_no_target() -> void:
	_ft_sf_s_pu_target(11, -999.0)


func _ft_sf_c_wind_no_target() -> Array:
	var lp = _ft_lp()
	var idx := int(lp.get("stored_boosts").find(11))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var kept: bool = 11 in lp.get("stored_boosts")
	# QA-135: read the tornado through a Variant + is_instance_valid
	# — a typed Node2D assignment errors if the reference dangles
	# (a freed tornado from an earlier step).
	var torn_raw = get("_wind_tornado_node")
	var torn_ok := torn_raw != null and is_instance_valid(torn_raw)
	var ok := not tapped and kept and not torn_ok
	return [ok, "tap=%s slot kept=%s tornado=%s (want tap=false, kept, no tornado)" % [str(tapped), str(kept), str(torn_ok)]]


func _ft_sf_s_thunder_no_target() -> void:
	_ft_sf_s_pu_target(12, -999.0)


func _ft_sf_c_thunder_no_target() -> Array:
	var lp = _ft_lp()
	var idx := int(lp.get("stored_boosts").find(12))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var kept: bool = 12 in lp.get("stored_boosts")
	var ok := not tapped and kept
	return [ok, "tap=%s slot kept=%s (want tap=false, kept)" % [str(tapped), str(kept)]]


# QA-135: Wind Blast throw-down — the tap happens in the setup
# (sweep starts at t=0); after 1.5 s the bot must have fallen
# below the platform it stood on (sweep 0.7 s + throw 0.5 s +
# fall), with full health (no damage).
func _ft_sf_s_wind_throw() -> void:
	_ft_sf_s_pu_target(11, 0.0)
	var lp = _ft_lp()
	var idx := int(lp.get("stored_boosts").find(11))
	if idx >= 0:
		lp.call("activate_slot", idx)


func _ft_sf_c_wind_throw() -> Array:
	var lp = _ft_lp()
	var bot = players_node.get_node_or_null("202")
	var plat_idx := _sf_platform_under(lp.position)
	var top := 0.0
	if plat_idx >= 0:
		top = (MAPS[map_id].get("platforms", []) as Array)[plat_idx].position.y
	var by := -1.0
	var bh := -1.0
	if bot != null:
		by = float(bot.position.y)
		bh = float(bot.health)
	var ok := bot != null and by > top + 200.0 and bh == 100.0
	return [ok, "bot y=%.0f plat top=%.0f (want >%.0f) bot health=%.0f (want 100, no damage)" % [by, top, top + 200.0, bh]]


# QA-135: Thunder Strike vs a shielded enemy — the strike fires
# (the bot IS on the platform) but the shield absorbs it all.
func _ft_sf_s_thunder_shield() -> void:
	_ft_sf_s_pu_target(12, 0.0)
	var bot = players_node.get_node_or_null("202")
	if bot != null:
		bot.set("shield_timer", 10.0)


func _ft_sf_c_thunder_shield() -> Array:
	var lp = _ft_lp()
	var bot = players_node.get_node_or_null("202")
	var idx := int(lp.get("stored_boosts").find(12))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var bh := -1.0
	if bot != null:
		bh = float(bot.health)
	var ok := tapped and bh == 100.0
	return [ok, "tap=%s bot health=%.0f (want tap=true, health 100 — shield absorbed the halving)" % [str(tapped), bh]]


# QA-135: height exclusion — the enemy hovers 150 px above the
# platform (jetpacking), so it is NOT on the platform surface and
# its height is far outside the 60 px tolerance. Neither
# power-up may fire; the slot is kept.
func _ft_sf_s_wind_height() -> void:
	_ft_sf_s_pu_target(11, -150.0)


func _ft_sf_c_wind_height() -> Array:
	var lp = _ft_lp()
	var idx := int(lp.get("stored_boosts").find(11))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var kept: bool = 11 in lp.get("stored_boosts")
	var ok := not tapped and kept
	return [ok, "tap=%s slot kept=%s (want tap=false, kept — bot 150 px above the platform)" % [str(tapped), str(kept)]]


func _ft_sf_s_thunder_height() -> void:
	_ft_sf_s_pu_target(12, -150.0)


func _ft_sf_c_thunder_height() -> Array:
	var lp = _ft_lp()
	var idx := int(lp.get("stored_boosts").find(12))
	var tapped := false
	if idx >= 0:
		tapped = bool(lp.call("activate_slot", idx))
	var kept: bool = 12 in lp.get("stored_boosts")
	var ok := not tapped and kept
	return [ok, "tap=%s slot kept=%s (want tap=false, kept — bot 150 px above the platform)" % [str(tapped), str(kept)]]


# QA-135 (v3.13): new traps per level. Rocks (L1): force the
# spawn timer to 0 — a rock must exist after the wait.
func _ft_sf_s_trap_rocks() -> void:
	_ft_lp()
	_sf_rock_timer = 0.0


func _ft_sf_c_trap_rocks() -> Array:
	var ok := _sf_rocks.size() > 0
	return [ok, "falling rocks=%d (want >0 — L1 interval 2.5 s, max 4)" % _sf_rocks.size()]


# Trapdoors (L2): the new trapdoor idx 19 must open after the
# player stands on it for 1.0 s.
func _ft_sf_s_trap_trapdoor_l2() -> void:
	var lp = _ft_lp()
	lp.set("health", 100.0)
	for td in _sf_trapdoors:
		if int(td.get("idx", -1)) == 19:
			var r: Rect2 = td["rect"]
			lp.position = Vector2(r.get_center().x, r.position.y - 31.0)
			lp.velocity = Vector2.ZERO
			lp.sync_position = lp.position
			break


func _ft_sf_c_trap_trapdoor_l2() -> Array:
	var state := "missing"
	for td in _sf_trapdoors:
		if int(td.get("idx", -1)) == 19:
			state = str(td.get("state", "?"))
			break
	var ok := state == "open"
	return [ok, "trapdoor idx 19 state=%s (want open after standing 1 s)" % state]


# Lava (L5): the new lava2 hazard (2150,2980) must deal 10 HP
# per tick while HOT. The match clock is reset to 0 so the zone
# is HOT for the whole wait (2 s on / 2 s off per 4 s cycle).
func _ft_sf_s_trap_lava2() -> void:
	var lp = _ft_lp()
	lp.set("health", 100.0)
	lp.set("shield_timer", 0.0)
	_sf_match_time = 0.0
	# Teleport 40 px BELOW the hazard top (inside the lava, like
	# the old HAZARD-LAVA test) so the player box overlaps the
	# hazard rect — a standing player's box only touches its top
	# edge, which Rect2.intersects does not count.
	_ft_teleport(Vector2(2300.0, 3020.0)) # in the new lava2 pool (2150,2980,300,84)


func _ft_sf_c_trap_lava2() -> Array:
	var lp = _ft_lp()
	var hp := float(lp.get("health"))
	var ok := hp <= 90.0
	return [ok, "player health=%.0f (want <=90 after a 10 HP lava tick)" % hp]


# Storm lightning (L4): force the strike timer to 0 with the
# player in L4 — the bolt must land within 1.5 s (0.6 s
# telegraph + strike) for 15 HP.
func _ft_sf_s_trap_lightning_l4() -> void:
	# QA-136 (v3.13 build gate): the old setup stood the player on
	# the FIRST L4 platform in list order — platform #36, which is
	# a COLLAPSING platform (0.8 s shake, then the shape drops and
	# the player falls out of the strike's 200 px radius before the
	# 0.6 s telegraph resolves). Stand on the first STATIC L4
	# platform instead (not collapsing, not a trapdoor), clear any
	# in-flight strike marker, and move every other living player
	# out of L4 so the random target pick can only choose the local
	# player — the strike must be deterministic in a test.
	var lp = _ft_lp()
	lp.set("health", 100.0)
	lp.set("shield_timer", 0.0)
	_sf_clear_strike_l4_marker()
	var plats: Array = MAPS[map_id].get("platforms", [])
	var collapse: Array = MAPS[map_id].get("collapsing", [])
	var traps: Array = MAPS[map_id].get("trapdoors", [])
	for i in plats.size():
		var r: Rect2 = plats[i]
		if r.position.y >= 3600.0 and r.position.y < 5400.0 and not collapse.has(i) and not traps.has(i):
			lp.position = Vector2(r.get_center().x, r.position.y - 31.0)
			lp.velocity = Vector2.ZERO
			lp.sync_position = lp.position
			break
	for child in players_node.get_children():
		if child == lp or not child.alive:
			continue
		child.position = Vector2(1800.0, 10378.0)
		child.velocity = Vector2.ZERO
		child.sync_position = child.position
	_sf_strike_l4_timer = 0.0


func _ft_sf_c_trap_lightning_l4() -> Array:
	var lp = _ft_lp()
	var hp := float(lp.get("health"))
	var ok := hp <= 85.0
	return [ok, "player health=%.0f (want <=85 after a 15 HP lightning strike)" % hp]


# Collapsing (L6): the new summit step idx 50 must start
# shaking after the player stands on it.
func _ft_sf_s_trap_collapse_l6() -> void:
	var lp = _ft_lp()
	lp.set("health", 100.0)
	for c in _sf_collapsing:
		if int(c.get("idx", -1)) == 50:
			var r: Rect2 = c["rect"]
			lp.position = Vector2(r.get_center().x, r.position.y - 31.0)
			lp.velocity = Vector2.ZERO
			lp.sync_position = lp.position
			break


func _ft_sf_c_trap_collapse_l6() -> Array:
	var state := "missing"
	for c in _sf_collapsing:
		if int(c.get("idx", -1)) == 50:
			state = str(c.get("state", "?"))
			break
	var ok := state == "shaking" or state == "falling"
	return [ok, "collapsing idx 50 state=%s (want shaking/falling after standing on it)" % state]


# Wind gusts (L3): the new upper wind zone (1400,5400,800,600,
# pushes left) must push the player left.
func _ft_sf_s_trap_wind_l3() -> void:
	var lp = _ft_lp()
	lp.position = Vector2(1800.0, 5700.0)
	lp.velocity = Vector2.ZERO
	lp.sync_position = lp.position
	_ft_sf_wind_x0 = lp.position.x


func _ft_sf_c_trap_wind_l3() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp.position.x < _ft_sf_wind_x0 - 20.0
	return [ok, "player x=%.0f (was %.0f, want <%.0f — pushed left by the new L3 wind zone)" % [lp.position.x, _ft_sf_wind_x0, _ft_sf_wind_x0 - 20.0]]


func _ft_sf_s_rarity() -> void:
	# Simulate 300 s of the spawn loops (1 s steps) and count.
	# Start from an empty field (as at match start) and clear the
	# field every 10 s — in a real match players grab pickups, and
	# without that the field sits at its cap and nothing respawns
	# (the first version of this test measured 0 power-ups for
	# exactly that reason). free() is immediate here (queue_free
	# would wait for the next frame, which never comes mid-loop).
	_test_weapon_spawns = 0
	_test_powerup_spawns = 0
	for child in pickups_node.get_children():
		child.free()
	_pickup_spot_timers.clear()
	_sf_pickup_timers.clear()
	_initial_pickups_done = false
	_sf_initial_powerups_done = false
	for i in 300:
		_update_pickup_spawn(1.0)
		_update_skyfall_powerups(1.0)
		if i % 10 == 9:
			for child in pickups_node.get_children():
				child.free()


func _ft_sf_c_rarity() -> Array:
	var ok := _test_weapon_spawns > _test_powerup_spawns and _test_powerup_spawns > 0
	return [ok, "300 s sim: weapons=%d power-ups=%d (power-ups must be rarer)" % [_test_weapon_spawns, _test_powerup_spawns]]


func _ft_sf_s_5v5() -> void:
	# 10 players in the game scene (test-only fake peers — never in
	# the real game, which has no bots). Remove the TestBot left by
	# the base KILLFEED/SPECTATOR steps first, then spawn 9 fakes
	# with explicit teams: local (RED) + 4 RED + 5 BLUE = 5v5.
	GameData.max_players = 10
	for child in players_node.get_children():
		if String(child.player_name).begins_with("TestBot"):
			child.queue_free()
	for i in range(1, 5):
		_do_spawn(100 + i, "TestBot%d" % i, i % 4, 0, 0)
	for i in range(5, 10):
		_do_spawn(100 + i, "TestBot%d" % i, i % 4, 0, 1)


func _ft_sf_c_5v5() -> Array:
	var red := 0
	var blue := 0
	for child in players_node.get_children():
		if int(child.team) == 0:
			red += 1
		elif int(child.team) == 1:
			blue += 1
	var ok := players_node.get_child_count() == 10 and red == 5 and blue == 5
	return [ok, "players=%d RED=%d BLUE=%d (want 10 / 5 / 5)" % [players_node.get_child_count(), red, blue]]


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
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	var b = players_node.get_node_or_null("99")
	if b == null:
		_do_spawn(99, "TestBot", 0, 0)
		b = players_node.get_node_or_null("99")
	_feat_bot = b
	if b != null:
		b.position = Vector2(600, 1318) # QA-071: floor 1352, centre top-34
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


func _ft_collect_label_texts(list: VBoxContainer) -> Array:
	# QA-113 (v3.9): the stats redesign puts rows in HBoxContainers
	# with one Label per column — collect every Label's text, direct
	# children and one level inside row boxes.
	var out: Array = []
	for c in list.get_children():
		if c is Label:
			out.append(String(c.text))
		elif c is HBoxContainer:
			for sub in c.get_children():
				if sub is Label:
					out.append(String(sub.text))
	return out


func _ft_c_endstats() -> Array:
	var mvp_ok := false
	for n in _mvp_nodes:
		if n is HBoxContainer:
			for c in n.get_children():
				if c is Label and String(c.text).contains("MVP: Player") and String(c.text).contains("60%"):
					mvp_ok = true
	# QA-113: rows are column HBoxes now — a row holds the K/D cell
	# ("2.50") and the ACC cell ("60%") as separate Labels.
	var row_ok := false
	for c in end_list.get_children():
		if c is HBoxContainer:
			var has_kd := false
			var has_acc := false
			for sub in c.get_children():
				if sub is Label and String(sub.text) == "2.50":
					has_kd = true
				if sub is Label and String(sub.text) == "60%":
					has_acc = true
			if has_kd and has_acc:
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
		b.position = Vector2(600, 1318) # QA-071: floor 1352, centre top-34
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
		b2.position = Vector2(900, 1318) # QA-071: floor 1352, centre top-34
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
	# QA-113: the header row holds "K/D" and "ACC" as separate
	# column Labels, and the self row holds "(YOU)" in its name
	# cell — collect all Label texts (direct + inside row HBoxes).
	var texts: Array = _ft_collect_label_texts(scoreboard_list)
	var kd_ok := "K/D" in texts and "ACC" in texts
	var self_ok := false
	for t in texts:
		if String(t).contains("(YOU)"):
			self_ok = true
	var team_ok := false # TDM totals header: must be found below
	# TDM totals header: flip the mode, rebuild, check, restore.
	game_mode = 1
	_update_scoreboard_rows(scoreboard_list)
	for t in _ft_collect_label_texts(scoreboard_list):
		if String(t).contains("RED") and String(t).contains("BLUE"):
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


# QA-079: HUD readouts — the K/D line is filled, the ammo line
# shows mag/reserve, the HP bar is green at full health.
func _ft_c_hud() -> Array:
	var lp = _get_local_player()
	var kd_ok: bool = _kd_label != null and String(_kd_label.text).begins_with("K ") and "• D " in String(_kd_label.text)
	var ammo_ok: bool = "/" in weapon_label.text
	var hp_ok: bool = hp_bar.ink == UI_SUCCESS
	return [kd_ok and ammo_ok and hp_ok, "kd='%s' ammo='%s' hp_ink_green=%s" % [_kd_label.text if _kd_label != null else "?", weapon_label.text, hp_ok]]


var _feat_data: Dictionary = {}
