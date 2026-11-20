extends CharacterBody2D

# Animated soldier: analog run, jump, jetpack, full 360-degree aim.
# Each peer owns its own player (multiplayer authority); movement is
# replicated by unreliable RPC snapshots on the SAME channel bullets
# and grenades already use (QA-053) - the MultiplayerSynchronizer
# proved undeliverable on real ENet (see BUGS.md QA-053) and is gone.
# The soldier art has a rifle baked in; a separate weapon sprite is drawn
# at the hands and rotated to the exact aim angle so the weapon always
# points where the right stick points.

# QA-071b (v3.6 phase 2, §3): the player is 1.20x bigger - Mini
# Militia proportions, more visible in play. Old capsule radius 17 /
# height 52 (34x52, sprite 64 px); new radius 22 / height 68
# (40x62, sprite 77 px). PLAYER_SCALE is the single multiplier: the
# sprite, gun, jetpack flame, ring, name label and HP bar all scale
# from it, the capsule and every size-coupled offset in this file and
# in game.gd (spawn validation, stuck query, wedge rays, hit regions,
# test teleports) scale with the same numbers. Physics (speeds, jump,
# gravity, fuel) is UNCHANGED - only the visible/collision size grew,
# so movement, sync (RPC snapshots, QA-053/068) and the kill/death
# chain (QA-069) are untouched.
const PLAYER_SCALE := 1.20 # QA-071b: user correction 2026-11-19 ~19:13 - 'bigger' means MODESTLY bigger, not 1.30x
const CAPSULE_RADIUS := 20.0
const CAPSULE_HEIGHT := 62.0
const SPEED := 350.0
const ACCEL := 2600.0
const DECEL := 3400.0
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
const JUMP_VELOCITY := -660.0
# QA-074 (v3.6 phase 3, §5 - user: jetpack speed excessively high).
# Mirrors PhysicsConfig - change both files together. Old values:
# JET_ACCEL 1900, MAX_JET_RISE 450, FUEL_REFILL 70, FUEL_REFILL_AIR
# 35, FUEL_REGEN_DELAY 0.6 (spec §24.B says 1800/450/25/s/15/s; the
# shipped code had already drifted from the spec - see BUGS.md).
# New: top flying speed 450 -> 320 (-29%); thrust 1900 -> 1650 (net
# climb accel 500 -> 250 px/s^2, gravity still applies while
# thrusting); thrust RAMPS 0.75 -> 1.0 over 0.35 s instead of instant
# full force. Drain 45/s KEPT (2.2 s per tank; a slower drain would
# lengthen total flight and push the 4 s hold-up landing past its
# joystick-test window). Regen 70/35 -> 50/25 per s, delay 0.6 -> 0.5.
# QA-132 (v3.12, user: jetpack +5 s): FUEL_MAX 100 -> 405, drain
# STILL 45/s, so one tank is now 405/45 = 9.0 s of continuous
# thrust (was 2.2 s). A full tank climbs 9 x 320 = 2880 px — more
# than one 1800 px level but far less than the 10800 px tower, so
# the climb still needs platforms/grapple/wall-jumps with refill
# waits (full refill 8.1 s on the ground, 16.2 s in the air).
# The joystick hold-up test seeds 90 fuel (2 s) so its 4 s window
# still covers thrust-out + landing (see game.gd _jt_s_hold_up_long).
const JET_ACCEL := 1650.0
const MAX_JET_RISE := 320.0
const JET_RAMP_MIN := 0.75
const JET_RAMP_TIME := 0.35
const JET_AIR_ACCEL := 1900.0 # horizontal accel while jetpacking (air 1500)
const GRAVITY := 1400.0
const MAX_FALL := 1000.0
const FUEL_MAX := 405.0 # QA-132: was 100.0 (9.0 s of thrust at drain 45/s)
const FUEL_DRAIN := 45.0
const FUEL_REFILL := 50.0
const FUEL_REFILL_AIR := 25.0
const FUEL_REGEN_DELAY := 0.5
const MASS := 1.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
# AIM_DEAD_ZONE is kept only as documentation: the dead zone is applied
# ONCE, in joystick.gd (0.20, rescaled). player/game must not re-apply
# their own thresholds (GAP-09). See _read_input.
const AIM_DEAD_ZONE := 0.20
# v2.2: the JUMP button is gone - the left stick does jumping and the
# jetpack. Push the stick up past this to jump (grounded) / thrust (air).
const STICK_UP_THRESHOLD := 0.35
const STICK_DOWN_THRESHOLD := 0.5
const FAST_FALL_EXTRA := 1600.0
# QA FIX (v2.1): spawn protection - 2s of invulnerability after (re)spawning
# so a camper cannot kill a player the instant they appear.
const SPAWN_PROTECTION := 2.0

const BULLET_SCENE: PackedScene = preload("res://bullet.tscn")
const GRENADE_SCENE: PackedScene = preload("res://grenade.tscn")

# weapon: 0 rifle, 1 smg, 2 shotgun, 3 sniper, 4 rocket, 5 pistol.
# The full table (fire rate, damage, mag, reload, speed, spread,
# pellets, explosive, sound, recoil, shake, auto, life) lives in
# WeaponData (weapons.gd) - one data-driven table, no per-weapon
# firing logic anywhere. The pistol is the starting sidearm.
const WEAPONS := WeaponData.TABLE
const WEAPON_TEX := {
	0: preload("res://assets/weapons/rifle.png"),
	1: preload("res://assets/weapons/smg.png"),
	2: preload("res://assets/weapons/shotgun.png"),
	3: preload("res://assets/weapons/sniper.png"),
	4: preload("res://assets/weapons/rocket.png"),
	5: preload("res://assets/weapons/pistol.png"),
}
const HELMET_TEX := {
	1: preload("res://assets/headgear/helmet_green.png"),
	2: preload("res://assets/headgear/cap_tan.png"),
	3: preload("res://assets/headgear/helmet_black.png"),
	# QA-090 (v3.7): 4 red bandana, 5 night-vision goggles, 6 camo
	# helmet. Indices 1-3 are UNCHANGED - existing players' saved
	# helmet choices must not shift.
	4: preload("res://assets/headgear/bandana_red.png"),
	5: preload("res://assets/headgear/nvg.png"),
	6: preload("res://assets/headgear/helmet_camo.png"),
}
# QA-083 (v3.7): one muzzle-flash sprite per weapon class (was one
# shared muzzle.png for every gun). Rifle and SMG share the rifle
# flash; the flash texture follows the current weapon in
# _update_gun_texture. Scale / timing still come from the weapon
# table (flash / flash_t, QA-075) - only the picture changes.
const MUZZLE_TEX := {
	0: preload("res://assets/effects/muzzle_rifle.png"),
	1: preload("res://assets/effects/muzzle_rifle.png"),
	2: preload("res://assets/effects/muzzle_shotgun.png"),
	3: preload("res://assets/effects/muzzle_sniper.png"),
	4: preload("res://assets/effects/muzzle_rocket.png"),
	5: preload("res://assets/effects/muzzle_pistol.png"),
}
# QA-092 (v3.7): hit-flash shader from Sprite Juice Kit Lite
# (REEBOO Labs, MIT, v1.0) - blends the sprite toward solid red.
# Only the SHADER file is used, driven directly from
# _hit_flash_timer (no autoload, no per-hit tween). The kit's
# screen shake and hit-stop are NOT adopted: the game already has
# trauma-based shake (add_shake), and hit-stop (Engine.time_scale)
# would freeze the shared LAN sim for every peer.
const HIT_FLASH_SHADER: Shader = preload("res://addons/sprite_juice_lite/shaders/hit_flash.gdshader")
# QA-082 (v3.7): jetpack flame sprite (was a plain orange Polygon2D
# triangle). Drawn pointing DOWN from its top edge, 32x64 px, so
# with centered=false the sprite's top sits at the old triangle's
# top (y=22) and its length matches the old 29 px at scale 1.
const FLAME_TEX: Texture2D = preload("res://assets/effects/jetpack_flame.png")

const GUN_LENGTH := 55.0 # QA-071b: 46 * 1.20 - gun scales with the player

var peer_id: int = 0
var player_index: int = 1
var player_name: String = "Player"
var color_index: int = 0
var player_color: Color = Color(0.95, 0.3, 0.25)
var helmet: int = 0 # 0 none, 1 green helmet, 2 cap, 3 black helmet, 4 bandana, 5 night vision, 6 camo helmet (QA-090)
var team: int = -1 # -1 FFA, 0 red, 1 blue
var aim_angle: float = 0.0
var facing: int = 1
var health: int = 100
var kills: int = 0
var deaths: int = 0
var weapon: int = 0
var mag_ammo: int = 30
var grenades: int = 2
var alive: bool = true
var fuel: float = FUEL_MAX
var reloading: bool = false
var sync_position: Vector2 = Vector2.ZERO
var sync_velocity: Vector2 = Vector2.ZERO
# QA-053: sync_position / sync_velocity are now the LAST RECEIVED
# snapshot values (written by receive_move_snapshot, read by the
# remote interpolation path). Nothing writes them from local movement
# any more - the local branch sends snapshots instead (see
# _send_move_snapshot). They are kept (same names) so _interp_position
# and the repl-sim keep working unchanged.
var _move_snap_timer: float = 0.0
var _move_snap_seq: int = 0 # per-snapshot sequence (out-of-order guard)
var _last_snap_seq: int = -1 # newest snapshot sequence applied
var _last_snap_receipt: float = 0.0 # QA-068: receipt time of the newest snapshot (gap detection)
var _snap_resync: bool = false # QA-068: next render snaps (join / rejoin / long gap), set in receive_move_snapshot
# QA-073: adaptive interpolation delay. Fixed 100 ms (INTERP_BUFFER)
# is the STARTING delay; the receiver measures Wi-Fi delivery jitter
# (arrival spacing vs sender spacing) and moves the delay slowly
# toward a jitter-derived target, 80-250 ms, at most 10 ms per 0.5 s
# - clean Wi-Fi settles near 80 ms, bursty Wi-Fi grows the buffer
# instead of letting the copy freeze and jump. The slow slew is
# deliberate: a fast-moving delay would itself wobble the render
# timeline. _interp_position reads _interp_delay, never the const.
var _interp_delay: float = PhysicsConfig.INTERP_BUFFER
var _jitter_ewma: float = 0.0 # QA-073: EWMA of |arrival gap - sender gap| (seconds)
var _prev_snap_sender_t: float = -1.0
var _prev_snap_receipt_t: float = -1.0
var _interp_delay_next_adjust: float = 0.0
# QA-073: remote gameplay state synced in the snapshot (spec §1/§5).
# Jetpack/firing/reload/airborne were NOT in the QA-068 payload, so
# the receiver guessed jetpack from velocity + fuel and could never
# show a remote player firing. These are the real flags now.
var _remote_jetpacking: bool = false
var _remote_firing: bool = false
var _remote_reloading: bool = false
var _remote_airborne: bool = false
# QA-073: snapshot delivery counters (spec §7, net-stats display).
# Lost = sequence gap (a seq never arrived); duplicate = same seq
# twice; out-of-order = an older seq arriving after a newer one.
# The counters only move on real deliveries - a duplicate storm or
# a loss burst is visible in the stats instead of silent.
var _net_recv_count: int = 0
var _net_lost_count: int = 0
var _net_dup_count: int = 0
var _net_ooo_count: int = 0
var _net_ups: float = 0.0 # QA-073: snapshots received per second (1 s window)
var _net_ups_count: int = 0
var _net_ups_window_start: float = 0.0
var _net_extrap_s: float = 0.0 # QA-073: current extrapolation past the newest snapshot (s, 0 = interpolating)
# QA-073: the render clock (spec §2). The render time must NEVER
# run backwards: when the adaptive delay grows, render_t = newest -
# delay would otherwise retreat and the copy would step back and
# then surge forward (the first chaos run: 52 px snap-back,
# 1352 px/s). The clock is held instead - only the delay growth
# itself (tens of ms, ~10 px) is deferred. There is deliberately
# no upper slew: capping the advance by wall time starved the clock
# whenever physics ticks batched. Only a resync jumps the clock.
var _render_t_last: float = -INF
# player already moves without waiting for the network (owner
# simulation); this ring records what it predicted so a correction
# can be checked against it. Ring of the last 90 physics frames:
# positions + velocities, indexed by snapshot sequence.
var _pred_pos: PackedVector2Array = PackedVector2Array()
var _pred_vel: PackedVector2Array = PackedVector2Array()
var _pred_seq: PackedInt32Array = PackedInt32Array()
# QA-073: reconciliation target (spec §4). Set by
# apply_authoritative_correction; the local branch blends toward it
# a little per physics frame (small errors) instead of snapping.
var _reconcile_target: Vector2 = Vector2.INF
var _reconcile_active: bool = false
var _last_corr_seq: int = -1 # newest correction sequence applied (stale corrections ignored)

var _shots_fired: int = 0
var _shots_hit: int = 0 # Phase 4: distinct trigger pulls that hit a player (accuracy)
var shot_devs: Array = [] # QA-061 diagnostic: per-pellet bullet direction deviation from aim (radians), capped at 200; the fire test reads it for rifle straightness. Gameplay never reads it.
var _hit_shot_keys: Array = [] # shot indices already counted as hits (shot_no / 10)
# Phase 4 hitmarker state: the host tells the shooter about each hit
# (hit_confirm RPC); the game polls _hitmark_seq and shows the marker
# + a floating damage number. Only the local player's values are read.
var _hitmark_seq: int = 0
var _hitmark_dmg: int = 0
var _hitmark_pos: Vector2 = Vector2.ZERO
var _hitmark_lethal: bool = false
var _hitmark_time: float = 0.0
var _fire_cooldown: float = 0.0
var _reload_timer: float = 0.0
var _respawn_timer: float = 0.0
var _spawn_protect_timer: float = 0.0
var _grenade_cooldown: float = 0.0
var _hit_flash_timer: float = 0.0
var _hit_flash_mat: ShaderMaterial # QA-092: shared hit-flash material (body + gun + helmet)
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _fall_speed: float = 0.0
var _jetpacking: bool = false
# QA-074: thrust spool-up state. _jet_ramp_t counts seconds of
# continuous thrust; _jet_thrust_factor is the ramp (JET_RAMP_MIN ->
# 1.0 over JET_RAMP_TIME). Both reset the moment thrust stops, so
# every jetpack burst spools up again instead of resuming at full.
var _jet_ramp_t: float = 0.0
var _jet_thrust_factor: float = 0.0
# QA-075: muzzle-flash timer (replaces one scene-tree timer per shot
# in _show_muzzle) + flash counter the fire test reads; gun dip on
# weapon switch (visual only, never blocks firing); per-weapon
# magazine memory so switching weapons no longer refills the mag.
var _muzzle_timer: float = 0.0
var _muzzle_flashes: int = 0
var _switch_dip_timer: float = 0.0
var _mag_memory: Dictionary = {}
var _current_anim: String = ""
var _anim_locked: bool = false # death anim plays out

var _owned_extra: Array = []
var _gun_base_scale: float = 1.0

var _move_axis: float = 0.0
var _move_mag: float = 0.0
var _jump_held: bool = false
var _jump_pressed: bool = false
var _fast_fall: bool = false
var _stick_up_prev: bool = false
var _stick_up_armed: bool = true
var _aim_dir: Vector2 = Vector2.ZERO
var _want_fire: bool = false
var _fire_edge: bool = false # fresh FIRE press (semi-auto weapons only)
var _aiming: bool = false
var _shake_trauma: float = 0.0
var _gun_kick: float = 0.0
var _round_dead: bool = false # Survival: dead for this round, revived on round reset
# Death FSM (spec §17.6, GAP-44): ALIVE -> DYING (0.4 s anim) -> DEAD
# (respawn timer) -> RESPAWNING (validation) -> ALIVE.
enum LifeState { ALIVE, DYING, DEAD, RESPAWNING }
var life_state: int = LifeState.ALIVE
var _dying_timer: float = 0.0
var _respawn_retry_timer: float = 0.0
# Weapon state machine (spec §16, GAP-41): READY -> FIRING (one frame)
# -> READY; READY -> RELOADING -> READY. `reloading` stays for the HUD.
enum WeaponState { READY, FIRING, RELOADING }
var weapon_state: int = WeaponState.READY
var _reload_transfer: int = 0
# Reserve ammo (spec §16, GAP-39): magazine vs reserve. Pistol reserve
# is -1 = infinite (starting sidearm). Reload transfers from reserve.
var _reserve: Dictionary = {0: 90, 1: 96, 2: 18, 3: 10, 4: 8, 5: -1}
const RESERVE_DEFAULT := {0: 90, 1: 96, 2: 18, 3: 10, 4: 8, 5: -1}
var _recoil_accum: float = 0.0 # R_n = R_0 + n*K, decays when not firing
var _jump_cut_armed: bool = false # variable jump height (GAP-04)
var _fuel_delay_timer: float = 0.0 # fuel regen delay (GAP-05)
var _seen_damage_ids: Array = [] # unique damage event ids (GAP-43)
var _snapshots: Array = [] # remote interpolation buffer (GAP-16)
var _cam_anchor: Vector2 = Vector2.ZERO # camera dead-zone anchor (GAP-52)
var _cam_anchor_init: bool = false
var _cam_look: float = 0.0 # smoothed look-ahead (GAP-53)
var _stuck_check_timer: float = 0.0 # stuck-in-geometry recovery (GAP-72)
var _wedge_ref_pos: Vector2 = Vector2.INF # QA-063: wedged-between-obstacles recovery
var _wedge_still: float = 0.0 # seconds of move input with no movement
var _wedge_tried_left: bool = false
var _wedge_tried_right: bool = false
var _flame: Sprite2D # jetpack flame sprite, driven by real thrust state (GAP-06)

var _collision_shape: CollisionShape2D
var _sprite: AnimatedSprite2D
var _helmet_sprite: Sprite2D
var _gun: Sprite2D
var _muzzle: Sprite2D
var _ring: Polygon2D
var _name_label: Label
var _hp_bg: ColorRect
var _hp_fg: ColorRect
var _audio # GameAudio node (set by game)
var _camera: Camera2D # kept so respawn can reset smoothing (see below)
# QA-105 (v3.8): scopes + sniper line of sight. Sniper zooms 2.0x,
# rifle 1.5x; SMG / shotgun / pistol / rocket have no scope. The
# sight line is the sniper bullet's true range (1600 px/s * 1.6 s).
const SCOPE_ZOOM_SNIPER := 2.0
const SCOPE_ZOOM_RIFLE := 1.5
const SIGHT_LINE_RANGE := 2560.0
var scoped: bool = false # scope toggle (HUD SCOPE button, sniper/rifle only)
var _sight_line: Line2D # sniper sight line (local player only)

# QA-119 (v3.11 power-up set, REPLACE - user 2026-11-20 ~20:51):
# 7 kinds, 7-13. 7 Health Potion, 8 Shield, 9 Speed Boost,
# 10 Jetpack Boost, 11 Wind Blast, 12 Thunder Strike,
# 13 Invisibility. Old Ammo Crate (10), Grenade Pack (11),
# Jetpack Boost (12) and Radar (13) are GONE - Radar is removed
# entirely, Double Damage was never implemented (user replaced it
# with Jetpack Boost, 2026-11-20 ~20:52).
# NO AUTO-ACTIVATION (user rule, 2026-11-20 ~21:00, IMMEDIATE):
# every picked-up power-up goes into one of the 3 slot buttons
# and WAITS - it does nothing until the player taps its slot.
# Timed kinds (8, 9, 10, 13): ONE active at a time; tapping a
# timed slot while a boost is active does nothing. Instant kinds
# (7 health, 11 wind, 12 thunder) fire at once on tap, even while
# a timed boost is active. A carrier CANNOT activate a timed
# boost while carrying the flag (the carrier rule wins) - instant
# kinds are still allowed for carriers. Same kind twice, or full
# slots, consumes the pickup with no effect.
# carrying_flag is set by game.gd (Vertical CTF): 0 none, 1 RED
# flag, 2 BLUE flag. wind_force is set by game.gd every frame on
# Skyfall wind zones (Vector2.ZERO on every other map).
const SHIELD_DURATION := 7.0 # QA-119: was 6.0 (user 2026-11-20 ~20:48)
const SPEED_DURATION := 8.0 # QA-132: was 7.0 (speed is now x1.5, see below)
const JETPACK_BOOST_DURATION := 15.0 # QA-119: was 7.0 (user 2026-11-20 ~20:48)
const INVISIBILITY_DURATION := 10.0 # QA-119: user corrected 4 -> 10 s (2026-11-20 ~20:49)
const INVISIBILITY_ALPHA := 0.1 # QA-119: 90% invisible - enemies see ~10% (user 2026-11-20 ~20:52)
const SPEED_BOOST_MULT := 1.5 # QA-132: was 1.3 — barely noticeable
const JETPACK_BOOST_MULT := 1.4
const FLAG_CARRY_SPEED_MULT := 0.85
const MAX_STORED_BOOSTS := 3
const TIMED_BOOST_KINDS: Array[int] = [8, 9, 10, 13] # shield, speed, jetpack, invisibility
const PU_NAMES := {7: "Health Potion", 8: "Shield", 9: "Speed Boost", 10: "Jetpack Boost", 11: "Wind Blast", 12: "Thunder Strike", 13: "Invisibility"} # QA-132: feed messages
const WIND_BLAST_RADIUS := 520.0 # QA-132: was 320.0 — on a 10800 px tower enemies are usually >320 px away, so it fired at nothing
const WIND_BLAST_KNOCKBACK := 650.0
const THUNDER_RADIUS := 300.0 # QA-132: was 220.0 — same reason as wind
const THUNDER_DAMAGE := 40
const THUNDER_RANGE := 800.0 # QA-132: was 500.0 — strike the nearest enemy inside this range, else own feet
const HEALTH_REGEN_DELAY := 3.0 # QA-120: health restores slowly after 3 s without damage
const HEALTH_REGEN_RATE := 4.0 # HP per second (slow)
var shield_timer: float = 0.0
var speed_timer: float = 0.0
var invisibility_timer: float = 0.0
var jetpack_boost_timer: float = 0.0
var active_boost_kind: int = 0 # 0 none, else 8/9/10/13
var stored_boosts: Array[int] = [] # power-ups waiting in the 3 slot buttons, distinct kinds only
var carrying_flag: int = 0 # 0 none, 1 carrying the RED flag, 2 carrying the BLUE flag
var wind_force: Vector2 = Vector2.ZERO
var _shield_ring: Polygon2D # blue ring, shown while the shield is up
var _regen_timer: float = 0.0 # QA-120: counts down after taking damage; regen starts at 0
var _fx_shield: Sprite2D # QA-119: power-up effect layers (assets/powerups_effects/)
var _fx_speed: Sprite2D
var _fx_health: Sprite2D
var _fx_wind: Sprite2D
var _fx_thunder: Sprite2D
var _fx_invis: Sprite2D
var _fx_flash_kind: int = 0 # instant-effect flash (health/wind/thunder), 0 = none
var _fx_flash_timer: float = 0.0

