extends Area2D

# Bullet: simulated on every peer; only the server (host) applies damage.
# FIX (v2): swept collision - each physics step we raycast from the previous
# position to the new position, so fast bullets can no longer tunnel through
# thin (24px) platforms, walls or the ground.
#
# v2.4: bullets come from a pool (BulletPool) instead of being
# instantiated per shot. `setup()` (re)initialises a pooled bullet;
# `_despawn()` returns it to the pool instead of queue_free(). A bullet
# that was allocated one-off (pool exhausted) is freed as before.
# Host-authoritative combat: the server's copy is the only one that
# deals damage, and the server credits the kill when its own hit is
# lethal (see _hit_player). Friendly fire is honoured in TDM.

# Per-projectile state (GAP-19, spec §9): position (node), velocity
# vector, direction, speed, damage, radius, lifetime, range, gravity,
# drag, owner id, weapon id (kind), collision mask. Velocity is a
# vector so firing-while-moving inheritance (0.15, GAP-55) and rocket
# gravity (GAP-10) both work; direction is derived from velocity.
var direction: Vector2 = Vector2.RIGHT
var velocity: Vector2 = Vector2.RIGHT * 900.0
var speed: float = 900.0
var damage: int = 12
var kind: int = 0 # 0 rifle, 1 smg, 2 shotgun, 3 sniper, 4 rocket, 5 pistol
var owner_id: int = 0
var explosive: bool = false
var blast_radius: float = 0.0
var life: float = 1.4
var radius: float = 3.0 # projectile collision radius (spec §9)
var grav: float = 0.0 # px/s^2; rocket 500 (GAP-10), others 0
var drag: float = 0.0 # air drag; 0 for bullets
var range_px: float = 0.0 # expires after travelling this far
var pooled: bool = false
var active: bool = false
var shot_no: int = 0 # Phase 4: _shots_fired * 10 + pellet index (accuracy dedupe key)
var _travelled: float = 0.0

var _life: float = 1.4
var _trail: Line2D
var _visual: Polygon2D
# QA-084 (v3.7): a drawn trail sprite behind the bullet (gradient
# streak, bright at the head, fading to the tail), on top of the
# existing Line2D trail — the line stays exactly as it was (the
# fire test reads its width / length), the sprite is a glow on top.
const TRAIL_SPRITE_TEX: Texture2D = preload("res://assets/effects/bullet_trail.png")
var _trail_sprite: Sprite2D
var _dead: bool = false
# QA-075: bullet trail length / width by weapon (was a fixed 21 px
# tail, 2.4 wide, on every gun). The pistol keeps exactly 21.0 /
# 2.4 — the fire test asserts those numbers. Faster, heavier rounds
# read longer and wider: the sniper's trail is the longest, the
# rocket's the widest. Visual only; the hitbox is the swept ray.
var _trail_len: float = 21.0
const TRAIL_LEN := {0: 33.0, 1: 30.0, 2: 26.0, 3: 48.0, 4: 40.0, 5: 21.0}
const TRAIL_WIDTH := {0: 2.4, 1: 2.4, 2: 2.8, 3: 3.2, 4: 4.0, 5: 2.4}


func _ready() -> void:
	# GAP-21/71: the scene owns layer 4 (projectile, spec §24.D) and
	# mask 0; the swept raycast below is the REAL collision, not the
	# Area2D (monitoring off). Do not re-enable Area2D detection here.
	collision_layer = 4
	collision_mask = 0
	monitoring = false
	monitorable = false
	_visual = Polygon2D.new()
	add_child(_visual)
	_trail_sprite = Sprite2D.new()
	_trail_sprite.texture = TRAIL_SPRITE_TEX
	_trail_sprite.z_index = -1 # behind the bullet head
	add_child(_trail_sprite)
	_trail = Line2D.new()
	_trail.width = 2.4 # QA-056: 80% of 3.0, matching the smaller bullet
	_trail.add_point(Vector2.ZERO)
	_trail.add_point(Vector2.ZERO)
	add_child(_trail)
	_apply_visual()


