class_name PlayerMovement
extends RefCounted


# QA-140 (v3.15): extracted from player/player.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `p` (dependency injection).
#
# NOTE: LifeState mirrors player.gd's enum (same order/values: ALIVE 0,
# DYING 1, DEAD 2, RESPAWNING 3). Enum values are NOT reachable through
# an instance (`p.ALIVE` is a runtime error), so this module defines
# the enum itself; keep the order in sync with player.gd.
enum LifeState { ALIVE, DYING, DEAD, RESPAWNING }


var p # the owner (player/player.gd)

const SPEED_BOOST_MULT := 1.5 # QA-132: was 1.3 — barely noticeable
const JETPACK_BOOST_MULT := 1.4
const FLAG_CARRY_SPEED_MULT := 0.85



func _init(owner) -> void:
	p = owner


func _physics_process(delta: float) -> void:
	p.player_movetest._movetest_pre_tick(delta) # QA-112: --movement-test step machine (no-op without the flag)
	p._spawn_protect_timer = maxf(0.0, p._spawn_protect_timer - delta)
	p._shake_trauma = maxf(0.0, p._shake_trauma - delta * 1.8)
	p._gun_kick = maxf(0.0, p._gun_kick - delta * 7.0)
	p._tick_boost_timers(delta) # QA-112: Skyfall power-up timers
	p._tick_health_regen(delta) # QA-120: slow health regen after 3 s without damage
	# Recoil accumulation decays when not firing (spec §16).
	if not p._want_fire:
		p._recoil_accum *= exp(-3.0 * delta)
		if p._recoil_accum < 0.001:
			p._recoil_accum = 0.0
	var game = p.get_tree().get_first_node_in_group("game")
	if game != null and game.match_over:
		# Match over: stand still, idle animation only.
		p.velocity = Vector2.ZERO
		if p.alive:
			p._play_anim("idle")
		return
	if p.life_state != LifeState.ALIVE:
		if p.is_local_player():
			# Death FSM: DYING (0.4 s anim window) -> DEAD, then the
			# respawn timer runs; RESPAWNING retries validation.
			if p.life_state == LifeState.DYING:
				p._dying_timer -= delta
				if p._dying_timer <= 0.0:
					p.life_state = LifeState.DEAD
			elif p.life_state == LifeState.RESPAWNING:
				p._respawn_retry_timer -= delta
				if p._respawn_retry_timer <= 0.0:
					p._respawn()
			else:
				# Last Man Standing: one life, no respawn. Survival: no
				# respawn until the host resets the round.
				var game3 = p.get_tree().get_first_node_in_group("game")
				var mode3: int = int(game3.game_mode) if game3 != null else 0
				if mode3 != 3 and not (mode3 == 2 and p._round_dead):
					p._respawn_timer -= delta
					if p._respawn_timer <= 0.0:
						p._respawn()
		else:
			# QA-069: a remote copy never runs _apply_damage (damage
			# RPCs go only to the victim's owning peer), so it never
			# played "die" - the body kept its last run/idle loop
			# with no gun, name or HP bar. Play the death pose here,
			# from the synced life_state, so every peer sees the
			# same death. _play_anim("die") is a no-op once playing.
			p._play_anim("die")
		return
	if p.is_local_player():
		_read_input()
		p.player_movetest._movetest_apply_input() # QA-112: --movement-test input overrides (no-op without the flag)
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
		if p._reconcile_active:
			var rdist = p.position.distance_to(p._reconcile_target)
			if rdist < 2.0:
				p._reconcile_active = false
			else:
				p.position = p.position.move_toward(p._reconcile_target, maxf(rdist * 0.2, 60.0 * delta))
		_update_ladder() # QA-112: Skyfall ladder grab / release, before movement
		_update_grapple(delta) # QA-112: Skyfall grapple attach / release, before movement
		_apply_movement(delta)
		p.player_weapons._apply_aim_and_fire(delta)
		# the local simulation predicted each physics frame, so a
		# correction can be checked against the prediction ring.
		# Packed arrays, capped at 90 frames (~1.5 s), no dicts.
		p._pred_pos.append(p.position)
		p._pred_vel.append(p.velocity)
		p._pred_seq.append(p._move_snap_seq)
		while p._pred_pos.size() > 90:
			p._pred_pos.remove_at(0)
			p._pred_vel.remove_at(0)
			p._pred_seq.remove_at(0)
		_check_stuck(delta)
		# QA-053: snapshots at the spec rate (30/s) - the owner's
		# only channel out. Force-send is used by _respawn /
		# _check_stuck after a teleport so the remote copy never
		# waits a full interval to learn the new position.
		# QA-068: subtract the interval instead of resetting to 0,
		# so the 30/s cadence stays steady under variable frame
		# times instead of drifting a little later every tick.
		p._move_snap_timer += delta
		if p._move_snap_timer >= PhysicsConfig.SNAPSHOT_INTERVAL:
			p._move_snap_timer -= PhysicsConfig.SNAPSHOT_INTERVAL
			p.player_sync._send_move_snapshot()
	else:
		# Remote players: reference-style render (QA-146, spec §21.D) —
		# chase the NEWEST snapshot every frame with the reference's
		# exponential smoothing (see below), on the SENDER's
		# timeline (QA-068). Position is owned ONLY by this buffer
		# - no second channel writes it. Velocity is smoothed
		# toward the latest snapshot (was: snapped instantly) so
		# the remote run/jetpack animation stops flickering on
		# jitter.
		var now := Time.get_ticks_msec() / 1000.0
		var target = p.player_sync._interp_position(now)
		var dist = p.position.distance_to(target)
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
		if dist > 600.0 or (p._snap_resync and dist > 100.0):
			p.position = target
		else:
			# QA-146 (reference port): exponential smoothing toward the
			# newest target — factor = max(0.05, 0.3745 - 15.0*dt)
			# (SoldierRemoteController::updateStep 0x8f3bf8; consts
			# in PhysicsConfig) — ~0.125 per physics frame at
			# 60 fps, floor 0.05. This REPLACES the old per-frame
			# step clamp (700 px/s + 20 px slack): reference has no such
			# clamp, and the clamp let the copy chase a stale
			# delayed target at full speed instead of easing onto
			# the newest one. A genuine teleport (respawn /
			# stuck-recovery, >600 px) or a re-placement after a
			# join / long gap (>100 px, QA-073) still snaps at
			# once, or the copy would swim across the map.
			var smooth_f := clampf(maxf(PhysicsConfig.REMOTE_SMOOTH_MIN, PhysicsConfig.REMOTE_SMOOTH_BASE - PhysicsConfig.REMOTE_SMOOTH_RATE * delta), 0.0, 1.0)
			p.position += (target - p.position) * smooth_f
		p._snap_resync = false
		p.velocity = p.velocity.lerp(p.sync_velocity, clampf(delta * 10.0, 0.0, 1.0))
		p._update_remote_anim()
		# QA-135: Wind Blast tornado sweep for a copy with NO live
		# peer (a test bot / fake peer in the sim — the owning peer
		# is not here to run _apply_movement, so this copy steers
		# itself). Real remote copies always have snapshots from
		# the owning peer and never reach this (their
		# _wind_sweep_timer is never set — the RPC goes to the
		# owning peer only). sync_position is kept equal to the
		# position so the interpolation above never fights the
		# sweep. The throw is held 0.5 s, then the copy falls on
		# gravity for up to 1 s (no floor collision on a remote
		# copy — the throw is verified by the fall distance).
		if p._snapshots.is_empty() and (p._wind_sweep_timer > 0.0 or p._wind_throw_timer > 0.0 or p._wind_fall_timer > 0.0):
			if p._wind_sweep_timer > 0.0:
				p._wind_sweep_timer -= delta
				var to_c3: Vector2 = p._wind_sweep_center - p.position
				if to_c3.length() > 12.0:
					p.position += to_c3.normalized() * 380.0 * delta
				if p._wind_sweep_timer <= 0.0:
					p.velocity = p._wind_throw
					p._wind_throw_timer = 0.5
					p._wind_sweep_timer = 0.0
			elif p._wind_throw_timer > 0.0:
				p._wind_throw_timer -= delta
				p.velocity = p._wind_throw
				p.velocity.y += p.GRAVITY * delta
				p.position += p.velocity * delta
				if p._wind_throw_timer <= 0.0:
					p._wind_throw_timer = 0.0
					p._wind_fall_timer = 1.0
			elif p._wind_fall_timer > 0.0:
				p._wind_fall_timer -= delta
				p.velocity.y += p.GRAVITY * delta
				p.position += p.velocity * delta
				if p._wind_fall_timer <= 0.0:
					p._wind_fall_timer = 0.0
			p.sync_position = p.position
			p.sync_velocity = p.velocity


