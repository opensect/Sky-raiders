class_name FireTest
extends RefCounted


# QA-140 (v3.15): extracted from game.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `g` (dependency injection).


var g # the owner (game.gd)

var _fire_test: bool = false # v2.4: --fire-test harness
var _fire_steps: Array = []
var _ft_fire_owns_aim: bool = false # v3.2: _ft_press_fire holds the aim stick when nothing else does
var _fire_step: int = 0
var _fire_in_step: bool = false
var _fire_timer: float = 0.0
var _fire_passed: int = 0
var _fire_failed: int = 0
var _fire_done: bool = false
var _fire_shots_before: int = 0
var _fire_pos_before: Vector2 = Vector2.ZERO
var _fire_grenades_before: int = 0
var _ft_tap_left: int = 0 # T-33 rapid-tap driver: taps remaining
var _ft_tap_timer: float = 0.0 # T-33: time until the next press/release
var _ft_tap_phase: int = 0 # T-33: 0 = press next, 1 = release next
var _ft_rifle_dev_start: int = 0 # QA-061: shot_devs size when the rifle-straight step starts
var _ft_smg_dev_start: int = 0 # QA-104: shot_devs size when the SMG-spread step starts
var _ft_inside_shots0: int = 0 # QA-055: _shots_fired when the inside-geometry step starts
var _ft_inside_old: Array = [] # QA-055: instance ids of bullets already flying at step start
var _fire_weapon_before: int = 0
var _fire_flashes_before: int = 0 # QA-075: _muzzle_flashes when the muzzle-flash step starts


func _init(owner) -> void:
	g = owner


func _update_firetest(delta: float) -> void:
	if _fire_done:
		return
	var lp = g._get_local_player()
	if lp == null:
		_fire_timer += delta
		if _fire_timer > 5.0:
			_fire_done = true
			print("FIRETEST DONE: 0/0 passed — no local player spawned")
			g.get_tree().quit()
		return
	if _fire_steps.is_empty():
		_firetest_build_steps()
		_fire_step = 0
		_fire_in_step = false
		_fire_timer = 0.0
	if _fire_step >= _fire_steps.size():
		_fire_done = true
		print("FIRETEST DONE: %d/%d passed" % [_fire_passed, _fire_passed + _fire_failed])
		g.get_tree().quit()
		return
	var step: Dictionary = _fire_steps[_fire_step]
	if not _fire_in_step:
		(step["setup"] as Callable).call()
		_fire_in_step = true
		_fire_timer = float(step["wait"])
	# T-33 rapid-tap driver: performs press/release pairs on a
	# schedule (0.10 s hold, 0.25 s gap — press-to-press 0.35 s,
	# comfortably above the pistol rate of 0.22 s).
	if _ft_tap_left > 0:
		_ft_tap_timer -= delta
		if _ft_tap_timer <= 0.0:
			if _ft_tap_phase == 0:
				_ft_press_fire()
				_ft_tap_phase = 1
				_ft_tap_timer = 0.10
			else:
				_ft_release_fire()
				_ft_tap_phase = 0
				_ft_tap_left -= 1
				_ft_tap_timer = 0.25
	_fire_timer -= delta
	if _fire_timer <= 0.0:
		var result: Array = (step["check"] as Callable).call()
		var ok: bool = bool(result[0])
		if ok:
			_fire_passed += 1
		else:
			_fire_failed += 1
		print("FIRETEST %s: %s — %s" % [String(step["name"]), "PASS" if ok else "FAIL", String(result[1])])
		# QA-047: the T-33 rapid-tap driver must not leak into the
		# next step. Under load its last tap can still be pending
		# when this step ends (physics runs behind real time, so
		# the 10th shot lands late) — the driver would then release
		# the next step's FIRE press, and FIRE-HOLD-CONTINUOUS read
		# 0 shots in the full regression. Stop the driver here.
		if _ft_tap_left > 0:
			_ft_tap_left = 0
			_ft_tap_phase = 0
			_ft_release_fire()
		_fire_step += 1
		_fire_in_step = false
		_fire_timer = 0.0


