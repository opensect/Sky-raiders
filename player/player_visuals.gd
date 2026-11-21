class_name PlayerVisuals
extends RefCounted


# QA-140 (v3.15): extracted from player/player.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `p` (dependency injection).


var p # the owner (player/player.gd)

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
const FLAME_TEX: Texture2D = preload("res://assets/user_assets_v3/jetpack_flame_normal.png")
# QA-137: the boost flame (bigger, blue core) from the user's
# jetpack sheet - shown while the Jetpack Boost power-up runs.
const FLAME_TEX_BOOST: Texture2D = preload("res://assets/user_assets_v3/jetpack_flame_boost.png")
# QA-137: the soldier frames now come from the user's character
# sheet (assets/user_assets_v3/soldier_new_r<R>_c<C>.png, 5 rows x
# 6 cols, labels excluded at slice time). Each row holds one
# animation group; the game needs 11 frames per animation (5 for
# die), so the source frames ping-pong: [0,1,2,3,4,5,4,3,2,1,0],
# wrapped modulo the group's frame count. Row 5 col 1 is empty
# (the label only), so die uses cols 4-6 (damage, fall, lying
# down, held). The gun is NOT in the art (only the row-4 aim poses
# hold a rifle), so the gun sprite still rides the hand anchor
# (QA-127). The game has NO slide animation - the slide frames in
# row 5 are unused (see BUGS.md QA-137).
const _QA137_PINGPONG := [0, 1, 2, 3, 4, 5, 4, 3, 2, 1, 0]
const _QA137_ANIM_CELLS := {
	"idle": [Vector2i(1, 1), Vector2i(1, 2)],
	"run": [Vector2i(1, 3), Vector2i(1, 4), Vector2i(1, 5), Vector2i(1, 6)],
	"jump": [Vector2i(2, 1), Vector2i(2, 2), Vector2i(2, 3)],
	"fall": [Vector2i(2, 4), Vector2i(2, 5), Vector2i(2, 6)],
	"jetpack": [Vector2i(3, 1), Vector2i(3, 2), Vector2i(3, 3), Vector2i(3, 4), Vector2i(3, 5), Vector2i(3, 6)],
	"shoot": [Vector2i(4, 3), Vector2i(4, 6)],
	"aim": [Vector2i(4, 3), Vector2i(4, 6)],
	"die": [Vector2i(5, 4), Vector2i(5, 5), Vector2i(5, 6), Vector2i(5, 6), Vector2i(5, 6)],
}
# QA-094: per-animation helmet height. The helmet rides the body
# sprite at a fixed offset, but the art frames do not share one
# head height (measured hair-top, 64px frame: idle 8, run 9,
# jump 5, shoot 6, aim 6, fall 8, jetpack 6, die 15). Without
# this the helmet floats ~20px above the head while jetpacking.
# Helmet centre = hair_top - 33 in sprite-local units.
# QA-137: re-measured on the user's character sheet (the jetpack
# frames now put the head near the top of the frame, so jetpack
# is -27, not the old -8; the die frames are more upright, so die
# is -18, not the old 3).
const HELMET_Y_BY_ANIM := {"idle": -26.0, "run": -25.0, "jump": -28.0, "shoot": -27.0, "aim": -27.0, "fall": -25.0, "jetpack": -27.0, "die": -18.0}
# QA-094: per-frame helmet centre (sprite-local) for the jetpack
# animation - the flying pose sways the head side-to-side, so a
# fixed offset floats off the head at the extremes. Measured from
# the art (helmet centre = face centre, y = face top - 33);
# verified by overlaying the helmet on all 11 frames. The negative
# parent scale mirrors these automatically when the player faces
# left. QA-137: re-measured on the user's sheet - the new flying
# pose is nearly upright, so the sway is only -2..+1 px.
const HELMET_JETPACK_FRAMES := [Vector2(1, -28), Vector2(-1, -27), Vector2(1, -27), Vector2(1, -26), Vector2(1, -26), Vector2(-2, -29), Vector2(1, -26), Vector2(1, -26), Vector2(1, -27), Vector2(-1, -27), Vector2(1, -28)]
# QA-127 (v3.11): hand anchors - where the TRIGGER hand grips the
# rifle, measured from the art (64px frames, frame coords - (32, 32);
# facing right). Values are in FRAME units; _hand_anchor() scales
# them by PLAYER_SCALE because the gun is a sibling of the scaled
# sprite, not a child of it (the helmet rides the sprite, the gun
# does not). The gun's GRIP sits on the anchor and the gun rotates
# to the aim angle around it, so the weapon reads as HELD instead
# of floating. QA-137: re-measured on the user's sheet. The new
# soldier holds NO gun in most poses (only the row-4 aim poses
# hold a rifle), so the anchor is the torso at waist height
# (y 7) for idle/run/jump/fall/jetpack/die, and the chest-height
# rifle grip (5, -6) for shoot/aim. Verified by overlaying the gun
# on the frames - see BUGS.md QA-137.
const HAND_ANCHOR_BY_ANIM := {"idle": Vector2(0, 7), "run": Vector2(0, 7), "jump": Vector2(0, 7), "shoot": Vector2(5, -6), "aim": Vector2(5, -6), "fall": Vector2(0, 7), "die": Vector2(0, 6)}
const HAND_IDLE_FRAMES := [Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7)]
const HAND_JETPACK_FRAMES := [Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 6), Vector2(-1, 7), Vector2(0, 6), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7), Vector2(0, 7)]
# QA-127: per-weapon grip - (x fraction along the weapon texture
# where the trigger hand sits, y px below the barrel line in game
# units). Measured from assets/weapons/*.png (trigger grip, not the
# magazine - the magazine hangs lower but the hand holds the grip).
const WEAPON_GRIP := {0: Vector2(0.34, 1.5), 1: Vector2(0.37, 2.0), 2: Vector2(0.23, 2.0), 3: Vector2(0.43, 3.0), 4: Vector2(0.47, 3.5), 5: Vector2(0.47, 5.0)}
const INVISIBILITY_ALPHA := 0.1 # QA-119: 90% invisible - enemies see ~10% (user 2026-11-20 ~20:52)