func _apply_movement(delta: float) -> void:
	# QA-141: reference movement model (SLC::updateStep 0x8e4d5c, velocity
	# function local 0x8e4604). the reference is impulse-based (Chipmunk); Frag
	# Arena is velocity-based (CharacterBody2D) — the EFFECTIVE
	# behaviour is ported: headroom accel (3.0x normal, 1.5x while
	# thrusting), full-vector damping at 0.598/s applied once per
	# physics frame BEFORE forces (reference damp-then-add order), gravity
	# 300 (50 while thrusting), no reversal bonus. Ground/air split
	# + ice zone (GAP-02/51) stay; only the numbers/model changed.
	var on_floor = p.is_on_floor()
	var game = p.get_tree().get_first_node_in_group("game")
	var on_ice := false
	if game != null and on_floor:
		on_ice = game.is_on_ice(p.global_position)
	var max_speed = p.SPEED_GROUND
	var accel = p.ACCEL_GROUND
	# QA-141: reference damping (0.598/s) is the ONLY no-input stopper now
	# (DECEL_GROUND/AIR stay defined as tuning reference only).
	# It is applied to the FULL velocity vector once per frame,
	# below, before any force — not per-axis, not twice.
	var drag = p.DRAG_GROUND
	if on_ice:
		max_speed = PhysicsConfig.ICE_MAX_SPEED
		accel = PhysicsConfig.ICE_ACCEL
		drag = PhysicsConfig.ICE_FRICTION / 1200.0 * p.DRAG_GROUND
	elif not on_floor:
		max_speed = p.SPEED_AIR
		drag = p.DRAG_AIR
	# QA-112: speed boost x1.3, flag carrier x0.85 (they stack if
	# both apply - a boosted carrier runs at 1.3 * 0.85).
	if p.speed_timer > 0.0:
		max_speed *= SPEED_BOOST_MULT
	if p.carrying_flag != 0:
		max_speed *= FLAG_CARRY_SPEED_MULT
	if p._on_ladder:
		# QA-112: ladder climb - no gravity, no jump, no jetpack.
		# Climb 200 px/s on the stick; horizontal at half speed;
		# move_and_slide still runs so platforms stop the climb.
		# The grab-frame jump edge is swallowed: pushing the stick
		# up grabs the ladder, it must not also hop the player.
		p._jump_buffer_timer = 0.0
		p._jump_cut_armed = false
		p._jet_thrust_factor = 0.0
		p._stop_jetpack_sound()
		var climb := 0.0
		if p._move_stick_y < -0.3:
			climb = -p.LADDER_CLIMB_SPEED
		elif p._move_stick_y > 0.3:
			climb = p.LADDER_CLIMB_SPEED
		p.velocity.y = climb
		p.velocity.x = move_toward(p.velocity.x, p._move_axis * max_speed * 0.5, p.ACCEL_GROUND * delta)
		p._fall_speed = p.velocity.y
		p._was_on_floor = on_floor
		p.move_and_slide()
		if p.is_on_floor():
			p._jump_cut_armed = false
		return
	if p._grappling:
		# QA-112: rope pull - velocity straight at the point at the
		# pull speed (500, 425 for a carrier), gravity at 30% so
		# the rope still sags a little. No fuel, no jetpack, no
		# jump while attached (firing is gated in
		# _apply_aim_and_fire). Arrival (within 60 px) or landing
		# ends the pull and falls through to normal movement.
		p._jetpacking = false
		p._jet_thrust_factor = 0.0
		p._stop_jetpack_sound()
		p._jump_buffer_timer = 0.0
		p._jump_cut_armed = false
		if p.is_on_floor() or p.global_position.distance_to(p._grapple_point) <= p.GRAPPLE_RELEASE_DIST:
			_release_grapple(false)
		if p._grappling:
			var dir = (p._grapple_point - p.global_position).normalized()
			p.velocity = dir * _grapple_pull_speed()
			p.velocity.y += p.GRAVITY * 0.3 * delta
			p._fall_speed = p.velocity.y
			p._was_on_floor = on_floor
			p.move_and_slide()
			return
		# Released this frame: fall through to normal movement below.
	# QA-141: reference damping — the velocity function damps the FULL
	# vector at ln(1/0.55) = 0.598/s (local 0x8e4604), once per
	# physics frame, BEFORE the forces below (reference damp-then-add
	# order). This is the only drag: the old per-axis / input-only
	# drag lines are gone, so stopping, falling and sliding all
	# share the one reference rate.
	p.velocity *= exp(-drag * delta)
	if p._move_axis != 0.0:
		# QA-141: reference headroom accel (SLC::updateStep 0x8e4d5c):
		# rate = fmov x max(0.0001, 300 - v_along), fmov 3.0
		# normal, 1.5 while thrusting. Fast when far from the
		# target, gentle near it — reversal is naturally faster
		# (big headroom) with NO reversal multiplier (reference has
		# none; REVERSAL_* are 1.0 now). _jetpacking here is last
		# frame's value: one frame of lag on the first thrust
		# frame only. Ice keeps its linear 500 accel (FA-only).
		var target_vx = p._move_axis * max_speed
		var rate: float = accel
		if not on_ice:
			var fmov := 1.5 if p._jetpacking else 3.0
			rate = fmov * maxf(0.0001, PhysicsConfig.REF_MOVE_BASE - p.velocity.x * signf(target_vx))
		p.velocity.x = move_toward(p.velocity.x, target_vx, rate * delta)
	# QA-112: jetpack-line check for this frame (Skyfall only;
	# false elsewhere). Used by the jetpack fuel drain below and
	# by the wind shield at the bottom of this function.
	p._on_jetpack_line = _is_on_jetpack_line()
	# Jump buffering + coyote time: jumping feels reliable even if the
	# button is pressed a moment before landing / after leaving a ledge.
	if p._jump_pressed:
		p._jump_buffer_timer = p.JUMP_BUFFER
	else:
		p._jump_buffer_timer = maxf(0.0, p._jump_buffer_timer - delta)
	if on_floor:
		p._coyote_timer = p.COYOTE_TIME
		p._wall_jumps_used = 0 # QA-112: touching ground resets the wall-jump chain
	else:
		p._coyote_timer = maxf(0.0, p._coyote_timer - delta)
	p._jetpacking = false
	if p._jump_buffer_timer > 0.0 and p._coyote_timer > 0.0:
		p.velocity.y = p.JUMP_VELOCITY
		p._jump_buffer_timer = 0.0
		p._coyote_timer = 0.0
		p._jump_cut_armed = true
		p._play_sound("jump")
	elif _try_wall_jump():
		# QA-112: Skyfall wall-jump fired (see _try_wall_jump) -
		# the press is eaten and the push is already applied.
		pass
	elif p._jump_held and not on_floor and p.fuel > 0.0 and p.carrying_flag == 0:
		# QA-112: a flag carrier gets NO jetpack thrust (carrier
		# rule) - the branch is skipped, so no fuel is spent either.
		# Jetpack sustains a climb, it never chops jump momentum:
		# thrust applies only while rising SLOWER than the cap, so
		# a -220 jump is not clamped down to -190 when fuel regens
		# mid-rise (air regen, GAP-05, used to do exactly that).
		# QA-141: reference jetpack (SLC::updateStep 0x8e4d5c). NO time
		# ramp — thrust scales with the stick instead:
		# thrustFactor = 0.5 + 0.5 x upInput, upInput =
		# -move_stick_y clamped 0..1. Thrust JET_ACCEL (450) x
		# factor, gravity 50 while thrusting (added below), rise
		# cap 190. Fuel drains 21/s x thrustFactor (half on a
		# Skyfall jetpack line — an FA mechanic, kept). The boost
		# (x1.4) is QA-112, kept: it spools the climb faster, the
		# cap stays 190.
		if p.velocity.y > -p.MAX_JET_RISE:
			var up_input := clampf(-p._move_stick_y, 0.0, 1.0)
			p._jet_thrust_factor = 0.5 + 0.5 * up_input
			# QA-112: jetpack boost multiplies the thrust x1.4 (the
			# rise cap MAX_JET_RISE stays 190 - the boost spools
			# the climb up faster, it does not raise the top speed).
			var thrust = p.JET_ACCEL * p._jet_thrust_factor
			if p.jetpack_boost_timer > 0.0:
				thrust *= JETPACK_BOOST_MULT
			p.velocity.y -= thrust * delta
			if p.velocity.y < -p.MAX_JET_RISE:
				p.velocity.y = -p.MAX_JET_RISE
			# QA-112: on a jetpack line the player rides the wind
			# instead of fighting it - fuel drains at HALF rate.
			# (A carrier never reaches this branch: no jetpack
			# while carrying, so no discount and no boost.)
			var drain = p.FUEL_DRAIN * p._jet_thrust_factor * (0.5 if p._on_jetpack_line else 1.0)
			p.fuel = maxf(0.0, p.fuel - drain * delta)
			p._fuel_delay_timer = p.FUEL_REGEN_DELAY
			p._jetpacking = true
			p._jump_cut_armed = false
			p._start_jetpack_sound()
		else:
			p._jet_thrust_factor = 0.0
			p._stop_jetpack_sound()
	else:
		p._jet_thrust_factor = 0.0
		p._stop_jetpack_sound()
	# Variable jump height (GAP-04, spec §4): releasing stick-up while
	# still rising cuts upward velocity. Never fires while jetpacking
	# (holding stick-up keeps _jump_held true, so no cut mid-climb).
	if p._jump_cut_armed and not p._jump_held and not p._jetpacking and p.velocity.y < 0.0:
		p.velocity.y *= PhysicsConfig.JUMP_CUT
		p._jump_cut_armed = false
	# Fuel regen (GAP-05, spec §5): after a 0.6 s delay, regen whether
	# grounded or airborne (ground faster). Never regen while thrusting.
	if not p._jetpacking:
		if p._fuel_delay_timer > 0.0:
			p._fuel_delay_timer -= delta
		else:
			var rate = p.FUEL_REFILL if on_floor else p.FUEL_REFILL_AIR
			p.fuel = minf(p.FUEL_MAX, p.fuel + rate * delta)
	# QA-141: reference owner gravity — 50 px/s^2 while thrusting, 300
	# otherwise (SLC::updateStep writes +0x198; local 0x8e4604
	# adds it after the damping, same order as here).
	p.velocity.y += (p.GRAVITY_THRUSTING if p._jetpacking else p.GRAVITY) * delta
	# v2.2: pushing the left stick down while airborne fast-falls.
	if p._fast_fall and not on_floor and not p._jetpacking:
		p.velocity.y += p.FAST_FALL_EXTRA * delta
	# QA-112: Skyfall wind zones push the player (game.gd sets
	# wind_force every frame; Vector2.ZERO on every other map, so
	# this is a no-op there). Extra acceleration, then clamped to
	# the normal speed limits so wind never outruns the player.
	# A jetpack line SHIELDS the rider from the wind - but only
	# while jetpacking on it, or while carrying the flag (a carrier
	# cannot jetpack at all, yet the line still shields them; they
	# get no fuel discount and no boost for it).
	var line_shield = p._on_jetpack_line and (p._jetpacking or p.carrying_flag != 0)
	if p.wind_force != Vector2.ZERO and not line_shield:
		p.velocity += p.wind_force * delta
		p.velocity.x = clampf(p.velocity.x, -max_speed - 100.0, max_speed + 100.0)
	# QA-135: Wind Blast tornado sweep — while swept, the tornado
	# owns the victim's velocity: pulled toward the funnel centre
	# for WIND_SWEEP_TIME, then thrown down (off the platform).
	# Set by the host's apply_wind_sweep RPC; the victim's own
	# physics applies it, so it works for remote victims too.
	# This runs AFTER movement/jetpack/wind, so the sweep wins
	# over the victim's own input while it lasts. The throw is
	# HELD for 0.5 s (not a one-frame impulse — friction would
	# eat a single impulse before the victim reaches the edge);
	# 700 px/s * 0.5 s = 350 px, enough to clear the nearest edge
	# from anywhere on a 500-600 px platform.
	if p._wind_sweep_timer > 0.0:
		p._wind_sweep_timer -= delta
		var to_c: Vector2 = p._wind_sweep_center - p.global_position
		if to_c.length() > 12.0:
			p.velocity = to_c.normalized() * 380.0
		else:
			p.velocity = Vector2.ZERO
		if p._wind_sweep_timer <= 0.0:
			p.velocity = p._wind_throw
			p._wind_throw_timer = 0.5
			p._wind_sweep_timer = 0.0
	elif p._wind_throw_timer > 0.0:
		p._wind_throw_timer -= delta
		p.velocity = p._wind_throw
		p.velocity.y += p.GRAVITY * delta
		if p._wind_throw_timer <= 0.0:
			p._wind_throw_timer = 0.0
	var max_fall = p.MAX_FALL + (350.0 if p._fast_fall else 0.0)
	if p.velocity.y > max_fall:
		p.velocity.y = max_fall
	p._fall_speed = p.velocity.y
	p._was_on_floor = on_floor
	p.move_and_slide()
	if p.is_on_floor():
		p._jump_cut_armed = false
	if p.is_on_floor() and not p._was_on_floor and p._fall_speed > 550.0:
		# Hard landing: small dust puff only.
		var game2 = p.get_tree().get_first_node_in_group("game")
		if game2 != null:
			# QA-110 (v3.8): the hit-spark call is REMOVED - after a
			# fall from a high area it flashed a white-gold sparkle
			# at the legs, which the user asked to remove. The soft
			# landing dust (QA-085) stays as the only landing effect.
			game2.spawn_dust_fx(p.global_position + Vector2(0, 31))
	var game3 = p.get_tree().get_first_node_in_group("game")
	if game3 != null and p.position.y > game3.map_size.y + 200.0:
		p._respawn()


