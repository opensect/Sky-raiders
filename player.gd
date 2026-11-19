extends CharacterBody2D

# Animated soldier: analog run, jump, jetpack, full 360-degree aim.
# Each peer owns its own player (multiplayer authority); a
# MultiplayerSynchronizer replicates state to the other peers.
# The soldier art has a rifle baked in; a separate weapon sprite is drawn
# at the hands and rotated to the exact aim angle so the weapon always
# points where the right stick points.

# Movement/physics values live in PhysicsConfig (GAP-70, single source of
# truth). The consts below mirror it for the hot path / old callers.
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
const JET_ACCEL := 1900.0
const MAX_JET_RISE := 450.0
const GRAVITY := 1400.0
const MAX_FALL := 1000.0
const FUEL_MAX := 100.0
const FUEL_DRAIN := 45.0
const FUEL_REFILL := 70.0
const FUEL_REFILL_AIR := 35.0
const FUEL_REGEN_DELAY := 0.6
const MASS := 1.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
# AIM_DEAD_ZONE is kept only as documentation: the dead zone is applied
# ONCE, in joystick.gd (0.20, rescaled). player/game must not re-apply
# their own thresholds (GAP-09). See _read_input.
const AIM_DEAD_ZONE := 0.20
# v2.2: the JUMP button is gone — the left stick does jumping and the
# jetpack. Push the stick up past this to jump (grounded) / thrust (air).
const STICK_UP_THRESHOLD := 0.35
const STICK_DOWN_THRESHOLD := 0.5
const FAST_FALL_EXTRA := 1600.0
# QA FIX (v2.1): spawn protection — 2s of invulnerability after (re)spawning
# so a camper cannot kill a player the instant they appear.
const SPAWN_PROTECTION := 2.0

const BULLET_SCENE: PackedScene = preload("res://bullet.tscn")
const GRENADE_SCENE: PackedScene = preload("res://grenade.tscn")

# weapon: 0 rifle, 1 smg, 2 shotgun, 3 sniper, 4 rocket, 5 pistol.
# The full table (fire rate, damage, mag, reload, speed, spread,
# pellets, explosive, sound, recoil, shake, auto, life) lives in
# WeaponData (weapons.gd) — one data-driven table, no per-weapon
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
}
const MUZZLE_TEX: Texture2D = preload("res://assets/effects/muzzle.png")

const GUN_LENGTH := 46.0

var peer_id: int = 0
var player_index: int = 1
var player_name: String = "Player"
var color_index: int = 0
var player_color: Color = Color(0.95, 0.3, 0.25)
var helmet: int = 0 # 0 none, 1 green helmet, 2 cap, 3 black helmet
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

var _shots_fired: int = 0
var _shots_hit: int = 0 # Phase 4: distinct trigger pulls that hit a player (accuracy)
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
var _coyote_timer: float = 0.0
var _jump_buffer_timer: float = 0.0
var _was_on_floor: bool = false
var _fall_speed: float = 0.0
var _jetpacking: bool = false
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
var _last_snap_pos: Vector2 = Vector2.INF
var _last_snap_vel: Vector2 = Vector2.INF
var _cam_anchor: Vector2 = Vector2.ZERO # camera dead-zone anchor (GAP-52)
var _cam_anchor_init: bool = false
var _cam_look: float = 0.0 # smoothed look-ahead (GAP-53)
var _stuck_check_timer: float = 0.0 # stuck-in-geometry recovery (GAP-72)
var _flame: Polygon2D # jetpack flame, driven by real thrust state (GAP-06)

var _collision_shape: CollisionShape2D
var _sprite: AnimatedSprite2D
var _helmet_sprite: Sprite2D
var _gun: Sprite2D
var _muzzle: Sprite2D
var _ring: Polygon2D
var _name_label: Label
var _hp_bg: ColorRect
var _hp_fg: ColorRect
var _sync: MultiplayerSynchronizer
var _audio # GameAudio node (set by game)
var _camera: Camera2D # kept so respawn can reset smoothing (see below)


func _enter_tree() -> void:
	if name.is_valid_int():
		set_multiplayer_authority(int(String(name)))


func _ready() -> void:
	add_to_group("players")
	_build_collision()
	_build_sprite()
	_setup_sync()
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
	_spawn_protect_timer = SPAWN_PROTECTION
	_play_anim("idle")


func is_local_player() -> bool:
	return get_multiplayer_authority() == multiplayer.get_unique_id()