func _init(owner) -> void:
	p = owner


func _build_sprite() -> void:
	p._sprite = AnimatedSprite2D.new()
	p._sprite.name = "Sprite"
	p._sprite.sprite_frames = _make_sprite_frames()
	p._sprite.centered = true
	# QA-071b: the soldier art scales 1.20x (64 px frame -> 77 px on
	# screen). _update_visuals keeps this scale and only flips x for
	# facing. The helmet is a child of the sprite, so it scales too.
	p._sprite.scale = Vector2(p.PLAYER_SCALE, p.PLAYER_SCALE)
	p.add_child(p._sprite)

	p._helmet_sprite = Sprite2D.new()
	p._helmet_sprite.name = "Helmet"
	p._helmet_sprite.position = Vector2(0, -26)
	p._helmet_sprite.z_index = 2
	p._sprite.add_child(p._helmet_sprite)
	_update_helmet()

	# Team / player colour ring under the feet (QA-071b: 24 -> 29 px
	# radii, y 26 -> 31, wobble 7 -> 8).
	p._ring = Polygon2D.new()
	var pts := PackedVector2Array()
	for i in 24:
		var a := TAU * float(i) / 24.0
		pts.append(Vector2(cos(a) * 29.0, 31.0 + sin(a) * 8.0))
	p._ring.polygon = pts
	p._ring.color = Color(p.player_color.r, p.player_color.g, p.player_color.b, 0.55)
	p._ring.z_index = -1
	p.add_child(p._ring)

	# QA-112: blue shield ring, shown while the shield boost is up.
	# A Polygon2D circle outline (outer 50 px, inner 45 px), drawn
	# as one ring band; _update_visuals toggles it. No flag sprite
	# here - game.gd draws the carried flag above the carrier, so a
	# second flag from this file would show two flags.
	p._shield_ring = Polygon2D.new()
	p._shield_ring.name = "ShieldRing"
	var shield_pts := PackedVector2Array()
	for i in 32:
		var a := TAU * float(i) / 32.0
		shield_pts.append(Vector2(cos(a) * 50.0, sin(a) * 50.0))
		shield_pts.append(Vector2(cos(a) * 45.0, sin(a) * 45.0))
	p._shield_ring.polygon = shield_pts
	p._shield_ring.color = Color(0.3, 0.6, 1.0, 0.7)
	p._shield_ring.z_index = 2
	p._shield_ring.visible = false
	p.add_child(p._shield_ring)
	# QA-119 (v3.11): active power-up effect layers - the 512x512
	# effect images from assets/powerups_effects/, layered on the
	# player while the power-up is active (animated in-engine:
	# rotation / pulse / fade in _update_visuals). Jetpack Boost has
	# NO effect image in the pack - it keeps the jetpack flame.
	# The wind whirlpool is a flat solid disc, so it is drawn small
	# and faded and spins fast; if it ever looks wrong in-game it is
	# replaced by the code-drawn wind effect.
	# QA-137: the shield dome is the user's energy-dome art
	# (assets/user_assets_v3/shield_dome.png, 1440 px wide), so the
	# scale drops from 0.30 (512 px art) to 0.11 to keep the same
	# ~154 px on-screen size. Same for the thunder bolt below.
	p._fx_shield = _make_fx_sprite("res://assets/user_assets_v3/shield_dome.png", 0.11)
	p._fx_speed = _make_fx_sprite("res://assets/powerups_effects/02_speed_boost_motion_trails_effect.png", 0.26)
	p._fx_health = _make_fx_sprite("res://assets/powerups_effects/03_health_healing_aura_effect.png", 0.28)
	p._fx_wind = _make_fx_sprite("res://assets/powerups_effects/05_wind_whirlpool_vortex_effect.png", 0.34)
	p._fx_thunder = _make_fx_sprite("res://assets/user_assets_v3/thunder_strike.png", 0.15)
	p._fx_invis = _make_fx_sprite("res://assets/powerups_effects/07_invisibility_shimmer_cloak_effect.png", 0.30)

	# Rotated weapon sprite at the hands (pivot = stock).
	p._gun = Sprite2D.new()
	p._gun.name = "Gun"
	p._gun.position = Vector2(10, 6) # QA-071b: (8, 5) * 1.20
	p._gun.z_index = 3
	p.add_child(p._gun)

	# QA-137: the flame is the user's jetpack art now (was a plain
	# orange triangle, then a 32x64 flame sprite). Normal flame is
	# 442x492, drawn 20x22 px (aspect kept); the boost flame is
	# 616x926, drawn 30x33 px while the boost runs (see the scale
	# code in _update_visuals). centered=false so the sprite grows
	# DOWN from y=22 exactly like the triangle did.
	p._flame = Sprite2D.new()
	p._flame.name = "JetFlame"
	p._flame.texture = FLAME_TEX
	p._flame.centered = false
	p._flame.position = Vector2(-10, 22) # QA-071b: (0, 18) * 1.20, x centred on the 20 px wide flame
	p._flame.scale = Vector2(20.0 / 442.0, 22.0 / 492.0)
	p._flame.z_index = 1
	p._flame.visible = false
	p.add_child(p._flame)

	p._muzzle = Sprite2D.new()
	p._muzzle.name = "Muzzle"
	p._muzzle.texture = MUZZLE_TEX[p.weapon]
	p._muzzle.visible = false
	p._muzzle.z_index = 4
	p._gun.add_child(p._muzzle)
	_update_gun_texture()

	# QA-071: the name label was already shown above every player
	# (this file, since v2) - it is now bigger and easier to read at
	# the new size: font 18 -> 22, 80 px wide -> 110, y -66 -> -88
	# (above the taller head + HP bar). _update_visuals refreshes
	# the text/colour live, so a name or colour set after _ready
	# (remote joins) still shows correctly.
	p._name_label = Label.new()
	p._name_label.text = p.player_name
	p._name_label.position = Vector2(-48, -79) # QA-071b: (-40, -66) * 1.20
	p._name_label.size = Vector2(96, 26) # QA-071b: (80, 22) * 1.20
	p._name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p._name_label.add_theme_font_size_override("font_size", 22)
	p._name_label.add_theme_color_override("font_color", p.player_color)
	p._name_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	p._name_label.add_theme_constant_override("outline_size", 5)
	p.add_child(p._name_label)

	p._hp_bg = ColorRect.new()
	p._hp_bg.color = Color(0, 0, 0, 0.6)
	p._hp_bg.position = Vector2(-26, -58)
	p._hp_bg.size = Vector2(53, 7)
	p.add_child(p._hp_bg)

	p._hp_fg = ColorRect.new()
	p._hp_fg.color = Color(0.3, 0.9, 0.3)
	p._hp_fg.position = Vector2(-26, -58)
	p._hp_fg.size = Vector2(53, 7)
	p.add_child(p._hp_fg)

	# QA-092: one shared hit-flash shader material for the body, the
	# gun and the helmet - one flash_amount drives all three, so the
	# whole player flashes red together (QA-086). Spawn-protection
	# blink still uses modulate, which composes with the shader.
	p._hit_flash_mat = ShaderMaterial.new()
	p._hit_flash_mat.shader = HIT_FLASH_SHADER
	p._hit_flash_mat.set_shader_parameter("flash_color", Color(1.0, 0.15, 0.15, 1.0))
	p._hit_flash_mat.set_shader_parameter("flash_amount", 0.0)
	p._sprite.material = p._hit_flash_mat
	p._gun.material = p._hit_flash_mat
	p._helmet_sprite.material = p._hit_flash_mat