func _read_input() -> void:
	p._move_axis = 0.0
	p._move_mag = 0.0
	p._jump_held = false
	p._jump_pressed = false
	p._aim_dir = Vector2.ZERO
	p._want_fire = false
	p._aiming = false

	var game = p.get_tree().get_first_node_in_group("game")
	if game == null:
		return
	# Touch input from the game (joysticks). The left stick is a full 2D
	# vector (normalized by the joystick itself; QA-141: reference has NO
	# dead zone, joystick.gd dead_zone is 0.0): x moves, y up jumps /
	# flies the jetpack, y down fast-falls.
	var move_vec: Vector2 = game.touch_move_vec
	p._move_axis = move_vec.x
	p._move_mag = absf(p._move_axis)
	p._move_stick_y = move_vec.y # QA-112: kept for the ladder (up/down to climb)
	# Stick-up jump: only on the rising edge, and only while "armed".
	# Holding the stick up through a landing must NOT auto-jump again -
	# the player re-arms by letting the stick drop below the threshold.
	var up_held = move_vec.y < -p.STICK_UP_THRESHOLD
	if up_held and not p._stick_up_prev and p._stick_up_armed:
		p._jump_pressed = true
		p._stick_up_armed = false
	if not up_held:
		p._stick_up_armed = true
	p._stick_up_prev = up_held
	p._jump_held = up_held
	p._fast_fall = move_vec.y > p.STICK_DOWN_THRESHOLD
	if game.touch_aim_active:
		# QA-141: reference has NO dead zone (Joypad::beginTouch, B §9) —
		# touch_aim is raw, so aiming is true for ANY non-zero aim
		# vector; sensitivity is applied after, so it cannot
		# shrink the (nonexistent) dead zone.
		p._aim_dir = game.touch_aim * GameData.sensitivity
		if p._aim_dir.length() > 1.0:
			p._aim_dir = p._aim_dir.normalized()
		p._aiming = p._aim_dir.length() > 0.0
	# v3.2: firing comes from the AIM stick (see game.gd) - the right
	# stick aims AND fires while held. Semi-auto weapons (pistol,
	# shotgun, sniper) fire one shot per fresh deflection.
	p._want_fire = game.touch_firing
	# Peek at the pending semi-auto shot - do NOT consume it here.
	# _read_input runs in _physics_process but touch_firing only
	# updates in _process, so a flick that lands just after a physics
	# step would otherwise be lost entirely (the flick would do
	# nothing on a real phone too). The edge is consumed in
	# _apply_aim_and_fire when the shot actually fires, and discarded
	# on respawn / while reloading / on weapon switch.
	p._fire_edge = false
	if game.has_method("has_aim_fire_edge"):
		p._fire_edge = game.has_aim_fire_edge()
	# Keyboard / mouse fallback (desktop testing only; touch wins when active).
	if p._move_axis == 0.0:
		var kb := Input.get_axis("ui_left", "ui_right")
		if kb != 0.0:
			p._move_axis = kb
			p._move_mag = absf(kb)
	if Input.is_key_pressed(KEY_SPACE):
		p._jump_held = true
	if Input.is_action_just_pressed("ui_accept"):
		p._jump_pressed = true
	if not p._aiming and game.touch_aim_active == false:
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
		var mouse_pos = p.get_viewport().get_mouse_position()
		# Mouse aims only - it never fires (the right stick shoots).
		# Clicks on HUD controls (fire / grenade / weapon / pause /
		# score / reload) must not swing the aim.
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not game.is_hud_control_pos(mouse_pos) and not game.touch_recently_used():
			var center = p.get_viewport().get_visible_rect().size * 0.5
			var dir = mouse_pos - center
			if dir.length() > 40.0:
				p._aim_dir = dir.normalized()
				p._aiming = true


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
	var was_on_ladder = p._on_ladder
	p._on_ladder = false
	p._ladder_rect = Rect2()
	var rect := Rect2()
	var scene = p.get_tree().current_scene
	if scene != null and scene.has_method("skyfall_ladder_at"):
		rect = scene.skyfall_ladder_at(p.global_position)
	if rect == Rect2():
		var game = p.get_tree().get_first_node_in_group("game")
		if game != null and game.has_method("skyfall_ladder_at"):
			rect = game.skyfall_ladder_at(p.global_position)
	if rect == Rect2():
		p._ladder_armed = true
		return
	p._ladder_rect = rect
	var holding = p._move_stick_y < -0.3 or p._move_stick_y > 0.3
	if not holding:
		p._ladder_armed = true
		return
	if p._jump_pressed and was_on_ladder:
		p._ladder_armed = false
		return
	if p._ladder_armed:
		p._on_ladder = true


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
	if p.is_on_floor() or p._wall_jumps_used >= p.WALL_JUMP_MAX_CHAIN:
		return false
	if p._jump_buffer_timer <= 0.0:
		return false
	# Which side is the wall on? is_on_wall + normal first (already
	# touching), else a 24 px ray in the move direction (close but
	# not yet touching). +1 = wall on the right, -1 = on the left.
	var side := 0
	if p.is_on_wall():
		var n = p.get_wall_normal()
		if n.x < -0.5:
			side = 1
		elif n.x > 0.5:
			side = -1
	if side == 0 and p._move_axis != 0.0:
		var space = p.get_world_2d().direct_space_state
		var from = p.global_position
		var to = p.global_position + Vector2(p._move_axis * (p.CAPSULE_RADIUS + p.WALL_DETECT_DIST), 0.0)
		var q := PhysicsRayQueryParameters2D.create(from, to, 1)
		q.collide_with_bodies = true
		q.collide_with_areas = false
		q.exclude = [p.get_rid()]
		if not space.intersect_ray(q).is_empty():
			side = 1 if p._move_axis > 0.0 else -1
	if side == 0:
		return false
	# Moving toward the wall: the stick is pushed that way, and the
	# horizontal velocity (if any) points into it - a player sliding
	# down the wall with no horizontal speed still counts.
	if p._move_axis == 0.0 or signf(p._move_axis) != float(side):
		return false
	if p.velocity.x != 0.0 and signf(p.velocity.x) != float(side):
		return false
	var mult = FLAG_CARRY_SPEED_MULT if p.carrying_flag != 0 else 1.0
	p.velocity.x = -float(side) * p.WALL_JUMP_PUSH * mult
	p.velocity.y = -p.WALL_JUMP_UP * mult
	p._wall_jumps_used += 1
	p._jump_buffer_timer = 0.0
	p._jump_pressed = false
	p._jump_cut_armed = false
	p._coyote_timer = 0.0
	p._play_sound("jump")
	return true


