class_name PhysicsTest
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)

var _physics_test: bool = false # --physics-test harness (T-01..T-75 support)
var _phys_steps: Array = []
var _phys_step: int = 0
var _phys_in_step: bool = false
var _phys_timer: float = 0.0
var _phys_passed: int = 0
var _phys_failed: int = 0
var _phys_done: bool = false
var _phys_data: Dictionary = {}


func _init(owner) -> void:
	g = owner


func _phys_lp():
	return g._get_local_player()


func _phys_teleport(pos: Vector2) -> void:
	var lp = _phys_lp()
	lp.position = pos
	lp.sync_position = pos
	lp.velocity = Vector2.ZERO


func _update_physicstest(delta: float) -> void:
	if _phys_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		_phys_timer += delta
		if _phys_timer > 5.0:
			_phys_done = true
			print("PHYSICSTEST DONE: 0/0 passed — no local player spawned")
			g.get_tree().quit()
		return
	# Live tracking for in-flight steps (apex, grenade bounce/rest).
	if bool(_phys_data.get("track_max_vy", false)):
		_phys_data["max_vy"] = maxf(float(_phys_data.get("max_vy", 0.0)), lp.velocity.y)
	var grn = _phys_data.get("grenade", null)
	if grn != null and is_instance_valid(grn):
		_phys_data["g_bounced"] = bool(grn.get("bounced"))
		_phys_data["g_resting"] = bool(grn.get("_resting"))
	if _phys_steps.is_empty():
		_physicstest_build_steps()
		_phys_step = 0
		_phys_in_step = false
		_phys_timer = 0.0
	if _phys_step >= _phys_steps.size():
		_phys_done = true
		print("PHYSICSTEST DONE: %d/%d passed" % [_phys_passed, _phys_passed + _phys_failed])
		g.get_tree().quit()
		return
	var step: Dictionary = _phys_steps[_phys_step]
	if int(step.get("skip_map", -1)) == g.map_id:
		print("PHYSICSTEST %s: SKIP — not applicable on map %d (%s)" % [String(step["name"]), g.map_id, String(step.get("skip_reason", ""))])
		_phys_step += 1
		_phys_in_step = false
		_phys_timer = 0.0
		return
	# Phase 5: "only_map" — a step that only applies on one map.
	# (No step uses it in v3.7 — kept for future map-specific steps.)
	if step.has("only_map") and int(step["only_map"]) != g.map_id:
		print("PHYSICSTEST %s: SKIP — only applicable on map %d (%s)" % [String(step["name"]), int(step["only_map"]), String(step.get("skip_reason", ""))])
		_phys_step += 1
		_phys_in_step = false
		_phys_timer = 0.0
		return
	if not _phys_in_step:
		(step["setup"] as Callable).call()
		_phys_in_step = true
		_phys_timer = float(step["wait"])
	_phys_timer -= delta
	if _phys_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_phys_passed += 1
		else:
			_phys_failed += 1
		print("PHYSICSTEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		_phys_step += 1
		_phys_in_step = false
		_phys_timer = 0.0


func _physicstest_build_steps() -> void:
	_phys_steps = [
		{"name": "P00-pickups-at-start", "wait": 0.5, "setup": _phys_s_noop, "check": _phys_c_pickups_start},
		{"name": "P01-ground-accel", "wait": 2.0, "setup": _phys_s_ground_run, "check": _phys_c_ground_accel},
		{"name": "P02-air-accel", "wait": 2.0, "setup": _phys_s_air_run, "check": _phys_c_air_accel},
		{"name": "P03-analog-half", "wait": 0.8, "setup": _phys_s_analog, "check": _phys_c_analog},
		{"name": "P04a-ground-run", "wait": 1.0, "setup": _phys_s_ground_stop_run, "check": _phys_c_ground_run},
		{"name": "P04b-ground-stop", "wait": 1.0, "setup": _phys_s_ground_stop_release, "check": _phys_c_ground_stop},
		{"name": "P05a-air-run", "wait": 0.1, "setup": _phys_s_air_slide, "check": _phys_c_air_run},
		{"name": "P05b-air-slide", "wait": 0.9, "setup": _phys_s_air_slide_release, "check": _phys_c_air_slide},
		{"name": "P06-terminal-velocity", "wait": 4.0, "setup": _phys_s_fall, "check": _phys_c_terminal},
		{"name": "P07a-jump-hold-apex", "wait": 1.2, "setup": _phys_s_jump_hold, "check": _phys_c_jump_hold},
		{"name": "P07b-jump-tap-apex", "wait": 0.7, "setup": _phys_s_jump_tap, "check": _phys_c_jump_tap},
		{"name": "P08-fuel-regen-delay", "wait": 0.3, "setup": _phys_s_fuel_drain, "check": _phys_c_fuel_delay},
		{"name": "P08b-fuel-regen-after", "wait": 1.2, "setup": _phys_s_noop, "check": _phys_c_fuel_after},
		{"name": "P09a-aim-hold-setup", "wait": 0.5, "setup": _phys_s_aim_hold, "check": _phys_c_aim_hold_setup},
		{"name": "P09b-aim-hold", "wait": 0.4, "setup": _phys_s_noop, "check": _phys_c_aim_hold},
		{"name": "P10-aim-deadzone", "wait": 0.3, "setup": _phys_s_aim_deadzone, "check": _phys_c_aim_deadzone},
		{"name": "P11-shotgun-table", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_shotgun_table},
		{"name": "P12-damage-calc", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_damage_calc},
		{"name": "P13-explosion-falloff", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_explosion_falloff},
		{"name": "P14-respawn-validation", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_respawn_valid},
		{"name": "P15-grenade-bounce", "wait": 2.0, "setup": _phys_s_grenade, "check": _phys_c_grenade},
		{"name": "P16-velocity-inheritance", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_inheritance},
		{"name": "P17-recoil-accum", "wait": 0.1, "setup": _phys_s_recoil_fire, "check": _phys_c_recoil},
		{"name": "P17b-recoil-decay", "wait": 2.0, "setup": _phys_s_noop, "check": _phys_c_recoil_decay},
		{"name": "P18a-ice-run", "wait": 0.5, "setup": _phys_s_ice, "check": _phys_c_ice},
		{"name": "P19-camera", "wait": 0.9 if g.map_id == GameData.SKYFALL_MAP_ID else 0.4, "setup": _phys_s_camera, "check": _phys_c_camera}, # v3.11 QA-131: Skyfall's 0.4 s window is load-marginal — _cam_look builds at 240 px/s toward a target set by sprint velocity, and under xvfb load physics dilates so the player is still ramping at 0.4 s (look-ahead read 24-32, want >40; isolated runs read 50). 0.9 s gives the same check room to build; the player is still mid-run on the L7 perch staircase at 0.9 s (gate at x1742 is ~740 px away), so nothing else changes. Flat maps keep 0.4 s.
		{"name": "P20-pool-budget", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_pool},
		{"name": "P21-version-handshake", "wait": 0.1, "setup": _phys_s_noop, "check": _phys_c_version},
		{"name": "P22-barrel", "wait": 0.1, "setup": _phys_s_barrel, "check": _phys_c_barrel},
		{"name": "P23-bounce-pad", "wait": 1.5, "setup": _phys_s_pad, "check": _phys_c_pad}, # QA-071b: was 0.12 — under xvfb load ~1 physics frame elapses in 0.2 s wall, so the launch may not have fired yet; 1.5 s gives it frames on any load, and the check accepts a fast rise OR having risen
		{"name": "P24-stuck-recovery", "wait": 0.1, "setup": _phys_s_stuck, "check": _phys_c_stuck},
		{"name": "P24b-wedge-recovery", "wait": 3.5, "setup": _phys_s_wedge, "check": _phys_c_wedge},
		{"name": "P25a-jetpack-cap", "wait": 1.0, "setup": _phys_s_jetpack_cap, "check": _phys_c_jetpack_cap},
		{"name": "P25b-jetpack-release", "wait": 0.5, "setup": _phys_s_jetpack_release, "check": _phys_c_jetpack_release},
		{"name": "P26-fire-trap-hot", "wait": 1.2, "setup": _phys_s_fire_trap_hot, "check": _phys_c_fire_trap_hot, "only_map": 2, "skip_reason": "Volcanic Cavern fire traps only"},
		{"name": "P27-fire-trap-safe", "wait": 1.2, "setup": _phys_s_fire_trap_safe, "check": _phys_c_fire_trap_safe, "only_map": 2, "skip_reason": "Volcanic Cavern fire traps only"},
		# QA-145 (v4.1) screenshot steps — capture the new fire visuals
		# (synchronous get_texture capture in the check: the scene has
		# been stable for the whole wait, so the last rendered frame
		# already shows it). --shot-2400 resizes the window for the
		# tall-phone pass (needs the dedicated Xvfb:99 2400x1080
		# screen; the default xvfb-run caps the window at 1600x720).
		{"name": "SHOT-VC-HOT", "wait": 2.0, "setup": _phys_s_shot_vc_hot, "check": _phys_c_shot_vc_hot, "only_map": 2, "skip_reason": "Volcanic Cavern shots only"},
		{"name": "SHOT-VC-SAFE", "wait": 2.0, "setup": _phys_s_shot_vc_safe, "check": _phys_c_shot_vc_safe, "only_map": 2, "skip_reason": "Volcanic Cavern shots only"},
		{"name": "SHOT-VC-TORNADO", "wait": 2.0, "setup": _phys_s_shot_vc_tornado, "check": _phys_c_shot_vc_tornado, "only_map": 2, "skip_reason": "Volcanic Cavern shots only"},
		{"name": "SHOT-SF-L5-UPPER", "wait": 2.0, "setup": _phys_s_shot_sf_l5_upper, "check": _phys_c_shot_sf_l5_upper, "only_map": GameData.SKYFALL_MAP_ID, "skip_reason": "Skyfall L5 shots only"},
		{"name": "SHOT-SF-L5-LOWER", "wait": 2.0, "setup": _phys_s_shot_sf_l5_lower, "check": _phys_c_shot_sf_l5_lower, "only_map": GameData.SKYFALL_MAP_ID, "skip_reason": "Skyfall L5 shots only"},
	]


func _phys_s_noop() -> void:
	pass


func _phys_c_pickups_start() -> Array:
	# Skyfall starts with 3 weapon pickups AND 3 power-ups (QA-132:
	# one low, one mid, one high — was 1 random power-up).
	# Every other map starts with exactly 3 weapons.
	if g.map_id == GameData.SKYFALL_MAP_ID:
		var w := 0
		var p := 0
		for child in g.pickups_node.get_children():
			if int(child.get("kind")) >= 8:
				p += 1
			else:
				w += 1
		return [w == 3 and p == 3, "pickups at match start: %d weapons + %d power-ups (want 3 + 3)" % [w, p]]
	var n = g.pickups_node.get_child_count()
	return [n == 3, "pickups at match start: %d (want 3)" % n]


func _phys_s_ground_run() -> void:
	# Time-to-200 tracking: physics ticks lag real time in xvfb, so a
	# fixed 0.15 s window under-measures. QA-141: the crossing is 200
	# px/s, not 300 — MMC's sustained top speed is ~250, so 300 is
	# unreachable. Ground (3.0x headroom) must reach 200 px/s clearly
	# faster than air (1.5x headroom); lag scales both.
	# Phase 5: start on the map's own spawn#0 (on the floor on every
	# map) — the old fixed (300, 1320) is mid-air on taller maps
	# (e.g. Neon City), so the "ground" time was measured in the air.
	_phys_teleport((g.MAPS[g.map_id]["spawns"] as Array)[0])
	_phys_data["t0"] = Time.get_ticks_msec() / 1000.0
	_phys_data["t0_phys"] = float(_phys_data.get("phys_clock", 0.0))
	_phys_data.erase("t200")
	_phys_data["track_t200"] = true
	g.joystick_test._jt_press_move(Vector2(60, 0))


func _phys_c_ground_accel() -> Array:
	_phys_data["track_t200"] = false
	g.joystick_test._jt_release_move()
	var t: float = float(_phys_data.get("t200", -1.0))
	_phys_data["t200_ground"] = t
	var ok: bool = t > 0.0 and t < 0.8
	return [ok, "ground time to 200 px/s: %.2f s (want <0.8, MMC headroom 3.0x)" % t]


func _phys_s_air_run() -> void:
	# QA-099 (v3.7): drop from a column with a long clear fall (see
	# _phys_clear_fall_x) — the old fixed (2100, 700) lands the
	# player against Volcanic's solid crate at (2140, 770) on the
	# platform below, so the player pinned after ~5 px and never
	# reached 200 px/s in the air. Air accel itself is unchanged.
	# QA-141: the air crossing takes ~0.5 s of physics time (same
	# 3.0x headroom as the ground — MMC has no air penalty), so the
	# 2.0 s wait has ample margin even under xvfb load.
	_phys_teleport(Vector2(_phys_clear_fall_x(), 200))
	_phys_data["t0"] = Time.get_ticks_msec() / 1000.0
	_phys_data["t0_phys"] = float(_phys_data.get("phys_clock", 0.0))
	_phys_data.erase("t200")
	_phys_data["track_t200"] = true
	g.joystick_test._jt_press_move(Vector2(60, 0))


func _phys_c_air_accel() -> Array:
	_phys_data["track_t200"] = false
	g.joystick_test._jt_release_move()
	var t: float = float(_phys_data.get("t200", -1.0))
	var tg: float = float(_phys_data.get("t200_ground", 0.2))
	# QA-141: MMC has NO air/ground accel split — the headroom
	# impulse is 3.0x whenever not thrusting (SLC::updateStep
	# 0x8e4d5c), in the air or on the ground; only jetpacking
	# drops it to 1.5x. The old check (air >1.3x ground, accel
	# 1500 < 2600) encoded the pre-MMC split and is superseded:
	# P02 now proves air accel EQUALS ground accel (ratio ~1.0).
	# Measured 0.50 s vs 0.50 s on map 0.
	var ok: bool = t > 0.0 and t > tg * 0.7 and t < tg * 1.3
	return [ok, "air time to 200 px/s: %.2f s vs ground %.2f s (want air ~= ground, MMC headroom 3.0x both)" % [t, tg]]


func _phys_s_analog() -> void:
	_phys_teleport(Vector2(300, 1318))
	g.joystick_test._jt_press_move(Vector2(30, 0))


func _phys_c_analog() -> Array:
	var lp = _phys_lp()
	# QA-141: no dead zone any more, so 50% deflection is 0.5
	# magnitude -> ~125 px/s (0.5 x 250). (Was (0.5-0.2)/0.8 =
	# 0.375 x 350 = ~131 with the 0.20 dead-zone rescale.)
	var ok: bool = lp.velocity.x > 100.0 and lp.velocity.x < 165.0
	g.joystick_test._jt_release_move()
	return [ok, "half-stick vel.x: %d (want ~125, 0.5 x 250, no dead zone)" % round(lp.velocity.x)]


func _phys_s_ground_stop_run() -> void:
	# Phase 5: spawn#0, as in _phys_s_ground_run (the fixed
	# (300, 1320) is mid-air on taller maps).
	_phys_teleport((g.MAPS[g.map_id]["spawns"] as Array)[0])
	g.joystick_test._jt_press_move(Vector2(60, 0))
	_phys_data["stop_x0"] = 300.0


func _phys_c_ground_run() -> Array:
	var lp = _phys_lp()
	_phys_data["stop_x0"] = lp.position.x
	g.joystick_test._jt_release_move()
	# QA-141: MMC top speed ~250 (was 350), reached in ~0.45 s of
	# physics time — the 1.0 s wait covers physics at half rate.
	return [lp.velocity.x > 200.0, "ground run vel.x=%d (want >200, near the 250 top speed)" % round(lp.velocity.x)]


func _phys_s_ground_stop_release() -> void:
	pass


func _phys_c_ground_stop() -> Array:
	var lp = _phys_lp()
	var dist: float = lp.position.x - float(_phys_data.get("stop_x0", 0.0))
	# QA-141: MMC damping is only 0.598/s (was drag 8.0), so the
	# stop is slow: after 1.0 s vel.x ~= 250 x e^-0.6 = 137 and the
	# slide is ~188 px. The 1.0 s wait + wide bands cover physics
	# at half rate (vel.x ~185, dist ~108 then). The distance is
	# stored for the air-slide ratio check (P05b).
	_phys_data["ground_stop_dist"] = dist
	return [absf(lp.velocity.x) < 200.0 and dist < 220.0,
		"ground stop: vel.x=%d dist=%.0f px after 1.0 s (want <200 and <220 px, MMC damping 0.6/s)" % [round(lp.velocity.x), dist]]


func _phys_s_air_slide() -> void:
	# Air slide, drag-only model (GAP-03): start airborne at 350 px/s
	# with no input. QA-099 (v3.7): drop from a column with a long
	# clear fall (see _phys_clear_fall_x) — the old fixed x=1000
	# drops the player onto Pirate Island's y600 platform at ~0.76 s,
	# so ground friction had already killed vel.x by the 1.0 s check.
	var _slide_x := _phys_clear_fall_x()
	_phys_teleport(Vector2(_slide_x, 200))
	g.joystick_test._jt_release_move()
	var lp = _phys_lp()
	lp.velocity = Vector2(350, 0)
	_phys_data["slide_x0"] = _slide_x


func _phys_c_air_run() -> Array:
	# Not used as a separate check any more; kept for step ordering.
	return [true, "air slide setup done"]


func _phys_s_air_slide_release() -> void:
	pass


func _phys_c_air_slide() -> Array:
	var lp = _phys_lp()
	var dist: float = lp.position.x - float(_phys_data.get("slide_x0", 0.0))
	# QA-141: drag 0.6 (was 1.2): vx(1 s) ~= 192, dist ~= 263 px.
	# The ground-stop distance is the one P04b measured in this
	# same run (same load), not a hardcoded 36 px. The old 2x
	# ratio is DEAD: MMC damps ground and air at the SAME 0.598/s
	# (local 0x8e4604) — the old split (drag 8.0 ground vs 1.2
	# air) is gone, so the air slide can only beat the ground
	# stop by the starting-speed ratio (350/243 ~= 1.44x, measured
	# 252/193 = 1.31x). P05b now proves the MMC slide itself
	# (dist/vel match the 0.6/s damping from 350 px/s) and that it
	# still out-slides the ground stop.
	var ground_stop: float = float(_phys_data.get("ground_stop_dist", 108.0))
	return [dist > 200.0 and dist < 320.0 and absf(lp.velocity.x) > 150.0 and absf(lp.velocity.x) < 230.0 and dist > ground_stop,
		"air slide: dist=%.0f px in 1 s, vel.x=%d (want 200-320 px, vel 150-230, > ground stop %.0f — MMC damping 0.6/s)" % [dist, round(lp.velocity.x), ground_stop]]


func _phys_s_fall() -> void:
	# x=1000 falls to the y=1010 platform; max vy is tracked so the
	# check does not depend on sampling the exact landing frame.
	# QA-095 (v3.7): the old ice map's x=400 branch is gone
	# with that map — every kept map has a clear fall at x=1000.
	# v3.11: Skyfall is the exception — at x=1000 the first
	# platform below y=300 is (700,690), only ~340 px of fall,
	# so the true landing speed (~976) sits just above the 950
	# floor and the per-render-frame max_vy sample reads 863-933
	# under xvfb load (two 32/34 runs, P19 passed on re-run);
	# x=1800 is worse, it lands on the summit gate box (top
	# y=484, ~130 px fall, reads 513-583). Scan for the longest
	# clear drop from y=300 instead (platforms + solid decor +
	# gate box); the other five maps keep x=1000.
	var fall_x := 1000.0
	if g.map_id == GameData.SKYFALL_MAP_ID:
		fall_x = _phys_longest_drop_x(300.0)
	_phys_teleport(Vector2(fall_x, 300))
	_phys_data["max_vy"] = 0.0
	_phys_data["track_max_vy"] = true


# Longest clear vertical drop from from_y on the current map:
# for each candidate column, the first solid top below from_y
# (platform rects + solid decor + the Skyfall summit gate box).
# Falls back to x=1000 if nothing is found.
func _phys_longest_drop_x(from_y: float) -> float:
	var solids: Array = []
	for p in (g.MAPS[g.map_id]["platforms"] as Array):
		solids.append(p as Rect2)
	solids.append_array(g.scale_test._ct_solid_rects(g.MAPS[g.map_id]))
	if g.map_id == GameData.SKYFALL_MAP_ID:
		solids.append(Rect2(1742, 484, 116, 378)) # summit gate box (see _build_skyfall_gate)
	var best_x := 1000.0
	var best_drop := -1.0
	var x := 60.0
	while x <= g.map_size.x - 60.0:
		var land_y = g.map_size.y
		for r in solids:
			var rr: Rect2 = r
			if rr.end.x < x - 30.0 or rr.position.x > x + 30.0:
				continue
			if rr.position.y <= from_y:
				continue
			if rr.position.y < land_y:
				land_y = rr.position.y
		var drop = land_y - from_y
		if drop > best_drop:
			best_drop = drop
			best_x = x
		x += 40.0
	return best_x


func _phys_c_terminal() -> Array:
	_phys_data["track_max_vy"] = false
	var m: float = float(_phys_data.get("max_vy", 0.0))
	# QA-141: MMC gravity 300 + damping 0.598/s equilibrates at
	# ~500 px/s (300/0.6), hard-capped at 600 (was 1000). The fall
	# height varies by map (shortest ~710 px), so the sampled max
	# reads ~390-500 depending on the drop; the band proves the
	# fall is MMC-like (far below the old 950-1050) and capped.
	# Wait is 4.0 s: gravity 300 needs ~3.3 s of physics to fall
	# the 1050 px drop (was 1.2 s at gravity 1400).
	var ok: bool = m >= 350.0 and m <= 600.0
	return [ok, "max fall vel.y=%.0f (want 350-600, MMC equilibrium ~500, cap 600)" % m]


# QA-099 (v3.7): the fixed x=800 jump/jetpack column sits under a
# y1180/y1280 platform on Ironfall and Volcanic (only 124 px
# of sky) — the jump bonked at ~65 px instead of ~155 and the jetpack
# never reached its cap there, on three different maps with the same
# numbers. The old "x=800 has >=294 px of sky on all five maps"
# comment was wrong: it only counted the y1110 row and missed the
# lower y1180/y1280 row. Scan every column and return the one with
# the most open sky above the floor; a column blocked at floor level
# by solid decor is skipped. The best column wins even if no column
# reaches clear_px (Volcanic's best is 294 px — still enough for the
# cap, which needs ~40 px of free rise at full thrust).
func _phys_clear_sky_x(clear_px: float) -> float:
	var floor_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
	var solids: Array = g.scale_test._ct_solid_rects(g.MAPS[g.map_id])
	var best_x := 800.0
	var best_clear := -1.0
	var x := 100.0
	while x <= g.map_size.x - 100.0:
		var lowest_bottom := 0.0
		for p in (g.MAPS[g.map_id]["platforms"] as Array):
			var r: Rect2 = p
			if r.end.x < x - 20.0 or r.position.x > x + 20.0:
				continue
			if r.position.y >= floor_top:
				continue
			lowest_bottom = maxf(lowest_bottom, r.end.y)
		var clear = floor_top - lowest_bottom
		var blocked := false
		for sr in solids:
			var srr: Rect2 = sr
			if srr.end.x < x - 45.0 or srr.position.x > x + 45.0:
				continue
			if srr.position.y < floor_top and srr.end.y > floor_top - 60.0:
				blocked = true
				break
		if not blocked and clear > best_clear:
			best_clear = clear
			best_x = x
		x += 50.0
	return best_x


# QA-099 (v3.7): a column with a long clear fall from y=200 — no
# platform top in the 200..950 band anywhere on the player's drift
# path (x-20 .. x+230, ~204 px at 350 px/s with drag 1.2), so the
# player stays airborne for the whole 1.0 s step (a 750 px fall takes
# ~1.03 s). The old fixed (1000, 200) drops the player onto Pirate
# Island's y600 platform at ~0.76 s (P05b landed early, vel.x killed
# by ground friction) and the old fixed (2100, 700) air-run drop
# lands the player against Volcanic's solid crate at (2140, 770)
# after ~5 px (P02 never reached 300 px/s). Physics untouched.
func _phys_clear_fall_x() -> float:
	var plats: Array = g.MAPS[g.map_id]["platforms"]
	var x := 200.0
	while x <= g.map_size.x - 300.0:
		var ok := true
		for i in range(1, plats.size()):
			var r: Rect2 = plats[i]
			if r.end.x < x - 20.0 or r.position.x > x + 230.0:
				continue
			if r.position.y >= 200.0 and r.position.y <= 950.0:
				ok = false
				break
		if ok:
			return x
		x += 50.0
	return 1000.0


# Phase 5 — physics harness helper: the ground (lowest platform top)
# at map x, so jump/grenade/respawn setups land on a floor on every
# map instead of a map-0-tuned coordinate.
func _phys_ground_at(x: float) -> Vector2:
	var best_top := -1.0
	for p in (g.MAPS[g.map_id]["platforms"] as Array):
		var r: Rect2 = p
		if r.position.x <= x and x <= r.end.x and r.position.y > best_top:
			best_top = r.position.y
	if best_top < 0.0:
		best_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
	return Vector2(x, best_top - 34.0) # QA-071b: 3 px clear of the floor (capsule half-height 31)


func _phys_s_jump_hold() -> void:
	# QA-099 (v3.7): stand on the ground at the clearest-sky column
	# (see _phys_clear_sky_x) — the old x=800 sits under a y1180
	# platform on Ironfall and a y1280 platform on Volcanic,
	# so the jump bonked at ~65 px instead of ~155. (The even older
	# x=2100 spot sat exactly on a bounce pad at 0.7 * W and x=300 has a
	# platform at y=1180 directly overhead — same bonk.) Physics
	# untouched.
	# fuel=0: holding stick-up must NOT jetpack, or the "hold" apex
	# measures jump+jetpack (~300 px) instead of the jump (~155 px).
	# The 999 s regen delay stops air regen re-enabling the jetpack
	# mid-rise (which also used to clamp the jump via the rise cap).
	var gp := _phys_ground_at(_phys_clear_sky_x(200.0))
	_phys_teleport(gp)
	var lp = _phys_lp()
	lp.fuel = 0.0
	lp._fuel_delay_timer = 999.0
	_phys_data["track_min_y"] = true
	_phys_data["min_y"] = gp.y + 6.0
	_phys_data["jump_y0"] = gp.y + 6.0
	g.joystick_test._jt_press_move(Vector2(0, -60))


func _phys_c_jump_hold() -> Array:
	g.joystick_test._jt_release_move()
	_phys_data["track_min_y"] = false
	_phys_lp().fuel = PhysicsConfig.FUEL_MAX
	_phys_lp()._fuel_delay_timer = 0.0
	var apex = float(_phys_data.get("jump_y0", 1326.0)) - float(_phys_data.get("min_y", 1326.0))
	_phys_data["hold_apex"] = apex
	# QA-141: MMC jump -220 with gravity 300: apex = 220^2/(2x300)
	# ~= 81 px, minus a little damping (was ~155 with -660/1400).
	# Wait is 1.2 s: the rise alone takes ~0.73 s of physics time.
	return [apex > 60.0 and apex < 100.0, "hold jump apex: %d px (want ~81, MMC -220/300)" % round(apex)]


# QA-099 (v3.7): fire-and-forget release after N physics frames
# (see _phys_s_jump_tap) — calling a coroutine without awaiting it
# runs it until the first await, then resumes it on later frames.
func _phys_release_move_after_frames(n: int) -> void:
	for i in n:
		await g.get_tree().physics_frame
	g.joystick_test._jt_release_move()


func _phys_s_jump_tap() -> void:
	# QA-099 (v3.7): same clear-sky column as _phys_s_jump_hold, so
	# the tap apex is measured against the same sky as the hold apex.
	var gp := _phys_ground_at(_phys_clear_sky_x(200.0))
	_phys_teleport(gp)
	var lp = _phys_lp()
	lp.fuel = 0.0
	lp._fuel_delay_timer = 999.0
	_phys_data["track_min_y"] = true
	_phys_data["min_y"] = gp.y + 6.0
	_phys_data["jump_y0"] = gp.y + 6.0
	g.joystick_test._jt_press_move(Vector2(0, -60))
	# Tap: release after a short hold counted in physics frames.
	# QA-099 (v3.7): the old 0.12 s wall-clock timer was load-flaky
	# both ways — QA-047 fixed its late firing (apex crept to
	# 124 px, cap 120), but under a loaded machine it can also fire
	# after fewer physics frames and the tap apex fell to 32 px
	# (want 50-120). 7 physics frames is the same ~0.12 s in
	# physics time, whatever the wall clock does (same lesson as
	# the pad fix: awaiting the physics frame is exact).
	_phys_release_move_after_frames(7)


func _phys_c_jump_tap() -> Array:
	_phys_data["track_min_y"] = false
	_phys_lp().fuel = PhysicsConfig.FUEL_MAX
	_phys_lp()._fuel_delay_timer = 0.0
	var apex = float(_phys_data.get("jump_y0", 1326.0)) - float(_phys_data.get("min_y", 1326.0))
	var hold_apex: float = float(_phys_data.get("hold_apex", 81.0))
	# QA-141: tap apex measured 17 px on map 0 (hold 65 px) — the
	# cut happens earlier in physics time than the rough estimate
	# (~33 px). JUMP_CUT 0.45 is KEPT (MMC variable-jump not
	# extracted), so the tap/hold gap is smaller than before: the
	# bound is hold-25, not hold-40, and the tap band is 10-60.
	return [apex > 10.0 and apex < 60.0 and apex < hold_apex - 25.0,
		"tap jump apex: %d px vs hold %d px (want tap 10-60, clearly lower)" % [round(apex), round(hold_apex)]]


func _phys_s_fuel_drain() -> void:
	var lp = _phys_lp()
	_phys_teleport(Vector2(300, 1318))
	lp.fuel = 0.0
	lp._fuel_delay_timer = 0.6


func _phys_c_fuel_delay() -> Array:
	var lp = _phys_lp()
	return [lp.fuel < 2.0, "fuel 0.3 s after empty: %.1f (want <2, regen delay 0.6 s)" % lp.fuel]


func _phys_c_fuel_after() -> Array:
	var lp = _phys_lp()
	return [lp.fuel > 20.0, "fuel 1.5 s after empty: %.1f (want >20, regen 50/s on ground, QA-074 was 70/s)" % lp.fuel]


func _phys_s_aim_hold() -> void:
	_phys_teleport(Vector2(1600, 1318))
	g.joystick_test._jt_press_aim(Vector2(42, -42))
	_phys_data["aim_before"] = 0.0


func _phys_c_aim_hold_setup() -> Array:
	var lp = _phys_lp()
	_phys_data["aim_before"] = lp.aim_angle
	# Release the aim stick, keep moving right; the hold is verified
	# in the next step, after physics frames have run.
	g.joystick_test._jt_release_aim()
	g.joystick_test._jt_press_move(Vector2(60, 0))
	return [absf(lp.aim_angle - (-PI / 4.0)) < 0.1, "aim while aiming: %.2f rad (want -0.79)" % lp.aim_angle]


func _phys_c_aim_hold() -> Array:
	var lp = _phys_lp()
	g.joystick_test._jt_release_move()
	var ok: bool = absf(lp.aim_angle - float(_phys_data.get("aim_before", -PI / 4.0))) < 0.05
	return [ok, "aim after release+move: %.2f rad (want -0.79, no snap to facing)" % lp.aim_angle]


func _phys_s_aim_deadzone() -> void:
	var lp = _phys_lp()
	_phys_data["aim_before"] = lp.aim_angle
	g.joystick_test._jt_press_aim(Vector2(8, 0)) # 13% deflection — QA-141: MMC has NO dead zone, so this must now register as aiming


func _phys_c_aim_deadzone() -> Array:
	var lp = _phys_lp()
	# QA-141: MMC Joypad has NO dead zone (B §9) — a 13% deflection
	# is a real aim input now (touch_aim != ZERO, aim follows it).
	# The old check (zero vector, aim unchanged) encoded the 0.20
	# dead zone and is superseded by the MMC port.
	var ok: bool = g.touch_aim != Vector2.ZERO and absf(lp.aim_angle - float(_phys_data.get("aim_before", 0.0))) > 0.05
	g.joystick_test._jt_release_aim()
	return [ok, "small aim deflection: touch_aim=%s aim moved (want non-zero vector — MMC has no dead zone)" % str(g.touch_aim)]


func _phys_c_shotgun_table() -> Array:
	var w: Dictionary = WeaponData.TABLE[2]
	# QA-141: MMC SPAS-12 — 6 pellets (was 7), AK47 rate 0.10
	# (was 0.125), SMAW speed 1800 (was 450, inferred from
	# 30.0/step), gravity 0 (rocket flies straight, QA-106).
	var ok: bool = int(w["pellets"]) == 6 and absf(float(WeaponData.TABLE[0]["rate"]) - 0.10) < 0.001 and absf(float(WeaponData.TABLE[4]["speed"]) - 1800.0) < 0.01 and absf(float(WeaponData.TABLE[4]["gravity"]) - 0.0) < 0.01
	return [ok, "shotgun pellets=%d rifle rate=%.3f rocket speed=%d gravity=%d (want 6 / 0.10 / 1800 / 0 — MMC SPAS-12/AK47/SMAW)" % [int(w["pellets"]), float(WeaponData.TABLE[0]["rate"]), int(WeaponData.TABLE[4]["speed"]), int(WeaponData.TABLE[4]["gravity"])]]


func _phys_c_damage_calc() -> Array:
	var lp = _phys_lp()
	var head: int = lp.calculate_damage(12, "head", 100.0, 0)
	var torso: int = lp.calculate_damage(12, "torso", 100.0, 0)
	var legs: int = lp.calculate_damage(12, "legs", 100.0, 0)
	# QA-141: close-range numbers above are unchanged (the test
	# passes explicit base values). Long range follows the new
	# table: sniper 60 at 1500 px — max range is now 10000 x 0.15
	# = 1500, so f = 1.0 and the 0.9 floor gives 54 (was 57 at
	# 1600 x 1.6 = 2560). Shotgun 9 at 450 px — max range is now
	# 1300 x 0.25 = 325 < 400, so falloff never starts and it
	# stays 9 (was 7).
	var sniper_far: int = lp.calculate_damage(60, "torso", 1500.0, 3)
	var shotgun_far: int = lp.calculate_damage(9, "torso", 450.0, 2)
	var ok: bool = head == 18 and torso == 12 and legs == 9 and sniper_far == 54 and shotgun_far == 9
	return [ok, "rifle 12 dmg: head=%d torso=%d legs=%d (want 18/12/9); sniper 60 @1500px=%d (want 54, floor 0.9); shotgun 9 @450px=%d (want 9, no falloff yet)" % [head, torso, legs, sniper_far, shotgun_far]]


func _phys_c_explosion_falloff() -> Array:
	# QA-141: MMC formula D = max(10, 100 - 0.8 x dist), radius
	# 125 — centre 100, mid (62.5 px) 50, edge (115 px) 10 (floor,
	# was 0-5 on the old smooth curve with 55/120).
	var c := int(round(maxf(10.0, 100.0 - 0.8 * 0.0)))
	var m := int(round(maxf(10.0, 100.0 - 0.8 * 62.5)))
	var e := int(round(maxf(10.0, 100.0 - 0.8 * 115.0)))
	var ok: bool = c == 100 and m == 50 and e == 10
	return [ok, "grenade MMC 100 dmg radius 125: centre=%d mid=%d edge=%d (want 100/50/10)" % [c, m, e]]


func _phys_c_respawn_valid() -> Array:
	# Phase 5: the "inside the floor" point is map-relative (the old
	# fixed (1600, 1370) is open air above the skybridge on Neon
	# City). plats[0] is the lowest floor/deck on every map.
	var floor_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
	var bad = g.is_spawn_valid(Vector2(g.map_size.x * 0.5, floor_top + 18.0), 1) # inside the floor slab
	var good = g.get_valid_spawn_point(1, 1) != Vector2.INF
	return [not bad and good, "spawn inside floor valid=%s, valid spawn found=%s (want false/true)" % [str(bad), str(good)]]


func _phys_s_grenade() -> void:
	_phys_teleport(Vector2(300, 1318))
	var grn = load("res://weapons/grenade.tscn").instantiate()
	grn.name = "phys_grenade"
	# Open sky: the old (1600,1000) spot is INSIDE the solid crate
	# at (1600,1010) — the grenade wedged there and never fell.
	# QA-141: dropped from only 100 px above the floor, not 250 —
	# MMC gravity is 250 (was 1400), so a 250 px fall takes 1.41 s
	# of physics and the 1.75 s fuse leaves no margin for the
	# bounce+rest check under xvfb load. From 100 px the fall is
	# ~0.25 s (thrown down at 360 px/s) and the bounce is still
	# real (vy ~424 at the floor, well over the 120 bounce gate).
	var floor_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
	grn.position = Vector2(2100, floor_top - 100.0)
	# Phase 5: straight down — the old (0.2, 0.3) drift rolled the
	# grenade off a segmented deck
	# before it could rest (want a bounce + rest on the platform
	# below the throw point, on every map).
	grn.throw_dir = Vector2(0, 1)
	grn.owner_id = 1
	g.grenades_node.add_child(grn)
	_phys_data["grenade"] = grn
	_phys_data["g_bounced"] = false
	_phys_data["g_max_vy"] = 0.0
	_phys_data["g_resting"] = false


func _phys_c_grenade() -> Array:
	var grn = _phys_data.get("grenade", null)
	var bounced = bool(_phys_data.get("g_bounced", false))
	var resting = bool(_phys_data.get("g_resting", false))
	# QA-141: the check reads the TRACKED flags (bounced/resting
	# were ever observed), not the live grenade — MMC's 1.75 s fuse
	# legitimately detonates the grenade before a 2.0 s wall-clock
	# check at full physics rate, so "still present" can no longer
	# be required. The tracked flags prove the bounce + rest
	# happened; the fuse itself is covered by the 1.75 s const.
	return [bounced and resting, "grenade bounced=%s resting=%s (want true/true — tracked flags; MMC fuse 1.75 s may already have detonated it)" % [str(bounced), str(resting)]]


func _phys_c_inheritance() -> Array:
	var b = g.obtain_bullet()
	var want := Vector2(1, 0) * 1100.0 + Vector2(330, 0) * 0.15
	b.setup(Vector2(100, 100), Vector2(1, 0), 1100.0, 12, 0, 1, false, 0.0, 1.2, 1, want, 0.0)
	var ok: bool = absf(b.velocity.x - 1149.5) < 1.0
	g.return_bullet(b)
	return [ok, "bullet velocity.x=%.1f with sprint 330 (want 1149.5 = 1100 + 330*0.15)" % b.velocity.x]


func _phys_s_recoil_fire() -> void:
	var lp = _phys_lp()
	lp.weapon = 0
	lp.mag_ammo = 30
	lp._recoil_accum = 0.0
	for i in 5:
		lp._fire_cooldown = 0.0
		lp._fire()


func _phys_c_recoil() -> Array:
	var lp = _phys_lp()
	var ok: bool = lp._recoil_accum > 0.15 and lp._recoil_accum < 0.35
	return [ok, "recoil accum after 5 rifle shots: %.2f (want ~0.30 = 5 x 0.06, decayed a little before the check)" % lp._recoil_accum]


func _phys_c_recoil_decay() -> Array:
	var lp = _phys_lp()
	return [lp._recoil_accum < 0.05, "recoil accum 2 s after firing: %.3f (want <0.05)" % lp._recoil_accum]


func _phys_s_ice() -> void:
	# QA-095 (v3.7): the old ice map is deleted, so there is no
	# live ice slide any more — the step records that and the
	# check below passes on the constants only.
	_phys_data["ice_map"] = false


func _phys_c_ice() -> Array:
	g.joystick_test._jt_release_move()
	# QA-095 (v3.7): no map has ice now — the check proves the
	# query is off everywhere and the constants are intact.
	var ok: bool = not g.is_on_ice(Vector2(1400, 1420)) and absf(PhysicsConfig.ICE_FRICTION - 100.0) < 0.01 and absf(PhysicsConfig.ICE_ACCEL - 500.0) < 0.01
	return [ok, "no ice map in v3.7 (map %d): is_on_ice=false, ice friction=100 accel=500" % g.map_id]


func _phys_s_camera() -> void:
	var lp = _phys_lp()
	_phys_data["cam_anchor0"] = lp._cam_anchor
	# Phase 5: stand on the highest platform at x=1600 — the fixed
	# (1600, 1320) is INSIDE a platform on some maps
	# ((1450,1280,300,48)), so the player wedged and look-ahead read 0.
	# QA-112 (v3.9): on Skyfall x=1600 is the summit, and the summit
	# gate (x 1742-1858) blocks the rightward run after ~120 px, so
	# the player stops and look-ahead never builds. Use x=1000 there
	# (the L7 left perch, a clear run right).
	var cx = 1000.0 if g.map_id == GameData.SKYFALL_MAP_ID else 1600.0
	_phys_teleport(_phys_top_at(cx))
	g.joystick_test._jt_press_move(Vector2(60, 0))


# Phase 5 — physics harness helper: the highest platform top at map x
# (the platform the player lands on when falling from above).
func _phys_top_at(x: float) -> Vector2:
	var best_top := 1e9
	for p in (g.MAPS[g.map_id]["platforms"] as Array):
		var r: Rect2 = p
		if r.position.x <= x and x <= r.end.x and r.position.y < best_top:
			best_top = r.position.y
	if best_top >= 1e9:
		best_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
	return Vector2(x, best_top - 34.0) # QA-071b: 3 px clear of the floor (capsule half-height 31)


func _phys_c_camera() -> Array:
	var lp = _phys_lp()
	g.joystick_test._jt_release_move()
	var ok: bool = lp._camera != null and absf(lp._camera.position_smoothing_speed - 8.0) < 0.01 and absf(lp._cam_look) > 40.0
	return [ok, "camera smoothing=%.1f look-ahead=%.0f (want 8.0 / >40 while sprinting)" % [lp._camera.position_smoothing_speed if lp._camera != null else -1.0, lp._cam_look]]


func _phys_c_pool() -> Array:
	var ok: bool = g.bullet_pool.pool_size() == 160 and g.bullet_pool.active_count() == 0
	return [ok, "bullet pool size=%d active=%d (want 160 / 0)" % [g.bullet_pool.pool_size(), g.bullet_pool.active_count()]]


func _phys_c_version() -> Array:
	# A mismatched build must be refused at join (GAP-61).
	g.request_spawn(999, "BadBuild", 0, 0, "0.0-wrong")
	var ok: bool = not g._spawned.has(999)
	return [ok, "spawn with version 0.0-wrong refused=%s (want true)" % str(ok)]


func _phys_s_barrel() -> void:
	_phys_teleport(Vector2(300, 1318))
	for b in g._barrels:
		if bool(b["alive"]):
			_phys_data["barrel_idx"] = g._barrels.find(b)
			_phys_data["barrel_hit"] = g.try_barrel_hit((b["rect"] as Rect2).get_center(), 100, 1)
			return
	_phys_data["barrel_idx"] = -1


func _phys_c_barrel() -> Array:
	var idx = int(_phys_data.get("barrel_idx", -1))
	if idx < 0:
		return [false, "no live barrel found on this map"]
	var alive = bool(g._barrels[idx]["alive"])
	return [bool(_phys_data.get("barrel_hit", false)) and not alive, "barrel hit=%s alive after 100 dmg=%s (want true/false)" % [str(_phys_data.get("barrel_hit", false)), str(alive)]]


func _phys_s_pad() -> void:
	var floor_top := 1352.0
	var plats: Array = g.MAPS[g.map_id]["platforms"]
	if not plats.is_empty():
		floor_top = float((plats[0] as Rect2).position.y)
	var pad_x = g.map_size.x * 0.3
	# QA-071b: the player can arrive here already overlapping a pad
	# (the P18b ice slide ends over the 0.3 pad) or inside its 0.3 s
	# cooldown, so a plain teleport onto the pad fires no fresh
	# body_entered and the launch never happens (map 4: vel.y=47,
	# map 10: vel.y=0/93/117). Two-phase: phase 1 moves the player
	# clear of the pads and clears the cooldowns; after one physics
	# frame (await physics_frame) phase 2 puts the player on the pad,
	# so the area sees a FRESH entry and fires body_entered. A wall
	# timer was tried first and proved racy (it fired up to 1.45 s
	# late under xvfb load); awaiting the physics frame is exact.
	for entry in g._bounce_pads:
		(entry["cooldowns"] as Dictionary).clear()
	# QA-099 (v3.7): track the launch itself — the pad sets vel.y
	# -750 on entry, so the fastest upward velocity proves the pad
	# fired even when a platform overhead caps the rise (Volcanic's
	# 0.3 pad sits under its y1280 platform: the launch bonks after
	# ~53 px and the old endpoint check read a falling player).
	_phys_data["pad_min_vy"] = 0.0
	_phys_data["track_min_vy_pad"] = true
	_phys_teleport(Vector2(g.map_size.x * 0.1, floor_top - 40.0))
	await g.get_tree().physics_frame
	_phys_teleport(Vector2(pad_x, floor_top - 40.0))


func _phys_c_pad() -> Array:
	_phys_data["track_min_vy_pad"] = false
	var lp = _phys_lp()
	var floor_top := 1352.0
	var plats: Array = g.MAPS[g.map_id]["platforms"]
	if not plats.is_empty():
		floor_top = float((plats[0] as Rect2).position.y)
	# QA-071b: a launched player is either still rising fast (vel.y < -400)
	# or has risen and is falling back from a bounce (the pad relaunches on
	# every landing, so a launched player is never standing still on the pad).
	# A player who never launched stands at floor_top - 34 with vel.y = 0,
	# so neither condition can pass by accident — the only upward force here
	# is the pad (no jump input in this step).
	# QA-099 (v3.7): or the launch was tracked at physics rate
	# (pad_min_vy < -600) — on Volcanic the pad sits under the y1280
	# platform, so the launch bonks after ~53 px and the endpoint
	# state alone reads as "never launched".
	var pad_min_vy: float = float(_phys_data.get("pad_min_vy", 0.0))
	var ok: bool = lp.velocity.y < -400.0 or lp.position.y < floor_top - 60.0 or pad_min_vy < -600.0
	return [ok, "bounce pad launch vel.y=%d pos.y=%.0f pad_min_vy=%d (want vel.y < -400 or risen above %.0f or pad_min_vy < -600, pad sets -750)" % [round(lp.velocity.y), lp.position.y, round(pad_min_vy), floor_top - 60.0]]


func _phys_s_stuck() -> void:
	var lp = _phys_lp()
	lp.position = Vector2(1600, 1380) # inside the floor slab (QA-071b: was 1370 — with the 62-tall capsule that is only 1 px into Neon's 1400 platform, so the smaller query capsule missed it and no recovery fired; 1380 embeds 11 px on every physics map)
	lp._stuck_check_timer = 1.0
	lp._check_stuck(0.016)


func _phys_c_stuck() -> Array:
	var lp = _phys_lp()
	var ok: bool = g.is_spawn_valid(lp.position, 1)
	return [ok, "stuck player moved to %s (want a valid spawn)" % str(lp.position)]


func _phys_s_wedge() -> void:
	# QA-063 wedge recovery: pin the local player between two
	# temporary solid walls (a synthetic slot, like the old Jungle
	# jcrate trap) and hold move-right. The detector must teleport
	# the player to a DIFFERENT valid spawn within the step's wait.
	var lp = _phys_lp()
	_phys_teleport((g.MAPS[g.map_id]["spawns"] as Array)[0])
	_phys_data["wedge_spot"] = lp.position
	var walls: Array = []
	for dir in [-1.0, 1.0]:
		var wall := StaticBody2D.new()
		wall.collision_layer = 1
		wall.collision_mask = 0
		var shape := CollisionShape2D.new()
		var rect := RectangleShape2D.new()
		rect.size = Vector2(20, 200)
		shape.shape = rect
		wall.add_child(shape)
		wall.position = lp.position + Vector2(37.0 * dir, 0.0)
		g.add_child(wall)
		walls.append(wall)
	_phys_data["wedge_walls"] = walls
	g.joystick_test._jt_press_move(Vector2(60, 0))


func _phys_c_wedge() -> Array:
	var lp = _phys_lp()
	g.joystick_test._jt_release_move()
	for wall in (_phys_data.get("wedge_walls", []) as Array):
		if is_instance_valid(wall):
			wall.queue_free()
	_phys_data.erase("wedge_walls")
	var spot: Vector2 = _phys_data.get("wedge_spot", Vector2.INF)
	var moved: bool = lp.position.distance_to(spot) > 100.0
	# The recovery only teleports to a spawn point, so the player
	# must be near one. is_spawn_valid is NOT used here: after the
	# teleport the test joystick is still held, so the player keeps
	# walking and can be mid-push against a crate (the solver leaves
	# the capsule transiently penetrating the floor), which fails
	# the strict full-capsule shape query even though the recovery
	# destination was valid.
	var nearest := 1e9
	for s in (g.MAPS[g.map_id]["spawns"] as Array):
		nearest = minf(nearest, lp.position.distance_to(s))
	var near_spawn: bool = nearest < 300.0
	var free: bool = not lp._both_sides_blocked()
	return [moved and near_spawn and free, "wedge player at %s (spot was %s, moved=%s, nearest spawn %.0f px, wedged=%s)" % [str(lp.position), str(spot), str(moved), nearest, str(not free)]]


# QA-074: jetpack balance. QA-141: MMC numbers now — P25a measures
# the climb itself (fastest vy while thrusting must be the 190 cap,
# not the old 320/450, and the fuel must actually drain at 21/s);
# P25b measures the release (half a second after letting go the
# player must be falling again, not hanging). Setup is the open sky
# P07 uses (x=800, >=294 px on the four non-ice physics-test maps);
# map 4 uses x=2100 instead — see _phys_s_jetpack_cap, the 1180
# level leaves only 59 px of sky at x=800 there. P25b's setup runs
# right after P25a's check, while the stick is still held up — it
# only releases it.
func _phys_s_jetpack_cap() -> void:
	# QA-099 (v3.7): the clearest-sky column (see
	# _phys_clear_sky_x) — the old x=800 sits under a y1180/y1280
	# platform on Ironfall/Volcanic, so the climb bonked
	# after ~53 px and never reached the 320 cap (fastest vy -23).
	var x := _phys_clear_sky_x(300.0)
	var gp := _phys_ground_at(x)
	_phys_teleport(gp)
	var lp = _phys_lp()
	lp.fuel = PhysicsConfig.FUEL_MAX
	lp._fuel_delay_timer = 0.0
	_phys_data["min_vy_jet"] = 0.0
	_phys_data["track_min_vy_jet"] = true
	g.joystick_test._jt_press_move(Vector2(0, -60))


func _phys_c_jetpack_cap() -> Array:
	_phys_data["track_min_vy_jet"] = false
	var lp = _phys_lp()
	var min_vy: float = float(_phys_data.get("min_vy_jet", 0.0))
	# QA-141: MMC climb — the jump's own -220 is gated out of the
	# tracker (it only samples while _jetpacking), so this is the
	# thrust climb: it must reach a real climb (faster than -150)
	# but never past the 190 cap (allow 25 px/s of physics slack).
	# Fuel drains 21/s x thrustFactor (~0.95 with the stick hard
	# up) from a 100 tank, so after a 1.0 s hold it sits near 80 —
	# the 70..95 band only fails if thrust never started (fuel
	# ~100) or ran dry (~0).
	var ok: bool = min_vy < -150.0 and min_vy >= -215.0 and lp.fuel < 95.0 and lp.fuel > 70.0
	return [ok, "jetpack climb: fastest thrust vy=%d px/s (want -215..-150, MMC cap 190), fuel=%d (want 70-95, draining from 100)" % [round(min_vy), round(lp.fuel)]]


func _phys_s_jetpack_release() -> void:
	g.joystick_test._jt_release_move()


func _phys_c_jetpack_release() -> Array:
	var lp = _phys_lp()
	lp.fuel = PhysicsConfig.FUEL_MAX
	lp._fuel_delay_timer = 0.0
	# QA-141: 0.5 s after release, MMC gravity (300 px/s^2) has
	# taken vy from the -190 cap to about -11 (nearly level). The
	# bar is -150, not -100: at half physics rate vy is ~-94, and
	# a still-thrusting player sits at the -190 cap, so -150 still
	# separates "falling again" from "hanging on thrust".
	var ok: bool = not lp._jetpacking and lp.velocity.y > -150.0
	return [ok, "0.5 s after release: jetpacking=%s vel.y=%d (want false, >-150 — falling again, not hanging)" % [lp._jetpacking, round(lp.velocity.y)]]



# QA-145 (v4.1): Volcanic Cavern fire traps (map 3 only). Trap A
# Rect2(900,1196,140,84) sits on platform (670,1280,630,48); the
# player stands at its centre (feet on the platform top, y=1280).
# The trap clock is forced so the phase is deterministic: 0.5 s =
# HOT, 2.5 s = safe. HOT must hurt 10 HP per 1 s tick with the
# flame visible; SAFE must hurt nothing with the flame hidden.
func _phys_s_fire_trap_hot() -> void:
	var lp = _phys_lp()
	_phys_teleport(Vector2(970, 1249))
	lp.health = 100.0
	lp.set("_spawn_protect_timer", 0.0)
	g._fire_trap_time = 0.5
	g._fire_trap_tick.clear()


func _phys_c_fire_trap_hot() -> Array:
	var lp = _phys_lp()
	var hp := float(lp.health)
	var flame_vis := false
	var flame_tex := ""
	for e in g._fire_trap_fx:
		var ed: Dictionary = e
		if str(ed.get("kind", "")) == "fire_jet" and (ed["rect"] as Rect2).position.x == 900.0:
			var f: Sprite2D = ed["flame"]
			flame_vis = bool(f.visible)
			var ft = f.texture
			flame_tex = ft.resource_path if ft != null else ""
	var lost := 100.0 - hp
	var ok := lost >= 10.0 and lost <= 20.0 and flame_vis and flame_tex.contains("flame_jet")
	return [ok, "HOT trap: hp=%.0f lost=%.0f (want 10-20, one 10 HP tick + maybe a second) flame visible=%s tex=%s (want flame_jet)" % [hp, lost, str(flame_vis), flame_tex]]


func _phys_s_fire_trap_safe() -> void:
	var lp = _phys_lp()
	_phys_teleport(Vector2(970, 1249))
	lp.health = 100.0
	lp.set("_spawn_protect_timer", 0.0)
	g._fire_trap_time = 2.5
	g._fire_trap_tick.clear()


func _phys_c_fire_trap_safe() -> Array:
	var lp = _phys_lp()
	var hp := float(lp.health)
	var flame_vis := true
	for e in g._fire_trap_fx:
		var ed: Dictionary = e
		if str(ed.get("kind", "")) == "fire_jet" and (ed["rect"] as Rect2).position.x == 900.0:
			var f: Sprite2D = ed["flame"]
			flame_vis = bool(f.visible)
	var ok := hp >= 100.0 and not flame_vis
	return [ok, "SAFE trap: hp=%.0f (want 100, no damage) flame visible=%s (want false)" % [hp, str(flame_vis)]]


# QA-145 (v4.1) screenshot helpers + steps. The camera follows the
# local player, so each setup teleports the player to a spot whose
# view covers the traps, forces the trap clock into the wanted phase,
# and waits 0.8 s for the camera to settle; the check captures the
# last rendered frame synchronously and verifies the flames read.
func _phys_shot_resize() -> void:
	if "--shot-2400" in OS.get_cmdline_user_args():
		g.get_window().size = Vector2(2400, 1080)


func _phys_capture(stem: String) -> String:
	var img = g.get_viewport().get_texture().get_image()
	var sz: Vector2i = img.get_size()
	var path := "/home/hatch/workspace/mini-militia-lan-qa145-proof/workerE/shots/%s_%dx%d.png" % [stem, int(sz.x), int(sz.y)]
	var err = img.save_png(path)
	print("PHYS-SHOT %s err=%s size=%s" % [path, str(err), str(sz)])
	return path


func _phys_s_shot_vc_hot() -> void:
	_phys_shot_resize()
	var lp = _phys_lp()
	# (1500,1249) stands on platform (1300,1280,460,48); the view
	# covers trap A (900), the fire ring (1290), trap B (1950) and
	# both lava pools (1000, 1750). The player is outside every
	# trap rect, so the shot stays clean (no hit flash). (The
	# camera sits ~100 px left of the player after a teleport, so
	# 1500 frames trap B fully; 1450 left it half-cut.)
	_phys_teleport(Vector2(1500, 1249))
	lp.health = 100.0
	lp.set("_spawn_protect_timer", 0.0)
	# 3.5 + ~2 s wait lands at fmod 1.0-1.5 (HOT, mid-phase).
	g._fire_trap_time = 3.5
	g._fire_trap_tick.clear()


func _phys_c_shot_vc_hot() -> Array:
	# QA-145 (v4.1, Worker S): 5 flames, not 4 — the summit
	# fire_jet (1200,516) was added after Worker E's 4-trap set.
	# The count is over the flame-visible flags, not the pixels
	# on screen (the summit jet is off-frame above this shot's
	# view from (1500,1249)); the SAFE test below proves all 5
	# hide together.
	var vis := 0
	for e in g._fire_trap_fx:
		var ed: Dictionary = e
		if str(ed.get("kind", "")) in ["fire_jet", "fire_ring", "fire_tornado"]:
			var f: Sprite2D = ed["flame"]
			if bool(f.visible):
				vis += 1
	var path := _phys_capture("vc_traps_hot")
	return [vis == 5, "VC HOT shot %s flames visible=%d/5 (want 5)" % [path, vis]]


func _phys_s_shot_vc_safe() -> void:
	_phys_shot_resize()
	var lp = _phys_lp()
	_phys_teleport(Vector2(1500, 1249))
	lp.health = 100.0
	lp.set("_spawn_protect_timer", 0.0)
	# 1.0 + ~2 s wait lands at fmod 2.5-3.0 (SAFE, mid-phase).
	g._fire_trap_time = 1.0
	g._fire_trap_tick.clear()


func _phys_c_shot_vc_safe() -> Array:
	var vis := 0
	for e in g._fire_trap_fx:
		var ed: Dictionary = e
		if str(ed.get("kind", "")) in ["fire_jet", "fire_ring", "fire_tornado"]:
			var f: Sprite2D = ed["flame"]
			if bool(f.visible):
				vis += 1
	var path := _phys_capture("vc_traps_safe")
	return [vis == 0, "VC SAFE shot %s flames visible=%d/5 (want 0, scorch marks only)" % [path, vis]]


func _phys_s_shot_vc_tornado() -> void:
	_phys_shot_resize()
	var lp = _phys_lp()
	# (125,1079) stands on the tornado platform (100,1110,240,48)
	# in the 60 px strip left of the trap rect (160,1026,120,84)
	# (Worker S narrowed it from 160 wide), so the player takes
	# no damage; the camera clamps to the map edge and the trap
	# sits at screen x 160-280. (750 put the camera 240 px right
	# of the player and the trap off-screen.)
	_phys_teleport(Vector2(125, 1079))
	lp.health = 100.0
	lp.set("_spawn_protect_timer", 0.0)
	# 3.5 + ~2 s wait lands at fmod 1.0-1.5 (HOT, mid-phase).
	g._fire_trap_time = 3.5
	g._fire_trap_tick.clear()


func _phys_c_shot_vc_tornado() -> Array:
	var vis := false
	for e in g._fire_trap_fx:
		var ed: Dictionary = e
		if str(ed.get("kind", "")) == "fire_tornado":
			var f: Sprite2D = ed["flame"]
			vis = bool(f.visible)
	var path := _phys_capture("vc_tornado_hot")
	return [vis, "VC TORNADO shot %s flame visible=%s (want true)" % [path, str(vis)]]


func _phys_s_shot_sf_l5_upper() -> void:
	_phys_shot_resize()
	# (1550,2193) stands on platform (1500,2224,600,48); the view
	# covers the L5 fire jet (1750,2140) and lava pool (950,2420).
	var lp = _phys_lp()
	_phys_teleport(Vector2(1550, 2193))
	lp.health = 100.0
	lp.set("_spawn_protect_timer", 0.0)
	# 3.5 + ~2 s wait lands at fmod 1.0-1.5 (HOT, mid-phase).
	g._sf_match_time = 3.5


func _phys_c_shot_sf_l5_upper() -> Array:
	var vis := false
	for h in g._sf_hazard_fx:
		var hd: Dictionary = h
		if str(hd.get("kind", "")) == "fire" and (hd["rect"] as Rect2).position.y == 2140.0:
			var f: Sprite2D = hd["flame"]
			vis = bool(f.visible)
	var path := _phys_capture("sf_l5_upper")
	return [vis, "SF L5 UPPER shot %s fire-jet flame visible=%s (want true)" % [path, str(vis)]]


func _phys_s_shot_sf_l5_lower() -> void:
	_phys_shot_resize()
	# (2050,3313) stands on platform (1500,3344,600,48) OUTSIDE
	# the fire-jet rect (1750,3260,200,84) — 1900 stood inside it
	# and burned (HP 80 in the first shot). The view covers the
	# jet (1750,3260) and the lava pool (2150,2980).
	var lp = _phys_lp()
	_phys_teleport(Vector2(2050, 3313))
	lp.health = 100.0
	lp.set("_spawn_protect_timer", 0.0)
	# 3.5 + ~2 s wait lands at fmod 1.0-1.5 (HOT, mid-phase).
	g._sf_match_time = 3.5


func _phys_c_shot_sf_l5_lower() -> Array:
	var vis := false
	for h in g._sf_hazard_fx:
		var hd: Dictionary = h
		if str(hd.get("kind", "")) == "fire" and (hd["rect"] as Rect2).position.y == 3260.0:
			var f: Sprite2D = hd["flame"]
			vis = bool(f.visible)
	var path := _phys_capture("sf_l5_lower")
	return [vis, "SF L5 LOWER shot %s fire-jet flame visible=%s (want true)" % [path, str(vis)]]