func _make_sprite_frames() -> SpriteFrames:
	var sf := SpriteFrames.new()
	var anims := {
		# QA-071: run / jump / jetpack play a little faster (10 -> 12
		# fps) so the bigger, more visible character moves smoothly
		# instead of visibly stepping frame-to-frame. Speeds are
		# unchanged; only the animation rate moves.
		"idle": [7.0, true],
		"run": [12.0, true],
		"jump": [12.0, true],
		"fall": [8.0, true],
		"shoot": [12.0, true],
		"aim": [6.0, true],
		"jetpack": [12.0, true],
		"die": [7.0, false],
	}
	for key in anims.keys():
		var spec: Array = anims[key]
		var fps: float = spec[0]
		var loop: bool = spec[1]
		sf.add_animation(key)
		sf.set_animation_speed(key, fps)
		sf.set_animation_loop(key, loop)
		var cells: Array = _QA137_ANIM_CELLS[key]
		var count: int = 5 if key == "die" else 11
		for i in count:
			# die plays its 5 cells straight through; every other
			# animation ping-pongs the source frames to 11 game
			# frames, wrapping the index for groups with fewer
			# than 6 source frames (idle/shoot/aim have 2).
			var idx: int = i if key == "die" else _QA137_PINGPONG[i] % cells.size()
			var cell: Vector2i = cells[idx]
			var tex: Texture2D = load("res://assets/user_assets_v3/soldier_new_r%d_c%d.png" % [cell.x, cell.y])
			sf.add_frame(key, tex)
	return sf


