extends CharacterBody2D

# Animated soldier: analog run, jump, jetpack, full 360-degree aim.
# Each peer owns its own player (multiplayer authority); a
# MultiplayerSynchronizer replicates state to the other peers.
# The soldier art has a rifle baked in; a separate weapon sprite is drawn
# at the hands and rotated to the exact aim angle so the weapon always
# points where the right stick points.

const SPEED := 330.0
const ACCEL := 2600.0
const DECEL := 3400.0
const JUMP_VELOCITY := -660.0
const JET_ACCEL := 1900.0
const MAX_JET_RISE := 430.0
const GRAVITY := 1400.0
const MAX_FALL := 950.0
const FUEL_MAX := 100.0
const FUEL_DRAIN := 45.0
const FUEL_REFILL := 70.0
const COYOTE_TIME := 0.10
const JUMP_BUFFER := 0.12
const AIM_DEAD_ZONE := 0.25
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
		position = game.get_spawn_point(player_index)
		_audio = game.audio
	sync_position = position
	if is_local_player():
		var cam := Camera2D.new()
		cam.position_smoothing_enabled = true
		cam.position_smoothing_speed = 7.0
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
	for prop in ["sync_position", "sync_velocity", "aim_angle", "facing", "health", "kills", "deaths", "weapon", "mag_ammo", "grenades", "alive", "fuel"]:
		cfg.add_property(NodePath(prop))
	_sync.replication_config = cfg
	_sync.replication_interval = 0.05
	add_child(_sync)


func _physics_process(delta: float) -> void:
	_update_visuals(delta)
	_spawn_protect_timer = maxf(0.0, _spawn_protect_timer - delta)
	_shake_trauma = maxf(0.0, _shake_trauma - delta * 1.8)
	_gun_kick = maxf(0.0, _gun_kick - delta * 7.0)
	var game = get_tree().get_first_node_in_group("game")
	if game != null and game.match_over:
		# Match over: stand still, idle animation only.
		velocity = Vector2.ZERO
		if alive:
			_play_anim("idle")
		return
	if not alive:
		if is_local_player():
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
		sync_position = position
		sync_velocity = velocity
	else:
		# Smoothly follow the synced state from the owning peer.
		position = position.lerp(sync_position, clampf(delta * 14.0, 0.0, 1.0))
		velocity = sync_velocity
		_update_remote_anim()


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
		_aim_dir = game.touch_aim * GameData.sensitivity
		if _aim_dir.length() > 1.0:
			_aim_dir = _aim_dir.normalized()
		_aiming = _aim_dir.length() > AIM_DEAD_ZONE
	# v2.4: firing comes ONLY from the FIRE button (see game.gd).
	# The aim stick is aim-only and never fires. Semi-auto weapons
	# (pistol, shotgun, sniper) fire one shot per fresh press.
	_want_fire = game.touch_firing
	# Peek at the press edge — do NOT consume it here. _read_input
	# runs in _physics_process but touch_firing only updates in
	# _process, so a tap that lands just after a physics step would
	# otherwise be consumed on a frame where _want_fire is still
	# false and the semi-auto shot would be lost entirely (the tap
	# would do nothing on a real phone too). The edge is consumed in
	# _apply_aim_and_fire when the shot actually fires, and discarded
	# on respawn / while reloading.
	_fire_edge = false
	if game.fire_button != null:
		_fire_edge = game.fire_button.has_press_edge()
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
		# Mouse aims only — it never fires (the FIRE button shoots).
		# Clicks on HUD controls (fire / grenade / weapon / pause /
		# score / reload) must not swing the aim.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not game.is_hud_control_pos(mouse_pos):
			var center := get_viewport().get_visible_rect().size * 0.5
			var dir := mouse_pos - center
			if dir.length() > 40.0:
				_aim_dir = dir.normalized()
				_aiming = true