# QA-112 (v3.9 Skyfall grapple): attach / release, run every physics
# frame for the local player before _apply_movement (same slot as the
# ladder). Airborne on Skyfall, JUMP pressed, a point within 320 px
# and above: the rope attaches and the press is swallowed (it must
# not also jump). JUMP again while attached: let go with a 200 px/s
# upward boost. 1 s cooldown between grapples. No fuel, no jetpack
# while attached; firing is gated in _apply_aim_and_fire. Leaving
# Skyfall (or the data disappearing) drops the rope.
func _update_grapple(delta: float) -> void:
	p._grapple_cooldown = maxf(0.0, p._grapple_cooldown - delta)
	if not _is_skyfall():
		if p._grappling:
			_release_grapple(false)
		return
	if p._grappling:
		if p._jump_pressed:
			_release_grapple(true)
			p._jump_pressed = false
		return
	if p._grapple_cooldown > 0.0:
		return
	# The ladder-grab frame also carries a jump edge (stick-up grabs
	# the ladder) - that edge climbs, it must not also grapple.
	if p._jump_pressed and not p._on_ladder and not p.is_on_floor():
		var pt := _nearest_grapple_point(_skyfall_grapple_points(), p.global_position)
		if pt != Vector2.INF:
			p._grappling = true
			p._grapple_point = pt
			p._jump_pressed = false


