class_name WeaponData
extends RefCounted

# WeaponController (data): the single source of truth for every weapon.
# Data-driven — no firing logic is hardcoded per weapon anywhere; the
# player reads rate / damage / mag / reload / speed / spread / pellets /
# explosive / sound / recoil / shake / auto / life from this table.
#
# Fields per weapon:
#   name, damage, rate (seconds between shots), mag (magazine size),
#   reload (seconds), speed (bullet px/s), spread (radians, per pellet),
#   pellets, explosive, sound, recoil (velocity kick, px/s),
#   shake (camera trauma 0..1), auto (hold-to-fire; false = one shot
#   per press), life (bullet lifetime in seconds = effective range),
#   gravity (px/s^2, 0 = straight; was 500 for the rocket until QA-106
#   in v3.8 made it fly straight — see the rocket row below),
#   knockback (victim velocity impulse, px/s, spec §17.5: pistol very
#   low, rifle low, shotgun medium, sniper medium/high, rocket high),
#   recoil_k (recoil accumulation per shot, spec §16 R_n = R_0 + n*K).
#   flash (muzzle-flash sprite scale, QA-075: heavy weapons flash
#   bigger), flash_t (muzzle-flash visible seconds, QA-075),
#   falloff_min (damage floor at max range, QA-075: per-weapon, the
#   sniper keeps 0.9x at range while the shotgun drops to 0.5x).
#
# weapon ids: 0 rifle, 1 smg, 2 shotgun, 3 sniper, 4 rocket, 5 pistol.
# The pistol is the starting sidearm (always owned, alongside the rifle).
#
# Phase 3B decisions (audit GAP-20/56, spec §20.C/§24.C): shotgun is
# 7 pellets with fixed [-15..15]° offsets (spec §9 wins over §20's 6);
# rifle rate 0.13 -> 0.125 s (spec 8 shots/s); pistol rate 0.22 KEPT
# (spec 3/s would make the sidearm deliberate, not fast — keep the
# fast sidearm); rocket speed 700 -> 450 WITH gravity 500 and life
# 1.4 -> 2.5 s (slow + arcing reads "heavy"; slow + straight would
# read broken; life rises so rockets still cross a map). QA-106
# (v3.8) later set rocket gravity to 0 — the user wants the rocket
# to fly straight in the shooting direction, no arc/drop.

const TABLE := {
	0: {"name": "Assault Rifle", "damage": 12, "rate": 0.125, "mag": 30, "reload": 1.2, "speed": 1100.0, "spread": 0.0, "pellets": 1, "explosive": false, "sound": "shoot", "recoil": 30.0, "shake": 0.08, "auto": true, "life": 1.2, "gravity": 0.0, "knockback": 60.0, "recoil_k": 0.06, "flash": 1.2, "flash_t": 0.05, "falloff_min": 0.7},
	# QA-104 (v3.8): SMG spread was 0.09 rad + recoil_k 0.04 — bullets
	# sprayed everywhere (user 2026-11-20). Spread 0.035, recoil_k
	# 0.015: tight in bursts, slight bloom on a full-mag hold.
	# Damage 8, rate 0.07, mag 32, auto unchanged.
	1: {"name": "SMG", "damage": 8, "rate": 0.07, "mag": 32, "reload": 1.0, "speed": 1000.0, "spread": 0.035, "pellets": 1, "explosive": false, "sound": "smg", "recoil": 15.0, "shake": 0.05, "auto": true, "life": 1.0, "gravity": 0.0, "knockback": 40.0, "recoil_k": 0.015, "flash": 1.1, "flash_t": 0.05, "falloff_min": 0.6},
	2: {"name": "Shotgun", "damage": 9, "rate": 0.8, "mag": 6, "reload": 1.8, "speed": 900.0, "spread": 0.16, "pellets": 7, "explosive": false, "sound": "shotgun", "recoil": 220.0, "shake": 0.35, "auto": false, "life": 0.55, "gravity": 0.0, "knockback": 180.0, "recoil_k": 0.20, "flash": 1.6, "flash_t": 0.08, "falloff_min": 0.5},
	3: {"name": "Sniper", "damage": 60, "rate": 0.9, "mag": 5, "reload": 1.6, "speed": 1600.0, "spread": 0.0, "pellets": 1, "explosive": false, "sound": "sniper", "recoil": 180.0, "shake": 0.40, "auto": false, "life": 1.6, "gravity": 0.0, "knockback": 220.0, "recoil_k": 0.15, "flash": 1.8, "flash_t": 0.08, "falloff_min": 0.9},
	# QA-106 (v3.8): rocket flies STRAIGHT in the shooting direction
	# (user 2026-11-20) — gravity 500 -> 0, and no velocity
	# inheritance (a moving shooter would bend it off the aim ray).
	# Damage 70, explosive, speed 450, life 2.5 unchanged.
	4: {"name": "Rocket Launcher", "damage": 70, "rate": 1.0, "mag": 4, "reload": 2.0, "speed": 450.0, "spread": 0.0, "pellets": 1, "explosive": true, "sound": "rocket", "recoil": 260.0, "shake": 0.50, "auto": true, "life": 2.5, "gravity": 0.0, "knockback": 400.0, "recoil_k": 0.25, "flash": 2.0, "flash_t": 0.08, "falloff_min": 1.0},
	5: {"name": "Pistol", "damage": 10, "rate": 0.22, "mag": 12, "reload": 1.0, "speed": 950.0, "spread": 0.02, "pellets": 1, "explosive": false, "sound": "pistol", "recoil": 20.0, "shake": 0.05, "auto": false, "life": 0.9, "gravity": 0.0, "knockback": 40.0, "recoil_k": 0.03, "flash": 1.0, "flash_t": 0.05, "falloff_min": 0.65},
}

# Fixed shotgun spread (spec §9): 7 pellets at [-15,-10,-5,0,5,10,15]°.
const SHOTGUN_SPREAD_DEG := [-15.0, -10.0, -5.0, 0.0, 5.0, 10.0, 15.0]


static func get_weapon(id: int) -> Dictionary:
	return TABLE.get(clampi(id, 0, TABLE.size() - 1), TABLE[0])


static func is_valid(id: int) -> bool:
	return TABLE.has(id)
