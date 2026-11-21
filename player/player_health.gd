class_name PlayerHealth
extends RefCounted


# QA-140 (v3.15): extracted from player/player.gd. This module owns no
# state of its own except the vars listed below: every other
# field it reads or writes lives on the owner and is reached
# through `p` (dependency injection).


# QA-140: mirrors player/player.gd (same order/values); enum values are not reachable through an instance.
enum LifeState { ALIVE, DYING, DEAD, RESPAWNING }


# QA-140: mirrors player/player.gd (same order/values); enum values are not reachable through an instance.
enum WeaponState { READY, FIRING, RELOADING }


var p # the owner (player/player.gd)

const HEALTH_REGEN_DELAY := 1.0 # QA-141: MMC 1 HP per 1.0 s tick (SLC::updateStep 0x8e4d5c, was 3.0)
const HEALTH_REGEN_RATE := 1.0 # HP per second (QA-141: MMC 1 HP/s, was 4.0)



func _init(owner) -> void:
	p = owner


func take_damage(amount: int, from_id: int) -> void:
	# Host-authoritative health (v2.4): only the host (peer 1) may
	# inflict damage - a client calling this directly is ignored.
	# The host routes damage to the victim's owning peer (see
	# bullet.gd / game.gd), so the call always arrives from the host.
	# Kept as the simple entry (lava, tests); bullets use take_hit
	# so knockback + damage event ids travel with the hit (GAP-43/46).
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_apply_damage(amount, from_id, Vector2.ZERO, 0.0, -1)


func take_hit(amount: int, from_id: int, dir: Vector2, knockback: float, event_id: int) -> void:
	# Host-authoritative hit with knockback + unique event id
	# (GAP-43/46, spec §17.5/§17.8). A re-sent or double-routed
	# damage RPC with an already-seen event id is ignored.
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if event_id >= 0:
		if p._seen_damage_ids.has(event_id):
			return
		p._seen_damage_ids.append(event_id)
		while p._seen_damage_ids.size() > 64:
			p._seen_damage_ids.pop_front()
	_apply_damage(amount, from_id, dir, knockback, event_id)


func _apply_damage(amount: int, from_id: int, dir: Vector2, knockback: float, event_id: int) -> void:
	# Single place where health actually changes (spec §17.8).
	# Guards: death happens only once per life (life_state, GAP-44).
	if p.life_state != LifeState.ALIVE:
		return
	if p._spawn_protect_timer > 0.0:
		return
	# QA-112: a shield absorbs ALL damage - only the health loss is
	# blocked. Knockback, hit flash, shake and sound still play.
	if p.shield_timer > 0.0:
		amount = 0
	p.health -= amount
	if amount > 0:
		p._regen_timer = HEALTH_REGEN_DELAY # QA-120: damage restarts the regen wait
	# Per-weapon victim knockback (GAP-46): a velocity add, so
	# move_and_slide resolves it against collision next frame -
	# knockback never bypasses collision (spec §17.8).
	if knockback > 0.0 and dir != Vector2.ZERO:
		p.velocity += dir * knockback
	p._hit_flash_timer = 0.09
	p.player_weapons.add_shake(0.25) # victim shake on damage (GAP-54, spec §19)
	p._play_sound("hurt")
	if p.health <= 0:
		p.health = 0
		p.alive = false
		p.life_state = LifeState.DYING
		p._dying_timer = 0.4
		p.deaths += 1
		p._respawn_timer = 3.0
		# QA-069: a death is a score change - force a snapshot at
		# once so every peer's scoreboard sees it now, not on the
		# next 30/s tick (same treatment respawn already gets).
		p.player_sync._send_move_snapshot(true)
		p._collision_shape.set_deferred("disabled", true)
		p._anim_locked = true
		p._play_anim("die")
		p._stop_jetpack_sound()
		p._play_sound("death")
		# Survival: dead for the rest of this round (revived by the
		# host's round reset). Last Man Standing: no respawn at all.
		var game2 = p.get_tree().get_first_node_in_group("game")
		if game2 != null and int(game2.game_mode) == 2:
			p._round_dead = true
		# Kill credit is the HOST's job (it decided the damage): the
		# server credits the killer when it deals the lethal hit (see
		# bullet.gd _hit_player / game.gd request_explosion). Nothing
		# is credited here, so a client can never award itself kills.