func _skyfall_grapple_points() -> Array:
	# Fixed grapple points for this map ([] off Skyfall, or when the
	# "grapple" key is missing). A skyfall_grapple_points() helper
	# on the game scene wins when it exists; otherwise MAPS[4]
	# is read directly (const access through the instance).
	if not _is_skyfall():
		return []
	var game = p.get_tree().get_first_node_in_group("game")
	if game == null:
		return []
	var mid := int(game.map_id)
	if p._sf_grapple_cache_map == mid:
		return p._sf_grapple_cache
	p._sf_grapple_cache_map = mid
	p._sf_grapple_cache = []
	if game.has_method("skyfall_grapple_points"):
		var r = game.skyfall_grapple_points()
		if r is Array:
			p._sf_grapple_cache = r
	if p._sf_grapple_cache.is_empty() and ("MAPS" in game):
		var maps: Array = game.MAPS
		if GameData.SKYFALL_MAP_ID < maps.size():
			var row = maps[GameData.SKYFALL_MAP_ID]
			if row is Dictionary:
				var raw = (row as Dictionary).get("grapple", [])
				if raw is Array:
					p._sf_grapple_cache = raw
	return p._sf_grapple_cache


func _skyfall_jetpack_lines() -> Array:
	# Marked jetpack routes ([{"from": Vector2, "to": Vector2}])
	# for this map ([] off Skyfall, or when "jetpack_lines" is
	# missing). A skyfall_jetpack_lines() helper on the game scene
	# wins when it exists; otherwise MAPS[4] is read directly.
	if not _is_skyfall():
		return []
	var game = p.get_tree().get_first_node_in_group("game")
	if game == null:
		return []
	var mid := int(game.map_id)
	if p._sf_lines_cache_map == mid:
		return p._sf_lines_cache
	p._sf_lines_cache_map = mid
	p._sf_lines_cache = []
	if game.has_method("skyfall_jetpack_lines"):
		var r = game.skyfall_jetpack_lines()
		if r is Array:
			p._sf_lines_cache = r
	if p._sf_lines_cache.is_empty() and ("MAPS" in game):
		var maps: Array = game.MAPS
		if GameData.SKYFALL_MAP_ID < maps.size():
			var row = maps[GameData.SKYFALL_MAP_ID]
			if row is Dictionary:
				var raw = (row as Dictionary).get("jetpack_lines", [])
				if raw is Array:
					p._sf_lines_cache = raw
	return p._sf_lines_cache