func _apply_movement(delta: float) -> void:
	var target_vx := _move_axis * SPEED
	if _move_axis != 0.0:
		velocity.x = move_toward(velocity.x, target_vx, ACCEL * delta)
	else:
		velocity.x = move_toward(velocity.x, 0.0, DECEL * delta)
	# Jump buffering + coyote time: jumping feels reliable even if the
	# button is pressed a moment before landing / after leaving a ledge.
	if _jump_pressed:
		_jump_buffer_timer = JUMP_BUFFER
	else:
		_jump_buffer_timer = maxf(0.0, _jump_buffer_timer - delta)
	if is_on_floor():
		_coyote_timer = COYOTE_TIME
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_jetpacking = false
	if _jump_buffer_timer > 0.0 and _coyote_timer > 0.0:
		velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0
		_play_sound("jump")
	elif _jump_held and not is_on_floor() and fuel > 0.0:
		velocity.y -= JET_ACCEL * delta
		if velocity.y < -MAX_JET_RISE:
			velocity.y = -MAX_JET_RISE
		fuel = maxf(0.0, fuel - FUEL_DRAIN * delta)
		_jetpacking = true
		_start_jetpack_sound()
	else:
		_stop_jetpack_sound()
	if is_on_floor():
		fuel = minf(FUEL_MAX, fuel + FUEL_REFILL * delta)
	velocity.y += GRAVITY * delta
	# v2.2: pushing the left stick down while airborne fast-falls.
	if _fast_fall and not is_on_floor() and not _jetpacking:
		velocity.y += FAST_FALL_EXTRA * delta
	var max_fall := MAX_FALL + (350.0 if _fast_fall else 0.0)
	if velocity.y > max_fall:
		velocity.y = max_fall
	_fall_speed = velocity.y
	_was_on_floor = is_on_floor()
	move_and_slide()
	if is_on_floor() and not _was_on_floor and _fall_speed > 550.0:
		# Hard landing: small dust puff.
		var game = get_tree().get_first_node_in_group("game")
		if game != null:
			game.spawn_impact_fx(global_position + Vector2(0, 26), true)
	var game2 = get_tree().get_first_node_in_group("game")
	if game2 != null and position.y > game2.map_size.y + 200.0:
		_respawn()


func _apply_aim_and_fire(delta: float) -> void:
	# Face the aim direction while aiming, else face the move direction.
	if _aiming:
		aim_angle = _aim_dir.angle()
		if absf(cos(aim_angle)) > 0.15:
			facing = -1 if cos(aim_angle) < 0.0 else 1
	elif _move_axis != 0.0:
		facing = -1 if _move_axis < 0.0 else 1
		aim_angle = 0.0 if facing > 0 else PI
	_fire_cooldown -= delta
	_grenade_cooldown -= delta
	if reloading:
		_reload_timer -= delta
		if _reload_timer <= 0.0:
			reloading = false
			mag_ammo = int(WEAPONS[weapon]["mag"])
		# A tap during reload does nothing — discard the edge so it
		# cannot fire a shot the moment the reload finishes.
		var game_r = get_tree().get_first_node_in_group("game")
		if game_r != null and game_r.fire_button != null:
			game_r.fire_button.consume_press_edge()
	elif _want_fire and _fire_cooldown <= 0.0:
		# v2.4: firing no longer requires aiming — without aim input
		# the shot goes in the character's facing direction. Automatic
		# weapons fire while held; semi-auto weapons (pistol, shotgun,
		# sniper) fire one shot per fresh FIRE press.
		var w: Dictionary = WEAPONS[weapon]
		var semi: bool = not bool(w.get("auto", true))
		if not semi or _fire_edge:
			_fire()
			if semi:
				# The tap has now produced its one shot.
				var game_f = get_tree().get_first_node_in_group("game")
				if game_f != null and game_f.fire_button != null:
					game_f.fire_button.consume_press_edge()
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
	var dir := Vector2(cos(aim_angle), sin(aim_angle))
	var muzzle := global_position + Vector2(8 * facing, 5) + dir * (GUN_LENGTH + 6.0)
	var pellets: int = int(w["pellets"])
	for i in pellets:
		var d := dir
		# Spread is per-pellet from the weapon's own table value.
		if float(w["spread"]) > 0.0:
			d = d.rotated(randf_range(-float(w["spread"]), float(w["spread"])))
		rpc("spawn_bullet", muzzle, d, float(w["speed"]), int(w["damage"]), weapon, peer_id, _shots_fired * 10 + i)
	_play_sound(str(w["sound"]))
	_show_muzzle()
	# Weapon feel: velocity kick opposite the shot, camera shake for
	# the heavy weapons, and a visible gun kick.
	velocity -= dir * float(w.get("recoil", 0.0))
	add_shake(float(w.get("shake", 0.0)))
	_gun_kick = 1.0
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
	_reload_timer = float(WEAPONS[weapon]["reload"])
	_play_sound("reload")


