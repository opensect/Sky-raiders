class_name PhysicsConfig
extends RefCounted

# PhysicsConfig (Phase 3B, GAP-68/70): the single source of truth for
# tuning values, diffed against PHYSICS_SPEC.md §24. Every value below
# records the audit's adopt / keep / decide verdict — do not change a
# number here without updating the comment that justifies it.
#
# Player movement (§24.A): max speed 350 ADOPTED (was 330); ground
# accel 2600 KEPT (spec 1800 would feel sluggish after 2600); air
# accel 1500 ADOPTED via the ground/air split (spec 900, air control
# 0.65 x 2600 = 1690 — 1500 is the tuned middle); ground friction is
# the linear DECEL 3400 KEPT (spec friction 1200 is a different model,
# not a number swap) PLUS exponential drag (GAP-03); gravity 1400
# IDENTICAL to spec; jump -660 KEPT (spec -550 gives apex ~108 px and
# breaks the 170 px platform gaps); max fall 1000 ADOPTED (was 950).
# Jetpack (§24.B): force 1900 KEPT (spec 1800, current is livelier);
# max rise 450 ADOPTED (was 430); fuel 405 (QA-132: was 100 — user
# asked +5 s; measured tank was 2.2 s, new tank is 9.0 s of thrust
# at drain 45/s); drain 45/s KEPT (spec 25/s = 4 s of thrust would
# change every map's vertical balance); refill 70/s ground / 35/s
# air KEPT-ish (spec 15/s = 6.7 s to refill is far too slow) with
# the new 0.6 s regen delay (GAP-05).
# QA-074 (v3.6 phase 3, §5 — user: jetpack speed excessively high):
# max rise 450 -> 320 (-29%, the top flying speed itself); thrust
# 1900 -> 1650 (net climb accel 500 -> 250 px/s^2, gravity still
# applies while thrusting); thrust now RAMPS (0.75 -> 1.0 over 0.35 s)
# instead of instant full force, so the climb spools up smoothly;
# air accel while jetpacking 1900 (was the plain air 1500) with NO
# reversal bonus (1.0x, was 1.2x) so direction changes in flight are
# smooth, not snappy. Drain 45/s KEPT on purpose: 2.2 s of thrust
# per tank already, and a slower drain would push the 4 s hold-up
# landing in the joystick test past its window and lengthen total
# flight — the speed complaint is fixed by cap + thrust + ramp, not
# by more airtime. Regen 70/35 -> 50/25 per s and delay 0.6 -> 0.5 s:
# a full tank now takes 2.0 s on the ground (was 1.4 s) and 4.0 s in
# the air (was 2.9 s), so fuel is a real budget instead of a refill
# you never notice. Release behaviour is unchanged (full gravity
# resumes, momentum kept, spec §5) — the shorter post-release rise
# comes from the lower cap; P25b proves the player is falling again
# 0.5 s after release. The 320 px/s cap still clears the 320 px
# map-reachability gaps (game.gd _ct_map_reachable) with fuel to spare.
# QA-132 (v3.12, user: jetpack +5 s): FUEL_MAX 100 -> 405, drain
# STILL 45/s — one tank is 405/45 = 9.0 s of continuous thrust, a
# full refill takes 8.1 s on the ground (405/50) and 16.2 s in the
# air (405/25). One tank climbs 9 x 320 = 2880 px: more than one
# 1800 px Skyfall level, far less than the 10800 px tower, so the
# climb still needs platforms/grapple/wall-jumps. The QA-074 note
# above about the 4 s hold-up window still applies — the joystick
# test seeds 90 fuel (2 s) for that step instead of a full tank.
# Player-to-player (§14): the spec's recommended default — bodies pass
# through each other, bullets/explosions still hit.

# QA-141 (v3.15): Mini Militia Classic physics port. Every number
# below that carries an MMC source was read from
# libcocos2dcpp.so (see BUGS.md QA-141 for the full table with
# function addresses). MMC is impulse-based (Chipmunk) while Frag
# Arena is velocity-based (CharacterBody2D) — the EFFECTIVE
# behaviour is ported, not the solver. Where MMC could not be
# extracted the old Frag Arena value is KEPT and listed in BUGS.md.
# Conflicts with earlier user requests: the jetpack tank is MMC's
# 4.76 s (FUEL_MAX 100, drain 21/s), superseding the v3.12 9 s tank
# (QA-132) — the user has now asked for MMC physics, so MMC wins.
# MAX_JET_RISE 320 -> 190 supersedes QA-074's cap the same way.
# Player movement (§24.A): MMC move target (320-20)xwwf = 300,
# sustained ~250 after the 0.598/s damping; wwf ~1.0 for all FA
# weapons. Gravity 300 (Cocos2d-x Y-up (0,-300) = 300 down here).
# Jump -220 (impulse 22.0 / mass 0.1). Max fall 600 (body clamp).
# Drag 0.6 = ln(1/0.55) applied to the FULL velocity vector, once
# per physics frame (MMC velocity function). Accel is MMC's
# headroom rate: 3.0x(300-v) normal, 1.5x(300-v) while thrusting
# (ACCEL consts 900 = 3.0x300 initial). No reversal bonus in MMC.
# Jetpack (§24.B): thrust 450, rise cap 190, gravity 50 while
# thrusting, drain 21/s x thrustFactor (0.5+0.5xup), no ramp.
# Fuel regen was NOT found in MMC — KEPT at 50/25, delay 0.5.
# Explosions (§10): MMC Explosion class — damage max(10, 100-0.8d)
# inside radius 125, knockback min(600, (100-0.8d)x10). Vertical
# multiplier 0.4 KEPT (not extracted). Barrels use the same class:
# radius 125, damage via the same formula.