# QA-112 (v3.9 Skyfall ladders): the 4 emergency ladders are
# climbable recovery routes after a fall. The game scene answers
# skyfall_ladder_at (added in game.gd); until it exists - or on
# any other map - has_method is false and this is a complete no-op.
const LADDER_CLIMB_SPEED := 200.0
var _on_ladder: bool = false
var _ladder_rect: Rect2 = Rect2()
var _ladder_armed: bool = true # re-grab only after the stick is released (see _update_ladder)
var _move_stick_y: float = 0.0 # move stick vertical, kept from _read_input for the ladder

# QA-112 (v3.9 Skyfall movement): grapple points, wall-jumps and
# jetpack lines - climbing is a SKILL, not just a route. All three
# are Skyfall-only and read their data from the game scene's
# MAPS[5] (see _skyfall_grapple_points / _skyfall_jetpack_lines);
# on any other map, or if the keys are missing, every helper
# returns empty / false and this is a complete no-op. Grapple and
# wall-jump use no fuel; the jetpack line halves fuel drain and
# shields the rider from the wind.
const GRAPPLE_RANGE := 320.0
const GRAPPLE_PULL_SPEED := 500.0
const GRAPPLE_RELEASE_DIST := 60.0
const GRAPPLE_RELEASE_BOOST := 200.0
const GRAPPLE_COOLDOWN := 1.0
const WALL_JUMP_PUSH := 380.0
const WALL_JUMP_UP := 520.0
const WALL_JUMP_MAX_CHAIN := 2
const WALL_DETECT_DIST := 24.0
const JETPACK_LINE_DIST := 70.0
var _grappling: bool = false
var _grapple_point: Vector2 = Vector2.ZERO
var _grapple_cooldown: float = 0.0
var _wall_jumps_used: int = 0
var _on_jetpack_line: bool = false
var _sf_grapple_cache: Array = []
var _sf_grapple_cache_map: int = -1
var _sf_lines_cache: Array = []
var _sf_lines_cache_map: int = -1


func _enter_tree() -> void:
	if name.is_valid_int():
		set_multiplayer_authority(int(String(name)))


func _ready() -> void:
	add_to_group("players")
	_reset_mag_memory() # QA-075: every weapon starts with a full mag remembered
	_build_collision()
	_build_sprite()
	var game = get_tree().get_first_node_in_group("game")
	if game != null:
		position = game.get_valid_spawn_point(player_index, peer_id)
		_audio = game.audio
	sync_position = position
	if is_local_player():
		var cam := Camera2D.new()
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 8.0 # spec §19 suggests ~8.0
		add_child(cam)
		# QA FIX (v2.1): keep the reference. Programmatically created nodes
		# get auto-names like "@Camera2D@141", so get_node("Camera2D") in
		# _respawn() could never find it and reset_smoothing() never ran.
		_camera = cam
		var game2 = get_tree().get_first_node_in_group("game")
		if game2 != null:
			var ms: Vector2 = game2.map_size
			cam.limit_left = 0
			cam.limit_top = 0
			cam.limit_right = int(ms.x)
			cam.limit_bottom = int(ms.y)
		# Deferred so the camera is fully inside the tree when it activates.
		cam.call_deferred("make_current")
		cam.call_deferred("reset_smoothing")
		# QA-105: the sniper sight line - a thin line from the muzzle
		# along the aim direction, green while the path is clear to
		# full sniper range, red where a wall blocks it. Local
		# player only; _update_sight_line drives it every frame.
		_sight_line = Line2D.new()
		_sight_line.width = 3.0
		_sight_line.visible = false
		_sight_line.z_index = 5
		add_child(_sight_line)
	_spawn_protect_timer = SPAWN_PROTECTION
	_play_anim("idle")
	# QA-112 (v3.9): --movement-test runs the in-process movement
	# checks at the bottom of this file (local player only, flag
	# gated - never runs in a real match).
	_movetest_active = "--movement-test" in OS.get_cmdline_user_args() and is_local_player()


func is_local_player() -> bool:
	return get_multiplayer_authority() == multiplayer.get_unique_id()


# QA-119: true when this player is on the LOCAL player's team.
# Only in team modes (team 0/1) - in FFA (team -1) nobody is a
# teammate, so everyone is an enemy for the invisibility rule.
func _is_same_team_as_local() -> bool:
	if team < 0:
		return false
	var game := get_tree().get_first_node_in_group("game")
	if game == null or not game.has_method("_get_local_player"):
		return false
	var lp = game._get_local_player()
	if lp == null or lp == self:
		return false
	return int(lp.team) == team


func _build_collision() -> void:
	_collision_shape = CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = CAPSULE_RADIUS # QA-071b: 17 -> 20 (1.20x)
	cap.height = CAPSULE_HEIGHT # QA-071b: 52 -> 62 (1.20x)
	_collision_shape.shape = cap
	add_child(_collision_shape)
	floor_snap_length = 4.0


# QA-119: one power-up effect layer. The image is 512x512; scale
# shrinks it to ~150 px on the player. Hidden until its power-up
# is active. A missing file (pack not imported) must not crash the
# game - load() returns null and the sprite simply stays empty.
func _make_fx_sprite(path: String, scale: float) -> Sprite2D:
	var sp := Sprite2D.new()
	sp.texture = load(path)
	sp.scale = Vector2(scale, scale)
	sp.z_index = 4
	sp.visible = false
	add_child(sp)
	return sp


func _build_sprite() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = _make_sprite_frames()
	_sprite.centered = true
	# QA-071b: the soldier art scales 1.20x (64 px frame -> 77 px on
	# screen). _update_visuals keeps this scale and only flips x for
	# facing. The helmet is a child of the sprite, so it scales too.
	_sprite.scale = Vector2(PLAYER_SCALE, PLAYER_SCALE)
	add_child(_sprite)

	_helmet_sprite = Sprite2D.new()
	_helmet_sprite.name = "Helmet"
	_helmet_sprite.position = Vector2(0, -26)
	_helmet_sprite.z_index = 2
	_sprite.add_child(_helmet_sprite)
	_update_helmet()

	# Team / player colour ring under the feet (QA-071b: 24 -> 29 px
	# radii, y 26 -> 31, wobble 7 -> 8).
	_ring = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * 29.0, 31.0 + sin(a) * 8.0))
	_ring.polygon = pts
	_ring.color = Color(player_color.r, player_color.g, player_color.b, 0.55)
	_ring.z_index = -1
	add_child(_ring)

	# QA-112: blue shield ring, shown while the shield boost is up.
	# A Polygon2D circle outline (outer 50 px, inner 45 px), drawn
	# as one ring band; _update_visuals toggles it. No flag sprite
	# here - game.gd draws the carried flag above the carrier, so a
	# second flag from this file would show two flags.
	_shield_ring = Polygon2D.new()
	_shield_ring.name = "ShieldRing"
	var shield_pts := PackedVector2Array()
	for i in 32:
		var a := TAU * float(i) / 32.0
		shield_pts.append(Vector2(cos(a) * 50.0, sin(a) * 50.0))
		shield_pts.append(Vector2(cos(a) * 45.0, sin(a) * 45.0))
	_shield_ring.polygon = shield_pts
	_shield_ring.color = Color(0.3, 0.6, 1.0, 0.7)
	_shield_ring.z_index = 2
	_shield_ring.visible = false
	add_child(_shield_ring)
	# QA-119 (v3.11): active power-up effect layers - the 512x512
	# effect images from assets/powerups_effects/, layered on the
	# player while the power-up is active (animated in-engine:
	# rotation / pulse / fade in _update_visuals). Jetpack Boost has
	# NO effect image in the pack - it keeps the jetpack flame.
	# The wind whirlpool is a flat solid disc, so it is drawn small
	# and faded and spins fast; if it ever looks wrong in-game it is
	# replaced by the code-drawn wind effect.
	_fx_shield = _make_fx_sprite("res://assets/powerups_effects/01_shield_energy_dome_effect.png", 0.30)
	_fx_speed = _make_fx_sprite("res://assets/powerups_effects/02_speed_boost_motion_trails_effect.png", 0.26)
	_fx_health = _make_fx_sprite("res://assets/powerups_effects/03_health_healing_aura_effect.png", 0.28)
	_fx_wind = _make_fx_sprite("res://assets/powerups_effects/05_wind_whirlpool_vortex_effect.png", 0.34)
	_fx_thunder = _make_fx_sprite("res://assets/powerups_effects/06_thunder_strike_lightning_impact_effect.png", 0.36)
	_fx_invis = _make_fx_sprite("res://assets/powerups_effects/07_invisibility_shimmer_cloak_effect.png", 0.30)

	# Rotated weapon sprite at the hands (pivot = stock).
	_gun = Sprite2D.new()
	_gun.name = "Gun"
	_gun.position = Vector2(10, 6) # QA-071b: (8, 5) * 1.20
	_gun.z_index = 3
	add_child(_gun)

	# QA-082: the flame is a drawn sprite now (was a plain orange
	# triangle). Same position / visibility / thrust behaviour as
	# before: top of the flame at the old triangle's top (y=22),
	# length 29 px at scale 1 (sprite is 32x64, so base scale is
	# 14/32 wide, 29/64 long); centered=false so the sprite grows
	# DOWN from y=22 exactly like the triangle did.
	_flame = Sprite2D.new()
	_flame.name = "JetFlame"
	_flame.texture = FLAME_TEX
	_flame.centered = false
	_flame.position = Vector2(-7, 22) # QA-071b: (0, 18) * 1.20, x centred on the 14 px wide flame
	_flame.scale = Vector2(14.0 / 32.0, 29.0 / 64.0)
	_flame.z_index = 1
	_flame.visible = false
	add_child(_flame)

	_muzzle = Sprite2D.new()
	_muzzle.name = "Muzzle"
	_muzzle.texture = MUZZLE_TEX[weapon]
	_muzzle.visible = false
	_muzzle.z_index = 4
	_gun.add_child(_muzzle)
	_update_gun_texture()

	# QA-071: the name label was already shown above every player
	# (this file, since v2) - it is now bigger and easier to read at
	# the new size: font 18 -> 22, 80 px wide -> 110, y -66 -> -88
	# (above the taller head + HP bar). _update_visuals refreshes
	# the text/colour live, so a name or colour set after _ready
	# (remote joins) still shows correctly.
	_name_label = Label.new()
	_name_label.text = player_name
	_name_label.position = Vector2(-48, -79) # QA-071b: (-40, -66) * 1.20
	_name_label.size = Vector2(96, 26) # QA-071b: (80, 22) * 1.20
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 22)
	_name_label.add_theme_color_override("font_color", player_color)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("outline_size", 5)
	add_child(_name_label)

	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.6)
	_hp_bg.position = Vector2(-26, -58)
	_hp_bg.size = Vector2(53, 7)
	add_child(_hp_bg)

	_hp_fg = ColorRect.new()
	_hp_fg.color = Color(0.3, 0.9, 0.3)
	_hp_fg.position = Vector2(-26, -58)
	_hp_fg.size = Vector2(53, 7)
	add_child(_hp_fg)

	# QA-092: one shared hit-flash shader material for the body, the
	# gun and the helmet - one flash_amount drives all three, so the
	# whole player flashes red together (QA-086). Spawn-protection
	# blink still uses modulate, which composes with the shader.
	_hit_flash_mat = ShaderMaterial.new()
	_hit_flash_mat.shader = HIT_FLASH_SHADER
	_hit_flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.15, 0.15, 1.0))
	_hit_flash_mat.set_shader_parameter("flash_amount", 0.0)
	_sprite.material = _hit_flash_mat
	_gun.material = _hit_flash_mat
	_helmet_sprite.material = _hit_flash_mat


func _make_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	var anims := {
		# QA-071: run / jump / jetpack play a little faster (10 -> 12
		# fps) so the bigger, more visible character moves smoothly
		# instead of visibly stepping frame-to-frame. Speeds are
		# unchanged; only the animation rate moves.
		"idle": ["idle", 11, 7.0, true],
		"run": ["run", 11, 12.0, true],
		"jump": ["jump", 11, 12.0, true],
		"fall": ["fall", 11, 8.0, true],
		"shoot": ["shoot", 11, 12.0, true],
		"aim": ["aim", 11, 6.0, true],
		"jetpack": ["jetpack", 11, 12.0, true],
		"die": ["die", 5, 7.0, false],
	}
	for key in anims.keys():
		var spec: Array = anims[key]
		var base: String = spec[0]
		var count: int = spec[1]
		var fps: float = spec[2]
		var loop: bool = spec[3]
		sf.add_animation(key)
		sf.set_animation_speed(key, fps)
		sf.set_animation_loop(key, loop)
		for i in count:
			var tex: Texture2D = load("res://assets/characters/soldier_%s_%02d.png" % [base, i])
			sf.add_frame(key, tex)
	return sf


# QA-094: per-animation helmet height. The helmet rides the body
# sprite at a fixed offset, but the art frames do not share one
# head height (measured hair-top, 64px frame: idle 8, run 10,
# jump 7, shoot 10, aim 10, fall 14, jetpack 25, die 36). Without
# this the helmet floats ~20px above the head while jetpacking.
# Helmet centre = hair_top - 33 in sprite-local units.
const HELMET_Y_BY_ANIM := {"idle": -25.0, "run": -23.0, "jump": -25.0, "shoot": -23.0, "aim": -23.0, "fall": -19.0, "jetpack": -8.0, "die": 3.0}
# QA-094: per-frame helmet centre (sprite-local) for the jetpack
# animation - the flying pose sways the head side-to-side (face
# centre x 21..47 across frames 00..10), so a fixed offset floats
# off the head at the extremes. Measured from the art (helmet
# centre = face centre, y = face top - 13); verified by overlaying
# the helmet on all 11 frames. The negative parent scale mirrors
# these automatically when the player faces left.
const HELMET_JETPACK_FRAMES := [Vector2(-11, -22), Vector2(0, -9), Vector2(3, -7), Vector2(1, -6), Vector2(-3, -9), Vector2(-1, -9), Vector2(11, -10), Vector2(9, -11), Vector2(2, -11), Vector2(13, -11), Vector2(15, -9)]
var _helmet_y: float = -25.0 # QA-094: current per-animation helmet height

# QA-127 (v3.11): hand anchors - where the TRIGGER hand grips the
# rifle, measured from the art (64px frames, frame coords - (32, 32);
# facing right). Values are in FRAME units; _hand_anchor() scales
# them by PLAYER_SCALE because the gun is a sibling of the scaled
# sprite, not a child of it (the helmet rides the sprite, the gun
# does not). The gun's GRIP sits on the anchor and the gun rotates
# to the aim angle around it, so the weapon reads as HELD instead
# of floating (the old fixed anchor (10, 6) sat on the FRONT hand,
# ~10 px ahead of the trigger hand). Idle lowers the gun to the hip
# in frames 04-10 (at ease, hands at the sides); jetpack sways, so
# it has a per-frame table like the helmet. Verified by overlaying
# the gun on the frames - see BUGS.md QA-127.
const HAND_ANCHOR_BY_ANIM := {"idle": Vector2(-2, 10), "run": Vector2(0, 8), "jump": Vector2(3, 6), "shoot": Vector2(3, 7), "aim": Vector2(3, 7), "fall": Vector2(2, 6), "die": Vector2(0, 8)}
const HAND_IDLE_FRAMES := [Vector2(-2, 10), Vector2(-2, 10), Vector2(-2, 10), Vector2(-4, 12), Vector2(-6, 14), Vector2(-6, 14), Vector2(-6, 14), Vector2(-6, 14), Vector2(-6, 14), Vector2(-6, 14), Vector2(-6, 14)]
const HAND_JETPACK_FRAMES := [Vector2(2, 8), Vector2(-2, 12), Vector2(-4, 10), Vector2(-2, 10), Vector2(2, 8), Vector2(4, 8), Vector2(2, 10), Vector2(4, 10), Vector2(4, 10), Vector2(4, 10), Vector2(2, 10)]
# QA-127: per-weapon grip - (x fraction along the weapon texture
# where the trigger hand sits, y px below the barrel line in game
# units). Measured from assets/weapons/*.png (trigger grip, not the
# magazine - the magazine hangs lower but the hand holds the grip).
const WEAPON_GRIP := {0: Vector2(0.34, 1.5), 1: Vector2(0.37, 2.0), 2: Vector2(0.23, 2.0), 3: Vector2(0.43, 3.0), 4: Vector2(0.47, 3.5), 5: Vector2(0.47, 5.0)}


# QA-127: the hand anchor in PLAYER units (frame units x PLAYER_SCALE),
# facing right. The gun grip sits here; the muzzle and bullet spawn
# use it too (see _muzzle_origin).
func _hand_anchor() -> Vector2:
	if _current_anim == "jetpack":
		var f := clampi(_sprite.frame, 0, HAND_JETPACK_FRAMES.size() - 1)
		return HAND_JETPACK_FRAMES[f] * PLAYER_SCALE
	if _current_anim == "idle":
		var fi := clampi(_sprite.frame, 0, HAND_IDLE_FRAMES.size() - 1)
		return HAND_IDLE_FRAMES[fi] * PLAYER_SCALE
	return HAND_ANCHOR_BY_ANIM.get(_current_anim, Vector2(0, 8)) * PLAYER_SCALE


# QA-127: the hands in the player's local space (mirrored when
# facing left). Bullets and the sight line leave from here.
func _muzzle_origin() -> Vector2:
	var hand := _hand_anchor()
	return Vector2(hand.x * facing, hand.y)

func _update_helmet() -> void:
	if _helmet_sprite == null:
		return
	if helmet <= 0 or not HELMET_TEX.has(helmet):
		_helmet_sprite.texture = null
		return
	var tex: Texture2D = HELMET_TEX[helmet]
	_helmet_sprite.texture = tex
	# Head is ~20px wide in the 64px frame; scale helmet to fit.
	var target_w := 26.0
	_helmet_sprite.scale = Vector2(target_w / tex.get_width(), target_w / tex.get_width())
	_helmet_sprite.position = Vector2(1, _helmet_y) # QA-094: was a fixed -25


func _update_gun_texture() -> void:
	if _gun == null:
		return
	var tex: Texture2D = WEAPON_TEX[weapon]
	_gun.texture = tex
	_gun_base_scale = GUN_LENGTH / tex.get_width()
	_gun.scale = Vector2(_gun_base_scale, _gun_base_scale)
	# Muzzle flash sits at the barrel tip in the gun's local space.
	# QA-108: was tex.get_width() - the gun sprite is CENTRED on the
	# node and scaled so its full width is GUN_LENGTH, so the barrel
	# tip is at half the texture width (27.5 px ahead after scaling),
	# not the far edge (55 px). The flash used to float 27.5 px past
	# the barrel in mid-air.
	if _muzzle != null:
		_muzzle.position = Vector2(tex.get_width() * 0.5, 0)
		# QA-083: the flash picture follows the weapon class.
		_muzzle.texture = MUZZLE_TEX[weapon]