func _firetest_build_steps() -> void:
	_fire_steps = [
		{"name": "MOVE-ALONE-NO-FIRE", "wait": 1.0, "setup": _ft_s_move_alone, "check": _ft_c_move_alone},
		{"name": "AIM-ALONE-FIRES", "wait": 1.0, "setup": _ft_s_aim_alone, "check": _ft_c_aim_alone},
		{"name": "GRENADE-ALONE-NO-FIRE", "wait": 0.4, "setup": _ft_s_grenade_alone, "check": _ft_c_grenade_alone},
		{"name": "WEAPON-ALONE-NO-FIRE", "wait": 0.4, "setup": _ft_s_weapon_alone, "check": _ft_c_weapon_alone},
		{"name": "PISTOL-TAP-ONE-SHOT", "wait": 0.4, "setup": _ft_s_pistol_tap, "check": _ft_c_pistol_tap},
		{"name": "PISTOL-TEN-RAPID-TAPS", "wait": 4.5, "setup": _ft_s_ten_taps, "check": _ft_c_ten_taps},
		{"name": "FIRE-HOLD-CONTINUOUS", "wait": 2.5, "setup": _ft_s_fire_hold, "check": _ft_c_fire_hold},
		{"name": "FIRE-WHILE-MOVING", "wait": 1.0, "setup": _ft_s_fire_moving, "check": _ft_c_fire_moving},
		{"name": "FIRE-DIAGONAL-AIM", "wait": 1.0, "setup": _ft_s_fire_diagonal, "check": _ft_c_fire_diagonal},
		{"name": "FIRE-WHILE-JETPACK", "wait": 1.0, "setup": _ft_s_fire_jetpack, "check": _ft_c_fire_jetpack},
		{"name": "FIRE-WHILE-JUMPING", "wait": 0.5, "setup": _ft_s_fire_jump, "check": _ft_c_fire_jump},
		{"name": "SWITCH-SETUP", "wait": 0.5, "setup": _ft_s_switch_setup, "check": _ft_c_switch_setup},
		{"name": "SWITCH-WHILE-FIRING", "wait": 0.6, "setup": _ft_s_switch_mid, "check": _ft_c_switch_mid},
		{"name": "EMPTY-MAG-BLOCKED", "wait": 0.6, "setup": _ft_s_empty_mag, "check": _ft_c_empty_mag},
		{"name": "RELOAD-COMPLETES", "wait": 1.5, "setup": _ft_s_noop, "check": _ft_c_reload_done},
		{"name": "RELOAD-WHILE-MOVING", "wait": 0.6, "setup": _ft_s_reload_moving, "check": _ft_c_reload_moving},
		{"name": "THREE-FINGERS", "wait": 1.0, "setup": _ft_s_three_fingers, "check": _ft_c_three_fingers},
		{"name": "GRENADE-WHILE-FIRING-SETUP", "wait": 0.5, "setup": _ft_s_grenade_firing_a, "check": _ft_c_grenade_firing_a},
		{"name": "GRENADE-WHILE-FIRING", "wait": 0.6, "setup": _ft_s_grenade_firing_b, "check": _ft_c_grenade_firing_b},
		{"name": "SLIDE-OFF-SETUP", "wait": 0.5, "setup": _ft_s_slide_off_a, "check": _ft_c_slide_off_a},
		{"name": "SLIDE-OFF-STOPS-FIRE", "wait": 0.5, "setup": _ft_s_slide_off_b, "check": _ft_c_slide_off_b},
		{"name": "LAYOUT-1280", "wait": 0.3, "setup": _ft_s_noop, "check": _ft_c_layout_1280},
		{"name": "LAYOUT-1920-AND-TRANSFORM", "wait": 0.5, "setup": _ft_s_layout_1920, "check": _ft_c_layout_1920},
		{"name": "MP-SYNC-VALIDATION", "wait": 0.3, "setup": _ft_s_noop, "check": _ft_c_mp_sync},
		{"name": "MP-SINGLE-SHOT-ONE-BULLET", "wait": 0.15, "setup": _ft_s_single_bullet, "check": _ft_c_single_bullet},
		{"name": "MP-SHOTGUN-SIX-PELLETS", "wait": 0.15, "setup": _ft_s_pellets, "check": _ft_c_pellets},
		{"name": "RIFLE-STRAIGHT-2S-HOLD", "wait": 2.5, "setup": _ft_s_rifle_straight, "check": _ft_c_rifle_straight},
		{"name": "SMG-SPREAD-TIGHT", "wait": 0.7, "setup": _ft_s_smg_spread, "check": _ft_c_smg_spread},
		{"name": "ROCKET-STRAIGHT", "wait": 0.5, "setup": _ft_s_rocket_straight, "check": _ft_c_rocket_straight},
		{"name": "SNIPER-SIGHT-LINE", "wait": 0.8, "setup": _ft_s_sniper_scope, "check": _ft_c_sniper_scope},
		{"name": "BULLET-INSIDE-GEOMETRY", "wait": 0.3, "setup": _ft_s_bullet_inside, "check": _ft_c_bullet_inside},
		{"name": "BULLET-SIZE-80PCT", "wait": 0.15, "setup": _ft_s_bullet_size, "check": _ft_c_bullet_size},
		{"name": "MAG-MEMORY", "wait": 0.3, "setup": _ft_s_mag_memory, "check": _ft_c_mag_memory},
		{"name": "RELOAD-REFUND", "wait": 0.6, "setup": _ft_s_reload_refund, "check": _ft_c_reload_refund},
		{"name": "MUZZLE-FLASH", "wait": 0.3, "setup": _ft_s_muzzle_flash, "check": _ft_c_muzzle_flash},
	]


func _ft_lp():
	return g._get_local_player()


func _ft_move_center() -> Vector2:
	return g.move_stick.get_global_rect().get_center()


func _ft_aim_center() -> Vector2:
	return g.aim_stick.get_global_rect().get_center()


func _ft_press_move(offset: Vector2) -> void:
	g._on_touch_press(910, _ft_move_center() + offset)


func _ft_release_move() -> void:
	g._on_touch_release(910)


func _ft_press_aim(offset: Vector2) -> void:
	g._on_touch_press(911, _ft_aim_center() + offset)
	# QA-104/105/106 (v3.8): the fake press lands inside _process
	# (the runner), AFTER _update_touch_state already read the
	# sticks that frame — so the next physics tick would fire a
	# semi-auto weapon with the STALE aim angle (BULLET-INSIDE
	# fired right, the sniper step's angle, instead of left).
	# Refresh the touch state synchronously so the aim direction
	# is visible before any physics tick runs — same reason the
	# press already arms _aim_fire_pending synchronously (QA-027).
	g._update_touch_state()


