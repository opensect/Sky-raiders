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
const SPEED := 250.0 # QA-141: MMC sustained move speed (was 350)
const ACCEL := 900.0 # QA-141: MMC headroom initial 3.0 x 300 (was 2600)
const DECEL := 3400.0 # retained as tuning reference only; MMC drag is the real stopper
const SPEED_GROUND := 250.0
const SPEED_AIR := 250.0
const ACCEL_GROUND := 900.0
const ACCEL_AIR := 900.0
const DECEL_GROUND := 3400.0
const DECEL_AIR := 900.0
const REVERSAL_GROUND := 1.0 # QA-141: MMC has no reversal bonus (was 1.6)
const REVERSAL_AIR := 1.0 # QA-141: MMC has no reversal bonus (was 1.2)
const DRAG_GROUND := 0.6 # QA-141: MMC damping ln(1/0.55) (was 8.0)
const DRAG_AIR := 0.6 # QA-141: MMC damping (was 1.2)
const JUMP_VELOCITY := -220.0 # QA-141: MMC jump impulse 22.0 / mass 0.1 (was -660)
# QA-141 (Mini Militia port): mirrors PhysicsConfig — change both
# files together. MMC values: JET_ACCEL 450, MAX_JET_RISE 190,
# FUEL_MAX 100 (4.76 s tank — supersedes QA-132's 9 s tank),
# FUEL_DRAIN 21/s x thrustFactor. NO jet ramp in MMC (JET_RAMP_MIN /
# JET_RAMP_TIME deleted); thrust scales with input instead
# (0.5 + 0.5 x up). Fuel regen 50/25 + delay 0.5 KEPT — MMC fuel
# regen was not found. Old values: JET_ACCEL 1650, MAX_JET_RISE
# 320, FUEL_REFILL 50, FUEL_REFILL_AIR 25, FUEL_REGEN_DELAY 0.5
# (QA-074 ramp 0.75 -> 1.0 over 0.35 s; QA-132 FUEL_MAX 405).
const JET_ACCEL := 450.0
const MAX_JET_RISE := 190.0
const JET_AIR_ACCEL := 450.0 # MMC thrusting initial accel 1.5 x 300 (was 1900)
const GRAVITY := 300.0
const GRAVITY_THRUSTING := 50.0 # QA-141: MMC owner gravity while thrusting
const MAX_FALL := 600.0
const FUEL_MAX := 100.0 # QA-141: MMC 100 fuel (was 405)
const FUEL_DRAIN := 21.0 # QA-141: MMC max 21/s x thrustFactor (was 45)
const FUEL_REFILL := 50.0
const FUEL_REFILL_AIR := 25.0
const FUEL_REGEN_DELAY := 0.5
const MASS := 1.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
# AIM_DEAD_ZONE is kept only as documentation: MMC has NO dead zone
# (QA-141: joystick.gd dead_zone 0.0) — the stick reports raw, and
# player/game must not re-apply their own thresholds (GAP-09).
const AIM_DEAD_ZONE := 0.0
# v2.2: the JUMP button is gone - the left stick does jumping and the
# jetpack. Push the stick up past this to jump (grounded) / thrust (air).
# QA-141: MMC jump gate up-input > 0.75 (SLC::updateStep 0x8e4d5c).
const STICK_UP_THRESHOLD := 0.75
const STICK_DOWN_THRESHOLD := 0.5
const FAST_FALL_EXTRA := 1600.0
# QA FIX (v2.1): spawn protection - 2s of invulnerability after (re)spawning
# so a camper cannot kill a player the instant they appear.
const SPAWN_PROTECTION := 2.0

const BULLET_SCENE: PackedScene = preload("res://weapons/bullet.tscn")
const GRENADE_SCENE: PackedScene = preload("res://weapons/grenade.tscn")