# QA-053 - movement / state replication over the PROVEN RPC channel.
# v3.3's MultiplayerSynchronizer is deleted: on real phones it delivered
# nothing (its packets are addressed by the synchronizer's node path,
# and a synchronizer created in _ready() gets an auto-uniquified name
# like "@MultiplayerSynchronizer@1335" that differs on every peer, so
# the remote peer has no node at the packet's path and drops it - the
# sim could never catch this because it hand-assigned sync_position
# directly, bypassing the wire entirely). RPCs, by contrast, are
# addressed by the PLAYER node's path (Players/<pid>), which is
# identical on every peer - the same reason spawn_bullet /
# spawn_grenade / spawn_player_remote all arrive on real phones.
#
# _send_move_snapshot runs on the OWNER only, at the spec's snapshot
# rate (PhysicsConfig.SNAPSHOT_INTERVAL = 0.033 s, 30/s, spec §21.F),
# and carries position + velocity + aim + facing + the visible state
# the synchronizer used to carry (weapon, health, kills, deaths,
# alive, fuel, life state, ammo, grenades, accuracy counters) - damage
# RPCs (take_hit / take_damage) go only to the victim's owning peer,
# and weapon switches / reloads are local-only writes, so without this
# payload the remote copies would show stale health, kills, weapons
# and ammo too. Combat stays host-authoritative: snapshots only RELAY
# values the host already decided via its RPCs; nothing here lets a
# client award itself damage, kills or pickups.
# One owner for the remote player's visible position: the snapshot
# buffer, consumed by the remote branch's _interp_position. No second
# channel touches position any more.
func _send_move_snapshot(force: bool = false) -> void:
	if not is_local_player():
		return
	# Offline harnesses have no peers to send to (and rpc() with no
	# peer would only spam the log at 30/s); the repl-sim calls
	# receive_move_snapshot directly instead. A host with nobody
	# connected yet has nobody to send to either.
	if not multiplayer.has_multiplayer_peer():
		return
	if multiplayer.get_peers().is_empty():
		return
	_move_snap_seq += 1
	# QA-068: the snapshot carries the SENDER's clock ("st") and the
	# spawn-protection flag ("prot"). The receiver must interpolate
	# on the sender's timeline, not on arrival times (see
	# receive_move_snapshot): Wi-Fi arrival jitter otherwise becomes
	# spacing jitter in the buffer. "prot" lets the host's copy know
	# a remote victim is spawn-protected, so a lethal-looking hit
	# during protection is never credited as a kill (QA-069).
	rpc("receive_move_snapshot", {
		"seq": _move_snap_seq, "st": Time.get_ticks_msec() / 1000.0,
		"prot": 1 if _spawn_protect_timer > 0.0 else 0,
		"id": peer_id, # QA-073: player ID in every packet (spec §1) - was only implied by sender/node path
		"jet": 1 if _jetpacking else 0, "fire": 1 if _want_fire else 0, # QA-073: jetpack + firing state (spec §5)
		"rel": 1 if reloading else 0, "air": 1 if not is_on_floor() else 0, # QA-073: reload + airborne state (spec §5)
		"p": position, "v": velocity,
		"aim": aim_angle, "face": facing, "wpn": weapon,
		"hp": health, "k": kills, "d": deaths, "al": alive,
		"fuel": fuel, "ls": life_state, "mag": mag_ammo,
		"gr": grenades, "sf": _shots_fired, "sh": _shots_hit,
		# QA-112: Skyfall power-up state. "sh" is already taken by
		# _shots_hit, so the shield timer rides as "shd", and the
		# speed timer as "spd" (not "sp" - kept distinct on purpose).
		"shd": shield_timer, "spd": speed_timer,
		"inv": invisibility_timer, "jb": jetpack_boost_timer,
		"ab": active_boost_kind, "cf": carrying_flag,
		"sb": stored_boosts,
	})
	if force:
		# A forced send (respawn / stuck-recovery / score change)
		# already went out - do not send again on the next tick.
		_move_snap_timer = 0.0


@rpc("any_peer", "unreliable")
func receive_move_snapshot(snap: Dictionary) -> void:
	# Accept only the owner's snapshots (sender 0 = a direct local
	# call in the sim / tests, where there is no sender). A snapshot
	# for our OWN player is ignored - the local branch owns the local
	# position and must never be overwritten by a stale echo.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != peer_id:
		return
	if is_local_player():
		return
	# QA-073: the packet carries its player ID (spec §1). An id of 0
	# means "unspecified" (hand-built / old dicts, and the repl-sim) -
	# accept it. Any other id that is not this player is a misrouted
	# packet and is ignored.
	var snap_id := int(snap.get("id", 0))
	if snap_id != 0 and snap_id != peer_id:
		return
	var seq := int(snap.get("seq", 0))
	# QA-073: count delivery faults before dropping. Unreliable RPCs
	# can arrive out of order or twice: only a newer sequence may
	# move the player, so an old packet can never drag a remote
	# player backwards (snap-back) after a newer one arrived. The
	# counters (lost by sequence gap, duplicate, out-of-order) feed
	# the net-stats display - previously this was silent.
	if seq == _last_snap_seq:
		_net_dup_count += 1
		return
	if seq < _last_snap_seq:
		_net_ooo_count += 1
		return
	if _last_snap_seq >= 0 and seq > _last_snap_seq + 1:
		_net_lost_count += seq - _last_snap_seq - 1
	_last_snap_seq = seq
	_net_recv_count += 1
	var now := Time.get_ticks_msec() / 1000.0
	# QA-073: updates-per-second over a rolling 1 s window.
	if _net_ups_window_start <= 0.0:
		_net_ups_window_start = now
	_net_ups_count += 1
	if now - _net_ups_window_start >= 1.0:
		_net_ups = float(_net_ups_count) / (now - _net_ups_window_start)
		_net_ups_count = 0
		_net_ups_window_start = now
	var pos: Vector2 = snap.get("p", position)
	var vel: Vector2 = snap.get("v", Vector2.ZERO)
	sync_position = pos
	sync_velocity = vel
	aim_angle = float(snap.get("aim", aim_angle))
	facing = int(snap.get("face", facing))
	# QA-073: synced gameplay state (spec §5) - jetpack, firing,
	# reload, airborne. Old dicts without these keys keep the
	# previous values (get with the current value as default).
	_remote_jetpacking = bool(int(snap.get("jet", 1 if _remote_jetpacking else 0)))
	_remote_firing = bool(int(snap.get("fire", 1 if _remote_firing else 0)))
	_remote_reloading = bool(int(snap.get("rel", 1 if _remote_reloading else 0)))
	_remote_airborne = bool(int(snap.get("air", 1 if _remote_airborne else 0)))
	var new_weapon := int(snap.get("wpn", weapon))
	if new_weapon != weapon and new_weapon >= 0 and new_weapon < WEAPONS.size():
		weapon = new_weapon
		_switch_dip_timer = 0.15 # QA-075: a remote copy dips its gun on switch too
		_update_gun_texture()
	# QA-075: the remote muzzle flash. The snapshot stream (30/s)
	# refreshes this while the remote player is firing; 0.25 s
	# bridges the frames between snapshots, so the flash shows
	# steadily while firing and ends by itself when the stream
	# stops carrying fire=1. The local flash uses the shorter
	# per-weapon flash_t in _show_muzzle instead.
	if _remote_firing:
		_muzzle_timer = maxf(_muzzle_timer, 0.25)
	health = int(snap.get("hp", health))
	kills = int(snap.get("k", kills))
	deaths = int(snap.get("d", deaths))
	alive = bool(snap.get("al", alive))
	fuel = float(snap.get("fuel", fuel))
	life_state = int(snap.get("ls", life_state))
	mag_ammo = int(snap.get("mag", mag_ammo))
	grenades = int(snap.get("gr", grenades))
	_shots_fired = int(snap.get("sf", _shots_fired))
	_shots_hit = int(snap.get("sh", _shots_hit))
	# QA-112: Skyfall power-up state (old dicts without these keys
	# keep the current values, same as the other synced fields).
	shield_timer = float(snap.get("shd", shield_timer))
	speed_timer = float(snap.get("spd", speed_timer))
	invisibility_timer = float(snap.get("inv", invisibility_timer))
	jetpack_boost_timer = float(snap.get("jb", jetpack_boost_timer))
	active_boost_kind = int(snap.get("ab", active_boost_kind))
	carrying_flag = int(snap.get("cf", carrying_flag))
	var sb: Array = snap.get("sb", stored_boosts)
	stored_boosts.clear()
	for v in sb:
		stored_boosts.append(int(v))
	# Feed the interpolation buffer. QA-068: each entry is stamped
	# with the SENDER's clock ("st", sent in the snapshot), NOT the
	# receipt time - the two phones' clocks are never compared (they
	# differ), the sender stamps only ever order and space the
	# sender's own snapshots, and the render timeline is anchored
	# to the newest sender stamp (see _interp_position). A snapshot
	# without "st" (old / hand-built dicts) falls back to the
	# receipt time, the pre-QA-068 behaviour. "rt" (receipt time)
	# is kept alongside so the receiver can tell how long it has
	# been since a packet arrived and dead-reckon through a gap.
	# "prot" refreshes this copy's spawn-protection timer so the
	# host's view of a remote victim's protection is real (QA-069);
	# when prot is 0 the local countdown is left to run down.
	var sender_t := float(snap.get("st", now))
	# QA-073: adaptive interpolation delay. Jitter is the mismatch
	# between arrival spacing and sender spacing: on clean Wi-Fi
	# both are ~33 ms (jitter ~0); when packets arrive in bursts
	# the arrival gaps are 0 ms then ~300 ms while the sender gaps
	# stay 33 ms (jitter ~tens of ms). The EWMA (alpha 0.1) tracks
	# it, the target delay is 80 ms + 1.5x jitter, clamped to
	# 80-250 ms, and the live delay slews toward the target at most
	# 10 ms per 0.5 s - slow enough that the delay never wobbles the
	# render timeline itself. A resync (long silence) resets the
	# jitter history: the gap is not Wi-Fi jitter, it is a rejoin.
	if _prev_snap_sender_t >= 0.0 and now - _last_snap_receipt <= 0.5:
		var arrival_gap := now - _prev_snap_receipt_t
		var sender_gap := sender_t - _prev_snap_sender_t
		var jitter := absf(arrival_gap - sender_gap)
		_jitter_ewma = lerpf(_jitter_ewma, jitter, 0.1)
		if now >= _interp_delay_next_adjust:
			var target := clampf(0.08 + 1.5 * _jitter_ewma, 0.08, 0.25)
			_interp_delay = move_toward(_interp_delay, target, 0.01)
			_interp_delay_next_adjust = now + 0.5
	else:
		_jitter_ewma = 0.0
	_prev_snap_sender_t = sender_t
	_prev_snap_receipt_t = now
	if int(snap.get("prot", 0)) == 1:
		_spawn_protect_timer = SPAWN_PROTECTION
	# QA-068: a snapshot arriving after a long silence (>0.5 s) or
	# into an empty buffer is a re-placement (join / rejoin / long
	# loss burst), not steady motion - the remote branch snaps to
	# it once instead of gliding across the map.
	if _snapshots.is_empty() or now - _last_snap_receipt > 0.5:
		_snap_resync = true
	_last_snap_receipt = now
	_snapshots.append({"t": sender_t, "p": pos, "v": vel, "rt": now})
	# Prune by sender-time age (>1 s behind the newest snapshot is
	# useless) as well as by count, so a burst of arrivals cannot
	# evict the snapshots the render time still needs.
	var newest_t := sender_t
	while _snapshots.size() > 24:
		_snapshots.pop_front()
	while _snapshots.size() > 1 and newest_t - float((_snapshots[0] as Dictionary)["t"]) > 1.0:
		_snapshots.pop_front()


# QA-073: reconciliation against authoritative state (spec §4).
# The host calls this on the owning client when its view of that
# player has diverged beyond what interpolation lag can explain
# (game.gd _update_divergence_check: fresh snapshot stream, >300 px
# sustained 1 s - it never fires on normal interp lag, which stays
# under ~60 px). Small errors blend in over a few physics frames
# via _reconcile_target (see the local branch); a teleport-class
# error (>300 px, e.g. a respawn the client never heard about)
# snaps at once, because gliding across the map would be worse.
# Stale corrections (older corr_seq) are ignored, so a delayed
# correction can never drag the player back to an old position.
# This is a no-op for remote copies - only the owner reconciles
# its own predicted position.
@rpc("any_peer")
func apply_authoritative_correction(auth_pos: Vector2, auth_vel: Vector2, corr_seq: int) -> void:
	if not is_local_player():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return # only the host may correct a client (0 = direct local call in tests)
	if corr_seq <= _last_corr_seq:
		return
	_last_corr_seq = corr_seq
	var dist := position.distance_to(auth_pos)
	if dist > 300.0:
		position = auth_pos
		velocity = auth_vel
		_reconcile_active = false
		return
	if dist < 2.0:
		return
	_reconcile_target = auth_pos
	_reconcile_active = true


# QA-073: one dict with everything the net-stats display needs
# (spec §7). "auth_pos" is the newest authoritative snapshot
# position for this (remote) player; the rendered position is the
# node's own position. For the local player the snapshot fields
# are its own last-received values (0 when solo).
func get_net_stats() -> Dictionary:
	var now := Time.get_ticks_msec() / 1000.0
	return {
		"recv": _net_recv_count, "lost": _net_lost_count,
		"dup": _net_dup_count, "ooo": _net_ooo_count,
		"ups": _net_ups, "buf": _snapshots.size(),
		"delay_ms": _interp_delay * 1000.0,
		"jitter_ms": _jitter_ewma * 1000.0,
		"extrap_ms": _net_extrap_s * 1000.0,
		"gap_ms": (now - _last_snap_receipt) * 1000.0 if _last_snap_receipt > 0.0 else 0.0,
		"auth_pos": sync_position, "pos": position,
		"jet": _remote_jetpacking, "fire": _remote_firing,
		"rel": _remote_reloading,
	}


func _process(delta: float) -> void:
	# Rendering only (GAP-69, spec §23.E): sprite/gun/camera/HP visuals
	# run at the render frame, never in _physics_process. Nothing here
	# writes position or velocity (camera position is a view offset).
	_update_visuals(delta)
	if is_local_player() and _camera != null:
		_update_camera(delta)
		_update_sight_line()


func _physics_process(delta: float) -> void:
	_movetest_pre_tick(delta) # QA-112: --movement-test step machine (no-op without the flag)
	_spawn_protect_timer = maxf(0.0, _spawn_protect_timer - delta)
	_shake_trauma = maxf(0.0, _shake_trauma - delta * 1.8)
	_gun_kick = maxf(0.0, _gun_kick - delta * 7.0)
	_tick_boost_timers(delta) # QA-112: Skyfall power-up timers
	_tick_health_regen(delta) # QA-120: slow health regen after 3 s without damage
	# Recoil accumulation decays when not firing (spec §16).
	if not _want_fire:
		_recoil_accum *= exp(-3.0 * delta)
		if _recoil_accum < 0.001:
			_recoil_accum = 0.0
	var game = get_tree().get_first_node_in_group("game")
	if game != null and game.match_over:
		# Match over: stand still, idle animation only.
		velocity = Vector2.ZERO
		if alive:
			_play_anim("idle")
		return
	if life_state != LifeState.ALIVE:
		if is_local_player():
			# Death FSM: DYING (0.4 s anim window) -> DEAD, then the
			# respawn timer runs; RESPAWNING retries validation.
			if life_state == LifeState.DYING:
				_dying_timer -= delta
				if _dying_timer <= 0.0:
					life_state = LifeState.DEAD
			elif life_state == LifeState.RESPAWNING:
				_respawn_retry_timer -= delta
				if _respawn_retry_timer <= 0.0:
					_respawn()
			else:
				# Last Man Standing: one life, no respawn. Survival: no
				# respawn until the host resets the round.
				var game3 = get_tree().get_first_node_in_group("game")
				var mode3: int = int(game3.game_mode) if game3 != null else 0
				if mode3 != 3 and not (mode3 == 2 and _round_dead):
					_respawn_timer -= delta
					if _respawn_timer <= 0.0:
						_respawn()
		else:
			# QA-069: a remote copy never runs _apply_damage (damage
			# RPCs go only to the victim's owning peer), so it never
			# played "die" - the body kept its last run/idle loop
			# with no gun, name or HP bar. Play the death pose here,
			# from the synced life_state, so every peer sees the
			# same death. _play_anim("die") is a no-op once playing.
			_play_anim("die")
		return
	if is_local_player():
		_read_input()
		_movetest_apply_input() # QA-112: --movement-test input overrides (no-op without the flag)
		# QA-073: reconciliation (spec §4) blends BEFORE movement,
		# not after: the blend sets position directly, and if that
		# put the player inside a wall the same frame's
		# move_and_slide pushes it back out - the player stops at
		# the wall instead of embedding in it (embedding trips the
		# stuck-recovery teleport, which is what the first
		# RECONCILE-BLEND run did: the +40 px nudge ended against
		# a wall and the player was teleported 228 px away). A small
		# authoritative correction blends in a little per physics
		# frame - the player never snaps for a few pixels of error,
		# so responsiveness is untouched. A large correction snapped
		# at once inside apply_authoritative_correction instead.
		if _reconcile_active:
			var rdist := position.distance_to(_reconcile_target)
			if rdist < 2.0:
				_reconcile_active = false
			else:
				position = position.move_toward(_reconcile_target, maxf(rdist * 0.2, 60.0 * delta))
		_update_ladder() # QA-112: Skyfall ladder grab / release, before movement
		_update_grapple(delta) # QA-112: Skyfall grapple attach / release, before movement
		_apply_movement(delta)
		_apply_aim_and_fire(delta)
		# the local simulation predicted each physics frame, so a
		# correction can be checked against the prediction ring.
		# Packed arrays, capped at 90 frames (~1.5 s), no dicts.
		_pred_pos.append(position)
		_pred_vel.append(velocity)
		_pred_seq.append(_move_snap_seq)
		while _pred_pos.size() > 90:
			_pred_pos.remove_at(0)
			_pred_vel.remove_at(0)
			_pred_seq.remove_at(0)
		_check_stuck(delta)
		# QA-053: snapshots at the spec rate (30/s) - the owner's
		# only channel out. Force-send is used by _respawn /
		# _check_stuck after a teleport so the remote copy never
		# waits a full interval to learn the new position.
		# QA-068: subtract the interval instead of resetting to 0,
		# so the 30/s cadence stays steady under variable frame
		# times instead of drifting a little later every tick.
		_move_snap_timer += delta
		if _move_snap_timer >= PhysicsConfig.SNAPSHOT_INTERVAL:
			_move_snap_timer -= PhysicsConfig.SNAPSHOT_INTERVAL
			_send_move_snapshot()
	else:
		# Remote players: 100 ms interpolation buffer (GAP-16, spec
		# §21.D/F), rendered on the SENDER's timeline (QA-068).
		# Position is owned ONLY by this buffer - no second channel
		# writes it. QA-068: the per-frame step clamp means one
		# physics frame can never move the copy further than the
		# fastest legit motion (700 px/s + 20 px slack) - a delayed
		# packet's catch-up glides over a few frames instead of
		# teleporting the copy. A genuine teleport (respawn /
		# stuck-recovery, >600 px away) or a re-placement after a
		# join / long gap (>100 px away, QA-073) still snaps at
		# once, or the copy would swim across the map. Velocity is
		# smoothed toward the latest snapshot (was: snapped
		# instantly) so the remote run/jetpack animation stops
		# flickering on jitter.
		var now := Time.get_ticks_msec() / 1000.0
		var target := _interp_position(now)
		var dist := position.distance_to(target)
		# QA-073: a resync snaps only when the copy is far from the
		# target (>100 px: a join / rejoin / long-gap re-placement).
		# When the copy is already close, snapping would drag it
		# BACKWARD: after a receipt gap just over 0.5 s the copy has
		# dead-reckoned forward past the delayed render target, so
		# the snap lands behind where the copy already is - the
		# chaos run caught a 49.5 px snap-back from exactly this.
		# Gliding the last few pixels instead is invisible and
		# never moves the copy backwards. A genuine teleport
		# (respawn / stuck-recovery, >600 px) still snaps at once.
		if dist > 600.0 or (_snap_resync and dist > 100.0):
			position = target
		else:
			position = position.move_toward(target, 700.0 * delta + 20.0)
		_snap_resync = false
		velocity = velocity.lerp(sync_velocity, clampf(delta * 10.0, 0.0, 1.0))
		_update_remote_anim()