func _ft_release_aim() -> void:
	g._on_touch_release(911)
	_ft_fire_owns_aim = false


func _ft_press_fire() -> void:
	if not g.aim_stick.is_active():
		_ft_fire_owns_aim = true
		g._on_touch_press(911, _ft_aim_center() + Vector2(60, 0))
		g._update_touch_state()


func _ft_release_fire() -> void:
	if _ft_fire_owns_aim:
		g._on_touch_release(911)
		_ft_fire_owns_aim = false


func _ft_set_weapon(id: int) -> void:
	var lp = _ft_lp()
	lp.weapon = id
	lp.mag_ammo = int(lp.WEAPONS[id]["mag"])
	lp.reloading = false
	# QA-104/105/106 (v3.8): each fire-test step runs its own
	# weapon in isolation, so the trigger must start ready. The
	# shared _fire_cooldown survives this direct assignment, and
	# the new slow weapons before BULLET-INSIDE (rocket 1.0 s,
	# sniper 0.9 s) left it running — the pistol was still on
	# cooldown at the 0.3 s check and never fired (33/35 in the
	# first v3.8 suite run). The real switch path
	# (player.switch_weapon) keeps its own cooldown; only the
	# harness resets it here.
	lp._fire_cooldown = 0.0
	lp._update_gun_texture()


func _ft_teleport(pos: Vector2) -> void:
	var lp = _ft_lp()
	lp.position = pos
	lp.sync_position = pos
	lp.velocity = Vector2.ZERO


func _ft_count_bullets(owner_id: int, kind: int = -1) -> int:
	var n := 0
	for b in g.bullets_node.get_children():
		if b.active and int(b.owner_id) == owner_id and (kind < 0 or int(b.kind) == kind):
			n += 1
	return n


func _ft_s_noop() -> void:
	pass


func _ft_s_move_alone() -> void:
	_fire_shots_before = _ft_lp()._shots_fired
	_fire_pos_before = _ft_lp().position
	_ft_press_move(Vector2(60, 0))


func _ft_c_move_alone() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired == _fire_shots_before and not g.touch_firing and lp.position.x > _fire_pos_before.x + 100.0
	_ft_release_move()
	return [ok, "shots=%d (was %d) firing=%s x=%d (was %d)" % [lp._shots_fired, _fire_shots_before, g.touch_firing, round(lp.position.x), round(_fire_pos_before.x)]]


func _ft_s_aim_alone() -> void:
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_aim(Vector2(42, -42))


func _ft_c_aim_alone() -> Array:
	# v3.2: the aim stick IS the fire control — deflecting it fires.
	# A (42,-42) push must aim up-right AND shoot.
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and g.touch_firing and absf(lp.aim_angle + PI * 0.25) < 0.35
	_ft_release_aim()
	return [ok, "shots=%d (was %d) firing=%s aim_angle=%.2f" % [lp._shots_fired, _fire_shots_before, g.touch_firing, lp.aim_angle]]


func _ft_s_grenade_alone() -> void:
	_fire_shots_before = _ft_lp()._shots_fired
	_fire_grenades_before = _ft_lp().grenades
	# Tap the GRENADE button's centre through the touch router.
	g._on_touch_press(913, g.grenade_button.get_global_rect().get_center())


func _ft_c_grenade_alone() -> Array:
	var lp = _ft_lp()
	# QA-023: a GRENADE tap must never grab a stick or fire the gun.
	var ok: bool = lp._shots_fired == _fire_shots_before and not g.touch_firing and not g.move_stick.is_active() and not g.aim_stick.is_active()
	g._on_touch_release(913)
	# The button handler itself still works: one grenade thrown.
	g._on_grenade_pressed()
	ok = ok and lp.grenades == _fire_grenades_before - 1
	return [ok, "shots=%d (was %d) firing=%s sticks_active=%s/%s grenades=%d (was %d)" % [lp._shots_fired, _fire_shots_before, g.touch_firing, g.move_stick.is_active(), g.aim_stick.is_active(), lp.grenades, _fire_grenades_before]]


func _ft_s_weapon_alone() -> void:
	var lp = _ft_lp()
	lp.give_pickup(1) # own the SMG so switching does something
	_fire_shots_before = lp._shots_fired
	_fire_weapon_before = lp.weapon
	g._on_touch_press(914, g.switch_button.get_global_rect().get_center())


func _ft_c_weapon_alone() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired == _fire_shots_before and not g.touch_firing and not g.move_stick.is_active() and not g.aim_stick.is_active()
	g._on_touch_release(914)
	g._on_switch_pressed()
	ok = ok and lp.weapon != _fire_weapon_before
	return [ok, "shots=%d (was %d) firing=%s weapon=%d (was %d)" % [lp._shots_fired, _fire_shots_before, g.touch_firing, lp.weapon, _fire_weapon_before]]


func _ft_s_pistol_tap() -> void:
	_ft_set_weapon(5)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_pistol_tap() -> Array:
	var lp = _ft_lp()
	# Semi-auto: one press = exactly one shot, even held for 0.4 s.
	var ok: bool = lp._shots_fired == _fire_shots_before + 1
	_ft_release_fire()
	return [ok, "shots=%d (was %d, want +1)" % [lp._shots_fired, _fire_shots_before]]