# QA-127: the hand anchor in PLAYER units (frame units x PLAYER_SCALE),
# facing right. The gun grip sits here; the muzzle and bullet spawn
# use it too (see _muzzle_origin).
func _hand_anchor() -> Vector2:
	if p._current_anim == "jetpack":
		var f = clampi(p._sprite.frame, 0, HAND_JETPACK_FRAMES.size() - 1)
		return HAND_JETPACK_FRAMES[f] * p.PLAYER_SCALE
	if p._current_anim == "idle":
		var fi = clampi(p._sprite.frame, 0, HAND_IDLE_FRAMES.size() - 1)
		return HAND_IDLE_FRAMES[fi] * p.PLAYER_SCALE
	return HAND_ANCHOR_BY_ANIM.get(p._current_anim, Vector2(0, 8)) * p.PLAYER_SCALE


# QA-127: the hands in the player's local space (mirrored when
# facing left). Bullets and the sight line leave from here.
func _muzzle_origin() -> Vector2:
	var hand := _hand_anchor()
	return Vector2(hand.x * p.facing, hand.y)


func _update_helmet() -> void:
	if p._helmet_sprite == null:
		return
	if p.helmet <= 0 or not HELMET_TEX.has(p.helmet):
		p._helmet_sprite.texture = null
		return
	var tex: Texture2D = HELMET_TEX[p.helmet]
	p._helmet_sprite.texture = tex
	# Head is ~20px wide in the 64px frame; scale helmet to fit.
	var target_w := 26.0
	p._helmet_sprite.scale = Vector2(target_w / tex.get_width(), target_w / tex.get_width())
	p._helmet_sprite.position = Vector2(1, p._helmet_y) # QA-094: was a fixed -25


func _update_gun_texture() -> void:
	if p._gun == null:
		return
	var tex: Texture2D = WEAPON_TEX[p.weapon]
	p._gun.texture = tex
	p._gun_base_scale = p.GUN_LENGTH / tex.get_width()
	p._gun.scale = Vector2(p._gun_base_scale, p._gun_base_scale)
	# Muzzle flash sits at the barrel tip in the gun's local space.
	# QA-108: was tex.get_width() - the gun sprite is CENTRED on the
	# node and scaled so its full width is GUN_LENGTH, so the barrel
	# tip is at half the texture width (27.5 px ahead after scaling),
	# not the far edge (55 px). The flash used to float 27.5 px past
	# the barrel in mid-air.
	if p._muzzle != null:
		p._muzzle.position = Vector2(tex.get_width() * 0.5, 0)
		# QA-083: the flash picture follows the weapon class.
		p._muzzle.texture = MUZZLE_TEX[p.weapon]


