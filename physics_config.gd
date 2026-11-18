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
# max rise 450 ADOPTED (was 430); fuel 100 IDENTICAL; drain 45/s KEPT
# (spec 25/s = 4 s of thrust would change every map's vertical
# balance); refill 70/s ground / 35/s air KEPT-ish (spec 15/s = 6.7 s
# to refill is far too slow) with the new 0.6 s regen delay (GAP-05).
# Player-to-player (§14): the spec's recommended default — bodies pass
# through each other, bullets/explosions still hit.

# --- Movement (spec §2, §24.A) ---
const SPEED_GROUND := 350.0
const SPEED_AIR := 360.0
const ACCEL_GROUND := 2600.0
const ACCEL_AIR := 1500.0
const DECEL_GROUND := 3400.0
const DECEL_AIR := 900.0
const REVERSAL_GROUND := 1.6
const REVERSAL_AIR := 1.2
const DRAG_GROUND := 8.0
const DRAG_AIR := 1.2
const GRAVITY := 1400.0
const MAX_FALL := 1000.0
const JUMP_VELOCITY := -660.0
const JUMP_CUT := 0.45 # variable jump height: release while rising cuts vy
const AIR_CONTROL := 0.65

# --- Jetpack (spec §5, §24.B) ---
const JET_ACCEL := 1900.0
const MAX_JET_RISE := 450.0
const FUEL_MAX := 100.0
const FUEL_DRAIN := 45.0
const FUEL_REFILL_GROUND := 70.0
const FUEL_REFILL_AIR := 35.0
const FUEL_REGEN_DELAY := 0.6
const FUEL_LOW_WARN := 25.0

# --- Hit regions (spec §17.3) ---
# Arms fold into torso: a single capsule cannot distinguish arms, so
# the documented deviation is head 1.5 / torso 1.0 / legs 0.75.
const REGION_MULT := {"head": 1.5, "torso": 1.0, "legs": 0.75, "arms": 0.85}
const HIT_HEAD_Y := -14.0 # rel_y < -14 (from player centre) = head
const HIT_LEGS_Y := 12.0 # rel_y > 12 = legs, else torso

# --- Damage falloff (spec §17.2) ---
const DAMAGE_FALLOFF_START := 400.0 # full damage inside this range
const DAMAGE_FALLOFF_MIN := 0.7 # at max weapon range

# --- Explosions (spec §10) ---
const EXPLOSION_KNOCKBACK := 550.0 # J in J = K * (1-u)^2
const EXPLOSION_VERTICAL_MULT := 0.4 # Ky: upward blast multiplier
const MASS := 1.0 # player mass for dV = J/m

# --- Ice zone, Frozen Fortress only (spec §18.A prototype values) ---
const ICE_FRICTION := 100.0
const ICE_ACCEL := 500.0
const ICE_MAX_SPEED := 350.0

# --- Bounce pads (spec §22.E) ---
const BOUNCE_VELOCITY := -750.0
const BOUNCE_COOLDOWN := 0.3

# --- Explosive barrels (spec §22.C) ---
const BARREL_HEALTH := 100.0
const BARREL_BLAST_RADIUS := 170.0
const BARREL_BLAST_DAMAGE := 70.0

# --- Grenades (spec §13) ---
const GRENADE_DRAG := 0.15
const GRENADE_RESTITUTION := 0.45
const GRENADE_REST_SPEED := 40.0

# --- Firing while moving (spec §20.C) ---
const VELOCITY_INHERITANCE := 0.15

# --- Multiplayer sync (spec §21.F) ---
const SNAPSHOT_INTERVAL := 0.033 # 30 snapshots/s (was 0.05 = 20/s)
const INTERP_BUFFER := 0.1 # 100 ms interpolation buffer

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