func _ft_s_ten_taps() -> void:
	# T-33: 10 rapid taps. The tap driver (in _update_firetest)
	# performs the press/release pairs; the pistol's 0.22 s rate is
	# respected by the 0.35 s press-to-press spacing, so every tap
	# is a separate trigger pull. Mag refilled by _ft_set_weapon.
	_ft_set_weapon(5)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_tap_left = 10
	_ft_tap_phase = 0
	_ft_tap_timer = 0.0


func _ft_c_ten_taps() -> Array:
	var lp = _ft_lp()
	var n: int = lp._shots_fired - _fire_shots_before
	var ok: bool = n == 10
	return [ok, "shots fired for 10 rapid taps: %d (want 10)" % n]


func _ft_s_fire_hold() -> void:
	_ft_set_weapon(0)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_fire_hold() -> Array:
	var lp = _ft_lp()
	var n: int = lp._shots_fired - _fire_shots_before
	# QA-141: rifle rate 0.10 s (reference AK47, was 0.125): 2.5 s of
	# holding should fire ~25 shots (mag is 35 now, so no reload
	# interrupts the hold).
	var ok: bool = n >= 18 and n <= 28
	_ft_release_fire()
	return [ok, "shots fired in 2.5 s hold: %d (want 18-28)" % n]


func _ft_s_fire_moving() -> void:
	_ft_set_weapon(0)
	# QA-030: the floor now has solid cover — teleport to a clear
	# stretch (spawn, with 300 px of open floor ahead) so the movement
	# check measures running, not being blocked by a column.
	var lp = _ft_lp()
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_fire_shots_before = _ft_lp()._shots_fired
	_fire_pos_before = _ft_lp().position
	_ft_press_move(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_fire_moving() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.position.x > _fire_pos_before.x + 100.0
	_ft_release_move()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) x=%d (was %d)" % [lp._shots_fired, _fire_shots_before, round(lp.position.x), round(_fire_pos_before.x)]]


func _ft_s_fire_diagonal() -> void:
	_ft_set_weapon(0)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_aim(Vector2(42, -42))
	_ft_press_fire()


func _ft_c_fire_diagonal() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and absf(lp.aim_angle + PI * 0.25) < 0.35
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) aim_angle=%.2f (want ~-0.79)" % [lp._shots_fired, _fire_shots_before, lp.aim_angle]]


func _ft_s_fire_jetpack() -> void:
	_ft_set_weapon(0)
	_ft_teleport(Vector2(2100, 1350))
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_move(Vector2(0, -60))
	_ft_press_fire()


func _ft_c_fire_jetpack() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.fuel < PhysicsConfig.FUEL_MAX
	_ft_release_move()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) fuel=%d jetpacking=%s" % [lp._shots_fired, _fire_shots_before, round(lp.fuel), lp._jetpacking]]


func _ft_s_fire_jump() -> void:
	_ft_set_weapon(0)
	# Open sky above (2100, 1350) — see _jt_s_diag_up_right.
	_ft_teleport(Vector2(2100, 1350))
	_fire_shots_before = _ft_lp()._shots_fired
	# The previous step released the move stick; the release and this
	# press can land in two _process calls with no physics frame
	# between them, so the player would never see the stick drop and
	# the jump edge would not arm. Re-arm it here (test-only).
	var lp = _ft_lp()
	lp._stick_up_armed = true
	lp._stick_up_prev = false
	_ft_press_move(Vector2(0, -55))
	_ft_press_fire()


func _ft_c_fire_jump() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and not lp.is_on_floor()
	_ft_release_move()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) on_floor=%s y=%d" % [lp._shots_fired, _fire_shots_before, lp.is_on_floor(), round(lp.position.y)]]


func _ft_s_switch_setup() -> void:
	# Start on the pistol (semi-auto): switching while FIRE is held
	# lands on the SMG (automatic), which must keep firing. Switching
	# onto a semi-auto weapon would correctly need a fresh tap.
	_ft_set_weapon(5)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_switch_setup() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before
	return [ok, "shots=%d (was %d) firing while held" % [lp._shots_fired, _fire_shots_before]]


func _ft_s_switch_mid() -> void:
	var lp = _ft_lp()
	_fire_shots_before = lp._shots_fired
	_fire_weapon_before = lp.weapon
	lp.switch_weapon()


func _ft_c_switch_mid() -> Array:
	var lp = _ft_lp()
	# Still holding FIRE: the new weapon keeps shooting.
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.weapon != _fire_weapon_before
	_ft_release_fire()
	return [ok, "shots=%d (was %d) weapon=%d (was %d)" % [lp._shots_fired, _fire_shots_before, lp.weapon, _fire_weapon_before]]


func _ft_s_empty_mag() -> void:
	var lp = _ft_lp()
	lp.mag_ammo = 0
	lp.reloading = false
	_fire_shots_before = lp._shots_fired
	_ft_press_fire()


func _ft_c_empty_mag() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired == _fire_shots_before and lp.reloading
	_ft_release_fire()
	return [ok, "shots=%d (was %d) reloading=%s mag=%d" % [lp._shots_fired, _fire_shots_before, lp.reloading, lp.mag_ammo]]


func _ft_c_reload_done() -> Array:
	var lp = _ft_lp()
	var ok: bool = not lp.reloading and lp.mag_ammo == int(lp.WEAPONS[lp.weapon]["mag"])
	return [ok, "reloading=%s mag=%d (want %d)" % [lp.reloading, lp.mag_ammo, int(lp.WEAPONS[lp.weapon]["mag"])]]