# --- Movement (spec §2, §24.A) ---
# QA-141: MMC values (SLC::updateStep 0x8e4d5c; local 0x8e4604).
const SPEED_GROUND := 250.0
const SPEED_AIR := 250.0
const ACCEL_GROUND := 900.0 # MMC headroom initial: 3.0 x 300 (see player_movement.gd)
const ACCEL_AIR := 900.0 # same headroom model in the air (rate, not accel, differs)
const DECEL_GROUND := 3400.0 # retained as tuning reference only; drag is the real stopper
const DECEL_AIR := 900.0 # retained as tuning reference only
const REVERSAL_GROUND := 1.0 # QA-141: MMC has no reversal bonus (was 1.6)
const REVERSAL_AIR := 1.0 # QA-141: MMC has no reversal bonus (was 1.2)
const DRAG_GROUND := 0.6 # QA-141: MMC damping ln(1/0.55) = 0.598/s (was 8.0)
const DRAG_AIR := 0.6 # QA-141: same MMC damping in the air (was 1.2)
const GRAVITY := 300.0
const GRAVITY_THRUSTING := 50.0 # QA-141: MMC owner gravity while thrusting (0,-50)
const MAX_FALL := 600.0
const MMC_MOVE_BASE := 300.0 # QA-141: MMC move-speed base (320-20) x wwf; headroom = base - v_along
const JUMP_VELOCITY := -220.0
const JUMP_CUT := 0.45 # variable jump height: release while rising cuts vy (KEPT — MMC variable-jump not extracted)
const AIR_CONTROL := 0.65

# --- Jetpack (spec §5, §24.B) ---
# QA-141: MMC values (SLC::updateStep 0x8e4d5c). player.gd mirrors
# these consts for the hot path — change both files together.
const JET_ACCEL := 450.0
const MAX_JET_RISE := 190.0
const JET_AIR_ACCEL := 450.0 # MMC thrusting initial accel 1.5 x 300 (was 1900)
const FUEL_MAX := 100.0 # QA-141: MMC 100 fuel, ~4.76 s full thrust (was 405 / 9.0 s, QA-132)
const FUEL_DRAIN := 21.0 # QA-141: MMC 0.35 x thrustFactor x 60 = max 21/s (was 45)
const FUEL_REFILL_GROUND := 50.0 # KEPT — MMC fuel regen not found (could-not-extract #3)
const FUEL_REFILL_AIR := 25.0 # KEPT — MMC fuel regen not found
const FUEL_REGEN_DELAY := 0.5 # KEPT
const FUEL_LOW_WARN := 25.0

# --- Hit regions (spec §17.3) ---
# Arms fold into torso: a single capsule cannot distinguish arms, so
# the documented deviation is head 1.5 / torso 1.0 / legs 0.75.
const REGION_MULT := {"head": 1.5, "torso": 1.0, "legs": 0.75, "arms": 0.85}
# QA-071b: hit-region boundaries scale with the 1.20x player (was
# -14 / +12 for the 52-tall capsule; now -17 / +14 for the 62-tall
# capsule, so head/torso/legs keep the same proportions).
const HIT_HEAD_Y := -17.0 # QA-071b: rel_y < -17 (from player centre) = head (was -14, 62-tall capsule)
const HIT_LEGS_Y := 14.0 # QA-071b: rel_y > 14 = legs, else torso (was 12, 62-tall capsule)

# --- Damage falloff (spec §17.2) ---
const DAMAGE_FALLOFF_START := 400.0 # full damage inside this range
# QA-075: the default floor at max range; each weapon overrides it
# with its own "falloff_min" in weapons.gd (sniper keeps 0.9x at
# range, shotgun drops to 0.5x — a long-range weapon should not fade
# like a close-range one). Weapons without the field use this.
const DAMAGE_FALLOFF_MIN := 0.7 # at max weapon range

