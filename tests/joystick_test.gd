class_name JoystickTest
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)

var _joystick_test: bool = false
var _joy_steps: Array = []
var _joy_step: int = 0
var _joy_in_step: bool = false
var _joy_timer: float = 0.0
var _joy_passed: int = 0
var _joy_failed: int = 0
var _joy_done: bool = false
var _joy_shots_before: int = 0
var _joy_fuel_before: float = 0.0
var _joy_pos_before: Vector2 = Vector2.ZERO
var _joy_vel_before: Vector2 = Vector2.ZERO
var _joy_mouse_seen: bool = false # QA-054: emulated mouse button was actually down during the hold
var _joy_mouse_pos_seen: Vector2 = Vector2.ZERO # QA-054: emulated mouse position during the hold
var _joy_aim_before: float = 0.0 # QA-054: aim angle before the push-right hold


func _init(owner) -> void:
	g = owner


func _update_joytest(delta: float) -> void:
	if _joy_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		_joy_timer += delta
		if _joy_timer > 5.0:
			_joy_done = true
			print("JOYTEST DONE: 0/0 passed — no local player spawned")
			g.get_tree().quit()
		return
	if _joy_steps.is_empty():
		_joytest_build_steps()
		_joy_step = 0
		_joy_in_step = false
		_joy_timer = 0.0
	if _joy_step >= _joy_steps.size():
		_joy_done = true
		print("JOYTEST DONE: %d/%d passed" % [_joy_passed, _joy_passed + _joy_failed])
		g.get_tree().quit()
		return
	var step: Dictionary = _joy_steps[_joy_step]
	if not _joy_in_step:
		(step["setup"] as Callable).call()
		_joy_in_step = true
		_joy_timer = float(step["wait"])
	_joy_timer -= delta
	if _joy_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_joy_passed += 1
		else:
			_joy_failed += 1
		print("JOYTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_joy_step += 1
		_joy_in_step = false
		_joy_timer = 0.0


func _joytest_build_steps() -> void:
	_joy_steps = [
		{"name": "PRESS-LEFT", "wait": 0.6, "setup": _jt_s_press_left, "check": _jt_c_press_left},
		{"name": "PRESS-RIGHT", "wait": 0.6, "setup": _jt_s_press_right, "check": _jt_c_press_right},
		{"name": "PRESS-UP-JUMP", "wait": 0.6, "setup": _jt_s_press_up, "check": _jt_c_press_up},
		# QA-117 (v3.9 fix round): wait 0.6 s, not 0.4 s. The jetpack
		# only thrusts once the jump's velocity decays above -190
		# (from -220, ~0.1 s of physics), so at 0.4 s of wall time
		# the fuel has barely drained — and under xvfb load the
		# physics lags wall time, so the 0.4 s check caught fuel
		# exactly at max (jetpack not yet engaged) in 2 of 3 map-0 runs.
		# 0.6 s gives the thrust time to engage and drain fuel even
		# with the lag. The check is unchanged (fuel < FUEL_MAX, risen
		# > 20 px, not on floor).
		# QA-099 (v3.7): wait 1.5 s, not 0.5 s. This step follows
		# PRESS-UP-JUMP, and the jump's air time is ~1.5 s (81 px apex
		# + brief jetpack thrust) — at 0.5 s the player is still
		# airborne, so the check measured air-drag decay (vel.x 91),
		# not the ground stop. It only passed before because the player
		# was pinned against Ironfall's floor crate (vel.x 0 from the
		# start — a vacuous pass). 1.5 s lands the player (~1.5 s) and
		# stops it before the check.
		{"name": "RELEASE-STOPS", "wait": 1.5, "setup": _jt_s_release_move, "check": _jt_c_release_stops},
		{"name": "MOVE-RELEASE-NO-LEFT", "wait": 0.8, "setup": _jt_s_move_right_mouse, "check": _jt_c_move_release_no_left},
		{"name": "AIM-RELEASE-NO-LEFT", "wait": 0.8, "setup": _jt_s_aim_right_mouse, "check": _jt_c_aim_release_no_left},
		{"name": "FUEL-STABLE", "wait": 0.5, "setup": _jt_s_noop, "check": _jt_c_fuel_stable},
		{"name": "PRESS-DOWN-FAST-FALL", "wait": 0.4, "setup": _jt_s_press_down, "check": _jt_c_press_down},
		{"name": "DIAG-UP-RIGHT", "wait": 0.5, "setup": _jt_s_diag_up_right, "check": _jt_c_diag_up_right},
		{"name": "DIAG-SPEED", "wait": 0.3, "setup": _jt_s_noop, "check": _jt_c_diag_speed},
		{"name": "KNOB-CLAMP", "wait": 0.3, "setup": _jt_s_knob_clamp, "check": _jt_c_knob_clamp},
		{"name": "MULTI-TOUCH", "wait": 0.6, "setup": _jt_s_multi_touch, "check": _jt_c_multi_touch},
		{"name": "RELEASE-MOVE-ONLY", "wait": 0.4, "setup": _jt_s_release_move_only, "check": _jt_c_release_move_only},
		{"name": "RELEASE-FIRE-STOPS-FIRE", "wait": 0.6, "setup": _jt_s_release_fire, "check": _jt_c_release_fire_stops_fire},
		{"name": "FOCUS-OUT-SETUP", "wait": 0.5, "setup": _jt_s_press_aim_fire, "check": _jt_c_firing_on},
		{"name": "FOCUS-OUT-RESET", "wait": 0.4, "setup": _jt_s_focus_out, "check": _jt_c_focus_out_reset},
		{"name": "FIRE-AFTER-DEATH", "wait": 0.6, "setup": _jt_s_kill_and_aim_fire, "check": _jt_c_fire_after_death},
		{"name": "WAIT-RESPAWN", "wait": 3.5, "setup": _jt_s_noop, "check": _jt_c_respawned},
		{"name": "FIRE-WHILE-PAUSED-SETUP", "wait": 0.4, "setup": _jt_s_press_aim_fire, "check": _jt_c_firing_on},
		{"name": "FIRE-WHILE-PAUSED", "wait": 0.6, "setup": _jt_s_pause, "check": _jt_c_fire_while_paused},
		{"name": "FIRE-AFTER-MATCH-END", "wait": 0.6, "setup": _jt_s_match_end_aim_fire, "check": _jt_c_fire_after_match_end},
		{"name": "STICK-UP-NO-REJUMP", "wait": 4.0, "setup": _jt_s_hold_up_long, "check": _jt_c_no_rejump},
		{"name": "RESOLUTION-1920", "wait": 0.5, "setup": _jt_s_resize_1920, "check": _jt_c_resolution_1920},
		{"name": "RESOLUTION-2400", "wait": 0.5, "setup": _jt_s_resize_2400, "check": _jt_c_resolution_2400},
		{"name": "MOVE-RELEASE-NO-LEFT-2400", "wait": 0.5, "setup": _jt_s_noop, "check": _jt_c_move_release_no_left_2400},
		{"name": "AIM-RELEASE-NO-LEFT-2400", "wait": 0.8, "setup": _jt_s_aim_right_mouse_2400, "check": _jt_c_aim_release_no_left_2400},
		# QA-117 (v3.9 fix round): the Skyfall height bar's 170 px-wide
		# rect overlapped the move stick and swallowed real touches
		# on it (the sim calls _on_touch_press directly, so the old
		# steps never saw it). These two steps reproduce it through
		# the real GUI/input pipeline.
		{"name": "GUI-STICK-CLEAR", "wait": 0.3, "setup": _jt_s_noop, "check": _jt_c_gui_stick_clear},
		{"name": "GUI-PRESS-LEFT", "wait": 0.6, "setup": _jt_s_gui_press_left, "check": _jt_c_gui_press_left},
		# QA-117: left push through the real GUI pipeline on a
		# middle level (L4 bridge) and the summit, not just the base.
		{"name": "GUI-PRESS-LEFT-MID", "wait": 0.6, "setup": _jt_s_gui_press_left_mid, "check": _jt_c_gui_press_left},
		{"name": "GUI-PRESS-LEFT-TOP", "wait": 0.6, "setup": _jt_s_gui_press_left_top, "check": _jt_c_gui_press_left},
	]


func _jt_move_center() -> Vector2:
	return g.move_stick.get_global_rect().get_center()


func _jt_aim_center() -> Vector2:
	return g.aim_stick.get_global_rect().get_center()


func _jt_press_move(offset: Vector2) -> void:
	g._on_touch_press(900, _jt_move_center() + offset)


func _jt_drag_move(offset: Vector2) -> void:
	g._on_touch_drag(900, _jt_move_center() + offset)


func _jt_release_move() -> void:
	g._on_touch_release(900)


func _jt_press_aim(offset: Vector2) -> void:
	g._on_touch_press(901, _jt_aim_center() + offset)


func _jt_drag_aim(offset: Vector2) -> void:
	g._on_touch_drag(901, _jt_aim_center() + offset)


func _jt_release_aim() -> void:
	g._on_touch_release(901)


func _jt_press_fire() -> void:
	if not g.aim_stick.is_active():
		g._jt_fire_owns_aim = true
		g._on_touch_press(902, _jt_aim_center() + Vector2(60, 0))


func _jt_release_fire() -> void:
	if g._jt_fire_owns_aim:
		g._on_touch_release(902)
		g._jt_fire_owns_aim = false


func _jt_press_aim_fire() -> void:
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_lp():
	return g._get_local_player()


func _jt_s_noop() -> void:
	pass


func _jt_s_press_left() -> void:
	# Phase 5: spawn#0 has a solid cover crate ~90 px to its LEFT
	# (cover within 150 px of every spawn), so pressing left straight
	# from the spawn pins the player against it after ~58 px. The
	# stick itself is fine — give it a clear run first (see
	# _jt_teleport_clear_left).
	_jt_teleport_clear_left()
	_jt_press_move(Vector2(-50, 0))


# Phase 5 — joystick-test helper: stand 200 px right of spawn#0.
# The run-up rule keeps 360 px clear right of spawn#0 on every map,
# so from there the left run is ~258 px (cover face to the left is
# ~90 px left of the spawn) — enough for the 0.6 s press checks.
func _jt_teleport_clear_left() -> void:
	var lp = _jt_lp()
	if lp == null:
		return
	var s0: Vector2 = (g.MAPS[g.map_id]["spawns"] as Array)[0]
	var p := Vector2(s0.x + 200.0, s0.y)
	lp.position = p
	lp.sync_position = p
	lp.velocity = Vector2.ZERO


func _jt_c_press_left() -> Array:
	var lp = _jt_lp()
	var v = g.touch_move_vec
	var ok: bool = v.x < -0.5 and absf(v.y) < 0.15 and lp.velocity.x < -50.0 and lp.facing == -1
	return [ok, "vec=%s vel.x=%d facing=%d anim=%s" % [v, round(lp.velocity.x), lp.facing, lp._current_anim]]


func _jt_s_press_right() -> void:
	_jt_drag_move(Vector2(50, 0))


func _jt_c_press_right() -> Array:
	var lp = _jt_lp()
	var v = g.touch_move_vec
	var ok: bool = v.x > 0.5 and absf(v.y) < 0.15 and lp.velocity.x > 50.0 and lp.facing == 1
	return [ok, "vec=%s vel.x=%d facing=%d anim=%s" % [v, round(lp.velocity.x), lp.facing, lp._current_anim]]


func _jt_s_press_up() -> void:
	_joy_pos_before = _jt_lp().position
	_jt_drag_move(Vector2(0, -55))


func _jt_c_press_up() -> Array:
	var lp = _jt_lp()
	var v = g.touch_move_vec
	# Up past the threshold: jumped off the floor and is thrusting
	# (fuel drains only while the jetpack is actually thrusting).
	# QA-099 (v3.7): fuel < FUEL_MAX, not < MAX-2 — any drain proves
	# the thrust ran; < MAX-2 needs >= 2 units in 0.4 s, which
	# load-starved physics frames don't deliver (one suite run read
	# fuel 1 under max with jetpacking=true and 128 px of rise).
	var ok: bool = v.y < -0.5 and not lp.is_on_floor() and lp.position.y < _joy_pos_before.y - 20.0 and lp.fuel < PhysicsConfig.FUEL_MAX
	return [ok, "vec=%s on_floor=%s y=%d (was %d) fuel=%d jetpacking=%s" % [v, lp.is_on_floor(), round(lp.position.y), round(_joy_pos_before.y), round(lp.fuel), lp._jetpacking]]


func _jt_s_release_move() -> void:
	_jt_release_move()


func _jt_c_release_stops() -> Array:
	var lp = _jt_lp()
	_joy_fuel_before = lp.fuel
	var ok: bool = g.touch_move_vec == Vector2.ZERO and g.move_stick.get_knob_offset().length() < 2.0 and not lp._jetpacking and absf(lp.velocity.x) < 60.0
	return [ok, "vec=%s knob=%.1f jetpacking=%s vel.x=%d fuel=%d" % [g.touch_move_vec, g.move_stick.get_knob_offset().length(), lp._jetpacking, round(lp.velocity.x), round(lp.fuel)]]


# --- QA-054 regression: push RIGHT, release, player must NOT turn left.
# On a real phone Godot emulates a mouse from every touch, so a MOVE
# stick hold also read as a held left mouse button at the finger's
# position — and the mouse-aim fallback in player.gd aimed the gun at
# that left-half point (LEFT) while the player ran RIGHT. Facing
# follows the aim, so the player faced left for the whole move and
# stayed facing left after release. These steps reproduce the phone
# exactly: a real touch hold PLUS an injected emulated mouse press at
# the same point (Input.parse_input_event, the OS path), released
# together 0.3 s later; the check runs ~0.5 s after release (30
# frames) and asserts no leftward velocity and no facing flip. The
# check REQUIRES the mouse press to have been seen during the hold
# (_joy_mouse_seen) — without it the test would pass vacuously if
# the injection ever stopped working.
func _jt_inject_mouse_press(canvas_pos: Vector2) -> void:
	var vp = g._to_viewport_pos(canvas_pos)
	# warp_mouse sets the viewport's mouse POSITION deterministically;
	# parse_input_event alone sets the button state but leaves
	# get_mouse_position() at its default (screen centre) in this
	# headless run, so the position assertion would read the centre.
	g.get_viewport().warp_mouse(vp)
	var btn := InputEventMouseButton.new()
	btn.button_index = MOUSE_BUTTON_LEFT
	btn.pressed = true
	btn.position = vp
	Input.parse_input_event(btn)


func _jt_inject_mouse_release() -> void:
	var btn := InputEventMouseButton.new()
	btn.button_index = MOUSE_BUTTON_LEFT
	btn.pressed = false
	btn.position = g.get_viewport().get_mouse_position()
	Input.parse_input_event(btn)


func _jt_release_move_mouse() -> void:
	# Record the emulated-mouse state BEFORE releasing it: the
	# check needs proof the mouse press was really down mid-hold.
	_joy_mouse_seen = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_joy_mouse_pos_seen = g.get_viewport().get_mouse_position()
	_jt_release_move()
	_jt_inject_mouse_release()


func _jt_release_aim_mouse() -> void:
	_joy_mouse_seen = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	_joy_mouse_pos_seen = g.get_viewport().get_mouse_position()
	_jt_release_aim()
	_jt_inject_mouse_release()


func _jt_s_move_right_mouse() -> void:
	var lp = _jt_lp()
	lp.position = Vector2(2100, 1318) # QA-071b: was 1350 — embedded 29 px into the floor with the 62-tall capsule; the solver could push the player DOWN through the 48 px slab (DIAG-UP-RIGHT vel.y=0, RESOLUTION-2400 vel.x=0)
	lp.velocity = Vector2.ZERO
	_joy_aim_before = lp.aim_angle
	_joy_mouse_seen = false
	_jt_press_move(Vector2(60, 0))
	_jt_inject_mouse_press(_jt_move_center() + Vector2(60, 0))
	g.get_tree().create_timer(0.3).timeout.connect(_jt_release_move_mouse)


func _jt_c_move_release_no_left() -> Array:
	var lp = _jt_lp()
	var centre_x = g.get_viewport().get_visible_rect().size.x * 0.5
	var ok: bool = _joy_mouse_seen and _joy_mouse_pos_seen.x < centre_x \
		and lp.facing == 1 and lp.velocity.x >= -1.0 \
		and g.touch_move_vec == Vector2.ZERO and g.move_stick.get_knob_offset().length() < 2.0 \
		and cos(lp.aim_angle) > 0.5
	return [ok, "mouse_seen=%s mouse_pos=%s (want left of centre %.0f) facing=%d vel.x=%d vec=%s knob=%.1f aim=%.2f (want facing 1, no leftward vel, vec 0, aim right)" % [_joy_mouse_seen, _joy_mouse_pos_seen, centre_x, lp.facing, round(lp.velocity.x), g.touch_move_vec, g.move_stick.get_knob_offset().length(), lp.aim_angle]]


func _jt_s_aim_right_mouse() -> void:
	var lp = _jt_lp()
	lp.position = Vector2(2100, 1318) # QA-071b: was 1350 — embedded 29 px into the floor with the 62-tall capsule; the solver could push the player DOWN through the 48 px slab (DIAG-UP-RIGHT vel.y=0, RESOLUTION-2400 vel.x=0)
	lp.velocity = Vector2.ZERO
	_joy_aim_before = lp.aim_angle
	_joy_mouse_seen = false
	_jt_press_aim(Vector2(60, 0))
	_jt_inject_mouse_press(_jt_aim_center() + Vector2(60, 0))
	g.get_tree().create_timer(0.3).timeout.connect(_jt_release_aim_mouse)


func _jt_c_aim_release_no_left() -> Array:
	var lp = _jt_lp()
	var centre_x = g.get_viewport().get_visible_rect().size.x * 0.5
	# QA-141: the vel.x bound is -120, not -5. The aim hold fires
	# the rifle right, and each shot kicks the player left 30 px/s
	# (recoil) — the old drag 8.0 erased that kick inside the
	# window, but reference damping is 0.6/s, so ~-40..-70 px/s of recoil
	# is still visible at the check. That is legitimate recoil, not
	# the QA-054 turn-left bug: facing == 1, aim ~= 0 (right) and
	# not firing still prove the released touch never aimed left.
	# A genuine leftward run (-250) still fails the bound.
	var ok: bool = _joy_mouse_seen and _joy_mouse_pos_seen.x > centre_x \
		and lp.facing == 1 and lp.velocity.x >= -120.0 \
		and not g.touch_firing and g.touch_aim == Vector2.ZERO \
		and cos(lp.aim_angle) > 0.5
	return [ok, "mouse_seen=%s mouse_pos=%s (want right of centre %.0f) facing=%d vel.x=%d firing=%s aim_vec=%s aim=%.2f (want facing 1, not firing, aim right)" % [_joy_mouse_seen, _joy_mouse_pos_seen, centre_x, lp.facing, round(lp.velocity.x), g.touch_firing, g.touch_aim, lp.aim_angle]]


func _jt_s_resize_2400() -> void:
	# Clear floor at (1600, 1318): the old (2100, 1350) spot's "clear
	# run right" is blocked 13 px on by the barrels at 2150 (QA-072
	# decor, solid 2133..2166) — the player runs into them and vel.x
	# reads 0. From 1600 the next solid is the barrels at 1920,
	# 283 px away, so the player is still running at the 0.5 s check.
	var lp = _jt_lp()
	lp.position = Vector2(1600, 1318)
	lp.velocity = Vector2.ZERO
	g.get_window().size = Vector2(2400, 1080)
	_joy_mouse_seen = false
	_jt_press_move(Vector2(60, 0))
	_jt_inject_mouse_press(_jt_move_center() + Vector2(60, 0))


func _jt_c_resolution_2400() -> Array:
	var lp = _jt_lp()
	var vp_size = g.get_viewport().get_visible_rect().size
	# Same stick math at phone aspect: rightward vector, moving right.
	# The resize reports the logical canvas size, which expands only
	# in aspect (1600x720 is the 2400x1080 aspect 2.22) — assert the
	# aspect, not raw window pixels. Release here (touch + emulated
	# mouse together); the next step observes the 30 frames after
	# release at this resolution.
	var ok: bool = absf(vp_size.x / vp_size.y - 2400.0 / 1080.0) < 0.05 and g.touch_move_vec.x > 0.5 and lp.velocity.x > 50.0
	_jt_release_move_mouse()
	return [ok, "viewport=%s vec=%s vel.x=%d" % [vp_size, g.touch_move_vec, round(lp.velocity.x)]]


func _jt_c_move_release_no_left_2400() -> Array:
	var lp = _jt_lp()
	var centre_x = g.get_viewport().get_visible_rect().size.x * 0.5
	var ok: bool = _joy_mouse_seen and _joy_mouse_pos_seen.x < centre_x \
		and lp.facing == 1 and lp.velocity.x >= -1.0 \
		and g.touch_move_vec == Vector2.ZERO and g.move_stick.get_knob_offset().length() < 2.0 \
		and cos(lp.aim_angle) > 0.5
	g.get_window().size = Vector2(1280, 720)
	return [ok, "mouse_seen=%s mouse_pos=%s (want left of centre %.0f) facing=%d vel.x=%d vec=%s knob=%.1f aim=%.2f at 2400x1080 (want facing 1, no leftward vel, vec 0, aim right)" % [_joy_mouse_seen, _joy_mouse_pos_seen, centre_x, lp.facing, round(lp.velocity.x), g.touch_move_vec, g.move_stick.get_knob_offset().length(), lp.aim_angle]]


# QA-054 (double-check): the 1280 AIM no-left check exists, but there
# was NO AIM no-left check at the tall resolution — only the MOVE one.
# Same sequence as _jt_s_aim_right_mouse, re-run at 2400x1080.
func _jt_s_aim_right_mouse_2400() -> void:
	var lp = _jt_lp()
	lp.position = Vector2(2100, 1318) # QA-071b: was 1350 — embedded 29 px into the floor with the 62-tall capsule; the solver could push the player DOWN through the 48 px slab (DIAG-UP-RIGHT vel.y=0, RESOLUTION-2400 vel.x=0)
	lp.velocity = Vector2.ZERO
	g.get_window().size = Vector2(2400, 1080)
	_joy_aim_before = lp.aim_angle
	_joy_mouse_seen = false
	_jt_press_aim(Vector2(60, 0))
	_jt_inject_mouse_press(_jt_aim_center() + Vector2(60, 0))
	g.get_tree().create_timer(0.3).timeout.connect(_jt_release_aim_mouse)


func _jt_c_aim_release_no_left_2400() -> Array:
	var lp = _jt_lp()
	var centre_x = g.get_viewport().get_visible_rect().size.x * 0.5
	# QA-141: vel.x bound -120, not -5 — rifle recoil under reference
	# damping 0.6/s (see _jt_c_aim_release_no_left).
	var ok: bool = _joy_mouse_seen and _joy_mouse_pos_seen.x > centre_x \
		and lp.facing == 1 and lp.velocity.x >= -120.0 \
		and not g.touch_firing and g.touch_aim == Vector2.ZERO \
		and cos(lp.aim_angle) > 0.5
	g.get_window().size = Vector2(1280, 720)
	return [ok, "mouse_seen=%s mouse_pos=%s (want right of centre %.0f) facing=%d vel.x=%d firing=%s aim_vec=%s aim=%.2f at 2400x1080 (want facing 1, not firing, aim right)" % [_joy_mouse_seen, _joy_mouse_pos_seen, centre_x, lp.facing, round(lp.velocity.x), g.touch_firing, g.touch_aim, lp.aim_angle]]


func _jt_gui_blockers() -> Array:
	# Every visible STOP control whose rect covers a point on the
	# move stick where a real thumb press can land (centre, and
	# 40 px left of centre — a left-push press point). The sticks
	# themselves are MOUSE_FILTER_IGNORE, and the intended buttons
	# (reload/grenade/switch/pause/score) sit far from the stick.
	var pts: Array = [g.move_stick.get_global_rect().get_center(), g.move_stick.get_global_rect().get_center() + Vector2(-40, 0)]
	var bad: Array = []
	var stack: Array = [g.hud]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is Control:
			var c := n as Control
			if c.is_visible_in_tree() and c.mouse_filter == Control.MOUSE_FILTER_STOP:
				var r := c.get_global_rect()
				for p in pts:
					if r.has_point(p):
						bad.append("%s rect=%s covers %s" % [c.name, str(r), str(p)])
						break
		for ch in n.get_children():
			stack.append(ch)
	return bad


func _jt_c_gui_stick_clear() -> Array:
	var bad := _jt_gui_blockers()
	var ok: bool = bad.is_empty()
	return [ok, "blockers=%s" % ["none" if ok else "; ".join(bad)]]


func _jt_gui_press_left() -> void:
	# A REAL touch through the viewport input pipeline (GUI first,
	# then _unhandled_input) — the exact path a phone finger takes.
	# Press on the stick centre, drag 50 px left, index 903.
	var centre: Vector2 = g.move_stick.get_global_rect().get_center()
	var to_vp: Vector2 = g.hud.get_final_transform() * centre
	var press := InputEventScreenTouch.new()
	press.index = 903
	press.pressed = true
	press.position = to_vp
	g.get_viewport().push_input(press)
	var drag = InputEventScreenDrag.new()
	drag.index = 903
	drag.position = g.hud.get_final_transform() * (centre + Vector2(-50, 0))
	g.get_viewport().push_input(drag)


func _jt_s_gui_press_left() -> void:
	_jt_teleport_clear_left()
	_jt_gui_press_left()


func _jt_s_gui_press_left_mid() -> void:
	# QA-132: L3 left row is now (900,6984,600) — stand at (1400,
	# 6950) with 500 px of clear run left. Same real-GUI press.
	var lp = _jt_lp()
	lp.position = Vector2(1400, 6950)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_jt_gui_press_left()


func _jt_s_gui_press_left_top() -> void:
	# Summit platform (top y862, x1200-2400): stand at (1600, 831)
	# with 400 px of clear run left, gate (x1800) to the right.
	var lp = _jt_lp()
	lp.position = Vector2(1600, 831)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_jt_gui_press_left()


func _jt_c_gui_press_left() -> Array:
	var lp = _jt_lp()
	var v = g.touch_move_vec
	var ok: bool = v.x < -0.5 and absf(v.y) < 0.15 and lp.velocity.x < -50.0 and lp.facing == -1
	# Release the real touch through the same pipeline.
	var rel := InputEventScreenTouch.new()
	rel.index = 903
	rel.pressed = false
	rel.position = g.hud.get_final_transform() * g.move_stick.get_global_rect().get_center()
	g.get_viewport().push_input(rel)
	return [ok, "vec=%s vel.x=%d facing=%d stick_active=%s" % [v, round(lp.velocity.x), lp.facing, str(g.move_stick.is_active())]]


func _jt_c_fuel_stable() -> Array:
	var lp = _jt_lp()
	# No thrust input: fuel must not decrease (it refills on the ground,
	# stays put in the air — either way it never goes down).
	var ok: bool = lp.fuel >= _joy_fuel_before - 0.5
	return [ok, "fuel=%d (was %d)" % [round(lp.fuel), round(_joy_fuel_before)]]


func _jt_s_press_down() -> void:
	var lp = _jt_lp()
	if g.map_id == GameData.SKYFALL_MAP_ID:
		# Skyfall: (2100, 900) lands ON the summit platform, so the
		# player is on the floor and vel.y stays 0. x100 is a clear
		# shaft to the base floor (352 px of fall, no platform under
		# it until y10752).
		lp.position = Vector2(100, 10400)
	else:
		lp.position = Vector2(2100, 900)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_jt_press_move(Vector2(0, 55))


func _jt_c_press_down() -> Array:
	var lp = _jt_lp()
	var v = g.touch_move_vec
	# Down past the threshold while airborne: fast fall (vy well above
	# the normal-fall value of ~107 after 0.4 s at reference gravity 300).
	# QA-141: the bar is 500, not 700 — fast fall is gravity 300 +
	# 1600 extra under 0.6/s drag, so vy(0.4 s) ~= 675 (was ~1400
	# under the old gravity 1400, where 700 had margin).
	var ok: bool = v.y > 0.5 and lp.velocity.y > 500.0
	_jt_release_move()
	return [ok, "vec=%s vel.y=%d" % [v, round(lp.velocity.y)]]


func _jt_s_diag_up_right() -> void:
	var lp = _jt_lp()
	if g.map_id == GameData.SKYFALL_MAP_ID:
		# Skyfall: (900, 1318) is mid-air here (no platform under it),
		# so the up-press fires the jetpack instead of a jump and
		# vel.y reads +81 at the check. Stand on the wide y1712
		# platform instead (top y1712, x600-3000): centre y1681.
		# QA-132: the old (900,1542) platform above is gone — the
		# nearest overhead now is the (1500,1424) summit step,
		# far right of x700, and the (700,690) perch is ~990 px
		# above, so the diagonal jump can actually rise; drifting
		# right for 0.5 s only reaches ~x823, still clear of it.
		lp.position = Vector2(700, 1681)
		lp.sync_position = lp.position
		lp.velocity = Vector2.ZERO
		# QA-141: (42,-55), not (42,-42) — the diagonal's up
		# component must clear the reference 0.75 jump gate (42,-42
		# gives -0.70, which no longer jumps). (42,-55) clamps to
		# a (0.61,-0.80) vector: inside the check's x/y bands.
		_jt_press_move(Vector2(42, -55))
		return
	# QA-141: (900, 1318) is WRONG — it sits under the y1180
	# platform Rect2(700, 1180, 350, 48), bottom 1228, only 62 px
	# above the head. The diagonal jump bonks it (probe:
	# ceil=true, pos.y pinned at 1259.065, vy=0.0 while
	# jetpacking=true and fuel draining), so vel.y < 0 could
	# never pass there. The old comment missed this platform
	# (it listed only the 840/1010 rows). (2350, 1321) was the
	# 1180-row gap (2300..2550) in the OLD Ironfall.
	# QA-143: the Outpost rebuild moved the 1180 runs — x2350 is
	# now UNDER the (2092..2400) run, so the jump bonks again
	# (full suite: vel=(148,0)). (1415, 1321) is the new 1180-row
	# gap (1292..1538): open sky up to the 1010 row (1477..1846,
	# bottom 1058, 148 px above the head at full rise), and the
	# rightward drift (~75 px in 0.5 s) stays inside the gap,
	# clear of the 1538 run. The physics is correct — reference would
	# bonk the same ceiling — the old spot was simply the wrong
	# place to prove a diagonal jump.
	# QA-141: (42,-55), not (42,-42) — see the Skyfall branch above.
	# QA-141: teleport to (1415,1321), not (1415,1318) — the standing
	# centre on the 1352 floor is 1352-31 = 1321, and 1318 leaves
	# the player 3 px in the air. At reference gravity 300 that 3 px
	# fall takes ~0.14 s, longer than the 0.12 s jump buffer, so
	# the stick-up edge was lost and the player never jumped
	# (vel.y read 0). At the old gravity 1400 the same fall took
	# 0.065 s, inside the buffer — that is why this only broke
	# now. The buffer itself is KEPT (QA-141: no buffer change).
	lp.position = Vector2(1415, 1321)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_jt_press_move(Vector2(42, -55))


func _jt_c_diag_up_right() -> Array:
	var lp = _jt_lp()
	var v = g.touch_move_vec
	var ok: bool = v.x > 0.55 and v.x < 0.85 and v.y < -0.55 and v.y > -0.85 and v.length() > 0.9 and v.length() <= 1.01 and lp.velocity.x > 50.0 and lp.velocity.y < 0.0
	return [ok, "vec=%s len=%.2f vel=(%d,%d)" % [v, v.length(), round(lp.velocity.x), round(lp.velocity.y)]]


func _jt_c_diag_speed() -> Array:
	var lp = _jt_lp()
	var v = g.touch_move_vec
	# Diagonal input is normalized: horizontal speed stays below the
	# full-run speed (250, QA-141 — was 330) instead of 250 * sqrt(2).
	# The diagonal target is 0.61 x 250 ~= 152 (the (42,-55) press
	# clamps to a (0.61,-0.80) vector), so the 150 lower bound is
	# tight by design: the headroom accel reaches it in ~0.3 s of
	# physics, and the step holds for 0.8 s total.
	var ok: bool = v.length() <= 1.01 and absf(lp.velocity.x) > 150.0 and absf(lp.velocity.x) < 300.0
	_jt_release_move()
	return [ok, "vec.len=%.2f vel.x=%d" % [v.length(), round(lp.velocity.x)]]


func _jt_s_knob_clamp() -> void:
	# Press far outside the stick: the knob must clamp to the base.
	# v3.3 QA-052: offset is 400, not 500 — touches are routed by
	# screen half, and the move stick's centre moved right to x=165,
	# so +500 would land at x=665, past the 640 half-line, and grab
	# the AIM stick instead. +400 (x=565) stays on the left half
	# while still being far outside the 60 px base radius.
	_jt_press_move(Vector2(400, 0))


func _jt_c_knob_clamp() -> Array:
	var v = g.touch_move_vec
	var ok: bool = g.move_stick.get_knob_offset().length() <= 60.5 and v.length() <= 1.01 and v.x > 0.9
	_jt_release_move()
	return [ok, "knob=%.1f vec=%s" % [g.move_stick.get_knob_offset().length(), v]]


func _jt_s_multi_touch() -> void:
	_joy_shots_before = _jt_lp()._shots_fired
	_jt_press_move(Vector2(60, 0))
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_c_multi_touch() -> Array:
	var lp = _jt_lp()
	# v3.2: move + aim are two independent fingers; deflecting the aim
	# stick fires (no separate FIRE finger any more).
	var ok: bool = g.move_stick.is_active() and g.aim_stick.is_active() and g.touch_firing and lp._shots_fired > _joy_shots_before
	return [ok, "move_active=%s aim_active=%s firing=%s shots=%d (was %d)" % [g.move_stick.is_active(), g.aim_stick.is_active(), g.touch_firing, lp._shots_fired, _joy_shots_before]]


func _jt_s_release_move_only() -> void:
	_jt_release_move()


func _jt_c_release_move_only() -> Array:
	# Releasing the move finger must NOT disturb the aim finger —
	# the aim stick stays held and keeps firing.
	var ok: bool = g.touch_move_vec == Vector2.ZERO and not g.move_stick.is_active() and g.aim_stick.is_active() and g.touch_firing
	return [ok, "move_vec=%s move_active=%s aim_active=%s firing=%s" % [g.touch_move_vec, g.move_stick.is_active(), g.aim_stick.is_active(), g.touch_firing]]


func _jt_s_release_fire() -> void:
	# v3.2: "release fire" means releasing the AIM stick — firing
	# stops the moment the stick returns to centre.
	_jt_release_aim()
	# QA-029: refresh the touch state NOW, then capture the baseline.
	# touch_firing only updates in _update_touch_state(), so without
	# this a physics step between the release and the next _process
	# could still see the stale "firing" value and fire one shot.
	g._update_touch_state()
	_joy_shots_before = _jt_lp()._shots_fired


func _jt_c_release_fire_stops_fire() -> Array:
	# v3.2: releasing the aim stick stops the shooting (there is no
	# separate FIRE finger any more — the aim stick IS the fire control).
	var lp = _jt_lp()
	var ok: bool = not g.touch_firing and not g.aim_stick.is_active() and lp._shots_fired == _joy_shots_before
	return [ok, "firing=%s aim_active=%s shots=%d (was %d)" % [g.touch_firing, g.aim_stick.is_active(), lp._shots_fired, _joy_shots_before]]


func _jt_s_press_aim() -> void:
	_jt_press_aim(Vector2(42, -42))


func _jt_s_press_aim_fire() -> void:
	_jt_press_aim_fire()


func _jt_c_firing_on() -> Array:
	var lp = _jt_lp()
	_joy_shots_before = lp._shots_fired
	var ok: bool = g.touch_firing and g.aim_stick.is_active()
	return [ok, "firing=%s aim_active=%s shots=%d" % [g.touch_firing, g.aim_stick.is_active(), lp._shots_fired]]


func _jt_s_focus_out() -> void:
	# Simulate the OS interrupting the touch (app switch, notification
	# shade): the engine notifies every node; the game and the sticks
	# must all reset. No release event is ever delivered for this touch.
	g._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	g.move_stick._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	g.aim_stick._notification(Node.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	# QA-029: capture the shot baseline AFTER the reset, not in the
	# previous step's check — a shot can legitimately fire in the one
	# frame between that check and this reset (the finger is still
	# down until the OS notifies), which made the test flaky. Refresh
	# the touch state first so no physics step after this setup can
	# still see the stale "firing" value.
	g._update_touch_state()
	_joy_shots_before = _jt_lp()._shots_fired


func _jt_c_focus_out_reset() -> Array:
	var lp = _jt_lp()
	# A stale drag with the old aim touch index must NOT re-activate it.
	g._on_touch_drag(901, _jt_aim_center() + Vector2(42, -42))
	var ok: bool = not g.touch_firing and g.touch_move_vec == Vector2.ZERO and g.touch_aim == Vector2.ZERO and not g.move_stick.is_active() and not g.aim_stick.is_active() and lp._shots_fired == _joy_shots_before
	return [ok, "firing=%s move_vec=%s aim_vec=%s move_active=%s aim_active=%s shots=%d (was %d)" % [g.touch_firing, g.touch_move_vec, g.touch_aim, g.move_stick.is_active(), g.aim_stick.is_active(), lp._shots_fired, _joy_shots_before]]


func _jt_s_kill_and_aim_fire() -> void:
	var lp = _jt_lp()
	lp.take_damage(500, 1)
	_joy_shots_before = lp._shots_fired
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_c_fire_after_death() -> Array:
	var lp = _jt_lp()
	var ok: bool = not lp.alive and lp._shots_fired == _joy_shots_before
	_jt_release_aim()
	_jt_release_fire()
	return [ok, "alive=%s shots=%d (was %d)" % [lp.alive, lp._shots_fired, _joy_shots_before]]


func _jt_c_respawned() -> Array:
	var lp = _jt_lp()
	var ok: bool = lp.alive and lp.health == 100
	return [ok, "alive=%s health=%d" % [lp.alive, lp.health]]


func _jt_s_pause() -> void:
	_joy_shots_before = _jt_lp()._shots_fired
	g.get_tree().paused = true


func _jt_c_fire_while_paused() -> Array:
	var lp = _jt_lp()
	var ok: bool = lp._shots_fired == _joy_shots_before
	g.get_tree().paused = false
	_jt_release_aim()
	_jt_release_fire()
	return [ok, "shots=%d (was %d) paused_resumed_ok" % [lp._shots_fired, _joy_shots_before]]


func _jt_s_match_end_aim_fire() -> void:
	g.match_over = true
	_joy_shots_before = _jt_lp()._shots_fired
	_jt_press_aim(Vector2(42, -42))
	_jt_press_fire()


func _jt_c_fire_after_match_end() -> Array:
	var lp = _jt_lp()
	var ok: bool = lp._shots_fired == _joy_shots_before
	g.match_over = false
	_jt_release_aim()
	_jt_release_fire()
	return [ok, "shots=%d (was %d)" % [lp._shots_fired, _joy_shots_before]]


func _jt_s_hold_up_long() -> void:
	var lp = _jt_lp()
	if g.map_id == GameData.SKYFALL_MAP_ID:
		# Skyfall: (300, 1350) falls ~3900 px down the L1 shaft to
		# the y8764 walkway — 4 s is not enough to land. Use the
		# base floor with a clear shaft above (x100, no platform
		# overhead): jump, jetpack, fall back to the floor.
		lp.position = Vector2(100, 10718)
	else:
		lp.position = Vector2(300, 1350)
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	# QA-141: seed 30 fuel (~1.5 s of thrust at reference drain 21/s) — the
	# tank is 100 now (4.76 s), so a full tank would still be
	# thrusting at the end of the 4 s window and the player would
	# not have landed yet. ~1.5 s of thrust (~350 px of climb) +
	# the fall back lands in ~3.0 s, inside the 4 s window with
	# margin; 42 fuel (~2 s) would land at ~3.75 s, too tight.
	# (Was 90 fuel = 2 s at the old drain 45/s.)
	lp.fuel = 30.0
	# Hold the stick up for the whole 4 s: jump, jetpack until the fuel
	# runs out, fall back down and land — still holding up.
	_jt_press_move(Vector2(0, -55))


func _jt_c_no_rejump() -> Array:
	var lp = _jt_lp()
	# Landed and standing still: holding up through the landing must NOT
	# trigger a second jump (the stick-up jump is edge-triggered + armed).
	var ok: bool = lp.is_on_floor() and absf(lp.velocity.y) < 50.0
	_jt_release_move()
	return [ok, "on_floor=%s vel.y=%d fuel=%d" % [lp.is_on_floor(), round(lp.velocity.y), round(lp.fuel)]]


func _jt_s_resize_1920() -> void:
	# Phase 5: same clear-left teleport as _jt_s_press_left — after
	# the earlier steps the player is back at spawn#0, pressed
	# against the cover crate on its left.
	_jt_teleport_clear_left()
	g.get_window().size = Vector2(1920, 1080)
	_jt_press_move(Vector2(-50, 0))


func _jt_c_resolution_1920() -> Array:
	var lp = _jt_lp()
	var vp_size = g.get_viewport().get_visible_rect().size
	# The stick math is rect-based, so it must work at any window size;
	# the check is the vector, the viewport size is logged for the record.
	var ok: bool = g.touch_move_vec.x < -0.5 and lp.velocity.x < -50.0
	g.get_window().size = Vector2(1280, 720)
	_jt_release_move()
	return [ok, "viewport=%s vec=%s vel.x=%d" % [vp_size, g.touch_move_vec, round(lp.velocity.x)]]