func _build_collision() -> void:
	_collision_shape = CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = 17.0
	cap.height = 52.0
	_collision_shape.shape = cap
	add_child(_collision_shape)
	floor_snap_length = 4.0


func _build_sprite() -> void:
	_sprite = AnimatedSprite2D.new()
	_sprite.name = "Sprite"
	_sprite.sprite_frames = _make_sprite_frames()
	_sprite.centered = true
	add_child(_sprite)

	_helmet_sprite = Sprite2D.new()
	_helmet_sprite.name = "Helmet"
	_helmet_sprite.position = Vector2(0, -26)
	_helmet_sprite.z_index = 2
	_sprite.add_child(_helmet_sprite)
	_update_helmet()

	# Team / player colour ring under the feet.
	_ring = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * 24.0, 26.0 + sin(a) * 7.0))
	_ring.polygon = pts
	_ring.color = Color(player_color.r, player_color.g, player_color.b, 0.55)
	_ring.z_index = -1
	add_child(_ring)

	# Rotated weapon sprite at the hands (pivot = stock).
	_gun = Sprite2D.new()
	_gun.name = "Gun"
	_gun.position = Vector2(8, 5)
	_gun.z_index = 3
	add_child(_gun)

	_flame = Polygon2D.new()
	_flame.name = "JetFlame"
	_flame.polygon = PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(0, 24)])
	_flame.color = Color(1.0, 0.55, 0.15, 0.95)
	_flame.position = Vector2(0, 18)
	_flame.z_index = 1
	_flame.visible = false
	add_child(_flame)

	_muzzle = Sprite2D.new()
	_muzzle.name = "Muzzle"
	_muzzle.texture = MUZZLE_TEX
	_muzzle.visible = false
	_muzzle.z_index = 4
	_gun.add_child(_muzzle)
	_update_gun_texture()

	_name_label = Label.new()
	_name_label.text = player_name
	_name_label.position = Vector2(-40, -66)
	_name_label.size = Vector2(80, 22)
	_name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name_label.add_theme_font_size_override("font_size", 18)
	_name_label.add_theme_color_override("font_color", player_color)
	_name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_name_label.add_theme_constant_override("outline_size", 4)
	add_child(_name_label)

	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0, 0, 0, 0.6)
	_hp_bg.position = Vector2(-22, -48)
	_hp_bg.size = Vector2(44, 6)
	add_child(_hp_bg)

	_hp_fg = ColorRect.new()
	_hp_fg.color = Color(0.3, 0.9, 0.3)
	_hp_fg.position = Vector2(-22, -48)
	_hp_fg.size = Vector2(44, 6)
	add_child(_hp_fg)