func _interp_position(now: float) -> Vector2:
	# QA-068: the render timeline is anchored to the SENDER's
	# clock - render at (newest sender stamp - 100 ms), NOT at
	# (receipt time - 100 ms). The sender emits every 33 ms on its
	# own clock, so the spacing between bracketing snapshots is a
	# steady 33 ms whatever the Wi-Fi arrival jitter was; a burst
	# of late arrivals no longer compresses the lerp, and a delayed
	# packet no longer renders as if it were on time. The two
	# clocks are never compared: only the sender's stamps order and
	# space the buffer, and "rt" (receipt time) is used only to
	# measure how long packets have been missing. If packets have
	# stopped arriving, the timeline advances with the wall clock
	# (minus one snapshot interval of grace) so the copy
	# dead-reckons forward on its last velocity instead of freezing
	# at the last bracket - the freeze-then-catch-up jump the user
	# reported. Extrapolation past the newest snapshot is capped
	# at 150 ms of velocity; past that the copy holds rather than
	# guessing a reversal it cannot see. (A capped variant was
	# tried and rejected: holding at the newest snapshot made
	# each burst land as a 1400+ px/s catch-up surge.)
	if _snapshots.is_empty():
		_net_extrap_s = 0.0
		return position.lerp(sync_position, clampf(1.0 / 60.0 * 14.0, 0.0, 1.0))
	var first: Dictionary = _snapshots[0]
	var last: Dictionary = _snapshots[_snapshots.size() - 1]
	if _snapshots.size() < 2:
		# One snapshot only (join moment): dead-reckon from it on
		# its velocity, capped at 150 ms, instead of the old fixed
		# per-frame lerp toward sync_position.
		var dt0 := clampf(now - float(last.get("rt", now)), 0.0, 0.15)
		_net_extrap_s = dt0
		return (last["p"] as Vector2) + (last["v"] as Vector2) * dt0
	var newest_t := float(last["t"])
	var since_last := now - float(last.get("rt", now))
	if since_last > PhysicsConfig.SNAPSHOT_INTERVAL:
		newest_t += since_last - PhysicsConfig.SNAPSHOT_INTERVAL
	# QA-073: the render time uses the ADAPTIVE delay (was the fixed
	# 100 ms INTERP_BUFFER): render at (newest sender stamp -
	# _interp_delay). Clean Wi-Fi settles near 80 ms, bursty Wi-Fi
	# grows the buffer. INTERP_BUFFER is still the starting value.
	# QA-073 (render clock): the target render time is then made
	# MONOTONIC - it may never move backwards. When the adaptive
	# delay grows, newest - delay would retreat, and the copy would
	# step back and then surge forward (the first chaos run: 52 px
	# snap-back, 1352 px/s). Holding the clock instead only defers
	# the delay growth itself (tens of ms of sender time, ~10 px),
	# so the copy pauses briefly instead of retreating. There is
	# deliberately NO upper slew: capping the advance by wall time
	# starved the clock whenever physics ticks batched (burst
	# smoothness 937 px/s, burst move 421 -> 332 px) - the render
	# clock must be free to follow the sender's clock, and the
	# per-frame step clamp is what bounds the copy's speed. Only a
	# resync jumps the clock, and the remote branch snaps the copy
	# on a resync anyway.
	var target_render_t := newest_t - _interp_delay
	var render_t := target_render_t
	if _snap_resync:
		_render_t_last = target_render_t
	elif _render_t_last > -INF:
		render_t = maxf(target_render_t, _render_t_last)
		_render_t_last = render_t
	else:
		_render_t_last = render_t
	if render_t <= float(first["t"]):
		_net_extrap_s = 0.0
		return first["p"]
	if render_t >= float(last["t"]):
		# Past the newest snapshot: glide on its velocity, at most
		# 150 ms (was: at most one 16.7 ms physics step, then
		# freeze - the freeze-then-jump the user saw on Wi-Fi).
		var dt := minf(render_t - float(last["t"]), 0.15)
		_net_extrap_s = dt
		return (last["p"] as Vector2) + (last["v"] as Vector2) * dt
	_net_extrap_s = 0.0
	for i in range(_snapshots.size() - 1):
		var a: Dictionary = _snapshots[i]
		var b: Dictionary = _snapshots[i + 1]
		if float(a["t"]) <= render_t and render_t <= float(b["t"]):
			var span := float(b["t"]) - float(a["t"])
			var f := 0.5 if span <= 0.0 else clampf((render_t - float(a["t"])) / span, 0.0, 1.0)
			return (a["p"] as Vector2).lerp(b["p"], f)
	return last["p"]


func _check_stuck(delta: float) -> void:
	# Stuck-in-geometry recovery (GAP-72): only fires when the player
	# is actually OVERLAPPING solid geometry (shape query), never for
	# merely pushing against a wall - that is normal play.
	_stuck_check_timer += delta
	if _stuck_check_timer < PhysicsConfig.STUCK_CHECK_INTERVAL:
		return
	_stuck_check_timer = 0.0
	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return
	# Query capsule is 3 px smaller than the real one (radius 17,
	# height 56): move_and_slide leaves ~1 px of solver penetration
	# when the player pushes flush against a wall, and that is NOT
	# being stuck - a real embed is 10+ px deep and still triggers.
	var cap := CapsuleShape2D.new()
	cap.radius = 17.0
	cap.height = 56.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cap
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var space := get_world_2d().direct_space_state
	if not space.intersect_shape(q, 1).is_empty():
		var spot: Vector2 = game.get_valid_spawn_point(player_index, peer_id, global_position)
		print("STUCK-RECOVERY: player %d was inside solid geometry, moved to %s" % [peer_id, str(spot)])
		position = spot
		velocity = Vector2.ZERO
		# QA-053: teleport - tell the other phones at once instead
		# of waiting for the next 33 ms snapshot tick.
		_send_move_snapshot(true)
		_wedge_reset()
		return
	# Wedged-between-obstacles recovery (QA-063): the overlap check
	# above only fires when the capsule is INSIDE solid geometry. A
	# player wedged in a slot between two solids is NOT overlapping
	# either one, so it never fired. Detect it by behaviour instead:
	# the player keeps giving move input on the floor but does not
	# move, and solid geometry is within reach on BOTH sides. Pushing
	# against a single wall is normal play and must NOT trigger: one
	# side is open there, so the both-sides probe fails and nothing
	# happens. The probe only runs after 1 s of no movement, and the
	# teleport needs either a wiggle (both directions tried) or 2 s
	# of holding one direction, so a brief shove against a wall in a
	# tight pocket cannot false-fire.
	if not is_on_floor() or absf(_move_axis) <= 0.3:
		_wedge_reset()
		return
	if _move_axis < 0.0:
		_wedge_tried_left = true
	else:
		_wedge_tried_right = true
	if _wedge_ref_pos == Vector2.INF or global_position.distance_to(_wedge_ref_pos) > 4.0:
		_wedge_ref_pos = global_position
		_wedge_still = 0.0
		_wedge_tried_left = _move_axis < 0.0
		_wedge_tried_right = _move_axis > 0.0
		return
	_wedge_still += PhysicsConfig.STUCK_CHECK_INTERVAL
	var both_tried: bool = _wedge_tried_left and _wedge_tried_right
	if _wedge_still >= 1.0 and (both_tried or _wedge_still >= 2.0) and _both_sides_blocked():
		var spot2: Vector2 = game.get_valid_spawn_point(player_index, peer_id, global_position)
		print("WEDGE-RECOVERY: player %d wedged between obstacles (no move for %.0f s), moved to %s" % [peer_id, _wedge_still, str(spot2)])
		position = spot2
		velocity = Vector2.ZERO
		_send_move_snapshot(true)
		_wedge_reset()


func _wedge_reset() -> void:
	_wedge_ref_pos = Vector2.INF
	_wedge_still = 0.0
	_wedge_tried_left = false
	_wedge_tried_right = false


func _both_sides_blocked() -> bool:
	# Raycast 48 px left and right from the capsule centre (QA-071b:
	# was 40 px; the capsule is 40 px wide, so the rays probe 28 px
	# past each edge). Both must hit solid world geometry (layer 1)
	# for a wedge.
	var space := get_world_2d().direct_space_state
	for dir in [-1.0, 1.0]:
		var rq := PhysicsRayQueryParameters2D.create(global_position, global_position + Vector2(48.0 * dir, 0.0))
		rq.collision_mask = 1
		rq.collide_with_bodies = true
		rq.collide_with_areas = false
		rq.exclude = [get_rid()]
		if space.intersect_ray(rq).is_empty():
			return false
	return true


func _update_camera(delta: float) -> void:
	# Camera dead zone + look-ahead (GAP-52/53, spec §19). The camera
	# is a child of the player, so the dead zone is implemented with an
	# anchor: it only moves when the player leaves a 120x80 px rect
	# around it, and the view leads the movement direction by up to 80 px.
	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return
	if not _cam_anchor_init:
		_cam_anchor = global_position
		_cam_anchor_init = true
	var off := global_position - _cam_anchor
	var dz: Vector2 = PhysicsConfig.CAMERA_DEAD_ZONE
	if absf(off.x) > dz.x:
		_cam_anchor.x += off.x - signf(off.x) * dz.x
	if absf(off.y) > dz.y:
		_cam_anchor.y += off.y - signf(off.y) * dz.y
	var look_target := 0.0
	if absf(velocity.x) > 100.0:
		look_target = signf(velocity.x) * PhysicsConfig.CAMERA_LOOKAHEAD
	elif absf(velocity.x) > 10.0:
		look_target = signf(velocity.x) * PhysicsConfig.CAMERA_LOOKAHEAD * 0.5
	_cam_look = move_toward(_cam_look, look_target, delta * 240.0)
	var target := _cam_anchor + Vector2(_cam_look, 0)
	# QA-105 (v3.8): while scoped, the view shifts toward the aim
	# direction so the player sees further that way.
	if scoped and _aiming:
		target += _aim_dir * 150.0
	# Clamp the view inside the map (hard limits, spec §19).
	# QA-105: the clamp uses the EFFECTIVE view size (viewport /
	# zoom) so a scoped (zoomed-in) camera still stays inside.
	var vp := get_viewport().get_visible_rect().size / _camera.zoom
	var ms: Vector2 = game.map_size
	var hx := minf(vp.x * 0.5, ms.x * 0.5)
	var hy := minf(vp.y * 0.5, ms.y * 0.5)
	target.x = clampf(target.x, hx, maxf(hx, ms.x - hx))
	target.y = clampf(target.y, hy, maxf(hy, ms.y - hy))
	_camera.position = target - global_position
	# QA-105: scope zoom - sniper 2.0x, rifle 1.5x, everything else
	# 1.0x. Eases at 3x/s so the zoom feels smooth, not a snap.
	var zoom_target := 1.0
	if scoped:
		zoom_target = SCOPE_ZOOM_SNIPER if weapon == 3 else (SCOPE_ZOOM_RIFLE if weapon == 0 else 1.0)
	var zoom_now := move_toward(_camera.zoom.x, zoom_target, delta * 3.0)
	_camera.zoom = Vector2(zoom_now, zoom_now)


func _update_sight_line() -> void:
	# QA-105 (v3.8): the sniper sight line - local player only,
	# sniper equipped, while aiming (right stick deflected). One
	# raycast along the true bullet path (mask 1 = world, same as
	# game.gd has_line_of_sight): green while clear to full sniper
	# range, red where a wall blocks it, ending at the wall.
	if _sight_line == null:
		return
	if not alive or weapon != 3 or not _aiming:
		_sight_line.visible = false
		return
	var dir := Vector2(cos(aim_angle), sin(aim_angle))
	var muzzle := global_position + _muzzle_origin() + dir * (GUN_LENGTH + 6.0)
	var end := muzzle + dir * SIGHT_LINE_RANGE
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(muzzle, end, 1)
	var hit: Dictionary = space.intersect_ray(query)
	var blocked := false
	if not hit.is_empty():
		end = hit["position"]
		blocked = true
	_sight_line.points = PackedVector2Array([muzzle - global_position, end - global_position])
	_sight_line.default_color = Color(1.0, 0.3, 0.25) if blocked else Color(0.35, 1.0, 0.45)
	_sight_line.visible = true


func _read_input() -> void:
	_move_axis = 0.0
	_move_mag = 0.0
	_jump_held = false
	_jump_pressed = false
	_aim_dir = Vector2.ZERO
	_want_fire = false
	_aiming = false

	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return
	# Touch input from the game (joysticks). The left stick is a full 2D
	# vector (already dead-zoned and normalized by the joystick itself):
	# x moves, y up jumps / flies the jetpack, y down fast-falls.
	var move_vec: Vector2 = game.touch_move_vec
	_move_axis = move_vec.x
	_move_mag = absf(_move_axis)
	_move_stick_y = move_vec.y # QA-112: kept for the ladder (up/down to climb)
	# Stick-up jump: only on the rising edge, and only while "armed".
	# Holding the stick up through a landing must NOT auto-jump again -
	# the player re-arms by letting the stick drop below the threshold.
	var up_held := move_vec.y < -STICK_UP_THRESHOLD
	if up_held and not _stick_up_prev and _stick_up_armed:
		_jump_pressed = true
		_stick_up_armed = false
	if not up_held:
		_stick_up_armed = true
	_stick_up_prev = up_held
	_jump_held = up_held
	_fast_fall = move_vec.y > STICK_DOWN_THRESHOLD
	if game.touch_aim_active:
		# GAP-09: the dead zone lives in joystick.gd only (0.20,
		# rescaled). touch_aim is already dead-zoned, so aiming is
		# true for ANY non-zero aim vector; sensitivity is applied
		# AFTER the dead zone so it cannot shrink it.
		_aim_dir = game.touch_aim * GameData.sensitivity
		if _aim_dir.length() > 1.0:
			_aim_dir = _aim_dir.normalized()
		_aiming = _aim_dir.length() > 0.0
	# v3.2: firing comes from the AIM stick (see game.gd) - the right
	# stick aims AND fires while held. Semi-auto weapons (pistol,
	# shotgun, sniper) fire one shot per fresh deflection.
	_want_fire = game.touch_firing
	# Peek at the pending semi-auto shot - do NOT consume it here.
	# _read_input runs in _physics_process but touch_firing only
	# updates in _process, so a flick that lands just after a physics
	# step would otherwise be lost entirely (the flick would do
	# nothing on a real phone too). The edge is consumed in
	# _apply_aim_and_fire when the shot actually fires, and discarded
	# on respawn / while reloading / on weapon switch.
	_fire_edge = false
	if game.has_method("has_aim_fire_edge"):
		_fire_edge = game.has_aim_fire_edge()
	# Keyboard / mouse fallback (desktop testing only; touch wins when active).
	if _move_axis == 0.0:
		var kb := Input.get_axis("ui_left", "ui_right")
		if kb != 0.0:
			_move_axis = kb
			_move_mag = absf(kb)
	if Input.is_key_pressed(KEY_SPACE):
		_jump_held = true
	if Input.is_action_just_pressed("ui_accept"):
		_jump_pressed = true
	if not _aiming and game.touch_aim_active == false:
		# QA-054 - the "turns left on release" glitch: on a phone,
		# Godot emulates a mouse from every touch
		# (emulate_mouse_from_touch defaults to true; project.godot
		# never turns it off), so holding the MOVE stick also read
		# as a held left mouse button at the finger's position - and
		# this fallback then aimed the gun at the left-half touch
		# point, i.e. LEFT, while the player ran RIGHT. Facing
		# follows the aim, so the player faced left for the whole
		# move and stayed facing left after release (facing only
		# ever changes on a fresh aim/move input, so nothing ever
		# turned it back). The mouse branch must never run while a
		# touch is held or was just released (game.touch_recently_used
		# covers both, with a 500 ms latch for a stale emulated
		# button-up). On a touch device this branch is effectively
		# desktop-only, which is what its comment always said.
		var mouse_pos := get_viewport().get_mouse_position()
		# Mouse aims only - it never fires (the right stick shoots).
		# Clicks on HUD controls (fire / grenade / weapon / pause /
		# score / reload) must not swing the aim.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not game.is_hud_control_pos(mouse_pos) and not game.touch_recently_used():
			var center := get_viewport().get_visible_rect().size * 0.5
			var dir := mouse_pos - center
			if dir.length() > 40.0:
				_aim_dir = dir.normalized()
				_aiming = true


# QA-112 (v3.9 Skyfall ladders): grab / release, run every physics
# frame for the local player before _apply_movement. The player is
# on a ladder when their centre is inside a ladder rect AND they
# hold up/down on the move stick. The helper lives on the game
# scene (game.gd skyfall_ladder_at); the current scene is checked
# first, then the "game" group node, and if neither has it this is
# a complete no-op - on any map but Skyfall nothing changes.
# Jumping exits the ladder: a fresh stick-up edge while already
# climbing jumps the player off. The grab itself also starts with
# a stick-up edge, so the exit only fires when already climbing
# (was_on_ladder); after jumping off, the ladder stays disarmed
# until the stick is released, or the same held stick-up would
# grab the ladder again mid-jump. Letting go, or leaving the rect,
# ends the climb and re-arms the grab.
func _update_ladder() -> void:
	var was_on_ladder := _on_ladder
	_on_ladder = false
	_ladder_rect = Rect2()
	var rect := Rect2()
	var scene = get_tree().current_scene
	if scene != null and scene.has_method("skyfall_ladder_at"):
		rect = scene.skyfall_ladder_at(global_position)
	if rect == Rect2():
		var game = get_tree().get_first_node_in_group("game")
		if game != null and game.has_method("skyfall_ladder_at"):
			rect = game.skyfall_ladder_at(global_position)
	if rect == Rect2():
		_ladder_armed = true
		return
	_ladder_rect = rect
	var holding := _move_stick_y < -0.3 or _move_stick_y > 0.3
	if not holding:
		_ladder_armed = true
		return
	if _jump_pressed and was_on_ladder:
		_ladder_armed = false
		return
	if _ladder_armed:
		_on_ladder = true


# QA-112 (v3.9 Skyfall movement): grapple / wall-jump / jetpack-line
# data + logic. The game scene owns the data (MAPS[5]); this file
# only reads it, the same way _update_ladder reads skyfall_ladder_at
# - current scene first, then the "game" group node, and a missing
# key or a missing helper is a no-op, never a crash. The point/line
# lists are cached per map (MAPS is const, so the data cannot
# change mid-match); any other map returns empty / false.


func _is_skyfall() -> bool:
	var game = get_tree().get_first_node_in_group("game")
	if game == null or not ("map_id" in game):
		return false
	return int(game.map_id) == GameData.SKYFALL_MAP_ID


func _skyfall_grapple_points() -> Array:
	# Fixed grapple points for this map ([] off Skyfall, or when the
	# "grapple" key is missing). A skyfall_grapple_points() helper
	# on the game scene wins when it exists; otherwise MAPS[5]
	# is read directly (const access through the instance).
	if not _is_skyfall():
		return []
	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return []
	var mid := int(game.map_id)
	if _sf_grapple_cache_map == mid:
		return _sf_grapple_cache
	_sf_grapple_cache_map = mid
	_sf_grapple_cache = []
	if game.has_method("skyfall_grapple_points"):
		var r = game.skyfall_grapple_points()
		if r is Array:
			_sf_grapple_cache = r
	if _sf_grapple_cache.is_empty() and ("MAPS" in game):
		var maps: Array = game.MAPS
		if GameData.SKYFALL_MAP_ID < maps.size():
			var row = maps[GameData.SKYFALL_MAP_ID]
			if row is Dictionary:
				var raw = (row as Dictionary).get("grapple", [])
				if raw is Array:
					_sf_grapple_cache = raw
	return _sf_grapple_cache


func _skyfall_jetpack_lines() -> Array:
	# Marked jetpack routes ([{"from": Vector2, "to": Vector2}])
	# for this map ([] off Skyfall, or when "jetpack_lines" is
	# missing). A skyfall_jetpack_lines() helper on the game scene
	# wins when it exists; otherwise MAPS[5] is read directly.
	if not _is_skyfall():
		return []
	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return []
	var mid := int(game.map_id)
	if _sf_lines_cache_map == mid:
		return _sf_lines_cache
	_sf_lines_cache_map = mid
	_sf_lines_cache = []
	if game.has_method("skyfall_jetpack_lines"):
		var r = game.skyfall_jetpack_lines()
		if r is Array:
			_sf_lines_cache = r
	if _sf_lines_cache.is_empty() and ("MAPS" in game):
		var maps: Array = game.MAPS
		if GameData.SKYFALL_MAP_ID < maps.size():
			var row = maps[GameData.SKYFALL_MAP_ID]
			if row is Dictionary:
				var raw = (row as Dictionary).get("jetpack_lines", [])
				if raw is Array:
					_sf_lines_cache = raw
	return _sf_lines_cache


static func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	# Shortest distance from a point to a line segment (clamped
	# projection; a zero-length segment is just its point).
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _on_jetpack_line_at(pos: Vector2, lines: Array) -> bool:
	for raw in lines:
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		if not (d.has("from") and d.has("to")):
			continue
		var a = d["from"]
		var b = d["to"]
		if a is Vector2 and b is Vector2 and _segment_distance(pos, a, b) <= JETPACK_LINE_DIST:
			return true
	return false


static func _nearest_grapple_point(points: Array, from_pos: Vector2) -> Vector2:
	# Nearest point within GRAPPLE_RANGE that is ABOVE the player
	# (Vector2.INF when there is none). Malformed entries are skipped.
	var best := Vector2.INF
	var best_d := INF
	for raw in points:
		if not (raw is Vector2):
			continue
		var pt: Vector2 = raw
		if pt.y >= from_pos.y:
			continue
		var d := from_pos.distance_to(pt)
		if d <= GRAPPLE_RANGE and d < best_d:
			best_d = d
			best = pt
	return best


