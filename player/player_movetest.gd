class_name PlayerMovetest
extends RefCounted


# QA-140 (v3.15): extracted from player/player.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `p` (dependency injection).


var p # the owner (player/player.gd)


func _init(owner) -> void:
	p = owner


func _movetest_pre_tick(delta: float) -> void:
	if not p._movetest_active or p._movetest_done:
		return
	p._movetest_total += delta
	if p._movetest_total > 120.0:
		print("MOVETEST TIMEOUT: FAIL - steps did not finish in 120 s")
		_movetest_finish()
		return
	if not p.alive:
		print("MOVETEST DEAD: FAIL - local player died mid-test")
		_movetest_finish()
		return
	var game = p.get_game_node()
	if game != null and bool(game.get("match_over")):
		print("MOVETEST MATCH-OVER: FAIL - match ended mid-test")
		_movetest_finish()
		return
	# A carrier step forces the flag every frame: game.gd rewrites
	# carrying_flag from its own CTF state, and this runs before
	# _tick_boost_timers, so the timers always see the forced value.
	if bool(p._movetest_data.get("force_carrier", false)):
		p.carrying_flag = 1
	if p._movetest_step == -1:
		# Wait for the 3-2-1 countdown to end (during it the game
		# zeroes touch input, so no step may start). 15 s timeout.
		var cd := false
		if game != null:
			cd = bool(game.get("_countdown_active"))
		if not cd:
			p._movetest_step = 0
			p._movetest_in_step = false
			p._movetest_timer = 0.0
			p._movetest_data = {}
			_build_movetest_steps()
		elif p._movetest_total > 15.0:
			print("MOVETEST COUNTDOWN: FAIL - countdown still active after 15 s")
			_movetest_finish()
		return
	if p._movetest_step >= p._movetest_steps.size():
		_movetest_finish()
		return
	var step: Dictionary = p._movetest_steps[p._movetest_step]
	if not p._movetest_in_step:
		(step["setup"] as Callable).call()
		p._movetest_in_step = true
		p._movetest_timer = float(step["wait"])
	p._movetest_timer -= delta
	if p._movetest_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			p._movetest_passed += 1
		else:
			p._movetest_failed += 1
		print("MOVETEST %s: %s - %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		p._movetest_step += 1
		p._movetest_in_step = false
		p._movetest_timer = 0.0
		p._movetest_hold = {}
		p._movetest_press_jump = false


func _movetest_apply_input() -> void:
	# Runs right after _read_input in the local branch: the step's
	# held inputs win for this frame, and a one-frame jump edge (or
	# the rising edge of a held stick-up) is pulsed exactly once.
	if not p._movetest_active or p._movetest_done:
		return
	var move := float(p._movetest_hold.get("move", 0.0))
	var up := bool(p._movetest_hold.get("up", false))
	p._move_axis = move
	p._move_mag = absf(move)
	p._move_stick_y = -1.0 if up else 0.0
	p._jump_held = up
	if up and not p._movetest_up_prev:
		p._jump_pressed = true
	p._movetest_up_prev = up
	if p._movetest_press_jump:
		p._jump_pressed = true
		p._movetest_press_jump = false


func _movetest_finish() -> void:
	if p._movetest_done:
		return
	p._movetest_done = true
	print("MOVETEST DONE: %d/%d passed" % [p._movetest_passed, p._movetest_passed + p._movetest_failed])
	p.get_tree().quit()


func _mt_teleport(pos: Vector2) -> void:
	p.position = pos
	p.sync_position = pos
	p.velocity = Vector2.ZERO


func _build_movetest_steps() -> void:
	if not p.player_movement._is_skyfall():
		# Non-Skyfall run (--map=0): every fetcher must be empty
		# and no movement feature may fire.
		p._movetest_steps = [
			{"name": "NONSKYFALL-NOOP", "wait": 0.3, "setup": _mt_s_nonskyfall, "check": _mt_c_nonskyfall},
		]
		return
	p._movetest_steps = [
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


func _mt_s_nonskyfall() -> void:
	_mt_teleport(p.position + Vector2(0, -300))
	p.velocity = Vector2.ZERO
	p._movetest_press_jump = true
	p._movetest_data["pts"] = p.player_movement._skyfall_grapple_points().size()
	p._movetest_data["lines"] = p.player_movement._skyfall_jetpack_lines().size()


func _mt_c_nonskyfall() -> Array:
	var ok: bool = not p.player_movement._is_skyfall() and int(p._movetest_data.get("pts", -1)) == 0 and int(p._movetest_data.get("lines", -1)) == 0 and not p._grappling and not p._on_jetpack_line
	return [ok, "skyfall=%s points=%s lines=%s grappling=%s on_line=%s" % [p.player_movement._is_skyfall(), p._movetest_data.get("pts"), p._movetest_data.get("lines"), p._grappling, p._on_jetpack_line]]


func _mt_s_grapple_setup() -> void:
	# Teleport under point (1200,3000) and let the floor state settle:
	# is_on_floor() is stale for one frame after a teleport (it
	# reports the last move_and_slide), so the attach press must
	# wait for the next step - pressing on this frame would be
	# skipped as "on floor". The player stands at (1150,3250), 255 px
	# below the point (inside GRAPPLE_RANGE 320); the shaft x=1150-1200
	# is clear of platforms (the (1500,3344) platform starts at
	# x=1500, the (2100,3064) one at x=2100), so the rope can
	# actually pull the player up.
	# QA-141: the old spot (850,4650) under (900,4400) is STALE —
	# the QA-132 rebuild moved the grapple points and there is no
	# (900,4400) point in MAPS[4] anymore (nearest above the old
	# spot is 1687 px away), so the rope could never attach. This
	# is a test-geometry fix, not a physics change: the attach
	# code and GRAPPLE_RANGE are untouched.
	_mt_teleport(Vector2(1150, 3250))
	p.fuel = p.FUEL_MAX


func _mt_c_grapple_setup() -> Array:
	var ok: bool = not p.is_on_floor()
	return [ok, "on_floor=%s (want airborne after settle)" % p.is_on_floor()]


func _mt_s_grapple_attach() -> void:
	p._movetest_data["dist0"] = p.global_position.distance_to(Vector2(1200, 3000))
	p._movetest_data["y0"] = p.global_position.y
	p._movetest_press_jump = true


func _mt_c_grapple_attach() -> Array:
	var d = p.global_position.distance_to(Vector2(1200, 3000))
	var ok: bool = p._grappling and d < float(p._movetest_data.get("dist0", 9999.0)) - 50.0 and p.global_position.y < float(p._movetest_data.get("y0", 0.0)) - 30.0 and p.fuel >= 99.0
	return [ok, "grappling=%s dist %.0f->%.0f y %.0f->%.0f fuel=%.0f" % [p._grappling, p._movetest_data.get("dist0", 0.0), d, p._movetest_data.get("y0", 0.0), p.global_position.y, p.fuel]]


func _mt_s_grapple_release() -> void:
	p._movetest_data["vy0"] = p.velocity.y
	p._movetest_press_jump = true


func _mt_c_grapple_release() -> Array:
	var ok: bool = not p._grappling and p.velocity.y < -150.0 and p._grapple_cooldown > 0.5
	return [ok, "grappling=%s vel.y=%.0f (was %.0f) cooldown=%.2f" % [p._grappling, p.velocity.y, p._movetest_data.get("vy0", 0.0), p._grapple_cooldown]]


func _mt_s_grapple_cooldown() -> void:
	# Still inside the 1 s cooldown, still in range of (1200,3000):
	# a jump press here must NOT attach.
	p._movetest_press_jump = true


func _mt_c_grapple_cooldown() -> Array:
	var ok: bool = not p._grappling and p._grapple_cooldown > 0.0
	return [ok, "grappling=%s cooldown=%.2f" % [p._grappling, p._grapple_cooldown]]


func _mt_s_grapple_cdwait() -> void:
	# No press - just wait out the rest of the 1 s cooldown (the
	# release was ~0.35 s before this step, so 0.8 s clears it).
	pass


func _mt_c_grapple_cdwait() -> Array:
	var ok: bool = p._grapple_cooldown <= 0.05
	return [ok, "cooldown=%.2f (want <= 0.05)" % p._grapple_cooldown]


func _mt_s_grapple_reattach_setup() -> void:
	# Same settle as the first setup: back under the point (the
	# player landed on the ground floor during the cooldown wait).
	# QA-141: (1150,3250) under (1200,3000) — see _mt_s_grapple_setup.
	_mt_teleport(Vector2(1150, 3250))
	p.fuel = p.FUEL_MAX


func _mt_s_grapple_reattach() -> void:
	p._movetest_press_jump = true


func _mt_c_grapple_reattach() -> Array:
	var ok: bool = p._grappling and p._grapple_cooldown <= 0.0
	return [ok, "grappling=%s cooldown=%.2f" % [p._grappling, p._grapple_cooldown]]


func _mt_s_wall_pin() -> void:
	# Airborne beside the RIGHT boundary wall (face x=3376, full
	# map height): hold right into it for the step's wait. The
	# player starts 4 px off the face (capsule edge 3372) and pins
	# in ~0.1 s; it falls ~13 px in 0.3 s at reference gravity 300 and
	# no platform is near (3352,5000), so it stays pinned, airborne.
	# The grapple from the reattach step MUST be released first -
	# otherwise the rope keeps pulling the player up toward
	# (1200,3000) and they leave the wall (run 1).
	# QA-141: the old spot (760,3300) beside the "sniper tower's
	# left face (x=784)" is STALE — the QA-132 rebuild removed
	# that tower; there is no wall at x=784 anymore, so is_on_wall
	# could never go true there. The boundary wall is the same
	# mechanic (a vertical solid face), just a real one. Test-only
	# geometry fix; _try_wall_jump is untouched.
	p.player_movement._release_grapple(false)
	_mt_teleport(Vector2(3352, 5000))
	p._movetest_hold = {"move": 1.0, "up": false}


func _mt_c_wall_pin() -> Array:
	var ok: bool = p.is_on_wall() and not p.is_on_floor()
	return [ok, "is_on_wall=%s on_floor=%s wall_normal=%s" % [p.is_on_wall(), p.is_on_floor(), p.get_wall_normal()]]


func _mt_s_wall_jump() -> void:
	# Press jump while still holding right into the wall (the
	# wall-jump needs the stick pushed toward the wall). The
	# wait is 0.05 s: any longer and holding right recovers the
	# -380 push back past the -200 bound.
	p._movetest_hold = {"move": 1.0, "up": false}
	p._movetest_press_jump = true


func _mt_c_wall_jump() -> Array:
	var ok: bool = p.velocity.x < -200.0 and p.velocity.y < -300.0 and p._wall_jumps_used == 1
	return [ok, "vel=%s wall_jumps=%d (want x<-200, y<-300, 1 jump)" % [p.velocity, p._wall_jumps_used]]


func _mt_s_wall_reset() -> void:
	# Drop onto the (1500,3344) platform to land, then the chain
	# must reset to 0.
	# QA-141: (1800,3300), not (1800,3200) — the fall to the 3344
	# top is 13 px (standing centre 3313), landing in ~0.3 s inside
	# the 0.6 s wait. From 3200 the fall is 144 px, which takes
	# ~0.98 s at reference gravity 300 (it took 0.45 s at the old gravity
	# 1400) — the player would still be airborne at the check.
	_mt_teleport(Vector2(1800, 3300))
	p._movetest_hold = {}


func _mt_c_wall_reset() -> Array:
	var ok: bool = p.is_on_floor() and p._wall_jumps_used == 0
	return [ok, "on_floor=%s wall_jumps=%d" % [p.is_on_floor(), p._wall_jumps_used]]


func _mt_s_jetpack_line_setup() -> void:
	# On line 1 (x=1800, y 4000-5400) inside wind zone 1
	# (x 1400-2200, y 4000-5400): hold up for 0.5 s first, so the
	# jump transient is over and the jetpack is thrusting at steady
	# state (the first hold frame fires a -220 jump, which delays
	# thrust by ~0.1 s and would make a single-step drain
	# measurement meaningless).
	# QA-141: the old spot (1800,3350) is STALE — the QA-132 rebuild
	# moved jetpack line 1 to y 4000-5400 and wind zone 1 to
	# y 4000-5400; at y=3350 the player was on NO line and in NO
	# wind zone, so on_line read false and the drain read the full
	# 8.4 instead of the halved 4.2. (1800,4700) is on the line AND
	# in the zone, as the test intends. Test-only geometry fix;
	# the drain numbers themselves were already right (8.4 full).
	p.player_movement._release_grapple(false)
	_mt_teleport(Vector2(1800, 4700))
	p.fuel = p.FUEL_MAX
	p._movetest_hold = {"move": 0.0, "up": true}


func _mt_c_jetpack_line_setup() -> Array:
	# Fuel < 100 proves thrust ran (_jetpacking itself alternates
	# on skip frames at the -190 rise cap, so it is not asserted).
	var ok: bool = p._on_jetpack_line and p.fuel < 100.0
	return [ok, "on_line=%s fuel=%.1f (want <100, thrusting)" % [p._on_jetpack_line, p.fuel]]


func _mt_s_jetpack_line() -> void:
	# QA-141: steady state now — half drain = 21 x 0.5 x 0.4 = 4.2 fuel (was 9 at drain 45/s).
	p._movetest_data["fuel0"] = p.fuel
	p._movetest_hold = {"move": 0.0, "up": true}


func _mt_c_jetpack_line() -> Array:
	var drain = float(p._movetest_data.get("fuel0", 100.0)) - p.fuel
	var ok: bool = p._on_jetpack_line and drain > 3.0 and drain < 6.0 and p.velocity.x > -20.0
	return [ok, "on_line=%s fuel drain=%.1f (want ~4.2) vel.x=%.0f (want >-20, wind shielded)" % [p._on_jetpack_line, drain, p.velocity.x]]


func _mt_s_wind_off_line_setup() -> void:
	# Same wind zone, 300 px off the line: same 0.5 s steady-state
	# hold first, for the same reason.
	# QA-141: (1500,4700), not (1500,3350) — same stale geometry
	# as the line setup: wind zone 1 is y 4000-5400 now, so at
	# y=3350 there was no wind at all (vel.x read 0, want <-25).
	# (1500,4700) is 300 px off line 1 and inside the zone.
	_mt_teleport(Vector2(1500, 4700))
	p.fuel = p.FUEL_MAX
	p._movetest_hold = {"move": 0.0, "up": true}


func _mt_c_wind_off_line_setup() -> Array:
	var ok: bool = not p._on_jetpack_line and p.fuel < 100.0
	return [ok, "on_line=%s fuel=%.1f (want <100, thrusting)" % [p._on_jetpack_line, p.fuel]]


func _mt_s_wind_off_line() -> void:
	# QA-141: steady state now — full drain = 21 x 0.4 = 8.4 fuel
	# (was 18 at drain 45/s), and the wind pushes left (-150 px/s^2).
	p._movetest_data["fuel0"] = p.fuel
	p._movetest_hold = {"move": 0.0, "up": true}


func _mt_c_wind_off_line() -> Array:
	var drain = float(p._movetest_data.get("fuel0", 100.0)) - p.fuel
	var ok: bool = not p._on_jetpack_line and drain > 6.5 and drain < 10.5 and p.velocity.x < -25.0
	return [ok, "on_line=%s fuel drain=%.1f (want ~8.4) vel.x=%.0f (want <-25, wind pushes)" % [p._on_jetpack_line, drain, p.velocity.x]]


func _mt_s_carrier_line() -> void:
	# Carrier on the line: wind shield yes, fuel discount no, boost
	# activation no. Pickup while carrying must STORE the jetpack
	# boost (fuel 50 proves no activation: activation refills it).
	# QA-119: jetpack is kind 10 now (was 12); pickup only stores.
	_mt_teleport(Vector2(1800, 3350))
	p.fuel = 50.0
	p._fuel_delay_timer = p.FUEL_REGEN_DELAY
	p.carrying_flag = 1
	p._movetest_data["force_carrier"] = true
	p.apply_powerup(10)
	p._movetest_data["stored"] = p.stored_boosts.has(10)
	p._movetest_data["active0"] = p.active_boost_kind
	p._movetest_data["fuel0"] = p.fuel
	p._movetest_hold = {"move": 0.0, "up": true}


func _mt_c_carrier_line() -> Array:
	var ok: bool = bool(p._movetest_data.get("stored", false)) and int(p._movetest_data.get("active0", -1)) == 0 and p.active_boost_kind == 0 and p.jetpack_boost_timer <= 0.0 and p.fuel <= 50.5 and p.velocity.x > -20.0
	return [ok, "stored10=%s active=%d boost_t=%.1f fuel=%.1f (was %.1f) vel.x=%.0f" % [p._movetest_data.get("stored"), p.active_boost_kind, p.jetpack_boost_timer, p.fuel, p._movetest_data.get("fuel0", 0.0), p.velocity.x]]


func _mt_s_carrier_drop() -> void:
	# Drop the flag: QA-119 - the stored jetpack boost must NOT
	# start by itself any more (tap-to-activate only). The check
	# below proves it waits, then taps the slot and proves it starts.
	p._movetest_data["force_carrier"] = false
	p.carrying_flag = 0
	p._movetest_hold = {}


func _mt_c_carrier_drop() -> Array:
	var waited: bool = p.active_boost_kind == 0 and p.stored_boosts.has(10) and p.jetpack_boost_timer <= 0.0
	var tapped: bool = p.activate_slot(0)
	var ok: bool = waited and tapped and p.active_boost_kind == 10 and p.jetpack_boost_timer > 0.0 and p.fuel >= 99.0
	return [ok, "waited=%s tapped=%s active=%d boost_t=%.1f fuel=%.1f stored=%s" % [waited, tapped, p.active_boost_kind, p.jetpack_boost_timer, p.fuel, p.stored_boosts]]