func take_explosion_damage(pos: Vector2, radius: float, damage: int, from_id: int, event_id: int = -1) -> void:
	# Host-authoritative, like take_damage: only the host may call.
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	if p.life_state != LifeState.ALIVE:
		return
	if p._spawn_protect_timer > 0.0:
		return
	if event_id >= 0:
		if p._seen_damage_ids.has(event_id):
			return
		p._seen_damage_ids.append(event_id)
		while p._seen_damage_ids.size() > 64:
			p._seen_damage_ids.pop_front()
	var dist = p.global_position.distance_to(pos)
	if dist > radius:
		return
	# QA-141: MMC explosion damage (Explosion::applyDamage 0x620168,
	# confirmed in ClientRoom::processDefaultExplosion 0x86ee54):
	# D = max(10, 100 - 0.8 x dist) inside radius 125. The `damage`
	# argument is legacy (flat per-source damage) and is ignored —
	# every explosion (grenade, rocket, barrel) uses this one MMC
	# formula. Knockback: dV = min(600, (100 - 0.8 x dist) x 10)
	# along the away-direction (MMC impulse x m_inv 10, capped by
	# the 600 max-speed clamp), plus the extra upward blast (Ky 0.4,
	# kept — not extracted).
	var amount := int(round(maxf(PhysicsConfig.EXPLOSION_DAMAGE_MIN, PhysicsConfig.EXPLOSION_DAMAGE_MAX - PhysicsConfig.EXPLOSION_DAMAGE_FALLOFF * dist)))
	var j := minf(PhysicsConfig.EXPLOSION_KNOCKBACK_CAP, (PhysicsConfig.EXPLOSION_DAMAGE_MAX - PhysicsConfig.EXPLOSION_DAMAGE_FALLOFF * dist) * 10.0)
	var dir = (p.global_position - pos).normalized()
	# Radial knockback dV = J/m plus an extra upward blast (Ky).
	var kb = dir * (j / PhysicsConfig.MASS) + Vector2(0, -j * PhysicsConfig.EXPLOSION_VERTICAL_MULT)
	p.velocity += kb
	p.player_weapons.add_shake(0.5) # victim shake on explosion (GAP-54)
	# Damage + death via the single damage path (no double counting:
	# the knockback above is applied here, _apply_damage gets 0).
	_apply_damage(amount, from_id, Vector2.ZERO, 0.0, -1)


func add_kill() -> void:
	# Only the host may award a kill (it decided the lethal hit).
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	p.kills += 1
	# QA-069: a kill is a score change - force a snapshot at once
	# so every peer's scoreboard sees it now, not on the next 30/s
	# tick. Offline / no peers, _send_move_snapshot is a no-op.
	p.player_sync._send_move_snapshot(true)
	p._play_sound("pickup")


# Phase 4 - accuracy: one trigger pull counts as a hit once, however
# many of its pellets land (a shotgun's 7 pellets are one shot, not
# seven). shot_no is _shots_fired * 10 + pellet index, so the key is
# shot_no / 10. Called by the host only.
func record_hit(shot_no: int) -> void:
	var key := shot_no / 10
	if p._hit_shot_keys.has(key):
		return
	p._hit_shot_keys.append(key)
	p._shots_hit += 1


# Phase 4 - hitmarker: the host confirms each hit to the shooter
# (damage dealt, where, and whether it was lethal). The game reads
# _hitmark_seq on the local player and shows the marker + damage
# number. Only the host may send this.
func hit_confirm(dmg: int, pos: Vector2, lethal: bool) -> void:
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	p._hitmark_seq += 1
	p._hitmark_dmg = dmg
	p._hitmark_pos = pos
	p._hitmark_lethal = lethal
	p._hitmark_time = Time.get_ticks_msec() / 1000.0


# QA-120: slow health regen. Called every physics frame next to
# _tick_boost_timers. Health restores only after
# HEALTH_REGEN_DELAY seconds without taking damage (the timer is
# restarted in _apply_damage on every real health loss).
func _tick_health_regen(delta: float) -> void:
	if not p.alive or p.health >= 100:
		return
	if p._regen_timer > 0.0:
		p._regen_timer = maxf(0.0, p._regen_timer - delta)
		return
	p.health = mini(100, p.health + HEALTH_REGEN_RATE * delta)


