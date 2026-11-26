class_name PlayerWeapons
extends RefCounted


# QA-140 (v3.15): extracted from player/player.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `p` (dependency injection).
#
# NOTE: WeaponState mirrors player.gd's enum (same order/values: READY 0,
# FIRING 1, RELOADING 2). Enum values are NOT reachable through an
# instance (`p.FIRING` is a runtime error), so this module defines the
# enum itself; keep the order in sync with player.gd.
enum WeaponState { READY, FIRING, RELOADING }


var p # the owner (player/player.gd)


func _init(owner) -> void:
	p = owner


func _apply_aim_and_fire(delta: float) -> void:
	# FIRING lasts exactly one physics frame (GAP-41).
	if p.weapon_state == WeaponState.FIRING:
		p.weapon_state = WeaponState.RELOADING if p.reloading else WeaponState.READY
	# QA-112: no firing while attached to a grapple - the aim stick
	# is the trigger, so the shot is suppressed here and the flick
	# edge is discarded (it must not fire the moment the rope is
	# let go). NOTE: the ladder does not gate firing anywhere in
	# this file, so the grapple gate is explicit here rather than
	# shared; aiming itself is left alone so the player can pre-aim
	# for the release.
	if p._grappling:
		p._want_fire = false
		p._fire_edge = false
		var game_g = p.get_tree().get_first_node_in_group("game")
		if game_g != null:
			game_g.consume_aim_fire_edge()
		p._update_anim()
		return
	# Face the aim direction while aiming, else face the move direction.
	if p._aiming:
		p.aim_angle = p._aim_dir.angle()
		# Keep the body and hand anchor aligned with the gun except
		# within a very narrow vertical-aim dead zone.
		if absf(cos(p.aim_angle)) > 0.05:
			p.facing = -1 if cos(p.aim_angle) < 0.0 else 1
	elif p._move_axis != 0.0:
		# Keep the body, hand anchor, and weapon pointing the same way
		# while moving without aim input. This pair is replicated in
		# each movement snapshot for remote players.
		p.facing = -1 if p._move_axis < 0.0 else 1
		p.aim_angle = PI if p.facing < 0 else 0.0
	p._fire_cooldown -= delta
	p._grenade_cooldown -= delta
	if p.reloading:
		p.weapon_state = WeaponState.RELOADING
		p._reload_timer -= delta
		if p._reload_timer <= 0.0:
			p.reloading = false
			p.weapon_state = WeaponState.READY
			# Reserve transfer (GAP-39): move ammo from reserve to mag.
			p.mag_ammo += p._reload_transfer
			p._reload_transfer = 0
		# A flick during reload does nothing - discard the edge so it
		# cannot fire a shot the moment the reload finishes.
		var game_r = p.get_tree().get_first_node_in_group("game")
		if game_r != null:
			game_r.consume_aim_fire_edge()
	elif p._fire_cooldown <= 0.0:
		# v3.2: firing only happens while aiming (the shot goes where
		# the aim stick points). Automatic weapons fire while the
		# stick is held (_want_fire); semi-auto weapons (pistol,
		# shotgun, sniper) fire ONLY on a fresh flick (_fire_edge),
		# so a quick flick shoots even if the finger is already gone
		# by the time this step runs (QA-027 carry-over).
		var w: Dictionary = p.WEAPONS[p.weapon]
		var semi: bool = not bool(w.get("auto", true))
		# Trigger rule: auto fires while held, semi fires ONLY on a
		# fresh flick edge. A held semi-auto must NOT keep shooting
		# (_want_fire alone never fires a semi weapon), and a stale
		# edge must NEVER fire an auto weapon (the edge is only
		# consumed by a shot, so an unconsumed edge would keep an
		# auto weapon shooting forever after the stick is released).
		if (not semi and p._want_fire) or (semi and p._fire_edge):
			_fire()
			# The shot has consumed the flick (semi) / any stale edge
			# (auto) - one edge, one shot, never more.
			var game_f = p.get_tree().get_first_node_in_group("game")
			if game_f != null:
				game_f.consume_aim_fire_edge()
	p._update_anim()