# weapon: 0 rifle, 1 smg, 2 shotgun, 3 sniper, 4 rocket, 5 pistol.
# The full table (fire rate, damage, mag, reload, speed, spread,
# pellets, explosive, sound, recoil, shake, auto, life) lives in
# WeaponData (weapons.gd) - one data-driven table, no per-weapon
# firing logic anywhere. The pistol is the starting sidearm.
const WEAPONS := WeaponData.TABLE

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
var mag_ammo: int = int(WEAPONS[0]["mag"]) # QA-141: spawn clip = the rifle's TABLE mag (35, MMC AK47) — was a hardcoded 30, which matched the old TABLE mag 30 but went stale when the TABLE moved to 35; _respawn already sets the full TABLE mag, so the first life must too, or the HUD reads 30/90 on spawn and 35/90 after the first death.
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
# QA-141: MMC thrust factor (0.5 + 0.5 x up-input), not a time ramp
# — MMC has no JET_RAMP. 0 while not thrusting; the jetpack flame
# (player_visuals.gd) scales with it. Reset the moment thrust stops.
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
# QA-141: MMC deterministic spread — one LCG counter per weapon id
# (Weapon::getRandomFiringAngle 0x948878: counter = (41 x counter
# + 37) % 100, init 0). player_weapons.gd advances it per pellet.
var _spread_counters: Dictionary = {}
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
# QA-140 (v3.15): system modules (built in _ready, each holds a
# reference to this player node and owns no state of its own).
var player_movetest: PlayerMovetest # movement-test step machine
var player_movement: PlayerMovement # physics, input, grapple, ladder, wall-jump
var player_sync: PlayerSync # move snapshots, interp, authoritative correction, net stats
var player_weapons: PlayerWeapons # aim/fire, reload, weapon switch, grenades, bullets
var player_health: PlayerHealth # damage, death/respawn, kills, hit confirm
var player_powerups: PlayerPowerups # pickups, boost slots, wind blast, thunder strike
var player_visuals: PlayerVisuals # sprite, anims, camera, sight line, sounds
# QA-105 (v3.8): scopes + sniper line of sight. Sniper zooms 2.0x,
# rifle 1.5x; SMG / shotgun / pistol / rocket have no scope. The
# sight line is the sniper bullet's true range (1600 px/s * 1.6 s).
const SCOPE_ZOOM_SNIPER := 2.0
const SCOPE_ZOOM_RIFLE := 1.5
const SIGHT_LINE_RANGE := 2560.0
var scoped: bool = false # scope toggle (HUD SCOPE button, sniper/rifle only)
var _sight_line: Line2D # sniper sight line (local player only)

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
var _wind_sweep_timer: float = 0.0 # QA-135: Wind Blast tornado sweep — seconds left being pulled into the funnel
var _wind_sweep_center: Vector2 = Vector2.ZERO # QA-135: tornado centre the victim is pulled toward
var _wind_throw: Vector2 = Vector2.ZERO # QA-135: throw velocity applied when the sweep ends
var _wind_throw_timer: float = 0.0 # QA-135: throw hold — seconds the throw velocity is forced (a one-frame impulse decays to friction before the victim reaches the edge)
var _wind_fall_timer: float = 0.0 # QA-135: remote-copy (test bot) fall after the throw — seconds the throw + gravity keep moving the copy

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
	# QA-140 (v3.15): system modules are built here, before any of
	# their functions run. Each holds a reference to this player node
	# and owns no state of its own.
	player_movetest = PlayerMovetest.new(self)
	player_movement = PlayerMovement.new(self)
	player_sync = PlayerSync.new(self)
	player_weapons = PlayerWeapons.new(self)
	player_health = PlayerHealth.new(self)
	player_powerups = PlayerPowerups.new(self)
	player_visuals = PlayerVisuals.new(self)
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
	return player_visuals._build_collision()


# QA-119: one power-up effect layer. The image is 512x512; scale
# shrinks it to ~150 px on the player. Hidden until its power-up
# is active. A missing file (pack not imported) must not crash the
# game - load() returns null and the sprite simply stays empty.
func _make_fx_sprite(path: String, scale: float) -> Sprite2D:
	return player_visuals._make_fx_sprite(path, scale)


func _build_sprite() -> void:
	return player_visuals._build_sprite()




func _make_sprite_frames() -> SpriteFrames:
	return player_visuals._make_sprite_frames()


var _helmet_y: float = -25.0 # QA-094: current per-animation helmet height