func _make_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	var anims := {
		"idle": ["idle", 11, 7.0, true],
		"run": ["run", 11, 10.0, true],
		"jump": ["jump", 11, 10.0, true],
		"fall": ["fall", 11, 8.0, true],
		"shoot": ["shoot", 11, 12.0, true],
		"aim": ["aim", 11, 6.0, true],
		"jetpack": ["jetpack", 11, 10.0, true],
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
	_helmet_sprite.position = Vector2(1, -25)


func _update_gun_texture() -> void:
	if _gun == null:
		return
	var tex: Texture2D = WEAPON_TEX[weapon]
	_gun.texture = tex
	_gun_base_scale = GUN_LENGTH / tex.get_width()
	_gun.scale = Vector2(_gun_base_scale, _gun_base_scale)
	# Muzzle flash sits at the barrel tip in the gun's local space.
	if _muzzle != null:
		_muzzle.position = Vector2(tex.get_width(), 0)


func _setup_sync() -> void:
	_sync = MultiplayerSynchronizer.new()
	var cfg := SceneReplicationConfig.new()
	for prop in ["sync_position", "sync_velocity", "aim_angle", "facing", "health", "kills", "deaths", "weapon", "mag_ammo", "grenades", "alive", "fuel", "life_state", "_shots_fired", "_shots_hit"]:
		cfg.add_property(NodePath(prop))
		# v3.3 QA-051: set the replication mode explicitly — never
		# rely on the SceneReplicationConfig default. Every property
		# is ALWAYS replicated, and spawns with its current value so
		# a late-joining peer gets the live state at once.
		cfg.property_set_replication_mode(NodePath(prop), SceneReplicationConfig.REPLICATION_MODE_ALWAYS)
		cfg.property_set_spawn(NodePath(prop), true)
	_sync.replication_config = cfg
	_sync.replication_interval = 0.033 # 30 snapshots/s (GAP-60, spec §21.F)
	# v3.3 QA-051: the synchronizer's OWN authority was never set,
	# so it stayed the server (1) on every copy — a client's
	# sync_position writes never left the client, and the host
	# re-broadcast its stale spawn-point sync_position back. The
	# player root's authority (set in _enter_tree from the node
	# name) does NOT propagate to the synchronizer. Set it
	# explicitly to the owning peer, and pin root_path to the
	# player explicitly instead of relying on the default.
	var owner_id: int = peer_id if peer_id > 0 else get_multiplayer_authority()
	_sync.set_multiplayer_authority(owner_id)
	_sync.root_path = NodePath("..")
	add_child(_sync)


# v3.3 QA-051: test hooks for the repl-sim — the synchronizer's own
# authority and a property's replication mode, so the sim can assert
# the configuration instead of only the player root's authority.
func get_sync_authority() -> int:
	if _sync == null:
		return -1
	return _sync.get_multiplayer_authority()


func get_sync_replication_mode(prop: String) -> int:
	if _sync == null or _sync.replication_config == null:
		return -1
	return _sync.replication_config.property_get_replication_mode(NodePath(prop))


func _process(delta: float) -> void:
	# Rendering only (GAP-69, spec §23.E): sprite/gun/camera/HP visuals
	# run at the render frame, never in _physics_process. Nothing here
	# writes position or velocity (camera position is a view offset).
	_update_visuals(delta)
	if is_local_player() and _camera != null:
		_update_camera(delta)


func _physics_process(delta: float) -> void:
	_spawn_protect_timer = maxf(0.0, _spawn_protect_timer - delta)
	_shake_trauma = maxf(0.0, _shake_trauma - delta * 1.8)
	_gun_kick = maxf(0.0, _gun_kick - delta * 7.0)
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
		return
	if is_local_player():
		_read_input()
		_apply_movement(delta)
		_apply_aim_and_fire(delta)
		_check_stuck(delta)
		sync_position = position
		sync_velocity = velocity
	else:
		# Remote players: 100 ms interpolation buffer (GAP-16, spec
		# §21.D/F). Snapshots are timestamped on receipt; render at
		# now - 100 ms between the bracketing snapshots, extrapolating
		# at most one physics step past the newest snapshot.
		var now := Time.get_ticks_msec() / 1000.0
		if sync_position != _last_snap_pos or sync_velocity != _last_snap_vel:
			_snapshots.append({"t": now, "p": sync_position, "v": sync_velocity})
			_last_snap_pos = sync_position
			_last_snap_vel = sync_velocity
			while _snapshots.size() > 12:
				_snapshots.pop_front()
		position = _interp_position(now)
		velocity = sync_velocity
		_update_remote_anim()


func _interp_position(now: float) -> Vector2:
	var render_t := now - PhysicsConfig.INTERP_BUFFER
	if _snapshots.size() < 2:
		return position.lerp(sync_position, clampf(1.0 / 60.0 * 14.0, 0.0, 1.0))
	var first: Dictionary = _snapshots[0]
	var last: Dictionary = _snapshots[_snapshots.size() - 1]
	if render_t <= float(first["t"]):
		return first["p"]
	if render_t >= float(last["t"]):
		# Extrapolate at most one physics step past the newest snapshot.
		var dt := minf(render_t - float(last["t"]), 1.0 / 60.0)
		return last["p"] + last["v"] * dt
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
	# merely pushing against a wall — that is normal play.
	_stuck_check_timer += delta
	if _stuck_check_timer < PhysicsConfig.STUCK_CHECK_INTERVAL:
		return
	_stuck_check_timer = 0.0
	var game = get_tree().get_first_node_in_group("game")
	if game == null:
		return
	# Query capsule is 3 px smaller than the real one (radius 14,
	# height 46): move_and_slide leaves ~1 px of solver penetration
	# when the player pushes flush against a wall, and that is NOT
	# being stuck — a real embed is 10+ px deep and still triggers.
	var cap := CapsuleShape2D.new()
	cap.radius = 14.0
	cap.height = 46.0
	var q := PhysicsShapeQueryParameters2D.new()
	q.shape = cap
	q.transform = Transform2D(0.0, global_position)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var space := get_world_2d().direct_space_state
	if not space.intersect_shape(q, 1).is_empty():
		var spot: Vector2 = game.get_valid_spawn_point(player_index, peer_id)
		print("STUCK-RECOVERY: player %d was inside solid geometry, moved to %s" % [peer_id, str(spot)])
		position = spot
		sync_position = position
		velocity = Vector2.ZERO


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
	# Clamp the view inside the map (hard limits, spec §19).
	var vp := get_viewport().get_visible_rect().size
	var ms: Vector2 = game.map_size
	var hx := minf(vp.x * 0.5, ms.x * 0.5)
	var hy := minf(vp.y * 0.5, ms.y * 0.5)
	target.x = clampf(target.x, hx, maxf(hx, ms.x - hx))
	target.y = clampf(target.y, hy, maxf(hy, ms.y - hy))
	_camera.position = target - global_position


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
	# Stick-up jump: only on the rising edge, and only while "armed".
	# Holding the stick up through a landing must NOT auto-jump again —
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
	# v3.2: firing comes from the AIM stick (see game.gd) — the right
	# stick aims AND fires while held. Semi-auto weapons (pistol,
	# shotgun, sniper) fire one shot per fresh deflection.
	_want_fire = game.touch_firing
	# Peek at the pending semi-auto shot — do NOT consume it here.
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
		var mouse_pos := get_viewport().get_mouse_position()
		# Mouse aims only — it never fires (the right stick shoots).
		# Clicks on HUD controls (fire / grenade / weapon / pause /
		# score / reload) must not swing the aim.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not game.is_hud_control_pos(mouse_pos):
			var center := get_viewport().get_visible_rect().size * 0.5
			var dir := mouse_pos - center
			if dir.length() > 40.0:
				_aim_dir = dir.normalized()
				_aiming = true


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
		accel = ACCEL_AIR
		drag = DRAG_AIR
	if _move_axis != 0.0:
		# Reversal bonus (GAP-01): flicking against current motion
		# reverses crisply on ground (1.6x), lazily in air (1.2x).
		var rate := accel
		if signf(_move_axis) != signf(velocity.x) and velocity.x != 0.0:
			rate = accel * (REVERSAL_GROUND if on_floor else REVERSAL_AIR)
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
	# Jump buffering + coyote time: jumping feels reliable even if the
	# button is pressed a moment before landing / after leaving a ledge.
	if _jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	if on_floor:
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_jetpacking = false
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_jump_cut_armed = true
		_play_sound("jump")
	elif _jump_held and not on_floor and fuel > 0.0:
		# Jetpack sustains a climb, it never chops jump momentum:
		# thrust applies only while rising SLOWER than the cap, so
		# a -660 jump is not clamped down to -450 when fuel regens
		# mid-rise (air regen, GAP-05, used to do exactly that).
		if velocity.y > -MAX_JET_RISE:
			velocity.y -= JET_ACCEL * delta
			if velocity.y < -MAX_JET_RISE:
				velocity.y = -MAX_JET_RISE
			fuel = maxf(0.0, fuel - FUEL_DRAIN * delta)
			_fuel_delay_timer = FUEL_REGEN_DELAY
			_jetpacking = true
			_jump_cut_armed = false
			_start_jetpack_sound()
		else:
			_stop_jetpack_sound()
	else:
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
	var max_fall := MAX_FALL + (350.0 if _fast_fall else 0.0)
	if velocity.y > max_fall:
		velocity.y = max_fall
	_fall_speed = velocity.y
	_was_on_floor = on_floor
	move_and_slide()
	if is_on_floor():
		_jump_cut_armed = false
	if is_on_floor() and not _was_on_floor and _fall_speed > 550.0:
		# Hard landing: small dust puff.
		var game2 = get_tree().get_first_node_in_group("game")
		if game2 != null:
			game2.spawn_impact_fx(global_position + Vector2(0, 26), true)
	var game3 = get_tree().get_first_node_in_group("game")
	if game3 != null and position.y > game3.map_size.y + 200.0:
		_respawn()


func _apply_aim_and_fire(delta: float) -> void:
	# FIRING lasts exactly one physics frame (GAP-41).
	if weapon_state == WeaponState.FIRING:
		weapon_state = WeaponState.RELOADING if reloading else WeaponState.READY
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
		# A flick during reload does nothing — discard the edge so it
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
			# (auto) — one edge, one shot, never more.
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
	if not alive:
		_play_anim("die")
		return
	if not is_on_floor():
		if velocity.y < -50.0:
			_play_anim("jetpack" if velocity.y < -380.0 and fuel < FUEL_MAX else "jump")
		elif velocity.y > 50.0:
			_play_anim("fall")
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
	var muzzle := global_position + Vector2(8 * facing, 5) + dir * (GUN_LENGTH + 6.0)
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
			var sp := float(w["spread"]) + _recoil_accum * 0.5
			d = d.rotated(randf_range(-sp, sp))
		# Velocity inheritance (GAP-55, spec §20.C): the bullet keeps
		# 0.15 of the shooter's velocity. spawn_bullet carries the
		# full velocity vector; bullet.gd integrates it.
		var bvel: Vector2 = d * float(w["speed"]) + velocity * PhysicsConfig.VELOCITY_INHERITANCE
		rpc("spawn_bullet", muzzle, d, float(w["speed"]), int(w["damage"]), weapon, peer_id, _shots_fired * 10 + i, bvel)
	_play_sound(str(w["sound"]))
	_show_muzzle()
	# Weapon feel: velocity kick opposite the shot, camera shake for
	# the heavy weapons, and a visible gun kick (grows with _recoil_accum).
	velocity -= dir * float(w.get("recoil", 0.0))
	add_shake(float(w.get("shake", 0.0)))
	_gun_kick = 1.0 + _recoil_accum
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


func _show_muzzle() -> void:
	_muzzle.visible = true
	_muzzle.scale = Vector2(1.2, 1.2)
	get_tree().create_timer(0.05).timeout.connect(_hide_muzzle)


func _hide_muzzle() -> void:
	_muzzle.visible = false


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
	var owned: Array = owned_weapons()
	var idx := owned.find(weapon)
	var next_w: int = owned[(idx + 1) % owned.size()]
	weapon = next_w
	mag_ammo = int(WEAPONS[weapon]["mag"])
	reloading = false
	# v3.2: a pending semi-auto flick belongs to the old weapon — drop
	# it so switching cannot fire a shot nobody asked for.
	var game_sw = get_tree().get_first_node_in_group("game")
	if game_sw != null:
		game_sw.consume_aim_fire_edge()
	_update_gun_texture()
	_play_sound("click")


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
	rpc("spawn_grenade", global_position + Vector2(0, -6), dir, peer_id)
	_play_sound("click")


@rpc("any_peer", "call_local")
func spawn_bullet(pos: Vector2, dir: Vector2, speed: float, damage: int, kind: int, owner_id: int, shot_no: int, bvel: Vector2 = Vector2.INF) -> void:
	# Host-authoritative shooting (v2.4): the server validates every
	# shot's fire rate and ammunition before simulating it. Only the
	# server's simulation can deal damage, so a rejected shot can
	# never hurt anyone — the shooter's local copy is visual only.
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
		170.0 if bool(WEAPONS[kind]["explosive"]) else 0.0,
		float(WEAPONS[kind].get("life", 1.4)),
		shot_no, vel, float(WEAPONS[kind].get("gravity", 0.0)))
	if b.get_parent() == null:
		game2.bullets_node.add_child(b)