func _fire() -> void:
	var w: Dictionary = p.WEAPONS[p.weapon]
	if p.mag_ammo <= 0:
		_start_reload()
		return
	p._fire_cooldown = float(w["rate"])
	p._shots_fired += 1
	p.mag_ammo -= 1
	p.weapon_state = WeaponState.FIRING
	var dir := Vector2(cos(p.aim_angle), sin(p.aim_angle))
	# QA-143: bullets leave from the reference design firing point
	# (muzzle_distance: grip-forward + frac * half gun length),
	# not the old flat GUN_LENGTH + 6.0 (61 px past the hands).
	var muzzle = p.global_position + p._muzzle_origin() + dir * p.player_visuals.muzzle_distance(p.weapon)
	# Recoil accumulation (GAP-40, spec §16): R_n = R_0 + n*K; the
	# accumulated spread widens the group and the gun kick grows.
	p._recoil_accum += float(w.get("recoil_k", 0.06))
	var pellets: int = int(w["pellets"])
	for i in pellets:
		var d := dir
		if p.weapon == 2:
			# QA-141: reference SPAS-12 — each of the 6 pellets gets an
			# INDEPENDENT angle from the LCG (Weapon::
			# getRandomFiringAngle 0x948878) in ±10° (the table
			# spread, 0.175 rad). The fixed [-15..15]° offset list
			# is deleted (weapons.gd).
			d = d.rotated(_lcg_spread_angle(float(w["spread"])))
		elif float(w["spread"]) > 0.0:
			# Other weapons: table spread + accumulated recoil spread.
			# QA-061: the Assault Rifle (weapon 0) is EXCLUDED from
			# the recoil growth - it fires straight no matter how
			# long the trigger is held (its table spread is 0.07
			# rad in QA-141, so this branch DOES run for it now;
			# the guard keeps its spread at the table value only).
			var sp := float(w["spread"])
			if p.weapon != 0:
				sp += p._recoil_accum * 0.5
			# QA-141: reference deterministic LCG spread (B §6) replaces
			# randf_range — same sequence on every peer, no RNG.
			d = d.rotated(_lcg_spread_angle(sp))
		# QA-061: record this pellet's direction deviation from the
		# aim (radians) for the rifle-straightness test. Capped so
		# a long match cannot grow the array without bound.
		p.shot_devs.append(wrapf(d.angle() - p.aim_angle, -PI, PI))
		if p.shot_devs.size() > 200:
			p.shot_devs.pop_front()
		# Velocity inheritance (GAP-55, spec §20.C): the bullet keeps
		# 0.15 of the shooter's velocity. spawn_bullet carries the
		# full velocity vector; bullet.gd integrates it.
		# QA-106 (v3.8): explosive weapons (the rocket) get NO
		# inheritance - the rocket must leave exactly along the aim
		# direction, straight, even when the shooter is moving.
		var bvel: Vector2 = d * float(w["speed"])
		if not bool(w["explosive"]):
			bvel += p.velocity * PhysicsConfig.VELOCITY_INHERITANCE
		p.rpc("spawn_bullet", muzzle, d, float(w["speed"]), int(w["damage"]), p.weapon, p.peer_id, p._shots_fired * 10 + i, bvel)
	p._play_sound(str(w["sound"]))
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
	p.velocity -= dir * float(w.get("recoil", 0.0))
	add_shake(float(w.get("shake", 0.0)))
	p._gun_kick = float(w.get("recoil", 0.0)) / 220.0 + p._recoil_accum
	if p.mag_ammo <= 0:
		_start_reload()


# QA-141: reference deterministic spread (Weapon::getRandomFiringAngle
# 0x948878, B §6). Per-weapon counter on the player, init 0:
# counter = (41 x counter + 37) % 100; uniform = (counter/100 -
# 0.5) x 2 (in [-1, +1)); angle = uniform x accuracy, where
# accuracy is the spread in DEGREES (table spread is radians).
# Returns the angle in RADIANS. The sequence is deterministic
# per weapon — the same shots group the same way on every peer.
func _lcg_spread_angle(spread_rad: float) -> float:
	var ctr: int = int(p._spread_counters.get(p.weapon, 0))
	ctr = (41 * ctr + 37) % 100
	p._spread_counters[p.weapon] = ctr
	var uniform: float = (float(ctr) / 100.0 - 0.5) * 2.0
	return deg_to_rad(uniform * rad_to_deg(spread_rad))


