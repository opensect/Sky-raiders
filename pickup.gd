extends Area2D

# Weapon / health / grenade pickup. Only the server (host) hands it out,
# so two players can't grab it at once.

# kind: 1 = SMG, 2 = Shotgun, 3 = Sniper, 4 = Rocket Launcher,
#       5 = Health (+50), 6 = Grenades (+2)
var kind: int = 1

var _life: float = 20.0
var _bob_t: float = 0.0
var _base_y: float = 0.0

const KIND_LABEL := {1: "SMG", 2: "BOOM", 3: "SNIPER", 4: "ROCKET", 5: "+", 6: "G"}
const KIND_COLOR := {
	1: Color(1.0, 0.6, 0.2),
	2: Color(1.0, 0.5, 0.3),
	3: Color(0.5, 0.9, 1.0),
	4: Color(1.0, 0.3, 0.2),
	5: Color(0.3, 0.9, 0.4),
	6: Color(0.2, 0.6, 0.25),
}


func _ready() -> void:
	collision_layer = 16
	collision_mask = 2
	monitoring = true
	monitorable = false
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 22.0
	shape.shape = circle
	add_child(shape)
	var box := Polygon2D.new()
	box.polygon = PackedVector2Array([
		Vector2(-20, -14), Vector2(20, -14), Vector2(20, 14), Vector2(-20, 14),
	])
	box.color = KIND_COLOR.get(kind, Color(0.5, 0.9, 1.0))
	add_child(box)
	var label := Label.new()
	label.text = KIND_LABEL.get(kind, "?")
	label.position = Vector2(-20, -12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size = Vector2(40, 24)
	label.add_theme_font_size_override("font_size", 15)
	add_child(label)
	_base_y = position.y
	body_entered.connect(_on_body_entered)


func _process(delta: float) -> void:
	_bob_t += delta
	position.y = _base_y + sin(_bob_t * 3.0) * 6.0
	if multiplayer.is_server():
		_life -= delta
		if _life <= 0.0:
			rpc("despawn")


func _on_body_entered(body: Node2D) -> void:
	if not multiplayer.is_server():
		return
	if body.is_in_group("players"):
		var p = body
		if p.alive:
			if body.get_multiplayer_authority() == multiplayer.get_unique_id():
				body.give_pickup(kind)
			else:
				body.rpc_id(body.get_multiplayer_authority(), "give_pickup", kind)
			rpc("despawn")


@rpc("any_peer", "call_local")
func despawn() -> void:
	queue_free()
