extends CharacterBody2D

# Throwable grenade: arcs with gravity, bounces off platforms, explodes
# after a 2-second fuse. Area damage + knockback, handled by the game.

const GRAVITY := 1400.0
const FUSE := 2.0
const BLAST_RADIUS := 170.0
const BLAST_DAMAGE := 55

var throw_dir: Vector2 = Vector2.RIGHT
var owner_id: int = 0

var _fuse: float = FUSE
var _visual: Polygon2D
var _blink_t: float = 0.0


func _ready() -> void:
	collision_layer = 0
	collision_mask = 1
	velocity = throw_dir * 620.0 + Vector2(0, -260.0)
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
	velocity.y += GRAVITY * delta
	move_and_slide()
	if is_on_floor():
		velocity.y = -velocity.y * 0.45
		velocity.x *= 0.7
	if is_on_wall():
		velocity.x = -velocity.x * 0.5
	_fuse -= delta
	_blink_t += delta
	_visual.color = Color(1.0, 0.25, 0.2) if int(_blink_t * 8.0) % 2 == 0 else Color(0.2, 0.6, 0.25)
	if _fuse <= 0.0:
		_explode()


func _explode() -> void:
	var game = get_tree().get_first_node_in_group("game")
	if game != null:
		game.request_explosion(global_position, BLAST_RADIUS, BLAST_DAMAGE, owner_id)
	queue_free()