func add_shake(amount: float) -> void:
	p._shake_trauma = minf(1.0, p._shake_trauma + amount)


func start_reload() -> void:
	# Manual reload (RELOAD button): only when it would do something.
	if not p.alive or p.reloading:
		return
	if p.mag_ammo >= int(p.WEAPONS[p.weapon]["mag"]):
		return
	_start_reload()


func reload_progress() -> float:
	if not p.reloading:
		return 0.0
	var total: float = float(p.WEAPONS[p.weapon]["reload"])
	return clampf(1.0 - p._reload_timer / total, 0.0, 1.0)


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
	var w: Dictionary = p.WEAPONS[p.weapon]
	p._muzzle_flashes += 1
	if p._muzzle != null:
		var fscale: float = float(w.get("flash", 1.2)) * randf_range(0.9, 1.1)
		p._muzzle.scale = Vector2(fscale, fscale)
		p._muzzle.rotation = randf() * TAU
	p._muzzle_timer = float(w.get("flash_t", 0.05))


func _start_reload() -> void:
	p.reloading = true
	p.weapon_state = WeaponState.RELOADING
	p._reload_timer = float(p.WEAPONS[p.weapon]["reload"])
	# Reserve transfer (GAP-39): how much actually moves into the mag.
	var need: int = int(p.WEAPONS[p.weapon]["mag"]) - p.mag_ammo
	var res: int = int(p._reserve.get(p.weapon, -1))
	if res < 0:
		p._reload_transfer = need # infinite reserve (pistol sidearm)
	else:
		p._reload_transfer = mini(need, res)
		p._reserve[p.weapon] = res - p._reload_transfer
	p._play_sound("reload")


func ammo_reserve() -> int:
	# Reserve for the current weapon (-1 = infinite). Used by the HUD.
	return int(p._reserve.get(p.weapon, -1))


func switch_weapon() -> void:
	if not p.alive or owned_weapons().size() <= 1:
		return
	var owned: Array = owned_weapons()
	var idx := owned.find(p.weapon)
	var next_w: int = owned[(idx + 1) % owned.size()]
	# QA-075: switching weapons no longer refills the magazine.
	# The old code set mag_ammo to the new weapon's full mag on
	# every switch, so switching away and back refilled the rifle
	# for free. Each weapon's mag is now remembered across switches
	# (full on pickup / respawn) and restored on switch-back.
	p._mag_memory[p.weapon] = p.mag_ammo
	# QA-075: a reload in progress loses its reserved ammo if the
	# player switches mid-reload - _start_reload already deducted
	# it from the reserve into _reload_transfer, and the old code
	# just dropped the transfer. Refund it before changing weapon.
	_refund_reload()
	p.weapon = next_w
	p.mag_ammo = int(p._mag_memory.get(next_w, int(p.WEAPONS[next_w]["mag"])))
	p.reloading = false
	p.weapon_state = WeaponState.READY
	# QA-143: reference refreshes the view's weapon-angle offset on every
	# switch (SLC::switchWeapons 0x8ebea0 -> Weapon::getArmAngle
	# 0x9487d8 -> SoldierView::setWeaponAngleOffset 0x8fafec). The
	# switch itself is INSTANT in the reference - no delay literal exists in
	# switchWeapons, so the 0.15 s dip below stays visual only.
	p._weapon_angle_offset = float(p.player_visuals.WEAPON_ARM_ANGLE.get(next_w, 0.0))
	# QA-075: the gun dips briefly on switch (visual only - firing
	# is never blocked; SWITCH-WHILE-FIRING still shoots straight
	# through the switch). Remote copies dip too (see
	# receive_move_snapshot).
	p._switch_dip_timer = 0.15
	# v3.2: a pending semi-auto flick belongs to the old weapon - drop
	# it so switching cannot fire a shot nobody asked for.
	var game_sw = p.get_tree().get_first_node_in_group("game")
	if game_sw != null:
		game_sw.consume_aim_fire_edge()
	p._update_gun_texture()
	p._play_sound("click")