func _is_on_jetpack_line() -> bool:
	# Within 70 px of a jetpack-line segment on Skyfall. A
	# skyfall_jetpack_line_at(pos) helper on the game scene wins
	# when it exists; otherwise the MAPS lines are measured here.
	if not _is_skyfall():
		return false
	var game = get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("skyfall_jetpack_line_at"):
		return bool(game.skyfall_jetpack_line_at(global_position))
	return _on_jetpack_line_at(global_position, _skyfall_jetpack_lines())


func _grapple_pull_speed() -> float:
	# 500 px/s, 425 for a flag carrier (the 15% slower rule applies
	# to the rope pull too).
	return GRAPPLE_PULL_SPEED * (FLAG_CARRY_SPEED_MULT if carrying_flag != 0 else 1.0)


func _release_grapple(with_boost: bool) -> void:
	if not _grappling:
		return
	_grappling = false
	_grapple_point = Vector2.ZERO
	_grapple_cooldown = GRAPPLE_COOLDOWN
	if with_boost:
		velocity.y -= GRAPPLE_RELEASE_BOOST


# QA-112 (v3.9 Skyfall grapple): attach / release, run every physics
# frame for the local player before _apply_movement (same slot as the
# ladder). Airborne on Skyfall, JUMP pressed, a point within 320 px
# and above: the rope attaches and the press is swallowed (it must
# not also jump). JUMP again while attached: let go with a 200 px/s
# upward boost. 1 s cooldown between grapples. No fuel, no jetpack
# while attached; firing is gated in _apply_aim_and_fire. Leaving
# Skyfall (or the data disappearing) drops the rope.
func _update_grapple(delta: float) -> void:
	_grapple_cooldown = maxf(0.0, _grapple_cooldown - delta)
	if not _is_skyfall():
		if _grappling:
			_release_grapple(false)
		return
	if _grappling:
		if _jump_pressed:
			_release_grapple(true)
			_jump_pressed = false
		return
	if _grapple_cooldown > 0.0:
		return
	# The ladder-grab frame also carries a jump edge (stick-up grabs
	# the ladder) - that edge climbs, it must not also grapple.
	if _jump_pressed and not _on_ladder and not is_on_floor():
		var pt := _nearest_grapple_point(_skyfall_grapple_points(), global_position)
		if pt != Vector2.INF:
			_grappling = true
			_grapple_point = pt
			_jump_pressed = false


# QA-112 (v3.9 Skyfall wall-jump): Skyfall only, airborne, pressed
# against a wall (moving toward it, velocity into it or stopped
# against it, wall within 24 px), JUMP pressed: push away from the
# wall (380 px/s) and up (-520 px/s). At most 2 in a row before
# touching ground. No fuel. A carrier may wall-jump (it is not a
# jetpack) at the 15% slower rate (323 / -442). A fixed impulse, so
# no variable-height cut. True when it fired (the press is eaten).
func _try_wall_jump() -> bool:
	if not _is_skyfall():
		return false
	if is_on_floor() or _wall_jumps_used >= WALL_JUMP_MAX_CHAIN:
		return false
	if _jump_buffer_timer <= 0.0:
		return false
	# Which side is the wall on? is_on_wall + normal first (already
	# touching), else a 24 px ray in the move direction (close but
	# not yet touching). +1 = wall on the right, -1 = on the left.
	var side := 0
	if is_on_wall():
		var n := get_wall_normal()
		if n.x < -0.5:
			side = 1
		elif n.x > 0.5:
			side = -1
	if side == 0 and _move_axis != 0.0:
		var space := get_world_2d().direct_space_state
		var from := global_position
		var to := global_position + Vector2(_move_axis * (CAPSULE_RADIUS + WALL_DETECT_DIST), 0.0)
		var q := PhysicsRayQueryParameters2D.create(from, to, 1)
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.exclude = [get_rid()]
		if not space.intersect_ray(q).is_empty():
			side = 1 if _move_axis > 0.0 else -1
	if side == 0:
		return false
	# Moving toward the wall: the stick is pushed that way, and the
	# horizontal velocity (if any) points into it - a player sliding
	# down the wall with no horizontal speed still counts.
	if _move_axis == 0.0 or signf(_move_axis) != float(side):
		return false
	if velocity.x != 0.0 and signf(velocity.x) != float(side):
		return false
	var mult := FLAG_CARRY_SPEED_MULT if carrying_flag != 0 else 1.0
	velocity.x = -float(side) * WALL_JUMP_PUSH * mult
	velocity.y = -WALL_JUMP_UP * mult
	_wall_jumps_used += 1
	_jump_buffer_timer = 0.0
	_jump_pressed = false
	_jump_cut_armed = false
	_coyote_timer = 0.0
	_play_sound("jump")
	return true


func _apply_movement(delta: float) -> void:
	# Ground/air split (GAP-02, spec §2E) + exponential drag (GAP-03,
	# spec §2C/§6) + ice zone (GAP-51, spec §18.A). Ground: strong
	# accel, high friction, fast reversal. Air: moderate accel, low
	# friction, momentum preserved. Ice: accel 500, friction 100.
	var on_floor := is_on_floor()
	var game = get_tree().get_first_node_in_group("game")
	var on_ice := false
	if game != null and on_floor:
		on_ice = game.is_on_ice(global_position)
	var max_speed := SPEED_GROUND
	var accel := ACCEL_GROUND
	# No-input decel is exponential drag (GAP-03); DECEL_GROUND/AIR
	# stay defined as tuning reference only.
	var drag := DRAG_GROUND
	if on_ice:
		max_speed = PhysicsConfig.ICE_MAX_SPEED
		accel = PhysicsConfig.ICE_ACCEL
		drag = PhysicsConfig.ICE_FRICTION / 1200.0 * DRAG_GROUND
	elif not on_floor:
		max_speed = SPEED_AIR
		# QA-074: while jetpacking the player steers better in the
		# air (accel 1900, was the plain air 1500) - flying should
		# feel controlled, not drifty. _jetpacking here is last
		# frame's value (the vertical block below sets it), which
		# is one frame of lag on the first thrust frame only.
		accel = JET_AIR_ACCEL if _jetpacking else ACCEL_AIR
		drag = DRAG_AIR
	# QA-112: speed boost x1.3, flag carrier x0.85 (they stack if
	# both apply - a boosted carrier runs at 1.3 * 0.85).
	if speed_timer > 0.0:
		max_speed *= SPEED_BOOST_MULT
	if carrying_flag != 0:
		max_speed *= FLAG_CARRY_SPEED_MULT
	if _on_ladder:
		# QA-112: ladder climb - no gravity, no jump, no jetpack.
		# Climb 200 px/s on the stick; horizontal at half speed;
		# move_and_slide still runs so platforms stop the climb.
		# The grab-frame jump edge is swallowed: pushing the stick
		# up grabs the ladder, it must not also hop the player.
		_jump_buffer_timer = 0.0
		_jump_cut_armed = false
		_jet_ramp_t = 0.0
		_jet_thrust_factor = 0.0
		_stop_jetpack_sound()
		var climb := 0.0
		if _move_stick_y < -0.3:
			climb = -LADDER_CLIMB_SPEED
		elif _move_stick_y > 0.3:
			climb = LADDER_CLIMB_SPEED
		velocity.y = climb
		velocity.x = move_toward(velocity.x, _move_axis * max_speed * 0.5, ACCEL_GROUND * delta)
		_fall_speed = velocity.y
		_was_on_floor = on_floor
		move_and_slide()
		if is_on_floor():
			_jump_cut_armed = false
		return
	if _grappling:
		# QA-112: rope pull - velocity straight at the point at the
		# pull speed (500, 425 for a carrier), gravity at 30% so
		# the rope still sags a little. No fuel, no jetpack, no
		# jump while attached (firing is gated in
		# _apply_aim_and_fire). Arrival (within 60 px) or landing
		# ends the pull and falls through to normal movement.
		_jetpacking = false
		_jet_ramp_t = 0.0
		_jet_thrust_factor = 0.0
		_stop_jetpack_sound()
		_jump_buffer_timer = 0.0
		_jump_cut_armed = false
		if is_on_floor() or global_position.distance_to(_grapple_point) <= GRAPPLE_RELEASE_DIST:
			_release_grapple(false)
		if _grappling:
			var dir := (_grapple_point - global_position).normalized()
			velocity = dir * _grapple_pull_speed()
			velocity.y += GRAVITY * 0.3 * delta
			_fall_speed = velocity.y
			_was_on_floor = on_floor
			move_and_slide()
			return
		# Released this frame: fall through to normal movement below.
	if _move_axis != 0.0:
		# Reversal bonus (GAP-01): flicking against current motion
		# reverses crisply on ground (1.6x), lazily in air (1.2x).
		# QA-074: NO reversal bonus while jetpacking (1.0x) - a
		# direction change in flight must be smooth, not snappy.
		var rate := accel
		if signf(_move_axis) != signf(velocity.x) and velocity.x != 0.0:
			rate = accel * (REVERSAL_GROUND if on_floor else (1.0 if _jetpacking else REVERSAL_AIR))
		var target_vx := _move_axis * max_speed
		velocity.x = move_toward(velocity.x, target_vx, rate * delta)
		# Air drag still applies while airborne even with input held,
		# so top speed in air is drag-limited, not just clamped.
		if not on_floor:
			velocity.x *= exp(-drag * delta)
	else:
		# No input: exponential drag only (GAP-03). DECEL_GROUND/AIR
		# are retained as tuning reference; the drag model above is
		# what actually stops the player.
		velocity.x *= exp(-drag * delta)
	# QA-112: jetpack-line check for this frame (Skyfall only;
	# false elsewhere). Used by the jetpack fuel drain below and
	# by the wind shield at the bottom of this function.
	_on_jetpack_line = _is_on_jetpack_line()
	# Jump buffering + coyote time: jumping feels reliable even if the
	# button is pressed a moment before landing / after leaving a ledge.
	if _jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	if on_floor:
		_coyote_timer = COYOTE_TIME
		_wall_jumps_used = 0 # QA-112: touching ground resets the wall-jump chain
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_jetpacking = false
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_cut_armed = true
		_play_sound("jump")
	elif _try_wall_jump():
		# QA-112: Skyfall wall-jump fired (see _try_wall_jump) -
		# the press is eaten and the push is already applied.
		pass
	elif _jump_held and not on_floor and fuel > 0.0 and carrying_flag == 0:
		# QA-112: a flag carrier gets NO jetpack thrust (carrier
		# rule) - the branch is skipped, so no fuel is spent either.
		# Jetpack sustains a climb, it never chops jump momentum:
		# thrust applies only while rising SLOWER than the cap, so
		# a -660 jump is not clamped down to -320 when fuel regens
		# mid-rise (air regen, GAP-05, used to do exactly that).
		# QA-074: the thrust RAMPS (JET_RAMP_MIN -> 1.0 over
		# JET_RAMP_TIME) instead of hitting at full force on the
		# first frame - the climb spools up smoothly, and the
		# handover from the jump's decay is a gentle slow-down,
		# not a sudden direction change. Gravity still applies
		# every frame below, so net climb accel at full ramp is
		# JET_ACCEL - GRAVITY = 250 px/s^2 (was 500), and the cap
		# is 320 px/s (was 450). The ramp resets whenever thrust
		# stops, so every burst spools up again.
		if velocity.y > -MAX_JET_RISE:
			_jet_ramp_t += delta
			_jet_thrust_factor = minf(1.0, JET_RAMP_MIN + _jet_ramp_t / JET_RAMP_TIME * (1.0 - JET_RAMP_MIN))
			# QA-112: jetpack boost multiplies the thrust x1.4 (the
			# rise cap MAX_JET_RISE stays 320 - the boost spools
			# the climb up faster, it does not raise the top speed).
			var thrust := JET_ACCEL * _jet_thrust_factor
			if jetpack_boost_timer > 0.0:
				thrust *= JETPACK_BOOST_MULT
			velocity.y -= thrust * delta
			if velocity.y < -MAX_JET_RISE:
				velocity.y = -MAX_JET_RISE
			# QA-112: on a jetpack line the player rides the wind
			# instead of fighting it - fuel drains at HALF rate.
			# (A carrier never reaches this branch: no jetpack
			# while carrying, so no discount and no boost.)
			var drain := FUEL_DRAIN * (0.5 if _on_jetpack_line else 1.0)
			fuel = maxf(0.0, fuel - drain * delta)
			_fuel_delay_timer = FUEL_REGEN_DELAY
			_jetpacking = true
			_jump_cut_armed = false
			_start_jetpack_sound()
		else:
			_jet_ramp_t = 0.0
			_jet_thrust_factor = 0.0
			_stop_jetpack_sound()
	else:
		_jet_ramp_t = 0.0
		_jet_thrust_factor = 0.0
		_stop_jetpack_sound()
	# Variable jump height (GAP-04, spec §4): releasing stick-up while
	# still rising cuts upward velocity. Never fires while jetpacking
	# (holding stick-up keeps _jump_held true, so no cut mid-climb).
	if _jump_cut_armed and not _jump_held and not _jetpacking and velocity.y < 0.0:
		velocity.y *= PhysicsConfig.JUMP_CUT
		_jump_cut_armed = false
	# Fuel regen (GAP-05, spec §5): after a 0.6 s delay, regen whether
	# grounded or airborne (ground faster). Never regen while thrusting.
	if not _jetpacking:
		if _fuel_delay_timer > 0.0:
			_fuel_delay_timer -= delta
		else:
			var rate := FUEL_REFILL if on_floor else FUEL_REFILL_AIR
			fuel = minf(FUEL_MAX, fuel + rate * delta)
	velocity.y += GRAVITY * delta
	# v2.2: pushing the left stick down while airborne fast-falls.
	if _fast_fall and not on_floor and not _jetpacking:
		velocity.y += FAST_FALL_EXTRA * delta
	# QA-112: Skyfall wind zones push the player (game.gd sets
	# wind_force every frame; Vector2.ZERO on every other map, so
	# this is a no-op there). Extra acceleration, then clamped to
	# the normal speed limits so wind never outruns the player.
	# A jetpack line SHIELDS the rider from the wind - but only
	# while jetpacking on it, or while carrying the flag (a carrier
	# cannot jetpack at all, yet the line still shields them; they
	# get no fuel discount and no boost for it).
	var line_shield := _on_jetpack_line and (_jetpacking or carrying_flag != 0)
	if wind_force != Vector2.ZERO and not line_shield:
		velocity += wind_force * delta
		velocity.x = clampf(velocity.x, -max_speed - 100.0, max_speed + 100.0)
	var max_fall := MAX_FALL + (350.0 if _fast_fall else 0.0)
	if velocity.y > max_fall:
		velocity.y = max_fall
	_fall_speed = velocity.y
	_was_on_floor = on_floor
	move_and_slide()
	if is_on_floor():
		_jump_cut_armed = false
	if is_on_floor() and not _was_on_floor and _fall_speed > 550.0:
		# Hard landing: small dust puff only.
		var game2 = get_tree().get_first_node_in_group("game")
		if game2 != null:
			# QA-110 (v3.8): the hit-spark call is REMOVED - after a
			# fall from a high area it flashed a white-gold sparkle
			# at the legs, which the user asked to remove. The soft
			# landing dust (QA-085) stays as the only landing effect.
			game2.spawn_dust_fx(global_position + Vector2(0, 31))
	var game3 = get_tree().get_first_node_in_group("game")
	if game3 != null and position.y > game3.map_size.y + 200.0:
		_respawn()


func _apply_aim_and_fire(delta: float) -> void:
	# FIRING lasts exactly one physics frame (GAP-41).
	if weapon_state == WeaponState.FIRING:
		weapon_state = WeaponState.RELOADING if reloading else WeaponState.READY
	# QA-112: no firing while attached to a grapple - the aim stick
	# is the trigger, so the shot is suppressed here and the flick
	# edge is discarded (it must not fire the moment the rope is
	# let go). NOTE: the ladder does not gate firing anywhere in
	# this file, so the grapple gate is explicit here rather than
	# shared; aiming itself is left alone so the player can pre-aim
	# for the release.
	if _grappling:
		_want_fire = false
		_fire_edge = false
		var game_g = get_tree().get_first_node_in_group("game")
		if game_g != null:
			game_g.consume_aim_fire_edge()
		_update_anim()
		return
	# Face the aim direction while aiming, else face the move direction.
	if _aiming:
		aim_angle = _aim_dir.angle()
		if absf(cos(aim_angle)) > 0.15:
			facing = -1 if cos(aim_angle) < 0.0 else 1
	elif _move_axis != 0.0:
		# GAP-08: only the FACING follows movement when not aiming;
		# aim_angle is left untouched so the gun holds its last aim.
		facing = -1 if _move_axis < 0.0 else 1
	_fire_cooldown -= delta
	_grenade_cooldown -= delta
	if reloading:
		weapon_state = WeaponState.RELOADING
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			reloading = false
			weapon_state = WeaponState.READY
			# Reserve transfer (GAP-39): move ammo from reserve to mag.
			mag_ammo += _reload_transfer
			_reload_transfer = 0
		# A flick during reload does nothing - discard the edge so it
		# cannot fire a shot the moment the reload finishes.
		var game_r = get_tree().get_first_node_in_group("game")
		if game_r != null:
			game_r.consume_aim_fire_edge()
	elif _fire_cooldown <= 0.0:
		# v3.2: firing only happens while aiming (the shot goes where
		# the aim stick points). Automatic weapons fire while the
		# stick is held (_want_fire); semi-auto weapons (pistol,
		# shotgun, sniper) fire ONLY on a fresh flick (_fire_edge),
		# so a quick flick shoots even if the finger is already gone
		# by the time this step runs (QA-027 carry-over).
		var w: Dictionary = WEAPONS[weapon]
		var semi: bool = not bool(w.get("auto", true))
		# Trigger rule: auto fires while held, semi fires ONLY on a
		# fresh flick edge. A held semi-auto must NOT keep shooting
		# (_want_fire alone never fires a semi weapon), and a stale
		# edge must NEVER fire an auto weapon (the edge is only
		# consumed by a shot, so an unconsumed edge would keep an
		# auto weapon shooting forever after the stick is released).
		if (not semi and _want_fire) or (semi and _fire_edge):
			_fire()
			# The shot has consumed the flick (semi) / any stale edge
			# (auto) - one edge, one shot, never more.
			var game_f = get_tree().get_first_node_in_group("game")
			if game_f != null:
				game_f.consume_aim_fire_edge()
	_update_anim()


func _update_anim() -> void:
	if not alive:
		return
	if _jetpacking:
		_play_anim("jetpack")
		_sprite.speed_scale = 1.0
		return
	if not is_on_floor():
		if velocity.y < 0.0:
			_play_anim("jump")
		else:
			_play_anim("fall")
		_sprite.speed_scale = 1.0
		return
	if _want_fire:
		_play_anim("shoot")
		_sprite.speed_scale = 1.0
		return
	if _aiming:
		_play_anim("aim")
		_sprite.speed_scale = 1.0
		return
	if _move_mag > 0.05:
		_play_anim("run")
		# Run cycle speed matches movement speed: slow walk, fast run.
		_sprite.speed_scale = 0.55 + _move_mag * 0.9
		return
	_play_anim("idle")
	_sprite.speed_scale = 1.0


func _update_remote_anim() -> void:
	# Remote players: pick the animation from the synced state.
	# QA-073: jetpack / firing / airborne now come from the snapshot
	# flags ("jet" / "fire" / "air"), not from guessing. The old
	# jetpack guess (velocity.y < -380 and fuel < FUEL_MAX) is gone:
	# a fast fall with a full tank read as a jump, and a jetpack
	# climb at full fuel after a pickup read as neither. A remote
	# player that is firing shows "shoot" (it never could before -
	# firing was not in the payload at all); reloading suppresses
	# the shoot pose, as it does locally.
	if not alive:
		_play_anim("die")
		return
	if _remote_jetpacking:
		_play_anim("jetpack")
		_sprite.speed_scale = 1.0
		return
	if _remote_airborne:
		if velocity.y < -50.0:
			_play_anim("jump")
		elif velocity.y > 50.0:
			_play_anim("fall")
		_sprite.speed_scale = 1.0
		return
	if _remote_firing and not _remote_reloading:
		_play_anim("shoot")
		_sprite.speed_scale = 1.0
		return
	if absf(velocity.x) > 25.0:
		_play_anim("run")
		_sprite.speed_scale = 0.55 + clampf(absf(velocity.x) / SPEED, 0.0, 1.0) * 0.9
		return
	_play_anim("idle")
	_sprite.speed_scale = 1.0


func _play_anim(anim_name: String) -> void:
	if _current_anim == anim_name:
		# Death plays once and stays on the last frame.
		if anim_name == "die":
			return
		if _sprite.is_playing():
			return
	_current_anim = anim_name
	_sprite.play(anim_name)
	# QA-094: the helmet rides at a fixed offset from the sprite,
	# but each animation draws the head at a different height in
	# the frame (jetpack frames sit ~17px low) - move the helmet
	# with the animation. _play_anim is the one choke point for
	# local + remote animation changes. Guarded: _ready calls
	# _play_anim("idle") before the helmet sprite exists.
	if HELMET_Y_BY_ANIM.has(anim_name):
		_helmet_y = float(HELMET_Y_BY_ANIM[anim_name])
		if _helmet_sprite != null:
			# QA-108: reset X as well as Y. The jetpack frames track
			# the helmet side-to-side (HELMET_JETPACK_FRAMES, x -11..+15)
			# and _update_visuals stops overriding it once jetpack ends;
			# only setting .y here left the last jetpack X stuck, so the
			# cap/helmet floated 11-15 px sideways off the head after
			# every landing until the next jetpack.
			_helmet_sprite.position = Vector2(1, _helmet_y)


