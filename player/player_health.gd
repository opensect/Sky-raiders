class_name PlayerHealth
extends RefCounted


# QA-140 (v3.15): extracted from player/player.gd.


enum LifeState { ALIVE, DYING, DEAD, RESPAWNING }
enum WeaponState { READY, FIRING, RELOADING }


var p # the owner (player/player.gd)

const HEALTH_REGEN_DELAY := 1.0
const HEALTH_REGEN_RATE := 1.0 # HP per second

# Float accumulator so 1 HP/s actually ticks at 60fps (delta ~0.016 per frame).
var _regen_accum: float = 0.0


func _init(owner) -> void:
	p = owner


func take_damage(amount: int, from_id: int) -> void:
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	_apply_damage(amount, from_id, Vector2.ZERO, 0.0, -1)


func take_hit(amount: int, from_id: int, dir: Vector2, knockback: float, event_id: int) -> void:
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
	if p.life_state != LifeState.ALIVE:
		return
	if p._spawn_protect_timer > 0.0:
		return
	if p.shield_timer > 0.0:
		amount = 0
	p.health -= amount
	if amount > 0:
		p._regen_timer = HEALTH_REGEN_DELAY
		_regen_accum = 0.0  # reset accumulator on damage
	if knockback > 0.0 and dir != Vector2.ZERO:
		p.velocity += dir * knockback
	p._hit_flash_timer = 0.09
	p.player_weapons.add_shake(0.25)
	p._play_sound("hurt")
	if p.health <= 0:
		p.health = 0
		p.alive = false
		p.life_state = LifeState.DYING
		p._dying_timer = 0.4
		p.deaths += 1
		p._respawn_timer = 3.0
		p.player_sync._send_move_snapshot(true)
		p._collision_shape.set_deferred("disabled", true)
		p._anim_locked = true
		p._play_anim("die")
		p._stop_jetpack_sound()
		p._play_sound("death")
		var game2 = p.get_tree().get_first_node_in_group("game")
		if game2 != null and int(game2.game_mode) == 2:
			p._round_dead = true


func take_explosion_damage(pos: Vector2, radius: float, damage: int, from_id: int, event_id: int = -1) -> void:
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
	var amount := int(round(maxf(PhysicsConfig.EXPLOSION_DAMAGE_MIN, PhysicsConfig.EXPLOSION_DAMAGE_MAX - PhysicsConfig.EXPLOSION_DAMAGE_FALLOFF * dist)))
	var j := minf(PhysicsConfig.EXPLOSION_KNOCKBACK_CAP, (PhysicsConfig.EXPLOSION_DAMAGE_MAX - PhysicsConfig.EXPLOSION_DAMAGE_FALLOFF * dist) * 10.0)
	var dir = (p.global_position - pos).normalized()
	var kb = dir * (j / PhysicsConfig.MASS) + Vector2(0, -j * PhysicsConfig.EXPLOSION_VERTICAL_MULT)
	p.velocity += kb
	p.player_weapons.add_shake(0.5)
	_apply_damage(amount, from_id, Vector2.ZERO, 0.0, -1)


func add_kill() -> void:
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	p.kills += 1
	p.player_sync._send_move_snapshot(true)
	p._play_sound("pickup")


func record_hit(shot_no: int) -> void:
	var key := shot_no / 10
	if p._hit_shot_keys.has(key):
		return
	p._hit_shot_keys.append(key)
	p._shots_hit += 1


func hit_confirm(dmg: int, pos: Vector2, lethal: bool) -> void:
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	p._hitmark_seq += 1
	p._hitmark_dmg = dmg
	p._hitmark_pos = pos
	p._hitmark_lethal = lethal
	p._hitmark_time = Time.get_ticks_msec() / 1000.0


func _tick_health_regen(delta: float) -> void:
	if not p.alive or p.health >= 100:
		_regen_accum = 0.0
		return
	if p._regen_timer > 0.0:
		p._regen_timer = maxf(0.0, p._regen_timer - delta)
		return
	# Float accumulator: HEALTH_REGEN_RATE is 1 HP/s; at 60fps delta~0.016
	# so we must accumulate fractional HP and only add whole HP integers.
	_regen_accum += HEALTH_REGEN_RATE * delta
	if _regen_accum >= 1.0:
		var gain := int(_regen_accum)
		p.health = mini(100, p.health + gain)
		_regen_accum -= float(gain)