# QA-127: the hand anchor in PLAYER units (frame units x PLAYER_SCALE),
# facing right. The gun grip sits here; the muzzle and bullet spawn
# use it too (see _muzzle_origin).
func _hand_anchor() -> Vector2:
	return player_visuals._hand_anchor()


# QA-127: the hands in the player's local space (mirrored when
# facing left). Bullets and the sight line leave from here.
func _muzzle_origin() -> Vector2:
	return player_visuals._muzzle_origin()

func _update_helmet() -> void:
	return player_visuals._update_helmet()


func _update_gun_texture() -> void:
	return player_visuals._update_gun_texture()


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
	return player_sync._send_move_snapshot(force)


@rpc("any_peer", "unreliable")
func receive_move_snapshot(snap: Dictionary) -> void:
	return player_sync.receive_move_snapshot(snap)


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
	return player_sync.apply_authoritative_correction(auth_pos, auth_vel, corr_seq)


# QA-073: one dict with everything the net-stats display needs
# (spec §7). "auth_pos" is the newest authoritative snapshot
# position for this (remote) player; the rendered position is the
# node's own position. For the local player the snapshot fields
# are its own last-received values (0 when solo).
func get_net_stats() -> Dictionary:
	return player_sync.get_net_stats()


func _process(delta: float) -> void:
	# Rendering only (GAP-69, spec §23.E): sprite/gun/camera/HP visuals
	# run at the render frame, never in _physics_process. Nothing here
	# writes position or velocity (camera position is a view offset).
	_update_visuals(delta)
	if is_local_player() and _camera != null:
		_update_camera(delta)
		_update_sight_line()


func _physics_process(delta: float) -> void:
	return player_movement._physics_process(delta)


func _interp_position(now: float) -> Vector2:
	return player_sync._interp_position(now)


func _check_stuck(delta: float) -> void:
	return player_movement._check_stuck(delta)


func _wedge_reset() -> void:
	return player_movement._wedge_reset()


func _both_sides_blocked() -> bool:
	return player_movement._both_sides_blocked()


func _update_camera(delta: float) -> void:
	return player_visuals._update_camera(delta)


func _update_sight_line() -> void:
	return player_visuals._update_sight_line()


func _read_input() -> void:
	return player_movement._read_input()


func _update_ladder() -> void:
	return player_movement._update_ladder()


# QA-112 (v3.9 Skyfall movement): grapple / wall-jump / jetpack-line
# data + logic. The game scene owns the data (MAPS[5]); this file
# only reads it, the same way _update_ladder reads skyfall_ladder_at
# - current scene first, then the "game" group node, and a missing
# key or a missing helper is a no-op, never a crash. The point/line
# lists are cached per map (MAPS is const, so the data cannot
# change mid-match); any other map returns empty / false.


func _is_skyfall() -> bool:
	return player_movement._is_skyfall()


func _skyfall_grapple_points() -> Array:
	return player_movement._skyfall_grapple_points()


func _skyfall_jetpack_lines() -> Array:
	return player_movement._skyfall_jetpack_lines()


func _is_on_jetpack_line() -> bool:
	return player_movement._is_on_jetpack_line()


func _grapple_pull_speed() -> float:
	return player_movement._grapple_pull_speed()


func _release_grapple(with_boost: bool) -> void:
	return player_movement._release_grapple(with_boost)


func _update_grapple(delta: float) -> void:
	return player_movement._update_grapple(delta)


func _try_wall_jump() -> bool:
	return player_movement._try_wall_jump()


func _apply_movement(delta: float) -> void:
	return player_movement._apply_movement(delta)


func _apply_aim_and_fire(delta: float) -> void:
	return player_weapons._apply_aim_and_fire(delta)


func _update_anim() -> void:
	return player_visuals._update_anim()


func _update_remote_anim() -> void:
	return player_visuals._update_remote_anim()


func _play_anim(anim_name: String) -> void:
	return player_visuals._play_anim(anim_name)


func _fire() -> void:
	return player_weapons._fire()


func add_shake(amount: float) -> void:
	return player_weapons.add_shake(amount)


func start_reload() -> void:
	return player_weapons.start_reload()


func reload_progress() -> float:
	return player_weapons.reload_progress()


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
	return player_weapons._show_muzzle()