func _respawn() -> void:
	# Validated respawn (GAP-45, spec §17.7): the spawn must be free
	# of walls/ground/obstacles, clear of live enemies (>150 px) and
	# inside the map. If no spawn is valid, retry in 0.5 s instead of
	# teleporting into a wall or a camper.
	var game = p.get_tree().get_first_node_in_group("game")
	var spot := Vector2.INF
	if game != null:
		spot = game.get_valid_spawn_point(p.player_index, p.peer_id)
	if spot == Vector2.INF:
		p.life_state = LifeState.RESPAWNING
		p._respawn_retry_timer = PhysicsConfig.RESPAWN_RETRY_DELAY
		return
	p.health = 100
	p.alive = true
	p.life_state = LifeState.ALIVE
	p.fuel = p.FUEL_MAX
	p._fuel_delay_timer = 0.0
	p._spawn_protect_timer = p.SPAWN_PROTECTION
	p.weapon = 0
	p._owned_extra.clear()
	p._reserve = p.RESERVE_DEFAULT.duplicate()
	p.player_weapons._reset_mag_memory() # QA-075: respawn refills every remembered mag
	p.mag_ammo = int(p.WEAPONS[0]["mag"])
	p.reloading = false
	p.weapon_state = WeaponState.READY
	p._reload_transfer = 0
	p._reload_timer = 0.0
	p._recoil_accum = 0.0
	p._jet_thrust_factor = 0.0 # QA-141: no thrust carries over a respawn
	p.scoped = false # QA-105: no scope carries over a respawn
	p._jet_thrust_factor = 0.0
	p._muzzle_timer = 0.0 # QA-075: no flash carries over a respawn
	p._switch_dip_timer = 0.0
	p._anim_locked = false
	p._fast_fall = false
	p._stick_up_prev = false
	p._stick_up_armed = true
	p._jump_cut_armed = false
	p._round_dead = false
	p._shake_trauma = 0.0
	p._gun_kick = 0.0
	# QA-112: a fresh life starts with no boosts, no flag, no wind,
	# no ladder. carrying_flag is cleared here, not on death, so
	# game.gd can still read who dropped the flag while the player
	# is dead (the flag drop itself is game.gd's job).
	p.shield_timer = 0.0
	p.speed_timer = 0.0
	p.invisibility_timer = 0.0
	p.jetpack_boost_timer = 0.0
	p.active_boost_kind = 0
	p.stored_boosts.clear()
	p._regen_timer = 0.0 # QA-120: no regen wait carries over a respawn
	p._fx_flash_kind = 0 # QA-119: no effect flash carries over a respawn
	p._fx_flash_timer = 0.0
	p.modulate = Color.WHITE # QA-119: no invisibility carries over a respawn
	p.carrying_flag = 0
	p.wind_force = Vector2.ZERO
	p._on_ladder = false
	p._ladder_rect = Rect2()
	p._ladder_armed = true
	# QA-112: a fresh life starts with no rope, no wall-jump chain,
	# no line state either.
	p._grappling = false
	p._grapple_point = Vector2.ZERO
	p._grapple_cooldown = 0.0
	p._wall_jumps_used = 0
	p._on_jetpack_line = false
	# Discard a stale pending shot so a finger held while dead
	# cannot fire a shot the instant we respawn.
	var game0 = p.get_tree().get_first_node_in_group("game")
	if game0 != null:
		game0.consume_aim_fire_edge()
	p.position = spot
	p.velocity = Vector2.ZERO
	# QA-053: respawn is a teleport - force a snapshot at once so the
	# remote copy learns the new spawn immediately (and never keeps
	# interpolating toward the old death position).
	p.player_sync._send_move_snapshot(true)
	p._collision_shape.set_deferred("disabled", false)
	p._update_gun_texture()
	p._play_anim("idle")
	p._play_sound("spawn")
	if p._camera != null:
		p._camera.reset_smoothing()
		p._cam_anchor = spot
		p._cam_anchor_init = true


# Survival round reset: the host tells every peer to respawn its own
# player for the next round (new positions, full health).
func reset_round_remote() -> void:
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	p._round_dead = false
	_respawn()


func hit_region(hit_pos: Vector2, player_pos: Vector2) -> String:
	# Separate hit regions from the hit height (GAP-25/42, spec §11/§17.3).
	# Arms fold into torso: the capsule cannot distinguish arms, so
	# the documented deviation is head 1.5 / torso 1.0 / legs 0.75.
	var rel_y := hit_pos.y - player_pos.y
	if rel_y < PhysicsConfig.HIT_HEAD_Y:
		return "head"
	if rel_y > PhysicsConfig.HIT_LEGS_Y:
		return "legs"
	return "torso"


func calculate_damage(base: int, region: String, distance: float, weapon_id: int) -> int:
	# D_final = D_base x M_region x M_distance x M_weapon x M_armor
	# (GAP-42, spec §17.2/§17.3). M_armor is 1.0 until armor exists.
	var m_region: float = float(PhysicsConfig.REGION_MULT.get(region, 1.0))
	var m_dist := 1.0
	if distance > PhysicsConfig.DAMAGE_FALLOFF_START:
		var w: Dictionary = WeaponData.get_weapon(weapon_id)
		var max_range := float(w.get("speed", 900.0)) * float(w.get("life", 1.0))
		if max_range > PhysicsConfig.DAMAGE_FALLOFF_START:
			var f := clampf((distance - PhysicsConfig.DAMAGE_FALLOFF_START) / (max_range - PhysicsConfig.DAMAGE_FALLOFF_START), 0.0, 1.0)
			# QA-075: the falloff floor is per-weapon now (was a
			# flat 0.7x for every gun): the sniper keeps 0.9x at
			# max range, the shotgun drops to 0.5x, the SMG to
			# 0.6x, the pistol to 0.65x. Close-range damage is
			# unchanged (falloff only starts past 400 px).
			var falloff_min: float = float(w.get("falloff_min", PhysicsConfig.DAMAGE_FALLOFF_MIN))
			m_dist = lerpf(1.0, falloff_min, f)
	var m_weapon: float = float(WeaponData.get_weapon(weapon_id).get("damage_mult", 1.0))
	return int(round(float(base) * m_region * m_dist * m_weapon))