func _fire() -> void:
	var w: Dictionary = WEAPONS[weapon]
	if mag_ammo <= 0:
		_start_reload()
		return
	_fire_cooldown = float(w["rate"])
	_shots_fired += 1
	mag_ammo -= 1
	weapon_state = WeaponState.FIRING
	var dir := Vector2(cos(aim_angle), sin(aim_angle))
	var muzzle := global_position + _muzzle_origin() + dir * (GUN_LENGTH + 6.0)
	# Recoil accumulation (GAP-40, spec §16): R_n = R_0 + n*K; the
	# accumulated spread widens the group and the gun kick grows.
	_recoil_accum += float(w.get("recoil_k", 0.06))
	var pellets: int = int(w["pellets"])
	for i in pellets:
		var d := dir
		if weapon == 2:
			# Shotgun: fixed 7-pellet spread [-15..15]° (GAP-20, §9).
			d = d.rotated(deg_to_rad(WeaponData.SHOTGUN_SPREAD_DEG[i % 7]))
		elif float(w["spread"]) > 0.0:
			# Other weapons: table spread + accumulated recoil spread.
			# QA-061: the Assault Rifle (weapon 0) is EXCLUDED from
			# the recoil growth - it fires straight no matter how
			# long the trigger is held (its table spread is 0.0
			# too, so this branch is skipped for it entirely; the
			# guard keeps it straight even if the table changes).
			var sp := float(w["spread"])
			if weapon != 0:
				sp += _recoil_accum * 0.5
			d = d.rotated(randf_range(-sp, sp))
		# QA-061: record this pellet's direction deviation from the
		# aim (radians) for the rifle-straightness test. Capped so
		# a long match cannot grow the array without bound.
		shot_devs.append(wrapf(d.angle() - aim_angle, -PI, PI))
		if shot_devs.size() > 200:
			shot_devs.pop_front()
		# Velocity inheritance (GAP-55, spec §20.C): the bullet keeps
		# 0.15 of the shooter's velocity. spawn_bullet carries the
		# full velocity vector; bullet.gd integrates it.
		# QA-106 (v3.8): explosive weapons (the rocket) get NO
		# inheritance - the rocket must leave exactly along the aim
		# direction, straight, even when the shooter is moving.
		var bvel: Vector2 = d * float(w["speed"])
		if not bool(w["explosive"]):
			bvel += velocity * PhysicsConfig.VELOCITY_INHERITANCE
		rpc("spawn_bullet", muzzle, d, float(w["speed"]), int(w["damage"]), weapon, peer_id, _shots_fired * 10 + i, bvel)
	_play_sound(str(w["sound"]))
	_show_muzzle()
	# Weapon feel: velocity kick opposite the shot, camera shake for
	# the heavy weapons, and a visible gun kick (grows with _recoil_accum).
	# QA-075: the kick now scales with the weapon (was a flat 1.0 for
	# every gun, so the rifle kicked as hard as the shotgun): the
	# base is the table recoil / 220 (shotgun 1.0, sniper 0.8, rocket
	# 1.2, rifle 0.14, SMG 0.07, pistol 0.09), plus the accumulated
	# recoil from sustained fire. The kick is visual + the velocity
	# impulse above; it never moves the aim (QA-061: the rifle stays
	# straight however long the trigger is held).
	velocity -= dir * float(w.get("recoil", 0.0))
	add_shake(float(w.get("shake", 0.0)))
	_gun_kick = float(w.get("recoil", 0.0)) / 220.0 + _recoil_accum
	if mag_ammo <= 0:
		_start_reload()


func add_shake(amount: float) -> void:
	_shake_trauma = minf(1.0, _shake_trauma + amount)


func start_reload() -> void:
	# Manual reload (RELOAD button): only when it would do something.
	if not alive or reloading:
		return
	if mag_ammo >= int(WEAPONS[weapon]["mag"]):
		return
	_start_reload()


func reload_progress() -> float:
	if not reloading:
		return 0.0
	var total: float = float(WEAPONS[weapon]["reload"])
	return clampf(1.0 - _reload_timer / total, 0.0, 1.0)


# v3.5 QA-062: the grenade button's loading fill reads this.
# QA-075: the muzzle flash is per-weapon now (was one fixed 1.2x
# sprite for 0.05 s on every gun): heavy weapons flash bigger and
# longer (shotgun 1.6x / 0.08 s, sniper 1.8x / 0.08 s, rocket 2.0x /
# 0.08 s; rifle 1.2x / 0.05 s, pistol 1.0x / 0.05 s), with a random
# rotation and a little scale jitter so a held trigger does not
# strobe the identical sprite. The flash is driven by _muzzle_timer
# (decremented in _update_visuals) instead of one scene-tree timer
# per shot - at 8 shots/s the old code stacked a timer per shot.
# _muzzle_flashes counts every flash for the fire test.
func _show_muzzle() -> void:
	var w: Dictionary = WEAPONS[weapon]
	_muzzle_flashes += 1
	if _muzzle != null:
		var fscale: float = float(w.get("flash", 1.2)) * randf_range(0.9, 1.1)
		_muzzle.scale = Vector2(fscale, fscale)
		_muzzle.rotation = randf() * TAU
	_muzzle_timer = float(w.get("flash_t", 0.05))


func _start_reload() -> void:
	reloading = true
	weapon_state = WeaponState.RELOADING
	_reload_timer = float(WEAPONS[weapon]["reload"])
	# Reserve transfer (GAP-39): how much actually moves into the mag.
	var need: int = int(WEAPONS[weapon]["mag"]) - mag_ammo
	var res: int = int(_reserve.get(weapon, -1))
	if res < 0:
		_reload_transfer = need # infinite reserve (pistol sidearm)
	else:
		_reload_transfer = mini(need, res)
		_reserve[weapon] = res - _reload_transfer
	_play_sound("reload")


func ammo_reserve() -> int:
	# Reserve for the current weapon (-1 = infinite). Used by the HUD.
	return int(_reserve.get(weapon, -1))


func switch_weapon() -> void:
	if not alive or owned_weapons().size() <= 1:
		return
	scoped = false # QA-105: scoping ends when the weapon changes
	var owned: Array = owned_weapons()
	var idx := owned.find(weapon)
	var next_w: int = owned[(idx + 1) % owned.size()]
	# QA-075: switching weapons no longer refills the magazine.
	# The old code set mag_ammo to the new weapon's full mag on
	# every switch, so switching away and back refilled the rifle
	# for free. Each weapon's mag is now remembered across switches
	# (full on pickup / respawn) and restored on switch-back.
	_mag_memory[weapon] = mag_ammo
	# QA-075: a reload in progress loses its reserved ammo if the
	# player switches mid-reload - _start_reload already deducted
	# it from the reserve into _reload_transfer, and the old code
	# just dropped the transfer. Refund it before changing weapon.
	_refund_reload()
	weapon = next_w
	mag_ammo = int(_mag_memory.get(next_w, int(WEAPONS[next_w]["mag"])))
	reloading = false
	weapon_state = WeaponState.READY
	# QA-075: the gun dips briefly on switch (visual only - firing
	# is never blocked; SWITCH-WHILE-FIRING still shoots straight
	# through the switch). Remote copies dip too (see
	# receive_move_snapshot).
	_switch_dip_timer = 0.15
	# v3.2: a pending semi-auto flick belongs to the old weapon - drop
	# it so switching cannot fire a shot nobody asked for.
	var game_sw = get_tree().get_first_node_in_group("game")
	if game_sw != null:
		game_sw.consume_aim_fire_edge()
	_update_gun_texture()
	_play_sound("click")


# QA-075: magazine memory + reload refund (see switch_weapon).
func _reset_mag_memory() -> void:
	_mag_memory.clear()
	for id in WEAPONS.keys():
		_mag_memory[id] = int((WEAPONS[id] as Dictionary).get("mag", 30))


func _refund_reload() -> void:
	if _reload_transfer > 0:
		var res: int = int(_reserve.get(weapon, -1))
		if res >= 0:
			_reserve[weapon] = res + _reload_transfer
		_reload_transfer = 0
	_reload_timer = 0.0


func owned_weapons() -> Array:
	# Rifle + pistol are always owned (starting loadout); the rest
	# come from weapon pickups.
	var list: Array = [0, 5]
	if _owned_extra.has(1):
		list.append(1)
	if _owned_extra.has(2):
		list.append(2)
	if _owned_extra.has(3):
		list.append(3)
	if _owned_extra.has(4):
		list.append(4)
	return list


func throw_grenade() -> void:
	if not alive or grenades <= 0 or _grenade_cooldown > 0.0:
		return
	_grenade_cooldown = 0.5
	grenades -= 1
	var dir := Vector2(cos(aim_angle), sin(aim_angle))
	if not _aiming:
		dir = Vector2(facing, -0.4).normalized()
	# QA-091 (v3.7, GRENADE_SPEC §2): the throw carries ~40% of the
	# thrower's velocity, so a jetpack throw keeps its momentum
	# instead of always leaving at the same flat arc.
	rpc("spawn_grenade", global_position + Vector2(0, -7), dir, peer_id, velocity)
	_play_sound("click")


@rpc("any_peer", "call_local")
func spawn_bullet(pos: Vector2, dir: Vector2, speed: float, damage: int, kind: int, owner_id: int, shot_no: int, bvel: Vector2 = Vector2.INF) -> void:
	# Host-authoritative shooting (v2.4): the server validates every
	# shot's fire rate and ammunition before simulating it. Only the
	# server's simulation can deal damage, so a rejected shot can
	# never hurt anyone - the shooter's local copy is visual only.
	if multiplayer.is_server():
		var sender := multiplayer.get_remote_sender_id()
		if sender != 0 and sender != multiplayer.get_unique_id():
			var game = get_tree().get_first_node_in_group("game")
			var shooter = game.players_node.get_node_or_null(str(sender)) if game != null else null
			var rep_mag: int = shooter.mag_ammo if shooter != null else 0
			if game == null or not game.shooting_sync.validate_shot(sender, kind, rep_mag):
				return
	var game2 = get_tree().get_first_node_in_group("game")
	if game2 == null:
		return
	var b = game2.obtain_bullet()
	var vel: Vector2 = bvel if bvel != Vector2.INF else dir * speed
	b.setup(pos, dir, speed, damage, kind, owner_id,
		bool(WEAPONS[kind]["explosive"]),
		# QA-109 (v3.8): rocket blast 170 -> 120, same ~29% cut as the
		# grenade (QA-101) - the user said the missile blast is huge
		# too. Damage 70, speed 450, life 2.5, gravity 0 unchanged.
		# The explosion FX scale with the radius, so the fireball,
		# flash, debris, particles and shake all shrink to match.
		# Barrels keep their own 170 (PhysicsConfig.BARREL_BLAST_RADIUS).
		120.0 if bool(WEAPONS[kind]["explosive"]) else 0.0,
		float(WEAPONS[kind].get("life", 1.4)),
		shot_no, vel, float(WEAPONS[kind].get("gravity", 0.0)))
	if b.get_parent() == null:
		game2.bullets_node.add_child(b)


@rpc("any_peer", "call_local")
func spawn_grenade(pos: Vector2, dir: Vector2, owner_id: int, thrower_vel: Vector2 = Vector2.ZERO) -> void:
	var node = get_tree().get_first_node_in_group("game")
	if node == null:
		return
	var g = GRENADE_SCENE.instantiate()
	g.name = "g_%d_%d" % [owner_id, Time.get_ticks_msec()]
	g.position = pos
	g.throw_dir = dir
	g.thrower_vel = thrower_vel # QA-091: 40% inherited in grenade.gd
	g.owner_id = owner_id
	node.grenades_node.add_child(g)


@rpc("any_peer")
func take_damage(amount: int, from_id: int) -> void:
	# Host-authoritative health (v2.4): only the host (peer 1) may
	# inflict damage - a client calling this directly is ignored.
	# The host routes damage to the victim's owning peer (see
	# bullet.gd / game.gd), so the call always arrives from the host.
	# Kept as the simple entry (lava, tests); bullets use take_hit
	# so knockback + damage event ids travel with the hit (GAP-43/46).
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_apply_damage(amount, from_id, Vector2.ZERO, 0.0, -1)


@rpc("any_peer")
func take_hit(amount: int, from_id: int, dir: Vector2, knockback: float, event_id: int) -> void:
	# Host-authoritative hit with knockback + unique event id
	# (GAP-43/46, spec §17.5/§17.8). A re-sent or double-routed
	# damage RPC with an already-seen event id is ignored.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if event_id >= 0:
		if _seen_damage_ids.has(event_id):
			return
		_seen_damage_ids.append(event_id)
		while _seen_damage_ids.size() > 64:
			_seen_damage_ids.pop_front()
	_apply_damage(amount, from_id, dir, knockback, event_id)


static func hit_region(hit_pos: Vector2, player_pos: Vector2) -> String:
	# Separate hit regions from the hit height (GAP-25/42, spec §11/§17.3).
	# Arms fold into torso: the capsule cannot distinguish arms, so
	# the documented deviation is head 1.5 / torso 1.0 / legs 0.75.
	var rel_y := hit_pos.y - player_pos.y
	if rel_y < PhysicsConfig.HIT_HEAD_Y:
		return "head"
	if rel_y > PhysicsConfig.HIT_LEGS_Y:
		return "legs"
	return "torso"


static func calculate_damage(base: int, region: String, distance: float, weapon_id: int) -> int:
	# D_final = D_base x M_region x M_distance x M_weapon x M_armor
	# (GAP-42, spec §17.2/§17.3). M_armor is 1.0 until armor exists.
	var m_region: float = float(PhysicsConfig.REGION_MULT.get(region, 1.0))
	var m_dist := 1.0
	if distance > PhysicsConfig.DAMAGE_FALLOFF_START:
		var w: Dictionary = WeaponData.get_weapon(weapon_id)
		var max_range := float(w.get("speed", 900.0)) * float(w.get("life", 1.0))
		if max_range > PhysicsConfig.DAMAGE_FALLOFF_START:
			var f := clampf((distance - PhysicsConfig.DAMAGE_FALLOFF_START) / (max_range - PhysicsConfig.DAMAGE_FALLOFF_START), 0.0, 1.0)
			# QA-075: the falloff floor is per-weapon now (was a
			# flat 0.7x for every gun): the sniper keeps 0.9x at
			# max range, the shotgun drops to 0.5x, the SMG to
			# 0.6x, the pistol to 0.65x. Close-range damage is
			# unchanged (falloff only starts past 400 px).
			var falloff_min: float = float(w.get("falloff_min", PhysicsConfig.DAMAGE_FALLOFF_MIN))
			m_dist = lerpf(1.0, falloff_min, f)
	var m_weapon: float = float(WeaponData.get_weapon(weapon_id).get("damage_mult", 1.0))
	return int(round(float(base) * m_region * m_dist * m_weapon))


func _apply_damage(amount: int, from_id: int, dir: Vector2, knockback: float, event_id: int) -> void:
	# Single place where health actually changes (spec §17.8).
	# Guards: death happens only once per life (life_state, GAP-44).
	if life_state != LifeState.ALIVE:
		return
	if _spawn_protect_timer > 0.0:
		return
	# QA-112: a shield absorbs ALL damage - only the health loss is
	# blocked. Knockback, hit flash, shake and sound still play.
	if shield_timer > 0.0:
		amount = 0
	health -= amount
	if amount > 0:
		_regen_timer = HEALTH_REGEN_DELAY # QA-120: damage restarts the regen wait
	# Per-weapon victim knockback (GAP-46): a velocity add, so
	# move_and_slide resolves it against collision next frame -
	# knockback never bypasses collision (spec §17.8).
	if knockback > 0.0 and dir != Vector2.ZERO:
		velocity += dir * knockback
	_hit_flash_timer = 0.09
	add_shake(0.25) # victim shake on damage (GAP-54, spec §19)
	_play_sound("hurt")
	if health <= 0:
		health = 0
		alive = false
		life_state = LifeState.DYING
		_dying_timer = 0.4
		deaths += 1
		_respawn_timer = 3.0
		# QA-069: a death is a score change - force a snapshot at
		# once so every peer's scoreboard sees it now, not on the
		# next 30/s tick (same treatment respawn already gets).
		_send_move_snapshot(true)
		_collision_shape.set_deferred("disabled", true)
		_anim_locked = true
		_play_anim("die")
		_stop_jetpack_sound()
		_play_sound("death")
		# Survival: dead for the rest of this round (revived by the
		# host's round reset). Last Man Standing: no respawn at all.
		var game2 = get_tree().get_first_node_in_group("game")
		if game2 != null and int(game2.game_mode) == 2:
			_round_dead = true
		# Kill credit is the HOST's job (it decided the damage): the
		# server credits the killer when it deals the lethal hit (see
		# bullet.gd _hit_player / game.gd request_explosion). Nothing
		# is credited here, so a client can never award itself kills.


@rpc("any_peer")
func take_explosion_damage(pos: Vector2, radius: float, damage: int, from_id: int, event_id: int = -1) -> void:
	# Host-authoritative, like take_damage: only the host may call.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if life_state != LifeState.ALIVE:
		return
	if _spawn_protect_timer > 0.0:
		return
	if event_id >= 0:
		if _seen_damage_ids.has(event_id):
			return
		_seen_damage_ids.append(event_id)
		while _seen_damage_ids.size() > 64:
			_seen_damage_ids.pop_front()
	var dist := global_position.distance_to(pos)
	if dist > radius:
		return
	# Smooth falloff (GAP-22, spec §10): D = Dmax * (1-u^2)^2, 0 at edge.
	var u := dist / radius
	var amount := int(round(damage * pow(1.0 - u * u, 2.0)))
	# Knockback (GAP-23): J = K*(1-u)^2, dV = J/m, vertical multiplier Ky.
	var j := PhysicsConfig.EXPLOSION_KNOCKBACK * pow(1.0 - u, 2.0)
	var dir := (global_position - pos).normalized()
	# Radial knockback dV = J/m plus an extra upward blast (Ky).
	var kb := dir * (j / PhysicsConfig.MASS) + Vector2(0, -j * PhysicsConfig.EXPLOSION_VERTICAL_MULT)
	velocity += kb
	add_shake(0.5) # victim shake on explosion (GAP-54)
	# Damage + death via the single damage path (no double counting:
	# the knockback above is applied here, _apply_damage gets 0).
	_apply_damage(amount, from_id, Vector2.ZERO, 0.0, -1)


@rpc("any_peer")
func add_kill() -> void:
	# Only the host may award a kill (it decided the lethal hit).
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	kills += 1
	# QA-069: a kill is a score change - force a snapshot at once
	# so every peer's scoreboard sees it now, not on the next 30/s
	# tick. Offline / no peers, _send_move_snapshot is a no-op.
	_send_move_snapshot(true)
	_play_sound("pickup")


# Phase 4 - accuracy: one trigger pull counts as a hit once, however
# many of its pellets land (a shotgun's 7 pellets are one shot, not
# seven). shot_no is _shots_fired * 10 + pellet index, so the key is
# shot_no / 10. Called by the host only.
func record_hit(shot_no: int) -> void:
	var key := shot_no / 10
	if _hit_shot_keys.has(key):
		return
	_hit_shot_keys.append(key)
	_shots_hit += 1


# Phase 4 - hitmarker: the host confirms each hit to the shooter
# (damage dealt, where, and whether it was lethal). The game reads
# _hitmark_seq on the local player and shows the marker + damage
# number. Only the host may send this.
@rpc("any_peer")
func hit_confirm(dmg: int, pos: Vector2, lethal: bool) -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_hitmark_seq += 1
	_hitmark_dmg = dmg
	_hitmark_pos = pos
	_hitmark_lethal = lethal
	_hitmark_time = Time.get_ticks_msec() / 1000.0


@rpc("any_peer")
func give_pickup(kind: int) -> void:
	# Only the host hands out pickups (pickup.gd enforces this); a
	# client calling this directly is ignored.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	# 1 SMG, 2 Shotgun, 3 Sniper, 4 Rocket, 5 Health, 6 Grenades
	if kind >= 1 and kind <= 4:
		if not _owned_extra.has(kind):
			_owned_extra.append(kind)
		# QA-075: picking up a weapon while reloading the old one
		# must not eat the pending reload's ammo (same refund as
		# switch_weapon - the transfer is returned to the reserve).
		_refund_reload()
		weapon = kind
		mag_ammo = int(WEAPONS[kind]["mag"])
		_mag_memory[kind] = mag_ammo
		_reserve[kind] = int(RESERVE_DEFAULT.get(kind, 0))
		reloading = false
		weapon_state = WeaponState.READY
		_update_gun_texture()
	elif kind == 5:
		health = mini(100, health + 50)
	elif kind == 6:
		grenades = mini(4, grenades + 2)
	elif kind >= 7 and kind <= 13:
		# QA-112: Skyfall power-ups (7-13) - kinds 1-6 above are unchanged.
		apply_powerup(kind)
	_play_sound("pickup")


