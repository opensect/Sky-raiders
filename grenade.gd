extends CharacterBody2D

# Throwable grenade: arcs with gravity, bounces off platforms, explodes
# after a 2-second fuse. Area damage + knockback, handled by the game.

const GRAVITY := 1400.0
const FUSE := 2.0
const BLAST_RADIUS := 170.0
const BLAST_DAMAGE := 55
const MAX_FALL := 950.0 # terminal velocity (GAP-27)
const DRAG := 0.15 # air drag (GAP-32, spec §13: Fd = -k*v)
const RESTITUTION := 0.45 # bounce: v_n' = -e*v_n (spec §13)
const REST_SPEED := 40.0 # below this, the grenade rests (GAP-33)

var throw_dir: Vector2 = Vector2.RIGHT
var thrower_vel: Vector2 = Vector2.ZERO # QA-091: thrower's velocity at throw time (GRENADE_SPEC §2)
var owner_id: int = 0

var _fuse: float = FUSE
var _visual: Polygon2D
var _blink_t: float = 0.0
var _resting: bool = false
var bounced: bool = false # set on the first real bounce (physics-test reads this)


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	# QA-091 (v3.7, GRENADE_SPEC §2): ~40% of the thrower's velocity
	# is inherited, so jetpack / running throws feel natural. The
	# base throw (620 px/s + -260 up) is unchanged.
	velocity = throw_dir * 620.0 + Vector2(0, -260.0) + thrower_vel * 0.4
	# Collision shape: without this the grenade falls through the world.
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 9.0
	shape.shape = circle
	add_child(shape)
	_visual = Polygon2D.new()
	_visual.polygon = PackedVector2Array([
		Vector2(-8, -8), Vector2(8, -8), Vector2(8, 8), Vector2(-8, 8),
	])
	_visual.color = Color(0.2, 0.6, 0.25)
	add_child(_visual)
	var pin := Polygon2D.new()
	pin.polygon = PackedVector2Array([
		Vector2(-2, -14), Vector2(2, -14), Vector2(2, -8), Vector2(-2, -8),
	])
	pin.color = Color(0.8, 0.8, 0.85)
	add_child(pin)


func _physics_process(delta: float) -> void:
	# Bounce uses the PRE-slide velocity (GAP-11): move_and_slide()
	# zeroes vy on floor contact before the bounce runs, so the old
	# code read vy ~= 0 and the grenade never bounced.
	var vy_before := velocity.y
	var vx_before := velocity.x
	velocity.y += GRAVITY * delta
	velocity *= exp(-DRAG * delta) # air drag (GAP-32)
	if velocity.y > MAX_FALL:
		velocity.y = MAX_FALL
	move_and_slide()
	if _resting:
		velocity = Vector2.ZERO
	elif is_on_floor():
		if vy_before > 120.0:
			velocity.y = -vy_before * RESTITUTION
			bounced = true
			velocity.x *= 0.8
			if velocity.length() < REST_SPEED:
				_resting = true
				velocity = Vector2.ZERO
		else:
			# Rolling friction, frame-rate independent (was vx *= 0.7
			# EVERY frame, which stopped a rolling grenade in ~0.1 s).
			velocity.x *= exp(-4.0 * delta)
			if velocity.length() < REST_SPEED:
				_resting = true
				velocity = Vector2.ZERO
	elif is_on_wall():
		# Wall bounce only when the pre-slide vx was toward the wall.
		if signf(vx_before) != signf(velocity.x) or absf(velocity.x) < absf(vx_before) * 0.5:
			velocity.x = -vx_before * 0.5
	_fuse -= delta
	_blink_t += delta
	_visual.color = Color(1.0, 0.25, 0.2) if int(_blink_t * 8.0) % 2 == 0 else Color(0.2, 0.6, 0.25)
	if _fuse <= 0.0:
		_explode()


func _explode() -> void:
	var game = get_tree().get_first_node_in_group("game")
	if game != null:
		game.request_explosion(global_position, BLAST_RADIUS, BLAST_DAMAGE, owner_id, -2)
	queue_free()