# QA-075: magazine memory + reload refund (see switch_weapon).
func _reset_mag_memory() -> void:
	p._mag_memory.clear()
	for id in p.WEAPONS.keys():
		p._mag_memory[id] = int((p.WEAPONS[id] as Dictionary).get("mag", 30))


func _refund_reload() -> void:
	if p._reload_transfer > 0:
		var res: int = int(p._reserve.get(p.weapon, -1))
		if res >= 0:
			p._reserve[p.weapon] = res + p._reload_transfer
		p._reload_transfer = 0
	p._reload_timer = 0.0


func owned_weapons() -> Array:
	# Rifle + pistol are always owned (starting loadout); the rest
	# come from weapon pickups.
	var list: Array = [0, 5]
	if p._owned_extra.has(1):
		list.append(1)
	if p._owned_extra.has(2):
		list.append(2)
	if p._owned_extra.has(3):
		list.append(3)
	if p._owned_extra.has(4):
		list.append(4)
	return list


func throw_grenade() -> void:
	if not p.alive or p.grenades <= 0 or p._grenade_cooldown > 0.0:
		return
	p._grenade_cooldown = 0.5
	p.grenades -= 1
	var dir := Vector2(cos(p.aim_angle), sin(p.aim_angle))
	if not p._aiming:
		# The grenade adds its own upward arc at launch. Keep the default
		# direction level so the arc is applied only once.
		dir = Vector2(p.facing, 0.0)
	# Throw launch speed, arc, and momentum inheritance are tuned in
	# PhysicsConfig; the grenade clamps inherited velocity on spawn.
	p.rpc("spawn_grenade", p.global_position + Vector2(0, -7), dir, p.peer_id, p.velocity, p._aiming)
	p._play_sound("click")


func spawn_bullet(pos: Vector2, dir: Vector2, speed: float, damage: int, kind: int, owner_id: int, shot_no: int, bvel: Vector2 = Vector2.INF) -> void:
	# Host-authoritative shooting (v2.4): the server validates every
	# shot's fire rate and ammunition before simulating it.
	if p.multiplayer.is_server():
		var sender = p.multiplayer.get_remote_sender_id()
		if sender != 0 and sender != p.multiplayer.get_unique_id():
			var game = p.get_tree().get_first_node_in_group("game")
			var shooter = game.players_node.get_node_or_null(str(sender)) if game != null else null
			var rep_mag: int = shooter.mag_ammo if shooter != null else 0
			if game == null or not game.shooting_sync.validate_shot(sender, kind, rep_mag):
				return
	var game2 = p.get_tree().get_first_node_in_group("game")
	if game2 == null:
		return
	var b = game2.obtain_bullet()
	if b == null:
		return
	var vel: Vector2 = bvel if bvel != Vector2.INF else dir * speed
	b.setup(pos, dir, speed, damage, kind, owner_id,
		bool(p.WEAPONS[kind]["explosive"]),
		120.0 if bool(p.WEAPONS[kind]["explosive"]) else 0.0,
		float(p.WEAPONS[kind].get("life", 1.4)),
		shot_no, vel, float(p.WEAPONS[kind].get("gravity", 0.0)))
	if b.get_parent() == null:
		game2.bullets_node.add_child(b)


func spawn_grenade(pos: Vector2, dir: Vector2, owner_id: int, thrower_vel: Vector2 = Vector2.ZERO, aimed: bool = false) -> void:
	var node = p.get_tree().get_first_node_in_group("game")
	if node == null:
		return
	var g = p.GRENADE_SCENE.instantiate()
	g.name = "g_%d_%d" % [owner_id, Time.get_ticks_msec()]
	g.position = pos
	g.throw_dir = dir
	g.thrower_vel = thrower_vel
	g.owner_id = owner_id
	g.aimed_throw = aimed
	# Add to scene AFTER all properties are set so the first physics
	# frame sees the correct throw_dir and thrower_vel (no zero-vel tick).
	node.grenades_node.add_child(g)