# QA-119 (v3.11): 7 kinds, 7-13 - Health Potion (7), Shield (8),
# Speed Boost (9), Jetpack Boost (10), Wind Blast (11), Thunder
# Strike (12), Invisibility (13). Pickup STORES the power-up in a
# slot - it NEVER activates on pickup (user rule, 2026-11-20
# ~21:00, IMMEDIATE). Every kind goes to a free slot (max 3,
# distinct kinds); a duplicate kind, or full slots, consumes the
# pickup with no effect. The player activates by tapping the slot
# button (see activate_slot). Timed kinds (8, 9, 10, 13): ONE
# active at a time; a carrier cannot activate one while carrying
# the flag. Instant kinds (7, 11, 12) fire at once on tap.
# The old auto-activate / instant-on-pickup behaviour is GONE.
func apply_powerup(kind: int) -> void:
	if kind < 7 or kind > 13:
		return
	if stored_boosts.has(kind):
		_pu_feed("Already carrying %s" % PU_NAMES.get(kind, "power-up"))
		return # same kind already held: consumed, no extra effect
	if stored_boosts.size() >= MAX_STORED_BOOSTS:
		_pu_feed("Slots full — power-up lost")
		return # slots full: consumed, no effect
	stored_boosts.append(kind)
	_play_sound("pickup")


# QA-132: power-up feedback — a lost pickup or a fired instant
# used to fail silently (no message, no visible effect). The feed
# goes through the game scene, into the same top-left message area
# as every other notice. No game node (menu / unit test) = silent.
func _pu_feed(text: String) -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("_ctf_feed"):
		game._ctf_feed(text, Color(1.0, 0.8, 0.2))


# Activate the power-up waiting in slot `idx` (HUD slot-button tap).
# Timed kinds (8, 9, 10, 13): ONE active at a time, and a carrier
# CANNOT activate one while carrying the flag (the carrier rule
# wins - the tap does nothing and the power-up stays in its slot).
# Instant kinds (7 health, 11 wind, 12 thunder) fire at once and
# work even while a timed boost is active or the flag is carried.
func activate_slot(idx: int) -> bool:
	if idx < 0 or idx >= stored_boosts.size():
		return false
	var kind: int = stored_boosts[idx]
	if kind in TIMED_BOOST_KINDS:
		if active_boost_kind != 0:
			return false # one active boost at a time
		if carrying_flag != 0:
			return false # carrier rule wins over the boost
		stored_boosts.remove_at(idx)
		_activate_boost(kind)
		return true
	stored_boosts.remove_at(idx)
	_apply_instant(kind)
	return true


# Fire an instant power-up. Health restores 50 HP (QA-132: was
# 35 — it competes with 4 HP/s regen now); Wind Blast pushes
# nearby enemies away (no damage); Thunder Strike hits the nearest
# enemy in range. Wind/thunder damage is host-authoritative: a
# client asks the host with an RPC (in the sim the peer IS the host).
# QA-132: wind + thunder announce themselves in the feed, so the
# player sees the activation even when no enemy is in range.
func _apply_instant(kind: int) -> void:
	match kind:
		7:
			health = mini(100, health + 50)
			_fx_flash_kind = 7
			_fx_flash_timer = 0.8
			_play_sound("heal")
		11:
			_fx_flash_kind = 11
			_fx_flash_timer = 0.8
			_play_sound("wind")
			_pu_feed("Wind Blast!")
			if multiplayer.is_server():
				_do_wind_blast()
			else:
				rpc_id(1, "request_wind_blast")
		12:
			_fx_flash_kind = 12
			_fx_flash_timer = 0.8
			# Sound plays inside show_thunder_strike_fx (once per
			# peer, via the host RPC) — not here, or the activator
			# would hear the crack twice.
			_pu_feed("Thunder Strike!")
			if multiplayer.is_server():
				_do_thunder_strike()
			else:
				rpc_id(1, "request_thunder_strike")


@rpc("any_peer", "call_local")
func request_wind_blast() -> void:
	# Only the host runs it, and only for the player that asked
	# (the sender must be this node's owner).
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	_do_wind_blast()


@rpc("any_peer", "call_local")
func request_thunder_strike() -> void:
	if not multiplayer.is_server():
		return
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != get_multiplayer_authority():
		return
	_do_thunder_strike()


# Host only: push every living enemy within WIND_BLAST_RADIUS away.
# Amount 0 = no damage; the knockback still plays (see
# _apply_damage), and a shield does not stop the push.
func _do_wind_blast() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	for other in game.players_node.get_children():
		if other == self or not other.is_in_group("players") or not other.alive:
			continue
		if other.team == team:
			continue
		var o: Node2D = other
		if o.global_position.distance_to(global_position) > WIND_BLAST_RADIUS:
			continue
		var dir: Vector2 = (o.global_position - global_position).normalized()
		other.take_hit(0, peer_id, dir, WIND_BLAST_KNOCKBACK, game.next_damage_event_id())


# Host only: lightning strikes the nearest living enemy within
# THUNDER_RANGE (else the activator's own feet - a wasted strike),
# damaging every enemy inside THUNDER_RADIUS of the strike point.
# Shield absorbs the damage; the bolt visual is drawn by the game
# (show_thunder_strike_fx, added in the game.gd step).
func _do_thunder_strike() -> void:
	var game := get_tree().get_first_node_in_group("game")
	if game == null:
		return
	var target: Node2D = null
	var best := THUNDER_RANGE
	for other in game.players_node.get_children():
		if other == self or not other.is_in_group("players") or not other.alive:
			continue
		if other.team == team:
			continue
		var o: Node2D = other
		var d: float = o.global_position.distance_to(global_position)
		if d < best:
			best = d
			target = o
	var strike_pos := global_position
	if target != null:
		strike_pos = target.global_position
	if game.has_method("show_thunder_strike_fx"):
		game.rpc("show_thunder_strike_fx", strike_pos)
	for other in game.players_node.get_children():
		if other == self or not other.is_in_group("players") or not other.alive:
			continue
		if other.team == team:
			continue
		var o: Node2D = other
		if o.global_position.distance_to(strike_pos) > THUNDER_RADIUS:
			continue
		var dir: Vector2 = (o.global_position - strike_pos).normalized()
		other.take_hit(THUNDER_DAMAGE, peer_id, dir, 150.0, game.next_damage_event_id())


# Start a timed boost now: set its timer (and refill the fuel for
# the jetpack boost) and mark it active.
func _activate_boost(kind: int) -> void:
	active_boost_kind = kind
	match kind:
		8:
			shield_timer = SHIELD_DURATION
			_play_sound("shield")
		9:
			speed_timer = SPEED_DURATION
			_play_sound("speed")
		10:
			jetpack_boost_timer = JETPACK_BOOST_DURATION
			fuel = FUEL_MAX
			_play_sound("jetpack_boost")
		13:
			invisibility_timer = INVISIBILITY_DURATION
			_play_sound("invis")


# Tick the boost timers every physics frame. When the active boost
# runs out it just ends - stored power-ups NEVER start by
# themselves (tap-to-activate only, QA-119). A carrier's stored
# boost waits in its slot until the player taps it after the drop.
func _tick_boost_timers(delta: float) -> void:
	shield_timer = maxf(0.0, shield_timer - delta)
	speed_timer = maxf(0.0, speed_timer - delta)
	jetpack_boost_timer = maxf(0.0, jetpack_boost_timer - delta)
	invisibility_timer = maxf(0.0, invisibility_timer - delta)
	if _fx_flash_timer > 0.0:
		_fx_flash_timer = maxf(0.0, _fx_flash_timer - delta)
		if _fx_flash_timer <= 0.0:
			_fx_flash_kind = 0
	if active_boost_kind == 0:
		return
	var t := 0.0
	match active_boost_kind:
		8:
			t = shield_timer
		9:
			t = speed_timer
		10:
			t = jetpack_boost_timer
		13:
			t = invisibility_timer
	if t <= 0.0:
		active_boost_kind = 0


# QA-120: slow health regen. Called every physics frame next to
# _tick_boost_timers. Health restores only after
# HEALTH_REGEN_DELAY seconds without taking damage (the timer is
# restarted in _apply_damage on every real health loss).
func _tick_health_regen(delta: float) -> void:
	if not alive or health >= 100:
		return
	if _regen_timer > 0.0:
		_regen_timer = maxf(0.0, _regen_timer - delta)
		return
	health = mini(100, health + HEALTH_REGEN_RATE * delta)


# Survival round reset: the host tells every peer to respawn its own
# player for the next round (new positions, full health).
@rpc("any_peer", "call_local")
func reset_round_remote() -> void:
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_round_dead = false
	_respawn()


func _respawn() -> void:
	# Validated respawn (GAP-45, spec §17.7): the spawn must be free
	# of walls/ground/obstacles, clear of live enemies (>150 px) and
	# inside the map. If no spawn is valid, retry in 0.5 s instead of
	# teleporting into a wall or a camper.
	var game = get_tree().get_first_node_in_group("game")
	var spot := Vector2.INF
	if game != null:
		spot = game.get_valid_spawn_point(player_index, peer_id)
	if spot == Vector2.INF:
		life_state = LifeState.RESPAWNING
		_respawn_retry_timer = PhysicsConfig.RESPAWN_RETRY_DELAY
		return
	health = 100
	alive = true
	life_state = LifeState.ALIVE
	fuel = FUEL_MAX
	_fuel_delay_timer = 0.0
	_spawn_protect_timer = SPAWN_PROTECTION
	weapon = 0
	_owned_extra.clear()
	_reserve = RESERVE_DEFAULT.duplicate()
	_reset_mag_memory() # QA-075: respawn refills every remembered mag
	mag_ammo = int(WEAPONS[0]["mag"])
	reloading = false
	weapon_state = WeaponState.READY
	_reload_transfer = 0
	_reload_timer = 0.0
	_recoil_accum = 0.0
	_jet_ramp_t = 0.0 # QA-074: no thrust carries over a respawn
	scoped = false # QA-105: no scope carries over a respawn
	_jet_thrust_factor = 0.0
	_muzzle_timer = 0.0 # QA-075: no flash carries over a respawn
	_switch_dip_timer = 0.0
	_anim_locked = false
	_fast_fall = false
	_stick_up_prev = false
	_stick_up_armed = true
	_jump_cut_armed = false
	_round_dead = false
	_shake_trauma = 0.0
	_gun_kick = 0.0
	# QA-112: a fresh life starts with no boosts, no flag, no wind,
	# no ladder. carrying_flag is cleared here, not on death, so
	# game.gd can still read who dropped the flag while the player
	# is dead (the flag drop itself is game.gd's job).
	shield_timer = 0.0
	speed_timer = 0.0
	invisibility_timer = 0.0
	jetpack_boost_timer = 0.0
	active_boost_kind = 0
	stored_boosts.clear()
	_regen_timer = 0.0 # QA-120: no regen wait carries over a respawn
	_fx_flash_kind = 0 # QA-119: no effect flash carries over a respawn
	_fx_flash_timer = 0.0
	modulate = Color.WHITE # QA-119: no invisibility carries over a respawn
	carrying_flag = 0
	wind_force = Vector2.ZERO
	_on_ladder = false
	_ladder_rect = Rect2()
	_ladder_armed = true
	# QA-112: a fresh life starts with no rope, no wall-jump chain,
	# no line state either.
	_grappling = false
	_grapple_point = Vector2.ZERO
	_grapple_cooldown = 0.0
	_wall_jumps_used = 0
	_on_jetpack_line = false
	# Discard a stale pending shot so a finger held while dead
	# cannot fire a shot the instant we respawn.
	var game0 = get_tree().get_first_node_in_group("game")
	if game0 != null:
		game0.consume_aim_fire_edge()
	position = spot
	velocity = Vector2.ZERO
	# QA-053: respawn is a teleport - force a snapshot at once so the
	# remote copy learns the new spawn immediately (and never keeps
	# interpolating toward the old death position).
	_send_move_snapshot(true)
	_collision_shape.set_deferred("disabled", false)
	_update_gun_texture()
	_play_anim("idle")
	_play_sound("spawn")
	if _camera != null:
		_camera.reset_smoothing()
		_cam_anchor = spot
		_cam_anchor_init = true


func _update_visuals(delta: float) -> void:
	if _sprite == null:
		return
	# QA-075: the muzzle flash and the switch dip are timers, not
	# scene-tree timers - they tick down here every render frame,
	# for the local player and for remote copies alike.
	_muzzle_timer = maxf(0.0, _muzzle_timer - delta)
	_switch_dip_timer = maxf(0.0, _switch_dip_timer - delta)
	if _muzzle != null:
		_muzzle.visible = alive and _muzzle_timer > 0.0
	# QA-071b: keep the 1.20x sprite scale; only flip x for facing.
	_sprite.scale = Vector2(PLAYER_SCALE * float(facing), PLAYER_SCALE)
	# QA-094: while jetpacking, track the head per frame - the
	# flying pose sways side-to-side (see HELMET_JETPACK_FRAMES).
	# Other animations use the per-animation height set in
	# _play_anim. Runs for local and remote copies alike.
	if _current_anim == "jetpack" and _helmet_sprite != null:
		var f := clampi(_sprite.frame, 0, HELMET_JETPACK_FRAMES.size() - 1)
		_helmet_sprite.position = HELMET_JETPACK_FRAMES[f]
	# Gun follows the aim angle exactly; flips upright when aiming left.
	# (Rotation is set below together with the reload/switch dip.)
	# QA-127 (v3.11): the gun is HELD - its GRIP sits in the hands
	# (_hand_anchor: per-animation, per-frame for idle/jetpack) and
	# the gun rotates to the aim angle around the grip. The grip
	# offset is per-weapon (WEAPON_GRIP): the gun's centre sits
	# ahead of the hands by the grip-to-centre distance, rotated by
	# the aim angle, so the barrel points where the player aims and
	# the stock stays behind the hands. When aiming left the gun
	# texture flips vertically (scale.y -1) so it stays upright -
	# the grip's vertical offset flips with it.
	var flip_y := -1.0 if cos(aim_angle) < 0.0 else 1.0
	_gun.scale = Vector2(_gun_base_scale, _gun_base_scale * flip_y)
	# Gun kick: the barrel jumps back along the aim direction right
	# after a shot and settles back (decays in _physics_process).
	# QA-075: the gun also dips while reloading (5 px) and briefly
	# after a weapon switch (6 px, fading over 0.15 s) - visual
	# only, it never blocks firing or aiming. The dip tilts the gun
	# down a touch so the lower-raise reads as a motion, not a snap.
	# QA-108: cap the visual kick at 6 px. _recoil_accum only decays
	# while NOT firing, so during a long trigger hold it grows without
	# bound and every shot re-assigns _gun_kick = recoil/220 + accum -
	# after ~100 rounds the gun sat 60+ px behind the hands, floating
	# detached in the air (a second rifle visibly floating behind the
	# player while running + firing). The kick is visual only and never
	# moves the aim (QA-061); 6 px reads as recoil and keeps the gun
	# in the hands. The spread model (_recoil_accum) is untouched.
	var kick := Vector2(cos(aim_angle), sin(aim_angle)) * minf(_gun_kick * 8.4, 6.0)
	var dip := 0.0
	if reloading:
		dip = 5.0
	if _switch_dip_timer > 0.0:
		dip = maxf(dip, 6.0 * (_switch_dip_timer / 0.15))
	var grip: Vector2 = WEAPON_GRIP.get(weapon, Vector2(0.34, 1.5))
	var grip_local := Vector2((grip.x - 0.5) * GUN_LENGTH, grip.y * flip_y)
	_gun.position = _muzzle_origin() - grip_local.rotated(aim_angle) - kick + Vector2(0, dip)
	_gun.rotation = aim_angle + dip * 0.008
	# Jetpack flame (GAP-06, spec §5): tied to the REAL thrust state,
	# never to the animation name. Off = hidden, thrusting = visible
	# with length by thrust, low fuel = blink, empty/descending = gone.
	# QA-074: the length also follows the thrust ramp
	# (_jet_thrust_factor), so the flame grows as the jetpack spools
	# up instead of appearing at full length on the first frame.
	if _flame != null:
		var thrusting := _jetpacking and fuel > 0.0
		_flame.visible = thrusting and alive
		if thrusting:
			var frac := (0.6 + 0.6 * clampf(absf(velocity.y) / MAX_JET_RISE, 0.0, 1.0)) * (0.7 + 0.3 * _jet_thrust_factor)
			# QA-119: Jetpack Boost has NO effect image in either
			# pack (and Gemini is 429-rate-limited, so no generated
			# one) — the boost reads through a bigger flame instead:
			# 1.5x while jetpack_boost_timer runs.
			var boost_mult := 1.5 if jetpack_boost_timer > 0.0 else 1.0
			_flame.scale = Vector2((14.0 / 32.0) * (1.0 + 0.15 * sin(Time.get_ticks_msec() / 40.0)) * boost_mult, (29.0 / 64.0) * frac * boost_mult)
			_flame.position = Vector2(-16.0 * _flame.scale.x, 22.0)
			if fuel < PhysicsConfig.FUEL_LOW_WARN:
				_flame.modulate = Color(1.0, 1.0, 1.0, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0))
			else:
				_flame.modulate = Color.WHITE
	_gun.visible = alive
	# Camera shake: trauma decays in _physics_process; the offset is
	# trauma squared so small shakes stay subtle and big ones punch.
	if _camera != null:
		var s := _shake_trauma * _shake_trauma * 16.0
		_camera.offset = Vector2(randf_range(-s, s), randf_range(-s, s)) if s > 0.05 else Vector2.ZERO
	_helmet_sprite.visible = alive
	_ring.visible = alive
	# QA-112: the shield ring shows while the shield boost is up
	# (local player and remote copies alike - the timer is synced).
	if _shield_ring != null:
		_shield_ring.visible = alive and shield_timer > 0.0
	# QA-119: invisibility is 90% - the player stays ~10% visible
	# (INVISIBILITY_ALPHA). The LOCAL player always sees themself
	# fully; teammates see a faint 40% outline; enemies see 10%.
	# modulate fades the whole body - sprite, gun, helmet, ring,
	# name label and HP bar - so nothing gives the position away.
	if alive and invisibility_timer > 0.0:
		if is_local_player():
			modulate = Color(1, 1, 1, 1)
		elif _is_same_team_as_local():
			modulate = Color(1, 1, 1, 0.4)
		else:
			modulate = Color(1, 1, 1, INVISIBILITY_ALPHA)
	else:
		modulate = Color.WHITE
	# QA-119: active power-up effect layers (assets/powerups_effects/).
	# Timed boosts show while their timer runs; instant kinds flash
	# for 0.8 s after activation. The wind whirlpool is a flat disc,
	# so it spins fast and stays faded (0.55 alpha).
	if _fx_shield != null:
		_fx_shield.visible = alive and shield_timer > 0.0
		var pulse := 1.0 + 0.06 * sin(Time.get_ticks_msec() / 180.0)
		_fx_shield.scale = Vector2(0.30 * pulse, 0.30 * pulse)
	if _fx_speed != null:
		_fx_speed.visible = alive and speed_timer > 0.0
	if _fx_health != null:
		_fx_health.visible = alive and _fx_flash_kind == 7 and _fx_flash_timer > 0.0
		_fx_health.modulate = Color(1, 1, 1, clampf(_fx_flash_timer / 0.8, 0.0, 1.0))
	if _fx_wind != null:
		_fx_wind.visible = alive and _fx_flash_kind == 11 and _fx_flash_timer > 0.0
		_fx_wind.rotation = Time.get_ticks_msec() / 1000.0 * 6.0
		_fx_wind.modulate = Color(1, 1, 1, 0.55 * clampf(_fx_flash_timer / 0.8, 0.0, 1.0))
	if _fx_thunder != null:
		_fx_thunder.visible = alive and _fx_flash_kind == 12 and _fx_flash_timer > 0.0
		_fx_thunder.modulate = Color(1, 1, 1, clampf(_fx_flash_timer / 0.8, 0.0, 1.0))
	if _fx_invis != null:
		_fx_invis.visible = alive and invisibility_timer > 0.0
		_fx_invis.modulate = Color(1, 1, 1, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0))
	_name_label.visible = alive
	# QA-071: keep the label in sync if the name/colour was set after
	# _ready (remote joins set fields before add_child, so this is
	# normally a no-op - it only guards the late-assignment case).
	if _name_label.text != player_name:
		_name_label.text = player_name
	if _name_label.get_theme_color("font_color") != player_color:
		_name_label.add_theme_color_override("font_color", player_color)
	_hp_bg.visible = alive
	_hp_fg.visible = alive
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		# QA-086 + QA-092 (v3.7): the hit flash is a shader-driven
		# red flash over the WHOLE player - body, gun and helmet
		# share one flash material, amount fading 1 -> 0 over the
		# 0.09 s timer (was a modulate tint on the body sprite only,
		# then on all three). Purely visual; the timer and the
		# damage path are unchanged.
		if _hit_flash_mat != null:
			_hit_flash_mat.set_shader_parameter("flash_amount", clampf(_hit_flash_timer / 0.09, 0.0, 1.0))
		if _hit_flash_timer <= 0.0 and _hit_flash_mat != null:
			_hit_flash_mat.set_shader_parameter("flash_amount", 0.0)
	elif _spawn_protect_timer > 0.0:
		# Spawn protection: blink so other players can see it.
		_sprite.modulate = Color(1, 1, 1, 0.55 + 0.35 * sin(Time.get_ticks_msec() / 90.0))
		_gun.modulate = _sprite.modulate
		_helmet_sprite.modulate = _sprite.modulate
	else:
		_sprite.modulate = Color.WHITE
		_gun.modulate = Color.WHITE
		_helmet_sprite.modulate = Color.WHITE
	_hp_fg.size.x = 53.0 * clampf(float(health) / 100.0, 0.0, 1.0)
	_hp_fg.color = Color(0.3, 0.9, 0.3) if health > 30 else Color(0.9, 0.25, 0.2)
	# Team colour ring tint.
	if team == 0:
		_ring.color = Color(0.95, 0.25, 0.2, 0.55)
	elif team == 1:
		_ring.color = Color(0.2, 0.5, 0.95, 0.55)
	else:
		_ring.color = Color(player_color.r, player_color.g, player_color.b, 0.55)