func _start_reload() -> void:
	return player_weapons._start_reload()


func ammo_reserve() -> int:
	return player_weapons.ammo_reserve()


func switch_weapon() -> void:
	return player_weapons.switch_weapon()


# QA-075: magazine memory + reload refund (see switch_weapon).
func _reset_mag_memory() -> void:
	return player_weapons._reset_mag_memory()


func _refund_reload() -> void:
	return player_weapons._refund_reload()


func owned_weapons() -> Array:
	return player_weapons.owned_weapons()


func throw_grenade() -> void:
	return player_weapons.throw_grenade()


@rpc("any_peer", "call_local")
func spawn_bullet(pos: Vector2, dir: Vector2, speed: float, damage: int, kind: int, owner_id: int, shot_no: int, bvel: Vector2 = Vector2.INF) -> void:
	return player_weapons.spawn_bullet(pos, dir, speed, damage, kind, owner_id, shot_no, bvel)


@rpc("any_peer", "call_local")
func spawn_grenade(pos: Vector2, dir: Vector2, owner_id: int, thrower_vel: Vector2 = Vector2.ZERO) -> void:
	return player_weapons.spawn_grenade(pos, dir, owner_id, thrower_vel)


@rpc("any_peer")
func take_damage(amount: int, from_id: int) -> void:
	return player_health.take_damage(amount, from_id)


@rpc("any_peer")
func take_hit(amount: int, from_id: int, dir: Vector2, knockback: float, event_id: int) -> void:
	return player_health.take_hit(amount, from_id, dir, knockback, event_id)


func hit_region(hit_pos: Vector2, player_pos: Vector2) -> String:
	return player_health.hit_region(hit_pos, player_pos)


func calculate_damage(base: int, region: String, distance: float, weapon_id: int) -> int:
	return player_health.calculate_damage(base, region, distance, weapon_id)


func _apply_damage(amount: int, from_id: int, dir: Vector2, knockback: float, event_id: int) -> void:
	return player_health._apply_damage(amount, from_id, dir, knockback, event_id)


@rpc("any_peer")
func take_explosion_damage(pos: Vector2, radius: float, damage: int, from_id: int, event_id: int = -1) -> void:
	return player_health.take_explosion_damage(pos, radius, damage, from_id, event_id)


@rpc("any_peer")
func add_kill() -> void:
	return player_health.add_kill()


# Phase 4 - accuracy: one trigger pull counts as a hit once, however
# many of its pellets land (a shotgun's 7 pellets are one shot, not
# seven). shot_no is _shots_fired * 10 + pellet index, so the key is
# shot_no / 10. Called by the host only.
func record_hit(shot_no: int) -> void:
	return player_health.record_hit(shot_no)


# Phase 4 - hitmarker: the host confirms each hit to the shooter
# (damage dealt, where, and whether it was lethal). The game reads
# _hitmark_seq on the local player and shows the marker + damage
# number. Only the host may send this.
@rpc("any_peer")
func hit_confirm(dmg: int, pos: Vector2, lethal: bool) -> void:
	return player_health.hit_confirm(dmg, pos, lethal)


@rpc("any_peer")
func give_pickup(kind: int) -> void:
	return player_powerups.give_pickup(kind)


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
	return player_powerups.apply_powerup(kind)


# QA-132: power-up feedback — a lost pickup or a fired instant
# used to fail silently (no message, no visible effect). The feed
# goes through the game scene, into the same top-left message area
# as every other notice. No game node (menu / unit test) = silent.
func _pu_feed(text: String) -> void:
	return player_powerups._pu_feed(text)


# Activate the power-up waiting in slot `idx` (HUD slot-button tap).
# Timed kinds (8, 9, 10, 13): ONE active at a time, and a carrier
# CANNOT activate one while carrying the flag (the carrier rule
# wins - the tap does nothing and the power-up stays in its slot).
# Instant kinds (7 health, 11 wind, 12 thunder) fire at once and
# work even while a timed boost is active or the flag is carried.
# QA-135 (v3.13): Wind (11) / Thunder (12) need a live enemy on
# the SAME PLATFORM at the SAME HEIGHT — no target, no fire, and
# the power-up STAYS in its slot (never wasted on thin air).
func activate_slot(idx: int) -> bool:
	return player_powerups.activate_slot(idx)


