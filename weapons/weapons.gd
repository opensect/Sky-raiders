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
#   falloff_start (optional per-weapon start distance; defaults to
#   PhysicsConfig.DAMAGE_FALLOFF_START).
#
# weapon ids: 0 rifle, 1 smg, 2 shotgun, 3 sniper, 4 rocket, 5 pistol.
# The pistol is the starting sidearm (always owned, alongside the rifle).
#
# Phase 3B decisions (audit GAP-20/56, spec §20.C/§24.C): shotgun was
# 7 pellets with fixed [-15..15]° offsets (spec §9 wins over §20's 6);
# QA-141 supersedes that with the reference's SPAS-12: 6 pellets, each an
# independent LCG angle in ±10°. Rifle rate 0.13 -> 0.125 s (spec 8
# shots/s); QA-141 supersedes with the reference AK47 0.10 s. Pistol rate 0.22
# KEPT (spec 3/s would make the sidearm deliberate, not fast — keep
# the fast sidearm); QA-141 supersedes with the reference D.EAGLE 0.25 s.
# Rocket speed 700 -> 450 WITH gravity 500 and life 1.4 -> 2.5 s
# (slow + arcing reads "heavy"); QA-106 (v3.8) later set rocket
# gravity to 0, and QA-141 supersedes speed/life with the reference SMAW
# (1800 px/s inferred, life 0.7 s inferred).