func _ft_s_reload_moving() -> void:
	var lp = _ft_lp()
	# QA-143: teleport to a clear stretch (spawn, with 300 px of
	# open floor ahead) like FIRE-WHILE-MOVING — the setup used to
	# rely on wherever the previous step left the player, and the
	# Outpost rebuild now leaves it at x1928, 35 px short of the
	# solid column at x2000, so the move check measured being
	# blocked by the column instead of running.
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	lp.mag_ammo = 10
	lp.reloading = false
	_fire_pos_before = lp.position
	_ft_press_move(Vector2(60, 0))
	g._on_reload_pressed()


func _ft_c_reload_moving() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp.position.x > _fire_pos_before.x + 50.0 and lp.reloading
	_ft_release_move()
	return [ok, "x=%d (was %d) reloading=%s progress=%d%%" % [round(lp.position.x), round(_fire_pos_before.x), lp.reloading, int(lp.reload_progress() * 100.0)]]


func _ft_s_three_fingers() -> void:
	_ft_set_weapon(0)
	# QA-030: same as FIRE-WHILE-MOVING — clear stretch of floor so
	# the movement check is not blocked by solid cover.
	var lp = _ft_lp()
	lp.position = Vector2(300, 1318) # QA-071: floor 1352, centre top-34
	lp.sync_position = lp.position
	lp.velocity = Vector2.ZERO
	_fire_shots_before = _ft_lp()._shots_fired
	_fire_pos_before = _ft_lp().position
	_ft_press_move(Vector2(60, 0))
	_ft_press_aim(Vector2(42, -42))
	_ft_press_fire()


func _ft_c_three_fingers() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and lp.position.x > _fire_pos_before.x + 100.0 and absf(lp.aim_angle + PI * 0.25) < 0.35
	_ft_release_move()
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "shots=%d (was %d) x=%d (was %d) aim=%.2f" % [lp._shots_fired, _fire_shots_before, round(lp.position.x), round(_fire_pos_before.x), lp.aim_angle]]


func _ft_s_grenade_firing_a() -> void:
	_ft_set_weapon(0)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_grenade_firing_a() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and g.touch_firing
	return [ok, "shots=%d (was %d) firing=%s" % [lp._shots_fired, _fire_shots_before, g.touch_firing]]


func _ft_s_grenade_firing_b() -> void:
	var lp = _ft_lp()
	_fire_shots_before = lp._shots_fired
	_fire_grenades_before = lp.grenades
	g._on_grenade_pressed()


func _ft_c_grenade_firing_b() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp.grenades == _fire_grenades_before - 1 and lp._shots_fired > _fire_shots_before and g.touch_firing
	_ft_release_fire()
	return [ok, "grenades=%d (was %d) shots=%d (was %d) still firing=%s" % [lp.grenades, _fire_grenades_before, lp._shots_fired, _fire_shots_before, g.touch_firing]]


func _ft_s_slide_off_a() -> void:
	_ft_set_weapon(0)
	_fire_shots_before = _ft_lp()._shots_fired
	_ft_press_fire()


func _ft_c_slide_off_a() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp._shots_fired > _fire_shots_before and g.touch_firing
	return [ok, "shots=%d (was %d) firing=%s" % [lp._shots_fired, _fire_shots_before, g.touch_firing]]


func _ft_s_slide_off_b() -> void:
	# v3.2: unlike the old FIRE button, sliding the aim finger off
	# the stick base does NOT stop firing — the knob clamps at the
	# radius and the deflection persists (reference behaviour).
	# Only releasing the stick stops the shooting.
	g._on_touch_drag(911, _ft_aim_center() + Vector2(300, 0))
	# QA-029: refresh the touch state NOW, then capture the baseline,
	# so no physics step after the drag can see a stale value.
	g._update_touch_state()
	_fire_shots_before = _ft_lp()._shots_fired


func _ft_c_slide_off_b() -> Array:
	var lp = _ft_lp()
	var ok: bool = g.touch_firing and g.aim_stick.is_active() and lp._shots_fired > _fire_shots_before
	g._on_touch_release(911)
	_ft_fire_owns_aim = false
	return [ok, "firing=%s aim_active=%s shots=%d (was %d)" % [g.touch_firing, g.aim_stick.is_active(), lp._shots_fired, _fire_shots_before]]


func _ft_layout_ok() -> Array:
	# No two HUD controls may overlap, and all must be inside the viewport.
	var ctrls: Array = [g.move_stick, g.aim_stick, g.grenade_button, g.switch_button, g.reload_button, g.pause_button, g.score_button]
	var vp = g.get_viewport().get_visible_rect().size
	for i in ctrls.size():
		var r1: Rect2 = (ctrls[i] as Control).get_global_rect()
		if not Rect2(Vector2.ZERO, vp).encloses(r1):
			return [false, "%s rect %s outside viewport %s" % [(ctrls[i] as Control).name, r1, vp]]
		for j in range(i + 1, ctrls.size()):
			var r2: Rect2 = (ctrls[j] as Control).get_global_rect()
			if r1.intersects(r2):
				return [false, "%s overlaps %s (%s vs %s)" % [(ctrls[i] as Control).name, (ctrls[j] as Control).name, r1, r2]]
	return [true, "7 controls, no overlaps, all inside %s" % vp]