@rpc("any_peer", "call_local")
func spawn_grenade(pos: Vector2, dir: Vector2, owner_id: int) -> void:
	var node = get_tree().get_first_node_in_group("game")
	if node == null:
		return
	var g = GRENADE_SCENE.instantiate()
	g.name = "g_%d_%d" % [owner_id, Time.get_ticks_msec()]
	g.position = pos
	g.throw_dir = dir
	g.owner_id = owner_id
	node.grenades_node.add_child(g)


@rpc("any_peer")
func take_damage(amount: int, from_id: int) -> void:
	# Host-authoritative health (v2.4): only the host (peer 1) may
	# inflict damage — a client calling this directly is ignored.
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
			m_dist = lerpf(1.0, PhysicsConfig.DAMAGE_FALLOFF_MIN, f)
	var m_weapon: float = float(WeaponData.get_weapon(weapon_id).get("damage_mult", 1.0))
	return int(round(float(base) * m_region * m_dist * m_weapon))


func _apply_damage(amount: int, from_id: int, dir: Vector2, knockback: float, event_id: int) -> void:
	# Single place where health actually changes (spec §17.8).
	# Guards: death happens only once per life (life_state, GAP-44).
	if life_state != LifeState.ALIVE:
		return
	if _spawn_protect_timer > 0.0:
		return
	health -= amount
	# Per-weapon victim knockback (GAP-46): a velocity add, so
	# move_and_slide resolves it against collision next frame —
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
	_play_sound("pickup")