const TABLE := {
	# QA-141 (v3.15): reference weapon stats, hardcoded
	# builder 0x9ed734 (extraction B §4). Rifle = AK47 (idx 7),
	# SMG = MP5 (idx 6), shotgun = SPAS-12 (idx 9), sniper = M93BA
	# (idx 10), rocket = SMAW (idx 11) + ROCKET projectile (idx 12,
	# damage 100), pistol = D.EAGLE (idx 3). Spread is in radians
	# here (accuracy degrees from the builder: rifle 4, smg 5,
	# shotgun 10, sniper 0, rocket 0, pistol 2). Life = range/speed.
	# Bullet speeds are the per-class overrides (B §6): AK47 1300,
	# MP5 1400, SPAS-12 1300, M93BA 10000, D.EAGLE 1300 (default),
	# SMAW 1 placeholder — rocket speed 1800 is INFERRED from the
	# 30.0/step in addRocket 0x806e5c at 60 Hz (B §8), NOT directly
	# measured; rocket life 0.7 s is an inference too (1800 x 0.7
	# ~ 1250 px reach) — see BUGS.md QA-141. Rocket blast radius
	# Rocket, grenade, and barrel splash use the shared 125 px radius
	# in PhysicsConfig.
	# Recoil, shake, knockback, flash, falloff_min, auto, gravity
	# KEPT — reference per-weapon recoil/knockback was not extracted.
	0: {"name": "Assault Rifle", "damage": 10, "rate": 0.10, "mag": 35, "reload": 2.0, "speed": 1300.0, "spread": 0.07, "pellets": 1, "explosive": false, "sound": "shoot", "recoil": 30.0, "shake": 0.08, "auto": true, "life": 0.62, "gravity": 0.0, "knockback": 60.0, "recoil_k": 0.06, "flash": 1.2, "flash_t": 0.05, "falloff_min": 0.7},
	# QA-104 (v3.8): SMG spread was 0.09 rad + recoil_k 0.04 — bullets
	# sprayed everywhere (user 2026-11-20). Spread 0.035, recoil_k
	# 0.015: tight in bursts, slight bloom on a full-mag hold.
	# QA-141: MP5 spread 0.087 rad (±5°), recoil_k kept 0.015.
	# Damage 7, rate 0.06, mag 45, auto unchanged.
	1: {"name": "SMG", "damage": 7, "rate": 0.06, "mag": 45, "reload": 1.75, "speed": 1400.0, "spread": 0.087, "pellets": 1, "explosive": false, "sound": "smg", "recoil": 15.0, "shake": 0.05, "auto": true, "life": 0.50, "gravity": 0.0, "knockback": 40.0, "recoil_k": 0.015, "flash": 1.1, "flash_t": 0.05, "falloff_min": 0.6},
	# QA-141: SPAS-12 — 6 pellets (was 7), 25 damage per pellet,
	# each pellet an INDEPENDENT LCG angle in ±10° (the fixed
	# [-15..15]° offset list is deleted — spec §9 superseded).
	2: {"name": "Shotgun", "damage": 25, "rate": 0.75, "mag": 4, "reload": 2.5, "speed": 1300.0, "spread": 0.175, "pellets": 6, "explosive": false, "sound": "shotgun", "recoil": 220.0, "shake": 0.35, "auto": false, "life": 0.25, "gravity": 0.0, "knockback": 180.0, "recoil_k": 0.20, "flash": 1.6, "flash_t": 0.08, "falloff_min": 0.5, "falloff_start": 100.0},
	# QA-141: M93BA — 75 damage, 10000 px/s (≈ hitscan), life 0.15.
	3: {"name": "Sniper", "damage": 75, "rate": 0.8, "mag": 3, "reload": 2.5, "speed": 10000.0, "spread": 0.0, "pellets": 1, "explosive": false, "sound": "sniper", "recoil": 180.0, "shake": 0.40, "auto": false, "life": 0.15, "gravity": 0.0, "knockback": 220.0, "recoil_k": 0.15, "flash": 1.8, "flash_t": 0.08, "falloff_min": 0.9},
	# QA-106 (v3.8): rocket flies STRAIGHT in the shooting direction
	# (user 2026-11-20) — gravity 500 -> 0, and no velocity
	# inheritance (a moving shooter would bend it off the aim ray).
	# QA-141: SMAW — damage 100 (ROCKET idx 12), rate 1.25, mag 3,
	# reload 4.0, speed 1800 (INFERRED from 30.0/step, B §8),
	# life 0.7 (inferred reach ~1250 px). Blast radius stays 120
	# (reference rocket blast radius not extracted); explosion DAMAGE
	# uses the reference formula (see player_health.gd).
	4: {"name": "Rocket Launcher", "damage": 100, "rate": 1.25, "mag": 3, "reload": 4.0, "speed": 1800.0, "spread": 0.0, "pellets": 1, "explosive": true, "sound": "rocket", "recoil": 260.0, "shake": 0.50, "auto": true, "life": 0.7, "gravity": 0.0, "knockback": 400.0, "recoil_k": 0.25, "flash": 2.0, "flash_t": 0.08, "falloff_min": 1.0},
	# QA-141: D.EAGLE — damage 8, rate 0.25, mag 15, reload 1.25,
	# speed 1300, spread 0.035 rad (±2°), life 0.38 (500/1300).
	5: {"name": "Pistol", "damage": 8, "rate": 0.25, "mag": 15, "reload": 1.25, "speed": 1300.0, "spread": 0.035, "pellets": 1, "explosive": false, "sound": "pistol", "recoil": 20.0, "shake": 0.05, "auto": false, "life": 0.38, "gravity": 0.0, "knockback": 40.0, "recoil_k": 0.03, "flash": 1.0, "flash_t": 0.05, "falloff_min": 0.65},
}

# QA-141: the fixed shotgun spread list is DELETED. reference gives each
# of the 6 SPAS-12 pellets an INDEPENDENT angle from the LCG
# (Weapon::getRandomFiringAngle 0x948878) in ±10° — see
# player_weapons.gd _fire(). The old SHOTGUN_SPREAD_DEG
# ([-15..15]°, spec §9) is superseded by the reference port.


static func get_weapon(id: int) -> Dictionary:
	return TABLE.get(clampi(id, 0, TABLE.size() - 1), TABLE[0])


static func is_valid(id: int) -> bool:
	return TABLE.has(id)