func _ft_c_layout_1280() -> Array:
	return _ft_layout_ok()


func _ft_s_layout_1920() -> void:
	g.get_window().size = Vector2(1920, 1080)


func _ft_c_layout_1920() -> Array:
	var res: Array = _ft_layout_ok()
	if not bool(res[0]):
		g.get_window().size = Vector2(1280, 720)
		return res
	# QA-023 regression at a non-identity stretch transform: a real
	# touch at the GRENADE button's PHYSICAL position (viewport pixels)
	# must not grab a stick or fire — the router converts it to canvas
	# space first, so the fallback rect check hits.
	var phys = g._to_viewport_pos(g.grenade_button.get_global_rect().get_center())
	var ev := InputEventScreenTouch.new()
	ev.index = 915
	ev.pressed = true
	ev.position = phys
	g._unhandled_input(ev)
	var shots_before: int = _ft_lp()._shots_fired
	var ok: bool = not g.move_stick.is_active() and not g.aim_stick.is_active() and not g.touch_firing and _ft_lp()._shots_fired == shots_before
	ev = InputEventScreenTouch.new()
	ev.index = 915
	ev.pressed = false
	ev.position = phys
	g._unhandled_input(ev)
	g.get_window().size = Vector2(1280, 720)
	return [ok, "layout ok at 1920x1080; physical grenade tap: sticks=%s/%s fire=%s shots stable — %s" % [g.move_stick.is_active(), g.aim_stick.is_active(), g.touch_firing, res[1]]]


func _ft_c_mp_sync() -> Array:
	# Server-side validation (host = this process): a first shot is
	# accepted, an immediate second is too fast, an empty magazine
	# is rejected.
	var v1: bool = g.shooting_sync.validate_shot(99, 0, 30)
	var v2: bool = g.shooting_sync.validate_shot(99, 0, 30)
	var v3: bool = g.shooting_sync.validate_shot(98, 0, 0)
	var ok: bool = v1 and not v2 and not v3
	g.shooting_sync.reset_peer(99)
	g.shooting_sync.reset_peer(98)
	return [ok, "validate: first=%s second-too-fast=%s empty-mag=%s" % [v1, v2, v3]]


func _ft_s_single_bullet() -> void:
	# One pistol shot (semi-auto) must create exactly one bullet.
	# QA-030: the player's own grenades (thrown earlier in this test)
	# now bounce off solid cover and can explode at point-blank range,
	# so the player may be dead or nearly dead here — revive + heal so
	# the bullet count measures shooting, not grenade damage.
	var lp0 = _ft_lp()
	if not lp0.alive:
		lp0._respawn()
	lp0.health = 100
	_ft_set_weapon(5)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(0, -60))
	_ft_press_fire()


func _ft_c_single_bullet() -> Array:
	var lp = _ft_lp()
	var n := _ft_count_bullets(lp.peer_id, 5)
	var any_n := _ft_count_bullets(lp.peer_id)
	var ok: bool = n == 1
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "active pistol bullets: %d (want 1), any-kind active: %d, shots=%d mag=%d reloading=%s" % [n, any_n, lp._shots_fired, lp.mag_ammo, lp.reloading]]


func _ft_s_pellets() -> void:
	# One shotgun shot must create exactly six pellets.
	# QA-030: same revive + heal as the single-bullet test — the
	# player must be alive and healthy to shoot.
	var lp0 = _ft_lp()
	if not lp0.alive:
		lp0._respawn()
	lp0.health = 100
	_ft_set_weapon(2)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(0, -60))
	_ft_press_fire()


func _ft_c_pellets() -> Array:
	var lp = _ft_lp()
	var n := _ft_count_bullets(lp.peer_id, 2)
	# QA-141: reference SPAS-12 fires 6 pellets (builder idx 9, rounds 6),
	# not 7 — the old "want 7, GAP-20 spec §9" encoded the pre-reference
	# table. The setup comment already said six; the check now
	# agrees with it and with the reference.
	var ok: bool = n == 6
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "active shotgun pellets from one shot: %d (want 6, reference SPAS-12)" % n]


# QA-061: the Assault Rifle must fire STRAIGHT — hold the trigger
# for a full 2.5 s (25 shots at the 0.10 s rate) and every bullet's
# recorded direction deviation from the aim must stay inside the
# reference spread. QA-141: reference AK47 has ±4° LCG spread (was 0° — the
# old <0.5° bound encoded the pre-reference straight rifle), so the bound
# is 4.5°, not 0.5°. Recoil growth is still excluded for the rifle
# (QA-061 guard), so the spread is the table value only. The step
# runs last so _recoil_accum is already high from the earlier
# firing steps — the worst case, not a fresh gun.
func _ft_s_rifle_straight() -> void:
	var lp = _ft_lp()
	_ft_set_weapon(0)
	_ft_rifle_dev_start = lp.shot_devs.size()
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_rifle_straight() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var total: int = int(lp.shot_devs.size())
	var start: int = mini(_ft_rifle_dev_start, total)
	var n: int = total - start
	var max_dev := 0.0
	for i in range(start, total):
		max_dev = maxf(max_dev, absf(float(lp.shot_devs[i])))
	var max_deg := rad_to_deg(max_dev)
	var ok: bool = n >= 10 and max_deg < 4.5
	return [ok, "rifle shots in hold=%d max deviation=%.2f° (want >=10 shots, <4.5° — reference AK47 ±4° LCG)" % [n, max_deg]]