func _respawn() -> void:
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
	p._jetpack_empty_locked = false
	p._fuel_delay_timer = 0.0
	p._spawn_protect_timer = p.SPAWN_PROTECTION
	p.weapon = 0
	p._weapon_angle_offset = 0.0
	p._owned_extra.clear()
	p._reserve = p.RESERVE_DEFAULT.duplicate()
	p.player_weapons._reset_mag_memory()
	p.mag_ammo = int(p.WEAPONS[0]["mag"])
	p.reloading = false
	p.weapon_state = WeaponState.READY
	p._reload_transfer = 0
	p._reload_timer = 0.0
	p._recoil_accum = 0.0
	p._jet_thrust_factor = 0.0
	p._muzzle_timer = 0.0
	p._switch_dip_timer = 0.0
	p._anim_locked = false
	p._fast_fall = false
	p._stick_up_prev = false
	p._stick_up_armed = true
	p._jump_cut_armed = false
	p._round_dead = false
	p._shake_trauma = 0.0
	p._gun_kick = 0.0
	p.shield_timer = 0.0
	p.speed_timer = 0.0
	p.invisibility_timer = 0.0
	p.jetpack_boost_timer = 0.0
	p.active_boost_kind = 0
	p.stored_boosts.clear()
	p._regen_timer = 0.0
	_regen_accum = 0.0
	p._fx_flash_kind = 0
	p._fx_flash_timer = 0.0
	p.modulate = Color.WHITE
	p.carrying_flag = 0
	p.wind_force = Vector2.ZERO
	p._on_ladder = false
	p._ladder_rect = Rect2()
	p._ladder_armed = true
	p._grappling = false
	p._grapple_point = Vector2.ZERO
	p._grapple_cooldown = 0.0
	p._wall_jumps_used = 0
	p._on_jetpack_line = false
	var game0 = p.get_tree().get_first_node_in_group("game")
	if game0 != null:
		game0.consume_aim_fire_edge()
	p.position = spot
	p.velocity = Vector2.ZERO
	p.player_sync._send_move_snapshot(true)
	p._collision_shape.set_deferred("disabled", false)
	p._update_gun_texture()
	p._play_anim("idle")
	p._play_sound("spawn")
	if p._camera != null:
		p._camera.reset_smoothing()
		p._cam_anchor = spot
		p._cam_anchor_init = true


func reset_round_remote() -> void:
	var sender = p.multiplayer.get_remote_sender_id()
	if sender != 0 and sender != 1:
		return
	p._round_dead = false
	_respawn()


func hit_region(hit_pos: Vector2, player_pos: Vector2) -> String:
	var rel_y := hit_pos.y - player_pos.y
	if rel_y < PhysicsConfig.HIT_HEAD_Y:
		return "head"
	if rel_y > PhysicsConfig.HIT_LEGS_Y:
		return "legs"
	return "torso"


func calculate_damage(base: int, region: String, distance: float, weapon_id: int) -> int:
	var m_region: float = float(PhysicsConfig.REGION_MULT.get(region, 1.0))
	var m_dist := 1.0
	if distance > PhysicsConfig.DAMAGE_FALLOFF_START:
		var w: Dictionary = WeaponData.get_weapon(weapon_id)
		var max_range := float(w.get("speed", 900.0)) * float(w.get("life", 1.0))
		if max_range > PhysicsConfig.DAMAGE_FALLOFF_START:
			var f := clampf((distance - PhysicsConfig.DAMAGE_FALLOFF_START) / (max_range - PhysicsConfig.DAMAGE_FALLOFF_START), 0.0, 1.0)
			var falloff_min: float = float(w.get("falloff_min", PhysicsConfig.DAMAGE_FALLOFF_MIN))
			m_dist = lerpf(1.0, falloff_min, f)
	var m_weapon: float = float(WeaponData.get_weapon(weapon_id).get("damage_mult", 1.0))
	return int(round(float(base) * m_region * m_dist * m_weapon))