func _build_collision() -> void:
	p._collision_shape = CollisionShape2D.new()
	var cap := CapsuleShape2D.new()
	cap.radius = p.CAPSULE_RADIUS # QA-071b: 17 -> 20 (1.20x)
	cap.height = p.CAPSULE_HEIGHT # QA-071b: 52 -> 62 (1.20x)
	p._collision_shape.shape = cap
	p.add_child(p._collision_shape)
	p.floor_snap_length = 4.0


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
	p.add_child(sp)
	return sp


func _update_anim() -> void:
	if not p.alive:
		return
	if p._jetpacking:
		_play_anim("jetpack")
		p._sprite.speed_scale = 1.0
		return
	if not p.is_on_floor():
		if p.velocity.y < 0.0:
			_play_anim("jump")
		else:
			_play_anim("fall")
		p._sprite.speed_scale = 1.0
		return
	if p._want_fire:
		_play_anim("shoot")
		p._sprite.speed_scale = 1.0
		return
	if p._aiming:
		_play_anim("aim")
		p._sprite.speed_scale = 1.0
		return
	if p._move_mag > 0.05:
		_play_anim("run")
		# Run cycle speed matches movement speed: slow walk, fast run.
		p._sprite.speed_scale = 0.55 + p._move_mag * 0.9
		return
	_play_anim("idle")
	p._sprite.speed_scale = 1.0


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
	if not p.alive:
		_play_anim("die")
		return
	if p._remote_jetpacking:
		_play_anim("jetpack")
		p._sprite.speed_scale = 1.0
		return
	if p._remote_airborne:
		if p.velocity.y < -50.0:
			_play_anim("jump")
		elif p.velocity.y > 50.0:
			_play_anim("fall")
		p._sprite.speed_scale = 1.0
		return
	if p._remote_firing and not p._remote_reloading:
		_play_anim("shoot")
		p._sprite.speed_scale = 1.0
		return
	if absf(p.velocity.x) > 25.0:
		_play_anim("run")
		p._sprite.speed_scale = 0.55 + clampf(absf(p.velocity.x) / p.SPEED, 0.0, 1.0) * 0.9
		return
	_play_anim("idle")
	p._sprite.speed_scale = 1.0


func _play_anim(anim_name: String) -> void:
	if p._current_anim == anim_name:
		# Death plays once and stays on the last frame.
		if anim_name == "die":
			return
		if p._sprite.is_playing():
			return
	p._current_anim = anim_name
	p._sprite.play(anim_name)
	# QA-094: the helmet rides at a fixed offset from the sprite,
	# but each animation draws the head at a different height in
	# the frame (jetpack frames sit ~17px low) - move the helmet
	# with the animation. _play_anim is the one choke point for
	# local + remote animation changes. Guarded: _ready calls
	# _play_anim("idle") before the helmet sprite exists.
	if HELMET_Y_BY_ANIM.has(anim_name):
		p._helmet_y = float(HELMET_Y_BY_ANIM[anim_name])
		if p._helmet_sprite != null:
			# QA-108: reset X as well as Y. The jetpack frames track
			# the helmet side-to-side (HELMET_JETPACK_FRAMES, x -11..+15)
			# and _update_visuals stops overriding it once jetpack ends;
			# only setting .y here left the last jetpack X stuck, so the
			# cap/helmet floated 11-15 px sideways off the head after
			# every landing until the next jetpack.
			p._helmet_sprite.position = Vector2(1, p._helmet_y)