func _segment_distance(p: Vector2, a: Vector2, b: Vector2) -> float:
	# Shortest distance from a point to a line segment (clamped
	# projection; a zero-length segment is just its point).
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 <= 0.0:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _on_jetpack_line_at(pos: Vector2, lines: Array) -> bool:
	for raw in lines:
		if not (raw is Dictionary):
			continue
		var d: Dictionary = raw
		if not (d.has("from") and d.has("to")):
			continue
		var a = d["from"]
		var b = d["to"]
		if a is Vector2 and b is Vector2 and _segment_distance(pos, a, b) <= p.JETPACK_LINE_DIST:
			return true
	return false


func _nearest_grapple_point(points: Array, from_pos: Vector2) -> Vector2:
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
		if d <= p.GRAPPLE_RANGE and d < best_d:
			best_d = d
			best = pt
	return best


func _is_on_jetpack_line() -> bool:
	# Within 70 px of a jetpack-line segment on Skyfall. A
	# skyfall_jetpack_line_at(pos) helper on the game scene wins
	# when it exists; otherwise the MAPS lines are measured here.
	if not _is_skyfall():
		return false
	var game = p.get_tree().get_first_node_in_group("game")
	if game != null and game.has_method("skyfall_jetpack_line_at"):
		return bool(game.skyfall_jetpack_line_at(p.global_position))
	return _on_jetpack_line_at(p.global_position, _skyfall_jetpack_lines())