# Phase 4 — accuracy: one trigger pull counts as a hit once, however
# many of its pellets land (a shotgun's 7 pellets are one shot, not
# seven). shot_no is _shots_fired * 10 + pellet index, so the key is
# shot_no / 10. Called by the host only.
func record_hit(shot_no: int) -> void:
	var key := shot_no / 10
	if _hit_shot_keys.has(key):
		return
	_hit_shot_keys.append(key)
	_shots_hit += 1


# Phase 4 — hitmarker: the host confirms each hit to the shooter
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
		weapon = kind
		mag_ammo = int(WEAPONS[kind]["mag"])
		_reserve[kind] = int(RESERVE_DEFAULT.get(kind, 0))
		reloading = false
		weapon_state = WeaponState.READY
		_update_gun_texture()
	elif kind == 5:
		health = mini(100, health + 50)
	elif kind == 6:
		grenades = mini(4, grenades + 2)
	_play_sound("pickup")


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
	mag_ammo = int(WEAPONS[0]["mag"])
	reloading = false
	weapon_state = WeaponState.READY
	_reload_transfer = 0
	_recoil_accum = 0.0
	_anim_locked = false
	_fast_fall = false
	_stick_up_prev = false
	_stick_up_armed = true
	_jump_cut_armed = false
	_round_dead = false
	_shake_trauma = 0.0
	_gun_kick = 0.0
	# Discard a stale pending shot so a finger held while dead
	# cannot fire a shot the instant we respawn.
	var game0 = get_tree().get_first_node_in_group("game")
	if game0 != null:
		game0.consume_aim_fire_edge()
	position = spot
	sync_position = position
	velocity = Vector2.ZERO
	sync_velocity = Vector2.ZERO
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
	_sprite.scale.x = float(facing)
	# Gun follows the aim angle exactly; flips upright when aiming left.
	_gun.rotation = aim_angle
	_gun.scale = Vector2(_gun_base_scale, _gun_base_scale * (-1.0 if cos(aim_angle) < 0.0 else 1.0))
	# Gun kick: the barrel jumps back along the aim direction right
	# after a shot and settles back (decays in _physics_process).
	var kick := Vector2(cos(aim_angle), sin(aim_angle)) * _gun_kick * 7.0
	_gun.position = Vector2(8 * facing, 5) - kick
	# Jetpack flame (GAP-06, spec §5): tied to the REAL thrust state,
	# never to the animation name. Off = hidden, thrusting = visible
	# with length by thrust, low fuel = blink, empty/descending = gone.
	if _flame != null:
		var thrusting := _jetpacking and fuel > 0.0
		_flame.visible = thrusting and alive
		if thrusting:
			var frac := 0.6 + 0.6 * clampf(absf(velocity.y) / MAX_JET_RISE, 0.0, 1.0)
			_flame.scale = Vector2(1.0 + 0.15 * sin(Time.get_ticks_msec() / 40.0), frac)
			if fuel < PhysicsConfig.FUEL_LOW_WARN:
				_flame.modulate = Color(1.0, 0.4, 0.1, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0))
			else:
				_flame.modulate = Color(1.0, 0.55, 0.15, 0.95)
	_gun.visible = alive
	# Camera shake: trauma decays in _physics_process; the offset is
	# trauma squared so small shakes stay subtle and big ones punch.
	if _camera != null:
		var s := _shake_trauma * _shake_trauma * 16.0
		_camera.offset = Vector2(randf_range(-s, s), randf_range(-s, s)) if s > 0.05 else Vector2.ZERO
	_helmet_sprite.visible = alive
	_ring.visible = alive
	_name_label.visible = alive
	_hp_bg.visible = alive
	_hp_fg.visible = alive
	if _hit_flash_timer > 0.0:
		_hit_flash_timer -= delta
		_sprite.modulate = Color(3.0, 0.6, 0.6)
		if _hit_flash_timer <= 0.0:
			_sprite.modulate = Color.WHITE
	elif _spawn_protect_timer > 0.0:
		# Spawn protection: blink so other players can see it.
		_sprite.modulate = Color(1, 1, 1, 0.55 + 0.35 * sin(Time.get_ticks_msec() / 90.0))
	else:
		_sprite.modulate = Color.WHITE
	_hp_fg.size.x = 44.0 * clampf(float(health) / 100.0, 0.0, 1.0)
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