func _update_visuals(delta: float) -> void:
	if p._sprite == null:
		return
	# QA-075: the muzzle flash and the switch dip are timers, not
	# scene-tree timers - they tick down here every render frame,
	# for the local player and for remote copies alike.
	p._muzzle_timer = maxf(0.0, p._muzzle_timer - delta)
	p._switch_dip_timer = maxf(0.0, p._switch_dip_timer - delta)
	if p._muzzle != null:
		p._muzzle.visible = p.alive and p._muzzle_timer > 0.0
	# QA-071b: keep the 1.20x sprite scale; only flip x for facing.
	p._sprite.scale = Vector2(p.PLAYER_SCALE * float(p.facing), p.PLAYER_SCALE)
	# QA-094: while jetpacking, track the head per frame - the
	# flying pose sways side-to-side (see HELMET_JETPACK_FRAMES).
	# Other animations use the per-animation height set in
	# _play_anim. Runs for local and remote copies alike.
	if p._current_anim == "jetpack" and p._helmet_sprite != null:
		var f = clampi(p._sprite.frame, 0, HELMET_JETPACK_FRAMES.size() - 1)
		p._helmet_sprite.position = HELMET_JETPACK_FRAMES[f]
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
	var flip_y = -1.0 if cos(p.aim_angle) < 0.0 else 1.0
	p._gun.scale = Vector2(p._gun_base_scale, p._gun_base_scale * flip_y)
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
	var kick = Vector2(cos(p.aim_angle), sin(p.aim_angle)) * minf(p._gun_kick * 8.4, 6.0)
	var dip := 0.0
	if p.reloading:
		dip = 5.0
	if p._switch_dip_timer > 0.0:
		dip = maxf(dip, 6.0 * (p._switch_dip_timer / 0.15))
	var grip: Vector2 = WEAPON_GRIP.get(p.weapon, Vector2(0.34, 1.5))
	var grip_local = Vector2((grip.x - 0.5) * p.GUN_LENGTH, grip.y * flip_y)
	p._gun.position = _muzzle_origin() - grip_local.rotated(p.aim_angle) - kick + Vector2(0, dip)
	p._gun.rotation = p.aim_angle + dip * 0.008
	# Jetpack flame (GAP-06, spec §5): tied to the REAL thrust state,
	# never to the animation name. Off = hidden, thrusting = visible
	# with length by thrust, low fuel = blink, empty/descending = gone.
	# QA-141: the length also follows the MMC thrust factor
	# (_jet_thrust_factor = 0.5 + 0.5 x up-input), so the flame
	# grows with how hard the stick is pushed up.
	if p._flame != null:
		var thrusting = p._jetpacking and p.fuel > 0.0
		p._flame.visible = thrusting and p.alive
		if thrusting:
			var frac = (0.6 + 0.6 * clampf(absf(p.velocity.y) / p.MAX_JET_RISE, 0.0, 1.0)) * (0.7 + 0.3 * p._jet_thrust_factor)
			# QA-137: the flame is the user's jetpack art now. The
			# boost flame is a separate, bigger texture (blue core)
			# shown while the Jetpack Boost power-up runs - it
			# replaces the old 1.5x stretch of the single flame.
			# Normal: 442x492 drawn 20x22 px; boost: 616x926 drawn
			# 30x33 px. The flicker (sin) and the thrust-length
			# (frac) still apply; the x centres the flame on the
			# jetpack (half the texture width x scale).
			var boosting = p.jetpack_boost_timer > 0.0
			p._flame.texture = FLAME_TEX_BOOST if boosting else FLAME_TEX
			var fw := 616.0 if boosting else 442.0
			var fh := 926.0 if boosting else 492.0
			var dw := 30.0 if boosting else 20.0
			var dh := 33.0 if boosting else 22.0
			p._flame.scale = Vector2((dw / fw) * (1.0 + 0.15 * sin(Time.get_ticks_msec() / 40.0)), (dh / fh) * frac)
			p._flame.position = Vector2(-0.5 * fw * p._flame.scale.x, 22.0)
			if p.fuel < PhysicsConfig.FUEL_LOW_WARN:
				p._flame.modulate = Color(1.0, 1.0, 1.0, 0.5 + 0.5 * sin(Time.get_ticks_msec() / 60.0))
			else:
				p._flame.modulate = Color.WHITE
	p._gun.visible = p.alive
	# Camera shake: trauma decays in _physics_process; the offset is
	# trauma squared so small shakes stay subtle and big ones punch.
	if p._camera != null:
		var s = p._shake_trauma * p._shake_trauma * 16.0
		p._camera.offset = Vector2(randf_range(-s, s), randf_range(-s, s)) if s > 0.05 else Vector2.ZERO
	p._helmet_sprite.visible = p.alive
	p._ring.visible = p.alive
	# QA-112: the shield ring shows while the shield boost is up
	# (local player and remote copies alike - the timer is synced).
	if p._shield_ring != null:
		p._shield_ring.visible = p.alive and p.shield_timer > 0.0
	# QA-119: invisibility is 90% - the player stays ~10% visible
	# (INVISIBILITY_ALPHA). The LOCAL player always sees themself
	# fully; teammates see a faint 40% outline; enemies see 10%.
	# modulate fades the whole body - sprite, gun, helmet, ring,
	# name label and HP bar - so nothing gives the position away.
	if p.alive and p.invisibility_timer > 0.0:
		if p.is_local_player():
			p.modulate = Color(1, 1, 1, 1)
		elif p._is_same_team_as_local():
			p.modulate = Color(1, 1, 1, 0.4)
		else:
			p.modulate = Color(1, 1, 1, INVISIBILITY_ALPHA)
	else:
		p.modulate = Color.WHITE
	# QA-119: active power-up effect layers (assets/powerups_effects/).
	# Timed boosts show while their timer runs; instant kinds flash
	# for 0.8 s after activation. The wind whirlpool is a flat disc,
	# so it spins fast and stays faded (0.55 alpha).
	if p._fx_shield != null:
		p._fx_shield.visible = p.alive and p.shield_timer > 0.0
		var pulse := 1.0 + 0.06 * sin(Time.get_ticks_msec() / 180.0)
		p._fx_shield.scale = Vector2(0.11 * pulse, 0.11 * pulse) # QA-137: 1440 px dome art, was 0.30 for 512 px
	if p._fx_speed != null:
		p._fx_speed.visible = p.alive and p.speed_timer > 0.0
	if p._fx_health != null:
		p._fx_health.visible = p.alive and p._fx_flash_kind == 7 and p._fx_flash_timer > 0.0
		p._fx_health.modulate = Color(1, 1, 1, clampf(p._fx_flash_timer / 0.8, 0.0, 1.0))
	if p._fx_wind != null:
		p._fx_wind.visible = p.alive and p._fx_flash_kind == 11 and p._fx_flash_timer > 0.0
		p._fx_wind.rotation = Time.get_ticks_msec() / 1000.0 * 6.0
		p._fx_wind.modulate = Color(1, 1, 1, 0.55 * clampf(p._fx_flash_timer / 0.8, 0.0, 1.0))
	if p._fx_thunder != null:
		p._fx_thunder.visible = p.alive and p._fx_flash_kind == 12 and p._fx_flash_timer > 0.0
		p._fx_thunder.modulate = Color(1, 1, 1, clampf(p._fx_flash_timer / 0.8, 0.0, 1.0))
	if p._fx_invis != null:
		p._fx_invis.visible = p.alive and p.invisibility_timer > 0.0
		p._fx_invis.modulate = Color(1, 1, 1, 0.6 + 0.4 * sin(Time.get_ticks_msec() / 300.0))
	p._name_label.visible = p.alive
	# QA-071: keep the label in sync if the name/colour was set after
	# _ready (remote joins set fields before add_child, so this is
	# normally a no-op - it only guards the late-assignment case).
	if p._name_label.text != p.player_name:
		p._name_label.text = p.player_name
	if p._name_label.get_theme_color("font_color") != p.player_color:
		p._name_label.add_theme_color_override("font_color", p.player_color)
	p._hp_bg.visible = p.alive
	p._hp_fg.visible = p.alive
	if p._hit_flash_timer > 0.0:
		p._hit_flash_timer -= delta
		# QA-086 + QA-092 (v3.7): the hit flash is a shader-driven
		# red flash over the WHOLE player - body, gun and helmet
		# share one flash material, amount fading 1 -> 0 over the
		# 0.09 s timer (was a modulate tint on the body sprite only,
		# then on all three). Purely visual; the timer and the
		# damage path are unchanged.
		if p._hit_flash_mat != null:
			p._hit_flash_mat.set_shader_parameter("flash_amount", clampf(p._hit_flash_timer / 0.09, 0.0, 1.0))
		if p._hit_flash_timer <= 0.0 and p._hit_flash_mat != null:
			p._hit_flash_mat.set_shader_parameter("flash_amount", 0.0)
	elif p._spawn_protect_timer > 0.0:
		# Spawn protection: blink so other players can see it.
		p._sprite.modulate = Color(1, 1, 1, 0.55 + 0.35 * sin(Time.get_ticks_msec() / 90.0))
		p._gun.modulate = p._sprite.modulate
		p._helmet_sprite.modulate = p._sprite.modulate
	else:
		p._sprite.modulate = Color.WHITE
		p._gun.modulate = Color.WHITE
		p._helmet_sprite.modulate = Color.WHITE
	p._hp_fg.size.x = 53.0 * clampf(float(p.health) / 100.0, 0.0, 1.0)
	p._hp_fg.color = Color(0.3, 0.9, 0.3) if p.health > 30 else Color(0.9, 0.25, 0.2)
	# Team colour ring tint.
	if p.team == 0:
		p._ring.color = Color(0.95, 0.25, 0.2, 0.55)
	elif p.team == 1:
		p._ring.color = Color(0.2, 0.5, 0.95, 0.55)
	else:
		p._ring.color = Color(p.player_color.r, p.player_color.g, p.player_color.b, 0.55)