# QA-104 (v3.8): the SMG must group tightly — base spread 0.035
# rad + recoil_k 0.015 (was 0.09 + 0.04, "bullets spray
# everywhere"). QA-141: reference MP5 base spread is 0.087 rad (±5°),
# and the recoil growth (recoil_k 0.015, kept) adds up to ~0.08
# rad over a 0.7 s burst, so the bound is 0.20 rad (was 0.15).
# Fire a ~0.7 s burst from a reset recoil state and every bullet's
# deviation from the aim must stay under 0.20 rad.
func _ft_s_smg_spread() -> void:
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(1)
	lp._recoil_accum = 0.0
	_ft_smg_dev_start = lp.shot_devs.size()
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_smg_spread() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var total: int = int(lp.shot_devs.size())
	var start: int = mini(_ft_smg_dev_start, total)
	var n: int = total - start
	var max_dev := 0.0
	for i in range(start, total):
		max_dev = maxf(max_dev, absf(float(lp.shot_devs[i])))
	var ok: bool = n >= 5 and max_dev < 0.20
	return [ok, "smg burst shots=%d max deviation=%.3f rad (want >=5 shots, <0.20 rad — reference MP5 ±5° + recoil)" % [n, max_dev]]


# QA-106 (v3.8): the rocket must fly straight along the aim
# direction — gravity 0, no velocity inheritance. Fire it
# horizontally and after 0.5 s its velocity must still point
# exactly right with no downward component (with the old gravity
# 500 the rocket would have vy = +250 by then).
func _ft_s_rocket_straight() -> void:
	var lp0 = _ft_lp()
	if not lp0.alive:
		lp0._respawn()
	lp0.health = 100
	_ft_set_weapon(4)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_rocket_straight() -> Array:
	var lp = _ft_lp()
	var rocket = null
	for b in g.bullets_node.get_children():
		if b.active and int(b.owner_id) == lp.peer_id and int(b.kind) == 4:
			rocket = b
			break
	var ok := false
	var detail := "no active rocket found"
	if rocket != null:
		var ang := absf(float(rocket.velocity.angle()))
		var vy := absf(float(rocket.velocity.y))
		ok = ang < 0.02 and vy < 5.0 and float(rocket.grav) == 0.0
		detail = "rocket angle=%.3f rad vy=%.1f grav=%.0f (want ~0 / ~0 / 0)" % [ang, vy, float(rocket.grav)]
	_ft_release_aim()
	_ft_release_fire()
	return [ok, detail]


# QA-105 (v3.8): aiming the sniper shows the sight line. QA-143:
# scoping was removed, so this now checks the camera stays at 1.0x
# (no zoom) and the sight line shows after 0.8 s.
func _ft_s_sniper_scope() -> void:
	var lp0 = _ft_lp()
	if not lp0.alive:
		lp0._respawn()
	lp0.health = 100
	_ft_set_weapon(3)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(60, 0))


func _ft_c_sniper_scope() -> Array:
	var lp = _ft_lp()
	var zoom := float(lp._camera.zoom.x) if lp._camera != null else 0.0
	var line_ok := lp._sight_line != null and bool(lp._sight_line.visible)
	var ok := zoom < 1.05 and line_ok
	_ft_release_aim()
	_ft_release_fire()
	return [ok, "sniper zoom=%.2f sight line visible=%s (want ~1.0 / true) - QA-143: scoping removed, sight line kept" % [zoom, str(line_ok)]]


func _ft_s_bullet_inside() -> void:
	# QA-055: a bullet whose muzzle starts INSIDE solid geometry
	# (player flush against a wall, aiming into it) must impact at
	# once, not fly through the wall. Muzzle = player pos +
	# hand-anchor offset + dir * muzzle_distance: the shoot anchor
	# is x=11 (QA-145 new sheet, x1.20 scale = 13.2) and the pistol
	# muzzle_distance is 43.7 (QA-143 reference firing point), so
	# standing at x=63 aiming left puts the muzzle at
	# 63 - 13.2 - 43.7 = 6.1, ~6 px inside the 24 px left boundary
	# wall — the same margin the old x=56 setup had with the old
	# anchor x=5 (56 - 6.0 - 43.7 = 6.3). Do NOT move the teleport
	# back to 56: with the new anchor the muzzle would sit at -0.9,
	# past the wall's outer face, and the bullet would (correctly)
	# spawn past the wall instead of impacting it.
	# The left wall is used because the right wall has sandbags at
	# x=3120 on the fire-test map (map 0).
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(5) # pistol: semi-auto, exactly one bullet
	var floor_top = float((g.MAPS[g.map_id]["platforms"] as Array)[0].position.y)
	_ft_teleport(Vector2(63.0, floor_top - 43.0))
	_ft_inside_shots0 = lp._shots_fired
	# Bullets from earlier steps may still be flying: remember them
	# so the check counts only the bullet fired in this step. (The
	# pool never reuses a node that is active, so the new bullet's
	# node cannot be in this set.)
	_ft_inside_old = []
	for b in g.bullets_node.get_children():
		if b.active:
			_ft_inside_old.append(b.get_instance_id())
	_ft_press_aim(Vector2(-60, 0))