func setup(p_pos: Vector2, p_dir: Vector2, p_speed: float, p_damage: int, p_kind: int, p_owner: int, p_explosive: bool, p_blast: float, p_life: float, p_shot_no: int, p_vel: Vector2 = Vector2.INF, p_gravity: float = 0.0) -> void:
	position = p_pos
	direction = p_dir.normalized()
	speed = p_speed
	damage = p_damage
	kind = p_kind
	owner_id = p_owner
	explosive = p_explosive
	blast_radius = p_blast
	life = p_life
	_life = p_life
	grav = p_gravity
	range_px = p_speed * p_life
	shot_no = p_shot_no
	_travelled = 0.0
	velocity = p_vel if p_vel != Vector2.INF else direction * p_speed
	_dead = false
	active = true
	visible = true
	set_physics_process(true)
	rotation = velocity.angle()
	if not pooled:
		name = "b_%d_%d" % [owner_id, p_shot_no]
	_apply_visual()
	if _trail != null:
		_trail.set_point_position(0, Vector2.ZERO)
		_trail.set_point_position(1, Vector2.ZERO)


func _apply_visual() -> void:
	if _visual == null:
		return
	# QA-056: bullets are 20% smaller (visual 80% of v3.3). The
	# swept raycast IS the hitbox (zero-width ray down the bullet's
	# path), so shrinking the visual keeps see-is-what-hits: the
	# 4.8 px wide visual stays centred on the same ray, with no big
	# invisible hitbox around a small bullet.
	var length := 17.6 if kind == 4 else 11.2
	_visual.polygon = PackedVector2Array([
		Vector2(-length, -2.4), Vector2(length, -2.4), Vector2(length, 2.4), Vector2(-length, 2.4),
	])
	var col := Color(1.0, 0.85, 0.3)
	if kind == 1:
		col = Color(1.0, 0.6, 0.2)
	elif kind == 2:
		col = Color(1.0, 0.5, 0.3)
	elif kind == 3:
		col = Color(0.5, 0.9, 1.0)
	elif kind == 4:
		col = Color(1.0, 0.3, 0.2)
	elif kind == 5:
		col = Color(1.0, 0.9, 0.55)
	_visual.color = col
	if _trail != null:
		_trail.default_color = Color(col.r, col.g, col.b, 0.5)
		_trail.width = float(TRAIL_WIDTH.get(kind, 2.4))
		_trail_len = float(TRAIL_LEN.get(kind, 21.0))
	# QA-084: the trail sprite stretches from the bullet's tail back
	# _trail_len px (same length as the line) and takes the bullet's
	# colour as a tint, so the glow matches the round. The bullet
	# node itself rotates to the velocity, so the sprite (a child)
	# always points along the flight path.
	if _trail_sprite != null:
		_trail_sprite.scale = Vector2(_trail_len / 64.0, float(TRAIL_WIDTH.get(kind, 2.4)) / 8.0)
		_trail_sprite.position = Vector2(-_trail_len / 2.0, 0)
		_trail_sprite.modulate = Color(col.r, col.g, col.b, 0.85)


func _despawn() -> void:
	if pooled:
		var game = get_tree().get_first_node_in_group("game")
		if game != null:
			game.return_bullet(self)
			return
	queue_free()