func _play_sound(sound_name: String) -> void:
	if p._audio != null:
		p._audio.play(sound_name)


func _start_jetpack_sound() -> void:
	if p._audio != null:
		p._audio.start_jetpack()


func _stop_jetpack_sound() -> void:
	if p._audio != null:
		p._audio.stop_jetpack()


func _update_camera(delta: float) -> void:
	# Camera dead zone + look-ahead (GAP-52/53, spec §19). The camera
	# is a child of the player, so the dead zone is implemented with an
	# anchor: it only moves when the player leaves a 120x80 px rect
	# around it, and the view leads the movement direction by up to 80 px.
	var game = p.get_tree().get_first_node_in_group("game")
	if game == null:
		return
	if not p._cam_anchor_init:
		p._cam_anchor = p.global_position
		p._cam_anchor_init = true
	var off = p.global_position - p._cam_anchor
	var dz: Vector2 = PhysicsConfig.CAMERA_DEAD_ZONE
	if absf(off.x) > dz.x:
		p._cam_anchor.x += off.x - signf(off.x) * dz.x
	if absf(off.y) > dz.y:
		p._cam_anchor.y += off.y - signf(off.y) * dz.y
	var look_target := 0.0
	if absf(p.velocity.x) > 100.0:
		look_target = signf(p.velocity.x) * PhysicsConfig.CAMERA_LOOKAHEAD
	elif absf(p.velocity.x) > 10.0:
		look_target = signf(p.velocity.x) * PhysicsConfig.CAMERA_LOOKAHEAD * 0.5
	p._cam_look = move_toward(p._cam_look, look_target, delta * 240.0)
	var target = p._cam_anchor + Vector2(p._cam_look, 0)
	# QA-105 (v3.8): while scoped, the view shifts toward the aim
	# direction so the player sees further that way.
	if p.scoped and p._aiming:
		target += p._aim_dir * 150.0
	# Clamp the view inside the map (hard limits, spec §19).
	# QA-105: the clamp uses the EFFECTIVE view size (viewport /
	# zoom) so a scoped (zoomed-in) camera still stays inside.
	var vp = p.get_viewport().get_visible_rect().size / p._camera.zoom
	var ms: Vector2 = game.map_size
	var hx = minf(vp.x * 0.5, ms.x * 0.5)
	var hy = minf(vp.y * 0.5, ms.y * 0.5)
	target.x = clampf(target.x, hx, maxf(hx, ms.x - hx))
	target.y = clampf(target.y, hy, maxf(hy, ms.y - hy))
	p._camera.position = target - p.global_position
	# QA-105: scope zoom - sniper 2.0x, rifle 1.5x, everything else
	# 1.0x. Eases at 3x/s so the zoom feels smooth, not a snap.
	var zoom_target := 1.0
	if p.scoped:
		zoom_target = p.SCOPE_ZOOM_SNIPER if p.weapon == 3 else (p.SCOPE_ZOOM_RIFLE if p.weapon == 0 else 1.0)
	var zoom_now = move_toward(p._camera.zoom.x, zoom_target, delta * 3.0)
	p._camera.zoom = Vector2(zoom_now, zoom_now)


func _update_sight_line() -> void:
	# QA-105 (v3.8): the sniper sight line - local player only,
	# sniper equipped, while aiming (right stick deflected). One
	# raycast along the true bullet path (mask 1 = world, same as
	# game.gd has_line_of_sight): green while clear to full sniper
	# range, red where a wall blocks it, ending at the wall.
	if p._sight_line == null:
		return
	if not p.alive or p.weapon != 3 or not p._aiming:
		p._sight_line.visible = false
		return
	var dir = Vector2(cos(p.aim_angle), sin(p.aim_angle))
	var muzzle = p.global_position + _muzzle_origin() + dir * (p.GUN_LENGTH + 6.0)
	var end = muzzle + dir * p.SIGHT_LINE_RANGE
	var space = p.get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(muzzle, end, 1)
	var hit: Dictionary = space.intersect_ray(query)
	var blocked := false
	if not hit.is_empty():
		end = hit["position"]
		blocked = true
	p._sight_line.points = PackedVector2Array([muzzle - p.global_position, end - p.global_position])
	p._sight_line.default_color = Color(1.0, 0.3, 0.25) if blocked else Color(0.35, 1.0, 0.45)
	p._sight_line.visible = true

