class_name GameAssets
extends RefCounted


# QA-140 (v3.15): texture / scene asset tables extracted from game.gd.
# Pure data — preloads and lookup tables. Referenced as GameAssets.NAME
# from game.gd and every module (was g.NAME).


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
const BG_TEX: Array[Texture2D] = [
	preload("res://assets/skybrawl/maps/bg_ironfall.png"),
	preload("res://assets/skybrawl/maps/bg_volcanic.png"),
	preload("res://assets/skybrawl/maps/bg_neon.png"),
	preload("res://assets/skyfall/SKYFALL_assets/map/bg_sky_dusk.png"),
]
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
const SF_TEX_LVL_1: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_1_twin_base_camp.png")
const SF_TEX_LVL_2: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_2_broken_cliffs.png")
const SF_TEX_LVL_3: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_3_underground_tunnels.png")
const SF_TEX_LVL_4: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_4_hanging_bridge.png")
const SF_TEX_LVL_5: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_5_sniper_territory.png")
const SF_TEX_LVL_6: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_6_mechanical_ascent.png")
const SF_TEX_LVL_7: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_7_the_last_stand.png")
const SF_TEX_LVL_8: Texture2D = preload("res://assets/skyfall/SKYFALL_assets/levels/level_8_flag_summit.png")
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
const TRAP_TEX_GRATE: Texture2D = preload("res://assets/user_assets_v3/trap_new_r1_c1.png")
const TRAP_TEX_GRATE_BROKEN: Texture2D = preload("res://assets/user_assets_v3/trap_new_r6_c1.png")
const TRAP_TEX_BALL: Texture2D = preload("res://assets/user_assets_v3/trap_ball.png")
const TRAP_TEX_FIRE_VENT: Array[Texture2D] = [
	preload("res://assets/user_assets_v3/trap_new_r4_c1.png"),
	preload("res://assets/user_assets_v3/trap_new_r4_c2.png"),
	preload("res://assets/user_assets_v3/trap_new_r4_c3.png"),
	preload("res://assets/user_assets_v3/trap_new_r4_c4.png"),
	preload("res://assets/user_assets_v3/trap_new_r4_c5.png"),
	preload("res://assets/user_assets_v3/trap_new_r4_c6.png"),
	preload("res://assets/user_assets_v3/trap_new_r4_c7.png"),
	preload("res://assets/user_assets_v3/trap_new_r4_c8.png"),
]
const FX_TEX_THUNDER: Texture2D = preload("res://assets/user_assets_v3/thunder_strike.png")
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
const DECOR_INSETS := {"crate": 6, "barrels": 8, "sandbags": 6, "rock": 10,
	"column": 10, "jpillar": 10, "jstatue": 8, "jtower": 10, "jcrate": 6, "jrock": 10,
	"sb_hut": 10, "sb_hut_pink": 10, "sb_hut_blue": 10, "sb_vent": 10,
	"sb_vent_orange": 10, "sb_shrine": 10, "sb_block": 10, "sb_hut_green": 10,
	"sb_crate": 10, "if_crate": 6, "if_barrel": 8, "if_sandbags": 6,
	"sf_tower": 12}
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
const SB_EXPLOSION_TEX: Texture2D = preload("res://assets/skybrawl/effects/effect_001.png")
const DUST_TEX: Texture2D = preload("res://assets/effects/dust.png")
const HIT_SPARK_SCENE: PackedScene = preload("res://addons/reeboo_fx2d/effects/hit_spark.tscn")
const EXPLOSION_SMALL_SCENE: PackedScene = preload("res://addons/reeboo_fx2d/effects/explosion_small.tscn")
const COIN_PICKUP_SCENE: PackedScene = preload("res://addons/reeboo_fx2d/effects/coin_pickup.tscn")