func _physics_process(delta: float) -> void:
	if _dead:
		return
	# Gravity (rockets arc, GAP-10) + drag, then integrate the velocity
	# vector (GAP-55 inheritance is baked into `velocity` at setup).
	if grav != 0.0:
		velocity.y += grav * delta
	if drag != 0.0:
		velocity *= exp(-drag * delta)
	if velocity.length() > 0.01:
		direction = velocity.normalized()
	var from := global_position
	var step := velocity * delta
	var to := from + step
	rotation = velocity.angle()
	# Swept test: ray from where we were to where we are going.
	# QA-075: _sweep_hit runs the centre ray first (the QA-055
	# hit-from-inside behaviour, unchanged), then two graze rays
	# offset +/-2.5 px — the bullet visual is 4.8 px wide, so a
	# shot whose edge clips a player or a wall used to miss on a
	# zero-width ray. A graze hit is handled exactly like a centre
	# hit below; a centre hit always wins over a graze.
	var hit: Dictionary = _sweep_hit(from, to)
	if not hit.is_empty():
		var collider: Object = hit["collider"]
		var hit_pos: Vector2 = hit["position"]
		_update_trail(from, hit_pos)
		if collider is StaticBody2D:
			# Explosive barrels are solid decor: a bullet can damage
			# them (GAP-64). The host decides; other peers just spark.
			var game_b = get_tree().get_first_node_in_group("game")
			if game_b != null and game_b.try_barrel_hit(hit_pos, damage, owner_id):
				_despawn()
				return
			_impact(hit_pos)
			return
		if collider is CharacterBody2D and collider.is_in_group("players"):
			var p = collider
			if p.peer_id == owner_id:
				# Ray started inside/behind the owner (muzzle overlap): keep flying.
				position = to
				_update_trail(from, to)
			elif p.alive:
				_hit_player(p, hit_pos)
			else:
				position = to
				_update_trail(from, to)
			return
		_impact(hit_pos)
		return
	position = to
	_update_trail(from, to)
	_travelled += step.length()
	_life -= delta
	if _life <= 0.0 or _travelled >= range_px:
		_despawn()


func _update_trail(from: Vector2, to: Vector2) -> void:
	if _trail == null:
		return
	# QA-056: tail 21 px behind the tip (was 26) — 80%, matching the
	# smaller bullet so the trail still ends at the bullet's tail.
	# QA-075: the length is per-weapon now (_trail_len: pistol 21,
	# sniper 48); the pistol value is unchanged, so the fire test's
	# bullet-size numbers still hold.
	_trail.set_point_position(0, to_local(from - direction * _trail_len))
	_trail.set_point_position(1, to_local(to))


# QA-075: the swept collision, centre ray first, graze rays second.
# The centre ray is the QA-055 ray exactly (mask 3: world + players,
# hit_from_inside so a muzzle inside geometry impacts at once). Only
# when it misses do the two offset rays run — a graze can only ADD
# a hit the centre ray missed, never take one away, so every
# existing bullet test (inside-geometry, single bullet, 7 pellets,
# rifle straight, repl-sim bullet track) reads the same path.
func _sweep_hit(from: Vector2, to: Vector2) -> Dictionary:
	var space := get_world_2d().direct_space_state
	var query := PhysicsRayQueryParameters2D.create(from, to, 3)
	query.hit_from_inside = true
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		return hit
	var step := to - from
	if step.length() < 0.5:
		return hit
	var perp := step.normalized().orthogonal() * 2.5
	var best := hit
	var best_d := INF
	for off in [perp, -perp]:
		var q2 := PhysicsRayQueryParameters2D.create(from + off, to + off, 3)
		q2.hit_from_inside = true
		var h2: Dictionary = space.intersect_ray(q2)
		if not h2.is_empty():
			var d2 := (h2["position"] as Vector2).distance_to(from)
			if d2 < best_d:
				best = h2
				best_d = d2
	return best


func _impact(hit_pos: Vector2) -> void:
	_dead = true
	var game = get_tree().get_first_node_in_group("game")
	if game != null:
		game.spawn_impact_fx(hit_pos)
		if explosive:
			game.request_explosion(hit_pos, blast_radius, damage, owner_id)
	_despawn()