# Fire an instant power-up. Health restores 50 HP (QA-132: was
# 35 — it competes with 4 HP/s regen now); Wind Blast sweeps the
# enemy on the activator's platform into a tornado and throws them
# down (no damage); Thunder Strike halves that enemy's current
# health. Wind/thunder are host-authoritative: a client asks the
# host with an RPC, passing the target the tap already picked (in
# the sim the peer IS the host).
# QA-132: wind + thunder announce themselves in the feed, so the
# player sees the activation even when no enemy is in range.
func _apply_instant(kind: int, target: Node2D = null) -> void:
	return player_powerups._apply_instant(kind, target)


@rpc("any_peer", "call_local")
func request_wind_blast(target_peer: int) -> void:
	return player_powerups.request_wind_blast(target_peer)


@rpc("any_peer", "call_local")
func request_thunder_strike(target_peer: int) -> void:
	return player_powerups.request_thunder_strike(target_peer)


# Host only: the Wind Blast tornado. The target (same platform +
# same height as the activator, picked at tap time and re-validated
# here) gets a tornado at their feet, is swept into it (pulled to
# the centre for 0.7 s), then thrown DOWN off the platform. No
# damage; a shield does not stop the push (movement, not damage).
# The throw goes toward the NEAREST edge of the shared platform
# (a downward velocity alone cannot leave a solid platform — the
# floor blocks it), so the victim clears the edge and falls below.
# The sweep itself runs on the victim's owning peer (see
# apply_wind_sweep) so it works for remote victims too; a test bot
# (fake peer, no live connection) is driven on the host copy.
func _do_wind_blast(target: Node2D) -> void:
	return player_powerups._do_wind_blast(target)


@rpc("any_peer")
func apply_wind_sweep(centre: Vector2, throw_vec: Vector2) -> void:
	return player_powerups.apply_wind_sweep(centre, throw_vec)


# Host only: Thunder Strike halves the target's CURRENT health
# (QA-135: was flat 40 damage) — a single target, no area damage.
# The target is the enemy on the activator's platform at the same
# height (picked at tap time, re-validated here). Shield absorbs
# the strike (take_hit -> _apply_damage zeroes it); the bolt
# visual is drawn by the game (show_thunder_strike_fx).
func _do_thunder_strike(target: Node2D) -> void:
	return player_powerups._do_thunder_strike(target)


# Start a timed boost now: set its timer (and refill the fuel for
# the jetpack boost) and mark it active.
func _activate_boost(kind: int) -> void:
	return player_powerups._activate_boost(kind)


# Tick the boost timers every physics frame. When the active boost
# runs out it just ends - stored power-ups NEVER start by
# themselves (tap-to-activate only, QA-119). A carrier's stored
# boost waits in its slot until the player taps it after the drop.
func _tick_boost_timers(delta: float) -> void:
	return player_powerups._tick_boost_timers(delta)


# QA-120: slow health regen. Called every physics frame next to
# _tick_boost_timers. Health restores only after
# HEALTH_REGEN_DELAY seconds without taking damage (the timer is
# restarted in _apply_damage on every real health loss).
func _tick_health_regen(delta: float) -> void:
	return player_health._tick_health_regen(delta)


# Survival round reset: the host tells every peer to respawn its own
# player for the next round (new positions, full health).
@rpc("any_peer", "call_local")
func reset_round_remote() -> void:
	return player_health.reset_round_remote()


func _respawn() -> void:
	return player_health._respawn()


func _update_visuals(delta: float) -> void:
	return player_visuals._update_visuals(delta)


func _play_sound(sound_name: String) -> void:
	return player_visuals._play_sound(sound_name)


func _start_jetpack_sound() -> void:
	return player_visuals._start_jetpack_sound()


func _stop_jetpack_sound() -> void:
	return player_visuals._stop_jetpack_sound()


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
	return player_movetest._movetest_pre_tick(delta)


func _movetest_apply_input() -> void:
	return player_movetest._movetest_apply_input()


func _movetest_finish() -> void:
	return player_movetest._movetest_finish()