func _play_sound(sound_name: String) -> void:
	if _audio != null:
		_audio.play(sound_name)


func _start_jetpack_sound() -> void:
	if _audio != null:
		_audio.start_jetpack()


func _stop_jetpack_sound() -> void:
	if _audio != null:
		_audio.stop_jetpack()


# --- QA-112 (v3.9) movement acceptance tests (--movement-test) ---
# In-process checks for the Skyfall grapple / wall-jump / jetpack-line
# work above, in the same step style as game.gd's --joystick-test
# (setup runs once, then after `wait` seconds the check runs and the
# result prints as "MOVETEST <name>: PASS/FAIL - <detail>").
# Run: xvfb-run -a godot --path . -- --auto-host --map=5 --movement-test
# (and --map=0 for the non-Skyfall no-op run). Flag-gated and local
# player only - nothing here runs in a real match. The test drives
# the REAL _update_grapple / _apply_movement / _apply_aim_and_fire
# paths: _movetest_pre_tick runs the step machine at the top of
# _physics_process (before _tick_boost_timers, so a forced carrier
# flag is already set when the boost timers tick - game.gd rewrites
# carrying_flag every frame from its own CTF state), and
# _movetest_apply_input overrides the input vars right after
# _read_input, so the touch-to-input translation is the only part
# bypassed (the joystick test already covers that).
var _movetest_active: bool = false
var _movetest_step: int = -1 # -1 = waiting for the countdown to end
var _movetest_steps: Array = []
var _movetest_in_step: bool = false
var _movetest_timer: float = 0.0
var _movetest_total: float = 0.0
var _movetest_passed: int = 0
var _movetest_failed: int = 0
var _movetest_done: bool = false
var _movetest_data: Dictionary = {}
var _movetest_hold: Dictionary = {} # {"move": float, "up": bool} held every frame this step
var _movetest_press_jump: bool = false # one-frame jump edge, consumed by _movetest_apply_input
var _movetest_up_prev: bool = false # rising-edge tracking for hold.up


func _movetest_pre_tick(delta: float) -> void:
	if not _movetest_active or _movetest_done:
		return
	_movetest_total += delta
	if _movetest_total > 120.0:
		print("MOVETEST TIMEOUT: FAIL - steps did not finish in 120 s")
		_movetest_finish()
		return
	if not alive:
		print("MOVETEST DEAD: FAIL - local player died mid-test")
		_movetest_finish()
		return
	var game = get_tree().get_first_node_in_group("game")
	if game != null and bool(game.get("match_over")):
		print("MOVETEST MATCH-OVER: FAIL - match ended mid-test")
		_movetest_finish()
		return
	# A carrier step forces the flag every frame: game.gd rewrites
	# carrying_flag from its own CTF state, and this runs before
	# _tick_boost_timers, so the timers always see the forced value.
	if bool(_movetest_data.get("force_carrier", false)):
		carrying_flag = 1
	if _movetest_step == -1:
		# Wait for the 3-2-1 countdown to end (during it the game
		# zeroes touch input, so no step may start). 15 s timeout.
		var cd := false
		if game != null:
			cd = bool(game.get("_countdown_active"))
		if not cd:
			_movetest_step = 0
			_movetest_in_step = false
			_movetest_timer = 0.0
			_movetest_data = {}
			_build_movetest_steps()
		elif _movetest_total > 15.0:
			print("MOVETEST COUNTDOWN: FAIL - countdown still active after 15 s")
			_movetest_finish()
		return
	if _movetest_step >= _movetest_steps.size():
		_movetest_finish()
		return
	var step: Dictionary = _movetest_steps[_movetest_step]
	if not _movetest_in_step:
		(step["setup"] as Callable).call()
		_movetest_in_step = true
		_movetest_timer = float(step["wait"])
	_movetest_timer -= delta
	if _movetest_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_movetest_passed += 1
		else:
			_movetest_failed += 1
		print("MOVETEST %s: %s - %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_movetest_step += 1
		_movetest_in_step = false
		_movetest_timer = 0.0
		_movetest_hold = {}
		_movetest_press_jump = false


func _movetest_apply_input() -> void:
	# Runs right after _read_input in the local branch: the step's
	# held inputs win for this frame, and a one-frame jump edge (or
	# the rising edge of a held stick-up) is pulsed exactly once.
	if not _movetest_active or _movetest_done:
		return
	var move := float(_movetest_hold.get("move", 0.0))
	var up := bool(_movetest_hold.get("up", false))
	_move_axis = move
	_move_mag = absf(move)
	_move_stick_y = -1.0 if up else 0.0
	_jump_held = up
	if up and not _movetest_up_prev:
		_jump_pressed = true
	_movetest_up_prev = up
	if _movetest_press_jump:
		_jump_pressed = true
		_movetest_press_jump = false


func _movetest_finish() -> void:
	if _movetest_done:
		return
	_movetest_done = true
	print("MOVETEST DONE: %d/%d passed" % [_movetest_passed, _movetest_passed + _movetest_failed])
	get_tree().quit()


func _mt_teleport(p: Vector2) -> void:
	position = p
	sync_position = p
	velocity = Vector2.ZERO


func _build_movetest_steps() -> void:
	if not _is_skyfall():
		# Non-Skyfall run (--map=0): every fetcher must be empty
		# and no movement feature may fire.
		_movetest_steps = [
			{"name": "NONSKYFALL-NOOP", "wait": 0.3, "setup": _mt_s_nonskyfall, "check": _mt_c_nonskyfall},
		]
		return
	_movetest_steps = [
		{"name": "GRAPPLE-SETUP", "wait": 0.1, "setup": _mt_s_grapple_setup, "check": _mt_c_grapple_setup},
		{"name": "GRAPPLE-ATTACH", "wait": 0.25, "setup": _mt_s_grapple_attach, "check": _mt_c_grapple_attach},
		{"name": "GRAPPLE-RELEASE", "wait": 0.15, "setup": _mt_s_grapple_release, "check": _mt_c_grapple_release},
		{"name": "GRAPPLE-COOLDOWN-BLOCKED", "wait": 0.2, "setup": _mt_s_grapple_cooldown, "check": _mt_c_grapple_cooldown},
		{"name": "GRAPPLE-COOLDOWN-WAIT", "wait": 0.8, "setup": _mt_s_grapple_cdwait, "check": _mt_c_grapple_cdwait},
		{"name": "GRAPPLE-REATTACH-SETUP", "wait": 0.1, "setup": _mt_s_grapple_reattach_setup, "check": _mt_c_grapple_setup},
		{"name": "GRAPPLE-REATTACH", "wait": 0.25, "setup": _mt_s_grapple_reattach, "check": _mt_c_grapple_reattach},
		{"name": "WALL-JUMP-PIN", "wait": 0.3, "setup": _mt_s_wall_pin, "check": _mt_c_wall_pin},
		{"name": "WALL-JUMP", "wait": 0.05, "setup": _mt_s_wall_jump, "check": _mt_c_wall_jump},
		{"name": "WALL-JUMP-RESET", "wait": 0.6, "setup": _mt_s_wall_reset, "check": _mt_c_wall_reset},
		{"name": "JETPACK-LINE-SETUP", "wait": 0.5, "setup": _mt_s_jetpack_line_setup, "check": _mt_c_jetpack_line_setup},
		{"name": "JETPACK-LINE", "wait": 0.4, "setup": _mt_s_jetpack_line, "check": _mt_c_jetpack_line},
		{"name": "WIND-OFF-LINE-SETUP", "wait": 0.5, "setup": _mt_s_wind_off_line_setup, "check": _mt_c_wind_off_line_setup},
		{"name": "WIND-OFF-LINE", "wait": 0.4, "setup": _mt_s_wind_off_line, "check": _mt_c_wind_off_line},
		{"name": "CARRIER-LINE", "wait": 0.4, "setup": _mt_s_carrier_line, "check": _mt_c_carrier_line},
		{"name": "CARRIER-DROP-BOOST", "wait": 0.3, "setup": _mt_s_carrier_drop, "check": _mt_c_carrier_drop},
	]


# --- Movement-test setups / checks (each check returns [passed, detail]) ---
# Geometry (Skyfall MAPS[5]): grapple points include (900,6200);
# the grapple test uses (900,4400) from (850,4650) instead - the
# shaft there is clear, while (900,6200) sits above the solid
# (800,6302,500,48) platform and pins the climber under it.
# the (700,3412,400,48) platform carries the solid sniper tower
# (256x384, inset 12 -> left face x=784, spans y 3040-3412);
# jetpack line 1 runs x=1800, y 2900-3600 through wind zone 1
# (Rect2(1400,2900,800,700), dir -1, strength 150); the (1500,3242,
# 600,48) platform caps the rise from y=3350, and (1500,3350) is
# 300 px off the line but inside the same wind zone.

func _mt_s_nonskyfall() -> void:
	_mt_teleport(position + Vector2(0, -300))
	velocity = Vector2.ZERO
	_movetest_press_jump = true
	_movetest_data["pts"] = _skyfall_grapple_points().size()
	_movetest_data["lines"] = _skyfall_jetpack_lines().size()


func _mt_c_nonskyfall() -> Array:
	var ok: bool = not _is_skyfall() and int(_movetest_data.get("pts", -1)) == 0 and int(_movetest_data.get("lines", -1)) == 0 and not _grappling and not _on_jetpack_line
	return [ok, "skyfall=%s points=%s lines=%s grappling=%s on_line=%s" % [_is_skyfall(), _movetest_data.get("pts"), _movetest_data.get("lines"), _grappling, _on_jetpack_line]]


func _mt_s_grapple_setup() -> void:
	# Teleport under point (900,4400) and let the floor state settle:
	# is_on_floor() is stale for one frame after a teleport (it
	# reports the last move_and_slide), so the attach press must
	# wait for the next step - pressing on this frame would be
	# skipped as "on floor". The player stands at (850,4650), 255 px
	# below the point; the shaft x=850-900 is clear of platforms
	# (the (900,4262) platform sits above the point, not in the
	# shaft), so the rope can actually pull the player up - the
	# first geometry tried, (900,6450) under (900,6200), pinned the
	# player under the (800,6302) platform instead.
	_mt_teleport(Vector2(850, 4650))
	fuel = FUEL_MAX


func _mt_c_grapple_setup() -> Array:
	var ok: bool = not is_on_floor()
	return [ok, "on_floor=%s (want airborne after settle)" % is_on_floor()]


func _mt_s_grapple_attach() -> void:
	_movetest_data["dist0"] = global_position.distance_to(Vector2(900, 4400))
	_movetest_data["y0"] = global_position.y
	_movetest_press_jump = true


func _mt_c_grapple_attach() -> Array:
	var d := global_position.distance_to(Vector2(900, 4400))
	var ok: bool = _grappling and d < float(_movetest_data.get("dist0", 9999.0)) - 50.0 and global_position.y < float(_movetest_data.get("y0", 0.0)) - 30.0 and fuel >= 99.0
	return [ok, "grappling=%s dist %.0f->%.0f y %.0f->%.0f fuel=%.0f" % [_grappling, _movetest_data.get("dist0", 0.0), d, _movetest_data.get("y0", 0.0), global_position.y, fuel]]


func _mt_s_grapple_release() -> void:
	_movetest_data["vy0"] = velocity.y
	_movetest_press_jump = true


func _mt_c_grapple_release() -> Array:
	var ok: bool = not _grappling and velocity.y < -150.0 and _grapple_cooldown > 0.5
	return [ok, "grappling=%s vel.y=%.0f (was %.0f) cooldown=%.2f" % [_grappling, velocity.y, _movetest_data.get("vy0", 0.0), _grapple_cooldown]]


func _mt_s_grapple_cooldown() -> void:
	# Still inside the 1 s cooldown, still in range of (900,6200):
	# a jump press here must NOT attach.
	_movetest_press_jump = true


func _mt_c_grapple_cooldown() -> Array:
	var ok: bool = not _grappling and _grapple_cooldown > 0.0
	return [ok, "grappling=%s cooldown=%.2f" % [_grappling, _grapple_cooldown]]


func _mt_s_grapple_cdwait() -> void:
	# No press - just wait out the rest of the 1 s cooldown (the
	# release was ~0.35 s before this step, so 0.8 s clears it).
	pass


func _mt_c_grapple_cdwait() -> Array:
	var ok: bool = _grapple_cooldown <= 0.05
	return [ok, "cooldown=%.2f (want <= 0.05)" % _grapple_cooldown]


func _mt_s_grapple_reattach_setup() -> void:
	# Same settle as the first setup: back under the point (the
	# player landed on the ground floor during the cooldown wait).
	_mt_teleport(Vector2(850, 4650))
	fuel = FUEL_MAX


func _mt_s_grapple_reattach() -> void:
	_movetest_press_jump = true


func _mt_c_grapple_reattach() -> Array:
	var ok: bool = _grappling and _grapple_cooldown <= 0.0
	return [ok, "grappling=%s cooldown=%.2f" % [_grappling, _grapple_cooldown]]


func _mt_s_wall_pin() -> void:
	# Airborne beside the sniper tower's left face (x=784): hold
	# right into it for the step's wait. The player falls ~60 px
	# in 0.3 s and stays beside the tower (it spans y 3040-3412).
	# The grapple from the reattach step MUST be released first -
	# otherwise the rope keeps pulling the player down toward
	# (900,4400) and they land on the platform mid-pin (run 1).
	_release_grapple(false)
	_mt_teleport(Vector2(760, 3300))
	_movetest_hold = {"move": 1.0, "up": false}


func _mt_c_wall_pin() -> Array:
	var ok: bool = is_on_wall() and not is_on_floor()
	return [ok, "is_on_wall=%s on_floor=%s wall_normal=%s" % [is_on_wall(), is_on_floor(), get_wall_normal()]]


func _mt_s_wall_jump() -> void:
	# Press jump while still holding right into the wall (the
	# wall-jump needs the stick pushed toward the wall). The
	# wait is 0.05 s: any longer and holding right recovers the
	# -380 push back past the -200 bound.
	_movetest_hold = {"move": 1.0, "up": false}
	_movetest_press_jump = true


func _mt_c_wall_jump() -> Array:
	var ok: bool = velocity.x < -200.0 and velocity.y < -300.0 and _wall_jumps_used == 1
	return [ok, "vel=%s wall_jumps=%d (want x<-200, y<-300, 1 jump)" % [velocity, _wall_jumps_used]]


func _mt_s_wall_reset() -> void:
	# Drop onto the (1500,3242) platform to land, then the chain
	# must reset to 0.
	_mt_teleport(Vector2(1800, 3200))
	_movetest_hold = {}


func _mt_c_wall_reset() -> Array:
	var ok: bool = is_on_floor() and _wall_jumps_used == 0
	return [ok, "on_floor=%s wall_jumps=%d" % [is_on_floor(), _wall_jumps_used]]


func _mt_s_jetpack_line_setup() -> void:
	# On line 1 (x=1800, y 2900-3600) inside wind zone 1: hold up
	# for 0.5 s first, so the jump transient is over and the
	# jetpack is thrusting at steady state (the first hold frame
	# fires a -660 jump, which delays thrust by ~0.24 s and would
	# make a single-step drain measurement meaningless).
	_release_grapple(false)
	_mt_teleport(Vector2(1800, 3350))
	fuel = FUEL_MAX
	_movetest_hold = {"move": 0.0, "up": true}


func _mt_c_jetpack_line_setup() -> Array:
	# Fuel < 100 proves thrust ran (_jetpacking itself alternates
	# on skip frames at the -320 rise cap, so it is not asserted).
	var ok: bool = _on_jetpack_line and fuel < 100.0
	return [ok, "on_line=%s fuel=%.1f (want <100, thrusting)" % [_on_jetpack_line, fuel]]


func _mt_s_jetpack_line() -> void:
	# Steady state now: half drain = 45*0.5*0.4 = 9 fuel.
	_movetest_data["fuel0"] = fuel
	_movetest_hold = {"move": 0.0, "up": true}


func _mt_c_jetpack_line() -> Array:
	var drain := float(_movetest_data.get("fuel0", 100.0)) - fuel
	var ok: bool = _on_jetpack_line and drain > 7.0 and drain < 11.0 and velocity.x > -20.0
	return [ok, "on_line=%s fuel drain=%.1f (want ~9) vel.x=%.0f (want >-20, wind shielded)" % [_on_jetpack_line, drain, velocity.x]]


func _mt_s_wind_off_line_setup() -> void:
	# Same wind zone, 300 px off the line: same 0.5 s steady-state
	# hold first, for the same reason.
	_mt_teleport(Vector2(1500, 3350))
	fuel = FUEL_MAX
	_movetest_hold = {"move": 0.0, "up": true}


func _mt_c_wind_off_line_setup() -> Array:
	var ok: bool = not _on_jetpack_line and fuel < 100.0
	return [ok, "on_line=%s fuel=%.1f (want <100, thrusting)" % [_on_jetpack_line, fuel]]


func _mt_s_wind_off_line() -> void:
	# Steady state now: full drain = 45*0.4 = 18 fuel, and the
	# wind pushes left (-150 px/s^2).
	_movetest_data["fuel0"] = fuel
	_movetest_hold = {"move": 0.0, "up": true}


func _mt_c_wind_off_line() -> Array:
	var drain := float(_movetest_data.get("fuel0", 100.0)) - fuel
	var ok: bool = not _on_jetpack_line and drain > 15.0 and drain < 21.0 and velocity.x < -25.0
	return [ok, "on_line=%s fuel drain=%.1f (want ~18) vel.x=%.0f (want <-25, wind pushes)" % [_on_jetpack_line, drain, velocity.x]]


func _mt_s_carrier_line() -> void:
	# Carrier on the line: wind shield yes, fuel discount no, boost
	# activation no. Pickup while carrying must STORE the jetpack
	# boost (fuel 50 proves no activation: activation refills it).
	# QA-119: jetpack is kind 10 now (was 12); pickup only stores.
	_mt_teleport(Vector2(1800, 3350))
	fuel = 50.0
	_fuel_delay_timer = FUEL_REGEN_DELAY
	carrying_flag = 1
	_movetest_data["force_carrier"] = true
	apply_powerup(10)
	_movetest_data["stored"] = stored_boosts.has(10)
	_movetest_data["active0"] = active_boost_kind
	_movetest_data["fuel0"] = fuel
	_movetest_hold = {"move": 0.0, "up": true}


func _mt_c_carrier_line() -> Array:
	var ok: bool = bool(_movetest_data.get("stored", false)) and int(_movetest_data.get("active0", -1)) == 0 and active_boost_kind == 0 and jetpack_boost_timer <= 0.0 and fuel <= 50.5 and velocity.x > -20.0
	return [ok, "stored10=%s active=%d boost_t=%.1f fuel=%.1f (was %.1f) vel.x=%.0f" % [_movetest_data.get("stored"), active_boost_kind, jetpack_boost_timer, fuel, _movetest_data.get("fuel0", 0.0), velocity.x]]


func _mt_s_carrier_drop() -> void:
	# Drop the flag: QA-119 - the stored jetpack boost must NOT
	# start by itself any more (tap-to-activate only). The check
	# below proves it waits, then taps the slot and proves it starts.
	_movetest_data["force_carrier"] = false
	carrying_flag = 0
	_movetest_hold = {}


func _mt_c_carrier_drop() -> Array:
	var waited: bool = active_boost_kind == 0 and stored_boosts.has(10) and jetpack_boost_timer <= 0.0
	var tapped: bool = activate_slot(0)
	var ok: bool = waited and tapped and active_boost_kind == 10 and jetpack_boost_timer > 0.0 and fuel >= 99.0
	return [ok, "waited=%s tapped=%s active=%d boost_t=%.1f fuel=%.1f stored=%s" % [waited, tapped, active_boost_kind, jetpack_boost_timer, fuel, stored_boosts]]