func _hit_player(p: Node, hit_pos: Vector2) -> void:
	_dead = true
	var game = get_tree().get_first_node_in_group("game")
	if game != null:
		game.spawn_impact_fx(hit_pos)
		if explosive:
			game.request_explosion(hit_pos, blast_radius, damage, owner_id, kind)
			# Phase 4: a rocket that hits a player directly counts as
			# a hit shot (splash damage is confirmed per victim by
			# request_explosion, which also posts the kill feed).
			if multiplayer.is_server():
				var shooter_e = game.players_node.get_node_or_null(str(owner_id))
				if shooter_e != null:
					shooter_e.record_hit(shot_no)
		elif multiplayer.is_server():
			# Host-authoritative damage (v2.4): only the server's
			# simulation deals damage. Friendly fire: in Team
			# Deathmatch with friendly fire off, teammates are immune.
			var shooter = game.players_node.get_node_or_null(str(owner_id))
			if shooter != null and int(game.game_mode) == 1 and not GameData.friendly_fire:
				if int(shooter.team) == int(p.team) and int(shooter.team) != -1:
					_despawn()
					return
			# Hit regions + distance falloff (GAP-25/42, spec §17.3):
			# head 1.5x / torso 1.0x / legs 0.75x, damage fading to
			# 0.7x at max range. Knockback per weapon (GAP-46).
			var shooter2 = game.players_node.get_node_or_null(str(owner_id))
			var dist := 0.0
			if shooter2 != null:
				dist = shooter2.global_position.distance_to(hit_pos)
			var region: String = p.hit_region(hit_pos, p.global_position)
			var final_dmg: int = p.calculate_damage(damage, region, dist, kind)
			var kb: float = float(WeaponData.get_weapon(kind).get("knockback", 0.0))
			var kb_dir := Vector2.ZERO
			if velocity.length() > 0.01:
				kb_dir = velocity.normalized()
			var event_id: int = game.next_damage_event_id()
			# The kill is credited here, by the host, when its own hit
			# is lethal (victim's replicated health minus this damage).
			# The victim's peer never awards kills any more.
			# QA-069: credit ONLY if the host's copy still shows the
			# victim alive and unprotected. The host predicts
			# lethality from replicated health, but the victim's
			# _apply_damage can still refuse the hit (already dead,
			# spawn protection — its timer is now synced in the
			# snapshots, QA-068 "prot"), and a credit for a refused
			# hit is a phantom kill: the shooter gains a kill and
			# the feed announces a death that never happened. The
			# QA-031 lock still covers the same-moment double-hit
			# case; this guard covers the stale-copy case.
			var lethal: bool = int(p.health) - final_dmg <= 0 and p.alive and p._spawn_protect_timer <= 0.0
			if p.get_multiplayer_authority() == multiplayer.get_unique_id():
				p.take_hit(final_dmg, owner_id, kb_dir, kb, event_id)
			elif multiplayer.get_peers().has(p.get_multiplayer_authority()):
				# The victim may have disconnected mid-flight: an
				# RPC to a gone peer only logs an error, so skip it.
				p.rpc_id(p.get_multiplayer_authority(), "take_hit", final_dmg, owner_id, kb_dir, kb, event_id)
			if lethal:
				# QA-031 (T-56): one credit per victim per lock window —
				# a second shooter landing a lethal hit in the same
				# moment gets nothing (no kill, no second feed line).
				game.try_credit_kill(owner_id, p.peer_id, kind)
			# Phase 4: accuracy + hitmarker for the shooter, kill
			# feed for everyone (suicides included — the feed shows
			# them as self-kills, the credit above stays excluded).
			if shooter != null and owner_id != p.peer_id:
				shooter.record_hit(shot_no)
				if shooter.get_multiplayer_authority() == multiplayer.get_unique_id():
					shooter.hit_confirm(final_dmg, hit_pos, lethal)
				elif multiplayer.get_peers().has(shooter.get_multiplayer_authority()):
					shooter.rpc_id(shooter.get_multiplayer_authority(), "hit_confirm", final_dmg, hit_pos, lethal)
	_despawn()