func _ft_c_bullet_inside() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var fired: int = int(lp._shots_fired) - _ft_inside_shots0
	# Only bullets spawned in this step count: earlier steps leave
	# strays flying. A bullet that flew through the wall would
	# still be alive at 0.3 s (lifetime ~1.5 s) and past x=0.
	var active := 0
	var past_wall := false
	for b in g.bullets_node.get_children():
		if b.active and not _ft_inside_old.has(b.get_instance_id()):
			active += 1
			if b.global_position.x < 0.0:
				past_wall = true
	var ok: bool = fired == 1 and active == 0 and not past_wall
	return [ok, "fired=%d (want 1), new active bullets=%d (want 0), past wall=%s" % [fired, active, str(past_wall)]]


func _ft_s_bullet_size() -> void:
	# QA-056: bullets are 20% smaller (visual 80% of v3.3) — assert
	# the polygon extents in the test, not just in code. One pistol
	# shot into open sky (1500, 300), aim right; the bullet is still
	# flying at the 0.15 s check.
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(5)
	_ft_teleport(Vector2(1500, 300))
	_ft_press_aim(Vector2(60, 0))


func _ft_c_bullet_size() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var half_len := -1.0
	var half_w := -1.0
	var trail_w := -1.0
	for b in g.bullets_node.get_children():
		if b.active and int(b.owner_id) == lp.peer_id and int(b.kind) == 5:
			var poly: PackedVector2Array = b._visual.polygon
			for p in poly:
				half_len = maxf(half_len, absf(p.x))
				half_w = maxf(half_w, absf(p.y))
			trail_w = b._trail.width
			break
	# v3.3 was 14.0 x 3.0 (trail 3.0); v3.5 QA-056 is 80%: 11.2 x 2.4.
	var ok: bool = half_len > 0.0 and absf(half_len - 11.2) < 0.15 and absf(half_w - 2.4) < 0.15 and absf(trail_w - 2.4) < 0.05
	return [ok, "pistol bullet half-length=%.2f (want 11.2), half-width=%.2f (want 2.4), trail=%.2f (want 2.4)" % [half_len, half_w, trail_w]]


# QA-075: switching weapons must remember each weapon's magazine
# (the old code refilled the mag on every switch, so switching
# away and back refilled the rifle for free). Fire the rifle down
# to 17, then switch through every owned weapon until the rifle
# comes round again: it must still hold 17, not a fresh 30. The
# loop (not two fixed switches) is deliberate: earlier fire steps
# may have picked up extra weapons on the map, so the cycle length
# is not always 2 — the owned list is [rifle, pistol] plus any
# pickups, in that order.
func _ft_s_mag_memory() -> void:
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(0)
	lp.mag_ammo = 17
	for i in 6:
		g._on_switch_pressed()
		if lp.weapon == 0 and i > 0:
			break


func _ft_c_mag_memory() -> Array:
	var lp = _ft_lp()
	var ok: bool = lp.weapon == 0 and lp.mag_ammo == 17
	return [ok, "weapon=%d mag=%d after cycling back to the rifle (want weapon 0, mag 17 — the remembered mag, not a refill to 30)" % [lp.weapon, lp.mag_ammo]]


# QA-075: switching mid-reload must not eat the ammo. Start a rifle
# reload with 10 in the mag (20 move from the reserve into the
# pending transfer), then switch before it finishes: the 20 must
# come back to the reserve (90 again), the rifle must remember its
# 10, and the player must not be stuck reloading.
func _ft_s_reload_refund() -> void:
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(0)
	lp._reserve[0] = 90
	lp.mag_ammo = 10
	lp.reloading = false
	g._on_reload_pressed() # transfer 20, reserve 90 -> 70
	g._on_switch_pressed() # -> pistol: refund 20, reserve back to 90


func _ft_c_reload_refund() -> Array:
	var lp = _ft_lp()
	var res: int = int(lp._reserve.get(0, -1))
	var mem: int = int(lp._mag_memory.get(0, -1))
	var ok: bool = lp.weapon == 5 and not lp.reloading and res == 90 and mem == 10
	return [ok, "weapon=%d reloading=%s rifle reserve=%d (want 90, refunded) rifle remembered mag=%d (want 10)" % [lp.weapon, lp.reloading, res, mem]]


# QA-075: the muzzle flash must fire on every shot, bigger on heavy
# weapons. Hold the rifle trigger for 0.3 s (2+ shots at the 0.125 s
# rate): the flash counter must grow, and the flash sprite scale
# must be the rifle's 1.2x (with the +/-10% per-shot jitter).
func _ft_s_muzzle_flash() -> void:
	var lp = _ft_lp()
	if not lp.alive:
		lp._respawn()
	lp.health = 100
	_ft_set_weapon(0)
	_fire_flashes_before = lp._muzzle_flashes
	_ft_press_aim(Vector2(60, 0))
	_ft_press_fire()


func _ft_c_muzzle_flash() -> Array:
	var lp = _ft_lp()
	_ft_release_aim()
	_ft_release_fire()
	var scale: float = lp._muzzle.scale.x if lp._muzzle != null else -1.0
	var ok: bool = lp._muzzle_flashes > _fire_flashes_before and scale > 1.05 and scale < 1.35
	return [ok, "muzzle flashes=%d (was %d) scale=%.2f (want rifle 1.2x, 1.05-1.35 with jitter)" % [lp._muzzle_flashes, _fire_flashes_before, scale]]