# --- Explosions (spec §10) ---
# QA-141: MMC Explosion::applyDamage 0x620168 — damage
# max(10, 100 - 0.8 x dist) inside radius 125; knockback
# min(600, (100 - 0.8 x dist) x 10) along the away-direction
# (impulse x m_inv 10, capped by the 600 max-speed clamp).
const EXPLOSION_RADIUS := 125.0 # MMC damage radius (Explosion::applyDamage 0x620168)
const EXPLOSION_DAMAGE_MAX := 100.0 # MMC centre damage
const EXPLOSION_DAMAGE_FALLOFF := 0.8 # MMC damage lost per px of distance
const EXPLOSION_DAMAGE_MIN := 10.0 # MMC damage floor
const EXPLOSION_KNOCKBACK_CAP := 600.0 # MMC knockback cap (600 max-speed clamp)
const EXPLOSION_VERTICAL_MULT := 0.4 # Ky: upward blast multiplier (KEPT — not extracted)
const MASS := 1.0 # player mass for dV = J/m

# --- Ice zone (spec §18.A prototype values) — no map uses
# ice in v3.7 (QA-095: the old ice map is deleted); the
# constants stay so is_on_ice / the physics check keep working ---
const ICE_FRICTION := 100.0
const ICE_ACCEL := 500.0
const ICE_MAX_SPEED := 350.0

# --- Bounce pads (spec §22.E) ---
const BOUNCE_VELOCITY := -750.0
const BOUNCE_COOLDOWN := 0.3

# --- Explosive barrels (spec §22.C) ---
# QA-141: MMC uses the same Explosion class for barrels — radius
# 125, damage via the Explosion formula above (centre 100, floor
# 10). BARREL_BLAST_DAMAGE is gone: the damage is computed from
# the distance, not passed in.
const BARREL_HEALTH := 100.0
const BARREL_BLAST_RADIUS := 125.0

# --- Grenades (spec §13) ---
# QA-141: MMC FRAGNADE::initBody 0x62f1b4 / local 0x62f330.
const GRENADE_DRAG := 0.01
const GRENADE_RESTITUTION := 0.1
const GRENADE_REST_SPEED := 40.0

# --- Firing while moving (spec §20.C) ---
const VELOCITY_INHERITANCE := 0.15

# --- Multiplayer sync (spec §21.F) ---
const SNAPSHOT_INTERVAL := 0.033 # 30 snapshots/s (was 0.05 = 20/s)
const INTERP_BUFFER := 0.1 # 100 ms interpolation buffer
# QA-146: MMC remote-player render (SoldierRemoteController::updateStep
# 0x8f3bf8, libcocos2dcpp.so). MMC has NO interpolation buffer: every
# frame the remote copy chases the NEWEST received position with
# factor = max(0.05, 0.3745 - 15.0 * dt) (.rodata doubles 0.05
# @0x1085010, 0.3745 @0x1086220; fmov 15.0) — ~0.125/frame at 60 fps,
# floor 0.05. The alt tween (TWEEN_METHOD != 0) lerps with
# t = min(1, extrapolationMultiplier * timer), extrapolationMultiplier
# = 4.0 (.data init), but TWEEN_METHOD defaults to 0 (.bss), so the
# max() formula is the live one. Dead reckoning is MMC's gap-filler
# (setRemotePositionWithDeadReckoning 0x8f5308 advances the copy on
# its velocity; setRemotePositionInterp 0x8f6340 is a no-op stub in
# this build). MMC's send rate could NOT be extracted
# (sendPositionData 0x71a16c has no internal throttle; the rate lives
# in a per-message timer table, ClientEntry::GetMessageTimer 0x82ef9c)
# — 30/s stays, per spec §21.F (20-30/s).
const REMOTE_SMOOTH_BASE := 0.3745 # MMC smoothing base (0x1086220)
const REMOTE_SMOOTH_RATE := 15.0 # MMC smoothing rate (fmov 15.0)
const REMOTE_SMOOTH_MIN := 0.05 # MMC smoothing floor (0x1085010)

# --- Player collision mode (spec §14, recommended default) ---
const PLAYER_COLLISION_ENABLED := false
const PLAYER_DAMAGE_COLLISION := true
const PLAYER_EXPLOSION_COLLISION := true

# --- Collision layers (spec §24.D, GAP-71) ---
# 1 world, 2 player, 3 enemy (unused, PvP only), 4 projectile,
# 5 destructible, 6 hazard, 7 pickup, 8 trigger.
const LAYER_WORLD := 1
const LAYER_PLAYER := 2
const LAYER_PROJECTILE := 4
const LAYER_PICKUP := 7
const LAYER_TRIGGER := 8
const MASK_WORLD_PLAYER := 3 # world(1) + player(2): bullet raycast mask
const MASK_PLAYER_ONLY := 2

# --- Camera (spec §19) ---
const CAMERA_SMOOTHING := 8.0
const CAMERA_DEAD_ZONE := Vector2(120, 80)
const CAMERA_LOOKAHEAD := 80.0

# --- Misc ---
const SPAWN_ENEMY_CLEARANCE := 150.0 # respawn never within this of a live enemy
const RESPAWN_RETRY_DELAY := 0.5
const STUCK_CHECK_INTERVAL := 1.0