func switch_weapon() -> void:
	if not alive or owned_weapons().size() <= 1:
		return
	var owned: Array = owned_weapons()
	var idx := owned.find(weapon)
	var next_w: int = owned[(idx + 1) % owned.size()]
	weapon = next_w
	mag_ammo = int(WEAPONS[weapon]["mag"])
	reloading = false
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
func spawn_bullet(pos: Vector2, dir: Vector2, speed: float, damage: int, kind: int, owner_id: int, shot_no: int) -> void:
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
	b.setup(pos, dir, speed, damage, kind, owner_id,
		bool(WEAPONS[kind]["explosive"]),
		170.0 if bool(WEAPONS[kind]["explosive"]) else 0.0,
		float(WEAPONS[kind].get("life", 1.4)),
		shot_no)
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
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not alive:
		return
	if _spawn_protect_timer > 0.0:
		return
	health -= amount
	_hit_flash_timer = 0.09
	_play_sound("hurt")
	if health <= 0:
		health = 0
		alive = false
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
func take_explosion_damage(pos: Vector2, radius: float, damage: int, from_id: int) -> void:
	# Host-authoritative, like take_damage: only the host may call.
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if not alive:
		return
	if _spawn_protect_timer > 0.0:
		return
	var dist := global_position.distance_to(pos)
	if dist > radius:
		return
	var falloff := 1.0 - dist / radius
	var amount := int(round(damage * (0.4 + 0.6 * falloff)))
	# Knockback away from the blast.
	var dir := (global_position - pos).normalized()
	velocity += dir * 550.0 * falloff + Vector2(0, -220.0 * falloff)
	take_damage(amount, from_id)


@rpc("any_peer")
func add_kill() -> void:
	# Only the host may award a kill (it decided the lethal hit).
	var sender := multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	kills += 1
	_play_sound("pickup")


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
		reloading = false
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
	health = 100
	alive = true
	fuel = FUEL_MAX
	_spawn_protect_timer = SPAWN_PROTECTION
	weapon = 0
	_owned_extra.clear()
	mag_ammo = int(WEAPONS[0]["mag"])
	reloading = false
	_anim_locked = false
	_fast_fall = false
	_stick_up_prev = false
	_stick_up_armed = true
	_round_dead = false
	_shake_trauma = 0.0
	_gun_kick = 0.0
	# Discard a stale FIRE press edge so a finger held while dead
	# cannot fire a shot the instant we respawn.
	var game0 = get_tree().get_first_node_in_group("game")
	if game0 != null and game0.fire_button != null:
		game0.fire_button.consume_press_edge()
	var game = get_tree().get_first_node_in_group("game")
	if game != null:
		position = game.get_spawn_point(player_index)
	sync_position = position
	velocity = Vector2.ZERO
	sync_velocity = Vector2.ZERO
	_collision_shape.set_deferred("disabled", false)
	_update_gun_texture()
	_play_anim("idle")
	_play_sound("spawn")
	if _camera != null:
		_camera.reset_smoothing()


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