func _grapple_pull_speed() -> float:
	# 500 px/s, 425 for a flag carrier (the 15% slower rule applies
	# to the rope pull too).
	return p.GRAPPLE_PULL_SPEED * (FLAG_CARRY_SPEED_MULT if p.carrying_flag != 0 else 1.0)


func _release_grapple(with_boost: bool) -> void:
	if not p._grappling:
		return
	p._grappling = false
	p._grapple_point = Vector2.ZERO
	p._grapple_cooldown = p.GRAPPLE_COOLDOWN
	if with_boost:
		p.velocity.y -= p.GRAPPLE_RELEASE_BOOST


func _is_skyfall() -> bool:
	var game = p.get_tree().get_first_node_in_group("game")
	if game == null or not ("map_id" in game):
		return false
	return int(game.map_id) == GameData.SKYFALL_MAP_ID


func _check_stuck(delta: float) -> void:
	# Stuck-in-geometry recovery (GAP-72): only fires when the player
	# is actually OVERLAPPING solid geometry (shape query), never for
	# merely pushing against a wall - that is normal play.
	p._stuck_check_timer += delta
	if p._stuck_check_timer < PhysicsConfig.STUCK_CHECK_INTERVAL:
		return
	p._stuck_check_timer = 0.0
	var game = p.get_tree().get_first_node_in_group("game")
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
	q.transform = Transform2D(0.0, p.global_position)
	q.collision_mask = 1
	q.collide_with_bodies = true
	q.collide_with_areas = false
	var space = p.get_world_2d().direct_space_state
	if not space.intersect_shape(q, 1).is_empty():
		var spot: Vector2 = game.get_valid_spawn_point(p.player_index, p.peer_id, p.global_position)
		print("STUCK-RECOVERY: player %d was inside solid geometry, moved to %s" % [p.peer_id, str(spot)])
		p.position = spot
		p.velocity = Vector2.ZERO
		# QA-053: teleport - tell the other phones at once instead
		# of waiting for the next 33 ms snapshot tick.
		p.player_sync._send_move_snapshot(true)
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
	if not p.is_on_floor() or absf(p._move_axis) <= 0.3:
		_wedge_reset()
		return
	if p._move_axis < 0.0:
		p._wedge_tried_left = true
	else:
		p._wedge_tried_right = true
	if p._wedge_ref_pos == Vector2.INF or p.global_position.distance_to(p._wedge_ref_pos) > 4.0:
		p._wedge_ref_pos = p.global_position
		p._wedge_still = 0.0
		p._wedge_tried_left = p._move_axis < 0.0
		p._wedge_tried_right = p._move_axis > 0.0
		return
	p._wedge_still += PhysicsConfig.STUCK_CHECK_INTERVAL
	var both_tried: bool = p._wedge_tried_left and p._wedge_tried_right
	if p._wedge_still >= 1.0 and (both_tried or p._wedge_still >= 2.0) and _both_sides_blocked():
		var spot2: Vector2 = game.get_valid_spawn_point(p.player_index, p.peer_id, p.global_position)
		print("WEDGE-RECOVERY: player %d wedged between obstacles (no move for %.0f s), moved to %s" % [p.peer_id, p._wedge_still, str(spot2)])
		p.position = spot2
		p.velocity = Vector2.ZERO
		p.player_sync._send_move_snapshot(true)
		_wedge_reset()


func _wedge_reset() -> void:
	p._wedge_ref_pos = Vector2.INF
	p._wedge_still = 0.0
	p._wedge_tried_left = false
	p._wedge_tried_right = false


func _both_sides_blocked() -> bool:
	# Raycast 48 px left and right from the capsule centre (QA-071b:
	# was 40 px; the capsule is 40 px wide, so the rays probe 28 px
	# past each edge). Both must hit solid world geometry (layer 1)
	# for a wedge.
	var space = p.get_world_2d().direct_space_state
	for dir in [-1.0, 1.0]:
		var rq := PhysicsRayQueryParameters2D.create(p.global_position, p.global_position + Vector2(48.0 * dir, 0.0))
		rq.collision_mask = 1
		rq.collide_with_bodies = true
		rq.collide_with_areas = false
		rq.exclude = [p.get_rid()]
		if space.intersect_ray(rq).is_empty():
			return false
	return true

